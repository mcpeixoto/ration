import Foundation
import RationKit

/// Where the tokens went — by model and by project.
extension Panel {

    func drawDetailTab(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        let entry = app.entry(for: selectedProviderID)
        let history = entry?.history?.history ?? UsageHistory()
        let status = entry?.history?.status ?? .ready
        let provider = entry?.provider ?? .claude

        if case .scanning(let progress) = status {
            return drawScanning(canvas, width: width, top: top, progress: progress)
        }
        if history.isEmpty {
            return drawStatusMessage(
                canvas, width: width, top: top, symbol: "chart.pie.fill",
                title: "No history yet",
                message: "Breakdowns appear once you have used \(provider.toolName).")
        }

        let window = history.window(days: detailDays, endingOn: now)
        let totals = history.total(over: window)
        var y = top + 12

        y += drawSegmented(
            canvas, rect: Rect(16, y, width - 32, 24),
            options: Self.ranges.map { "\($0) days" },
            selected: Self.ranges.firstIndex(of: detailDays) ?? 1,
            tinted: true
        ) { [weak self] index in
            self?.detailDays = Self.ranges[index]
        }
        y += 16

        y += drawBreakdown(
            canvas, rect: Rect(16, y, width - 32, 0), title: "Models",
            entries: totals.rankedModels, total: totals.tokens)
        y += 10

        canvas.separator(y: y, from: 16, to: width - 16)
        y += 12

        y += drawBreakdown(
            canvas, rect: Rect(16, y, width - 32, 0), title: "Projects",
            entries: Array(totals.rankedProjects.prefix(6)), total: totals.tokens)

        return y - top + 14
    }

    private func drawBreakdown(
        _ canvas: Canvas, rect: Rect, title: String, entries: [(name: String, tokens: Int)],
        total: Int
    ) -> Double {
        let palette = canvas.palette
        var y = rect.y
        canvas.text(
            title, at: Point(rect.x, y), size: 11, weight: .bold, color: palette.secondaryText)
        y += 18

        guard !entries.isEmpty else {
            canvas.text(
                "Nothing in this period.", at: Point(rect.x, y), size: 11,
                color: palette.tertiaryText)
            return y - rect.y + 16
        }

        for entry in entries {
            let share = total > 0 ? Double(entry.tokens) / Double(total) : 0
            y += drawShareRow(
                canvas, rect: Rect(rect.x, y, rect.width, 0), name: entry.name,
                tokens: entry.tokens, share: share)
            y += 6
        }
        return y - rect.y
    }

    /// One model or project, with its share of the window's tokens.
    private func drawShareRow(
        _ canvas: Canvas, rect: Rect, name: String, tokens: Int, share: Double
    ) -> Double {
        let palette = canvas.palette
        let percent = "\(Int((share * 100).rounded()))%"
        let tokenText = Format.tokens(tokens)
        let percentWidth = 30.0
        let tokenWidth = canvas.width(tokenText, size: 11, weight: .medium)
        let nameMax = rect.width - percentWidth - tokenWidth - 16

        canvas.text(
            middleTruncated(name, on: canvas, size: 11, maxWidth: nameMax),
            at: Point(rect.x, rect.y), size: 11)
        canvas.text(
            tokenText, at: Point(rect.maxX - percentWidth - 6, rect.y), size: 11, weight: .medium,
            color: palette.secondaryText, align: .trailing)
        canvas.text(
            percent, at: Point(rect.maxX, rect.y), size: 10, color: palette.tertiaryText,
            align: .trailing)

        let bar = Rect(rect.x, rect.y + 17, rect.width, 4)
        canvas.fillRounded(bar, radius: 2, palette.track)
        canvas.fillRounded(
            Rect(bar.x, bar.y, max(bar.width * share * entrance, 4), bar.height), radius: 2,
            palette.accent)
        return 23
    }

    /// Project paths differ at the end, so the middle is what gives.
    private func middleTruncated(
        _ string: String, on canvas: Canvas, size: Double, maxWidth: Double
    ) -> String {
        guard canvas.width(string, size: size) > maxWidth else { return string }
        var characters = Array(string)
        while characters.count > 4 {
            characters.remove(at: characters.count / 2)
            let candidate =
                String(characters[..<(characters.count / 2)]) + "…"
                + String(characters[(characters.count / 2)...])
            if canvas.width(candidate, size: size) <= maxWidth { return candidate }
        }
        return String(characters)
    }
}
