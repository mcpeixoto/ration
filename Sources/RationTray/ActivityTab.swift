import CLinuxTray
import Foundation
import RationKit

/// A calendar heat map of the last few months, one square per day, plus
/// streaks and which hours of the day the work actually happens.
extension Panel {

    /// Roughly five months — as many weeks as fit the panel without crowding.
    private var activityWeeks: Int { 20 }
    private var cellSize: Double { 11 }
    private var cellGap: Double { 3 }

    func drawActivityTab(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        let entry = app.entry(for: selectedProviderID)
        let history = entry?.history?.history ?? UsageHistory()
        let status = entry?.history?.status ?? .ready
        let provider = entry?.provider ?? .claude

        if case .scanning(let progress) = status {
            return drawScanning(canvas, width: width, top: top, progress: progress)
        }
        if history.isEmpty {
            return drawStatusMessage(
                canvas, width: width, top: top, symbol: "calendar", title: "No history yet",
                message: "Once you have used \(provider.toolName), your activity appears here.")
        }

        var y = top + 14
        let days = activityDays(history: history, now: now)
        let columns = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
        let peak = max(days.map(\.billableTokens).max() ?? 0, 1)

        y += drawHeatMap(
            canvas, origin: Point(16, y), columns: columns, peak: peak, now: now)
        y += 8
        y += drawLegend(canvas, rect: Rect(16, y, width - 32, 12), days: days)
        y += 12

        canvas.separator(y: y, from: 16, to: width - 16)
        y += 12

        let totals = history.total(over: days)
        let streak = history.currentStreak(endingOn: now)
        y += drawStatTiles(
            canvas, rect: Rect(16, y, width - 32, 34),
            tiles: [
                (label: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days"),
                (label: "Sessions", value: "\(totals.sessions)", unit: nil),
                (label: "Busiest", value: busiestLabel(totals.busiestDay), unit: nil),
            ])
        y += 12

        canvas.separator(y: y, from: 16, to: width - 16)
        y += 12

        y += drawRhythm(canvas, rect: Rect(16, y, width - 32, 70), totals: totals)
        return y - top + 12
    }

    // MARK: Heat map

    private func activityDays(history: UsageHistory, now: Date) -> [DayUsage] {
        // Pad to the end of the current week so the grid's last column is full.
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now) - 1
        let end = calendar.date(byAdding: .day, value: 6 - weekday, to: now) ?? now
        return history.window(days: activityWeeks * 7, endingOn: end)
    }

    private func drawHeatMap(
        _ canvas: Canvas, origin: Point, columns: [[DayUsage]], peak: Int, now: Date
    ) -> Double {
        let palette = canvas.palette
        let labelColumn = 12.0
        var y = origin.y

        // Month labels: the first column of each month, and nothing else.
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let calendar = Calendar.current
        for (index, week) in columns.enumerated() {
            guard let first = week.first else { continue }
            let month = calendar.component(.month, from: first.date)
            if index > 0, let previous = columns[index - 1].first,
                calendar.component(.month, from: previous.date) == month
            {
                continue
            }
            canvas.text(
                formatter.string(from: first.date),
                at: Point(origin.x + labelColumn + Double(index) * (cellSize + cellGap), y),
                size: 8, color: palette.tertiaryText)
        }
        y += 12

        // Mon / Wed / Fri only — labelling all seven is unreadable at this size.
        let weekdayLabels = ["", "M", "", "W", "", "F", ""]
        for row in 0..<7 where !weekdayLabels[row].isEmpty {
            canvas.text(
                weekdayLabels[row],
                at: Point(origin.x + 10, y + Double(row) * (cellSize + cellGap) + 1),
                size: 8, color: palette.tertiaryText, align: .trailing)
        }

        for (index, week) in columns.enumerated() {
            for (row, day) in week.enumerated() {
                let rect = Rect(
                    origin.x + labelColumn + Double(index) * (cellSize + cellGap),
                    y + Double(row) * (cellSize + cellGap),
                    cellSize, cellSize)
                guard day.date <= now else { continue }
                // Square root so a few enormous days don't flatten everything else.
                let intensity =
                    day.billableTokens > 0
                    ? (Double(day.billableTokens) / Double(peak)).squareRoot() : 0
                canvas.fillRounded(rect, radius: 2.5, palette.heat(intensity))
                if isHovered(rect) {
                    canvas.strokeRounded(rect, radius: 2.5, width: 1.2, palette.accent)
                    hoveredDay = day
                }
            }
        }

        return y - origin.y + 7 * (cellSize + cellGap)
    }

    private func drawLegend(_ canvas: Canvas, rect: Rect, days: [DayUsage]) -> Double {
        let palette = canvas.palette
        let text: String
        if let day = hoveredDay, days.contains(where: { $0.id == day.id }) {
            text = tooltip(for: day)
        } else {
            text = "\(days.filter { $0.billableTokens > 0 }.count) active days"
        }
        canvas.text(
            canvas.truncated(text, size: 10, maxWidth: rect.width - 110),
            at: Point(rect.x, rect.y), size: 10, color: palette.secondaryText)

        var x = rect.maxX
        canvas.text(
            "More", at: Point(x, rect.y + 1), size: 8, color: palette.tertiaryText,
            align: .trailing)
        x -= canvas.width("More", size: 8) + 4
        for level in [1.0, 0.8, 0.55, 0.3, 0.0] {
            x -= 8
            canvas.fillRounded(Rect(x, rect.y + 2, 8, 8), radius: 2, palette.heat(level))
            x -= 2
        }
        x -= 2
        canvas.text(
            "Less", at: Point(x, rect.y + 1), size: 8, color: palette.tertiaryText,
            align: .trailing)
        return 14
    }

    private func tooltip(for day: DayUsage) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let date = formatter.string(from: day.date)
        guard day.billableTokens > 0 else { return "\(date) · no activity" }
        let sessions = day.sessionCount
        return
            "\(date) · \(Format.tokens(day.billableTokens)) tokens · \(sessions) session\(sessions == 1 ? "" : "s")"
    }

    private func busiestLabel(_ day: DayUsage?) -> String {
        guard let day, day.billableTokens > 0 else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: day.date)
    }

    // MARK: Tiles and rhythm

    func drawStatTiles(
        _ canvas: Canvas, rect: Rect, tiles: [(label: String, value: String, unit: String?)]
    ) -> Double {
        let palette = canvas.palette
        let slot = rect.width / Double(tiles.count)
        for (index, tile) in tiles.enumerated() {
            let center = rect.x + slot * (Double(index) + 0.5)
            let valueWidth = canvas.width(tile.value, size: 15, weight: .bold)
            let unitWidth = tile.unit.map { canvas.width($0, size: 9) + 3 } ?? 0
            let startX = center - (valueWidth + unitWidth) / 2
            canvas.text(tile.value, at: Point(startX, rect.y), size: 15, weight: .bold)
            if let unit = tile.unit {
                canvas.text(
                    unit, at: Point(startX + valueWidth + 3, rect.y + 6), size: 9,
                    color: palette.secondaryText)
            }
            canvas.text(
                tile.label, at: Point(center, rect.y + 20), size: 9,
                color: palette.tertiaryText, align: .center)

            if index > 0 {
                canvas.setColor(palette.separator)
                cairo_set_line_width(canvas.cr, 1)
                cairo_move_to(canvas.cr, rect.x + slot * Double(index), rect.y + 3)
                cairo_line_to(canvas.cr, rect.x + slot * Double(index), rect.y + 29)
                cairo_stroke(canvas.cr)
            }
        }
        return rect.height
    }

    /// When in the day the work happens. Local history knows this; the API
    /// never sees it.
    private func drawRhythm(
        _ canvas: Canvas, rect: Rect, totals: UsageHistory.Totals
    ) -> Double {
        let palette = canvas.palette
        canvas.text(
            "Rhythm", at: Point(rect.x, rect.y), size: 11, weight: .bold,
            color: palette.secondaryText)
        if let hour = totals.busiestHour {
            canvas.text(
                "peak \(hourLabel(hour))", at: Point(rect.maxX, rect.y + 1), size: 10,
                color: palette.tertiaryText, align: .trailing)
        }

        let chart = Rect(rect.x, rect.y + 18, rect.width, 46)
        let peak = max(totals.tokensByHour.max() ?? 0, 1)
        let slot = chart.width / 24
        for (hour, value) in totals.tokensByHour.enumerated() {
            let height = chart.height * Double(value) / Double(peak)
            guard height > 0 else { continue }
            canvas.fillRounded(
                Rect(chart.x + slot * Double(hour) + 1, chart.maxY - height, slot - 2, height),
                radius: 1, palette.accent.opacity(0.7))
        }
        for hour in [0, 6, 12, 18, 23] {
            canvas.text(
                "\(hour)", at: Point(chart.x + slot * (Double(hour) + 0.5), chart.maxY + 2),
                size: 8, color: palette.tertiaryText, align: .center)
        }
        return rect.height + 12
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        return formatter.string(from: Calendar.current.date(from: components) ?? Date())
            .lowercased()
    }

    // MARK: Scanning

    func drawScanning(_ canvas: Canvas, width: Double, top: Double, progress: Double) -> Double {
        let palette = canvas.palette
        var y = top + 28
        let bar = Rect(40, y, width - 80, 5)
        canvas.fillRounded(bar, radius: 2.5, palette.track)
        canvas.fillRounded(
            Rect(bar.x, bar.y, bar.width * min(max(progress, 0), 1), bar.height), radius: 2.5,
            palette.accent)
        y += 16

        canvas.text(
            "Reading your history… \(Int(progress * 100))%", at: Point(width / 2, y), size: 11,
            color: palette.secondaryText, align: .center)
        y += 18
        y += canvas.paragraph(
            "This happens once. Afterwards only new activity is read.",
            at: Point(40, y), width: width - 80, size: 10, color: palette.tertiaryText,
            align: .center)
        return y - top + 28
    }
}

/// `1_234_567` → `1.2M`. Token counts get large fast; exact digits are noise.
///
/// Mirrors `Format` in the macOS build so the two read identically.
enum Format {

    static func tokens(_ count: Int) -> String { compact(count) }

    static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        case ..<10_000: String(format: "%.1fk", Double(count) / 1_000)
        case ..<1_000_000: "\(count / 1_000)k"
        case ..<10_000_000: String(format: "%.1fM", Double(count) / 1_000_000)
        default: "\(count / 1_000_000)M"
        }
    }

    /// Estimated API-equivalent cost. Always shown with a qualifier — a
    /// subscription is a flat fee, not a per-token bill.
    static func cost(_ amount: Double) -> String {
        amount < 10 ? String(format: "$%.2f", amount) : String(format: "$%.0f", amount)
    }
}
