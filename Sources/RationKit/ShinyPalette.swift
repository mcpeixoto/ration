import Foundation

/// The colour maths behind a shiny, shared by both renderers.
///
/// SwiftUI and Cairo draw the card twice over, and the rarity, energy and foil tables
/// are already duplicated between `Theme` and `CardFace`. A second copy of this would
/// be the easiest of all of them to let drift, because the two would still both *look*
/// plausible — so the rotation lives here and neither renderer owns it.
public enum ShinyPalette {

    /// The same colour, spun around the wheel, keeping saturation and lightness.
    ///
    /// HSL rather than HSB: the card is designed around a key colour at a particular
    /// weight, and HSL is the model that holds that weight steady as the hue moves.
    public static func rotate(
        red: Double, green: Double, blue: Double, degrees: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        let delta = high - low
        guard delta > 0 else { return (red, green, blue) }

        let saturation =
            lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        if high == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if high == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue = (hue / 6 + degrees / 360).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }

        let q =
            lightness < 0.5
            ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ offset: Double) -> Double {
            var t = hue + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (channel(1 / 3), channel(0), channel(-1 / 3))
    }

    /// A creature's key colour, shifted if this one is shiny.
    public static func shiny(
        red: Double, green: Double, blue: Double
    ) -> (red: Double, green: Double, blue: Double) {
        rotate(red: red, green: green, blue: blue, degrees: CompanionBalance.shinyHueShift)
    }
}
