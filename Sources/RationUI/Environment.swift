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
