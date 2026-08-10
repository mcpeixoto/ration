import Foundation
import Testing

@testable import RationKit

/// Thread-safe call counter. `FakeSource` is a struct copied into the poller
/// it backs, so counting `forget()` calls needs a reference type the test and
/// the poller's copy both point at.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// A source that reports whatever availability the test wants and never
/// succeeds at fetching, so no test depends on network or disk.
private struct FakeSource: UsageSource {

    let provider: Provider
    var reported: ProviderAvailability = .ready
    let forgetCount = Counter()

    func availability() -> ProviderAvailability { reported }

    func fetchUsage() async throws -> UsageSnapshot {
        throw LimitsError.unavailable(reason: "test double")
    }

    func forget() {
        forgetCount.increment()
    }
}

@MainActor
private func makeRegistry(
    disabled: Set<String> = [],
    primary: Provider = .claude
) -> ProviderRegistry {
    ProviderRegistry(
        entries: [
            ProviderRegistry.Entry(
                provider: .claude,
                poller: UsagePoller(source: FakeSource(provider: .claude)),
                history: nil),
            ProviderRegistry.Entry(
                provider: .codex,
                poller: UsagePoller(source: FakeSource(provider: .codex)),
                history: nil),
        ],
        primary: primary,
        disabled: disabled)
}

/// One meterable provider and one Ration can see but cannot meter, which is
/// what any Mac with Cursor, Copilot or Gemini installed actually looks like.
@MainActor
private func makeUnmeterableRegistry(disabled: Set<String> = []) -> ProviderRegistry {
    ProviderRegistry(
        entries: [
            ProviderRegistry.Entry(
                provider: .claude,
                poller: UsagePoller(source: FakeSource(provider: .claude)),
                history: nil),
            ProviderRegistry.Entry(
                provider: .cursor,
                poller: UsagePoller(
                    source: FakeSource(
                        provider: .cursor,
                        reported: .quotaNotReadable(reason: "test double"))),
                history: nil),
        ],
        disabled: disabled)
}

@Suite("ProviderRegistry visibility")
struct ProviderRegistryVisibilityTests {

    @Test("everything is enabled by default")
    @MainActor
    func defaultsToAllEnabled() {
        let registry = makeRegistry()

        #expect(registry.disabled.isEmpty)
        #expect(registry.visible.count == 2)
        #expect(registry.isEnabled(.claude))
        #expect(registry.isEnabled(.codex))
    }

    @Test("a disabled provider leaves visible and metered")
    @MainActor
    func disabledIsHidden() {
        let registry = makeRegistry(disabled: ["codex"])

        #expect(registry.visible.map(\.id) == ["claude"])
        #expect(registry.metered.map(\.id) == ["claude"])
        #expect(!registry.isEnabled(.codex))
    }

    @Test("hiding the primary promotes the next one")
    @MainActor
    func hidingPrimaryPromotesNext() {
        let registry = makeRegistry(primary: .claude)

        registry.setEnabled(false, for: .claude)

        #expect(registry.primary == .codex)
        #expect(registry.primaryEntry?.provider == .codex)
        // The app layer persists the promotion only while this is non-nil, so
        // the legitimate promotion has to leave it filled in.
        #expect(registry.primaryEntry != nil)
    }

    @Test("hiding everything leaves no primary entry")
    @MainActor
    func hidingAllLeavesNothing() {
        let registry = makeRegistry()

        registry.setEnabled(false, for: .claude)
        registry.setEnabled(false, for: .codex)

        #expect(registry.visible.isEmpty)
        #expect(registry.primaryEntry == nil)
    }

    /// The path that once recursed without bound: the fallback resolves to a
    /// *different* provider than the one being replaced, so `didSet` re-enters
    /// — and only the second pass reaches the equality guard that stops it.
    /// Starting from `.claude` returns on the first pass and proves nothing.
    ///
    /// A regression here hangs or crashes rather than failing cleanly. That is
    /// still a caught regression.
    @Test("hiding everything terminates when the primary is not the fallback")
    @MainActor
    func hidingAllFromCodexTerminates() {
        let registry = makeRegistry(primary: .codex)

        registry.setEnabled(false, for: .claude)
        registry.setEnabled(false, for: .codex)

        #expect(registry.primaryEntry == nil)
        #expect(registry.primary == .claude)
    }

    /// A tool Ration can see but cannot meter stays listed — the switcher and
    /// the Accounts tab both keep showing it — but it can never be handed the
    /// menu bar, which has nothing but a gauge to put there.
    @Test("an unmeterable provider stays visible but never owns the menu bar")
    @MainActor
    func unmeterableNeverOwnsTheMenuBar() {
        let registry = makeUnmeterableRegistry(disabled: ["claude"])

        #expect(registry.visible.map(\.id) == ["cursor"])
        #expect(registry.metered.isEmpty)
        #expect(registry.primaryEntry == nil)
    }
}

@Suite("ProviderRegistry all-hidden")
struct ProviderRegistryAllHiddenTests {

    @Test("nothing installed is setup required, not everything hidden")
    @MainActor
    func nothingInstalledIsNotHidden() {
        let registry = ProviderRegistry(entries: [
            ProviderRegistry.Entry(
                provider: .claude,
                poller: UsagePoller(
                    source: FakeSource(provider: .claude, reported: .notInstalled)),
                history: nil),
            ProviderRegistry.Entry(
                provider: .codex,
                poller: UsagePoller(
                    source: FakeSource(provider: .codex, reported: .notInstalled)),
                history: nil),
        ])

        #expect(registry.primaryEntry == nil)
        #expect(!registry.isEverythingHidden)
    }

    /// The case the menu bar used to get wrong: an unmeterable tool on the
    /// machine kept `visible` non-empty, so turning every account off looked
    /// like nothing had happened.
    @Test("every meterable account hidden is hidden, unmeterable tools notwithstanding")
    @MainActor
    func allMeterableHiddenIsHidden() {
        let registry = makeUnmeterableRegistry(disabled: ["claude"])

        #expect(registry.primaryEntry == nil)
        #expect(registry.isEverythingHidden)
    }

    @Test("one metered account left is neither")
    @MainActor
    func oneMeteredIsNeither() {
        let registry = makeUnmeterableRegistry()

        #expect(registry.primaryEntry?.provider == .claude)
        #expect(!registry.isEverythingHidden)
    }

    @Test("re-enabling brings a provider back")
    @MainActor
    func enablingRestores() {
        let registry = makeRegistry(disabled: ["codex"])

        registry.setEnabled(true, for: .codex)

        #expect(registry.disabled.isEmpty)
        #expect(registry.visible.count == 2)
    }

    @Test("an uninstalled provider is not visible")
    @MainActor
    func notInstalledIsNotVisible() {
        let registry = ProviderRegistry(entries: [
            ProviderRegistry.Entry(
                provider: .claude,
                poller: UsagePoller(source: FakeSource(provider: .claude)),
                history: nil),
            ProviderRegistry.Entry(
                provider: .codex,
                poller: UsagePoller(
                    source: FakeSource(provider: .codex, reported: .notInstalled)),
                history: nil),
        ])

        #expect(registry.visible.map(\.id) == ["claude"])
    }
}

@Suite("ProviderRegistry polling")
struct ProviderRegistryPollingTests {

    @Test("start does not start a disabled provider")
    @MainActor
    func startSkipsDisabled() {
        let registry = makeRegistry(disabled: ["codex"])

        registry.start()

        #expect(registry.entry(for: .claude)?.poller.isRunning == true)
        #expect(registry.entry(for: .codex)?.poller.isRunning == false)
    }

    @Test("disabling a running provider stops it immediately")
    @MainActor
    func disablingStopsPolling() {
        let registry = makeRegistry()
        registry.start()
        #expect(registry.entry(for: .codex)?.poller.isRunning == true)

        registry.setEnabled(false, for: .codex)

        #expect(registry.entry(for: .codex)?.poller.isRunning == false)
    }

    @Test("disabling calls forget on the source; a plain suspend does not")
    @MainActor
    func disablingCallsForgetSuspendDoesNot() {
        let codexSource = FakeSource(provider: .codex)
        let registry = ProviderRegistry(entries: [
            ProviderRegistry.Entry(
                provider: .claude,
                poller: UsagePoller(source: FakeSource(provider: .claude)),
                history: nil),
            ProviderRegistry.Entry(
                provider: .codex,
                poller: UsagePoller(source: codexSource),
                history: nil),
        ])
        registry.start()

        registry.suspend()
        #expect(codexSource.forgetCount.count == 0)

        registry.resume()
        registry.setEnabled(false, for: .codex)

        #expect(codexSource.forgetCount.count == 1)
    }

    @Test("enabling a provider starts it without waiting for a relaunch")
    @MainActor
    func enablingStartsPolling() {
        let registry = makeRegistry(disabled: ["codex"])
        registry.start()

        registry.setEnabled(true, for: .codex)

        #expect(registry.entry(for: .codex)?.poller.isRunning == true)
    }

    @Test("enabling a provider without a readable quota does not start it")
    @MainActor
    func enablingWithoutQuotaDoesNotStart() {
        let registry = ProviderRegistry(
            entries: [
                ProviderRegistry.Entry(
                    provider: .claude,
                    poller: UsagePoller(source: FakeSource(provider: .claude)),
                    history: nil),
                ProviderRegistry.Entry(
                    provider: .codex,
                    poller: UsagePoller(
                        source: FakeSource(
                            provider: .codex,
                            reported: .quotaNotReadable(reason: "test double"))),
                    history: nil),
            ],
            disabled: ["codex"])
        registry.start()

        registry.setEnabled(true, for: .codex)

        #expect(registry.entry(for: .codex)?.poller.isRunning == false)
    }

    /// Without the checkpoint, `refresh()` takes its first-scan branch and
    /// re-reads every transcript from byte 0 — minutes of scanning, and a
    /// progress bar, to arrive at numbers already sitting on disk.
    @Test("enabling a provider loads its checkpoint before scanning")
    @MainActor
    func enablingLoadsTheCheckpoint() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ration-enable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        // `days` is keyed by `Date`, so it encodes as a flat array rather than
        // an object. Empty is enough: what is being asserted is that the file
        // was read at all.
        let saved = """
            {"version":2,"history":{"days":[]},"files":{"/x.jsonl":{"offset":999}},\
            "savedAt":\(Date().timeIntervalSinceReferenceDate)}
            """
        try Data(saved.utf8).write(to: support.appending(path: "history-codex.json"))

        let history = TranscriptStore(
            provider: .codex, format: CodexRolloutFormat(),
            root: URL(fileURLWithPath: "/nonexistent"), supportDirectory: support)
        let registry = ProviderRegistry(
            entries: [
                ProviderRegistry.Entry(
                    provider: .claude,
                    poller: UsagePoller(source: FakeSource(provider: .claude)),
                    history: nil),
                ProviderRegistry.Entry(
                    provider: .codex,
                    poller: UsagePoller(source: FakeSource(provider: .codex)),
                    history: history),
            ],
            disabled: ["codex"])

        // Disabled at launch, so `start()` skips it entirely.
        registry.start()
        #expect(history.lastScan == nil)

        registry.setEnabled(true, for: .codex)

        // `lastScan` can only have come from the checkpoint: the root does not
        // exist, so no scan can ever set it.
        #expect(history.lastScan != nil)
    }

    @Test("setting the state it is already in changes nothing")
    @MainActor
    func settingSameStateIsANoOp() {
        let registry = makeRegistry()
        registry.start()

        registry.setEnabled(true, for: .codex)

        #expect(registry.disabled.isEmpty)
        #expect(registry.entry(for: .codex)?.poller.isRunning == true)
    }
}
