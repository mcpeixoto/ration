import RationKit
import SwiftUI

/// Shared visual vocabulary.
///
/// Everything here resolves through semantic colours and system materials, so
/// light mode, dark mode, Increase Contrast, and accent-colour changes are
/// handled by the system rather than by us guessing hex values.
enum Theme {

    /// Popover width. Wide enough for "Weekly · Fable" plus a percentage,
    /// narrow enough to feel like a menu rather than a window.
    static let popoverWidth: CGFloat = 320
    static let ringSize: CGFloat = 116
}

extension Severity {

    /// The colour that represents this severity, or `nil` at `normal` — normal
    /// deliberately has no colour of its own so it inherits the surrounding
    /// text style.
    var color: Color? {
        switch self {
        case .normal: nil
        case .warning: .orange
        case .critical: .red
        }
    }

    /// A colour that is always safe to draw with, falling back to the accent
    /// colour when there is nothing to warn about.
    var accentColor: Color {
        color ?? .accentColor
    }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Approaching limit"
        case .critical: "At limit"
        }
    }
}
