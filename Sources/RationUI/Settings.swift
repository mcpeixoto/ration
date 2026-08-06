import Foundation
import Observation
import RationKit
import ServiceManagement

/// User preferences, backed by `UserDefaults`.
///
/// Wrapped in an object rather than scattered `@AppStorage` properties so the
/// defaults live in one place and can be exercised in tests.
@MainActor
@Observable
public final class Settings {

    private enum Key {
        static let displayMode = "displayMode"
        static let useSeverityColor = "useSeverityColor"
        static let pollInterval = "pollInterval"
        static let notifyOnThresholds = "notifyOnThresholds"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.displayMode =
            defaults.string(forKey: Key.displayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .sessionPercent
        // A coloured menu bar is a strong opinion; let people opt in.
        self.useSeverityColor = defaults.bool(forKey: Key.useSeverityColor)
        self.pollInterval =
            defaults.object(forKey: Key.pollInterval) as? Double ?? 60
        self.notifyOnThresholds =
            defaults.object(forKey: Key.notifyOnThresholds) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    public var displayMode: MenuBarDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    public var useSeverityColor: Bool {
        didSet { defaults.set(useSeverityColor, forKey: Key.useSeverityColor) }
    }

    /// Seconds between refreshes while the popover is closed.
    public var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Key.pollInterval) }
    }

    public var notifyOnThresholds: Bool {
        didSet { defaults.set(notifyOnThresholds, forKey: Key.notifyOnThresholds) }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// The intervals offered in Settings. The floor comes from `PollSchedule`,
    /// which enforces it regardless of what is stored here.
    public static let pollIntervalOptions: [Double] = [30, 60, 120, 300]

    public var schedule: PollSchedule {
        PollSchedule(idleInterval: pollInterval, openInterval: 10)
    }

    // MARK: Launch at login

    /// Reads through to the system rather than caching, so the toggle reflects
    /// reality even if the user changed it in System Settings.
    public var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration fails for unsigned or non-bundled builds, which
                // is normal during development. Nothing actionable for the user.
                launchAtLoginError = error.localizedDescription
            }
        }
    }

    public var launchAtLoginError: String?
}
