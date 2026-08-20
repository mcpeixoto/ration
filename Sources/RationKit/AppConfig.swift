import Foundation

/// Persistent settings shared by the Linux tray and the CLI.
///
/// macOS keeps these in `UserDefaults`, which the menu bar app and its
/// Settings window both read. Linux has two front ends over the same data —
/// `ration` and `ration-tray` — so the equivalent lives in one JSON file that
/// both load and save. Unknown keys decode to their defaults, so a file
/// written by an older build still opens.
public struct AppConfig: Codable, Equatable, Sendable {

    /// Seconds between polls. Floored at 60 when turned into a schedule.
    public var pollInterval: TimeInterval = 60
    /// Desktop alerts when a limit is approached.
    public var notifyOnThresholds: Bool = true
    /// Accounts the user turned off in Settings → Accounts.
    public var disabledProviders: [String] = []
    /// Creatures whose unlock has already been announced.
    public var revealedCreatureIDs: [String] = []

    /// Which number the tray shows. Ignored by the CLI, which always prints
    /// every limit.
    public var menuBarDisplayMode: String = MenuBarDisplayMode.highestPercent.rawValue
    /// Whether the tray turns amber and red as limits are approached.
    public var useSeverityColor: Bool = false
    /// Whether the tray draws the small weekly allowance bar.
    public var showWeeklyBar: Bool = true
    /// The account the tray gauges by default.
    public var primaryProviderID: String = Provider.claude.id
    /// Set once the welcome screen has been dismissed.
    public var hasCompletedOnboarding: Bool = false
    /// How large the tray's windows are drawn. Zero means "work it out from
    /// the display", which is what most people want; a number overrides it.
    ///
    /// macOS has no equivalent because AppKit resolves points to a physical
    /// size for you. X11 does not, so this is the knob that stands in for it.
    public var uiScale: Double = 0

    public init() {}

    public static var url: URL {
        #if os(Linux)
        PlatformPaths.home.appending(path: ".config/ration/config.json")
        #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Ration/cli-config.json")
        #endif
    }

    public static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    public func save() {
        let url = Self.url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public var disabled: Set<Provider.ID> { Set(disabledProviders) }
    public var revealed: Set<String> { Set(revealedCreatureIDs) }

    public var schedule: PollSchedule {
        PollSchedule(idleInterval: max(60, pollInterval))
    }

    public var displayMode: MenuBarDisplayMode {
        get { MenuBarDisplayMode(rawValue: menuBarDisplayMode) ?? .highestPercent }
        set { menuBarDisplayMode = newValue.rawValue }
    }

    public var primaryProvider: Provider {
        get { Provider.named(primaryProviderID) ?? .claude }
        set { primaryProviderID = newValue.id }
    }
}
