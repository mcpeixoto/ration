import Foundation
import RationKit

/// Persistent CLI settings, stored under XDG config on Linux and Application
/// Support elsewhere.
struct CLIConfig: Codable, Equatable {
    var pollInterval: TimeInterval = 60
    var notifyOnThresholds: Bool = true
    var disabledProviders: [String] = []
    var revealedCreatureIDs: [String] = []

    static var url: URL {
        #if os(Linux)
        PlatformPaths.home.appending(path: ".config/ration/config.json")
        #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Ration/cli-config.json")
        #endif
    }

    static func load() -> CLIConfig {
        let url = url
        guard let data = try? Data(contentsOf: url) else { return CLIConfig() }
        return (try? JSONDecoder().decode(CLIConfig.self, from: data)) ?? CLIConfig()
    }

    func save() {
        let url = Self.url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    var disabled: Set<Provider.ID> { Set(disabledProviders) }
    var revealed: Set<String> { Set(revealedCreatureIDs) }

    var schedule: PollSchedule {
        PollSchedule(idleInterval: max(60, pollInterval))
    }
}
