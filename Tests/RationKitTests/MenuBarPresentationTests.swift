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
        #expect(presentation.tooltip.contains("Sign in"))
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

@Suite("Menu bar hit testing")
struct MenuBarHitTestingTests {

    @Test("a click on the trailing third of a three-item strip selects the last")
    func trailingItem() {
        let widths = [40.0, 40.0, 40.0]
        let index = MenuBarHitTesting.itemIndex(
            clickX: 120, barWidth: 136, itemWidths: widths)
        #expect(index == 2)
    }

    @Test("a click on the leading item selects the first")
    func leadingItem() {
        let widths = [50.0, 50.0]
        let index = MenuBarHitTesting.itemIndex(
            clickX: 10, barWidth: 108, itemWidths: widths)
        #expect(index == 0)
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

// MARK: - Weekly bar

@Suite("Menu bar weekly bar")
struct MenuBarWeeklyBarTests {

    private func present(
        _ limits: [UsageLimit], bar: Bool = true, color: Bool = true
    ) -> MenuBarPresentation {
        var state = UsageState()
        state.recordSuccess(UsageSnapshot(limits: limits))
        return MenuBarPresentation.make(
            state: state, mode: .sessionPercent, useSeverityColor: color, showWeeklyBar: bar)
    }

    @Test("the bar tracks the weekly limit, not the displayed one")
    func tracksWeekly() {
        let presentation = present([limit(.session, 10), limit(.weeklyAll, 64)])

        #expect(presentation.title == "10%", "the title still shows the chosen mode")
        #expect(presentation.bar?.fraction == 0.64)
        #expect(presentation.bar?.name == "Weekly")
    }

    @Test("no bar when the setting is off")
    func hiddenWhenDisabled() {
        #expect(present([limit(.weeklyAll, 50)], bar: false).bar == nil)
    }

    @Test("falls back to the worst limit on an account with no weekly window")
    func fallsBackWithoutWeekly() {
        let presentation = present([limit(.session, 42)])
        #expect(presentation.bar?.fraction == 0.42)
    }

    @Test("no bar at all when there is no snapshot")
    func noBarWithoutData() {
        let presentation = MenuBarPresentation.make(
            state: UsageState(), mode: .sessionPercent,
            useSeverityColor: true, showWeeklyBar: true)
        #expect(presentation.bar == nil)
    }

    @Test("the fraction is clamped to 0…1 so the bar cannot overflow")
    func clampsFraction() {
        #expect(present([limit(.weeklyAll, 140)]).bar?.fraction == 1)
        #expect(present([limit(.weeklyAll, -5)]).bar?.fraction == 0)
    }

    @Test("goes amber past 80% and red past 90%")
    func escalatesWithUsage() {
        #expect(present([limit(.weeklyAll, 50)]).bar?.severity == .normal)
        #expect(present([limit(.weeklyAll, 79)]).bar?.severity == .normal)
        #expect(present([limit(.weeklyAll, 82)]).bar?.severity == .warning)
        #expect(present([limit(.weeklyAll, 95)]).bar?.severity == .critical)
    }

    @Test("the server can escalate sooner, but never calm things down")
    func serverCanOnlyEscalate() {
        // Server says critical at a low percentage — believe it.
        let early = present([limit(.weeklyAll, 20, severity: .critical)])
        #expect(early.bar?.severity == .critical)

        // Server says normal at 95% — our own threshold still wins.
        let late = present([limit(.weeklyAll, 95, severity: .normal)])
        #expect(late.bar?.severity == .critical)
    }

    @Test("the icon escalates from the worst limit, not just the displayed one")
    func iconEscalatesFromWorstLimit() {
        // Session is quiet; the week is nearly gone. A calm menu bar here
        // would hide the thing about to stop your work.
        let presentation = present([limit(.session, 5), limit(.weeklyAll, 93)])
        #expect(presentation.tint == .critical)
    }

    @Test("stays uncoloured when the user turned colour off")
    func respectsColourSetting() {
        let presentation = present([limit(.weeklyAll, 95)], color: false)
        #expect(presentation.tint == nil)
        // The bar keeps its colour regardless — it is the warning.
        #expect(presentation.bar?.severity == .critical)
    }
}

// MARK: - Chromatic colour (bitmap vs template)

@Suite("Menu bar chromatic colour")
struct MenuBarChromaticColorTests {

    private func present(
        _ limits: [UsageLimit], bar: Bool = true, color: Bool = true
    ) -> MenuBarPresentation {
        var state = UsageState()
        state.recordSuccess(UsageSnapshot(limits: limits))
        return MenuBarPresentation.make(
            state: state, mode: .sessionPercent, useSeverityColor: color, showWeeklyBar: bar)
    }

    @Test("a healthy weekly bar is still a template: it is drawn in primary")
    func healthyBarIsNotChromatic() {
        let presentation = present([limit(.weeklyAll, 50)])
        #expect(presentation.bar != nil)
        #expect(presentation.tint == nil)
        #expect(!presentation.hasChromaticColor)
    }

    @Test("an amber or red bar needs a bitmap, even with colouring off")
    func warningBarIsChromatic() {
        #expect(present([limit(.weeklyAll, 82)]).hasChromaticColor)
        #expect(present([limit(.weeklyAll, 95)], color: false).hasChromaticColor)
    }

    @Test("a severity tint needs a bitmap even without a bar")
    func tintIsChromatic() {
        let presentation = present([limit(.session, 95)], bar: false)
        #expect(presentation.bar == nil)
        #expect(presentation.tint == .critical)
        #expect(presentation.hasChromaticColor)
    }

    @Test("icon and percentage alone stay a template")
    func plainLabelIsNotChromatic() {
        #expect(!present([limit(.session, 20)], bar: false, color: false).hasChromaticColor)
    }

    @Test("the strip is chromatic if any account is")
    func stripFollowsAnyAccount() {
        let calm = present([limit(.weeklyAll, 20)])
        let loud = present([limit(.weeklyAll, 95)])
        #expect(!MenuBarStrip(items: [calm]).hasChromaticColor)
        #expect(MenuBarStrip(items: [calm, loud]).hasChromaticColor)
    }
}

@Suite("All hidden")
struct AllHiddenPresentationTests {

    @Test("shows an icon and nothing else")
    func isIconOnly() {
        let presentation = MenuBarPresentation.allHidden

        #expect(presentation.title == nil)
        #expect(presentation.tint == nil)
        #expect(presentation.bar == nil)
    }

    @Test("is not the same thing as needing setup")
    func differsFromSetupRequired() {
        #expect(MenuBarPresentation.allHidden != MenuBarPresentation.setupRequired)
    }

    @Test("says where to turn an account back on")
    func pointsAtTheAccountsTab() {
        #expect(MenuBarPresentation.allHidden.tooltip.contains("Accounts"))
    }
}

@Suite("Menu bar strip")
struct MenuBarStripTests {

    @Test("one account keeps the gauge glyph")
    func singleAccountUsesGauge() {
        let strip = MenuBarStrip.make(
            accounts: [
                (
                    provider: .claude, state: state([limit(.session, 32)]),
                    promptsForPermission: false
                )
            ],
            mode: .sessionPercent,
            useSeverityColor: false,
            showWeeklyBar: false,
            hasCompletedOnboarding: true,
            isEverythingHidden: false)

        #expect(strip.items.count == 1)
        #expect(strip.items[0].title == "32%")
        #expect(strip.items[0].symbolName.contains("gauge"))
    }

    @Test("two accounts sit side by side, each named by its own symbol")
    func multipleAccountsUseIdentitySymbols() {
        let strip = MenuBarStrip.make(
            accounts: [
                (
                    provider: .claude, state: state([limit(.session, 32)]),
                    promptsForPermission: false
                ),
                (
                    provider: .cursor, state: state([limit(.weeklyAll, 71)]),
                    promptsForPermission: false
                ),
            ],
            mode: .highestPercent,
            useSeverityColor: false,
            showWeeklyBar: false,
            hasCompletedOnboarding: true,
            isEverythingHidden: false)

        #expect(strip.items.map(\.title) == ["32%", "71%"])
        #expect(
            strip.items.map(\.symbolName) == [
                Provider.claude.symbolName, Provider.cursor.symbolName,
            ])
        #expect(strip.accessibilityLabel.contains("Claude"))
        #expect(strip.accessibilityLabel.contains("Cursor"))
    }

    @Test("skips a provider that would prompt until onboarding is done")
    func skipsPromptingProvidersBeforeOnboarding() {
        let strip = MenuBarStrip.make(
            accounts: [
                (
                    provider: .claude, state: state([limit(.session, 10)]),
                    promptsForPermission: true
                ),
                (
                    provider: .cursor, state: state([limit(.weeklyAll, 40)]),
                    promptsForPermission: false
                ),
            ],
            mode: .highestPercent,
            useSeverityColor: false,
            showWeeklyBar: false,
            hasCompletedOnboarding: false,
            isEverythingHidden: false)

        #expect(strip.items.count == 1)
        #expect(strip.items[0].title == "40%")
    }

    @Test("everything hidden is the muted icon, not setup")
    func hiddenIsNotSetup() {
        let strip = MenuBarStrip.make(
            accounts: [],
            mode: .sessionPercent,
            useSeverityColor: false,
            showWeeklyBar: false,
            hasCompletedOnboarding: true,
            isEverythingHidden: true)

        #expect(strip == .allHidden)
        #expect(strip != .setupRequired)
    }

    @Test("names the tool in a signed-out tooltip")
    func signedOutNamesTheTool() {
        let presentation = MenuBarPresentation.make(
            state: state([], signedOut: true),
            mode: .sessionPercent,
            useSeverityColor: false,
            provider: .cursor)

        #expect(presentation.tooltip.contains("Cursor"))
        #expect(!presentation.tooltip.contains("Claude Code"))
    }
}

@Suite("Severity escalation")
struct SeverityEscalationTests {

    @Test("thresholds are 80 for amber and 90 for red")
    func thresholds() {
        #expect(Severity.escalating(percent: 0, reported: .normal) == .normal)
        #expect(Severity.escalating(percent: 79.9, reported: .normal) == .normal)
        #expect(Severity.escalating(percent: 80, reported: .normal) == .warning)
        #expect(Severity.escalating(percent: 89.9, reported: .normal) == .warning)
        #expect(Severity.escalating(percent: 90, reported: .normal) == .critical)
    }

    @Test("never quieter than the server said")
    func neverDowngrades() {
        #expect(Severity.escalating(percent: 10, reported: .warning) == .warning)
        #expect(Severity.escalating(percent: 10, reported: .critical) == .critical)
        #expect(Severity.escalating(percent: 85, reported: .critical) == .critical)
    }
}
