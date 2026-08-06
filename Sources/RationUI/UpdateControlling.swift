import Foundation

/// The slice of the updater that the UI needs.
///
/// A protocol so `RationUI` doesn't link Sparkle: only the app target does.
/// Settings can then render an update section without the whole framework
/// following it into every preview and test build.
@MainActor
public protocol UpdateControlling: AnyObject {
    /// Whether Ration checks for updates on its own.
    var automaticallyChecks: Bool { get set }
    /// Whether an update check can run at all — false in unbundled dev builds.
    var canCheck: Bool { get }
    var lastCheck: Date? { get }
    /// Shows Sparkle's update panel.
    func checkNow()
}
