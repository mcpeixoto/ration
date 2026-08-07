import Foundation
import RationKit
import UserNotifications

/// Delivers threshold alerts as native notifications.
///
/// All the "should this fire?" logic lives in `ThresholdTracker`, which is pure
/// and tested. This type only handles permission and delivery.
@MainActor
public final class Notifier {

    /// One tracker per provider.
    ///
    /// `ThresholdAlert` keys on the limit's id, and every provider has a limit
    /// called `session`. Sharing one tracker would let Claude crossing 80%
    /// suppress Codex crossing 80% — the alert that matters most, silently.
    private var trackers: [String: ThresholdTracker] = [:]
    private var hasRequestedAuthorization = false
    private let center: UNUserNotificationCenter?

    public init() {
        // `UNUserNotificationCenter.current()` traps in processes without a
        // bundle identifier, such as `swift run` during development.
        self.center = Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// Asked for lazily, the first time we actually have something to say,
    /// rather than with a permission prompt at launch.
    private func requestAuthorizationIfNeeded() async {
        guard let center, !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Feeds a new snapshot in and delivers whatever it warrants.
    public func handle(
        _ snapshot: UsageSnapshot, from provider: Provider = .claude, enabled: Bool
    ) async {
        // Always feed the tracker, even when notifications are off, so that
        // turning them on later does not fire a backlog of stale alerts.
        var tracker = trackers[provider.id] ?? ThresholdTracker()
        let alerts = tracker.alerts(for: snapshot)
        trackers[provider.id] = tracker

        guard enabled, !alerts.isEmpty, let center else { return }

        await requestAuthorizationIfNeeded()

        for alert in alerts {
            let content = UNMutableNotificationContent()
            // Which tool is running out matters as much as the fact that one is.
            content.title = "\(provider.displayName) · \(alert.title)"
            content.body = alert.body
            content.sound = .default

            // Identifier includes the threshold, so a later, higher alert is a
            // new notification rather than a replacement — and the provider, so
            // two tools crossing the same line are two notifications.
            let request = UNNotificationRequest(
                identifier: "\(provider.id)|\(alert.id)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
