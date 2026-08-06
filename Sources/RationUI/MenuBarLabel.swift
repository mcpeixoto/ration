import RationKit
import SwiftUI

/// The menu bar item: gauge glyph, optional percentage, optional weekly bar.
///
/// macOS renders menu bar label images as templates, which strips colour. So
/// whenever the item needs colour — a tint, or the bar — the whole label is
/// drawn into a single non-template `NSImage`. Without colour we hand SwiftUI
/// the plain views and let the system tint them for the current appearance,
/// which keeps text crisper and adapts to menu bar transparency.
public struct MenuBarLabel: View {

    let presentation: MenuBarPresentation

    public init(presentation: MenuBarPresentation) {
        self.presentation = presentation
    }

    /// Menu bar items live in a 22pt bar; this leaves room above and below.
    private let barSize = CGSize(width: 26, height: 4)

    public var body: some View {
        Group {
            if needsColor {
                Image(nsImage: renderedImage())
            } else {
                plainLabel
            }
        }
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    /// Colour survives only through the bitmap path.
    private var needsColor: Bool {
        presentation.tint != nil || presentation.bar != nil
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
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
    }

    private var plainLabel: some View {
        content
    }

    // MARK: Bitmap path

    private func renderedImage() -> NSImage {
        let renderer = ImageRenderer(
            content:
                content
                .foregroundStyle(presentation.tint?.color ?? .primary)
        )
        // Render at the screen's pixel density so text stays sharp.
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return NSImage(
                systemSymbolName: presentation.symbolName,
                accessibilityDescription: presentation.accessibilityLabel) ?? NSImage()
        }
        // Not a template: we want our colours, not the menu bar's.
        image.isTemplate = false
        return image
    }
}

// MARK: - The bar

/// A tiny capsule showing how much of the weekly allowance is gone.
///
/// Drawn rather than using `ProgressView`, which brings its own padding and
/// minimum size — neither of which fits a 22pt menu bar.
struct WeeklyBar: View {

    let bar: MenuBarPresentation.Bar
    let size: CGSize

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.25))
                .frame(width: size.width, height: size.height)

            Capsule()
                .fill(fill)
                // Keep a sliver visible at very low usage so the bar never
                // looks broken or empty.
                .frame(width: max(size.width * bar.fraction, size.height), height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// Amber and red are the point of the bar, so they are not optional here —
    /// unlike the icon tint, which the user can turn off.
    private var fill: Color {
        switch bar.severity {
        case .normal: Theme.accent
        case .warning: Theme.warning
        case .critical: Theme.critical
        }
    }
}
