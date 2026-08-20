import CLinuxTray
import Foundation
import RationKit

/// How usage is trending: totals over a chosen range, and a daily chart.
extension Panel {

    /// The ranges offered on Trends and Detail. Shared so the two tabs agree.
    static let ranges = [7, 30, 90]

    func drawTrendsTab(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        let entry = app.entry(for: selectedProviderID)
        let history = entry?.history?.history ?? UsageHistory()
        let status = entry?.history?.status ?? .ready
        let provider = entry?.provider ?? .claude

        if case .scanning(let progress) = status {
            return drawScanning(canvas, width: width, top: top, progress: progress)
        }
        if history.isEmpty {
            return drawStatusMessage(
                canvas, width: width, top: top, symbol: "chart.line.uptrend.xyaxis",
                title: "No history yet",
                message: "Trends appear once you have used \(provider.toolName).")
        }

        let window = history.window(days: trendsDays, endingOn: now)
        let totals = history.total(over: window)
        var y = top + 12

        y += drawSegmented(
            canvas, rect: Rect(16, y, width - 32, 24),
            options: Self.ranges.map { "\($0) days" },
            selected: Self.ranges.firstIndex(of: trendsDays) ?? 1,
            tinted: true
        ) { [weak self] index in
            self?.trendsDays = Self.ranges[index]
        }
        y += 14

        y += drawStatTiles(
            canvas, rect: Rect(16, y, width - 32, 34),
            tiles: [
                (label: "Tokens", value: Format.tokens(totals.tokens), unit: nil),
                (label: "Messages", value: Format.compact(totals.messages), unit: nil),
                (label: "Sessions", value: "\(totals.sessions)", unit: nil),
            ])
        y += 14

        let metrics = TrendsMetric.allCases
        y += drawSegmented(
            canvas, rect: Rect(16, y, width - 32, 24),
            options: metrics.map(\.title),
            selected: metrics.firstIndex(of: trendsMetric) ?? 0,
            tinted: true
        ) { [weak self] index in
            self?.trendsMetric = metrics[index]
        }
        y += 10

        y += drawDailyChart(
            canvas, rect: Rect(16, y, width - 32, 92), days: window, metric: trendsMetric)
        y += 14

        canvas.separator(y: y, from: 16, to: width - 16)
        y += 12

        // A "≥" rather than a quietly-too-low number: some models have no
        // published rate, and their tokens are excluded.
        let costLabel = totals.uncostedTokens > 0 ? "Est. cost (partial)" : "Est. cost"
        let costValue =
            totals.uncostedTokens > 0
            ? "≥ \(Format.cost(totals.cost))" : Format.cost(totals.cost)
        y += drawStatTiles(
            canvas, rect: Rect(16, y, width - 32, 34),
            tiles: [
                (
                    label: "Per active day",
                    value: Format.tokens(totals.averageTokensPerActiveDay), unit: nil
                ),
                (label: "Active days", value: "\(totals.activeDays)", unit: nil),
                (label: costLabel, value: costValue, unit: nil),
            ])

        return y - top + 16
    }

    // MARK: Daily chart

    private func drawDailyChart(
        _ canvas: Canvas, rect: Rect, days: [DayUsage], metric: TrendsMetric
    ) -> Double {
        let palette = canvas.palette
        let cr = canvas.cr
        let plot = Rect(rect.x + 30, rect.y, rect.width - 30, rect.height - 12)
        let peak = max(days.map { value(of: $0, metric: metric) }.max() ?? 1, 1)

        for level in [0.0, 0.5, 1.0] {
            let y = plot.maxY - plot.height * level
            canvas.setColor(palette.primary.opacity(0.07))
            cairo_set_line_width(cr, 1)
            cairo_move_to(cr, plot.x, y)
            cairo_line_to(cr, plot.maxX, y)
            cairo_stroke(cr)
            canvas.text(
                format(peak * level, metric: metric), at: Point(plot.x - 4, y - 5), size: 8,
                color: palette.tertiaryText, align: .trailing)
        }

        guard !days.isEmpty else { return rect.height }
        let slot = plot.width / Double(days.count)

        for (index, day) in days.enumerated() {
            let height = plot.height * value(of: day, metric: metric) / peak
            guard height > 0 else { continue }
            canvas.fillRounded(
                Rect(
                    plot.x + slot * Double(index) + 0.5, plot.maxY - height, max(slot - 1, 1),
                    height),
                radius: 1.5, palette.accent.opacity(0.75))
        }

        // A seven-day trailing mean, so the shape of a habit shows through the
        // daily noise. Weekends alone can halve a bar.
        if days.count >= 7 {
            canvas.setColor(palette.rollingAverage)
            cairo_set_line_width(cr, 1.4)
            var started = false
            for index in days.indices.dropFirst(6) {
                let mean =
                    days[(index - 6)...index].map { value(of: $0, metric: metric) }.reduce(0, +) / 7
                let point = Point(
                    plot.x + slot * (Double(index) + 0.5), plot.maxY - plot.height * mean / peak)
                if started {
                    cairo_line_to(cr, point.x, point.y)
                } else {
                    cairo_move_to(cr, point.x, point.y)
                    started = true
                }
            }
            cairo_stroke(cr)
        }

        // Four date labels across the range.
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let stride = max(days.count / 4, 1)
        for index in Swift.stride(from: 0, to: days.count, by: stride) {
            canvas.text(
                formatter.string(from: days[index].date),
                at: Point(plot.x + slot * (Double(index) + 0.5), plot.maxY + 2), size: 8,
                color: palette.tertiaryText, align: .center)
        }

        return rect.height
    }

    private func value(of day: DayUsage, metric: TrendsMetric) -> Double {
        switch metric {
        case .tokens: Double(day.billableTokens)
        case .messages: Double(day.messages)
        case .sessions: Double(day.sessionCount)
        case .cost: day.cost
        }
    }

    private func format(_ value: Double, metric: TrendsMetric) -> String {
        switch metric {
        case .tokens: Format.tokens(Int(value))
        case .messages, .sessions: Format.compact(Int(value))
        case .cost: Format.cost(value)
        }
    }

    // MARK: Segmented control

    /// The small segmented control the panel uses for ranges and metrics.
    @discardableResult
    func drawSegmented(
        _ canvas: Canvas, rect: Rect, options: [String], selected: Int, tinted: Bool = false,
        onSelect: @escaping (Int) -> Void
    ) -> Double {
        let palette = canvas.palette
        canvas.fillRounded(rect, radius: 8, palette.controlBackground)
        let inner = rect.inset(by: 2)
        let slot = inner.width / Double(options.count)

        for (index, option) in options.enumerated() {
            let slotRect = Rect(inner.x + slot * Double(index), inner.y, slot, inner.height)
            let isSelected = index == selected
            if isSelected {
                canvas.fillRounded(
                    slotRect, radius: 6,
                    tinted ? palette.accent.opacity(0.22) : palette.selectedControl)
            }
            canvas.text(
                option, at: Point(slotRect.midX, slotRect.midY - 6.5), size: 11,
                color: isSelected ? palette.primary : palette.secondaryText, align: .center)
            addHit(slotRect) { onSelect(index) }
        }
        return rect.height
    }
}
