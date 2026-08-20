import CLinuxTray
import Foundation
import RationKit

/// Live plan limits, and whether the current window survives them.
extension Panel {

    func drawUsageTab(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        guard let entry = app.entry(for: selectedProviderID) else {
            guard app.registry.isEverythingHidden else {
                return drawStatusMessage(
                    canvas, width: width, top: top, symbol: "questionmark.circle",
                    title: "Nothing to show",
                    message: "No supported tool was found on this machine.")
            }
            return drawStatusMessage(
                canvas, width: width, top: top, symbol: "eye.slash",
                title: "Everything is hidden",
                message:
                    "You have turned off every account, so Ration is not reading anything. "
                    + "Turn one back on to see your usage.",
                action: ("Open Accounts", { [weak self] in self?.app.openSettings() }))
        }

        let poller = entry.poller
        let provider = entry.provider

        if !app.isSetUp {
            return drawStatusMessage(
                canvas, width: width, top: top,
                symbol: "hand.wave", title: "Finish setting up",
                message:
                    "Ration reads the \(provider.toolName) session already stored on this machine. "
                    + "Nothing is sent anywhere but the host that issued it.",
                action: ("Set up Ration", { [weak self] in self?.app.completeOnboarding() }))
        }

        if case .quotaNotReadable(let reason) = poller.availability {
            return drawStatusMessage(
                canvas, width: width, top: top,
                symbol: "eye.slash", title: "\(provider.displayName) can't be metered",
                message: reason)
        }

        if poller.state.status == .signedOut {
            return drawStatusMessage(
                canvas, width: width, top: top,
                symbol: "person.crop.circle.badge.exclamationmark", title: "Signed out",
                message:
                    "Ration reads the session \(provider.toolName) already has. Open "
                    + "\(provider.toolName) and sign in, then try again.",
                tint: canvas.palette.warning,
                action: ("Try again", { poller.refreshNow() }))
        }

        if let snapshot = poller.state.snapshot, !snapshot.limits.isEmpty {
            return drawLimits(
                canvas, width: width, top: top, snapshot: snapshot, entry: entry, now: now)
        }

        if poller.state.snapshot != nil {
            return drawStatusMessage(
                canvas, width: width, top: top,
                symbol: "gauge.with.dots.needle.0percent", title: "No limits reported",
                message: "This account has no usage limits to show.")
        }

        if case .failed(let error) = poller.state.status {
            // A provider read from files cannot fail to be *reached*, so
            // offering "can't reach the network" for one would be nonsense.
            let readsFromDisk: Bool
            switch error {
            case .noData, .unavailable: readsFromDisk = true
            default: readsFromDisk = false
            }
            return drawStatusMessage(
                canvas, width: width, top: top,
                symbol: readsFromDisk ? "circle.dotted" : "wifi.slash",
                title: readsFromDisk
                    ? "Nothing recorded yet" : "Can't reach \(provider.displayName)",
                message: error.errorDescription ?? "Something went wrong.",
                action: error.isRetryable ? ("Retry", { poller.refreshNow() }) : nil)
        }

        return drawStatusMessage(
            canvas, width: width, top: top,
            symbol: "circle.dotted", title: "Loading",
            message: "Fetching your current usage…")
    }

    // MARK: Limits

    private func drawLimits(
        _ canvas: Canvas, width: Double, top: Double, snapshot: UsageSnapshot,
        entry: ProviderRegistry.Entry, now: Date
    ) -> Double {
        var y = top
        let hero = heroLimit(in: snapshot)
        let rest = snapshot.limits.filter { $0.id != hero?.id }

        if let hero {
            y += 20
            drawRing(
                canvas, center: Point(width / 2, y + 58), percent: hero.percent,
                severity: hero.severity)
            y += 116 + 10

            canvas.text(
                hero.displayName, at: Point(width / 2, y), size: 12, weight: .bold,
                align: .center)
            y += 17
            if let resetsAt = hero.resetsAt {
                canvas.text(
                    RelativeTime.sentence(until: resetsAt, from: now),
                    at: Point(width / 2, y), size: 11, color: canvas.palette.secondaryText,
                    align: .center)
                y += 16
            }
            y += 18
        }

        for limit in rest {
            y += drawLimitRow(
                canvas, rect: Rect(6, y, width - 12, 0), limit: limit, now: now,
                isSelected: focusedLimitID == limit.id)
            y += 2
        }
        if !rest.isEmpty { y += 6 }

        if let projection = WindowProjection(limit: hero ?? snapshot.limits[0], now: now) {
            canvas.separator(y: y, from: 16, to: width - 16)
            y += 10
            y += drawProjection(
                canvas, rect: Rect(16, y, width - 32, 0), projection: projection,
                history: entry.history?.history ?? UsageHistory(), provider: entry.provider,
                now: now)
        }

        if let spend = snapshot.spend, spend.isEnabled {
            canvas.separator(y: y, from: 16, to: width - 16)
            y += 10
            y += drawSpend(canvas, rect: Rect(16, y, width - 32, 0), spend: spend)
        }

        return y - top + 6
    }

    /// The limit the user clicked, else the one they configured, else the worst.
    private func heroLimit(in snapshot: UsageSnapshot) -> UsageLimit? {
        if let focusedLimitID,
            let focused = snapshot.limits.first(where: { $0.id == focusedLimitID })
        {
            return focused
        }
        return MenuBarPresentation.select(mode: app.config.displayMode, from: snapshot)
            ?? snapshot.primaryLimit
    }

    /// The headline ring: a 116pt dial with an 11pt stroke, the reading in the
    /// middle.
    private func drawRing(_ canvas: Canvas, center: Point, percent: Double, severity: Severity) {
        let radius = 58.0 - 11.0 / 2
        canvas.ring(center: center, radius: radius, width: 11, canvas.palette.track)
        let tint = accentColor(for: severity, palette: canvas.palette)
        canvas.arc(
            center: center, radius: radius, fraction: min(max(percent, 0), 100) / 100, width: 11,
            tint)

        let value = "\(Int(min(max(percent, 0), 100).rounded(.down)))"
        let valueWidth = canvas.width(value, size: 33, weight: .bold)
        let unitWidth = canvas.width("%", size: 17, weight: .bold)
        let startX = center.x - (valueWidth + unitWidth) / 2
        canvas.text(value, at: Point(startX, center.y - 22), size: 33, weight: .bold)
        canvas.text(
            "%", at: Point(startX + valueWidth, center.y - 12), size: 17, weight: .bold,
            color: canvas.palette.secondaryText)
    }

    /// One limit as a labelled bar. Clicking promotes it into the ring above.
    private func drawLimitRow(
        _ canvas: Canvas, rect: Rect, limit: UsageLimit, now: Date, isSelected: Bool
    ) -> Double {
        let hasReset = limit.resetsAt != nil
        let height = hasReset ? 62.0 : 46.0
        let row = Rect(rect.x, rect.y, rect.width, height)
        if isHovered(row) {
            canvas.fillRounded(row, radius: 8, canvas.palette.hover)
        }

        let palette = canvas.palette
        let percentText = MenuBarPresentation.percentText(limit.percent)
        let percentWidth = canvas.width(percentText, size: 12, weight: .medium)
        let nameMax = row.width - 20 - percentWidth - 20

        var nameX = row.x + 10
        if isSelected {
            canvas.circle(
                center: Point(nameX + 4, row.y + 14), radius: 4.5,
                accentColor(for: limit.severity, palette: palette))
            nameX += 13
        }
        canvas.text(
            canvas.truncated(limit.displayName, size: 12, maxWidth: nameMax),
            at: Point(nameX, row.y + 8), size: 12)
        canvas.text(
            percentText, at: Point(row.maxX - 10, row.y + 8), size: 12, weight: .medium,
            color: severityColor(limit.severity, palette: palette) ?? palette.secondaryText,
            align: .trailing)

        drawLimitBar(
            canvas, rect: Rect(row.x + 10, row.y + 28, row.width - 20, 6),
            percent: limit.percent, severity: limit.severity)

        if let resetsAt = limit.resetsAt {
            canvas.text(
                RelativeTime.sentence(until: resetsAt, from: now),
                at: Point(row.x + 10, row.y + 40), size: 10.5, color: palette.tertiaryText)
        }

        addHit(row) { [weak self] in
            guard let self else { return }
            self.focusedLimitID = self.focusedLimitID == limit.id ? nil : limit.id
        }
        return height
    }

    func drawLimitBar(_ canvas: Canvas, rect: Rect, percent: Double, severity: Severity) {
        canvas.fillRounded(rect, radius: rect.height / 2, canvas.palette.track)
        let fraction = min(max(percent, 0), 100) / 100
        guard fraction > 0 else { return }
        let filled = max(rect.width * fraction, rect.height)
        canvas.fillRounded(
            Rect(rect.x, rect.y, filled, rect.height), radius: rect.height / 2,
            accentColor(for: severity, palette: canvas.palette))
    }

    // MARK: Projection

    /// "At this rate, do I run out before the window resets?"
    private func drawProjection(
        _ canvas: Canvas, rect: Rect, projection: WindowProjection, history: UsageHistory,
        provider: Provider, now: Date
    ) -> Double {
        let palette = canvas.palette
        var y = rect.y

        canvas.text(
            projection.limit.displayName, at: Point(rect.x, y), size: 10.5, weight: .bold,
            color: palette.secondaryText)

        // Pace badge, right-aligned against the verdict.
        let pace = String(format: "%.1f×", projection.pace)
        canvas.text(
            pace, at: Point(rect.maxX, y), size: 14, weight: .bold,
            color: severityColor(projection.severity, palette: palette) ?? palette.primary,
            align: .trailing)
        canvas.text(
            "pace", at: Point(rect.maxX, y + 17), size: 8, color: palette.tertiaryText,
            align: .trailing)
        y += 14

        let verdictWidth = rect.width - 44
        y += canvas.paragraph(
            projection.verdict(now: now), at: Point(rect.x, y), width: verdictWidth, size: 12,
            weight: .medium,
            color: severityColor(projection.severity, palette: palette) ?? palette.primary)
        y += 8

        let chart = Rect(rect.x, y, rect.width, 84)
        drawProjectionChart(
            canvas, rect: chart, projection: projection, history: history, now: now)
        y += chart.height + 6

        y += canvas.paragraph(
            "Shape from your local history, scaled to the percentage \(provider.displayName) "
                + "reports. The dashed line assumes you keep going at the current rate.",
            at: Point(rect.x, y), width: rect.width, size: 9, color: palette.tertiaryText)

        return y - rect.y + 8
    }

    private func drawProjectionChart(
        _ canvas: Canvas, rect: Rect, projection: WindowProjection, history: UsageHistory,
        now: Date
    ) {
        let cr = canvas.cr
        let palette = canvas.palette
        let plot = Rect(rect.x + 22, rect.y, rect.width - 22, rect.height - 12)

        let maxY = max(110, projection.projectedPercent * 1.05)
        let start = now.addingTimeInterval(-projection.elapsed)
        let resetsAt = now.addingTimeInterval(projection.remaining)
        let span = resetsAt.timeIntervalSince(start)

        func point(_ date: Date, _ percent: Double) -> Point {
            let tx = span > 0 ? date.timeIntervalSince(start) / span : 0
            return Point(
                plot.x + plot.width * min(max(tx, 0), 1),
                plot.maxY - plot.height * min(max(percent / maxY, 0), 1))
        }

        // Y axis: 0, 50, 100.
        for value in [0.0, 50.0, 100.0] {
            let p = point(start, value)
            canvas.setColor(palette.primary.opacity(0.08))
            cairo_set_line_width(cr, 1)
            cairo_move_to(cr, plot.x, p.y)
            cairo_line_to(cr, plot.maxX, p.y)
            cairo_stroke(cr)
            canvas.text(
                "\(Int(value))%", at: Point(plot.x - 4, p.y - 5), size: 8,
                color: palette.tertiaryText, align: .trailing)
        }

        // What has actually happened, shaped by local history.
        let curve = history.windowCurve(for: projection, now: now)
        if curve.count > 1 {
            let points = curve.map { point($0.date, $0.percent) }
            // Area under the line.
            cairo_move_to(cr, points[0].x, plot.maxY)
            for p in points { cairo_line_to(cr, p.x, p.y) }
            cairo_line_to(cr, points[points.count - 1].x, plot.maxY)
            cairo_close_path(cr)
            if let gradient = cairo_pattern_create_linear(0, plot.y, 0, plot.maxY) {
                let accent = palette.accent
                cairo_pattern_add_color_stop_rgba(gradient, 0, accent.r, accent.g, accent.b, 0.35)
                cairo_pattern_add_color_stop_rgba(gradient, 1, accent.r, accent.g, accent.b, 0.02)
                cairo_set_source(cr, gradient)
                cairo_fill(cr)
                cairo_pattern_destroy(gradient)
            } else {
                canvas.setColor(palette.accent.opacity(0.2))
                cairo_fill(cr)
            }

            canvas.setColor(palette.accent)
            cairo_set_line_width(cr, 1.8)
            cairo_move_to(cr, points[0].x, points[0].y)
            for p in points.dropFirst() { cairo_line_to(cr, p.x, p.y) }
            cairo_stroke(cr)
        }

        // Where the current rate leads. Dashed, because it is a guess.
        let from = point(now, projection.percentUsed)
        let to = point(resetsAt, projection.projectedPercent)
        canvas.setColor(
            (severityColor(projection.severity, palette: palette) ?? palette.accent).opacity(0.9))
        cairo_set_line_width(cr, 1.6)
        let forecastDash: [Double] = [4, 3]
        forecastDash.withUnsafeBufferPointer { buffer in
            cairo_set_dash(cr, buffer.baseAddress, 2, 0)
        }
        cairo_move_to(cr, from.x, from.y)
        cairo_line_to(cr, to.x, to.y)
        cairo_stroke(cr)

        // The ceiling.
        let ceiling = point(start, 100)
        canvas.setColor(palette.critical.opacity(0.55))
        cairo_set_line_width(cr, 1)
        let ceilingDash: [Double] = [2, 3]
        ceilingDash.withUnsafeBufferPointer { buffer in
            cairo_set_dash(cr, buffer.baseAddress, 2, 0)
        }
        cairo_move_to(cr, plot.x, ceiling.y)
        cairo_line_to(cr, plot.maxX, ceiling.y)
        cairo_stroke(cr)
        cairo_set_dash(cr, nil, 0, 0)

        // You are here.
        let marker = point(now, 0)
        canvas.setColor(palette.chartRule)
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, marker.x, plot.y)
        cairo_line_to(cr, marker.x, plot.maxY)
        cairo_stroke(cr)

        // Where it runs out, when it does.
        if let exhaustedAt = projection.exhaustedAt {
            canvas.circle(center: point(exhaustedAt, 100), radius: 3.4, palette.critical)
        }

        canvas.text(
            "start", at: Point(plot.x, plot.maxY + 2), size: 8, color: palette.tertiaryText)
        canvas.text(
            "reset", at: Point(plot.maxX, plot.maxY + 2), size: 8, color: palette.tertiaryText,
            align: .trailing)
    }

    // MARK: Spend

    /// Pay-as-you-go credits, shown only when the account actually uses them.
    private func drawSpend(_ canvas: Canvas, rect: Rect, spend: UsageSnapshot.Spend) -> Double {
        let palette = canvas.palette
        canvas.text(
            "Extra usage", at: Point(rect.x, rect.y), size: 11, color: palette.secondaryText)
        canvas.text(
            spendText(spend), at: Point(rect.maxX, rect.y), size: 11, weight: .medium,
            color: severityColor(spend.severity, palette: palette) ?? palette.secondaryText,
            align: .trailing)
        return 26
    }

    private func spendText(_ spend: UsageSnapshot.Spend) -> String {
        let used = NSDecimalNumber(decimal: spend.usedAmount).doubleValue
        let symbol = currencySymbol(spend.currencyCode)
        guard let limit = spend.limitAmount else {
            return String(format: "%@%.2f", symbol, used)
        }
        let cap = NSDecimalNumber(decimal: limit).doubleValue
        return String(format: "%@%.2f of %@%.2f", symbol, used, symbol, cap)
    }

    private func currencySymbol(_ code: String?) -> String {
        switch code?.uppercased() {
        case "USD", nil: "$"
        case "EUR": "€"
        case "GBP": "£"
        case let other?: "\(other) "
        }
    }

    // MARK: Empty and error states

    func drawStatusMessage(
        _ canvas: Canvas, width: Double, top: Double, symbol: String, title: String,
        message: String, tint: RGBA? = nil, action: (String, () -> Void)? = nil
    ) -> Double {
        let palette = canvas.palette
        var y = top + 28
        Glyph.draw(
            symbol, in: Rect(width / 2 - 14, y, 28, 28), on: canvas,
            color: tint ?? palette.secondaryText)
        y += 40

        canvas.text(title, at: Point(width / 2, y), size: 13, weight: .bold, align: .center)
        y += 22

        y += canvas.paragraph(
            message, at: Point(28, y), width: width - 56, size: 11,
            color: palette.secondaryText, align: .center)
        y += 14

        if let (label, handler) = action {
            let buttonWidth = canvas.width(label, size: 11, weight: .medium) + 26
            let button = Rect(width / 2 - buttonWidth / 2, y, buttonWidth, 26)
            canvas.fillRounded(
                button, radius: 7,
                isHovered(button) ? palette.accent.opacity(0.28) : palette.accent.opacity(0.18))
            canvas.text(
                label, at: Point(button.midX, button.y + 6), size: 11, weight: .medium,
                color: palette.accent, align: .center)
            addHit(button) { handler() }
            y += 34
        }

        return y - top + 24
    }

    // MARK: Colour helpers

    func severityColor(_ severity: Severity, palette: Palette) -> RGBA? {
        switch severity {
        case .normal: nil
        case .warning: palette.warning
        case .critical: palette.critical
        }
    }

    /// Always safe to draw with: falls back to the accent when there is
    /// nothing to warn about.
    func accentColor(for severity: Severity, palette: Palette) -> RGBA {
        severityColor(severity, palette: palette) ?? palette.accent
    }
}
