import Charts
import RationKit
import SwiftUI

/// "At this rate, do I run out before the window resets?"
///
/// The gauge answers *how much is gone*; this answers *whether that is a
/// problem*, which is the question you actually have. 60% used is comfortable
/// on day six of a week and alarming on day one.
public struct ProjectionCard: View {

    let projection: WindowProjection
    let curve: [(date: Date, percent: Double)]
    let now: Date

    public init(
        projection: WindowProjection,
        curve: [(date: Date, percent: Double)],
        now: Date = Date()
    ) {
        self.projection = projection
        self.curve = curve
        self.now = now
    }

    private var resetsAt: Date { now.addingTimeInterval(projection.remaining) }

    /// The dashed continuation from here to the reset, at the current rate.
    private var forecast: [(date: Date, percent: Double)] {
        [
            (now, projection.percentUsed),
            (resetsAt, projection.projectedPercent),
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chart
            footnote
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(projection.limit.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(projection.verdict(now: now))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(projection.severity.color ?? .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            PaceBadge(pace: projection.pace, severity: projection.severity)
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            // What has actually happened, shaped by local history.
            ForEach(curve, id: \.date) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.percent)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.percent)
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.8))
            }

            // Where the current rate leads. Dashed, because it is a guess.
            ForEach(forecast, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.percent),
                    series: .value("Series", "forecast")
                )
                .foregroundStyle(projection.severity.accentColor.opacity(0.9))
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
            }

            // The ceiling.
            RuleMark(y: .value("Limit", 100))
                .foregroundStyle(Theme.critical.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

            // You are here.
            RuleMark(x: .value("Now", now))
                .foregroundStyle(Theme.chartRule)
                .lineStyle(StrokeStyle(lineWidth: 1))

            // Where it runs out, when it does.
            if let exhaustedAt = projection.exhaustedAt {
                PointMark(
                    x: .value("Time", exhaustedAt),
                    y: .value("Used", 100)
                )
                .foregroundStyle(Theme.critical)
                .symbolSize(36)
            }
        }
        .chartYScale(domain: 0...max(110, projection.projectedPercent * 1.05))
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%").font(.system(size: 8))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [now.addingTimeInterval(-projection.elapsed), resetsAt]) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date == resetsAt ? "reset" : "start")
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .frame(height: 84)
    }

    // MARK: Footnote

    private var footnote: some View {
        Text(
            "Shape from your local history, scaled to the percentage Anthropic reports. "
                + "The dashed line assumes you keep going at the current rate."
        )
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pace

/// Consumption relative to time elapsed. 1.0× is exactly on pace to finish the
/// window at 100%.
private struct PaceBadge: View {
    let pace: Double
    let severity: Severity

    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: "%.1f×", pace))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(severity.color ?? .primary)
            Text("pace")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .help("1.0× means you finish the window at exactly 100%.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pace")
        .accessibilityValue(String(format: "%.1f times the sustainable rate", pace))
    }
}
