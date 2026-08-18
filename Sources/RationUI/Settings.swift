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
        static let showWeeklyBar = "showWeeklyBar"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let primaryProvider = "primaryProvider"
        static let disabledProviders = "disabledProviders"
        static let hasAppliedLoginItemDefault = "hasAppliedLoginItemDefault"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.displayMode =
            defaults.string(forKey: Key.displayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .sessionPercent
        // Colour earns its place here: the whole point of the menu bar item is
        // to warn you before you run out, and a monochrome warning is not one.
        // Still a setting, for anyone who keeps a strictly grey menu bar.
        self.useSeverityColor =
            defaults.object(forKey: Key.useSeverityColor) as? Bool ?? true
        self.showWeeklyBar =
            defaults.object(forKey: Key.showWeeklyBar) as? Bool ?? true
        let storedInterval = defaults.object(forKey: Key.pollInterval) as? Double ?? 60
        // 30s used to be offered; it is now below the floor. Map it to 60 so
        // the picker has a matching option rather than a blank selection.
        self.pollInterval =
            Self.pollIntervalOptions.contains(storedInterval) ? storedInterval : 60
        self.notifyOnThresholds =
            defaults.object(forKey: Key.notifyOnThresholds) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.primaryProvider =
            defaults.string(forKey: Key.primaryProvider).flatMap(Provider.named) ?? .claude
        // Ids from a future release are dropped rather than kept: an unknown
        // provider cannot be shown in the Accounts tab, so a set holding one
        // would be impossible to clear from the UI.
        self.disabledProviders = Set(
            (defaults.stringArray(forKey: Key.disabledProviders) ?? [])
                .filter { Provider.named($0) != nil })
    }

    /// Which provider the panel opens on.
    ///
    /// The menu bar reports every account that is on. The panel still has to
    /// pick one to show first; this is that pick, and it is what hiding the
    /// current one promotes the next into.
    public var primaryProvider: Provider {
        didSet { defaults.set(primaryProvider.id, forKey: Key.primaryProvider) }
    }

    /// Providers the user turned off in Settings → Accounts.
    ///
    /// Hidden means hidden *and* unread: the registry stops polling them. The
    /// disabled set is stored rather than the enabled one so a fresh install
    /// stores nothing, and a provider added in a later release arrives
    /// switched on instead of silently hidden.
    ///
    /// Sorted on the way out purely so the stored value is stable and diffable.
    public var disabledProviders: Set<String> {
        didSet {
            defaults.set(disabledProviders.sorted(), forKey: Key.disabledProviders)
        }
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

    /// Whether the menu bar item carries a small weekly-usage bar.
    ///
    /// The weekly window is the one that creeps up on you — a session resets
    /// often enough to watch itself.
    public var showWeeklyBar: Bool {
        didSet { defaults.set(showWeeklyBar, forKey: Key.showWeeklyBar) }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// The intervals offered in Settings. The floor comes from `PollSchedule`,
    /// which enforces it regardless of what is stored here.
    public static let pollIntervalOptions: [Double] = [60, 120, 300]

    public var schedule: PollSchedule {
        PollSchedule(idleInterval: pollInterval, openInterval: pollInterval)
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

    /// Turns launch at login on the first time a build runs, and never again.
    ///
    /// A menu bar gauge that is not running tells you nothing, so the useful
    /// default is on. It is applied once and recorded, so switching it off in
    /// Settings — or in System Settings — sticks rather than being re-enabled
    /// on the next launch.
    ///
    /// Registration fails for unsigned or ad-hoc bundles. That is recorded too:
    /// retrying every launch would just re-throw the same error, and a properly
    /// signed build gets its chance on first run.
    public func applyLoginItemDefaultIfNeeded() {
        guard !defaults.bool(forKey: Key.hasAppliedLoginItemDefault) else { return }
        defaults.set(true, forKey: Key.hasAppliedLoginItemDefault)
        guard SMAppService.mainApp.status != .enabled else { return }
        launchesAtLogin = true
    }
}
