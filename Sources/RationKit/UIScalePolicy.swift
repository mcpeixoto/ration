import Foundation

/// How large the Linux tray draws itself.
///
/// macOS resolves a point to a physical size for you; X11 does not, so the
/// panel — whose geometry is written in the same units as the macOS popover —
/// needs to be told how many pixels a unit is worth. The decision lives here
/// rather than in the tray so it can be tested without a display.
public enum UIScalePolicy {

    /// Below this the type stops being legible; above it the panel stops
    /// fitting on a laptop screen.
    public static let range: ClosedRange<Double> = 0.75...3.0

    /// Steps rather than a continuous ratio: a panel 1.37× the width of the
    /// last one looks like a mistake, and fractional strokes shimmer.
    public static func scale(forDPI dpi: Double) -> Double {
        switch dpi {
        case ..<110: 1.0
        case ..<140: 1.25
        case ..<180: 1.5
        default: 2.0
        }
    }

    /// What is left for the app to apply.
    ///
    /// - Parameters:
    ///   - wanted: the total scale the display and the user's preferences ask
    ///     for.
    ///   - gtkScaleFactor: whole-number scaling the toolkit already applied to
    ///     the surface. Applying it twice would double everything.
    public static func remainder(wanted: Double, gtkScaleFactor: Int) -> Double {
        let remaining = wanted / Double(max(gtkScaleFactor, 1))
        return min(max(remaining, range.lowerBound), range.upperBound)
    }

    /// Pixels per inch from a monitor's reported geometry, or `nil` when it
    /// does not report a believable physical size — guessing from resolution
    /// alone would blow up a large, low-density display.
    public static func dpi(pixels: Int, millimetres: Int, scaleFactor: Int) -> Double? {
        guard pixels > 0, millimetres > 50 else { return nil }
        return Double(pixels) * Double(max(scaleFactor, 1)) / (Double(millimetres) / 25.4)
    }
}
