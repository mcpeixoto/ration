import CLinuxTray
import Dispatch
import Foundation
import RationKit

/// The panel that drops down from the tray, mirroring the macOS popover.
///
/// One undecorated window with one drawing area. Every frame is drawn from
/// scratch and records the rectangles that respond to a click, which keeps the
/// layout code and the hit testing in one place instead of two that drift.
@MainActor
final class Panel {

    /// Wide enough for the calendar's thirteen week columns and a
    /// "Weekly · Fable" label, narrow enough to still feel like a menu — the
    /// same 340 the macOS popover uses.
    static let width = 340.0
    /// Hard ceiling in logical units; the content scrolls past it.
    ///
    /// Also bounded by the screen: 700 units at 1.875× is 1312 pixels, which
    /// is taller than a 1200-pixel laptop display. A panel that does not fit
    /// is worse than one that scrolls.
    fileprivate var maxHeight: Double {
        min(700, availableHeight)
    }

    /// What the monitor under the pointer leaves room for, in logical units.
    private var availableHeight: Double {
        guard let placement = currentPointerPlacement() else { return 700 }
        return max(320, Double(placement.workArea.height) / scale - 24)
    }

    let app: TrayApp
    private var window: Widget?
    private var area: Widget?

    private(set) var isOpen = false

    /// Which tab is showing, and where each one was scrolled to.
    var tab: PanelTab = .usage
    private var scrollOffsets: [PanelTab: Double] = [:]
    /// The overlays — a card being inspected, a card being revealed — scroll
    /// independently of the binder behind them. Sharing one offset opened the
    /// inspector already scrolled to wherever the grid happened to be, which
    /// looked like the click had done nothing.
    private var overlayScroll = 0.0
    /// Which limit the user promoted into the ring. Cleared when the panel
    /// closes, so the ring returns to their configured default.
    var focusedLimitID: String?
    /// Which account the panel is showing.
    var selectedProviderID: String?
    /// The creature open in the inspector, if any.
    var inspectedCreatureID: String?
    /// Range shown by the Trends tab.
    var trendsDays = 30
    var trendsMetric: TrendsMetric = .tokens
    /// The calendar cell under the pointer, named by the Activity tab as it
    /// draws so the legend can describe it.
    var hoveredDay: DayUsage?
    /// Range shown by the Detail tab.
    var detailDays = 30
    /// Creatures unlocked since the binder was last opened, announced one at
    /// a time before the grid appears.
    var revealQueue: [Creature] = []
    /// The card whose image was just put on the clipboard.
    var copiedCreatureID: String?
    /// Where the last card image was written.
    var lastSavedCardPath: String?

    /// Whether an overlay owns the body, and therefore the scroll position.
    var isShowingOverlay: Bool {
        tab == .collection && (inspectedCreatureID != nil || !revealQueue.isEmpty)
    }

    private var scrollOffset: Double {
        get { isShowingOverlay ? overlayScroll : (scrollOffsets[tab] ?? 0) }
        set {
            if isShowingOverlay {
                overlayScroll = newValue
            } else {
                scrollOffsets[tab] = newValue
            }
        }
    }

    /// Called when an overlay opens or closes, so it starts at the top and the
    /// binder keeps the place the user left it.
    func resetOverlayScroll() {
        overlayScroll = 0
    }

    // MARK: Motion

    /// How far through the entrance animation this frame is, 0…1.
    var entrance: Double {
        guard Motion.isEnabled else { return 1 }
        return Motion.easeOut(Motion.progress(since: entranceStartedAt, duration: 0.9))
    }

    /// How far through the reveal spring the caught card is, 0…1.
    var revealProgress: Double {
        guard Motion.isEnabled else { return 1 }
        return Motion.spring(Motion.progress(since: revealStartedAt, duration: 0.45))
    }

    /// The seconds value the foil turns on, or `nil` when animation is off.
    var foilPhase: Double? {
        Motion.isEnabled ? Motion.clock() : nil
    }

    func restartEntrance() {
        entranceStartedAt = Date()
        scheduleFrame()
    }

    func restartReveal() {
        revealStartedAt = Date()
        scheduleFrame()
    }

    /// Whether anything on screen still needs redrawing.
    ///
    /// Foil never settles, so the binder and its overlays animate for as long
    /// as they are open; everything else runs its entrance and stops. A panel
    /// that is not showing a card does no work at all.
    private var needsFrames: Bool {
        guard isOpen, Motion.isEnabled else { return false }
        if tab == .collection { return true }
        return Date() < entranceStartedAt.addingTimeInterval(0.9)
    }

    /// Asks for the next frame, at the foil's rate.
    private func scheduleFrame() {
        guard !frameScheduled, needsFrames else { return }
        frameScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.frameInterval) { [weak self] in
            guard let self else { return }
            self.frameScheduled = false
            guard self.needsFrames else { return }
            self.redraw()
            self.scheduleFrame()
        }
    }

    /// Regions that respond to a click, innermost last.
    private var hitRegions: [(rect: Rect, action: () -> Void)] = []
    private var pointer = Point(-1, -1)
    /// Height the last frame wanted, used to size the window.
    fileprivate var contentHeight = 0.0
    private var lastAppliedHeight = 0.0
    /// When the panel was last opened, so a focus-out during mapping does not
    /// close it before it is on screen.
    private var openedAt = Date.distantPast
    /// Logical units per pixel. Everything below is written in the same units
    /// as the macOS popover and multiplied up at draw time.
    fileprivate var scale = 1.0

    /// When the current entrance animation began — the ring sweeping up to its
    /// value, the bars filling. Restarted when the panel opens and when the
    /// tab or the account changes, the way a SwiftUI view re-runs `onAppear`.
    private var entranceStartedAt = Date.distantPast
    /// When the card now being revealed came on screen.
    fileprivate var revealStartedAt = Date.distantPast
    /// True while a frame has been asked for and not yet drawn.
    private var frameScheduled = false

    init(app: TrayApp) {
        self.app = app
    }

    // MARK: Window

    private func build() {
        // A toplevel, undecorated, hinted as a popup menu. GTK_WINDOW_POPUP
        // would also be undecorated, but the window manager never focuses one,
        // and a panel that cannot take focus can neither be dismissed by
        // clicking away nor closed with Escape.
        let window = gtk_window_new(0)
        gtk_window_set_title(window, "Ration")
        gtk_window_set_decorated(window, 0)
        gtk_window_set_resizable(window, 0)
        gtk_window_set_skip_taskbar_hint(window, 1)
        gtk_window_set_skip_pager_hint(window, 1)
        gtk_window_set_keep_above(window, 1)
        gtk_window_set_type_hint(window, 10)  // GDK_WINDOW_TYPE_HINT_POPUP_MENU
        gtk_window_set_default_size(window, Int32(Self.width), 420)

        // An RGBA visual lets the rounded corners sit on the desktop rather
        // than on a square of grey, where the compositor allows it.
        if let screen = gdk_screen_get_default(), gdk_screen_is_composited(screen) != 0,
            let visual = gdk_screen_get_rgba_visual(screen)
        {
            gtk_widget_set_visual(window, visual)
            gtk_widget_set_app_paintable(window, 1)
        }

        let area = gtk_drawing_area_new()
        gtk_widget_add_events(area, EventMask.panel)
        gtk_widget_set_can_focus(area, 1)
        gtk_container_add(window, area)

        onDraw(area) { [weak self] cr in
            self?.draw(cr: cr)
        }
        onButtonPress(area) { [weak self] event in
            guard let self else { return false }
            return self.handleClick(at: self.logical(event))
        }
        onMotion(area) { [weak self] event in
            guard let self else { return false }
            return self.handleMotion(to: self.logical(event))
        }
        onScroll(area) { [weak self] event in
            self?.handleScroll(delta: event.scrollDelta) ?? false
        }
        onKeyPress(window) { [weak self] event in
            // Escape backs out one step: an open card first, then the panel.
            guard let self, event.keyval == 0xFF1B else { return false }
            if self.inspectedCreatureID != nil {
                self.inspectedCreatureID = nil
                self.resetOverlayScroll()
                self.redraw()
            } else {
                self.close()
            }
            return true
        }
        onFocusOut(window) { [weak self] in
            // The first focus-out lands while the window is still being
            // mapped, before the pointer has had a chance to go anywhere.
            guard let self, self.isOpen, Date() > self.openedAt.addingTimeInterval(0.4) else {
                return
            }
            self.close()
        }

        self.window = window
        self.area = area
    }

    /// Opens under the pointer, which is where the tray icon was clicked.
    func open() {
        if window == nil { build() }
        guard let window else { return }

        isOpen = true
        openedAt = Date()
        refreshScale()
        restartEntrance()
        app.registry.setMenuOpen(true)
        app.refreshHistories()

        let height = Int32((min(max(contentHeight, 220), maxHeight) * scale).rounded())
        gtk_window_resize(window, pixelWidth, height)

        if let placement = currentPointerPlacement() {
            let area = placement.workArea
            let panelWidth = Int(pixelWidth)
            var x = placement.pointerX - panelWidth / 2
            x = min(max(x, Int(area.x) + 8), Int(area.x) + Int(area.width) - panelWidth - 8)
            // Below the panel when the pointer is at the top of the screen,
            // above it when the shell puts its bar at the bottom.
            let opensDownward = placement.pointerY < Int(area.y) + Int(area.height) / 2
            let y =
                opensDownward
                ? min(placement.pointerY + 12, Int(area.y) + Int(area.height) - Int(height))
                : max(placement.pointerY - Int(height) - 12, Int(area.y))
            gtk_window_move(window, Int32(x), Int32(y))
        }

        gtk_widget_show_all(window)
        gtk_window_present(window)
        gtk_widget_grab_focus(window)
        redraw()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        focusedLimitID = nil
        inspectedCreatureID = nil
        resetOverlayScroll()
        app.registry.setMenuOpen(false)
        if let window { gtk_widget_hide(window) }
    }

    func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    func redraw() {
        guard let area, isOpen else { return }
        gtk_widget_queue_draw(area)
    }

    /// Re-reads the scale. GTK's own `scale-factor` is already applied to the
    /// surface, so only the remainder is ours to apply.
    private func refreshScale() {
        scale = UIScale.factor(
            override: app.config.uiScale,
            gtkScaleFactor: area.map { Int(gtk_widget_get_scale_factor($0)) } ?? 1)
    }

    /// The panel's size in pixels, from its size in logical units.
    private var pixelWidth: Int32 { Int32((Self.width * scale).rounded()) }

    // MARK: Input

    private func handleClick(at point: Point) -> Bool {
        // Innermost region wins, so a button inside a card beats the card.
        for region in hitRegions.reversed() where region.rect.contains(point) {
            region.action()
            resize()
            redraw()
            return true
        }
        return false
    }

    private func handleMotion(to point: Point) -> Bool {
        let wasOver = hitRegions.contains { $0.rect.contains(pointer) }
        let isOver = hitRegions.contains { $0.rect.contains(point) }
        pointer = point
        if wasOver || isOver { redraw() }
        return false
    }

    private func handleScroll(delta: Double) -> Bool {
        let offset = scrollOffset
        let limit = max(0, contentHeight - maxHeight)
        let next = min(max(offset + delta * 48, 0), limit)
        guard next != offset else { return false }
        scrollOffset = next
        redraw()
        return true
    }

    /// Grows or shrinks the window to the frame the content asked for.
    private func resize() {
        guard let window, isOpen else { return }
        let height = min(max(contentHeight, 220), maxHeight)
        guard abs(height - lastAppliedHeight) > 1 else { return }
        lastAppliedHeight = height
        gtk_window_resize(window, pixelWidth, Int32((height * scale).rounded()))
    }

    /// Turns a pointer position into the units the layout is written in.
    private func logical(_ event: InputEvent) -> Point {
        Point(event.x / scale, event.y / scale)
    }

    // MARK: Hit testing

    func addHit(_ rect: Rect, _ action: @escaping () -> Void) {
        hitRegions.append((rect, action))
    }

    func isHovered(_ rect: Rect) -> Bool {
        rect.contains(pointer)
    }

    // MARK: Drawing

    private func draw(cr: OpaquePointer) {
        refreshScale()
        cairo_scale(cr, scale, scale)
        render(
            cr: cr,
            width: Double(gtk_widget_get_allocated_width(area)) / scale,
            height: Double(gtk_widget_get_allocated_height(area)) / scale)
    }

    /// Draws one frame into a context already scaled to logical units.
    ///
    /// Split out so the same code paints the window and an image surface —
    /// `--screenshot` renders every tab without a display, which is how the
    /// panel's states get checked.
    fileprivate func render(cr: OpaquePointer, width: Double, height: Double) {
        hitRegions.removeAll(keepingCapacity: true)
        let palette = Palette.current()
        let now = Date()
        let canvas = Canvas(cr: cr, palette: palette)

        // Background, with the rounded corners a menu has.
        cairo_set_operator(cr, 0)  // CLEAR — start from nothing under the corners
        cairo_paint(cr)
        cairo_set_operator(cr, 2)  // OVER
        canvas.fillRounded(Rect(0, 0, width, height), radius: 12, palette.background)
        canvas.strokeRounded(
            Rect(0.5, 0.5, width - 1, height - 1), radius: 12, width: 1, palette.separator)

        var y = 0.0
        y += drawHeader(canvas, width: width, top: y, now: now)

        let accounts = app.visibleEntries
        if app.isSetUp, accounts.count > 1, tab != .collection {
            y += drawProviderSwitcher(canvas, width: width, top: y, accounts: accounts)
        }
        if app.isSetUp, tab != .collection {
            y += drawTabSwitcher(canvas, width: width, top: y)
        }

        canvas.separator(y: y, from: 0, to: width)
        y += 1

        let footerHeight = 34.0
        let available = maxHeight - y - footerHeight
        let offset = scrollOffset
        var bodyHeight = 0.0
        canvas.clipped(to: Rect(0, y, width, max(0, min(available, height - y - footerHeight)))) {
            bodyHeight = drawBody(canvas, width: width, top: y - offset, now: now)
        }

        contentHeight = y + bodyHeight + footerHeight + 1
        let bodyBottom = min(y + bodyHeight - offset, height - footerHeight)

        canvas.separator(y: max(y, bodyBottom), from: 0, to: width)
        drawFooter(canvas, width: width, top: height - footerHeight, now: now)

        // The window is sized from the frame just measured, so a tab switch
        // settles on the next turn of the loop rather than mid-draw.
        if isOpen {
            DispatchQueue.main.async { [weak self] in
                self?.resize()
                self?.scheduleFrame()
            }
        }
    }

    private func drawBody(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        switch tab {
        case .usage: drawUsageTab(canvas, width: width, top: top, now: now)
        case .activity: drawActivityTab(canvas, width: width, top: top, now: now)
        case .trends: drawTrendsTab(canvas, width: width, top: top, now: now)
        case .breakdown: drawDetailTab(canvas, width: width, top: top, now: now)
        case .collection: drawCollectionTab(canvas, width: width, top: top, now: now)
        }
    }

    // MARK: Chrome

    private func drawHeader(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        let height = 42.0
        var x = 16.0
        let palette = canvas.palette

        let titleColor = tab == .collection ? palette.secondaryText : palette.primary
        let titleWidth = canvas.width("Ration", size: 14, weight: .bold)
        canvas.text(
            "Ration", at: Point(x, top + 12), size: 14, weight: .bold, color: titleColor)
        addHit(Rect(x, top + 8, titleWidth, 20)) { [weak self] in
            guard let self, self.tab == .collection else { return }
            self.tab = .usage
            self.restartEntrance()
        }
        x += titleWidth + 8

        // Pokémon sits beside the title rather than in the tab strip, the way
        // the Mac does it.
        let dexLabel = "Pokémon"
        let dexWidth = canvas.width(dexLabel, size: 11, weight: .bold) + 18
        let dexRect = Rect(x, top + 10, dexWidth, 21)
        let isDex = tab == .collection
        canvas.fillRounded(
            dexRect, radius: 10.5,
            isDex ? palette.accent.opacity(0.28) : palette.primary.opacity(0.07))
        canvas.text(
            dexLabel, at: Point(dexRect.midX, top + 14), size: 11, weight: .bold,
            color: isDex ? palette.accent : palette.secondaryText, align: .center)
        addHit(dexRect) { [weak self] in
            guard let self, self.tab != .collection else { return }
            self.tab = .collection
            self.restartEntrance()
        }
        x += dexWidth + 8

        if tab != .collection, let plan = app.planLabel(providerID: selectedProviderID) {
            let planWidth = canvas.width(plan, size: 10, weight: .bold) + 12
            let planRect = Rect(x, top + 12, planWidth, 17)
            canvas.fillRounded(planRect, radius: 8.5, palette.primary.opacity(0.09))
            canvas.text(
                plan, at: Point(planRect.midX, top + 15), size: 10, weight: .bold,
                color: palette.secondaryText, align: .center)
        }

        // Trailing controls: refresh, then settings.
        var trailing = width - 16.0
        let gearRect = Rect(trailing - 18, top + 11, 18, 18)
        drawGear(canvas, in: gearRect, color: palette.secondaryText)
        addHit(gearRect.inset(by: -4)) { [weak self] in
            self?.app.openSettings()
        }
        trailing -= 26

        if tab != .collection {
            let refreshRect = Rect(trailing - 18, top + 11, 18, 18)
            drawRefresh(
                canvas, in: refreshRect,
                color: app.isRefreshing ? palette.accent : palette.secondaryText)
            addHit(refreshRect.inset(by: -4)) { [weak self] in
                self?.app.refreshNow()
            }
        }

        return height
    }

    private func drawProviderSwitcher(
        _ canvas: Canvas, width: Double, top: Double, accounts: [ProviderRegistry.Entry]
    ) -> Double {
        let rect = Rect(14, top, width - 28, 26)
        canvas.fillRounded(rect, radius: 8, canvas.palette.controlBackground)
        let inner = rect.inset(by: 2)
        let slot = inner.width / Double(accounts.count)
        let current = app.selectedProvider(id: selectedProviderID).id

        for (index, entry) in accounts.enumerated() {
            let slotRect = Rect(inner.x + slot * Double(index), inner.y, slot, inner.height)
            let isSelected = entry.provider.id == current
            if isSelected {
                canvas.fillRounded(slotRect, radius: 6, canvas.palette.selectedControl)
            }
            let color = isSelected ? canvas.palette.primary : canvas.palette.secondaryText
            let label = entry.provider.displayName
            let labelWidth = canvas.width(label, size: 11)
            let glyphSize = 11.0
            let contentWidth = glyphSize + 4 + labelWidth
            let startX = slotRect.midX - contentWidth / 2
            Glyph.draw(
                entry.provider.symbolName,
                in: Rect(startX, slotRect.midY - glyphSize / 2, glyphSize, glyphSize),
                on: canvas, color: color)
            canvas.text(
                label, at: Point(startX + glyphSize + 4, slotRect.midY - 7), size: 11, color: color)
            addHit(slotRect) { [weak self] in
                guard let self else { return }
                self.selectedProviderID = entry.provider.id
                self.focusedLimitID = nil
                self.restartEntrance()
            }
        }
        return rect.height + 8
    }

    private func drawTabSwitcher(_ canvas: Canvas, width: Double, top: Double) -> Double {
        let rect = Rect(14, top, width - 28, 26)
        canvas.fillRounded(rect, radius: 8, canvas.palette.controlBackground)
        let inner = rect.inset(by: 2)
        let tabs = PanelTab.meterTabs
        let slot = inner.width / Double(tabs.count)

        for (index, candidate) in tabs.enumerated() {
            let slotRect = Rect(inner.x + slot * Double(index), inner.y, slot, inner.height)
            let isSelected = candidate == tab
            if isSelected {
                canvas.fillRounded(slotRect, radius: 6, canvas.palette.selectedControl)
            }
            canvas.text(
                candidate.title, at: Point(slotRect.midX, slotRect.midY - 7), size: 11,
                color: isSelected ? canvas.palette.primary : canvas.palette.secondaryText,
                align: .center)
            addHit(slotRect) { [weak self] in
                guard let self, self.tab != candidate else { return }
                self.tab = candidate
                self.restartEntrance()
            }
        }
        return rect.height + 10
    }

    private func drawFooter(_ canvas: Canvas, width: Double, top: Double, now: Date) {
        let palette = canvas.palette
        let status = app.footerStatus(providerID: selectedProviderID, now: now)
        canvas.text(
            canvas.truncated(status.text, size: 10.5, maxWidth: width - 120),
            at: Point(16, top + 10), size: 10.5,
            color: status.isWarning ? palette.warning : palette.secondaryText)

        let quitWidth = canvas.width("Quit", size: 10.5)
        let quitRect = Rect(width - 16 - quitWidth, top + 8, quitWidth, 16)
        canvas.text(
            "Quit", at: Point(quitRect.x, top + 10), size: 10.5,
            color: isHovered(quitRect.inset(by: -4)) ? palette.primary : palette.secondaryText)
        addHit(quitRect.inset(by: -4)) { [weak self] in
            self?.app.quit()
        }
    }

    // MARK: Small marks

    private func drawGear(_ canvas: Canvas, in rect: Rect, color: RGBA) {
        let cr = canvas.cr
        canvas.setColor(isHovered(rect.inset(by: -4)) ? canvas.palette.primary : color)
        let center = rect.center
        let teeth = 8
        cairo_set_line_width(cr, 1.6)
        for index in 0..<teeth {
            let angle = 2 * Double.pi * Double(index) / Double(teeth)
            cairo_move_to(
                cr, center.x + cos(angle) * rect.width * 0.28,
                center.y + sin(angle) * rect.width * 0.28)
            cairo_line_to(
                cr, center.x + cos(angle) * rect.width * 0.46,
                center.y + sin(angle) * rect.width * 0.46)
            cairo_stroke(cr)
        }
        canvas.ring(center: center, radius: rect.width * 0.26, width: 1.6, color)
    }

    private func drawRefresh(_ canvas: Canvas, in rect: Rect, color: RGBA) {
        let cr = canvas.cr
        canvas.setColor(isHovered(rect.inset(by: -4)) ? canvas.palette.primary : color)
        cairo_set_line_width(cr, 1.6)
        cairo_set_line_cap(cr, 1)
        let radius = rect.width * 0.36
        cairo_new_sub_path(cr)
        cairo_arc(cr, rect.midX, rect.midY, radius, -Double.pi * 0.8, Double.pi * 0.65)
        cairo_stroke(cr)
        // Arrow head on the open end.
        let angle = -Double.pi * 0.8
        let tip = Point(rect.midX + cos(angle) * radius, rect.midY + sin(angle) * radius)
        cairo_move_to(cr, tip.x - 4, tip.y - 1)
        cairo_line_to(cr, tip.x, tip.y + 4)
        cairo_line_to(cr, tip.x + 4, tip.y - 2)
        cairo_stroke(cr)
    }
}

extension Panel {

    /// Renders the panel to a PNG without a window.
    ///
    /// The height is measured by drawing once into a throwaway surface, then
    /// the real frame is drawn at that size — the same two-pass shape the live
    /// panel uses when it resizes itself after a tab switch.
    @discardableResult
    func snapshot(to path: String) -> Bool {
        scale = UIScale.factor(override: app.config.uiScale)
        let width = Self.width

        guard let measuring = cairo_image_surface_create(0, 1, 1),
            let measuringContext = cairo_create(measuring)
        else { return false }
        render(cr: measuringContext, width: width, height: maxHeight)
        cairo_destroy(measuringContext)
        cairo_surface_destroy(measuring)

        let height = min(max(contentHeight, 220), maxHeight)
        guard
            let surface = cairo_image_surface_create(
                0, Int32((width * scale).rounded()), Int32((height * scale).rounded())),
            let cr = cairo_create(surface)
        else { return false }
        cairo_scale(cr, scale, scale)
        render(cr: cr, width: width, height: height)
        cairo_surface_flush(surface)

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let status = cairo_surface_write_to_png(surface, path)
        cairo_destroy(cr)
        cairo_surface_destroy(surface)
        return status == 0
    }
}

/// Which measure the Trends tab charts.
enum TrendsMetric: String, CaseIterable {
    case tokens
    case messages
    case sessions
    case cost

    var title: String {
        switch self {
        case .tokens: "Tokens"
        case .messages: "Messages"
        case .sessions: "Sessions"
        case .cost: "Cost"
        }
    }
}
