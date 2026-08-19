import Foundation
import RationKit

@MainActor
enum CLIContext {

    static func registry(config: CLIConfig) -> ProviderRegistry {
        ProviderRegistry.standard(schedule: config.schedule, disabled: config.disabled)
    }

    static func historyEntry(
        registry: ProviderRegistry, providerID: String?
    ) -> ProviderRegistry.Entry? {
        let withHistory = registry.metered.filter { $0.history != nil }
        guard let providerID else { return withHistory.first }
        return withHistory.first { $0.provider.id == providerID }
    }

    static func prepareHistories(registry: ProviderRegistry) async {
        for entry in registry.metered {
            entry.history?.loadCheckpoint()
            entry.history?.refresh()
        }
        for entry in registry.metered {
            if let history = entry.history {
                await waitForScan(history)
            }
        }
    }

    static func waitForScan(_ store: TranscriptStore, timeout: TimeInterval = 600) async {
        let deadline = Date().addingTimeInterval(timeout)
        while case .scanning = store.status {
            if Date() > deadline { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func dexInput(registry: ProviderRegistry) -> DexInput {
        var histories: [String: UsageHistory] = [:]
        var live: Set<String> = []
        for entry in registry.metered {
            if let history = entry.history?.history {
                histories[entry.provider.id] = history
            }
            if snapshotShowsUsage(entry.poller.state.snapshot) {
                live.insert(entry.provider.id)
            }
        }
        return DexInput(histories: histories, liveProviders: live)
    }

    private static func snapshotShowsUsage(_ snapshot: UsageSnapshot?) -> Bool {
        guard let snapshot else { return false }
        if snapshot.limits.contains(where: { $0.percent > 0 }) { return true }
        if let spend = snapshot.spend, spend.usedAmount > 0 { return true }
        return false
    }
}
