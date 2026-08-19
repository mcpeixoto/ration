import SwiftUI

/// Whether views should play their entrance animations.
///
/// True in the running app. Set false by the preview renderer, which draws a
/// single static frame and would otherwise capture views mid-animation.
public struct RationAnimatesEntranceKey: EnvironmentKey {
    public static let defaultValue = true
}

extension EnvironmentValues {
    public var rationAnimatesEntrance: Bool {
        get { self[RationAnimatesEntranceKey.self] }
        set { self[RationAnimatesEntranceKey.self] = newValue }
    }
}

/// A clock for the card illustrations, in seconds.
///
/// Nil in the running app, where the portraits follow the display link. The
/// video renderer sets it to the scene's own time so the creatures animate as
/// a pure function of the timeline rather than of how long the render took.
public struct RationArtTimeKey: EnvironmentKey {
    public static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    public var rationArtTime: Double? {
        get { self[RationArtTimeKey.self] }
        set { self[RationArtTimeKey.self] = newValue }
    }
}
