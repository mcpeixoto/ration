import Foundation
import RationKit

@MainActor
enum HistoryCommands {

    static func activity(options: CLIOptions, config: CLIConfig) async {
        let registry = CLIContext.registry(config: config)
        await CLIContext.prepareHistories(registry: registry)
        let loaded = loadedHistories(registry: registry, providerID: options.providerID)
        let days = options.rangeDays

        if options.json {
            printActivityJSON(loaded: loaded, days: days)
            return
        }

        if loaded.isEmpty {
            print("No history available. Install Claude Code or Codex and use them first.")
            return
        }

        for item in loaded {
            print("\(item.provider.displayName) — Activity (\(days) days)")
            print()
            if case .scanning(let progress) = item.status {
                print("  Reading history… \(Int(progress * 100))%")
                print()
                continue
            }
            if item.history.isEmpty {
                print("  No history yet.")
                print()
                continue
            }

            let now = Date()
            let window = item.history.window(days: days, endingOn: now)
            let totals = item.history.total(over: window)
            let streak = item.history.currentStreak(endingOn: now)
            let peak = max(window.map(\.billableTokens).max() ?? 0, 1)

            print("  Heat map")
            printHeatMap(window: window, peak: peak, now: now)
            print()
            print("  Streak: \(streak) day\(streak == 1 ? "" : "s")")
            print("  Sessions: \(totals.sessions)")
            if let busiest = totals.busiestDay, busiest.billableTokens > 0 {
                print("  Busiest: \(CLIFormat.shortDate(busiest.date))")
            }
            if let hour = totals.busiestHour {
                print("  Peak hour: \(CLIFormat.hourLabel(hour))")
            }
            print()
        }
    }

    static func trends(options: CLIOptions, config: CLIConfig) async {
        let registry = CLIContext.registry(config: config)
        await CLIContext.prepareHistories(registry: registry)
        let loaded = loadedHistories(registry: registry, providerID: options.providerID)
        let days = options.rangeDays

        if options.json {
            printTrendsJSON(loaded: loaded, days: days)
            return
        }

        if loaded.isEmpty {
            print("No history available.")
            return
        }

        for item in loaded {
            print("\(item.provider.displayName) — Trends (\(days) days)")
            print()
            if item.history.isEmpty {
                print("  No history yet.")
                print()
                continue
            }

            let now = Date()
            let window = item.history.window(days: days, endingOn: now)
            let totals = item.history.total(over: window)
            let peak = max(window.map(\.billableTokens).max() ?? 0, 1)

            print("  Tokens: \(CLIFormat.tokens(totals.tokens))")
            print("  Messages: \(CLIFormat.compact(totals.messages))")
            print("  Sessions: \(totals.sessions)")
            print("  Active days: \(totals.activeDays)")
            print(
                totals.uncostedTokens > 0
                    ? "  Est. cost: ≥ \(CLIFormat.cost(totals.cost))"
                    : "  Est. cost: \(CLIFormat.cost(totals.cost))"
            )
            print()
            print("  Daily tokens")
            for day in window where day.date <= now {
                let bar = CLIFormat.progressBar(
                    Double(day.billableTokens) / Double(peak) * 100, width: 16)
                let label =
                    day.billableTokens > 0
                    ? CLIFormat.compact(day.billableTokens).padding(
                        toLength: 6, withPad: " ", startingAt: 0)
                    : "      "
                print(
                    "  \(CLIFormat.shortDate(day.date).padding(toLength: 6, withPad: " ", startingAt: 0)) \(bar) \(label)"
                )
            }
            print()
        }
    }

    static func detail(options: CLIOptions, config: CLIConfig) async {
        let registry = CLIContext.registry(config: config)
        await CLIContext.prepareHistories(registry: registry)
        let loaded = loadedHistories(registry: registry, providerID: options.providerID)
        let days = options.rangeDays

        if options.json {
            printDetailJSON(loaded: loaded, days: days)
            return
        }

        if loaded.isEmpty {
            print("No history available.")
            return
        }

        for item in loaded {
            print("\(item.provider.displayName) — Detail (\(days) days)")
            print()
            if item.history.isEmpty {
                print("  No history yet.")
                print()
                continue
            }

            let window = item.history.window(days: days, endingOn: Date())
            let totals = item.history.total(over: window)

            print("  Models")
            printRanked(totals.rankedModels, total: totals.tokens)
            print()
            print("  Projects")
            printRanked(Array(totals.rankedProjects.prefix(6)), total: totals.tokens)
            print()
        }
    }

    // MARK: - Helpers

    private struct LoadedHistory {
        let provider: Provider
        let history: UsageHistory
        let status: TranscriptStore.Status
    }

    private static func loadedHistories(
        registry: ProviderRegistry, providerID: String?
    ) -> [LoadedHistory] {
        let entries = registry.metered.filter { $0.history != nil }
        let filtered: [ProviderRegistry.Entry]
        if let providerID {
            filtered = entries.filter { $0.provider.id == providerID }
        } else {
            filtered = entries
        }
        return filtered.compactMap { entry in
            guard let store = entry.history else { return nil }
            return LoadedHistory(
                provider: entry.provider, history: store.history, status: store.status)
        }
    }

    private static func printHeatMap(window: [DayUsage], peak: Int, now: Date) {
        let levels = [" ", "░", "▒", "▓", "█"]
        for week in stride(from: 0, to: window.count, by: 7) {
            let slice = Array(window[week..<min(week + 7, window.count)])
            let row = slice.map { day -> String in
                guard day.date <= now, day.billableTokens > 0 else { return " " }
                let intensity = (Double(day.billableTokens) / Double(peak)).squareRoot()
                let index = min(levels.count - 1, max(1, Int(intensity * Double(levels.count - 1))))
                return levels[index]
            }.joined()
            print("  \(row)")
        }
    }

    private static func printRanked(_ entries: [(name: String, tokens: Int)], total: Int) {
        if entries.isEmpty {
            print("    Nothing in this period.")
            return
        }
        for entry in entries {
            let share = total > 0 ? Int((Double(entry.tokens) / Double(total) * 100).rounded()) : 0
            print(
                "    \(entry.name.padding(toLength: 22, withPad: " ", startingAt: 0)) "
                    + "\(CLIFormat.tokens(entry.tokens).padding(toLength: 8, withPad: " ", startingAt: 0)) "
                    + "\(share)%")
        }
    }

    private static func printActivityJSON(loaded: [LoadedHistory], days: Int) {
        let now = Date()
        let payload: [[String: Any]] = loaded.map { item in
            let window = item.history.window(days: days, endingOn: now)
            let totals = item.history.total(over: window)
            return [
                "provider": item.provider.id,
                "streak": item.history.currentStreak(endingOn: now),
                "sessions": totals.sessions,
                "busiestHour": totals.busiestHour as Any,
                "days": window.map { day in
                    [
                        "date": CLIFormat.shortDate(day.date),
                        "tokens": day.billableTokens,
                        "sessions": day.sessionCount,
                    ] as [String: Any]
                },
            ] as [String: Any]
        }
        printJSON(payload)
    }

    private static func printTrendsJSON(loaded: [LoadedHistory], days: Int) {
        let now = Date()
        let payload: [[String: Any]] = loaded.map { item in
            let window = item.history.window(days: days, endingOn: now)
            let totals = item.history.total(over: window)
            return [
                "provider": item.provider.id,
                "tokens": totals.tokens,
                "messages": totals.messages,
                "sessions": totals.sessions,
                "activeDays": totals.activeDays,
                "cost": totals.cost,
                "daily": window.filter { $0.date <= now }.map {
                    ["date": CLIFormat.shortDate($0.date), "tokens": $0.billableTokens]
                },
            ] as [String: Any]
        }
        printJSON(payload)
    }

    private static func printDetailJSON(loaded: [LoadedHistory], days: Int) {
        let payload: [[String: Any]] = loaded.map { item in
            let window = item.history.window(days: days, endingOn: Date())
            let totals = item.history.total(over: window)
            return [
                "provider": item.provider.id,
                "models": totals.rankedModels.map { ["name": $0.name, "tokens": $0.tokens] },
                "projects": totals.rankedProjects.prefix(6).map {
                    ["name": $0.name, "tokens": $0.tokens]
                },
            ] as [String: Any]
        }
        printJSON(payload)
    }

    private static func printJSON(_ object: Any) {
        if let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted]),
            let text = String(data: data, encoding: .utf8)
        {
            print(text)
        }
    }
}
