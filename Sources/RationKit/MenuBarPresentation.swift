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

    /// True when the item carries a colour a template image would strip.
    ///
    /// A healthy weekly bar is drawn in `primary`, so it can stay a template
    /// and follow the menu bar into night. Amber, red, or a severity tint
    /// cannot, and must be baked as a bitmap.
    public var hasChromaticColor: Bool {
        if tint != nil { return true }
        if let bar, bar.severity != .normal { return true }
        return false
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
    ///   - provider: The tool this item is for. Names the signed-out tooltip
    ///     and, when `useIdentitySymbol` is set, the glyph so two accounts in
    ///     the tray can be told apart.
    ///   - useIdentitySymbol: Use the provider's own symbol instead of the
    ///     gauge needle. The tray turns this on once more than one account is
    ///     showing, because three identical gauges would be unreadable.
    public static func make(
        state: UsageState,
        mode: MenuBarDisplayMode,
        useSeverityColor: Bool,
        showWeeklyBar: Bool = false,
        now: Date = Date(),
        provider: Provider? = nil,
        useIdentitySymbol: Bool = false
    ) -> MenuBarPresentation {

        let tool = provider?.toolName ?? "the tool"
        let name = provider?.displayName

        // Signed out: never show a number we cannot stand behind.
        if state.status == .signedOut {
            return MenuBarPresentation(
                title: nil,
                symbolName: "person.crop.circle.badge.exclamationmark",
                tint: useSeverityColor ? .warning : nil,
                accessibilityLabel: name.map { "Ration: \($0) signed out" } ?? "Ration: signed out",
                tooltip: "Sign in with \(tool) to see your usage."
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

        let glyph =
            (useIdentitySymbol ? provider?.symbolName : nil)
            ?? symbolName(forPercent: limit.percent)
        let spoken =
            name.map { "\($0), \(limit.displayName): \(Self.percentText(limit.percent)) used" }
            ?? "\(limit.displayName): \(Self.percentText(limit.percent)) used"

        return MenuBarPresentation(
            title: title,
            symbolName: glyph,
            tint: useSeverityColor && severity != .normal ? severity : nil,
            accessibilityLabel: spoken,
            tooltip: tooltip(
                for: snapshot, state: state, now: now, providerName: name),
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

    /// Every account has been turned off in Settings → Accounts.
    ///
    /// Deliberately not `setupRequired`: "you hid everything" and "no supported
    /// tool was found" are different sentences pointing at different fixes.
    public static let allHidden = MenuBarPresentation(
        title: nil,
        symbolName: "eye.slash",
        tint: nil,
        accessibilityLabel: "Ration: all accounts hidden",
        tooltip: "Every account is hidden. Turn one on in Settings → Accounts."
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

    static func tooltip(
        for snapshot: UsageSnapshot,
        state: UsageState,
        now: Date,
        providerName: String? = nil
    ) -> String {
        var lines = snapshot.limits.map { limit -> String in
            if let resets = limit.resetsAt {
                return
                    "\(limit.displayName): \(percentText(limit.percent)) · resets \(RelativeTime.short(until: resets, from: now))"
            }
            return "\(limit.displayName): \(percentText(limit.percent))"
        }

        if let providerName {
            lines.insert(providerName, at: 0)
        }
        if state.isStale {
            lines.append("Last update failed — showing older numbers.")
        }
        return lines.joined(separator: "\n")
    }
}

/// The whole menu bar item: one presentation per account that is on.
///
/// A single account keeps the original gauge-and-number look. Two or more sit
/// side by side, each named by its own symbol so they can be told apart. Empty
/// is either `setupRequired` or `allHidden`, which are different sentences.
public struct MenuBarStrip: Sendable, Equatable {

    public let items: [MenuBarPresentation]

    public init(items: [MenuBarPresentation]) {
        self.items = items
    }

    public static let setupRequired = MenuBarStrip(items: [.setupRequired])
    public static let allHidden = MenuBarStrip(items: [.allHidden])

    public var accessibilityLabel: String {
        items.map(\.accessibilityLabel).joined(separator: ", ")
    }

    /// True when any account needs a colour the menu bar cannot template.
    public var hasChromaticColor: Bool {
        items.contains { $0.hasChromaticColor }
    }

    /// One account that is on, in the order the caller listed them.
    ///
    /// A provider whose first read would raise a permission dialog is skipped
    /// until onboarding is done, so the tray can still show Codex or Cursor
    /// while Claude is waiting on the keychain prompt.
    public static func make(
        accounts: [(provider: Provider, state: UsageState, promptsForPermission: Bool)],
        mode: MenuBarDisplayMode,
        useSeverityColor: Bool,
        showWeeklyBar: Bool,
        hasCompletedOnboarding: Bool,
        isEverythingHidden: Bool,
        now: Date = Date()
    ) -> MenuBarStrip {
        let shown = accounts.filter { hasCompletedOnboarding || !$0.promptsForPermission }
        guard !shown.isEmpty else {
            return isEverythingHidden ? .allHidden : .setupRequired
        }

        let named = shown.count > 1
        let items = shown.map { account in
            MenuBarPresentation.make(
                state: account.state,
                mode: mode,
                useSeverityColor: useSeverityColor,
                showWeeklyBar: showWeeklyBar,
                now: now,
                provider: account.provider,
                useIdentitySymbol: named)
        }
        return MenuBarStrip(items: items)
    }
}

/// Maps a click on the tray strip to an item index, so opening on Cursor's
/// gauge can open Cursor's page.
public enum MenuBarHitTesting {

    /// Horizontal space one tray item occupies, matching `MenuBarLabel`.
    public static func itemWidth(_ item: MenuBarPresentation) -> Double {
        var width: Double = 17
        if let title = item.title {
            width += 4 + Double(title.count) * 8
        }
        if item.bar != nil { width += 9 }
        return width
    }

    public static func itemIndex(
        clickX: Double,
        barWidth: Double,
        itemWidths: [Double],
        spacing: Double = 8
    ) -> Int? {
        guard barWidth > 0, !itemWidths.isEmpty else { return nil }
        let content =
            itemWidths.reduce(0, +) + spacing * Double(max(itemWidths.count - 1, 0))
        let scale = barWidth / max(content, 1)
        var start: Double = 0
        for (i, width) in itemWidths.enumerated() {
            let end = start + width * scale
            if clickX < end || i == itemWidths.count - 1 { return i }
            start = end + spacing * scale
        }
        return itemWidths.count - 1
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
