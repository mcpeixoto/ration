import Foundation

/// What the menu bar item shows without being clicked.
public enum MenuBarDisplayMode: String, Sendable, Codable, CaseIterable, Identifiable {
    /// The rolling session window — the limit most likely to interrupt you.
    case sessionPercent
    /// The rolling week across all models.
    case weeklyPercent
    /// Whichever limit is closest to being hit.
    case highestPercent
    /// Just the gauge, no number.
    case iconOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sessionPercent: "Session"
        case .weeklyPercent: "Weekly"
        case .highestPercent: "Highest"
        case .iconOnly: "Icon only"
        }
    }

    public var explanation: String {
        switch self {
        case .sessionPercent: "Percentage of the current 5-hour session used."
        case .weeklyPercent: "Percentage of this week's allowance used."
        case .highestPercent: "Whichever limit is closest to being reached."
        case .iconOnly: "Show only the gauge, with no percentage."
        }
    }
}

/// Everything the menu bar item needs to draw itself.
///
/// Derived purely from a `UsageState`, so the exact pixels are unit-testable
/// without launching an app.
public struct MenuBarPresentation: Sendable, Equatable {

    /// The number beside the icon. `nil` renders the icon alone.
    public let title: String?
    public let symbolName: String
    /// `nil` means draw in the default menu bar colour.
    public let tint: Severity?
    /// Read aloud by VoiceOver.
    public let accessibilityLabel: String
    /// Shown on hover.
    public let tooltip: String
    /// A small bar drawn beside the icon. `nil` hides it.
    public let bar: Bar?

    /// A miniature progress bar for the menu bar.
    public struct Bar: Sendable, Equatable {
        /// 0…1 of the limit consumed.
        public let fraction: Double
        public let severity: Severity
        /// What it tracks, for the accessibility label.
        public let name: String

        public init(fraction: Double, severity: Severity, name: String) {
            self.fraction = min(max(fraction, 0), 1)
            self.severity = severity
            self.name = name
        }
    }

    public init(
        title: String?,
        symbolName: String,
        tint: Severity?,
        accessibilityLabel: String,
        tooltip: String,
        bar: Bar? = nil
    ) {
        self.title = title
        self.symbolName = symbolName
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.tooltip = tooltip
        self.bar = bar
    }
}

extension MenuBarPresentation {

    /// Builds the menu bar presentation for a given state.
    ///
    /// - Parameters:
    ///   - state: The latest poll result.
    ///   - mode: What the user chose to display.
    ///   - useSeverityColor: Whether to tint at warning and critical. Off by
    ///     default, because a coloured menu bar is a strong opinion to impose.
    ///   - now: Injected for testable relative times.
    public static func make(
        state: UsageState,
        mode: MenuBarDisplayMode,
        useSeverityColor: Bool,
        showWeeklyBar: Bool = false,
        now: Date = Date()
    ) -> MenuBarPresentation {

        // Signed out: never show a number we cannot stand behind.
        if state.status == .signedOut {
            return MenuBarPresentation(
                title: nil,
                symbolName: "person.crop.circle.badge.exclamationmark",
                tint: useSeverityColor ? .warning : nil,
                accessibilityLabel: "Ration: signed out",
                tooltip: "Sign in with Claude Code to see your usage."
            )
        }

        guard let snapshot = state.snapshot else {
            let waiting = state.status == .idle || state.status == .refreshing
            return MenuBarPresentation(
                title: nil,
                symbolName: waiting ? "circle.dotted" : "wifi.slash",
                tint: nil,
                accessibilityLabel: waiting ? "Ration: loading" : "Ration: unavailable",
                tooltip: waiting
                    ? "Loading usage…"
                    : (state.lastError?.errorDescription ?? "Usage unavailable.")
            )
        }

        let limit = select(mode: mode, from: snapshot)

        // The chosen limit may not exist on this plan (a personal account has no
        // scoped weekly limit, for instance). Fall back rather than show nothing.
        guard let limit else {
            return MenuBarPresentation(
                title: nil,
                symbolName: "gauge.with.dots.needle.0percent",
                tint: nil,
                accessibilityLabel: "Ration: no limit data",
                tooltip: "No usage limits reported for this account."
            )
        }

        let title = mode == .iconOnly ? nil : Self.percentText(limit.percent)

        // Escalate the whole item from the worst limit on the account, not
        // just the one being displayed — a calm menu bar while the weekly
        // limit is about to stop your work would be actively misleading.
        let severity =
            snapshot.limits
            .map { Severity.escalating(percent: $0.percent, reported: $0.severity) }
            .max { $0.rank < $1.rank } ?? .normal

        return MenuBarPresentation(
            title: title,
            symbolName: symbolName(forPercent: limit.percent),
            tint: useSeverityColor && severity != .normal ? severity : nil,
            accessibilityLabel: "\(limit.displayName): \(Self.percentText(limit.percent)) used",
            tooltip: tooltip(for: snapshot, state: state, now: now),
            bar: showWeeklyBar ? weeklyBar(from: snapshot) : nil
        )
    }

    /// The bar tracks the weekly allowance, which is the one that creeps up on
    /// you — the session window resets often enough to watch itself.
    static func weeklyBar(from snapshot: UsageSnapshot) -> Bar? {
        guard let limit = snapshot.weeklyLimit ?? snapshot.primaryLimit else { return nil }
        return Bar(
            fraction: limit.percent / 100,
            severity: Severity.escalating(percent: limit.percent, reported: limit.severity),
            name: limit.displayName
        )
    }

    /// Shown before the user has agreed to let Ration read the keychain.
    /// Deliberately distinct from "loading": nothing is happening, and won't
    /// until they say so.
    public static let setupRequired = MenuBarPresentation(
        title: nil,
        symbolName: "gauge.with.dots.needle.0percent",
        tint: nil,
        accessibilityLabel: "Ration: setup required",
        tooltip: "Finish setting up Ration to see your usage."
    )

    // MARK: Pieces

    public static func select(mode: MenuBarDisplayMode, from snapshot: UsageSnapshot) -> UsageLimit?
    {
        switch mode {
        case .sessionPercent: snapshot.sessionLimit ?? snapshot.primaryLimit
        case .weeklyPercent: snapshot.weeklyLimit ?? snapshot.primaryLimit
        case .highestPercent, .iconOnly: snapshot.primaryLimit
        }
    }

    /// Whole numbers only. A menu bar is not the place for decimals, and
    /// rounding down avoids claiming 100% before you are actually there.
    public static func percentText(_ percent: Double) -> String {
        let clamped = min(max(percent, 0), 100)
        return "\(Int(clamped.rounded(.down)))%"
    }

    /// Picks the gauge whose needle position matches the fill.
    static func symbolName(forPercent percent: Double) -> String {
        switch percent {
        case ..<15: "gauge.with.dots.needle.0percent"
        case ..<45: "gauge.with.dots.needle.33percent"
        case ..<60: "gauge.with.dots.needle.50percent"
        case ..<85: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }

    static func tooltip(for snapshot: UsageSnapshot, state: UsageState, now: Date) -> String {
        var lines = snapshot.limits.map { limit -> String in
            if let resets = limit.resetsAt {
                return
                    "\(limit.displayName): \(percentText(limit.percent)) · resets \(RelativeTime.short(until: resets, from: now))"
            }
            return "\(limit.displayName): \(percentText(limit.percent))"
        }

        if state.isStale {
            lines.append("Last update failed — showing older numbers.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Relative time

/// Formats "how long until this window resets".
public enum RelativeTime {

    /// `2h 39m`, `45m`, `30s`, or `now` once the window has rolled over.
    public static func short(until date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        guard seconds > 0 else { return "now" }

        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    /// `resets in 2h 39m` / `resets now`.
    public static func sentence(until date: Date, from now: Date = Date()) -> String {
        let text = short(until: date, from: now)
        return text == "now" ? "resets now" : "resets in \(text)"
    }
}
