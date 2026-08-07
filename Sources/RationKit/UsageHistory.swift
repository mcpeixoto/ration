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
    /// Billable tokens by hour of day (24 entries, local time) — the raw
    /// material for "when do I actually work?".
    public var tokensByHour: [Int]
    /// Estimated, in USD. See `Pricing`.
    public var cost: Double
    /// Tokens from models with no known rate, which `cost` therefore excludes.
    ///
    /// Kept so the UI can qualify the estimate instead of presenting an
    /// incomplete number as a complete one.
    public var uncostedTokens: Int

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
        self.tokensByHour = Array(repeating: 0, count: 24)
        self.cost = 0
        self.uncostedTokens = 0
    }

    /// Older checkpoints predate `tokensByHour` and `uncostedTokens`; decode
    /// them as empty rather than discarding a whole history for one added field.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        tokensByModel = try container.decode([String: Int].self, forKey: .tokensByModel)
        tokensByProject = try container.decode([String: Int].self, forKey: .tokensByProject)
        messages = try container.decode(Int.self, forKey: .messages)
        sessions = try container.decode(Set<String>.self, forKey: .sessions)
        billableTokens = try container.decode(Int.self, forKey: .billableTokens)
        cacheReadTokens = try container.decode(Int.self, forKey: .cacheReadTokens)
        webSearches = try container.decode(Int.self, forKey: .webSearches)
        cost = try container.decode(Double.self, forKey: .cost)
        tokensByHour =
            try container.decodeIfPresent([Int].self, forKey: .tokensByHour)
            ?? Array(repeating: 0, count: 24)
        uncostedTokens = try container.decodeIfPresent(Int.self, forKey: .uncostedTokens) ?? 0
    }

    public var totalTokens: Int { billableTokens + cacheReadTokens }
    public var sessionCount: Int { sessions.count }

    mutating func add(_ event: UsageEvent, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: event.timestamp)
        if tokensByHour.indices.contains(hour) {
            tokensByHour[hour] += event.billableTokens
        }
        tokensByModel[event.model, default: 0] += event.billableTokens
        tokensByProject[event.project, default: 0] += event.billableTokens
        messages += 1
        sessions.insert(event.sessionID)
        billableTokens += event.billableTokens
        cacheReadTokens += event.cacheReadTokens
        webSearches += event.webSearches

        if let priced = Pricing.cost(of: event) {
            cost += priced
        } else {
            uncostedTokens += event.billableTokens
        }
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
            days[day, default: DayUsage(date: day)].add(event, calendar: calendar)
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
            totals.uncostedTokens += day.uncostedTokens
            totals.webSearches += day.webSearches
            sessions.formUnion(day.sessions)

            for (model, tokens) in day.tokensByModel {
                totals.tokensByModel[model, default: 0] += tokens
            }
            for (project, tokens) in day.tokensByProject {
                totals.tokensByProject[project, default: 0] += tokens
            }
            for hour in 0..<24 where day.tokensByHour.indices.contains(hour) {
                totals.tokensByHour[hour] += day.tokensByHour[hour]
            }
            if day.billableTokens > 0 { totals.activeDays += 1 }
        }

        totals.sessions = sessions.count
        totals.busiestDay = window.max { $0.billableTokens < $1.billableTokens }
        return totals
    }

    public struct Totals: Sendable, Equatable {
        public var tokens = 0
        public var tokensByHour = Array(repeating: 0, count: 24)
        public var cacheReadTokens = 0
        public var messages = 0
        public var sessions = 0
        public var webSearches = 0
        public var cost: Double = 0
        /// Tokens the estimate could not include. Non-zero means `cost` is a
        /// floor, not a total.
        public var uncostedTokens: Int = 0
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

        /// The hour of day with the most output, or `nil` with no data.
        public var busiestHour: Int? {
            guard let peak = tokensByHour.max(), peak > 0 else { return nil }
            return tokensByHour.firstIndex(of: peak)
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
