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

    /// Which provider owns the menu bar. Persisted by the app layer.
    public var primary: Provider {
        didSet {
            guard !visible.contains(where: { $0.provider == primary }) else { return }
            // Selected a provider that has since vanished — fall back rather
            // than showing an empty menu bar item.
            primary = visible.first?.provider ?? .claude
        }
    }

    public init(entries: [Entry], primary: Provider = .claude) {
        self.entries = entries
        self.primary =
            entries.contains { $0.provider == primary }
            ? primary
            : entries.first?.provider ?? .claude
    }

    /// The providers worth putting in front of the user: installed, whatever
    /// else is true of them. A tool you do not use is not an error to report.
    public var visible: [Entry] {
        entries.filter { $0.availability.isVisible }
    }

    /// Those that can actually show a gauge and a history.
    public var metered: [Entry] {
        visible.filter { $0.availability.hasQuota }
    }

    public func entry(for provider: Provider) -> Entry? {
        entries.first { $0.provider == provider }
    }

    public var primaryEntry: Entry? {
        entry(for: primary) ?? visible.first
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
    public static func standard(schedule: PollSchedule = PollSchedule()) -> ProviderRegistry {
        ProviderRegistry(entries: [
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
                poller: UsagePoller(source: DetectOnlyUsageSource.copilot(), schedule: schedule),
                history: nil),
            Entry(
                provider: .gemini,
                poller: UsagePoller(source: DetectOnlyUsageSource.gemini(), schedule: schedule),
                history: nil),
        ])
    }
}
