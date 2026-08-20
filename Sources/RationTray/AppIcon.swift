import CLinuxTray
import Foundation

/// The application icon, drawn in code.
///
/// The same mark `Scripts/make-icon.swift` draws for macOS — a terracotta
/// squircle with a three-quarter gauge ring — rendered with Cairo so the Linux
/// build can produce its own PNGs without an Apple toolchain. Drawn rather than
/// checked in as a binary blob, so it stays reviewable in a diff.
enum AppIcon {

    /// Writes a square PNG of `size` pixels. Returns false if Cairo refused.
    @discardableResult
    static func write(to path: String, size: Int) -> Bool {
        guard let surface = cairo_image_surface_create(0, Int32(size), Int32(size)),
            let cr = cairo_create(surface)
        else { return false }
        defer {
            cairo_destroy(cr)
            cairo_surface_destroy(surface)
        }

        draw(cr: cr, size: Double(size))
        cairo_surface_flush(surface)

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return cairo_surface_write_to_png(surface, path) == 0
    }

    private static func draw(cr: OpaquePointer, size: Double) {
        // Desktop icons fill their canvas rather than sitting inset the way a
        // macOS icon does, so the body is the whole square less a hair.
        let inset = size * 0.04
        let body = Rect(inset, inset, size - inset * 2, size - inset * 2)
        let radius = body.width * 0.2237

        let canvas = Canvas(cr: cr, palette: Palette(isDark: true))
        canvas.roundedPath(body, radius: radius)
        if let gradient = cairo_pattern_create_linear(body.x, body.maxY, body.maxX, body.y) {
            // #E58C6D → #C96444
            cairo_pattern_add_color_stop_rgba(gradient, 0, 0.898, 0.549, 0.427, 1)
            cairo_pattern_add_color_stop_rgba(gradient, 1, 0.788, 0.392, 0.267, 1)
            cairo_set_source(cr, gradient)
            cairo_fill(cr)
            cairo_pattern_destroy(gradient)
        } else {
            canvas.setColor(RGBA(0.851, 0.467, 0.341))
            cairo_fill(cr)
        }

        // The gauge ring, matching the one in the app: starts at twelve
        // o'clock, sweeps clockwise about three quarters of the way round.
        let center = body.center
        let ringRadius = body.width * 0.285
        let lineWidth = body.width * 0.115

        canvas.ring(center: center, radius: ringRadius, width: lineWidth, RGBA(1, 1, 1, 0.22))
        canvas.arc(
            center: center, radius: ringRadius, fraction: 0.72, width: lineWidth, RGBA(1, 1, 1))
    }
}
