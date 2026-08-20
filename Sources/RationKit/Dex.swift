import Foundation

/// A collectible creature, earned by using the tools Ration already meters.
///
/// Original to Ration — not anyone else's monsters. A card is an illustration,
/// a name, a rarity, and a collector number. The numbers behind an unlock are
/// the same local history the rest of the app already has. Nothing is sent
/// anywhere to decide this.
public struct Creature: Sendable, Equatable, Identifiable {
    public let id: String
    /// 1-based position in the set. Stable across releases: new creatures
    /// append, they do not reorder. Display names may change; ids do not.
    public let number: Int
    public let name: String
    public let rarity: CreatureRarity
    public let flavor: String
    public let requirement: UnlockRequirement
    /// Image Playground seed, and the idea the code-drawn portrait follows.
    public let silhouette: String

    public var collectorNumber: String {
        String(format: "%03d/%03d", number, Dex.roster.count)
    }

    /// Short seeds for Image Playground. Original mascot, not anyone else's.
    public var artConcepts: [String] {
        [
            "Cute original chibi monster mascot",
            "Trading-card illustration, big glossy eyes, no text, no logos",
            "Not a copyrighted character",
            silhouette,
        ]
    }

    public var artPrompt: String {
        artConcepts.joined(separator: ". ")
    }
}

public enum CreatureRarity: String, Sendable, Equatable, Comparable, CaseIterable {
    case common, uncommon, rare, epic, legendary, mythic

    public var label: String {
        rawValue.capitalized
    }

    public var rank: Int {
        switch self {
        case .common: 0
        case .uncommon: 1
        case .rare: 2
        case .epic: 3
        case .legendary: 4
        case .mythic: 5
        }
    }

    public static func < (lhs: CreatureRarity, rhs: CreatureRarity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// What has to be true of local usage before this creature is caught.
///
/// Power is billable tokens summed across every tool Ration can read. That
/// sum is not a usage metric — a Claude token is not a Codex token — and the
/// UI must not present it as one. It is a score for a game.
public enum UnlockRequirement: Sendable, Equatable {
    /// Any billable token, from any tool.
    case anyUsage
    case power(Int)
    case messages(Int)
    case sessions(Int)
    case cacheReads(Int)
    case activeDays(Int)
    case streak(Int)
    case models(Int)
    case providers(Int)
    /// Most tokens in a single hour of the day, at or after 22:00 or at or before 05:00.
    case nightOwl
    case singleDay(Int)
    /// Busiest hour is in the morning, 06:00 through 10:00.
    case earlyBird
    /// Busiest hour is in the evening, 16:00 through 18:00.
    case dusk
    /// Estimated API cost in dollars. A toy threshold, not a bill.
    case cost(Double)

    func isMet(by stats: TrainerStats) -> Bool {
        switch self {
        case .anyUsage: return stats.power > 0 || !stats.providers.isEmpty
        case .power(let n): return stats.power >= n
        case .messages(let n): return stats.messages >= n
        case .sessions(let n): return stats.sessions >= n
        case .cacheReads(let n): return stats.cacheReads >= n
        case .activeDays(let n): return stats.activeDays >= n
        case .streak(let n): return stats.streak >= n
        case .models(let n): return stats.models >= n
        case .providers(let n): return stats.providers.count >= n
        case .nightOwl:
            guard let hour = stats.busiestHour else { return false }
            return hour >= 22 || hour <= 5
        case .singleDay(let n): return stats.busiestDayTokens >= n
        case .earlyBird:
            guard let hour = stats.busiestHour else { return false }
            return (6...10).contains(hour)
        case .dusk:
            guard let hour = stats.busiestHour else { return false }
            return (16...18).contains(hour)
        case .cost(let n): return stats.cost >= n
        }
    }
}

/// Rolled-up local usage, across every tool, for deciding catches.
public struct TrainerStats: Sendable, Equatable {
    public var power: Int = 0
    public var messages: Int = 0
    public var sessions: Int = 0
    public var cacheReads: Int = 0
    public var activeDays: Int = 0
    public var streak: Int = 0
    public var models: Int = 0
    public var providers: Set<String> = []
    public var busiestHour: Int? = nil
    public var busiestDayTokens: Int = 0
    public var cost: Double = 0
}

/// Histories Ration already has, plus tools that only have a live gauge.
public struct DexInput: Sendable, Equatable {
    public var histories: [String: UsageHistory]
    /// Provider ids with a live snapshot that shows real usage — how a tool
    /// that has a gauge but no history yet still counts as a provider.
    public var liveProviders: Set<String>
    public var now: Date
    public var calendar: Calendar

    public init(
        histories: [String: UsageHistory],
        liveProviders: Set<String> = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.histories = histories
        self.liveProviders = liveProviders
        self.now = now
        self.calendar = calendar
    }
}

public struct PowerHunt: Sendable, Equatable {
    public var creature: Creature
    public var progress: Double
}

public struct DexState: Sendable, Equatable {
    public var stats: TrainerStats
    public var caught: [Creature]
    public var uncaught: [Creature]
    public var nextPowerCatch: PowerHunt?
}

/// The set, and the rules that decide who has been caught.
public enum Dex {

    public static func evaluate(_ input: DexInput) -> DexState {
        let stats = tally(input)
        let caught = roster.filter { $0.requirement.isMet(by: stats) }
        let uncaught = roster.filter { creature in
            !caught.contains { $0.id == creature.id }
        }
        return DexState(
            stats: stats,
            caught: caught,
            uncaught: uncaught,
            nextPowerCatch: nextPowerHunt(caught: caught, stats: stats))
    }

    /// Caught creatures the trainer has not been shown yet, in set order.
    public static func pendingReveals(caught: [Creature], alreadyRevealed: Set<String>)
        -> [Creature]
    {
        caught.filter { !alreadyRevealed.contains($0.id) }
    }

    // MARK: - Tally

    private static func tally(_ input: DexInput) -> TrainerStats {
        var stats = TrainerStats()
        var hourTokens = Array(repeating: 0, count: 24)
        var activeDates: Set<Date> = []
        var models: Set<String> = []

        for (id, history) in input.histories {
            let totals = history.total(over: history.sortedDays)
            stats.power += totals.tokens
            stats.messages += totals.messages
            stats.sessions += totals.sessions
            stats.cacheReads += totals.cacheReadTokens
            stats.cost += totals.cost
            stats.busiestDayTokens = max(
                stats.busiestDayTokens, totals.busiestDay?.billableTokens ?? 0)
            stats.streak = max(
                stats.streak, history.currentStreak(endingOn: input.now, calendar: input.calendar))
            if totals.tokens > 0 { stats.providers.insert(id) }
            models.formUnion(totals.tokensByModel.keys)
            for day in history.sortedDays where day.billableTokens > 0 {
                activeDates.insert(input.calendar.startOfDay(for: day.date))
            }
            for hour in 0..<24 where totals.tokensByHour.indices.contains(hour) {
                hourTokens[hour] += totals.tokensByHour[hour]
            }
        }

        stats.providers.formUnion(input.liveProviders)
        stats.activeDays = activeDates.count
        stats.models = models.count
        if let peak = hourTokens.max(), peak > 0 {
            stats.busiestHour = hourTokens.firstIndex(of: peak)
        }
        return stats
    }

    private static func nextPowerHunt(caught: [Creature], stats: TrainerStats) -> PowerHunt? {
        let caughtIDs = Set(caught.map(\.id))
        for creature in roster where !caughtIDs.contains(creature.id) {
            if case .power(let n) = creature.requirement, n > 0 {
                return PowerHunt(
                    creature: creature,
                    progress: min(1, Double(stats.power) / Double(n)))
            }
        }
        return nil
    }
}
