import CLinuxTray
import Foundation

/// A drawing surface for one frame.
///
/// The panel is drawn rather than assembled from GTK widgets: the macOS build
/// is a single SwiftUI hierarchy with custom gauges, charts and cards, and
/// rebuilding that from stock GTK controls would look like a different
/// program. Cairo gets the same picture, and hit testing is recorded as the
/// frame is drawn (see `HitTester`).
struct Canvas {

    let cr: OpaquePointer
    let palette: Palette

    init(cr: OpaquePointer, palette: Palette) {
        self.cr = cr
        self.palette = palette
        Self.applyFontOptions(to: cr)
    }

    /// Greyscale antialiasing, not the subpixel default.
    ///
    /// Subpixel rendering assumes it knows the physical order of the display's
    /// stripes; on a panel drawn into an ARGB surface and composited by the
    /// shell that assumption does not hold, and small text picks up visible
    /// red and blue fringes — grey body copy comes out faintly orange.
    private static func applyFontOptions(to cr: OpaquePointer) {
        guard let options = cairo_font_options_create() else { return }
        cairo_font_options_set_antialias(options, 2)  // CAIRO_ANTIALIAS_GRAY
        cairo_font_options_set_hint_style(options, 2)  // CAIRO_HINT_STYLE_SLIGHT
        cairo_font_options_set_hint_metrics(options, 1)  // CAIRO_HINT_METRICS_ON
        cairo_set_font_options(cr, options)
        cairo_font_options_destroy(options)
    }

    // MARK: Colours and paths

    func setColor(_ color: RGBA) {
        cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a)
    }

    func fill(_ rect: Rect, _ color: RGBA) {
        setColor(color)
        cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height)
        cairo_fill(cr)
    }

    func fillRounded(_ rect: Rect, radius: Double, _ color: RGBA) {
        setColor(color)
        roundedPath(rect, radius: radius)
        cairo_fill(cr)
    }

    func strokeRounded(_ rect: Rect, radius: Double, width: Double, _ color: RGBA) {
        setColor(color)
        cairo_set_line_width(cr, width)
        roundedPath(rect, radius: radius)
        cairo_stroke(cr)
    }

    func roundedPath(_ rect: Rect, radius: Double) {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let x = rect.x
        let y = rect.y
        let w = rect.width
        let h = rect.height
        cairo_new_sub_path(cr)
        cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
        cairo_arc(cr, x + w - r, y + h - r, r, 0, Double.pi / 2)
        cairo_arc(cr, x + r, y + h - r, r, Double.pi / 2, Double.pi)
        cairo_arc(cr, x + r, y + r, r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(cr)
    }

    func line(from: Point, to: Point, width: Double, _ color: RGBA) {
        setColor(color)
        cairo_set_line_width(cr, width)
        cairo_set_line_cap(cr, 1)  // round
        cairo_move_to(cr, from.x, from.y)
        cairo_line_to(cr, to.x, to.y)
        cairo_stroke(cr)
    }

    func separator(y: Double, from x0: Double, to x1: Double) {
        setColor(palette.separator)
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, x0, y + 0.5)
        cairo_line_to(cr, x1, y + 0.5)
        cairo_stroke(cr)
    }

    func circle(center: Point, radius: Double, _ color: RGBA) {
        setColor(color)
        cairo_new_sub_path(cr)
        cairo_arc(cr, center.x, center.y, radius, 0, 2 * Double.pi)
        cairo_fill(cr)
    }

    /// One arc of a ring gauge, drawn clockwise from twelve o'clock.
    func arc(
        center: Point, radius: Double, fraction: Double, width: Double, _ color: RGBA,
        rounded: Bool = true
    ) {
        guard fraction > 0 else { return }
        setColor(color)
        cairo_set_line_width(cr, width)
        cairo_set_line_cap(cr, rounded ? 1 : 0)
        let start = -Double.pi / 2
        let end = start + 2 * Double.pi * min(fraction, 1)
        cairo_new_sub_path(cr)
        cairo_arc(cr, center.x, center.y, radius, start, end)
        cairo_stroke(cr)
    }

    func ring(center: Point, radius: Double, width: Double, _ color: RGBA) {
        setColor(color)
        cairo_set_line_width(cr, width)
        cairo_new_sub_path(cr)
        cairo_arc(cr, center.x, center.y, radius, 0, 2 * Double.pi)
        cairo_stroke(cr)
    }

    // MARK: Clipping

    func clipped(to rect: Rect, radius: Double = 0, _ body: () -> Void) {
        cairo_save(cr)
        if radius > 0 {
            roundedPath(rect, radius: radius)
        } else {
            cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height)
        }
        cairo_clip(cr)
        body()
        cairo_restore(cr)
    }

    func translated(by point: Point, _ body: () -> Void) {
        cairo_save(cr)
        cairo_translate(cr, point.x, point.y)
        body()
        cairo_restore(cr)
    }

    // MARK: Text

    enum Weight {
        case regular
        case medium
        case bold

        var cairoWeight: Int32 {
            switch self {
            case .regular, .medium: 0
            case .bold: 1
            }
        }
    }

    enum Alignment {
        case leading
        case center
        case trailing
    }

    /// The desktop's own UI face.
    ///
    /// GSettings reports it as "Ubuntu Sans 11" — family, then size. Only the
    /// family is taken: the panel's type scale is its own, and adopting the
    /// desktop's point size would resize every label independently of the
    /// layout around it. Falls back to whatever fontconfig calls "sans".
    static var family: String {
        if let cached = cachedFamily { return cached }
        let raw = GSettings.read("org.gnome.desktop.interface", "font-name") ?? ""
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \n'\""))
        // Drop the trailing point size, and any style words before it.
        var words = trimmed.split(separator: " ").map(String.init)
        while let last = words.last, Double(last) != nil || last == "Regular" {
            words.removeLast()
        }
        let family = words.joined(separator: " ")
        let resolved = family.isEmpty ? "sans" : family
        cachedFamily = resolved
        return resolved
    }

    nonisolated(unsafe) private static var cachedFamily: String?

    func selectFont(size: Double, weight: Weight) {
        cairo_select_font_face(cr, Self.family, 0, weight.cairoWeight)
        cairo_set_font_size(cr, size)
    }

    func width(_ string: String, size: Double, weight: Weight = .regular) -> Double {
        guard !string.isEmpty else { return 0 }
        selectFont(size: size, weight: weight)
        var extents = cairo_text_extents_t()
        cairo_text_extents(cr, string, &extents)
        return extents.x_advance
    }

    /// Draws one line, with `y` naming the text baseline's line box top.
    @discardableResult
    func text(
        _ string: String,
        at point: Point,
        size: Double,
        weight: Weight = .regular,
        color: RGBA? = nil,
        align: Alignment = .leading
    ) -> Double {
        guard !string.isEmpty else { return 0 }
        selectFont(size: size, weight: weight)
        var extents = cairo_text_extents_t()
        cairo_text_extents(cr, string, &extents)
        var font = cairo_font_extents_t()
        cairo_font_extents(cr, &font)

        let x: Double
        switch align {
        case .leading: x = point.x
        case .center: x = point.x - extents.x_advance / 2
        case .trailing: x = point.x - extents.x_advance
        }

        setColor(color ?? palette.primary)
        cairo_move_to(cr, x, point.y + font.ascent)
        cairo_show_text(cr, string)
        return extents.x_advance
    }

    /// Height of one line at this size, for laying rows out.
    func lineHeight(size: Double, weight: Weight = .regular) -> Double {
        selectFont(size: size, weight: weight)
        var font = cairo_font_extents_t()
        cairo_font_extents(cr, &font)
        return font.height
    }

    /// Shortens with an ellipsis until it fits, the way a SwiftUI `Text` with
    /// `lineLimit(1)` would.
    func truncated(_ string: String, size: Double, weight: Weight = .regular, maxWidth: Double)
        -> String
    {
        guard maxWidth > 0 else { return "" }
        if width(string, size: size, weight: weight) <= maxWidth { return string }
        var characters = Array(string)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters) + "…"
            if width(candidate, size: size, weight: weight) <= maxWidth { return candidate }
        }
        return ""
    }

    /// Greedy word wrap, returning the lines that fit `maxWidth`.
    func wrapped(_ string: String, size: Double, weight: Weight = .regular, maxWidth: Double)
        -> [String]
    {
        var lines: [String] = []
        var current = ""
        for word in string.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if width(candidate, size: size, weight: weight) <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Draws wrapped text and returns the height it consumed.
    @discardableResult
    func paragraph(
        _ string: String,
        at point: Point,
        width maxWidth: Double,
        size: Double,
        weight: Weight = .regular,
        color: RGBA? = nil,
        lineSpacing: Double = 2,
        align: Alignment = .leading
    ) -> Double {
        let lines = wrapped(string, size: size, weight: weight, maxWidth: maxWidth)
        let height = lineHeight(size: size, weight: weight)
        var y = point.y
        for line in lines {
            let x: Double
            switch align {
            case .leading: x = point.x
            case .center: x = point.x + maxWidth / 2
            case .trailing: x = point.x + maxWidth
            }
            text(line, at: Point(x, y), size: size, weight: weight, color: color, align: align)
            y += height + lineSpacing
        }
        return max(0, y - point.y - lineSpacing)
    }
}

// MARK: - Geometry

struct Point: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

struct Rect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var center: Point { Point(midX, midY) }

    func contains(_ point: Point) -> Bool {
        point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }

    func inset(by amount: Double) -> Rect {
        Rect(x + amount, y + amount, max(0, width - 2 * amount), max(0, height - 2 * amount))
    }

    func inset(dx: Double, dy: Double) -> Rect {
        Rect(x + dx, y + dy, max(0, width - 2 * dx), max(0, height - 2 * dy))
    }

    func offset(dx: Double, dy: Double) -> Rect {
        Rect(x + dx, y + dy, width, height)
    }
}
