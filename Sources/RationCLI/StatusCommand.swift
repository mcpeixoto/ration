import Foundation
import RationKit

@MainActor
enum StatusCommand {

    static func run(options: CLIOptions, watch: Bool, config: CLIConfig) async {
        let interval = max(60, options.interval ?? config.pollInterval)
        let registry = CLIContext.registry(config: config)
        let notifier = CLINotifier()
        let notificationsEnabled = options.notify || config.notifyOnThresholds

        repeat {
            if watch { print("\u{001B}[2J\u{001B}[H", terminator: "") }
            print("Ration \(Ration.version)")
            if watch {
                print("Refreshing every \(Int(interval))s — Ctrl+C to stop")
                if notificationsEnabled {
                    print("Notifications: on")
                }
            }
            print()

            let entries = filteredEntries(registry: registry, providerID: options.providerID)
            for entry in entries {
                await printEntry(entry, json: options.json)
                if watch, let snapshot = entry.poller.state.snapshot {
                    notifier.handle(
                        snapshot, from: entry.provider, enabled: notificationsEnabled)
                }
                if !options.json { print() }
            }

            guard watch else { return }
            try? await Task.sleep(for: .seconds(interval))
        } while watch
    }

    private static func filteredEntries(
        registry: ProviderRegistry, providerID: String?
    ) -> [ProviderRegistry.Entry] {
        let metered = registry.metered
        guard let providerID else { return metered }
        return metered.filter { $0.provider.id == providerID }
    }

    private static func printEntry(_ entry: ProviderRegistry.Entry, json: Bool) async {
        let provider = entry.provider
        let availability = entry.availability

        guard availability.hasQuota else {
            if json {
                printUnavailableJSON(provider: provider, availability: availability)
            } else {
                print("\(provider.displayName): \(availability.explanation ?? "Unavailable")")
            }
            return
        }

        entry.poller.start()
        defer { entry.poller.suspend() }

        if entry.poller.state.status == .idle {
            await waitForRefresh(entry.poller)
        }

        let state = entry.poller.state
        if json {
            printStateJSON(provider: provider, state: state, availability: availability)
        } else {
            printStateText(provider: provider, state: state, availability: availability)
        }
    }

    private static func waitForRefresh(_ poller: UsagePoller) async {
        let deadline = Date().addingTimeInterval(30)
        while poller.state.status == .idle || poller.state.status == .refreshing {
            if Date() > deadline { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func printStateText(
        provider: Provider, state: UsageState, availability: ProviderAvailability
    ) {
        print("\(provider.displayName)")

        if let reason = availability.explanation, availability != .ready {
            print("  \(reason)")
            return
        }

        switch state.status {
        case .signedOut:
            if let credentialError = state.credentialError {
                print("  \(credentialError.localizedDescription)")
            } else {
                print("  Session expired. Open \(provider.toolName) and sign in again.")
            }
        case .failed(let error):
            print("  \(error.localizedDescription)")
            if let snapshot = state.snapshot {
                print("  (showing last known values)")
                printLimits(snapshot, indent: "  ")
            }
        case .idle, .refreshing:
            print("  Loading…")
        case .ready:
            guard let snapshot = state.snapshot else {
                print("  No usage data.")
                return
            }
            let age = Date().timeIntervalSince(snapshot.fetchedAt)
            if age > 60 {
                print("  As of \(formattedAge(snapshot.fetchedAt))")
            }
            if let plan = snapshot.planName {
                print("  Plan: \(plan)")
            }
            printLimits(snapshot, indent: "  ")
        }
    }

    private static func printLimits(_ snapshot: UsageSnapshot, indent: String) {
        for limit in snapshot.limits {
            let bar = CLIFormat.progressBar(limit.percent)
            let reset =
                limit.resetsAt.map { " · resets \(formattedReset($0))" } ?? ""
            print(
                "\(indent)\(limit.displayName.padding(toLength: 14, withPad: " ", startingAt: 0)) \(bar) \(Int(limit.percent.rounded()))%\(reset)"
            )
        }
    }

    private static func formattedAge(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    private static func formattedReset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func printStateJSON(
        provider: Provider, state: UsageState, availability: ProviderAvailability
    ) {
        var payload: [String: Any] = [
            "provider": provider.id,
            "displayName": provider.displayName,
            "availability": availabilityLabel(availability),
        ]

        if let snapshot = state.snapshot {
            payload["plan"] = snapshot.planName as Any
            payload["fetchedAt"] = ISO8601DateFormatter().string(from: snapshot.fetchedAt)
            payload["limits"] = snapshot.limits.map { limit in
                [
                    "kind": limit.kind.rawValue,
                    "name": limit.displayName,
                    "percent": limit.percent,
                    "resetsAt": limit.resetsAt.map { ISO8601DateFormatter().string(from: $0) }
                        as Any,
                ] as [String: Any]
            }
        }

        if case .signedOut = state.status {
            payload["error"] =
                state.credentialError?.localizedDescription
                ?? "Session expired."
        } else if case .failed(let error) = state.status {
            payload["error"] = error.localizedDescription
        } else if let reason = availability.explanation, availability != .ready {
            payload["error"] = reason
        }

        printJSON(payload)
    }

    private static func printUnavailableJSON(
        provider: Provider, availability: ProviderAvailability
    ) {
        let payload: [String: Any] = [
            "provider": provider.id,
            "displayName": provider.displayName,
            "availability": availabilityLabel(availability),
            "error": availability.explanation as Any,
        ]
        printJSON(payload)
    }

    private static func availabilityLabel(_ availability: ProviderAvailability) -> String {
        switch availability {
        case .ready: "ready"
        case .notInstalled: "not_installed"
        case .noData: "no_data"
        case .quotaNotReadable: "quota_not_readable"
        }
    }

    private static func printJSON(_ payload: [String: Any]) {
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted]),
            let text = String(data: data, encoding: .utf8)
        {
            print(text)
        }
    }
}
