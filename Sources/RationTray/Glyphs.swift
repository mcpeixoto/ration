import CLinuxTray
import Foundation

/// Line drawings standing in for the SF Symbols the macOS build uses.
///
/// `MenuBarPresentation` names its glyph as an SF Symbol, which is the right
/// currency on macOS and means nothing here. Rather than fork the presentation
/// logic, the Linux tray keeps the same names and draws each one, so a symbol
/// added on the Mac side shows up as a recognisable mark instead of a blank.
enum Glyph {

    /// Draws `name` centred in `rect`, in the current colour.
    static func draw(_ name: String, in rect: Rect, on canvas: Canvas, color: RGBA) {
        let cr = canvas.cr
        cairo_save(cr)
        cairo_translate(cr, rect.x, rect.y)
        let scale = min(rect.width, rect.height)
        cairo_scale(cr, scale, scale)
        cairo_set_line_width(cr, 0.085)
        cairo_set_line_cap(cr, 1)
        cairo_set_line_join(cr, 1)
        cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a)

        switch name {
        case let gauge where gauge.hasPrefix("gauge"):
            drawGauge(percent: gaugePercent(from: gauge), cr: cr)
        case "sparkle":
            drawSparkle(cr: cr)
        case "chevron.left.forwardslash.chevron.right":
            drawCodeChevrons(cr: cr)
        case "cursorarrow.rays":
            drawCursorRays(cr: cr)
        case "airplane":
            drawAirplane(cr: cr)
        case "diamond":
            drawDiamond(cr: cr)
        case "person.crop.circle.badge.exclamationmark":
            drawSignedOut(cr: cr)
        case "circle.dotted":
            drawDottedCircle(cr: cr)
        case "wifi.slash":
            drawWifiSlash(cr: cr)
        case "eye.slash":
            drawEyeSlash(cr: cr)
        case "key.fill":
            drawKey(cr: cr)
        case "hand.wave":
            drawHand(cr: cr)
        case "calendar":
            drawCalendar(cr: cr)
        case "chart.line.uptrend.xyaxis":
            drawTrendLine(cr: cr)
        case "chart.pie.fill", "chart.pie":
            drawPie(cr: cr)
        case "questionmark.circle":
            drawQuestion(cr: cr)
        case "tray":
            drawTray(cr: cr)
        case "creditcard":
            drawCard(cr: cr)
        default:
            drawGauge(percent: 0, cr: cr)
        }

        cairo_restore(cr)
    }

    /// The needle position encoded in the SF Symbol's name.
    private static func gaugePercent(from name: String) -> Double {
        if name.contains("100percent") { return 100 }
        if name.contains("67percent") { return 67 }
        if name.contains("50percent") { return 50 }
        if name.contains("33percent") { return 33 }
        return 0
    }

    // MARK: Marks

    /// An open dial with tick dots and a needle, matching the SF gauge family.
    private static func drawGauge(percent: Double, cr: OpaquePointer) {
        let center = 0.5
        let radius = 0.36
        // The dial spans 270°, from lower-left round to lower-right.
        let start = Double.pi * 0.75
        let sweep = Double.pi * 1.5

        cairo_set_line_width(cr, 0.075)
        cairo_new_sub_path(cr)
        cairo_arc(cr, center, center, radius, start, start + sweep)
        cairo_stroke(cr)

        // Dots at the quarter marks, the detail that names the symbol.
        for step in 0...4 {
            let angle = start + sweep * Double(step) / 4
            let x = center + cos(angle) * radius
            let y = center + sin(angle) * radius
            cairo_new_sub_path(cr)
            cairo_arc(cr, x, y, 0.035, 0, 2 * Double.pi)
            cairo_fill(cr)
        }

        let angle = start + sweep * min(max(percent, 0), 100) / 100
        cairo_set_line_width(cr, 0.09)
        cairo_move_to(cr, center, center)
        cairo_line_to(
            cr, center + cos(angle) * (radius - 0.07), center + sin(angle) * (radius - 0.07))
        cairo_stroke(cr)
    }

    /// Claude's four-pointed spark.
    private static func drawSparkle(cr: OpaquePointer) {
        func star(cx: Double, cy: Double, outer: Double, inner: Double) {
            cairo_new_sub_path(cr)
            cairo_move_to(cr, cx, cy - outer)
            cairo_curve_to(cr, cx + inner, cy - inner, cx + inner, cy - inner, cx + outer, cy)
            cairo_curve_to(cr, cx + inner, cy + inner, cx + inner, cy + inner, cx, cy + outer)
            cairo_curve_to(cr, cx - inner, cy + inner, cx - inner, cy + inner, cx - outer, cy)
            cairo_curve_to(cr, cx - inner, cy - inner, cx - inner, cy - inner, cx, cy - outer)
            cairo_close_path(cr)
            cairo_fill(cr)
        }
        star(cx: 0.44, cy: 0.46, outer: 0.34, inner: 0.06)
        star(cx: 0.79, cy: 0.79, outer: 0.16, inner: 0.03)
    }

    /// `</>`, for Codex.
    private static func drawCodeChevrons(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.1)
        cairo_move_to(cr, 0.34, 0.28)
        cairo_line_to(cr, 0.14, 0.5)
        cairo_line_to(cr, 0.34, 0.72)
        cairo_stroke(cr)

        cairo_move_to(cr, 0.66, 0.28)
        cairo_line_to(cr, 0.86, 0.5)
        cairo_line_to(cr, 0.66, 0.72)
        cairo_stroke(cr)

        cairo_move_to(cr, 0.57, 0.22)
        cairo_line_to(cr, 0.43, 0.78)
        cairo_stroke(cr)
    }

    /// A pointer with radiating marks, for Cursor.
    private static func drawCursorRays(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_move_to(cr, 0.38, 0.3)
        cairo_line_to(cr, 0.38, 0.78)
        cairo_line_to(cr, 0.5, 0.66)
        cairo_line_to(cr, 0.58, 0.82)
        cairo_line_to(cr, 0.68, 0.77)
        cairo_line_to(cr, 0.6, 0.62)
        cairo_line_to(cr, 0.74, 0.6)
        cairo_close_path(cr)
        cairo_fill(cr)

        for angle in stride(from: -Double.pi, through: -Double.pi / 4, by: Double.pi / 4) {
            let x0 = 0.38 + cos(angle) * 0.24
            let y0 = 0.3 + sin(angle) * 0.24
            let x1 = 0.38 + cos(angle) * 0.36
            let y1 = 0.3 + sin(angle) * 0.36
            cairo_move_to(cr, x0, y0)
            cairo_line_to(cr, x1, y1)
            cairo_stroke(cr)
        }
    }

    private static func drawAirplane(cr: OpaquePointer) {
        cairo_move_to(cr, 0.5, 0.12)
        cairo_curve_to(cr, 0.58, 0.2, 0.58, 0.3, 0.57, 0.4)
        cairo_line_to(cr, 0.9, 0.6)
        cairo_line_to(cr, 0.9, 0.7)
        cairo_line_to(cr, 0.56, 0.6)
        cairo_line_to(cr, 0.55, 0.76)
        cairo_line_to(cr, 0.66, 0.84)
        cairo_line_to(cr, 0.66, 0.9)
        cairo_line_to(cr, 0.5, 0.86)
        cairo_line_to(cr, 0.34, 0.9)
        cairo_line_to(cr, 0.34, 0.84)
        cairo_line_to(cr, 0.45, 0.76)
        cairo_line_to(cr, 0.44, 0.6)
        cairo_line_to(cr, 0.1, 0.7)
        cairo_line_to(cr, 0.1, 0.6)
        cairo_line_to(cr, 0.43, 0.4)
        cairo_curve_to(cr, 0.42, 0.3, 0.42, 0.2, 0.5, 0.12)
        cairo_close_path(cr)
        cairo_fill(cr)
    }

    private static func drawDiamond(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.09)
        cairo_move_to(cr, 0.5, 0.14)
        cairo_line_to(cr, 0.86, 0.5)
        cairo_line_to(cr, 0.5, 0.86)
        cairo_line_to(cr, 0.14, 0.5)
        cairo_close_path(cr)
        cairo_stroke(cr)
    }

    /// A person in a circle with a warning badge — the signed-out state.
    private static func drawSignedOut(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.46, 0.46, 0.38, 0, 2 * Double.pi)
        cairo_stroke(cr)

        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.46, 0.36, 0.12, 0, 2 * Double.pi)
        cairo_fill(cr)

        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.46, 0.74, 0.2, Double.pi, 2 * Double.pi)
        cairo_fill(cr)

        // Badge
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.8, 0.8, 0.2, 0, 2 * Double.pi)
        cairo_fill(cr)
        cairo_set_line_width(cr, 0.055)
        cairo_set_operator(cr, 0)  // CAIRO_OPERATOR_CLEAR punches the mark out
        cairo_move_to(cr, 0.8, 0.7)
        cairo_line_to(cr, 0.8, 0.83)
        cairo_stroke(cr)
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.8, 0.89, 0.028, 0, 2 * Double.pi)
        cairo_fill(cr)
        cairo_set_operator(cr, 2)  // back to CAIRO_OPERATOR_OVER
    }

    private static func drawDottedCircle(cr: OpaquePointer) {
        let dots = 12
        for index in 0..<dots {
            let angle = 2 * Double.pi * Double(index) / Double(dots)
            cairo_new_sub_path(cr)
            cairo_arc(cr, 0.5 + cos(angle) * 0.36, 0.5 + sin(angle) * 0.36, 0.055, 0, 2 * Double.pi)
            cairo_fill(cr)
        }
    }

    private static func drawWifiSlash(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.085)
        for (radius, _) in [(0.38, 0), (0.24, 0), (0.1, 0)] {
            cairo_new_sub_path(cr)
            cairo_arc(cr, 0.5, 0.72, radius, Double.pi * 1.2, Double.pi * 1.8)
            cairo_stroke(cr)
        }
        cairo_move_to(cr, 0.16, 0.16)
        cairo_line_to(cr, 0.84, 0.84)
        cairo_stroke(cr)
    }

    private static func drawKey(cr: OpaquePointer) {
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.34, 0.34, 0.18, 0, 2 * Double.pi)
        cairo_fill(cr)
        cairo_set_line_width(cr, 0.1)
        cairo_move_to(cr, 0.45, 0.45)
        cairo_line_to(cr, 0.84, 0.84)
        cairo_stroke(cr)
        cairo_set_line_width(cr, 0.08)
        cairo_move_to(cr, 0.7, 0.7)
        cairo_line_to(cr, 0.6, 0.8)
        cairo_stroke(cr)
    }

    private static func drawHand(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.09)
        cairo_set_line_cap(cr, 1)
        for (index, length) in [(0, 0.34), (1, 0.42), (2, 0.4), (3, 0.34)] {
            let x = 0.32 + Double(index) * 0.12
            cairo_move_to(cr, x, 0.72)
            cairo_line_to(cr, x, 0.72 - length)
            cairo_stroke(cr)
        }
        cairo_move_to(cr, 0.26, 0.6)
        cairo_line_to(cr, 0.18, 0.5)
        cairo_stroke(cr)
        cairo_rectangle(cr, 0.28, 0.66, 0.46, 0.18)
        cairo_fill(cr)
    }

    private static func drawCalendar(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_rectangle(cr, 0.14, 0.22, 0.72, 0.62)
        cairo_stroke(cr)
        cairo_move_to(cr, 0.14, 0.4)
        cairo_line_to(cr, 0.86, 0.4)
        cairo_stroke(cr)
        cairo_move_to(cr, 0.32, 0.14)
        cairo_line_to(cr, 0.32, 0.28)
        cairo_move_to(cr, 0.68, 0.14)
        cairo_line_to(cr, 0.68, 0.28)
        cairo_stroke(cr)
        for row in 0..<2 {
            for column in 0..<3 {
                cairo_rectangle(
                    cr, 0.26 + Double(column) * 0.19, 0.5 + Double(row) * 0.16, 0.1, 0.08)
            }
        }
        cairo_fill(cr)
    }

    private static func drawTrendLine(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_move_to(cr, 0.14, 0.16)
        cairo_line_to(cr, 0.14, 0.84)
        cairo_line_to(cr, 0.88, 0.84)
        cairo_stroke(cr)
        cairo_move_to(cr, 0.24, 0.68)
        cairo_line_to(cr, 0.44, 0.48)
        cairo_line_to(cr, 0.58, 0.58)
        cairo_line_to(cr, 0.82, 0.28)
        cairo_stroke(cr)
    }

    private static func drawPie(cr: OpaquePointer) {
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.5, 0.5, 0.36, -Double.pi / 2, Double.pi * 0.4)
        cairo_line_to(cr, 0.5, 0.5)
        cairo_close_path(cr)
        cairo_fill(cr)
        cairo_set_line_width(cr, 0.075)
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.5, 0.5, 0.36, Double.pi * 0.4, 3 * Double.pi / 2)
        cairo_line_to(cr, 0.5, 0.5)
        cairo_close_path(cr)
        cairo_stroke(cr)
    }

    private static func drawQuestion(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.5, 0.5, 0.36, 0, 2 * Double.pi)
        cairo_stroke(cr)
        cairo_set_line_width(cr, 0.08)
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.5, 0.4, 0.12, Double.pi, Double.pi * 2.35)
        cairo_stroke(cr)
        cairo_move_to(cr, 0.5, 0.52)
        cairo_line_to(cr, 0.5, 0.6)
        cairo_stroke(cr)
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.5, 0.7, 0.045, 0, 2 * Double.pi)
        cairo_fill(cr)
    }

    private static func drawTray(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_move_to(cr, 0.14, 0.5)
        cairo_line_to(cr, 0.14, 0.78)
        cairo_line_to(cr, 0.86, 0.78)
        cairo_line_to(cr, 0.86, 0.5)
        cairo_line_to(cr, 0.68, 0.5)
        cairo_line_to(cr, 0.62, 0.6)
        cairo_line_to(cr, 0.38, 0.6)
        cairo_line_to(cr, 0.32, 0.5)
        cairo_close_path(cr)
        cairo_stroke(cr)
        cairo_move_to(cr, 0.24, 0.5)
        cairo_line_to(cr, 0.32, 0.24)
        cairo_line_to(cr, 0.68, 0.24)
        cairo_line_to(cr, 0.76, 0.5)
        cairo_stroke(cr)
    }

    private static func drawCard(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.07)
        cairo_rectangle(cr, 0.12, 0.28, 0.76, 0.44)
        cairo_stroke(cr)
        cairo_rectangle(cr, 0.12, 0.38, 0.76, 0.1)
        cairo_fill(cr)
    }

    private static func drawEyeSlash(cr: OpaquePointer) {
        cairo_set_line_width(cr, 0.075)
        cairo_move_to(cr, 0.1, 0.5)
        cairo_curve_to(cr, 0.3, 0.24, 0.7, 0.24, 0.9, 0.5)
        cairo_curve_to(cr, 0.7, 0.76, 0.3, 0.76, 0.1, 0.5)
        cairo_close_path(cr)
        cairo_stroke(cr)

        cairo_new_sub_path(cr)
        cairo_arc(cr, 0.5, 0.5, 0.13, 0, 2 * Double.pi)
        cairo_stroke(cr)

        cairo_move_to(cr, 0.14, 0.16)
        cairo_line_to(cr, 0.86, 0.84)
        cairo_stroke(cr)
    }
}
