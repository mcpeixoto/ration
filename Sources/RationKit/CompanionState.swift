import Foundation

/// Everything the loop remembers between launches.
///
/// Decoding is deliberately forgiving. One bad field must not cost somebody their
/// binder, so every key falls back to its default and a single corrupt log row drops
/// itself rather than taking the array with it. Only a file whose root is not an
/// object throws, and `CompanionStore` backs that one up before starting over.
public struct CompanionState: Codable, Sendable, Equatable {

    // MARK: The ledger

    /// Lifetime billable tokens per provider that have already been credited.
    ///
    /// `nil` means a save from before the ledger existed: seed it from the current
    /// reading and credit nothing, so nobody gets two years of backdated growth on the
    /// morning they update. An empty dictionary is a seeded ledger with nothing to
    /// report and must stay distinguishable from `nil`.
    ///
    /// Lifetime rather than daily on purpose. Three processes write this file, and a
    /// daily baseline double-credits across a date boundary when two of them are
    /// running. Lifetime totals only ever rise, so whoever writes first takes the delta
    /// and the second sees nothing left to take.
    public var claimedLifetimeTokensByProvider: [String: Int]?

    /// Tokens credited since the loop started. The growth meter; never rewound.
    public var creditedTokens = 0
    /// Tokens handed to the shop. Spending lowers the wallet, never the growth meter.
    public var spentTokens = 0

    // MARK: The pack

    /// Growth banked toward ripping the sealed pack.
    public var packUsage = 0
    /// The rarity floor a bought pack promised. Persisted, because the promise has to
    /// survive a restart between paying for it and ripping it.
    public var packGuarantee: CreatureRarity?

    // MARK: The collection

    public var active: ActiveRun?
    public var log: [CatchEntry] = []
    /// Finals already reached. Steers the branch roll away from routes that would
    /// file a creature the binder already has.
    public var filedFinals: Set<String> = []
    /// Creatures unlocked under the old threshold model, kept as a read-only Set 01
    /// mark. They do not count toward the new binder and do not steer the roll.
    public var archive: Set<String> = []

    // MARK: Held

    public var inventory: [String: Int] = [:]
    /// Windows already paid out on, so filling a cap grants once rather than once per
    /// launch. Cleared when the window drops back under its cap.
    public var grantedWindows: Set<String> = []
    /// First run seeds the window state without paying out — otherwise updating while
    /// already at 100% hands over a fistful of Overclocks for work done last week.
    public var grantsSeeded = false

    /// Species pinned to the menu bar and tray. `nil` follows whatever is being raised.
    public var pinnedID: String?

    public init() {}

    // MARK: Derived

    /// Spendable tokens. Growth counts the full burn; the shop only draws on this.
    public var wallet: Int { max(0, creditedTokens - spentTokens) }

    /// Every species in the binder from the new loop — the union of filed chains plus
    /// the forms the current run has actually reached.
    public var filedSpecies: Set<String> {
        var out = Set(log.flatMap(\.chain))
        if let active { out.formUnion(active.revealed) }
        return out
    }

    public func itemCount(_ kind: ItemKind) -> Int { inventory[kind.rawValue] ?? 0 }
    public var ownsLens: Bool { itemCount(.lens) > 0 }

    public var packProgress: Double {
        min(1, Double(packUsage) / Double(CompanionBalance.packFill))
    }
    public var packRemaining: Int { max(0, CompanionBalance.packFill - packUsage) }

    /// Items held, in a stable order, for the bag rows in the shop.
    public var heldItems: [(kind: ItemKind, count: Int)] {
        ItemKind.allCases.compactMap { kind in
            let n = itemCount(kind)
            return n > 0 ? (kind, n) : nil
        }
    }

    // MARK: Posed

    /// A loop part-way through, for previews and screenshots.
    ///
    /// Three of the four collection screens are empty on a fresh profile and months of
    /// play away from being interesting, so the renderers pose one rather than wait.
    /// Deterministic: the same seed always builds the same collection.
    public static func posed(seed: UInt64 = 4, tokens: Int = 4_200_000_000) -> CompanionState {
        var state = CompanionState()
        var rng = SeededGenerator(seed: seed)
        // A fixed instant, so a screenshot taken today matches one taken last week.
        let stamp = Date(timeIntervalSinceReferenceDate: 807_000_000)
        state.claimedLifetimeTokensByProvider = [:]
        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": tokens], now: stamp, using: &rng)
        state.inventory = [ItemKind.overclock.rawValue: 3, ItemKind.lens.rawValue: 1]
        state.archive = Set(Dex.roster.prefix(18).map(\.id))
        if !state.log.isEmpty { state.log[0].isShiny = true }
        return state
    }

    // MARK: Forgiving decode

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(T.self)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func lenient<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        // Absent and unreadable have to stay different here: absent means "never
        // seeded", unreadable means "seeded, contents lost". Both credit nothing this
        // time round, but only the first re-seeds from the current reading.
        if c.contains(.claimedLifetimeTokensByProvider) {
            claimedLifetimeTokensByProvider = lenient(.claimedLifetimeTokensByProvider, [:])
        } else {
            claimedLifetimeTokensByProvider = nil
        }
        creditedTokens = lenient(.creditedTokens, 0)
        spentTokens = lenient(.spentTokens, 0)
        packUsage = lenient(.packUsage, 0)
        // An unreadable floor degrades to no promise rather than inventing one.
        packGuarantee = try? c.decode(CreatureRarity.self, forKey: .packGuarantee)
        active = try? c.decode(ActiveRun.self, forKey: .active)
        log = lenient(.log, [Lossy<CatchEntry>]()).compactMap(\.value)
        filedFinals = lenient(.filedFinals, [])
        archive = lenient(.archive, [])
        inventory = lenient(.inventory, [:])
        grantedWindows = lenient(.grantedWindows, [])
        grantsSeeded = lenient(.grantsSeeded, false)
        pinnedID = try? c.decode(String.self, forKey: .pinnedID)
    }
}
