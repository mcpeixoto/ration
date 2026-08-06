import RationKit
import SwiftUI

/// The menu bar item itself: gauge glyph, optional percentage.
///
/// macOS renders menu bar label images as templates, which strips colour. To
/// honour the severity tint we render the whole label — glyph and text — into a
/// single non-template `NSImage` when a tint is active, and fall back to the
/// plain SwiftUI label (which the system tints correctly for the current
/// appearance) when it is not.
public struct MenuBarLabel: View {

    let presentation: MenuBarPresentation

    public init(presentation: MenuBarPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        if let tint = presentation.tint?.color {
            Image(nsImage: renderedImage(tint: tint))
                .accessibilityLabel(presentation.accessibilityLabel)
        } else {
            plainLabel
                .accessibilityLabel(presentation.accessibilityLabel)
        }
    }

    private var plainLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: presentation.symbolName)
            if let title = presentation.title {
                Text(title).monospacedDigit()
            }
        }
    }

    /// Draws the label to a bitmap so the tint survives the menu bar's
    /// template rendering.
    private func renderedImage(tint: Color) -> NSImage {
        let renderer = ImageRenderer(
            content:
                HStack(spacing: 4) {
                    Image(systemName: presentation.symbolName)
                    if let title = presentation.title {
                        Text(title)
                            .font(.system(size: 13))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(tint)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return NSImage(
                systemSymbolName: presentation.symbolName,
                accessibilityDescription: presentation.accessibilityLabel)
                ?? NSImage()
        }
        // Not a template: we want our colour, not the menu bar's.
        image.isTemplate = false
        return image
    }
}

extension MenuBarPresentation {
    /// A monospaced-digit menu bar title never changes width as the number
    /// changes, so the item does not jitter once a minute.
    var hasTitle: Bool { title != nil }
}
