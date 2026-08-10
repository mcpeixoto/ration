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
