import Foundation

/// A day's worth of usage, which is the grain everything in the Activity and
/// Metrics tabs is built from.
public struct DayUsage: Sendable, Equatable, Codable, Identifiable {

    /// Midnight local time for the day this covers.
    public let date: Date

    public var tokensByModel: [String: Int]
    public var tokensByProject: [String: Int]
    public var messages: Int
    public var sessions: Set<String>
    public var billableTokens: Int
    public var cacheReadTokens: Int
    public var webSearches: Int
    /// Estimated, in USD. See `Pricing`.
    public var cost: Double

    public var id: Date { date }

    public init(date: Date) {
        self.date = date
        self.tokensByModel = [:]
        self.tokensByProject = [:]
        self.messages = 0
        self.sessions = []
        self.billableTokens = 0
        self.cacheReadTokens = 0
        self.webSearches = 0
        self.cost = 0
    }

    public var totalTokens: Int { billableTokens + cacheReadTokens }
    public var sessionCount: Int { sessions.count }

    mutating func add(_ event: UsageEvent) {
        tokensByModel[event.model, default: 0] += event.billableTokens
        tokensByProject[event.project, default: 0] += event.billableTokens
        messages += 1
        sessions.insert(event.sessionID)
        billableTokens += event.billableTokens
        cacheReadTokens += event.cacheReadTokens
        webSearches += event.webSearches
        cost += Pricing.cost(of: event)
    }
}

// MARK: - History

/// Usage rolled up by day.
///
/// Kept as an aggregate rather than a list of events: a year of history is a
/// few hundred small structs instead of hundreds of thousands of them, which
/// is what makes it cheap to persist and to redraw.
public struct UsageHistory: Sendable, Equatable, Codable {

    public private(set) var days: [Date: DayUsage]

    public init(days: [Date: DayUsage] = [:]) {
        self.days = days
    }

    public mutating func add(_ events: [UsageEvent], calendar: Calendar = .current) {
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            days[day, default: DayUsage(date: day)].add(event)
        }
    }

    public var isEmpty: Bool { days.isEmpty }

    /// Days with any activity, most recent last.
    public var sortedDays: [DayUsage] {
        days.values.sorted { $0.date < $1.date }
    }

    public func day(_ date: Date, calendar: Calendar = .current) -> DayUsage? {
        days[calendar.startOfDay(for: date)]
    }

    // MARK: Windows

    /// Every day in the window, including days with no activity, oldest first.
    ///
    /// Gaps are filled with empty days so the calendar draws a continuous grid
    /// rather than collapsing quiet stretches.
    public func window(
        days count: Int,
        endingOn end: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayUsage] {
        let last = calendar.startOfDay(for: end)
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: last) else {
                return nil
            }
            return days[date] ?? DayUsage(date: date)
        }
    }

    // MARK: Totals

    public func total(over window: [DayUsage]) -> Totals {
        var totals = Totals()
        var sessions: Set<String> = []

        for day in window {
            totals.tokens += day.billableTokens
            totals.cacheReadTokens += day.cacheReadTokens
            totals.messages += day.messages
            totals.cost += day.cost
            totals.webSearches += day.webSearches
            sessions.formUnion(day.sessions)

            for (model, tokens) in day.tokensByModel {
                totals.tokensByModel[model, default: 0] += tokens
            }
            for (project, tokens) in day.tokensByProject {
                totals.tokensByProject[project, default: 0] += tokens
            }
            if day.billableTokens > 0 { totals.activeDays += 1 }
        }

        totals.sessions = sessions.count
        totals.busiestDay = window.max { $0.billableTokens < $1.billableTokens }
        return totals
    }

    public struct Totals: Sendable, Equatable {
        public var tokens = 0
        public var cacheReadTokens = 0
        public var messages = 0
        public var sessions = 0
        public var webSearches = 0
        public var cost: Double = 0
        public var activeDays = 0
        public var tokensByModel: [String: Int] = [:]
        public var tokensByProject: [String: Int] = [:]
        public var busiestDay: DayUsage?

        public init() {}

        /// Models by usage, biggest first.
        public var rankedModels: [(name: String, tokens: Int)] {
            tokensByModel.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                .map { (UsageEvent.displayName(forModel: $0.key), $0.value) }
        }

        public var rankedProjects: [(name: String, tokens: Int)] {
            tokensByProject.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                .map { ($0.key, $0.value) }
        }

        public var averageTokensPerActiveDay: Int {
            activeDays > 0 ? tokens / activeDays : 0
        }
    }

    // MARK: Streaks

    /// Consecutive days with activity, counting back from `end`.
    ///
    /// Today not having started yet does not break a streak, so an unused
    /// today is skipped rather than counted as a zero.
    public func currentStreak(endingOn end: Date = Date(), calendar: Calendar = .current) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: end)

        if days[cursor]?.billableTokens ?? 0 == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }

        while (days[cursor]?.billableTokens ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
