import Foundation
import Testing

@testable import RationKit

@Suite("Shiny palette")
struct ShinyPaletteTests {

    /// The eight key colours the cards are drawn in.
    private let energies: [(String, Double, Double, Double)] = [
        ("ember", 0.894, 0.545, 0.416),
        ("signal", 0.373, 0.663, 0.882),
        ("cache", 0.310, 0.749, 0.545),
        ("cycle", 0.859, 0.667, 0.263),
        ("depth", 0.694, 0.514, 0.871),
        ("night", 0.553, 0.580, 0.878),
        ("alloy", 0.502, 0.769, 0.804),
        ("void", 0.882, 0.365, 0.302),
    ]

    private func distance(
        _ a: (red: Double, green: Double, blue: Double), _ b: (Double, Double, Double)
    ) -> Double {
        ((a.red - b.0) * (a.red - b.0) + (a.green - b.1) * (a.green - b.1)
            + (a.blue - b.2) * (a.blue - b.2)).squareRoot()
    }

    /// The whole point. Pairing each energy with the one it is weak to was tried first
    /// and three of eight pairs were both warm — ember against void separated by only
    /// 0.21, which reads as the same card. Every rotation clears twice that.
    @Test("every shiny is clearly a different colour from its normal")
    func shiniesAreDistinct() {
        for (name, r, g, b) in energies {
            let shiny = ShinyPalette.shiny(red: r, green: g, blue: b)
            #expect(distance(shiny, (r, g, b)) > 0.45, "\(name) barely moved")
        }
    }

    @Test("two shinies stay as different from each other as their normals were")
    func shiniesStayDistinctFromEachOther() {
        let shinies = energies.map { ShinyPalette.shiny(red: $0.1, green: $0.2, blue: $0.3) }
        for (index, a) in shinies.enumerated() {
            for b in shinies[(index + 1)...] {
                #expect(distance(a, (b.red, b.green, b.blue)) > 0.08)
            }
        }
    }

    @Test("every channel stays inside the range Cairo and SwiftUI accept")
    func staysInGamut() {
        for (_, r, g, b) in energies {
            let shiny = ShinyPalette.shiny(red: r, green: g, blue: b)
            for channel in [shiny.red, shiny.green, shiny.blue] {
                #expect(channel >= -0.0001 && channel <= 1.0001)
            }
        }
    }

    /// A shiny is a colourway, not a different weight of card, so the illustration has
    /// to keep the presence it was drawn with.
    @Test("rotating keeps a colour's lightness")
    func keepsLightness() {
        for (name, r, g, b) in energies {
            let shiny = ShinyPalette.shiny(red: r, green: g, blue: b)
            let before = (max(r, g, b) + min(r, g, b)) / 2
            let after =
                (max(shiny.red, shiny.green, shiny.blue)
                    + min(shiny.red, shiny.green, shiny.blue)) / 2
            #expect(abs(before - after) < 0.01, "\(name) changed weight")
        }
    }

    @Test("a full turn is no turn at all")
    func fullTurnIsIdentity() {
        let rotated = ShinyPalette.rotate(red: 0.894, green: 0.545, blue: 0.416, degrees: 360)
        #expect(abs(rotated.red - 0.894) < 0.001)
        #expect(abs(rotated.green - 0.545) < 0.001)
        #expect(abs(rotated.blue - 0.416) < 0.001)
    }

    @Test("grey has no hue to turn")
    func greyIsUnchanged() {
        let rotated = ShinyPalette.shiny(red: 0.5, green: 0.5, blue: 0.5)
        #expect(rotated.red == 0.5 && rotated.green == 0.5 && rotated.blue == 0.5)
    }
}
