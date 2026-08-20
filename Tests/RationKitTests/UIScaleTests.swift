import Foundation
import Testing

@testable import RationKit

@Suite("UI scale")
struct UIScaleTests {

    /// A 27" 4K panel is the case that started this: 340 device pixels across
    /// is about four centimetres of glass.
    @Test("a dense display asks for a larger panel")
    func denseDisplay() throws {
        let dpi = try #require(
            UIScalePolicy.dpi(pixels: 3840, millimetres: 597, scaleFactor: 1))
        #expect(dpi > 160)
        #expect(UIScalePolicy.scale(forDPI: dpi) == 1.5)
    }

    @Test("an ordinary desktop display is left alone")
    func ordinaryDisplay() throws {
        let dpi = try #require(
            UIScalePolicy.dpi(pixels: 1920, millimetres: 527, scaleFactor: 1))
        #expect(UIScalePolicy.scale(forDPI: dpi) == 1.0)
    }

    /// EDID-less monitors report nonsense; a guess from resolution alone would
    /// magnify a wall-sized low-density screen.
    @Test("a monitor with no believable size reports no density")
    func unknownSize() {
        #expect(UIScalePolicy.dpi(pixels: 3840, millimetres: 0, scaleFactor: 1) == nil)
        #expect(UIScalePolicy.dpi(pixels: 0, millimetres: 597, scaleFactor: 1) == nil)
    }

    /// GTK already scales the surface by whole numbers. Applying that again
    /// would draw everything twice the intended size.
    @Test("whole-number toolkit scaling is not applied twice")
    func doesNotDoubleApply() {
        #expect(UIScalePolicy.remainder(wanted: 2, gtkScaleFactor: 2) == 1)
        #expect(UIScalePolicy.remainder(wanted: 1.5, gtkScaleFactor: 1) == 1.5)
    }

    @Test("the result stays inside the legible range")
    func clamped() {
        #expect(
            UIScalePolicy.remainder(wanted: 8, gtkScaleFactor: 1) == UIScalePolicy.range.upperBound)
        #expect(
            UIScalePolicy.remainder(wanted: 0.1, gtkScaleFactor: 1)
                == UIScalePolicy.range.lowerBound)
    }
}
