import AppKit
import Testing

@testable import RationUI

@Suite("Menu bar appearance image")
struct MenuBarAppearanceImageTests {

    @Test("a combined image is not a template")
    @MainActor
    func isNotTemplate() {
        let combined = MenuBarAppearanceImage.combining(
            light: swatch(.black), dark: swatch(.white))
        #expect(!combined.isTemplate)
    }

    @Test("the result keeps the point size of the source")
    @MainActor
    func preservesSize() {
        let combined = MenuBarAppearanceImage.combining(
            light: swatch(.black, size: NSSize(width: 12, height: 8)),
            dark: swatch(.white, size: NSSize(width: 12, height: 8)))

        #expect(combined.size == NSSize(width: 12, height: 8))
    }

    @Test("drawing follows the current appearance, so night gets the dark pixels")
    @MainActor
    func drawsMatchingAppearance() {
        let combined = MenuBarAppearanceImage.combining(
            light: swatch(.black), dark: swatch(.white))

        let light = sample(combined, appearance: .aqua)
        let dark = sample(combined, appearance: .darkAqua)

        #expect(light < 0.1, "light menu bar should draw the black variant")
        #expect(dark > 0.9, "dark menu bar should draw the white variant")
    }
}

private func swatch(_ color: NSColor, size: NSSize = NSSize(width: 4, height: 4)) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

/// Average brightness of the image when drawn under `appearance`.
private func sample(_ image: NSImage, appearance name: NSAppearance.Name) -> CGFloat {
    let appearance = NSAppearance(named: name)!
    let size = image.size
    let pixelsWide = max(Int(size.width), 1)
    let pixelsHigh = max(Int(size.height), 1)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
    else { return -1 }

    appearance.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    guard let color = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
        return -1
    }
    return (color.redComponent + color.greenComponent + color.blueComponent) / 3
}
