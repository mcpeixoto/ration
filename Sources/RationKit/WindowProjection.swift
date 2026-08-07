import Foundation

/// Answers the question the gauge cannot: at this rate, do I run out before
/// the window resets?
///
/// The percentage alone is ambiguous — 60% used is comfortable on day six of a
/// week and alarming on day one. This compares consumption against elapsed
/// time and extrapolates.
public struct WindowProjection: Sendable, Equatable {

    public let limit: UsageLimit
    /// How long the whole window lasts.
    public let windowLength: TimeInterval
    public let elapsed: TimeInterval
    public let remaining: TimeInterval
    /// Consumed so far, 0–100.
    public let percentUsed: Double
    /// Where the current rate lands by the time the window resets. May exceed 100.
    public let projectedPercent: Double
    /// When the limit would be reached, if it would be reached before the reset.
    public let exhaustedAt: Date?

    /// Whether the current rate runs out the allowance early.
    public var willExceed: Bool { exhaustedAt != nil }

    /// How far through the window we are, 0–1. Drives the "you are here" marker.
    public var elapsedFraction: Double {
        guard windowLength > 0 else { return 0 }
        return min(max(elapsed / windowLength, 0), 1)
    }

    /// Consumption relative to time: 1.0 means exactly on pace to finish at
    /// 100%, below 1 is comfortable, above 1 runs out early.
    public var pace: Double {
        guard elapsedFraction > 0 else { return 0 }
        return (percentUsed / 100) / elapsedFraction
    }

    // MARK: Building

    /// How long each kind of window lasts.
    ///
    /// Anthropic does not publish the window length in the usage response —
    /// only when it next resets — so these are the documented durations of the
    /// session and weekly windows. An unrecognised kind yields no projection
    /// rather than a guess.
    static func length(of kind: UsageLimit.Kind) -> TimeInterval? {
        switch kind {
        case .session: 5 * 3600
        case .weeklyAll, .weeklyScoped: 7 * 24 * 3600
        case .other: nil
        }
    }

    /// A stated length always beats an inferred one.
    ///
    /// This is what lets a provider introduce a window Ration has never heard of
    /// — a fortnightly quota, say — and still get a projection, instead of
    /// falling into `.other` and silently losing the card.
    static func length(of limit: UsageLimit) -> TimeInterval? {
        if let stated = limit.windowLength, stated > 0 { return stated }
        return length(of: limit.kind)
    }

    /// Returns `nil` when a projection would be meaningless: no reset time, an
    /// unknown window length, a window that has already elapsed, or one so
    /// fresh that the rate is pure noise.
    public init?(limit: UsageLimit, now: Date = Date()) {
        guard let resetsAt = limit.resetsAt,
            let windowLength = Self.length(of: limit)
        else { return nil }

        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        let elapsed = windowLength - remaining
        // In the first few minutes, one burst of work extrapolates to absurd
        // numbers. Wait until there is enough of the window to reason about.
        guard elapsed > windowLength * 0.02 else { return nil }

        self.limit = limit
        self.windowLength = windowLength
        self.elapsed = elapsed
        self.remaining = min(remaining, windowLength)
        self.percentUsed = min(max(limit.percent, 0), 100)

        let ratePerSecond = percentUsed / elapsed
        self.projectedPercent = ratePerSecond * windowLength

        if ratePerSecond > 0, percentUsed < 100 {
            let secondsToLimit = (100 - percentUsed) / ratePerSecond
            self.exhaustedAt =
                secondsToLimit < remaining
                ? now.addingTimeInterval(secondsToLimit)
                : nil
        } else if percentUsed >= 100 {
            self.exhaustedAt = now
        } else {
            self.exhaustedAt = nil
        }
    }

    // MARK: Wording

    /// A short verdict for the UI.
    public func verdict(now: Date = Date()) -> String {
        if percentUsed >= 100 {
            return "Limit reached"
        }
        guard let exhaustedAt else {
            return "On track — about \(Int(projectedPercent.rounded()))% by reset"
        }
        let early = RelativeTime.short(until: exhaustedAt, from: now)
        return "At this rate you run out in \(early)"
    }

    /// How the verdict should be coloured.
    public var severity: Severity {
        if percentUsed >= 100 { return .critical }
        if willExceed { return .critical }
        // Comfortably ahead of pace is worth flagging before it becomes urgent.
        return projectedPercent >= 90 ? .warning : .normal
    }
}

// MARK: - Series for charting

extension UsageHistory {

    /// Cumulative share of the window consumed over time, for the projection
    /// chart.
    ///
    /// The **shape** comes from your local transcripts — when you actually did
    /// the work — and is then scaled so the final point equals the percentage
    /// Anthropic reports. The transcripts know token counts, not what fraction
    /// of your plan they represent, so the shape is real and the scale is
    /// borrowed from the authoritative number.
    ///
    /// Falls back to a straight line when there is no local history to shape it.
    public func windowCurve(
        for projection: WindowProjection,
        now: Date = Date(),
        buckets: Int = 24
    ) -> [(date: Date, percent: Double)] {

        let start = now.addingTimeInterval(-projection.elapsed)
        let step = projection.elapsed / Double(max(buckets, 1))
        guard step > 0 else { return [] }

        // Bucket the events by time, then integrate.
        var cumulative: [(Date, Double)] = []
        var running = 0.0
        var totals: [Double] = []

        for index in 0..<buckets {
            let bucketEnd = start.addingTimeInterval(step * Double(index + 1))
            running += tokens(
                between: start.addingTimeInterval(step * Double(index)), and: bucketEnd)
            totals.append(running)
            cumulative.append((bucketEnd, running))
        }

        guard let total = totals.last, total > 0 else {
            // No local history for this window — a straight line is the honest
            // fallback, since we know only the endpoints.
            return (0...buckets).map { index in
                let fraction = Double(index) / Double(buckets)
                return (
                    start.addingTimeInterval(projection.elapsed * fraction),
                    projection.percentUsed * fraction
                )
            }
        }

        let scale = projection.percentUsed / total
        return [(start, 0.0)] + cumulative.map { ($0.0, $0.1 * scale) }
    }

    /// Billable tokens recorded in a time range.
    ///
    /// Day-grained, because that is the resolution the history keeps — a range
    /// is attributed by overlap with each day.
    func tokens(between start: Date, and end: Date, calendar: Calendar = .current) -> Double {
        guard end > start else { return 0 }
        var total = 0.0

        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            if let day = days[cursor], day.billableTokens > 0 {
                let overlap = min(end, dayEnd).timeIntervalSince(max(start, cursor))
                if overlap > 0 {
                    let dayLength = dayEnd.timeIntervalSince(cursor)
                    total += Double(day.billableTokens) * (overlap / dayLength)
                }
            }
            cursor = dayEnd
        }
        return total
    }

    /// A per-day series for the bar chart, oldest first.
    public func dailySeries(days count: Int, endingOn end: Date = Date()) -> [DayUsage] {
        window(days: count, endingOn: end)
    }
}
