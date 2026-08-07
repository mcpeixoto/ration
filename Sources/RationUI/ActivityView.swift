import RationKit
import SwiftUI

/// A calendar heat map of the last few months, one square per day.
public struct ActivityView: View {

    let history: UsageHistory
    let status: TranscriptStore.Status
    let now: Date
    /// Whose history this is, for the empty state. The rest of the view is
    /// provider-agnostic — tokens are tokens once they are in the history.
    let provider: Provider

    public init(
        history: UsageHistory,
        status: TranscriptStore.Status,
        now: Date = Date(),
        provider: Provider = .claude
    ) {
        self.history = history
        self.status = status
        self.now = now
        self.provider = provider
    }

    /// Roughly five months — as many weeks as fit the panel without crowding.
    private let weeks = 20
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    @State private var hovered: DayUsage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .scanning(let progress) = status {
                scanning(progress: progress)
            } else if history.isEmpty {
                StatusMessageView(
                    symbol: "calendar",
                    title: "No history yet",
                    message: "Once you have used \(provider.toolName), your activity appears here."
                )
            } else {
                heatMap
                legend
                Divider()
                summary
                Divider()
                rhythm
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Heat map

    private var days: [DayUsage] {
        // Pad to the end of the current week so the grid's last column is full.
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now) - 1
        let end = calendar.date(byAdding: .day, value: 6 - weekday, to: now) ?? now
        return history.window(days: weeks * 7, endingOn: end)
    }

    /// Columns of seven, oldest week first.
    private var columns: [[DayUsage]] {
        stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    private var peak: Int {
        max(days.map(\.billableTokens).max() ?? 0, 1)
    }

    private var heatMap: some View {
        VStack(alignment: .leading, spacing: 5) {
            monthLabels

            HStack(alignment: .top, spacing: gap) {
                weekdayLabels

                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(week) { day in
                            DayCell(
                                day: day,
                                intensity: intensity(of: day),
                                isFuture: day.date > now,
                                isHovered: hovered?.id == day.id,
                                size: cell
                            )
                            .onHover { inside in
                                hovered = inside ? day : (hovered?.id == day.id ? nil : hovered)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Relative to the busiest day in view, so the scale adapts to how heavily
    /// this particular person uses Claude rather than to an absolute number.
    private func intensity(of day: DayUsage) -> Double {
        guard day.billableTokens > 0 else { return 0 }
        // Square root so a few enormous days don't flatten everything else.
        return (Double(day.billableTokens) / Double(peak)).squareRoot()
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            // Mon / Wed / Fri only — labelling all seven is unreadable at this size.
            ForEach(0..<7, id: \.self) { row in
                Text(["", "M", "", "W", "", "F", ""][row])
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10, height: cell)
            }
        }
    }

    private var monthLabels: some View {
        HStack(alignment: .bottom, spacing: gap) {
            Color.clear.frame(width: 10, height: 1)

            ForEach(Array(columns.enumerated()), id: \.offset) { index, week in
                // `fixedSize` before the frame keeps the label on one line and
                // lets it overhang its column instead of wrapping into two.
                Text(monthLabel(forWeek: week, at: index))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: cell, alignment: .leading)
            }
        }
        .frame(height: 10, alignment: .bottom)
    }

    /// Labels the first column of each month, and nothing else.
    private func monthLabel(forWeek week: [DayUsage], at index: Int) -> String {
        guard let first = week.first else { return "" }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: first.date)

        if index > 0, let previous = columns[index - 1].first,
            calendar.component(.month, from: previous.date) == month
        {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: first.date)
    }

    // MARK: Legend and summary

    private var legend: some View {
        HStack(spacing: 6) {
            if let hovered {
                Text(tooltip(for: hovered))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(activeDays) active days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Less")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            ForEach([0.0, 0.3, 0.55, 0.8, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.heat(level))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered?.id)
    }

    private var activeDays: Int {
        days.filter { $0.billableTokens > 0 }.count
    }

    private func tooltip(for day: DayUsage) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let date = formatter.string(from: day.date)

        guard day.billableTokens > 0 else { return "\(date) · no activity" }
        return
            "\(date) · \(Format.tokens(day.billableTokens)) tokens · \(day.sessionCount) session\(day.sessionCount == 1 ? "" : "s")"
    }

    private var summary: some View {
        let totals = history.total(over: days)
        let streak = history.currentStreak(endingOn: now)

        return HStack(spacing: 0) {
            StatTile(label: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days")
            Divider().frame(height: 26)
            StatTile(label: "Sessions", value: "\(totals.sessions)")
            Divider().frame(height: 26)
            StatTile(label: "Busiest", value: busiestLabel(totals.busiestDay))
        }
    }

    /// When in the day the work actually happens. Local history knows this;
    /// the API never sees it.
    private var rhythm: some View {
        let totals = history.total(over: days)
        return VStack(alignment: .leading, spacing: 6) {
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
            HourHistogram(days: days, hourly: totals.tokensByHour)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        return formatter.string(from: Calendar.current.date(from: components) ?? Date())
            .lowercased()
    }

    private func busiestLabel(_ day: DayUsage?) -> String {
        guard let day, day.billableTokens > 0 else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: day.date)
    }

    private func scanning(progress: Double) -> some View {
        VStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
            Text("Reading your history… \(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("This happens once. Afterwards only new activity is read.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Day cell

private struct DayCell: View {

    let day: DayUsage
    let intensity: Double
    let isFuture: Bool
    let isHovered: Bool
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(isFuture ? Color.clear : Theme.heat(intensity))
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: isHovered ? 1.2 : 0)
            }
            .accessibilityLabel(Text(day.date, format: .dateTime.day().month()))
            .accessibilityValue(
                day.billableTokens > 0
                    ? "\(Format.tokens(day.billableTokens)) tokens" : "no activity")
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
