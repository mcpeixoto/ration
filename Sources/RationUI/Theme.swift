import AppKit
import RationKit
import SwiftUI

/// Shared visual vocabulary.
///
/// Colours are declared once here and resolved per appearance, so light mode,
/// dark mode, and Increase Contrast are handled by the system rather than by
/// scattering hex values through the views.
enum Theme {

    /// Popover width. Wide enough for the calendar's thirteen week columns and
    /// a "Weekly · Fable" label, narrow enough to still feel like a menu.
    static let popoverWidth: CGFloat = 340
    static let ringSize: CGFloat = 116

    /// Claude's terracotta orange, the app's accent.
    ///
    /// Slightly lifted in dark mode: the daylight value goes muddy against a
    /// dark background.
    static let accent = Color(
        light: Color(red: 0.851, green: 0.467, blue: 0.341),  // #D97757
        dark: Color(red: 0.894, green: 0.545, blue: 0.416)  // #E48B6A
    )

    /// A dimmer companion, for gradient tails and inactive marks.
    static let accentMuted = Color(
        light: Color(red: 0.902, green: 0.643, blue: 0.545),
        dark: Color(red: 0.702, green: 0.404, blue: 0.294)
    )

    /// Amber, for a limit being approached. Deliberately yellower than the
    /// accent so it does not read as "normal, but bigger".
    static let warning = Color(
        light: Color(red: 0.878, green: 0.616, blue: 0.145),
        dark: Color(red: 0.949, green: 0.706, blue: 0.235)
    )

    /// Red, for a limit reached.
    static let critical = Color(
        light: Color(red: 0.831, green: 0.239, blue: 0.192),
        dark: Color(red: 0.949, green: 0.365, blue: 0.314)
    )

    /// The neutral fill behind gauges and bars.
    static let track = Color.primary.opacity(0.09)

    /// Swift Charts assigns marks its own palette colours whenever they carry
    /// a `series` value, and the `.primary` shorthand loses that fight — an
    /// explicit colour does not. Hence these two.
    static let rollingAverage = Color(
        light: Color(white: 0.35), dark: Color(white: 0.80))
    static let chartRule = Color(
        light: Color(white: 0.55), dark: Color(white: 0.55))

    /// Calendar heat-map fill for a relative intensity of 0…1.
    ///
    /// Zero is the empty-cell colour rather than a very pale orange, so quiet
    /// days read as genuinely empty instead of faintly active.
    static func heat(_ intensity: Double) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.07) }
        // Floor the opacity so the lightest active day is still visible.
        return accent.opacity(0.25 + 0.75 * min(intensity, 1))
    }
}

extension Color {
    /// Builds a colour that resolves differently in light and dark appearances.
    init(light: Color, dark: Color) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark =
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(isDark ? dark : light)
            })
    }
}

extension Severity {

    /// The colour that represents this severity, or `nil` at `normal` — normal
    /// carries no warning of its own, so text inherits the surrounding style.
    var color: Color? {
        switch self {
        case .normal: nil
        case .warning: Theme.warning
        case .critical: Theme.critical
        }
    }

    /// A colour that is always safe to draw with, falling back to the accent
    /// when there is nothing to warn about.
    var accentColor: Color {
        color ?? Theme.accent
    }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Approaching limit"
        case .critical: "At limit"
        }
    }
}
