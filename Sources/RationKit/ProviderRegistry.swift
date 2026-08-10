import Foundation
import Observation

/// Every provider Ration knows about, and the live objects behind each one.
///
/// Replaces the one-poller-one-store arrangement that only ever described
/// Claude. The panel reads whichever entry the user has selected; the menu bar
/// reads `primary`.
@MainActor
@Observable
public final class ProviderRegistry {

    /// Main-actor because it reaches into `UsagePoller`, which is.
    @MainActor
    public struct Entry: Identifiable {
        public let provider: Provider
        public let poller: UsagePoller
        /// Absent for providers whose sessions Ration cannot read.
        public let history: TranscriptStore?

        public init(provider: Provider, poller: UsagePoller, history: TranscriptStore?) {
            self.provider = provider
            self.poller = poller
            self.history = history
        }

        // `provider` is an immutable Sendable value, so identity is readable
        // from anywhere even though the rest of the entry is main-actor bound.
        public nonisolated var id: String { provider.id }
        public var availability: ProviderAvailability { poller.availability }
    }

    public private(set) var entries: [Entry]

    /// Providers the user has turned off in Settings → Accounts.
    ///
    /// The *disabled* set is stored rather than the enabled one so that an
    /// empty set is the correct fresh-install state, and a provider added in a
    /// later release arrives switched on instead of silently hidden.
    public private(set) var disabled: Set<Provider.ID>

    /// Which provider owns the menu bar. Persisted by the app layer.
    ///
    /// Resolved against `metered`, not `visible`: the menu bar can only show a
    /// gauge, so promoting a tool Ration cannot meter would leave it stuck on
    /// "Loading usage…" forever.
    public var primary: Provider {
        didSet {
            guard !metered.contains(where: { $0.provider == primary }) else { return }
            // Selected a provider that has since vanished — fall back rather
            // than showing an empty menu bar item.
            let fallback = metered.first?.provider ?? .claude
            // `@Observable` re-invokes didSet on a self-reentrant write, even
            // one that assigns the same value; when nothing is visible the
            // fallback keeps resolving to the same provider, so bail once it
            // stops changing anything instead of recursing forever.
            guard fallback != primary else { return }
            primary = fallback
        }
    }

    public init(
        entries: [Entry],
        primary: Provider = .claude,
        disabled: Set<Provider.ID> = []
    ) {
        self.entries = entries
        self.disabled = disabled
        self.primary =
            entries.contains { $0.provider == primary }
            ? primary
            : entries.first?.provider ?? .claude
    }

    /// The providers worth putting in front of the user: installed, not turned
    /// off, whatever else is true of them. A tool you do not use is not an
    /// error to report.
    public var visible: [Entry] {
        entries.filter { $0.availability.isVisible && !disabled.contains($0.id) }
    }

    /// Those that can actually show a gauge and a history.
    public var metered: [Entry] {
        visible.filter { $0.availability.hasQuota }
    }

    public func entry(for provider: Provider) -> Entry? {
        entries.first { $0.provider == provider }
    }

    public func isEnabled(_ provider: Provider) -> Bool {
        !disabled.contains(provider.id)
    }

    /// Turns a provider on or off.
    ///
    /// Takes effect now rather than at next launch: a poller just disabled is
    /// stopped and told to forget what it cached, and one just enabled starts
    /// polling. Hiding the provider that owns the menu bar promotes the next
    /// one, which `primary`'s own fallback handles.
    public func setEnabled(_ enabled: Bool, for provider: Provider) {
        guard enabled != isEnabled(provider) else { return }

        if enabled {
            disabled.remove(provider.id)
            if let entry = entry(for: provider), entry.availability.hasQuota {
                entry.poller.start()
                // Same pair as `start()`, and in the same order: a provider
                // disabled at launch never loaded its checkpoint, so refreshing
                // without it would re-read every transcript from byte 0 —
                // minutes of scanning to arrive at numbers already on disk.
                entry.history?.loadCheckpoint()
                entry.history?.refresh()
            }
        } else {
            disabled.insert(provider.id)
            entry(for: provider)?.poller.disable()
        }

        // Re-run the fallback: the menu bar's provider may have just been
        // hidden, or the only visible one may have just come back.
        let current = primary
        primary = current
    }

    /// Resolved against `metered`, not `entries`: a provider the user turned
    /// off must not come back through the menu bar's own lookup, and one whose
    /// quota Ration cannot read has no number to put there in the first place.
    public var primaryEntry: Entry? {
        metered.first { $0.provider == primary } ?? metered.first
    }

    /// Whether the user has turned off every account Ration could meter, as
    /// opposed to there being none installed to begin with.
    ///
    /// Two different dead ends needing two different sentences: the first is
    /// fixed in Settings → Accounts, the second by installing a tool. Lives
    /// here rather than in the app layer so it can be tested without launching
    /// one — and because the panel and the Accounts tab ask the same question.
    public var isEverythingHidden: Bool {
        metered.isEmpty && entries.contains { $0.availability.hasQuota }
    }

    // MARK: Lifecycle
    //
    // Fanned out rather than exposed one at a time: forgetting to suspend one
    // provider on sleep is exactly the kind of bug that only shows up as a
    // flat battery.

    /// - Parameter allowingPrompts: whether sources that trigger a system
    ///   permission dialog may run. False until the user has been shown what
    ///   the prompt is for; everything else starts regardless, because reading
    ///   the user's own files asks nobody for anything.
    public func start(allowingPrompts: Bool = true) {
        for entry in metered where allowingPrompts || !entry.poller.promptsForPermission {
            entry.poller.start()
        }
        for entry in metered {
            entry.history?.loadCheckpoint()
            entry.history?.refresh()
        }
    }

    public func suspend() {
        for entry in entries { entry.poller.suspend() }
    }

    public func resume() {
        for entry in metered { entry.poller.resume() }
        for entry in metered { entry.history?.refresh() }
    }

    public func setMenuOpen(_ open: Bool) {
        for entry in metered { entry.poller.setMenuOpen(open) }
    }

    public func updateSchedule(_ schedule: PollSchedule) {
        for entry in entries { entry.poller.updateSchedule(schedule) }
    }

    // MARK: Assembly

    /// The full set Ration ships with.
    ///
    /// Claude is a network read; Codex is read from its own session files;
    /// the rest are listed honestly and metered by nobody.
    public static func standard(
        schedule: PollSchedule = PollSchedule(),
        disabled: Set<Provider.ID> = []
    ) -> ProviderRegistry {
        ProviderRegistry(
            entries: [
                Entry(
                    provider: .claude,
                    poller: UsagePoller(source: AnthropicUsageSource(), schedule: schedule),
                    history: TranscriptStore(provider: .claude, format: ClaudeTranscriptFormat())),
                Entry(
                    provider: .codex,
                    poller: UsagePoller(source: CodexUsageSource(), schedule: schedule),
                    history: TranscriptStore(provider: .codex, format: CodexRolloutFormat())),
                Entry(
                    provider: .cursor,
                    poller: UsagePoller(source: DetectOnlyUsageSource.cursor(), schedule: schedule),
                    history: nil),
                Entry(
                    provider: .copilot,
                    poller: UsagePoller(
                        source: DetectOnlyUsageSource.copilot(), schedule: schedule),
                    history: nil),
                Entry(
                    provider: .gemini,
                    poller: UsagePoller(source: DetectOnlyUsageSource.gemini(), schedule: schedule),
                    history: nil),
            ],
            disabled: disabled)
    }
}
