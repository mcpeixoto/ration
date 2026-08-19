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
    public let ability: String
    public let nature: String
    /// Image Playground seed, and the idea the code-drawn portrait follows.
    public let silhouette: String

    public var collectorNumber: String {
        String(format: "%03d/%03d", number, Dex.roster.count)
    }

    /// Life on the card. Scales with rarity, not with real usage.
    public var life: Int {
        switch rarity {
        case .common: 50
        case .uncommon: 70
        case .rare: 90
        case .epic: 120
        case .legendary: 150
        case .mythic: 200
        }
    }

    /// How hard it hits. A toy number for the card, derived from the deed.
    public var strength: Int {
        switch requirement {
        case .anyUsage: 28
        case .power(let n): min(180, 30 + n / 800_000)
        case .messages(let n): min(120, 20 + n)
        case .sessions(let n): min(150, n * 6)
        case .cacheReads(let n): min(140, n / 25_000)
        case .activeDays(let n): n * 11
        case .streak(let n): n * 14
        case .models(let n): n * 32
        case .providers(let n): n * 45
        case .nightOwl: 96
        case .singleDay: 170
        case .earlyBird: 88
        case .dusk: 84
        case .cost(let n): min(175, 40 + Int(n) * 2)
        }
    }

    /// Stamina on the card. Commons are eager; mythics barely breathe.
    public var energy: Int {
        max(20, 110 - rarity.rank * 12 + number)
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
    /// Provider ids with a live snapshot that shows real usage — how Cursor
    /// gets into the Dex, since Ration cannot read its transcripts yet.
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

    public static let roster: [Creature] = [
        c(
            "sparkit", 1, "Ember", .common,
            "The first spark. One token and it wakes the whole set. Trainers say the menu bar runs a degree warmer.",
            .anyUsage, "First Spark", "Bold",
            "Tiny flame creature, teardrop body of fire, warm orange, inner yellow core"),
        c(
            "promptail", 2, "Prompt", .common,
            "Asks faster than anyone answers. An empty input box is its only known weakness.",
            .messages(25), "Rapid Ask", "Chatty",
            "Round speech-bubble creature with a curly tail, cream and terracotta"),
        c(
            "gaugeling", 3, "Needle", .common,
            "Nests in the menu bar. If the ring twitches, Needle already knew — and it is judging you.",
            .power(50_000), "Needle Watch", "Watchful",
            "Little gauge monster, terracotta ring body, needle on its head"),
        c(
            "tokenoth", 4, "Moth", .uncommon,
            "Feeds on leftover context and coughs billable powder. Do not vacuum. Do not pet.",
            .power(250_000), "Context Dust", "Hungry",
            "Moth creature with powdery spotted wings at a small lamp"),
        c(
            "cachewisp", 5, "Wisp", .uncommon,
            "Almost free, almost nothing, almost not there. Still on the bill. Always on the bill.",
            .cacheReads(100_000), "Almost Free", "Faint",
            "Translucent ghost wisp of three fading orbs, almost not there"),
        c(
            "heatmite", 6, "Cell", .uncommon,
            "Paints one square on your calendar and dares you to skip Tuesday. Tuesday never wins.",
            .activeDays(5), "Calendar Bite", "Restless",
            "Square calendar mite with stubby legs, one glowing belly cell"),
        c(
            "sessiondrake", 7, "Session", .uncommon,
            "Hatches when a window opens. Evaporates at reset. Leaves the coffee. Rude.",
            .sessions(10), "Window Hatch", "Hatchling",
            "Tiny window dragon hatching from a macOS window, traffic-light crest"),
        c(
            "limitwyrm", 8, "Coil", .rare,
            "Sleeps around the weekly cap. You only meet it when you cannot move another token.",
            .power(2_000_000), "Cap Coil", "Tense",
            "Coiled wyrm wrapped around a circular cap, tense and glittering"),
        c(
            "contextaur", 9, "Context", .rare,
            "Remembers a file from March and charges a tenth to prove it. Never throws anything out.",
            .cacheReads(1_000_000), "March Recall", "Bookish",
            "Stack of paper files as a creature, dog-ear ears, remembering old pages"),
        c(
            "modelith", 10, "Shift", .rare,
            "Changes shape each time you switch models. The old one stays in the room, sulking.",
            .models(3), "Shape Shift", "Fluid",
            "Three overlapping stone tablets as one shifting creature"),
        c(
            "streakon", 11, "Streak", .rare,
            "A chain of days wearing a grin. Break it and the grin becomes a hole in a fence.",
            .streak(5), "Day Chain", "Loyal",
            "Five-bead chain snake, each bead a day, glowing"),
        c(
            "burnrate", 12, "Pace", .epic,
            "Always slightly ahead of you. The projection on the Usage tab is just its shadow.",
            .power(10_000_000), "Ahead of Pace", "Ahead",
            "Speedy spark creature running up a rising line chart, motion lines"),
        c(
            "weeklyrex", 13, "Week", .epic,
            "The limit that creeps. Session windows reset; this one does not forgive, and it does not hurry.",
            .power(25_000_000), "Slow Creep", "Unhurried",
            "Small rex with seven bar-chart spikes on its back"),
        c(
            "braidon", 14, "Braid", .epic,
            "Two tools, one score. Argues with itself in stereo and still ships.",
            .providers(2), "Twin Thread", "Twin",
            "Two-headed braid creature, two tools twisted into one body"),
        c(
            "nightshift", 15, "Night", .legendary,
            "Wakes when the house is quiet and the tokens are loud. Bring coffee. Do not bring a clock.",
            .nightOwl, "Quiet Hours", "Nocturnal",
            "Crescent-moon owl creature coding under stars, coffee"),
        c(
            "omnivore", 16, "Trio", .legendary,
            "Claude, Codex, Cursor. No favourite. An appetite with three mouths and one Score.",
            .providers(3), "Triple Appetite", "Glutton",
            "Three-eyed round creature marked sparkle, chevron and cursor"),
        c(
            "wallback", 17, "Wall", .legendary,
            "The wall at the end of a long run. You can hear the cap from here. It hears you too.",
            .singleDay(2_000_000), "Hard Stop", "Stony",
            "Brick-wall golem with a crack, stubby arms, blocking a path"),
        c(
            "rationyx", 18, "Mark", .mythic,
            "It has been sitting in the menu bar the whole time, grinning, keeping score.",
            .power(100_000_000), "Menu Presence", "Present",
            "Tiny terracotta menu-bar mark creature, a living gauge needle grinning"),
        c(
            "draftling", 19, "Draft", .common,
            "Lives in the input box. Half a thought, already sent. The undo key is its natural predator.",
            .messages(100), "Unfinished", "Hasty",
            "Stack of three speech bubbles as a creature, the top one still a dotted outline"),
        c(
            "replybit", 20, "Reply", .common,
            "Bounces every time a session window comes back. Never reads the previous message first.",
            .sessions(25), "Bounce Back", "Perky",
            "Two overlapping macOS windows with a round face peeking from the front one"),
        c(
            "tabbit", 21, "Tab", .common,
            "Collects open folders the way magpies collect foil. Closing a tab makes it hiss.",
            .activeDays(10), "Open Tab", "Curious",
            "Folder-tab creature with dog-ear ears and a paper tongue"),
        c(
            "diffling", 22, "Diff", .uncommon,
            "One half green, one half gone. It cannot agree with itself and that is the point.",
            .power(500_000), "Split Take", "Two-sided",
            "Creature split down the middle, left half filled, right half an outline"),
        c(
            "patchkit", 23, "Patch", .uncommon,
            "A bandage with opinions. It slaps itself onto broken prompts and calls it a release.",
            .messages(250), "Hotfix", "Mending",
            "Round creature wearing a crossed bandage patch, needle and thread tail"),
        c(
            "commito", 24, "Commit", .uncommon,
            "Stamps the day and refuses to take it back. Amend is a dirty word in its house.",
            .sessions(50), "Sign Off", "Steady",
            "Rubber-stamp creature with a bold mark on its belly and stubby arms"),
        c(
            "branchlet", 25, "Branch", .uncommon,
            "Forks whenever you hesitate. Both paths are the wrong one, according to the other head.",
            .streak(3), "Fork Path", "Divergent",
            "Y-shaped stick creature with a face on each fork"),
        c(
            "merjil", 26, "Merge", .uncommon,
            "Two streams, one body. Conflicts make it dizzy. Fast-forward makes it smug.",
            .cacheReads(500_000), "Combine", "Together",
            "Two coloured streams twisting into one round body"),
        c(
            "rebasil", 27, "Rebase", .rare,
            "Rewrites history until it looks like it always happened this way. Do not ask about the original.",
            .activeDays(14), "Rewrite", "Careful",
            "Stacked discs offset like a spiral staircase, a face on the top disc"),
        c(
            "blamelite", 28, "Blame", .rare,
            "Points at a line from three weeks ago and will not blink. The line was yours.",
            .streak(14), "Who Touched It", "Accusing",
            "Round creature with one huge pointing arm and a tiny unimpressed mouth"),
        c(
            "lintail", 29, "Lint", .rare,
            "Nitpicks trailing spaces for sport. Has never shipped, and that is a feature.",
            .power(5_000_000), "Nit Pick", "Fussy",
            "Magnifying-glass creature with a long fussy tail and spectacles"),
        c(
            "buildrake", 30, "Build", .rare,
            "Spins until the compile is done. If it stops spinning, do not make eye contact.",
            .sessions(100), "Compile Storm", "Busy",
            "Round gear creature with smaller gears for ears, mid-spin"),
        c(
            "shipling", 31, "Ship", .epic,
            "Leaves the dock the moment the tests go green. Sometimes before.",
            .power(50_000_000), "Launch Window", "Reckless",
            "Capsule rocket creature with stubby fins and a visor face"),
        c(
            "crashowl", 32, "Crash", .epic,
            "Appears in a puff of stack frames. Remembers nothing. Will do it again in an hour.",
            .singleDay(500_000), "Stack Dump", "Startled",
            "Round cracked-egg creature with wide startled eyes and a lightning hair"),
        c(
            "dawnkit", 33, "Dawn", .epic,
            "Tokens before breakfast. The coffee is still brewing and Dawn has already spent the morning.",
            .earlyBird, "First Light", "Eager",
            "Rising-sun creature with rays as hair and a sleepy-but-grinning face"),
        c(
            "duskwing", 34, "Dusk", .epic,
            "The last useful hour. After this it is snacks, not software. Dusk does not know that yet.",
            .dusk, "Last Light", "Sleepy",
            "Evening-sun creature with drooping wing-rays and half-lidded eyes"),
        c(
            "billow", 35, "Bill", .legendary,
            "Not a bill. An estimate with a face. Trainers still flinch when it smiles.",
            .cost(20), "Itemised", "Shocked",
            "Coin creature with a dollar-ish mark that is not a logo, wide shocked eyes"),
        c(
            "echoling", 36, "Echo", .legendary,
            "A thousand messages later it still repeats the first one. Slightly wrong. Slightly louder.",
            .messages(1_000), "Repeat After", "Loud",
            "Concentric-ring creature, a face in the middle shouting"),
        c(
            "vaultaur", 37, "Vault", .legendary,
            "Keeps every cached page since the machine was new. Opening it takes a minute. Worth it.",
            .cacheReads(10_000_000), "Keep Forever", "Hoarding",
            "Treasure-chest creature with a lock-nose and peeking eyes under the lid"),
        c(
            "orbiton", 38, "Orbit", .legendary,
            "Thirty days around the same problem. It calls that a year. It is not wrong.",
            .activeDays(30), "Full Circle", "Patient",
            "Small planet creature with a ring and a tiny moon for a pet"),
        c(
            "floodwyrm", 39, "Flood", .mythic,
            "A single day that should have been a week. The gauge went under. Flood waved.",
            .singleDay(10_000_000), "Overflow", "Unstoppable",
            "Wave-serpent creature made of stacked swells, grinning over the high-water mark"),
        c(
            "summitox", 40, "Summit", .mythic,
            "The score you can see from the valley. The air is thin. Summit lives here anyway.",
            .power(250_000_000), "High Score", "Proud",
            "Mountain-peak creature, triangular body, flag of hair, proud little face"),
        c(
            "zenithar", 41, "Zenith", .mythic,
            "The top of the meter. There is no more meter. Zenith is the sky now.",
            .power(500_000_000), "Peak Form", "Radiant",
            "Star-burst creature, many rays, a calm face in the bright centre"),
        c(
            "foreveris", 42, "Forever", .mythic,
            "A month without a hole in the chain. It does not blink. It does not forget Tuesday.",
            .streak(30), "Never Break", "Devoted",
            "Ouroboros ring creature, a chain eating its own tail, gentle eyes"),
    ]

    private static func c(
        _ id: String, _ number: Int, _ name: String, _ rarity: CreatureRarity,
        _ flavor: String, _ requirement: UnlockRequirement,
        _ ability: String, _ nature: String, _ silhouette: String
    ) -> Creature {
        Creature(
            id: id, number: number, name: name, rarity: rarity, flavor: flavor,
            requirement: requirement, ability: ability, nature: nature,
            silhouette: silhouette)
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
