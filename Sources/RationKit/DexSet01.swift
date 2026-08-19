import Foundation

/// Set 01 — fifty cards.
///
/// Cards 001–018 are the roster that already shipped: same ids, numbers,
/// names, rarities and requirements, so nothing reorders and no unlock
/// changes hands. 019–050 append. Ids are permanent; display names are not.
extension Dex {

    public static let roster: [Creature] = [
        c(
            "sparkit", 1, "Ember", .common,
            "The first tokens of the day.",
            .anyUsage,
            "Tiny chibi flame creature, teardrop body of fire, warm orange, yellow inner core"),
        c(
            "promptail", 2, "Prompt", .common,
            "Another question, before the last one has landed.",
            .messages(25),
            "Round speech-bubble creature with a curly tail, cream and terracotta"),
        c(
            "gaugeling", 3, "Needle", .common,
            "The thing in the menu bar, watching the number.",
            .power(50_000),
            "Little gauge monster, terracotta ring body, a needle for a crest"),
        c(
            "tokenoth", 4, "Moth", .uncommon,
            "Eats leftover context. Leaves a fine billable powder.",
            .power(250_000),
            "Moth creature with powdery spotted wings circling a small lamp"),
        c(
            "cachewisp", 5, "Wisp", .uncommon,
            "Almost free, almost nothing, almost not there.",
            .cacheReads(100_000),
            "Translucent ghost wisp of three fading orbs, almost not there"),
        c(
            "heatmite", 6, "Cell", .uncommon,
            "One square on the calendar. Never satisfied with a quiet Tuesday.",
            .activeDays(5),
            "Square calendar mite with stubby legs and one glowing belly cell"),
        c(
            "sessiondrake", 7, "Session", .uncommon,
            "Hatches when a window opens. Gone when it resets.",
            .sessions(10),
            "Tiny window dragon hatching from a macOS window, traffic-light crest"),
        c(
            "limitwyrm", 8, "Coil", .rare,
            "Around the weekly cap. People notice it when they cannot move.",
            .power(2_000_000),
            "Coiled wyrm wrapped around a circular cap, tense and glittering"),
        c(
            "contextaur", 9, "Context", .rare,
            "Remembers a file from March, and charges a tenth to say so.",
            .cacheReads(1_000_000),
            "Stack of paper files as a creature, dog-ear ears, remembering old pages"),
        c(
            "modelith", 10, "Shift", .rare,
            "Changes when you change models. The old shape stays in the room.",
            .models(3),
            "Three overlapping stone tablets as one shifting creature"),
        c(
            "streakon", 11, "Streak", .rare,
            "A chain of days. An empty calendar looks like a fence.",
            .streak(5),
            "Five-bead chain snake, each bead a glowing day"),
        c(
            "burnrate", 12, "Pace", .epic,
            "Always slightly ahead. The projection is its shadow.",
            .power(10_000_000),
            "Speedy spark creature running up a rising line chart, motion lines"),
        c(
            "weeklyrex", 13, "Week", .epic,
            "The limit that creeps. Session windows reset; this one does not.",
            .power(25_000_000),
            "Small rex with seven bar-chart spikes down its back"),
        c(
            "braidon", 14, "Braid", .epic,
            "Two tools, one score.",
            .providers(2),
            "Two-headed braid creature, two tools twisted into one body"),
        c(
            "nightshift", 15, "Night", .legendary,
            "Wakes when the house is quiet and the tokens are not.",
            .nightOwl,
            "Crescent-moon owl creature coding under stars, coffee at its feet"),
        c(
            "omnivore", 16, "Trio", .legendary,
            "Claude, Codex, Cursor. No favourite — an appetite.",
            .providers(3),
            "Three-eyed round creature marked sparkle, chevron and cursor"),
        c(
            "wallback", 17, "Wall", .legendary,
            "The one you meet when a long run dies at the cap.",
            .singleDay(2_000_000),
            "Brick-wall golem with a crack down its face, stubby arms, blocking a path"),
        c(
            "rationyx", 18, "Mark", .mythic,
            "The last one. It has been in the menu bar the whole time.",
            .power(100_000_000),
            "Tiny terracotta menu-bar mark creature, a living gauge needle, grinning"),
        c(
            "sparkline", 19, "Spark", .common,
            "Two words and a question mark. Still billed.",
            .messages(50),
            "Zigzag sparkline creature with a bright head and a trailing tail"),
        c(
            "draftling", 20, "Draft", .common,
            "Never finished, never deleted, always one tab away.",
            .sessions(3),
            "Stack of speech bubbles, the top one still a dotted outline"),
        c(
            "tallyfin", 21, "Tally", .common,
            "Counts what you already spent. Offers no opinion.",
            .power(100_000),
            "Four tally marks and a slash as a creature, chalk white on terracotta"),
        c(
            "crumbit", 22, "Crumb", .common,
            "What is left of a prompt once the answer has eaten.",
            .cacheReads(25_000),
            "Round crumb creature with a bitten edge and hamster cheeks"),
        c(
            "loopet", 23, "Loop", .common,
            "Opens the window, closes the window, opens the window.",
            .sessions(25),
            "Looping arrow creature chasing its own tail, dizzy eyes"),
        c(
            "dawnlet", 24, "Dawn", .common,
            "The first commit, made before the coffee lands.",
            .activeDays(3),
            "Rising-sun creature with rays for hair and a sleepy grin"),
        c(
            "echofin", 25, "Echo", .common,
            "Repeats the question back, slightly longer.",
            .messages(100),
            "Concentric-ring creature shouting from its centre"),
        c(
            "chiplet", 26, "Chip", .common,
            "A small fixed cost that turns up in every total.",
            .power(500_000),
            "Square silicon chip creature with pin legs and a lit core"),
        c(
            "threadon", 27, "Thread", .uncommon,
            "One conversation, forty turns, no summary.",
            .messages(250),
            "Spool creature trailing a long thread that knots into a face"),
        c(
            "ledgerite", 28, "Ledger", .uncommon,
            "Ten squares filled. It keeps the book, not the score.",
            .activeDays(10),
            "Open ledger book creature with ruled pages and reading glasses"),
        c(
            "relayon", 29, "Relay", .uncommon,
            "Hands the work to whichever model is cheaper this hour.",
            .models(2),
            "Runner creature passing a glowing baton to its own second arm"),
        c(
            "kindlewyrm", 30, "Kindle", .uncommon,
            "The hour when a small idea starts costing real tokens.",
            .power(750_000),
            "Small twin-flame wyrm curled around a warm coal"),
        c(
            "siftmite", 31, "Sift", .uncommon,
            "Reads nine files to answer one line of the question.",
            .cacheReads(250_000),
            "Magnifying-glass creature with a fussy tail and tiny spectacles"),
        c(
            "vaultoise", 32, "Vault", .uncommon,
            "Keeps the whole prefix warm so nothing has to be paid twice.",
            .cacheReads(500_000),
            "Tortoise with a safe door for a shell, peeking out contentedly"),
        c(
            "anvilon", 33, "Anvil", .uncommon,
            "One long afternoon, hammered flat.",
            .singleDay(250_000),
            "Anvil creature with stubby arms and a sparking hammer dent"),
        c(
            "lanternfox", 34, "Lantern", .rare,
            "Ten nights in a row with the same window open.",
            .streak(10),
            "Fox creature with a paper lantern tail, warm glow, night blues"),
        c(
            "quarrion", 35, "Quarry", .rare,
            "Cuts the same seam until the seam runs out.",
            .power(5_000_000),
            "Stone creature with a pickaxe crest, chipping the same seam"),
        c(
            "prismarch", 36, "Prism", .rare,
            "One question, split four ways, four different answers.",
            .models(4),
            "Triangular prism creature splitting one beam into four colours"),
        c(
            "tidewarden", 37, "Tide", .rare,
            "Fifty windows in, the rhythm is not yours any more.",
            .sessions(50),
            "Wave-serpent creature made of stacked swells, calm and endless"),
        c(
            "cinderling", 38, "Cinder", .rare,
            "What a big day leaves in the grate.",
            .singleDay(500_000),
            "Ember-pile creature glowing under grey ash, sleepy eyes"),
        c(
            "beaconox", 39, "Beacon", .rare,
            "Visible from the menu bar of the next desk over.",
            .activeDays(25),
            "Lighthouse creature with a sweeping beam and a proud little face"),
        c(
            "forgeheart", 40, "Forge", .epic,
            "Where the score stops being a number and starts being a habit.",
            .power(15_000_000),
            "Furnace creature with a burning heart window and iron arms"),
        c(
            "marrowdeep", 41, "Marrow", .epic,
            "Everything the project ever said, kept warm and cheap.",
            .cacheReads(5_000_000),
            "Deep strata creature, layered rock body with a warm glowing core"),
        c(
            "weaveon", 42, "Weave", .epic,
            "A thousand turns, tied into something that holds weight.",
            .messages(1000),
            "Loom creature weaving many bright threads into one cloth"),
        c(
            "sentinox", 43, "Sentinel", .epic,
            "Watches the weekly bar so you do not have to.",
            .streak(20),
            "Watchtower creature with one huge unblinking eye and folded arms"),
        c(
            "harvestide", 44, "Harvest", .epic,
            "Two months of squares, standing in rows.",
            .activeDays(60),
            "Wheat-sheaf creature standing in rows of golden calendar squares"),
        c(
            "reckonoth", 45, "Reckon", .legendary,
            "Arrives with the invoice and waits while you read it.",
            .power(50_000_000),
            "Hourglass creature holding a long paper invoice, patient and grave"),
        c(
            "vigilith", 46, "Vigil", .legendary,
            "Forty-five days unbroken. It has stopped counting for you.",
            .streak(45),
            "Tall candle creature with a watchful eye in its flame, never guttering"),
        c(
            "chorusaur", 47, "Chorus", .legendary,
            "Six models in the room, all confident, none agreeing.",
            .models(6),
            "Swarm of six small singing heads orbiting one round body"),
        c(
            "meridiax", 48, "Meridian", .legendary,
            "Two hundred windows. The line between days stopped mattering.",
            .sessions(200),
            "Compass-dial creature with a spinning meridian ring and calm eyes"),
        c(
            "aurumark", 49, "Aurum", .mythic,
            "A quarter of a billion tokens, all of them local history now.",
            .power(250_000_000),
            "Gold vortex creature, coin-bright rings spiralling around a serene face"),
        c(
            "zenithyx", 50, "Zenith", .mythic,
            "The single day the whole calendar is scaled against.",
            .singleDay(5_000_000),
            "Shard-crowned creature at the top of a peak, calm face in bright light"),
    ]

    private static func c(
        _ id: String, _ number: Int, _ name: String, _ rarity: CreatureRarity,
        _ flavor: String, _ requirement: UnlockRequirement, _ silhouette: String
    ) -> Creature {
        Creature(
            id: id, number: number, name: name, rarity: rarity, flavor: flavor,
            requirement: requirement, silhouette: silhouette)
    }
}
