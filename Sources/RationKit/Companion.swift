import Foundation

// MARK: - Identity rolled at the rip

/// A creature's temperament, fixed the moment its pack is ripped and kept through
/// every evolution. Cosmetic — it changes nothing about growth or the card's numbers.
/// It is here so two runs down the same line are still two different animals.
public enum CreatureTrait: String, Codable, Sendable, CaseIterable {
    case eager, patient, terse, verbose, cached
    case stubborn, curious, frugal, reckless, methodical
    case restless, precise, drifting, blunt, tidy
    case greedy, quiet, brash, dogged, idle
    case brisk, careful, feral, wry, plain

    public var label: String { rawValue.capitalized }
}

// MARK: - Balance

extension CreatureRarity {
    /// How often a line rolls at the rip. The spread mirrors the shape of a capture
    /// rate — commons are near-certain, the top tiers are a story — but only the two
    /// tiers that appear on a root (common, uncommon) are ever consulted for the roll
    /// itself. The rest exist so the table reads as one scale.
    public var pullWeight: Int {
        switch self {
        case .common: 255
        case .uncommon: 120
        case .rare: 45
        case .epic: 20
        case .legendary: 8
        case .mythic: 3
        }
    }
}

/// Every number the loop turns on, in one place, with the reasoning attached.
///
/// The set was simulated over two thousand seeded runs against these values: a full
/// fifty takes a median forty-four rips and about 43B tokens, which is roughly six
/// months of heavy use and a year and a half of steady use. Change a number here and
/// that is the thing you are changing.
public enum CompanionBalance {

    /// Tokens that fill a sealed pack. Small on purpose — the first rip should land
    /// inside an afternoon, not a fortnight. Overflow carries into the creature, so
    /// nothing spent while the pack was already full is lost.
    public static let packFill = 5_000_000

    /// Total growth from rip to filed, decided by the rarity of the *final* form the
    /// run is planned to reach. This is the first thing in Ration that makes rarity
    /// mean anything beyond a border colour.
    public static func graduationTotal(_ rarity: CreatureRarity) -> Int {
        switch rarity {
        case .common: 150_000_000
        case .uncommon: 300_000_000
        case .rare: 600_000_000
        case .epic: 1_200_000_000
        case .legendary: 2_000_000_000
        case .mythic: 3_000_000_000
        }
    }

    /// Growth needed to leave this stage. Weighted so the stages of a `k`-form line
    /// sum to exactly the graduation total whatever `k` is — a three-form line and a
    /// one-form line of the same rarity cost the same overall, and later stages cost
    /// more than earlier ones.
    ///
    ///     stage i of k  =  total · (i+1) / (k(k+1)/2)
    public static func phaseThreshold(
        rarity: CreatureRarity, forms: Int, stageIndex: Int
    ) -> Int {
        let k = max(1, forms)
        let i = max(0, min(stageIndex, k - 1)) + 1
        let total = Double(graduationTotal(rarity))
        return Int((total * Double(i) / (Double(k * (k + 1)) / 2)).rounded())
    }

    /// Degrees to rotate a creature's key colour by for a shiny.
    ///
    /// A rotation rather than a second palette: it is one number instead of fifty
    /// authored colours, it is guaranteed to differ from the original, and each
    /// creature's shiny still differs from every other creature's. Pairing each energy
    /// with the one it is weak to was tried first and abandoned — three of the eight
    /// pairs are both warm, so those shinies were indistinguishable.
    ///
    /// Just short of a straight complement, which lands flat and slightly muddy.
    public static let shinyHueShift = 168.0

    /// One rip in sixty-four is shiny. The mainline's odds would mean nobody ever saw
    /// one; this is rare enough to be worth saying out loud and common enough to
    /// happen.
    public static let shinyDenominator: UInt64 = 64
    /// Holding a Lens. A third again as likely, not twice — the upgrade should be felt
    /// without making the plain rip feel like the punishment.
    public static let lensShinyDenominator: UInt64 = 48

    /// Growth an Overclock injects. Deliberately under the smallest evolution step in
    /// the set (100M), so one can never chain two evolutions at once.
    public static let overclockGrowth = 50_000_000

    /// A line whose every final is already filed still rolls, so a favourite can be
    /// replayed for a shiny — but at an eighth the weight, or the tail of the set
    /// takes twice as long as it should. The simulation picked eight: at ÷2 the median
    /// run count is 76, at ÷8 it is 44, and past that the roll stops feeling random.
    public static let exhaustedLineDivisor = 8

    /// Free Overclocks for filling a limit window. Spending to the cap is the one
    /// thing the app already watches for you; this pays it back.
    public static let sessionGrant = 1
    public static let weeklyGrant = 5
}

// MARK: - Things you can hold and buy

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    /// Consumed for a burst of growth.
    case overclock
    /// Consumed to re-roll the current creature's trait.
    case refactor
    /// Held, never consumed: better shiny odds on every rip from here.
    case lens

    public var label: String {
        switch self {
        case .overclock: "Overclock"
        case .refactor: "Refactor"
        case .lens: "Lens"
        }
    }

    public var detail: String {
        switch self {
        case .overclock:
            "Adds \(PowerFormat.compact(CompanionBalance.overclockGrowth)) of growth."
        case .refactor: "Rolls a new trait for the creature you are raising."
        case .lens: "Shiny odds rise from 1 in 64 to 1 in 48, for good."
        }
    }

    /// Held rather than spent — bought once, and the shop says "held" after that.
    public var isPassive: Bool { self == .lens }

    public var price: Int {
        switch self {
        case .refactor: 50_000_000
        // Five times the growth it grants. Tokens are both the growth meter and the
        // wallet, so pricing it at its own value would make buying one pure free
        // progress. At 5× the free grant from filling a limit is always the better
        // deal, which is the behaviour worth rewarding.
        case .overclock: 250_000_000
        // Permanent luck, so it is priced like finishing a rare line.
        case .lens: 600_000_000
        }
    }
}

/// A row in the shop: something you hold, or a pack that restarts the loop.
public enum ShopEntry: Hashable, Sendable {
    case item(ItemKind)
    /// The rarity floor the pack promises. `nil` is the plain booster.
    case pack(CreatureRarity?)

    public var price: Int {
        switch self {
        case .item(let kind): kind.price
        case .pack(let floor): CompanionPack.price(guaranteeing: floor)
        }
    }
}

public enum CompanionPack {
    /// A plain booster: discards what you are raising and reseals a pack.
    public static let boosterPrice = 200_000_000

    /// Floors that are actually sold. The top two tiers are not — a guaranteed mythic
    /// is the whole game bought outright, and the set is meant to take a while.
    public static let sold: [CreatureRarity?] = [nil, .rare, .epic]

    /// Guaranteed packs are priced off the **graduation-total** ratio, never the
    /// probability ratio.
    ///
    /// Priced by probability, buying two cheap packs would beat one expensive pack on
    /// every axis at the same spend, and the higher tier becomes a strictly worse
    /// purchase that only exists to catch people out. Pricing by what the guarantee is
    /// worth to finish keeps the ladder honest.
    public static func price(guaranteeing floor: CreatureRarity?) -> Int {
        guard let floor else { return boosterPrice }
        let ratio =
            Double(CompanionBalance.graduationTotal(floor))
            / Double(CompanionBalance.graduationTotal(.common))
        return Int((Double(boosterPrice) * ratio).rounded())
    }

    public static func label(_ floor: CreatureRarity?) -> String {
        switch floor {
        case .none: "Booster Pack"
        case .rare: "Foil Pack"
        case .epic: "Hobby Pack"
        case .some(let tier): "\(tier.label) Pack"
        }
    }
}

// MARK: - The run in progress

/// The creature currently being raised. The whole path is planned at the rip, but
/// only `path` has actually happened — everything past `stageIndex` in `plan` is a
/// destination the player has not been told about.
public struct ActiveRun: Codable, Sendable, Equatable {
    public var rootID: String
    /// Forms reached so far, root first.
    public var path: [String]
    /// The full planned route, root to final.
    public var plan: [String]
    public var stageIndex: Int
    /// Growth banked against the current form's threshold.
    public var usedAtStage: Int
    public var isShiny: Bool
    public var trait: CreatureTrait
    public var startedAt: Date

    public init(
        rootID: String, path: [String], plan: [String], stageIndex: Int = 0,
        usedAtStage: Int = 0, isShiny: Bool = false, trait: CreatureTrait, startedAt: Date
    ) {
        self.rootID = rootID
        self.path = path.isEmpty ? [rootID] : path
        self.plan = plan.isEmpty ? [rootID] : plan
        self.stageIndex = stageIndex
        self.usedAtStage = usedAtStage
        self.isShiny = isShiny
        self.trait = trait
        self.startedAt = startedAt
    }

    /// The form on screen right now. Clamped, because a hand-edited save should draw
    /// something rather than crash the panel on every frame.
    public var currentID: String {
        path.isEmpty ? rootID : path[min(stageIndex, path.count - 1)]
    }

    /// Where this run is headed. Not shown until it is reached.
    public var finalID: String { plan.last ?? currentID }
    public var forms: Int { max(plan.count, path.count) }
    public var isFinalForm: Bool { stageIndex >= forms - 1 }

    /// Growth needed to leave the current form, or to file if this is the last one.
    public var threshold: Int {
        CompanionBalance.phaseThreshold(
            rarity: Dex.creature(finalID)?.rarity ?? .common,
            forms: forms, stageIndex: stageIndex)
    }

    public var progress: Double {
        let t = threshold
        return t <= 0 ? 1 : min(1, Double(usedAtStage) / Double(t))
    }

    public var remaining: Int { max(0, threshold - usedAtStage) }

    /// Root first, with unreached forms omitted — what the evolution strip draws as
    /// "done" and "current" before it starts drawing question marks.
    public var revealed: [String] { Array(path.prefix(stageIndex + 1)) }
}

/// One filed creature. The catch log is these in the order they happened; the binder
/// is the union of their chains.
public struct CatchEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var rootID: String
    public var finalID: String
    /// Root first, final last — every form this run actually passed through.
    public var chain: [String]
    public var trait: CreatureTrait
    public var isShiny: Bool
    public var filedAt: Date

    public init(
        id: String = UUID().uuidString, rootID: String, finalID: String, chain: [String],
        trait: CreatureTrait, isShiny: Bool, filedAt: Date
    ) {
        self.id = id
        self.rootID = rootID
        self.finalID = finalID
        self.chain = chain
        self.trait = trait
        self.isShiny = isShiny
        self.filedAt = filedAt
    }

    public var rarity: CreatureRarity { Dex.creature(finalID)?.rarity ?? .common }
}

/// A limit window, flattened out of whatever the provider reported, for deciding
/// whether an Overclock is owed.
public struct LimitWindow: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case session, weekly }

    /// Stable across resets — never build it from a reset timestamp, or every window
    /// looks new and pays out again.
    public let key: String
    public let name: String
    public let kind: Kind
    public let utilization: Double

    public init(key: String, name: String, kind: Kind, utilization: Double) {
        self.key = key
        self.name = name
        self.kind = kind
        self.utilization = utilization
    }

    public var isFull: Bool { utilization >= 100 }
    public var grant: Int {
        kind == .weekly ? CompanionBalance.weeklyGrant : CompanionBalance.sessionGrant
    }
}

/// Something worth telling the player about. The engine returns these instead of
/// firing notifications itself, so the rules stay testable and each front end decides
/// what a celebration looks like.
public enum CompanionEvent: Sendable, Equatable {
    case ripped(creature: String, shiny: Bool)
    case evolved(from: String, to: String)
    case filed(creature: String, shiny: Bool, rarity: CreatureRarity)
    case traitRolled(CreatureTrait)
    case boosted(Int)
    case granted(item: ItemKind, count: Int, window: String)
    case bought(ShopEntry)
}
