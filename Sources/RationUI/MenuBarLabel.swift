import AppKit
import RationKit
import SwiftUI

/// The menu bar item: one gauge (or more) for every account that is on.
///
/// macOS renders menu bar label images as templates, which strips colour. A
/// healthy item — icon, percentage, even a monochrome weekly bar — stays a
/// template so the system can tint it for the current menu bar, including a
/// dark wallpaper at night. Colour (a severity tint, or an amber/red bar)
/// cannot be templated, so that path is drawn into a non-template image that
/// picks its light or dark pixels from the appearance at draw time.
public struct MenuBarLabel: View {

    let strip: MenuBarStrip

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    public init(strip: MenuBarStrip) {
        self.strip = strip
    }

    public init(presentation: MenuBarPresentation) {
        self.strip = MenuBarStrip(items: [presentation])
    }

    /// Vertical, so it reads as a level gauge rather than a progress bar and
    /// costs almost no width in a crowded menu bar.
    private let barSize = CGSize(width: 5, height: 13)

    public var body: some View {
        // Read so SwiftUI drops a stale bitmap when Dark Mode, contrast, or
        // the display scale changes. Wallpaper-based menu-bar light/dark is
        // handled by redrawing the image from the current appearance.
        let appearanceToken =
            "\(colorScheme)-\(displayScale)-\(MenuBarAppearance.shared.generation)"
        Group {
            if strip.hasChromaticColor {
                Image(nsImage: renderedImage())
                    .renderingMode(.original)
            } else {
                plainLabel
            }
        }
        .accessibilityLabel(strip.accessibilityLabel)
        .id(appearanceToken)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            ForEach(Array(strip.items.enumerated()), id: \.offset) { _, item in
                itemContent(item)
            }
        }
    }

    @ViewBuilder
    private func itemContent(_ presentation: MenuBarPresentation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: presentation.symbolName)

            if let title = presentation.title {
                Text(title)
                    .font(.system(size: 13))
                    .monospacedDigit()
            }

            if let bar = presentation.bar {
                WeeklyBar(bar: bar, size: barSize)
            }
        }
        .foregroundStyle(presentation.tint?.color ?? .primary)
        .help(presentation.tooltip)
    }

    private var plainLabel: some View {
        content
    }

    // MARK: Bitmap path

    private func renderedImage() -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? displayScale
        let light = render(scheme: .light, scale: scale)
        let dark = render(scheme: .dark, scale: scale)
        guard light.size != .zero || dark.size != .zero else {
            return fallbackSymbol
        }
        return MenuBarAppearanceImage.combining(light: light, dark: dark)
    }

    private func render(scheme: ColorScheme, scale: CGFloat) -> NSImage {
        let name: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else { return NSImage() }
        var rendered: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(
                content: content.environment(\.colorScheme, scheme)
            )
            renderer.scale = scale
            rendered = renderer.nsImage
        }
        return rendered ?? NSImage()
    }

    private var fallbackSymbol: NSImage {
        NSImage(
            systemSymbolName: strip.items.first?.symbolName
                ?? "gauge.with.dots.needle.0percent",
            accessibilityDescription: strip.accessibilityLabel) ?? NSImage()
    }
}

// MARK: - Appearance

/// Bumps when macOS changes its appearance so a baked menu-bar image cannot
/// outlive the bar that displays it.
@MainActor
@Observable
final class MenuBarAppearance {
    static let shared = MenuBarAppearance()

    private(set) var generation = 0
    private var observation: NSKeyValueObservation?

    private init() {
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.generation += 1
            }
        }
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.generation += 1
            }
        }
    }
}

// MARK: - Dual-appearance image

/// One non-template image that redraws for the current appearance — Dark Mode,
/// night, or a dark wallpaper behind the menu bar.
///
/// Tagging `NSImageRep.appearance` is not a public API. A drawing handler
/// consults `currentDrawing()` at draw time instead, and `cacheMode`
/// is `.never` so AppKit cannot freeze the first variant it saw.
enum MenuBarAppearanceImage {
    static func combining(light: NSImage, dark: NSImage) -> NSImage {
        let size = light.size == .zero ? dark.size : light.size
        let image = NSImage(size: size, flipped: false) { rect in
            let isDark =
                NSAppearance.currentDrawing()
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let source = isDark ? dark : light
            guard source.size != .zero else { return false }
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        return image
    }
}

// MARK: - The bar

/// A small vertical gauge showing how much of the weekly allowance is gone.
///
/// Fills from the bottom, like a fuel gauge. Drawn rather than using
/// `ProgressView`, which brings its own padding and minimum size — neither of
/// which fits a 22pt menu bar.
struct WeeklyBar: View {

    let bar: MenuBarPresentation.Bar
    let size: CGSize

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: size.width / 2, style: .continuous)
                .fill(Color.primary.opacity(0.22))
                .frame(width: size.width, height: size.height)

            RoundedRectangle(cornerRadius: size.width / 2, style: .continuous)
                .fill(fill)
                // Keep a sliver visible at very low usage so the gauge never
                // looks broken or empty.
                .frame(width: size.width, height: max(size.height * bar.fraction, size.width))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// Stays monochrome until it matters. Colour is a warning here, so
    /// spending it on a perfectly healthy 30% would leave nothing to escalate
    /// to — the amber and red only mean something if they are rare.
    private var fill: Color {
        switch bar.severity {
        case .normal: Color.primary.opacity(0.75)
        case .warning: Theme.warning
        case .critical: Theme.critical
        }
    }
}
