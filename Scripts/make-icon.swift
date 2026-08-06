#!/usr/bin/env swift
//
// Generates Resources/AppIcon.icns.
//
// The icon is drawn in code rather than checked in as a binary blob, so it is
// reviewable in a diff and reproducible from source.
//
// Usage: swift Scripts/make-icon.swift

import AppKit
import Foundation

// MARK: - Drawing

/// Draws the Ration mark: a squircle with a three-quarter gauge ring.
func drawIcon(size: CGFloat, in context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // macOS icons sit inset within their canvas rather than filling it.
    let inset = size * 0.086
    let body = rect.insetBy(dx: inset, dy: inset)
    // Apple's continuous-corner radius is very close to 22.37% of the side.
    let radius = body.width * 0.2237

    context.saveGState()

    // Background: a deep blue gradient, lighter at the top left.
    let path = CGPath(
        roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.267, green: 0.545, blue: 0.980, alpha: 1),
            CGColor(red: 0.118, green: 0.310, blue: 0.812, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )
    context.resetClip()
    context.restoreGState()

    // The gauge ring, matching the one in the app: starts at twelve o'clock,
    // sweeps clockwise about three quarters of the way round.
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = body.width * 0.285
    let lineWidth = body.width * 0.115

    context.setLineCap(.round)
    context.setLineWidth(lineWidth)

    // Track.
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
    context.addArc(
        center: centre, radius: ringRadius,
        startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
    context.strokePath()

    // Fill, to 72%.
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.addArc(
        center: centre, radius: ringRadius,
        startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * 0.72, clockwise: true)
    context.strokePath()
}

func makeImage(size: CGFloat, scale: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphicsContext
    // No manual scaling here: the context already maps `rep.size` onto the
    // bitmap's pixel dimensions, so scaling again would draw at double size.
    drawIcon(size: size, in: graphicsContext.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return rep
}

// MARK: - Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects.
let variants: [(size: CGFloat, scale: CGFloat, name: String)] = [
    (16, 1, "icon_16x16.png"), (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"), (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"), (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"), (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"), (512, 2, "icon_512x512@2x.png"),
]

for variant in variants {
    let rep = makeImage(size: variant.size, scale: variant.scale)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(variant.name)")
    }
    try data.write(to: iconset.appendingPathComponent(variant.name))
}

// Convert to .icns.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns", iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

try? FileManager.default.removeItem(at: iconset)
print("==> Wrote Resources/AppIcon.icns")
