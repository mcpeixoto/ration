import CLinuxTray
import Foundation
import RationKit

/// How large to draw.
///
/// The panel's geometry is written in the same units as the macOS popover —
/// 340 across, 11pt type — where a point is a physical size the system keeps
/// constant. X11 has no such promise: on a 27" 4K screen a "point" is a third
/// of a millimetre, and a panel laid out in device pixels comes out the size of
/// a matchbox.
///
/// GTK corrects for whole-number scaling on its own (`scale-factor`, 1 or 2),
/// so only what is left over belongs here: the display's real density, GNOME's
/// text-scaling preference, and an explicit override for when a person simply
/// wants it bigger.
enum UIScale {

    /// The factor to apply on top of whatever GTK is already doing.
    ///
    /// - Parameters:
    ///   - override: `uiScale` from settings. Zero means "work it out".
    ///   - gtkScaleFactor: the widget's `scale-factor`, already applied by GDK.
    static func factor(override: Double, gtkScaleFactor: Int = 1) -> Double {
        UIScalePolicy.remainder(
            wanted: override > 0 ? override : automatic(), gtkScaleFactor: gtkScaleFactor)
    }

    /// Density first, then the user's text-scaling preference on top.
    static func automatic() -> Double {
        density() * textScaling()
    }

    private static func density() -> Double {
        guard let display = gdk_display_get_default() else { return 1 }
        // The monitor the pointer is on, since that is where the panel opens.
        let monitor =
            currentPointerPlacement().flatMap {
                gdk_display_get_monitor_at_point(display, Int32($0.pointerX), Int32($0.pointerY))
            } ?? gdk_display_get_primary_monitor(display)
        guard let monitor else { return 1 }

        var geometry = GdkRectangle(x: 0, y: 0, width: 0, height: 0)
        gdk_monitor_get_geometry(monitor, &geometry)
        guard
            let dpi = UIScalePolicy.dpi(
                pixels: Int(geometry.width),
                millimetres: Int(gdk_monitor_get_width_mm(monitor)),
                scaleFactor: Int(gdk_monitor_get_scale_factor(monitor)))
        else { return 1 }
        return UIScalePolicy.scale(forDPI: dpi)
    }

    /// GNOME's Large Text setting, and anything else that writes it.
    private static func textScaling() -> Double {
        guard let raw = GSettings.read("org.gnome.desktop.interface", "text-scaling-factor"),
            let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return 1 }
        return min(max(value, 0.5), 2)
    }
}
