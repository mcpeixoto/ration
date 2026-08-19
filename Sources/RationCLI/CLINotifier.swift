import Foundation
import RationKit

/// Delivers threshold alerts on the CLI via the platform's desktop notification API.
@MainActor
final class CLINotifier {
    private var trackers: [String: ThresholdTracker] = [:]

    func handle(
        _ snapshot: UsageSnapshot, from provider: Provider, enabled: Bool
    ) {
        var tracker = trackers[provider.id] ?? ThresholdTracker()
        let alerts = tracker.alerts(for: snapshot)
        trackers[provider.id] = tracker

        guard enabled, !alerts.isEmpty else { return }

        for alert in alerts {
            let title = "\(provider.displayName) · \(alert.title)"
            deliver(title: title, body: alert.body)
        }
    }

    private func deliver(title: String, body: String) {
        #if os(macOS)
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        #elseif os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/notify-send")
        process.arguments = ["-a", "Ration", title, body]
        try? process.run()
        #endif
    }
}
