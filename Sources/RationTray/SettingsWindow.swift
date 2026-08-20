import CLinuxTray
import Foundation
import RationKit

/// Settings: General, Accounts, and About — the three tabs the macOS Settings
/// window has, stacked in one scrolling window.
@MainActor
final class SettingsWindow {

    private let app: TrayApp
    private var window: Widget?
    private var area: Widget?
    private(set) var isOpen = false

    private var hitRegions: [(rect: Rect, action: () -> Void)] = []
    private var pointer = Point(-1, -1)
    /// Logical units per pixel; see `UIScale`.
    private var scale = 1.0
    private var scroll = 0.0
    private var contentHeight = 0.0
    private var section: Section = .general

    private let width = 460.0
    private let height = 560.0

    enum Section: String, CaseIterable {
        case general = "General"
        case accounts = "Accounts"
        case about = "About"
    }

    init(app: TrayApp) {
        self.app = app
    }

    // MARK: Window

    func open(on section: Section? = nil) {
        if let section { self.section = section }
        if window == nil { build() }
        guard let window else { return }
        isOpen = true
        gtk_widget_show_all(window)
        gtk_window_present(window)
        redraw()
    }

    func close() {
        isOpen = false
        if let window { gtk_widget_hide(window) }
    }

    /// Re-creates the window at the new size. A GTK window cannot be resized
    /// out from under a drawing area mid-frame without the next frame being
    /// laid out against the old allocation, so the whole thing is rebuilt.
    func rebuild() {
        let wasOpen = isOpen
        if let window { gtk_widget_destroy(window) }
        window = nil
        area = nil
        isOpen = false
        if wasOpen { open() }
    }

    func redraw() {
        guard let area, isOpen else { return }
        gtk_widget_queue_draw(area)
    }

    private func build() {
        let window = gtk_window_new(0)
        gtk_window_set_title(window, "Ration Settings")
        scale = UIScale.factor(override: app.config.uiScale)
        gtk_window_set_default_size(
            window, Int32((width * scale).rounded()), Int32((height * scale).rounded()))
        gtk_window_set_resizable(window, 0)

        let area = gtk_drawing_area_new()
        gtk_widget_add_events(area, EventMask.panel)
        gtk_container_add(window, area)

        onDraw(area) { [weak self] cr in
            self?.draw(cr: cr)
        }
        onButtonPress(area) { [weak self] event in
            guard let self else { return false }
            let point = Point(event.x / self.scale, event.y / self.scale)
            for region in self.hitRegions.reversed() where region.rect.contains(point) {
                region.action()
                self.redraw()
                return true
            }
            return false
        }
        onMotion(area) { [weak self] event in
            guard let self else { return false }
            self.pointer = Point(event.x / self.scale, event.y / self.scale)
            self.redraw()
            return false
        }
        onScroll(area) { [weak self] event in
            guard let self else { return false }
            let limit = max(0, self.contentHeight - self.height)
            self.scroll = min(max(self.scroll + event.scrollDelta * 48, 0), limit)
            self.redraw()
            return true
        }
        // The close button destroys the window by default; hide it instead so
        // reopening Settings does not have to rebuild everything.
        onSignal(window, "delete-event") { [weak self] in
            self?.close()
        }

        self.window = window
        self.area = area
    }

    // MARK: Drawing

    private func draw(cr: OpaquePointer) {
        hitRegions.removeAll(keepingCapacity: true)
        let palette = Palette.current()
        cairo_scale(cr, scale, scale)
        let canvas = Canvas(cr: cr, palette: palette)
        canvas.fill(Rect(0, 0, width, height), palette.background)

        var y = 14.0
        y += drawSectionPicker(canvas, top: y)
        y += 10

        canvas.clipped(to: Rect(0, y, width, height - y)) {
            let top = y - scroll
            let used: Double
            switch section {
            case .general: used = drawGeneral(canvas, top: top)
            case .accounts: used = drawAccounts(canvas, top: top)
            case .about: used = drawAbout(canvas, top: top)
            }
            contentHeight = y + used + 20
        }
    }

    private func drawSectionPicker(_ canvas: Canvas, top: Double) -> Double {
        let palette = canvas.palette
        let rect = Rect(16, top, width - 32, 28)
        canvas.fillRounded(rect, radius: 8, palette.controlBackground)
        let inner = rect.inset(by: 2)
        let slot = inner.width / Double(Section.allCases.count)
        for (index, candidate) in Section.allCases.enumerated() {
            let slotRect = Rect(inner.x + slot * Double(index), inner.y, slot, inner.height)
            if candidate == section {
                canvas.fillRounded(slotRect, radius: 6, palette.selectedControl)
            }
            canvas.text(
                candidate.rawValue, at: Point(slotRect.midX, slotRect.midY - 7), size: 12,
                color: candidate == section ? palette.primary : palette.secondaryText,
                align: .center)
            addHit(slotRect) { [weak self] in
                self?.section = candidate
                self?.scroll = 0
            }
        }
        return rect.height
    }

    // MARK: General

    private func drawGeneral(_ canvas: Canvas, top: Double) -> Double {
        let palette = canvas.palette
        var y = top
        let inset = 20.0
        let contentWidth = width - inset * 2

        y += drawLabel(canvas, "Tray shows", at: Point(inset, y))
        let modes = MenuBarDisplayMode.allCases
        y += drawChoice(
            canvas, rect: Rect(inset, y, contentWidth, 26), options: modes.map(\.title),
            selected: modes.firstIndex(of: app.config.displayMode) ?? 0
        ) { [weak self] index in
            self?.app.update { $0.displayMode = modes[index] }
        }
        y += 6
        y += canvas.paragraph(
            app.config.displayMode.explanation, at: Point(inset, y), width: contentWidth,
            size: 10.5, color: palette.secondaryText)
        y += 16

        y += drawToggle(
            canvas, rect: Rect(inset, y, contentWidth, 22), title: "Show a weekly usage bar",
            detail: "A small bar beside the icon, filling up as the week's allowance is spent.",
            isOn: app.config.showWeeklyBar
        ) { [weak self] value in
            self?.app.update { $0.showWeeklyBar = value }
        }

        y += drawToggle(
            canvas, rect: Rect(inset, y, contentWidth, 22), title: "Colour when close to a limit",
            detail: "Turns amber past 80% and red past 90%.",
            isOn: app.config.useSeverityColor
        ) { [weak self] value in
            self?.app.update { $0.useSeverityColor = value }
        }

        canvas.separator(y: y, from: inset, to: width - inset)
        y += 14

        y += drawLabel(canvas, "Size", at: Point(inset, y))
        let scales: [Double] = [0, 1, 1.25, 1.5, 2]
        let scaleLabels = ["Automatic", "100%", "125%", "150%", "200%"]
        y += drawChoice(
            canvas, rect: Rect(inset, y, contentWidth, 26), options: scaleLabels,
            selected: scales.firstIndex(of: app.config.uiScale) ?? 0
        ) { [weak self] index in
            self?.app.update { $0.uiScale = scales[index] }
            self?.rebuild()
        }
        y += 6
        y += canvas.paragraph(
            "Automatic reads the display's density and your text-size setting. "
                + "A point is a physical size on a Mac; on Linux it is whatever the "
                + "screen makes of it, so this is the knob that stands in for that.",
            at: Point(inset, y), width: contentWidth, size: 10.5, color: palette.secondaryText)
        y += 16

        canvas.separator(y: y, from: inset, to: width - inset)
        y += 14

        y += drawLabel(canvas, "Check every", at: Point(inset, y))
        let intervals: [TimeInterval] = [60, 120, 300]
        y += drawChoice(
            canvas, rect: Rect(inset, y, contentWidth, 26),
            options: intervals.map(intervalLabel),
            selected: intervals.firstIndex(of: app.config.pollInterval) ?? 0
        ) { [weak self] index in
            self?.app.update { $0.pollInterval = intervals[index] }
        }
        y += 6
        y += canvas.paragraph(
            "Once a minute is the fastest Ration will check. Each tick reads every account "
                + "you have switched on.",
            at: Point(inset, y), width: contentWidth, size: 10.5, color: palette.secondaryText)
        y += 16

        y += drawToggle(
            canvas, rect: Rect(inset, y, contentWidth, 22),
            title: "Notify me when I approach a limit",
            detail: "Desktop alerts at 80% and 95%, through notify-send.",
            isOn: app.config.notifyOnThresholds
        ) { [weak self] value in
            self?.app.update { $0.notifyOnThresholds = value }
        }

        y += drawToggle(
            canvas, rect: Rect(inset, y, contentWidth, 22), title: "Open at login",
            detail: "Starts the tray with your desktop session, via an XDG autostart entry.",
            isOn: Autostart.isEnabled
        ) { value in
            Autostart.setEnabled(value)
        }

        if let error = Autostart.lastError {
            y += canvas.paragraph(
                error, at: Point(inset, y), width: contentWidth, size: 10.5,
                color: palette.critical)
            y += 8
        }

        canvas.separator(y: y, from: inset, to: width - inset)
        y += 14
        y += canvas.paragraph(
            "Updates are not automatic on Linux. Ration checks GitHub for a newer release and "
                + "tells you; installing it is a download you run yourself.",
            at: Point(inset, y), width: contentWidth, size: 10.5, color: palette.secondaryText)
        y += 8

        let checkWidth = canvas.width("Check for updates", size: 11, weight: .medium) + 24
        let button = Rect(inset, y, checkWidth, 26)
        canvas.fillRounded(
            button, radius: 7,
            isHovered(button) ? palette.accent.opacity(0.3) : palette.accent.opacity(0.18))
        canvas.text(
            "Check for updates", at: Point(button.midX, button.y + 6), size: 11, weight: .medium,
            color: palette.accent, align: .center)
        addHit(button) { [weak self] in
            self?.checkForUpdates()
        }
        if let status = updateStatus {
            canvas.text(
                status, at: Point(button.maxX + 12, y + 7), size: 10.5,
                color: palette.secondaryText)
        }
        y += 34

        return y - top
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(Int(seconds)) seconds"
            : "\(Int(seconds / 60)) minute\(seconds >= 120 ? "s" : "")"
    }

    // MARK: Accounts

    private func drawAccounts(_ canvas: Canvas, top: Double) -> Double {
        let palette = canvas.palette
        var y = top
        let inset = 20.0
        let contentWidth = width - inset * 2

        let selectable = app.registry.metered.map(\.provider)
        y += drawLabel(canvas, "Panel opens on", at: Point(inset, y))
        y += drawChoice(
            canvas, rect: Rect(inset, y, contentWidth, 26),
            options: selectable.map(\.displayName),
            selected: selectable.firstIndex(of: app.config.primaryProvider) ?? 0
        ) { [weak self] index in
            guard selectable.count > 1 else { return }
            self?.app.update { $0.primaryProvider = selectable[index] }
        }
        y += 6
        y += canvas.paragraph(
            "The tray reports every account that is on. The panel opens on this one — "
                + "switch at the top of it.",
            at: Point(inset, y), width: contentWidth, size: 10.5, color: palette.secondaryText)
        y += 14

        canvas.text(
            "ACCOUNTS", at: Point(inset, y), size: 9.5, weight: .bold,
            color: palette.tertiaryText)
        y += 18

        for entry in app.registry.entries where entry.availability.hasQuota {
            y += drawAccountRow(canvas, rect: Rect(inset, y, contentWidth, 0), entry: entry)
            y += 8
        }

        if app.registry.isEverythingHidden {
            y += canvas.paragraph(
                "Every account is off. Ration is not reading anything, and the tray shows no "
                    + "usage.",
                at: Point(inset, y), width: contentWidth, size: 10.5,
                color: palette.secondaryText)
            y += 10
        }

        let unmetered = app.registry.entries.filter { !$0.availability.hasQuota }
        if !unmetered.isEmpty {
            y += 6
            canvas.text(
                "NOT METERED", at: Point(inset, y), size: 9.5, weight: .bold,
                color: palette.tertiaryText)
            y += 18
            for entry in unmetered {
                Glyph.draw(
                    entry.provider.symbolName, in: Rect(inset, y + 1, 14, 14), on: canvas,
                    color: palette.tertiaryText)
                canvas.text(
                    entry.provider.toolName, at: Point(inset + 22, y), size: 11.5,
                    color: palette.secondaryText)
                y += 17
                y += canvas.paragraph(
                    entry.availability.explanation ?? "", at: Point(inset + 22, y),
                    width: contentWidth - 22, size: 10.5, color: palette.tertiaryText)
                y += 10
            }
        }

        return y - top
    }

    /// One metered account: what it is, what Ration reads for it, and a switch.
    private func drawAccountRow(
        _ canvas: Canvas, rect: Rect, entry: ProviderRegistry.Entry
    ) -> Double {
        let palette = canvas.palette
        let isEnabled = app.registry.isEnabled(entry.provider)
        var y = rect.y

        Glyph.draw(
            entry.provider.symbolName, in: Rect(rect.x, y + 1, 15, 15), on: canvas,
            color: isEnabled ? palette.accent : palette.secondaryText)

        // The plan is the only name Ration has for an account: the session the
        // tool stores carries no email and no account id.
        let plan = entry.poller.planName
        let title =
            plan.map { "\(entry.provider.toolName) — \($0.capitalized)" }
            ?? entry.provider.toolName
        canvas.text(title, at: Point(rect.x + 24, y), size: 11.5)

        let toggle = Rect(rect.maxX - 34, y, 34, 18)
        drawSwitch(canvas, rect: toggle, isOn: isEnabled)
        addHit(toggle) { [weak self] in
            guard let self else { return }
            let ids =
                isEnabled
                ? self.app.config.disabled.union([entry.provider.id])
                : self.app.config.disabled.subtracting([entry.provider.id])
            self.app.update { $0.disabledProviders = Array(ids) }
        }
        y += 17

        y += canvas.paragraph(
            detail(for: entry, isEnabled: isEnabled), at: Point(rect.x + 24, y),
            width: rect.width - 24 - 40, size: 10.5, color: palette.secondaryText)

        let source = sourceText(for: entry.provider)
        if !source.isEmpty {
            y += canvas.paragraph(
                source, at: Point(rect.x + 24, y), width: rect.width - 24 - 40, size: 10.5,
                color: palette.tertiaryText)
        }
        return y - rect.y
    }

    private func detail(for entry: ProviderRegistry.Entry, isEnabled: Bool) -> String {
        guard isEnabled else { return "Hidden, and not being read." }
        switch entry.availability {
        case .ready:
            if let percent = entry.poller.state.snapshot?.primaryLimit?.percent {
                return "\(Int(percent.rounded()))% of the current window used."
            }
            return "Ready."
        default:
            return entry.availability.explanation ?? "Ready."
        }
    }

    /// What Ration reads to produce the row above — shown regardless of the
    /// switch, because someone deciding whether to turn an account off is
    /// exactly who needs to know what reading it entails.
    private func sourceText(for provider: Provider) -> String {
        switch provider {
        case .claude:
            "Reads the Claude Code session stored in ~/.claude, and asks api.anthropic.com "
                + "for your limits."
        case .codex:
            "Reads the session files Codex already writes to disk. No request, no credential."
        case .cursor:
            "Reads the session Cursor already stored on disk, and asks api2.cursor.sh for "
                + "your limits."
        default:
            ""
        }
    }

    // MARK: About

    private func drawAbout(_ canvas: Canvas, top: Double) -> Double {
        let palette = canvas.palette
        var y = top + 20

        Glyph.draw(
            "gauge.with.dots.needle.67percent", in: Rect(width / 2 - 22, y, 44, 44), on: canvas,
            color: palette.accent)
        y += 56

        canvas.text("Ration", at: Point(width / 2, y), size: 16, weight: .bold, align: .center)
        y += 22
        canvas.text(
            "Version \(Ration.version)", at: Point(width / 2, y), size: 10.5,
            color: palette.secondaryText, align: .center)
        y += 24

        y += canvas.paragraph(
            "Ration reads the sessions your tools already stored — Claude Code in "
                + "~/.claude, Cursor in its local database, Codex in its session files — and "
                + "shows how much of each plan you have used. It collects no analytics and "
                + "stores nothing of yours on disk.",
            at: Point(40, y), width: width - 80, size: 11.5, color: palette.secondaryText,
            align: .center)
        y += 20

        let links = [
            ("Source", Links.repository),
            ("Privacy", Links.privacy),
            ("Buy me a coffee", Links.coffee),
        ]
        var x = 40.0
        let totalWidth =
            links.map { canvas.width($0.0, size: 11.5) }.reduce(0, +) + 32 * Double(links.count - 1)
        x = width / 2 - totalWidth / 2
        for (label, url) in links {
            let labelWidth = canvas.width(label, size: 11.5)
            let rect = Rect(x, y, labelWidth, 18)
            canvas.text(
                label, at: Point(x, y), size: 11.5,
                color: isHovered(rect) ? palette.primary : palette.accent)
            addHit(rect) { openInBrowser(url) }
            x += labelWidth + 32
        }
        y += 28

        y += canvas.paragraph(
            "Not affiliated with Anthropic, OpenAI, or Anysphere.", at: Point(40, y),
            width: width - 80, size: 10, color: palette.tertiaryText, align: .center)

        return y - top + 20
    }

    // MARK: Controls

    private func drawLabel(_ canvas: Canvas, _ text: String, at point: Point) -> Double {
        canvas.text(text, at: point, size: 11.5, weight: .medium)
        return 20
    }

    private func drawChoice(
        _ canvas: Canvas, rect: Rect, options: [String], selected: Int,
        onSelect: @escaping (Int) -> Void
    ) -> Double {
        let palette = canvas.palette
        canvas.fillRounded(rect, radius: 8, palette.controlBackground)
        let inner = rect.inset(by: 2)
        let slot = inner.width / Double(max(options.count, 1))
        for (index, option) in options.enumerated() {
            let slotRect = Rect(inner.x + slot * Double(index), inner.y, slot, inner.height)
            if index == selected {
                canvas.fillRounded(slotRect, radius: 6, palette.accent.opacity(0.22))
            }
            canvas.text(
                canvas.truncated(option, size: 11, maxWidth: slot - 8),
                at: Point(slotRect.midX, slotRect.midY - 7), size: 11,
                color: index == selected ? palette.primary : palette.secondaryText,
                align: .center)
            addHit(slotRect) { onSelect(index) }
        }
        return rect.height
    }

    private func drawToggle(
        _ canvas: Canvas, rect: Rect, title: String, detail: String, isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> Double {
        let palette = canvas.palette
        canvas.text(title, at: Point(rect.x, rect.y), size: 11.5)
        let toggle = Rect(rect.maxX - 34, rect.y, 34, 18)
        drawSwitch(canvas, rect: toggle, isOn: isOn)
        addHit(Rect(rect.x, rect.y - 2, rect.width, 22)) { onChange(!isOn) }

        var height = 20.0
        height += canvas.paragraph(
            detail, at: Point(rect.x, rect.y + height), width: rect.width - 44, size: 10.5,
            color: palette.secondaryText)
        return height + 12
    }

    private func drawSwitch(_ canvas: Canvas, rect: Rect, isOn: Bool) {
        let palette = canvas.palette
        canvas.fillRounded(
            rect, radius: rect.height / 2, isOn ? palette.accent : palette.primary.opacity(0.18))
        let knob = rect.height - 4
        canvas.circle(
            center: Point(isOn ? rect.maxX - 2 - knob / 2 : rect.x + 2 + knob / 2, rect.midY),
            radius: knob / 2, RGBA(1, 1, 1, isOn ? 1 : 0.75))
    }

    private func addHit(_ rect: Rect, _ action: @escaping () -> Void) {
        hitRegions.append((rect, action))
    }

    private func isHovered(_ rect: Rect) -> Bool {
        rect.contains(pointer)
    }

    // MARK: Updates

    private var updateStatus: String?

    /// Reads the release feed and compares it with this build — the same feed
    /// Sparkle reads on macOS. Nothing is downloaded and no credential is
    /// sent.
    private func checkForUpdates() {
        updateStatus = "Checking…"
        redraw()
        Task { [weak self] in
            let latest = await UpdateFeedClient().latestVersion()
            guard let self else { return }
            switch latest {
            case .none:
                self.updateStatus = "Couldn't read the release feed"
            case .some(let version)
            where !UpdateFeedClient.isVersion(Ration.version, olderThan: version):
                self.updateStatus = "Up to date"
            case .some(let version):
                self.updateStatus = "Version \(version) is available"
            }
            self.redraw()
        }
    }
}

/// Launch at login, as an XDG autostart entry.
enum Autostart {

    nonisolated(unsafe) private(set) static var lastError: String?

    private static var entryURL: URL {
        PlatformPaths.home.appending(path: ".config/autostart/ration-tray.desktop")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: entryURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                let executable =
                    ProcessInfo.processInfo.arguments.first.map {
                        URL(fileURLWithPath: $0).standardizedFileURL.path
                    } ?? "ration-tray"
                let entry = """
                    [Desktop Entry]
                    Type=Application
                    Name=Ration
                    Comment=AI coding usage in the tray
                    Exec=\(executable)
                    Icon=ration
                    Terminal=false
                    X-GNOME-Autostart-enabled=true
                    """
                try FileManager.default.createDirectory(
                    at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.write(to: entryURL, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: entryURL.path) {
                try FileManager.default.removeItem(at: entryURL)
            }
        } catch {
            lastError = "Couldn't update the autostart entry: \(error.localizedDescription)"
        }
    }
}

/// Opens a URL in the user's browser. A click, never something Ration does on
/// its own.
func openInBrowser(_ url: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
    process.arguments = [url]
    try? process.run()
}
