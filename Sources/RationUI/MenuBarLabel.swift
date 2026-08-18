import RationKit
import SwiftUI

/// The menu bar item: one gauge (or more) for every account that is on.
///
/// macOS renders menu bar label images as templates, which strips colour. So
/// whenever the item needs colour — a tint, or the bar — the whole label is
/// drawn into a single non-template `NSImage`. Without colour we hand SwiftUI
/// the plain views and let the system tint them for the current appearance,
/// which keeps text crisper and adapts to menu bar transparency.
public struct MenuBarLabel: View {

    let strip: MenuBarStrip

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
        Group {
            if needsColor {
                Image(nsImage: renderedImage())
            } else {
                plainLabel
            }
        }
        .accessibilityLabel(strip.accessibilityLabel)
    }

    /// Colour survives only through the bitmap path.
    private var needsColor: Bool {
        strip.items.contains { $0.tint != nil || $0.bar != nil }
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
        let renderer = ImageRenderer(content: content)
        // Render at the screen's pixel density so text stays sharp.
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return NSImage(
                systemSymbolName: strip.items.first?.symbolName
                    ?? "gauge.with.dots.needle.0percent",
                accessibilityDescription: strip.accessibilityLabel) ?? NSImage()
        }
        // Not a template: we want our colours, not the menu bar's.
        image.isTemplate = false
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
