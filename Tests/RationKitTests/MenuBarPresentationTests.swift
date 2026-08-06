import Foundation
import Testing

@testable import RationKit

// MARK: - Builders

private func limit(
    _ kind: UsageLimit.Kind,
    _ percent: Double,
    severity: Severity = .normal,
    resetsIn: TimeInterval? = nil,
    model: String? = nil
) -> UsageLimit {
    UsageLimit(
        kind: kind,
        group: kind == .session ? .session : .weekly,
        percent: percent,
        severity: severity,
        resetsAt: resetsIn.map { Date(timeIntervalSinceNow: $0) },
        scope: model.map { UsageLimit.Scope(modelDisplayName: $0) },
        isActive: true
    )
}

private func state(
    _ limits: [UsageLimit],
    failing: LimitsError? = nil,
    signedOut: Bool = false
) -> UsageState {
    var state = UsageState()
    if signedOut {
        state.recordFailure(.unauthorized)
        return state
    }
    state.recordSuccess(UsageSnapshot(limits: limits))
    if let failing { state.recordFailure(failing) }
    return state
}

private func present(
    _ state: UsageState,
    mode: MenuBarDisplayMode = .sessionPercent,
    color: Bool = false
) -> MenuBarPresentation {
    MenuBarPresentation.make(state: state, mode: mode, useSeverityColor: color)
}

// MARK: - Title

@Suite("Menu bar title")
struct MenuBarTitleTests {

    @Test("shows the session percentage in session mode")
    func sessionMode() {
        let presentation = present(
            state([limit(.session, 32), limit(.weeklyAll, 51)]), mode: .sessionPercent)
        #expect(presentation.title == "32%")
    }

    @Test("shows the weekly percentage in weekly mode")
    func weeklyMode() {
        let presentation = present(
            state([limit(.session, 32), limit(.weeklyAll, 51)]), mode: .weeklyPercent)
        #expect(presentation.title == "51%")
    }

    @Test("shows the worst limit in highest mode")
    func highestMode() {
        let presentation = present(
            state([limit(.session, 32), limit(.weeklyAll, 51)]), mode: .highestPercent)
        #expect(presentation.title == "51%")
    }

    @Test("shows no number in icon-only mode")
    func iconOnlyMode() {
        let presentation = present(
            state([limit(.session, 32)]), mode: .iconOnly)
        #expect(presentation.title == nil)
    }

    @Test("falls back to the worst limit when the chosen one does not exist on this plan")
    func fallsBackWhenModeUnavailable() {
        // An account with no session limit at all.
        let presentation = present(state([limit(.weeklyAll, 77)]), mode: .sessionPercent)
        #expect(presentation.title == "77%")
    }

    @Test("rounds down, so it never claims 100% early")
    func roundsDown() {
        #expect(MenuBarPresentation.percentText(99.9) == "99%")
        #expect(MenuBarPresentation.percentText(0.9) == "0%")
        #expect(MenuBarPresentation.percentText(100) == "100%")
    }

    @Test("clamps nonsense percentages instead of rendering them")
    func clampsOutOfRange() {
        #expect(MenuBarPresentation.percentText(-5) == "0%")
        #expect(MenuBarPresentation.percentText(140) == "100%")
    }

    @Test("never renders decimals")
    func noDecimals() {
        for percent in stride(from: 0.0, through: 100.0, by: 0.7) {
            #expect(!MenuBarPresentation.percentText(percent).contains("."))
        }
    }
}

// MARK: - Icon

@Suite("Menu bar icon")
struct MenuBarIconTests {

    @Test("the gauge needle tracks the fill level")
    func needleTracksFill() {
        #expect(MenuBarPresentation.symbolName(forPercent: 0).hasSuffix("0percent"))
        #expect(MenuBarPresentation.symbolName(forPercent: 30).hasSuffix("33percent"))
        #expect(MenuBarPresentation.symbolName(forPercent: 55).hasSuffix("50percent"))
        #expect(MenuBarPresentation.symbolName(forPercent: 70).hasSuffix("67percent"))
        #expect(MenuBarPresentation.symbolName(forPercent: 99).hasSuffix("100percent"))
    }

    @Test("every produced symbol name is a gauge variant")
    func allSymbolsAreGauges() {
        for percent in stride(from: 0.0, through: 100.0, by: 1) {
            #expect(MenuBarPresentation.symbolName(forPercent: percent).hasPrefix("gauge."))
        }
    }
}

// MARK: - Colour

@Suite("Menu bar tint")
struct MenuBarTintTests {

    @Test("stays monochrome when severity colouring is off")
    func monochromeByDefault() {
        let critical = state([limit(.session, 99, severity: .critical)])
        #expect(present(critical, color: false).tint == nil)
    }

    @Test("tints at warning and critical when enabled")
    func tintsWhenEnabled() {
        let warning = state([limit(.session, 85, severity: .warning)])
        let critical = state([limit(.session, 99, severity: .critical)])

        #expect(present(warning, color: true).tint == .warning)
        #expect(present(critical, color: true).tint == .critical)
    }

    @Test("stays untinted at normal severity even when colouring is enabled")
    func noTintWhenNormal() {
        let normal = state([limit(.session, 20, severity: .normal)])
        #expect(present(normal, color: true).tint == nil)
    }

    @Test("tints from the worst limit, not the displayed one")
    func tintUsesWorstLimit() {
        // Session is fine, but the weekly limit is critical. Showing a calm
        // menu bar here would hide the thing about to stop your work.
        let mixed = state([
            limit(.session, 10, severity: .normal),
            limit(.weeklyAll, 99, severity: .critical),
        ])
        let presentation = present(mixed, mode: .sessionPercent, color: true)

        #expect(presentation.title == "10%")
        #expect(presentation.tint == .critical)
    }
}

// MARK: - Non-ready states

@Suite("Menu bar states")
struct MenuBarStateTests {

    @Test("signed out shows a person badge and no percentage")
    func signedOut() {
        let presentation = present(state([], signedOut: true))
        #expect(presentation.title == nil)
        #expect(presentation.symbolName.contains("person"))
        #expect(presentation.tooltip.contains("Claude Code"))
    }

    @Test("the very first load shows a placeholder, not a zero")
    func initialLoad() {
        let presentation = present(UsageState())
        #expect(presentation.title == nil)
        #expect(presentation.symbolName == "circle.dotted")
    }

    @Test("keeps showing the last good number while a refresh is failing")
    func staleShowsLastGoodNumber() {
        let stale = state([limit(.session, 42)], failing: .transport(message: "offline"))
        let presentation = present(stale)

        #expect(presentation.title == "42%")
        #expect(presentation.tooltip.contains("older numbers"))
    }

    @Test("an offline first load shows the offline icon")
    func offlineWithNoData() {
        var offline = UsageState()
        offline.recordFailure(.transport(message: "offline"))
        #expect(present(offline).symbolName == "wifi.slash")
    }
}

// MARK: - Accessibility & tooltip

@Suite("Menu bar accessibility")
struct MenuBarAccessibilityTests {

    @Test("VoiceOver hears the limit name and its percentage, even in icon-only mode")
    func voiceOverLabel() {
        let presentation = present(state([limit(.session, 32)]), mode: .iconOnly)
        #expect(presentation.accessibilityLabel == "Session: 32% used")
    }

    @Test("scoped limits name their model")
    func scopedLabel() {
        let presentation = present(
            state([limit(.weeklyScoped, 12, model: "Opus")]), mode: .highestPercent)
        #expect(presentation.accessibilityLabel.contains("Opus"))
    }

    @Test("the tooltip lists every limit with its reset time")
    func tooltipListsAll() {
        let tooltip = present(
            state([
                limit(.session, 32, resetsIn: 3600 * 2 + 60 * 39),
                limit(.weeklyAll, 51, resetsIn: 3600 * 50),
            ])
        ).tooltip

        #expect(tooltip.contains("Session: 32%"))
        #expect(tooltip.contains("2h 39m"))
        #expect(tooltip.contains("Weekly: 51%"))
    }

    @Test("every state produces a non-empty tooltip and label")
    func neverEmpty() {
        let states: [UsageState] = [
            UsageState(),
            state([limit(.session, 50)]),
            state([], signedOut: true),
            state([limit(.session, 50)], failing: .serverError(status: 500)),
        ]
        for state in states {
            for mode in MenuBarDisplayMode.allCases {
                let presentation = present(state, mode: mode)
                #expect(!presentation.tooltip.isEmpty)
                #expect(!presentation.accessibilityLabel.isEmpty)
                #expect(!presentation.symbolName.isEmpty)
            }
        }
    }
}

// MARK: - Relative time

@Suite("Relative time")
struct RelativeTimeTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func short(_ offset: TimeInterval) -> String {
        RelativeTime.short(until: now.addingTimeInterval(offset), from: now)
    }

    @Test("formats hours and minutes")
    func hoursAndMinutes() {
        #expect(short(3600 * 2 + 60 * 39) == "2h 39m")
    }

    @Test("drops the minutes component when it is zero")
    func wholeHours() {
        #expect(short(3600 * 3) == "3h")
    }

    @Test("formats minutes alone under an hour")
    func minutesOnly() {
        #expect(short(60 * 45) == "45m")
    }

    @Test("counts seconds in the final minute")
    func secondsOnly() {
        #expect(short(30) == "30s")
    }

    @Test("formats multi-day waits with days")
    func days() {
        #expect(short(86400 * 2 + 3600 * 5) == "2d 5h")
        #expect(short(86400 * 3) == "3d")
    }

    @Test("a window that has already rolled over reads as now, not a negative time")
    func pastIsNow() {
        #expect(short(-500) == "now")
        #expect(short(0) == "now")
    }

    @Test("the sentence form reads naturally in both cases")
    func sentences() {
        let future = RelativeTime.sentence(until: now.addingTimeInterval(3600), from: now)
        let past = RelativeTime.sentence(until: now.addingTimeInterval(-10), from: now)

        #expect(future == "resets in 1h")
        #expect(past == "resets now")
    }
}
