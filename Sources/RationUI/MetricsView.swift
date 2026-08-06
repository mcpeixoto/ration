import RationKit
import SwiftUI

/// Where the tokens went: by model, by project, and what it would have cost.
public struct MetricsView: View {

    let history: UsageHistory
    let status: TranscriptStore.Status
    let now: Date

    public init(history: UsageHistory, status: TranscriptStore.Status, now: Date = Date()) {
        self.history = history
        self.status = status
        self.now = now
    }

    @AppStorage("metricsRange") private var rangeDays = 30

    private let ranges = [7, 30, 90]

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
                rangePicker
                headline
                Divider()
                breakdown(
                    title: "Models", entries: totals.rankedModels, total: totals.tokens)
                Divider()
                breakdown(
                    title: "Projects", entries: Array(totals.rankedProjects.prefix(5)),
                    total: totals.tokens)
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
