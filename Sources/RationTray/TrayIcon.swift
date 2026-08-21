import CLinuxTray
import Foundation
import RationKit

/// The tray item: the Linux counterpart of the macOS menu bar extra.
///
/// `MenuBarStrip` decides what to show — one gauge for a single account, one
/// symbol each once more are on, a percentage, a weekly bar, and a severity
/// tint. That logic is shared with the Mac. What differs is delivery: the
/// StatusNotifierItem protocol takes an icon by name from a theme directory,
/// so each refresh draws a PNG and points the indicator at it.
@MainActor
final class TrayIcon {

    private let indicator: OpaquePointer
    private let directory: URL
    /// Toggled every refresh: an indicator ignores a re-set of the icon name
    /// it already has, even when the file behind it changed.
    private var slot = 0

    /// Logical height of a tray icon; the shell scales it to the panel.
    private let height = 22.0
    /// Drawn at twice the size so the mark stays crisp on a HiDPI panel.
    private let scale = 2.0

    /// A drawing-only icon, for the screenshot harness. Has no indicator to publish to,
    /// so `update` must not be called on it.
    init(offscreen directory: URL) {
        self.indicator = OpaquePointer(bitPattern: -1)!
        self.directory = directory
    }

    init?(title: String) {
        directory = PlatformPaths.home.appending(path: ".cache/ration/tray")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let indicator = app_indicator_new("ration", "ration-0", 0) else { return nil }
        self.indicator = indicator
        app_indicator_set_icon_theme_path(indicator, directory.path)
        app_indicator_set_title(indicator, title)
        // APP_INDICATOR_STATUS_ACTIVE
        app_indicator_set_status(indicator, 1)
    }

    func attach(menu: Widget?) {
        app_indicator_set_menu(indicator, menu)
    }

    /// Lets a middle click open the panel, matching a left click on the Mac.
    func setPrimaryTarget(_ item: Widget?) {
        app_indicator_set_secondary_activate_target(indicator, item)
    }

    // MARK: Drawing

    /// The creature to draw beside the gauge, if any. Set before `update`.
    var companion: (creature: Creature, shiny: Bool)?

    func update(strip: MenuBarStrip, palette: Palette) {
        slot = (slot + 1) % 2
        let name = "ration-\(slot)"
        let path = directory.appending(path: "\(name).png").path
        writePNG(strip: strip, palette: palette, to: path)
        app_indicator_set_icon_full(indicator, name, strip.accessibilityLabel)
        app_indicator_set_title(indicator, strip.accessibilityLabel)
    }

    /// Draws the icon to a file. Split from `update` so the icon can be rendered
    /// without a live indicator — `--screenshot` has no panel to publish to, and an
    /// icon nobody can look at is one nobody checks.
    func writePNG(strip: MenuBarStrip, palette: Palette, to path: String) {
        let foreground = panelForeground(palette: palette)
        let size = measure(strip: strip, palette: palette, foreground: foreground)
        guard
            let surface = cairo_image_surface_create(
                0, Int32((size * scale).rounded(.up)), Int32(height * scale))
        else { return }
        guard let cr = cairo_create(surface) else {
            cairo_surface_destroy(surface)
            return
        }
        cairo_scale(cr, scale, scale)
        let canvas = Canvas(cr: cr, palette: palette)
        render(strip: strip, on: canvas, width: size, foreground: foreground)
        cairo_surface_flush(surface)
        _ = cairo_surface_write_to_png(surface, path)
        cairo_destroy(cr)
        cairo_surface_destroy(surface)
    }

    /// The panel paints its own background, so the icon has to supply its own
    /// contrast: light marks on GNOME's dark shell, dark marks on a light one.
    private func panelForeground(palette: Palette) -> RGBA {
        palette.isDark ? RGBA(1, 1, 1, 0.92) : RGBA(0, 0, 0, 0.85)
    }

    private func tint(for item: MenuBarPresentation, palette: Palette, fallback: RGBA) -> RGBA {
        switch item.tint {
        case .warning: palette.warning
        case .critical: palette.critical
        default: fallback
        }
    }

    // MARK: Layout

    private let glyphSize = 15.0
    private let itemSpacing = 8.0
    private let innerSpacing = 4.0
    private let barSize = (width: 5.0, height: 13.0)
    private let titleSize = 12.0

    /// Measures with a throwaway 1×1 surface: Cairo needs a context before it
    /// will report text extents, and the real one is not sized yet.
    private func measure(strip: MenuBarStrip, palette: Palette, foreground: RGBA) -> Double {
        guard let surface = cairo_image_surface_create(0, 1, 1),
            let cr = cairo_create(surface)
        else { return 24 }
        defer {
            cairo_destroy(cr)
            cairo_surface_destroy(surface)
        }
        let canvas = Canvas(cr: cr, palette: palette)
        var total = companion == nil ? 0 : companionSize + innerSpacing
        for (index, item) in strip.items.enumerated() {
            if index > 0 { total += itemSpacing }
            total += itemWidth(item, on: canvas)
        }
        return max(total + 2, 16)
    }

    /// Small enough not to cost real estate in a crowded panel, big enough that the
    /// illustration is still a shape rather than a smudge.
    private let companionSize = 15.0

    private func itemWidth(_ item: MenuBarPresentation, on canvas: Canvas) -> Double {
        var width = glyphSize
        if let title = item.title {
            width += innerSpacing + canvas.width(title, size: titleSize, weight: .medium)
        }
        if item.bar != nil {
            width += innerSpacing + barSize.width
        }
        return width
    }

    private func render(
        strip: MenuBarStrip, on canvas: Canvas, width: Double, foreground: RGBA
    ) {
        var x = 1.0
        // The creature leads, so the number keeps the position people read it in.
        if let companion {
            let rect = Rect(x, (height - companionSize) / 2, companionSize, companionSize)
            let key = CardFace.keyColor(companion.creature.lore.energy, shiny: companion.shiny)
            canvas.clipped(to: rect, radius: 4) {
                CreatureArtwork.draw(
                    companion.creature.lore.art, in: rect, on: canvas, key: key, caught: true)
            }
            x += companionSize + innerSpacing
        }
        for (index, item) in strip.items.enumerated() {
            if index > 0 { x += itemSpacing }
            let color = tint(for: item, palette: canvas.palette, fallback: foreground)

            Glyph.draw(
                item.symbolName,
                in: Rect(x, (height - glyphSize) / 2, glyphSize, glyphSize),
                on: canvas, color: color)
            x += glyphSize

            if let title = item.title {
                x += innerSpacing
                let lineHeight = canvas.lineHeight(size: titleSize, weight: .medium)
                let advance = canvas.text(
                    title, at: Point(x, (height - lineHeight) / 2),
                    size: titleSize, weight: .medium, color: color)
                x += advance
            }

            if let bar = item.bar {
                x += innerSpacing
                drawWeeklyBar(bar, at: x, on: canvas, foreground: foreground)
                x += barSize.width
            }
        }
    }

    /// Fills from the bottom, like a fuel gauge, and stays monochrome until
    /// there is something to warn about.
    private func drawWeeklyBar(
        _ bar: MenuBarPresentation.Bar, at x: Double, on canvas: Canvas, foreground: RGBA
    ) {
        let top = (height - barSize.height) / 2
        let track = Rect(x, top, barSize.width, barSize.height)
        canvas.fillRounded(track, radius: barSize.width / 2, foreground.opacity(0.28))

        let fillColor: RGBA
        switch bar.severity {
        case .normal: fillColor = foreground.opacity(0.8)
        case .warning: fillColor = canvas.palette.warning
        case .critical: fillColor = canvas.palette.critical
        }
        // Keep a sliver visible at very low usage so the gauge never looks broken.
        let filled = max(barSize.height * min(max(bar.fraction, 0), 1), barSize.width)
        canvas.fillRounded(
            Rect(x, top + barSize.height - filled, barSize.width, filled),
            radius: barSize.width / 2, fillColor)
    }
}
