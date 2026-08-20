import Foundation
import RationKit

/// Timing for the tray's animations.
///
/// The macOS build gets these from SwiftUI: a ring that sweeps up to its value
/// on appear, bars that fill, a card that springs in when it is caught, and
/// holographic foil that never stops moving. None of that is free here — a
/// Cairo frame is a still — so the panel redraws itself while something is
/// moving, and these are the curves it moves along.
enum Motion {

    /// The desktop's animation preference, honoured the way the Mac honours
    /// Reduce Motion. Cached; people do not toggle it mid-session.
    static var isEnabled: Bool {
        guard let value = GSettings.read("org.gnome.desktop.interface", "enable-animations")
        else { return true }
        return !value.contains("false")
    }

    /// Foil runs at the same 24fps the macOS `TimelineView` asks for. Faster
    /// buys nothing on a shimmer and costs a redraw of the whole panel.
    static let frameInterval: TimeInterval = 1.0 / 24

    /// A monotonic seconds value for the continuous animations.
    static func clock(_ now: Date = Date()) -> Double {
        now.timeIntervalSinceReferenceDate
    }

    /// The curves themselves live in `RationKit`, where they are tested.
    static func easeOut(_ t: Double) -> Double { MotionCurve.easeOut(t) }

    static func spring(_ t: Double) -> Double { MotionCurve.spring(t) }

    static func progress(since start: Date, duration: TimeInterval, now: Date = Date()) -> Double {
        MotionCurve.progress(since: start, duration: duration, now: now)
    }
}
