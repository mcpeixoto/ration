import Charts
import RationKit
import SwiftUI

/// What to plot over time.
public enum DailyMetric: String, CaseIterable, Identifiable, Hashable {
    case tokens
    case messages
    case sessions
    case cost

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tokens: "Tokens"
        case .messages: "Messages"
        case .sessions: "Sessions"
        case .cost: "Cost"
        }
    }

    func value(_ day: DayUsage) -> Double {
        switch self {
        case .tokens: Double(day.billableTokens)
        case .messages: Double(day.messages)
        case .sessions: Double(day.sessionCount)
        case .cost: day.cost
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .tokens: Format.tokens(Int(value))
        case .messages, .sessions: Format.compact(Int(value))
        case .cost: Format.cost(value)
        }
    }
}

/// Daily activity over the selected range.
struct DailyChart: View {

    let days: [DayUsage]
    let metric: DailyMetric

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var peak: Double {
        max(days.map(metric.value).max() ?? 1, 1)
    }

    /// A seven-day trailing mean, so the shape of a habit shows through the
    /// daily noise. Weekends alone can halve a bar.
    private var rollingAverage: [(date: Date, value: Double)] {
        guard days.count >= 7 else { return [] }
        return days.indices.dropFirst(6).map { index in
            let slice = days[(index - 6)...index]
            let mean = slice.map(metric.value).reduce(0, +) / 7
            return (days[index].date, mean)
        }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(metric.title, metric.value(day))
                )
                .foregroundStyle(Theme.accent.opacity(0.75))
                .cornerRadius(1.5)
            }

            ForEach(rollingAverage, id: \.date) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("7-day average", point.value),
                    series: .value("Series", "average")
                )
                .foregroundStyle(Theme.rollingAverage)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, peak / 2, peak]) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.07))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(metric.format(raw)).font(.system(size: 8))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 8))
            }
        }
        .frame(height: 92)
        .accessibilityLabel("\(metric.title) per day")
    }
}

/// Which hours of the day the work actually happens in.
///
/// Built from local history, so it reflects when you were at the keyboard
/// rather than anything the API knows.
struct HourHistogram: View {

    let days: [DayUsage]
    let hourly: [Int]

    var body: some View {
        Chart {
            ForEach(Array(hourly.enumerated()), id: \.offset) { hour, value in
                BarMark(
                    x: .value("Hour", hour),
                    y: .value("Tokens", value)
                )
                .foregroundStyle(Theme.accent.opacity(0.7))
                .cornerRadius(1)
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text("\(hour)").font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 54)
        .accessibilityLabel("Activity by hour of day")
    }
}
