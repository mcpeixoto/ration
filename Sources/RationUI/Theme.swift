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

extension CreatureRarity {
    var color: Color {
        switch self {
        case .common: Color(light: Color(white: 0.45), dark: Color(white: 0.72))
        case .uncommon:
            Color(
                light: Color(red: 0.22, green: 0.62, blue: 0.38),
                dark: Color(red: 0.40, green: 0.82, blue: 0.55))
        case .rare:
            Color(
                light: Color(red: 0.20, green: 0.42, blue: 0.82),
                dark: Color(red: 0.45, green: 0.65, blue: 1.0))
        case .epic:
            Color(
                light: Color(red: 0.56, green: 0.28, blue: 0.78),
                dark: Color(red: 0.75, green: 0.50, blue: 0.95))
        case .legendary: Theme.warning
        case .mythic: Theme.accent
        }
    }

    /// Whether the card carries a moving foil. Common is printed; the rest shine.
    var hasFoil: Bool { self >= .uncommon }

    var foilColors: [Color] {
        switch self {
        case .common: [.white.opacity(0.2)]
        case .uncommon: [.green, .mint, .white, .green]
        case .rare: [.blue, .cyan, .white, .indigo, .blue]
        case .epic: [.purple, .pink, .white, .indigo, .purple]
        case .legendary: [.yellow, .orange, .white, .mint, .yellow]
        case .mythic:
            [
                Theme.accent, .orange, .yellow, .mint, .cyan, .purple, Theme.accent,
            ]
        }
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

extension CreatureRarity {
    /// The mark printed next to the collector number.
    var pipGlyph: String {
        switch self {
        case .common: "\u{25CF}"  // ●
        case .uncommon: "\u{25C6}"  // ◆
        case .rare: "\u{2605}"  // ★
        case .epic: "\u{2726}"  // ✦
        case .legendary: "\u{2739}"  // ✹
        case .mythic: "\u{2735}"  // ✵
        }
    }
}

extension CreatureEnergy {

    /// The card's key colour: pips, stat bars, art window, ability rail.
    ///
    /// Card stock is dark in both appearances, so these are tuned for a dark
    /// ground and do not switch with the system appearance.
    var color: Color {
        switch self {
        case .ember: Color(red: 0.894, green: 0.545, blue: 0.416)
        case .signal: Color(red: 0.373, green: 0.663, blue: 0.882)
        case .cache: Color(red: 0.310, green: 0.749, blue: 0.545)
        case .cycle: Color(red: 0.859, green: 0.667, blue: 0.263)
        case .depth: Color(red: 0.694, green: 0.514, blue: 0.871)
        case .night: Color(red: 0.553, green: 0.580, blue: 0.878)
        case .alloy: Color(red: 0.502, green: 0.769, blue: 0.804)
        case .void: Color(red: 0.882, green: 0.365, blue: 0.302)
        }
    }
}
