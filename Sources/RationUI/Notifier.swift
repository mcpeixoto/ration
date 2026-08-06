import Foundation
import RationKit
import UserNotifications

/// Delivers threshold alerts as native notifications.
///
/// All the "should this fire?" logic lives in `ThresholdTracker`, which is pure
/// and tested. This type only handles permission and delivery.
@MainActor
public final class Notifier {

    private var tracker = ThresholdTracker()
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
    public func handle(_ snapshot: UsageSnapshot, enabled: Bool) async {
        // Always feed the tracker, even when notifications are off, so that
        // turning them on later does not fire a backlog of stale alerts.
        let alerts = tracker.alerts(for: snapshot)
        guard enabled, !alerts.isEmpty, let center else { return }

        await requestAuthorizationIfNeeded()

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default

            // Identifier includes the threshold, so a later, higher alert is a
            // new notification rather than a replacement.
            let request = UNNotificationRequest(
                identifier: alert.id, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
