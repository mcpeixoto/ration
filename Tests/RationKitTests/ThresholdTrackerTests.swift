import Foundation
import Testing

@testable import RationKit

private func snapshot(
    session: Double,
    resetsAt: Date? = Date(timeIntervalSince1970: 1_000_000),
    weekly: Double? = nil
) -> UsageSnapshot {
    var limits = [
        UsageLimit(
            kind: .session, group: .session, percent: session,
            severity: .normal, resetsAt: resetsAt, isActive: true)
    ]
    if let weekly {
        limits.append(
            UsageLimit(
                kind: .weeklyAll, group: .weekly, percent: weekly,
                severity: .normal, resetsAt: resetsAt, isActive: false))
    }
    return UsageSnapshot(limits: limits)
}

@Suite("Threshold notifications")
struct ThresholdTrackerTests {

    @Test("the first snapshot never notifies, however bad it looks")
    func firstSnapshotIsSilent() {
        var tracker = ThresholdTracker()
        #expect(tracker.alerts(for: snapshot(session: 99)).isEmpty)
    }

    @Test("notifies once when usage climbs past a threshold")
    func notifiesOnCrossing() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 50))

        let alerts = tracker.alerts(for: snapshot(session: 82))
        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .crossed(threshold: 80))
    }

    @Test("does not notify again while usage stays above the threshold")
    func doesNotRepeat() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 50))
        _ = tracker.alerts(for: snapshot(session: 82))

        // Simulates a minute-by-minute poll sitting in the same band.
        for percent in [83.0, 85.0, 88.0, 90.0, 94.0] {
            #expect(tracker.alerts(for: snapshot(session: percent)).isEmpty)
        }
    }

    @Test("notifies again at the next threshold up")
    func notifiesAtEachThreshold() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 50))
        _ = tracker.alerts(for: snapshot(session: 82))

        let alerts = tracker.alerts(for: snapshot(session: 96))
        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .crossed(threshold: 95))
    }

    @Test("a jump past several thresholds only reports the highest")
    func onlyHighestOnJump() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 10))

        let alerts = tracker.alerts(for: snapshot(session: 97))
        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .crossed(threshold: 95))
    }

    @Test("tracks each limit separately")
    func perLimitTracking() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 10, weekly: 10))

        let alerts = tracker.alerts(for: snapshot(session: 85, weekly: 85))
        #expect(alerts.count == 2)
        #expect(Set(alerts.map(\.limitID)) == ["session", "weekly_all"])
    }

    @Test("a window rollover re-arms the thresholds")
    func resetReArms() {
        let firstWindow = Date(timeIntervalSince1970: 1_000_000)
        let secondWindow = Date(timeIntervalSince1970: 1_018_000)

        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 50, resetsAt: firstWindow))
        _ = tracker.alerts(for: snapshot(session: 85, resetsAt: firstWindow))

        // New window, usage back down.
        let resetAlerts = tracker.alerts(for: snapshot(session: 2, resetsAt: secondWindow))
        #expect(resetAlerts.contains { $0.kind == .reset })

        // Climbing again in the new window notifies again.
        let climbAlerts = tracker.alerts(for: snapshot(session: 85, resetsAt: secondWindow))
        #expect(climbAlerts.contains { $0.kind == .crossed(threshold: 80) })
    }

    @Test("reset notifications can be turned off")
    func resetNotificationsOptional() {
        let first = Date(timeIntervalSince1970: 1_000_000)
        let second = Date(timeIntervalSince1970: 1_018_000)

        var tracker = ThresholdTracker(notifyOnReset: false)
        _ = tracker.alerts(for: snapshot(session: 85, resetsAt: first))
        let alerts = tracker.alerts(for: snapshot(session: 2, resetsAt: second))

        #expect(!alerts.contains { $0.kind == .reset })
    }

    @Test("dropping below a threshold and climbing back notifies again")
    func reArmsOnDrop() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 50))
        _ = tracker.alerts(for: snapshot(session: 85))
        _ = tracker.alerts(for: snapshot(session: 60))

        let alerts = tracker.alerts(for: snapshot(session: 86))
        #expect(alerts.contains { $0.kind == .crossed(threshold: 80) })
    }

    @Test("staying below every threshold is silent")
    func quietBelowThresholds() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 5))

        for percent in stride(from: 10.0, to: 80.0, by: 5) {
            #expect(tracker.alerts(for: snapshot(session: percent)).isEmpty)
        }
    }

    @Test("alert text names the limit and the number")
    func alertText() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 10))
        let alert = tracker.alerts(for: snapshot(session: 96)).first

        let alert2 = try? #require(alert)
        #expect(alert2?.title.contains("Session") == true)
        #expect(alert2?.body.contains("96") == true)
    }

    @Test("every alert has a non-empty title and body")
    func alertsAreWellFormed() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: snapshot(session: 10, weekly: 10))

        let alerts =
            tracker.alerts(for: snapshot(session: 85, weekly: 96))
            + tracker.alerts(
                for: snapshot(
                    session: 1, resetsAt: Date(timeIntervalSince1970: 2_000_000), weekly: 1))

        #expect(!alerts.isEmpty)
        for alert in alerts {
            #expect(!alert.title.isEmpty)
            #expect(!alert.body.isEmpty)
            #expect(!alert.id.isEmpty)
        }
    }
}
