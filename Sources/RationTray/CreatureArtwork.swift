import CLinuxTray
import Foundation
import RationKit

/// The illustration inside a card's art window.
///
/// The macOS build animates each of these; a Cairo frame is static, so what
/// carries over is the composition — the energy orb behind the subject and the
/// arrangement of primitives in front of it, one distinct silhouette per
/// `CreatureArt`. A locked card draws the same shapes in grey.
enum CreatureArtwork {

    static func draw(
        _ art: CreatureArt, in rect: Rect, on canvas: Canvas, key: RGBA, caught: Bool
    ) {
        let cr = canvas.cr
        cairo_save(cr)
        cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height)
        cairo_clip(cr)

        // The type orb: a radial bloom the subject sits in front of.
        if let orb = cairo_pattern_create_radial(
            rect.midX, rect.y + rect.height * 0.06, 0, rect.midX, rect.y + rect.height * 0.06,
            rect.width * 0.9)
        {
            cairo_pattern_add_color_stop_rgba(
                orb, 0, key.r, key.g, key.b, caught ? 0.22 : 0.08)
            cairo_pattern_add_color_stop_rgba(orb, 1, 0, 0, 0, 0.72)
            cairo_set_source(cr, orb)
            cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height)
            cairo_fill(cr)
            cairo_pattern_destroy(orb)
        }

        cairo_translate(cr, rect.x, rect.y)
        cairo_scale(cr, rect.width, rect.height)
        cairo_set_line_width(cr, 0.02)

        let body = caught ? key : RGBA(0.5, 0.5, 0.5)
        subject(art, cr: cr, key: body)

        cairo_restore(cr)
    }

    // MARK: Subjects

    /// Everything below draws in a 1×1 box: `x` and `y` are fractions of the
    /// art window, which keeps a mini card and a full card identical in shape.
    private static func subject(_ art: CreatureArt, cr: OpaquePointer, key: RGBA) {
        func color(_ alpha: Double) {
            cairo_set_source_rgba(cr, key.r, key.g, key.b, alpha)
        }
        func white(_ alpha: Double) {
            cairo_set_source_rgba(cr, 1, 1, 1, alpha)
        }
        func circle(_ x: Double, _ y: Double, _ r: Double) {
            cairo_new_sub_path(cr)
            cairo_arc(cr, x, y, r, 0, 2 * Double.pi)
        }
        func bar(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            cairo_rectangle(cr, x, y, w, h)
        }

        switch art {
        case .flame:
            color(0.9)
            cairo_move_to(cr, 0.5, 0.16)
            cairo_curve_to(cr, 0.74, 0.42, 0.7, 0.64, 0.5, 0.82)
            cairo_curve_to(cr, 0.3, 0.64, 0.26, 0.42, 0.5, 0.16)
            cairo_close_path(cr)
            cairo_fill(cr)
            white(0.55)
            cairo_move_to(cr, 0.5, 0.38)
            cairo_curve_to(cr, 0.61, 0.52, 0.59, 0.63, 0.5, 0.73)
            cairo_curve_to(cr, 0.41, 0.63, 0.39, 0.52, 0.5, 0.38)
            cairo_close_path(cr)
            cairo_fill(cr)

        case .orbit:
            color(0.9)
            circle(0.5, 0.5, 0.13)
            cairo_fill(cr)
            for (radius, alpha) in [(0.26, 0.6), (0.38, 0.35)] {
                color(alpha)
                cairo_save(cr)
                cairo_translate(cr, 0.5, 0.5)
                cairo_scale(cr, 1, 0.42)
                circle(0, 0, radius)
                cairo_restore(cr)
                cairo_stroke(cr)
            }
            white(0.8)
            circle(0.76, 0.5, 0.035)
            cairo_fill(cr)

        case .gauge:
            color(0.8)
            cairo_set_line_width(cr, 0.1)
            cairo_new_sub_path(cr)
            cairo_arc(cr, 0.5, 0.62, 0.3, Double.pi, 2 * Double.pi)
            cairo_stroke(cr)
            white(0.85)
            cairo_set_line_width(cr, 0.035)
            cairo_move_to(cr, 0.5, 0.62)
            cairo_line_to(cr, 0.66, 0.42)
            cairo_stroke(cr)

        case .wings:
            color(0.85)
            cairo_move_to(cr, 0.5, 0.5)
            cairo_curve_to(cr, 0.3, 0.24, 0.12, 0.34, 0.1, 0.56)
            cairo_curve_to(cr, 0.26, 0.6, 0.4, 0.58, 0.5, 0.5)
            cairo_close_path(cr)
            cairo_fill(cr)
            cairo_move_to(cr, 0.5, 0.5)
            cairo_curve_to(cr, 0.7, 0.24, 0.88, 0.34, 0.9, 0.56)
            cairo_curve_to(cr, 0.74, 0.6, 0.6, 0.58, 0.5, 0.5)
            cairo_close_path(cr)
            cairo_fill(cr)
            white(0.7)
            circle(0.5, 0.56, 0.07)
            cairo_fill(cr)

        case .wisp:
            for (index, alpha) in [(0, 0.75), (1, 0.5), (2, 0.3)] {
                color(alpha)
                circle(
                    0.5 + Double(index) * 0.02, 0.62 - Double(index) * 0.16,
                    0.13 - Double(index) * 0.03)
                cairo_fill(cr)
            }

        case .grid:
            color(0.6)
            cairo_set_line_width(cr, 0.02)
            for step in 0...4 {
                let t = 0.2 + Double(step) * 0.15
                cairo_move_to(cr, 0.2, t)
                cairo_line_to(cr, 0.8, t)
                cairo_move_to(cr, t, 0.2)
                cairo_line_to(cr, t, 0.8)
            }
            cairo_stroke(cr)
            white(0.8)
            circle(0.5, 0.5, 0.06)
            cairo_fill(cr)

        case .window:
            color(0.75)
            bar(0.26, 0.22, 0.48, 0.56)
            cairo_fill(cr)
            white(0.85)
            bar(0.34, 0.3, 0.14, 0.18)
            bar(0.52, 0.3, 0.14, 0.18)
            bar(0.34, 0.52, 0.32, 0.06)
            cairo_fill(cr)

        case .spiral:
            color(0.85)
            cairo_set_line_width(cr, 0.035)
            var radius = 0.06
            var angle = 0.0
            cairo_move_to(cr, 0.5, 0.5)
            while radius < 0.34 {
                angle += 0.35
                radius += 0.012
                cairo_line_to(cr, 0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius * 0.9)
            }
            cairo_stroke(cr)

        case .slabs:
            for (index, alpha) in [(0, 0.8), (1, 0.6), (2, 0.4)] {
                color(alpha)
                bar(0.22 + Double(index) * 0.06, 0.62 - Double(index) * 0.16, 0.5, 0.12)
                cairo_fill(cr)
            }

        case .prism:
            color(0.85)
            cairo_move_to(cr, 0.5, 0.18)
            cairo_line_to(cr, 0.78, 0.7)
            cairo_line_to(cr, 0.22, 0.7)
            cairo_close_path(cr)
            cairo_fill(cr)
            white(0.6)
            cairo_move_to(cr, 0.5, 0.18)
            cairo_line_to(cr, 0.5, 0.7)
            cairo_line_to(cr, 0.22, 0.7)
            cairo_close_path(cr)
            cairo_fill(cr)

        case .chain:
            color(0.8)
            cairo_set_line_width(cr, 0.045)
            for index in 0..<3 {
                circle(0.3 + Double(index) * 0.2, 0.5, 0.11)
                cairo_stroke(cr)
            }

        case .comet:
            color(0.35)
            cairo_move_to(cr, 0.16, 0.72)
            cairo_line_to(cr, 0.62, 0.32)
            cairo_line_to(cr, 0.68, 0.44)
            cairo_close_path(cr)
            cairo_fill(cr)
            white(0.9)
            circle(0.68, 0.34, 0.09)
            cairo_fill(cr)

        case .bars:
            let heights = [0.28, 0.46, 0.62, 0.4, 0.54]
            for (index, height) in heights.enumerated() {
                color(0.55 + Double(index) * 0.07)
                bar(0.2 + Double(index) * 0.13, 0.78 - height, 0.09, height)
                cairo_fill(cr)
            }

        case .braid:
            color(0.85)
            cairo_set_line_width(cr, 0.04)
            for offset in [0.0, 0.12] {
                cairo_move_to(cr, 0.2, 0.5 + offset)
                cairo_curve_to(cr, 0.38, 0.24 + offset, 0.62, 0.76 + offset, 0.8, 0.5 + offset)
                cairo_stroke(cr)
            }

        case .moon:
            color(0.85)
            circle(0.5, 0.5, 0.3)
            cairo_fill(cr)
            cairo_set_source_rgba(cr, 0, 0, 0, 0.85)
            circle(0.62, 0.42, 0.26)
            cairo_fill(cr)

        case .cluster:
            for (x, y, r) in [(0.38, 0.42, 0.13), (0.62, 0.38, 0.09), (0.52, 0.62, 0.11)] {
                color(0.8)
                circle(x, y, r)
                cairo_fill(cr)
            }

        case .wall:
            color(0.7)
            for row in 0..<3 {
                for column in 0..<4 {
                    let offset = row % 2 == 0 ? 0.0 : 0.07
                    bar(
                        0.16 + offset + Double(column) * 0.17, 0.28 + Double(row) * 0.16, 0.15,
                        0.13)
                }
            }
            cairo_fill(cr)

        case .vortex:
            color(0.8)
            cairo_set_line_width(cr, 0.03)
            for index in 0..<4 {
                let scale = 1 - Double(index) * 0.18
                cairo_save(cr)
                cairo_translate(cr, 0.5, 0.5)
                cairo_rotate(cr, Double(index) * 0.5)
                cairo_scale(cr, scale, scale * 0.55)
                circle(0, 0, 0.34)
                cairo_restore(cr)
                cairo_stroke(cr)
            }

        case .shards:
            for (index, points) in [
                [(0.3, 0.26), (0.44, 0.5), (0.24, 0.58)],
                [(0.54, 0.2), (0.72, 0.46), (0.54, 0.52)],
                [(0.44, 0.58), (0.7, 0.56), (0.56, 0.8)],
            ].enumerated() {
                color(0.5 + Double(index) * 0.15)
                cairo_move_to(cr, points[0].0, points[0].1)
                cairo_line_to(cr, points[1].0, points[1].1)
                cairo_line_to(cr, points[2].0, points[2].1)
                cairo_close_path(cr)
                cairo_fill(cr)
            }

        case .eye:
            color(0.8)
            cairo_move_to(cr, 0.14, 0.5)
            cairo_curve_to(cr, 0.34, 0.2, 0.66, 0.2, 0.86, 0.5)
            cairo_curve_to(cr, 0.66, 0.8, 0.34, 0.8, 0.14, 0.5)
            cairo_close_path(cr)
            cairo_fill(cr)
            cairo_set_source_rgba(cr, 0, 0, 0, 0.8)
            circle(0.5, 0.5, 0.14)
            cairo_fill(cr)
            white(0.9)
            circle(0.55, 0.44, 0.045)
            cairo_fill(cr)

        case .lattice:
            color(0.7)
            cairo_set_line_width(cr, 0.022)
            for index in 0...4 {
                let t = 0.2 + Double(index) * 0.15
                cairo_move_to(cr, t, 0.2)
                cairo_line_to(cr, 0.8, t)
                cairo_move_to(cr, 0.2, t)
                cairo_line_to(cr, t, 0.8)
            }
            cairo_stroke(cr)

        case .wave:
            color(0.8)
            cairo_set_line_width(cr, 0.04)
            for offset in [0.0, 0.14, 0.28] {
                cairo_move_to(cr, 0.14, 0.34 + offset)
                cairo_curve_to(
                    cr, 0.34, 0.2 + offset, 0.62, 0.48 + offset, 0.86, 0.34 + offset)
                cairo_stroke(cr)
            }

        case .pillars:
            for index in 0..<4 {
                color(0.55 + Double(index) * 0.09)
                bar(0.22 + Double(index) * 0.15, 0.24, 0.1, 0.54)
                cairo_fill(cr)
            }

        case .droplet:
            color(0.88)
            cairo_move_to(cr, 0.5, 0.18)
            cairo_curve_to(cr, 0.76, 0.5, 0.72, 0.8, 0.5, 0.8)
            cairo_curve_to(cr, 0.28, 0.8, 0.24, 0.5, 0.5, 0.18)
            cairo_close_path(cr)
            cairo_fill(cr)
            white(0.5)
            circle(0.42, 0.62, 0.06)
            cairo_fill(cr)

        case .hourglass:
            color(0.85)
            cairo_move_to(cr, 0.28, 0.2)
            cairo_line_to(cr, 0.72, 0.2)
            cairo_line_to(cr, 0.5, 0.5)
            cairo_close_path(cr)
            cairo_fill(cr)
            cairo_move_to(cr, 0.28, 0.8)
            cairo_line_to(cr, 0.72, 0.8)
            cairo_line_to(cr, 0.5, 0.5)
            cairo_close_path(cr)
            cairo_fill(cr)

        case .steps:
            for index in 0..<4 {
                color(0.5 + Double(index) * 0.12)
                bar(
                    0.2 + Double(index) * 0.15, 0.72 - Double(index) * 0.13, 0.14,
                    0.08 + Double(index) * 0.13)
                cairo_fill(cr)
            }
        }
    }
}
