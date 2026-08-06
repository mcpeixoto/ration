import RationKit
import SwiftUI

/// How usage is trending: totals over a chosen range, and a daily chart.
///
/// Split out of Metrics once that tab grew past what a menu bar panel can show
/// without scrolling. This half answers "how much, and is it going up?"; the
/// Detail tab answers "what is it going into?".
public struct TrendsView: View {

    let history: UsageHistory
    let status: TranscriptStore.Status
    let now: Date

    public init(history: UsageHistory, status: TranscriptStore.Status, now: Date = Date()) {
        self.history = history
        self.status = status
        self.now = now
    }

    @AppStorage("metricsRange") private var rangeDays = 30
    @AppStorage("metricsChart") private var metricRaw = DailyMetric.tokens.rawValue

    private var metric: DailyMetric { DailyMetric(rawValue: metricRaw) ?? .tokens }
    private var window: [DayUsage] { history.window(days: rangeDays, endingOn: now) }
    private var totals: UsageHistory.Totals { history.total(over: window) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .scanning = status {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if history.isEmpty {
                StatusMessageView(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "No history yet",
                    message: "Trends appear once you have used Claude Code."
                )
            } else {
                SegmentedChoice(
                    options: Ranges.all, selection: $rangeDays, label: Ranges.label)

                HStack(spacing: 0) {
                    StatTile(label: "Tokens", value: Format.tokens(totals.tokens))
                    Divider().frame(height: 26)
                    StatTile(label: "Messages", value: Format.compact(totals.messages))
                    Divider().frame(height: 26)
                    StatTile(label: "Sessions", value: "\(totals.sessions)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    SegmentedChoice(
                        options: DailyMetric.allCases,
                        selection: Binding(
                            get: { metric }, set: { metricRaw = $0.rawValue }),
                        label: \.title
                    )
                    DailyChart(days: window, metric: metric)
                }

                Divider()

                HStack(spacing: 0) {
                    StatTile(
                        label: "Per active day",
                        value: Format.tokens(totals.averageTokensPerActiveDay))
                    Divider().frame(height: 24)
                    StatTile(label: "Active days", value: "\(totals.activeDays)")
                    Divider().frame(height: 24)
                    StatTile(label: "Est. cost", value: Format.cost(totals.cost))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The ranges offered on Trends and Detail. Shared so the two tabs agree.
enum Ranges {
    static let all = [7, 30, 90]
    static func label(_ days: Int) -> String { "\(days) days" }
}
