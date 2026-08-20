import Foundation
import RationKit

/// Desktop alerts when a limit is approached.
///
/// `ThresholdTracker` decides when there is something worth saying — once per
/// threshold per window, never on the first snapshot after launch — and this
/// hands the result to the desktop's notification daemon.
@MainActor
final class TrayNotifier {

    private var trackers: [String: ThresholdTracker] = [:]

    func handle(_ snapshot: UsageSnapshot, from provider: Provider) {
        var tracker = trackers[provider.id] ?? ThresholdTracker()
        let alerts = tracker.alerts(for: snapshot)
        trackers[provider.id] = tracker

        for alert in alerts {
            deliver(title: "\(provider.displayName) · \(alert.title)", body: alert.body)
        }
    }

    private func deliver(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/notify-send")
        process.arguments = [
            "-a", "Ration", "-i", "ration", "-h", "string:desktop-entry:ration", title, body,
        ]
        try? process.run()
    }
}
