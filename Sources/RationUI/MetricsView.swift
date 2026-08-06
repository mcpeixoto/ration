import RationKit
import SwiftUI

/// Where the tokens went: by model, by project, and what it would have cost.
public struct MetricsView: View {

    let history: UsageHistory
    let status: TranscriptStore.Status
    let now: Date
    /// The live snapshot, when there is one — the projection needs the
    /// authoritative percentage, which local history cannot supply.
    let snapshot: UsageSnapshot?

    public init(
        history: UsageHistory,
        status: TranscriptStore.Status,
        now: Date = Date(),
        snapshot: UsageSnapshot? = nil
    ) {
        self.history = history
        self.status = status
        self.now = now
        self.snapshot = snapshot
    }

    @AppStorage("metricsRange") private var rangeDays = 30
    @AppStorage("metricsChart") private var metricRaw = DailyMetric.tokens.rawValue

    private let ranges = [7, 30, 90]

    private var metric: DailyMetric {
        DailyMetric(rawValue: metricRaw) ?? .tokens
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .scanning = status {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if history.isEmpty {
                StatusMessageView(
                    symbol: "chart.bar",
                    title: "No history yet",
                    message: "Metrics appear once you have used Claude Code."
                )
            } else {
                if let projection {
                    ProjectionCard(
                        projection: projection,
                        curve: history.windowCurve(for: projection, now: now),
                        now: now)
                    Divider()
                }

                rangePicker
                headline

                chartSection

                Divider()
                breakdown(
                    title: "Models", entries: totals.rankedModels, total: totals.tokens)
                Divider()
                breakdown(
                    title: "Projects", entries: Array(totals.rankedProjects.prefix(5)),
                    total: totals.tokens)
                Divider()
                rhythm
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var window: [DayUsage] {
        history.window(days: rangeDays, endingOn: now)
    }

    private var totals: UsageHistory.Totals {
        history.total(over: window)
    }

    /// Projects the weekly window by default — the one that creeps up. Falls
    /// back to whichever limit is closest to being hit.
    private var projection: WindowProjection? {
        guard let snapshot else { return nil }
        let candidates = [snapshot.weeklyLimit, snapshot.primaryLimit].compactMap { $0 }
        for limit in candidates {
            if let projection = WindowProjection(limit: limit, now: now) { return projection }
        }
        return nil
    }

    // MARK: Charts

    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedChoice(
                options: DailyMetric.allCases,
                selection: Binding(
                    get: { metric },
                    set: { metricRaw = $0.rawValue }
                ),
                label: \.title
            )
            DailyChart(days: window, metric: metric)
        }
    }

    /// When the work actually happens. Local history knows this; the API does not.
    @ViewBuilder
    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rhythm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let hour = totals.busiestHour {
                    Text("peak \(hourLabel(hour))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            HourHistogram(days: window, hourly: totals.tokensByHour)

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

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date).lowercased()
    }

    // MARK: Range

    /// Hand-rolled rather than `Picker(.segmented)`: the stock macOS control
    /// is backed by `NSSegmentedControl` and keeps the system accent colour
    /// regardless of `.tint`, which would put a blue chip in an orange app.
    private var rangePicker: some View {
        SegmentedChoice(
            options: ranges,
            selection: $rangeDays,
            label: { "\($0) days" }
        )
    }

    // MARK: Headline numbers

    private var headline: some View {
        HStack(spacing: 0) {
            StatTile(label: "Tokens", value: Format.tokens(totals.tokens))
            Divider().frame(height: 26)
            StatTile(label: "Messages", value: Format.compact(totals.messages))
            Divider().frame(height: 26)
            StatTile(label: "Sessions", value: "\(totals.sessions)")
        }
    }

    // MARK: Breakdowns

    @ViewBuilder
    private func breakdown(
        title: String, entries: [(name: String, tokens: Int)], total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("Nothing in this period.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(entries, id: \.name) { entry in
                    ShareRow(
                        name: entry.name,
                        tokens: entry.tokens,
                        share: total > 0 ? Double(entry.tokens) / Double(total) : 0
                    )
                }
            }
        }
    }
}

// MARK: - Row

/// One model or project, with its share of the window's tokens.
private struct ShareRow: View {

    let name: String
    let tokens: Int
    let share: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rationAnimatesEntrance) private var animatesEntrance
    /// See `RingGauge.displayed` for why this starts as `nil`.
    @State private var shown: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Text(Format.tokens(tokens))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("\(Int((share * 100).rounded()))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(Theme.accent.gradient)
                        .frame(width: max(geometry.size.width * (shown ?? share), 4))
                }
            }
            .frame(height: 4)
        }
        .onAppear {
            guard animatesEntrance, !reduceMotion else {
                shown = share
                return
            }
            shown = 0
            withAnimation(.smooth(duration: 0.6)) { shown = share }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue("\(Format.tokens(tokens)) tokens, \(Int(share * 100)) percent")
    }
}

// MARK: - Formatting

enum Format {

    /// `1_234_567` → `1.2M`. Token counts get large fast; exact digits are noise.
    static func tokens(_ count: Int) -> String {
        compact(count)
    }

    static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        case ..<10_000: String(format: "%.1fk", Double(count) / 1_000)
        case ..<1_000_000: "\(count / 1_000)k"
        case ..<10_000_000: String(format: "%.1fM", Double(count) / 1_000_000)
        default: "\(count / 1_000_000)M"
        }
    }

    /// Estimated API-equivalent cost. Always shown with a qualifier in the UI —
    /// a subscription is a flat fee, not a per-token bill.
    static func cost(_ amount: Double) -> String {
        amount < 10
            ? String(format: "$%.2f", amount)
            : String(format: "$%.0f", amount)
    }
}
