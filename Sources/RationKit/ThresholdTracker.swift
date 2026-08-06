import Foundation

/// A notification Ration wants to show.
public struct ThresholdAlert: Sendable, Equatable, Identifiable {

    public enum Kind: Sendable, Equatable {
        /// Usage climbed past a threshold.
        case crossed(threshold: Int)
        /// The window rolled over and the allowance is fresh again.
        case reset
    }

    public let limitID: String
    public let limitName: String
    public let kind: Kind
    public let percent: Double

    public var id: String {
        switch kind {
        case .crossed(let threshold): "\(limitID)-crossed-\(threshold)"
        case .reset: "\(limitID)-reset"
        }
    }

    public var title: String {
        switch kind {
        case .crossed(let threshold):
            threshold >= 95
                ? "\(limitName) limit almost reached"
                : "\(limitName) usage at \(threshold)%"
        case .reset:
            "\(limitName) allowance reset"
        }
    }

    public var body: String {
        switch kind {
        case .crossed(let threshold):
            threshold >= 95
                ? "You've used \(Int(percent))% of your \(limitName.lowercased()) allowance."
                : "You've used \(Int(percent))% of your \(limitName.lowercased()) allowance."
        case .reset:
            "Your \(limitName.lowercased()) allowance has rolled over."
        }
    }
}

/// Decides when to raise a notification, and — more importantly — when not to.
///
/// The rules that matter:
/// - Each threshold fires at most once per window. Polling every minute must
///   not produce a notification every minute.
/// - The first snapshot after launch never notifies. Opening the app at 90%
///   should not immediately fire two alerts about a situation you already knew.
/// - A window rollover re-arms the thresholds, so the next climb notifies again.
public struct ThresholdTracker: Sendable {

    /// Percentages worth interrupting someone for.
    public static let defaultThresholds = [80, 95]

    private let thresholds: [Int]
    private let notifyOnReset: Bool

    /// Per-limit memory of what we have already said.
    private var fired: [String: Set<Int>] = [:]
    /// Per-limit reset time, to detect a rollover.
    private var windows: [String: Date] = [:]
    private var hasSeenFirstSnapshot = false

    public init(
        thresholds: [Int] = ThresholdTracker.defaultThresholds,
        notifyOnReset: Bool = true
    ) {
        self.thresholds = thresholds.sorted()
        self.notifyOnReset = notifyOnReset
    }

    /// Feeds in a new snapshot and returns the alerts to show.
    public mutating func alerts(for snapshot: UsageSnapshot) -> [ThresholdAlert] {

        // Prime state on the first snapshot without notifying: we have no idea
        // whether the user just crossed 80% or has been sitting there all day.
        guard hasSeenFirstSnapshot else {
            hasSeenFirstSnapshot = true
            for limit in snapshot.limits {
                fired[limit.id] = Set(thresholds.filter { Double($0) <= limit.percent })
                windows[limit.id] = limit.resetsAt
            }
            return []
        }

        var alerts: [ThresholdAlert] = []

        for limit in snapshot.limits {
            let didReset = self.didReset(limit)

            if didReset {
                fired[limit.id] = []
                if notifyOnReset {
                    alerts.append(
                        ThresholdAlert(
                            limitID: limit.id, limitName: limit.displayName,
                            kind: .reset, percent: limit.percent))
                }
            }
            windows[limit.id] = limit.resetsAt

            var alreadyFired = fired[limit.id] ?? []

            // Drop below a threshold and it re-arms, so a genuine second climb
            // is reported.
            alreadyFired = alreadyFired.filter { Double($0) <= limit.percent }

            for threshold in thresholds
            where limit.percent >= Double(threshold) && !alreadyFired.contains(threshold) {
                alreadyFired.insert(threshold)
                alerts.append(
                    ThresholdAlert(
                        limitID: limit.id, limitName: limit.displayName,
                        kind: .crossed(threshold: threshold), percent: limit.percent))
            }

            fired[limit.id] = alreadyFired
        }

        // Only ever mention the highest threshold crossed per limit — being told
        // "80%" and "95%" in the same instant is noise.
        return dedupePerLimit(alerts)
    }

    private func didReset(_ limit: UsageLimit) -> Bool {
        guard let previous = windows[limit.id] ?? nil,
            let current = limit.resetsAt
        else { return false }
        return current > previous
    }

    private func dedupePerLimit(_ alerts: [ThresholdAlert]) -> [ThresholdAlert] {
        var best: [String: ThresholdAlert] = [:]

        for alert in alerts {
            guard let existing = best[alert.limitID] else {
                best[alert.limitID] = alert
                continue
            }
            if rank(alert) > rank(existing) {
                best[alert.limitID] = alert
            }
        }
        return alerts.filter { best[$0.limitID]?.id == $0.id }
    }

    private func rank(_ alert: ThresholdAlert) -> Int {
        switch alert.kind {
        case .reset: -1
        case .crossed(let threshold): threshold
        }
    }
}
