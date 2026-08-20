import Foundation

/// The curves the Linux tray animates along.
///
/// SwiftUI supplies these on macOS. Cairo has no animation model at all, so the
/// tray advances the values itself — and the curves live here, away from the
/// drawing code, so they can be checked without a display.
public enum MotionCurve {

    /// Progress through an animation that began at `start`, 0…1.
    public static func progress(
        since start: Date, duration: TimeInterval, now: Date = Date()
    ) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / duration, 0), 1)
    }

    /// Ease-out, for entrances that should land rather than stop.
    public static func easeOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// A settling spring with a little overshoot, matching `.spring` on the
    /// Mac closely enough that the pack-rip feels the same.
    public static func spring(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        guard clamped < 1 else { return 1 }
        return 1 - exp(-6 * clamped) * cos(7 * clamped)
    }
}
