import Foundation
import Testing

@testable import RationKit

/// Every route the set can actually plan, as (forms, rarity of the final).
private let realRoutes: [(forms: Int, rarity: CreatureRarity)] = {
    var out: [(Int, CreatureRarity)] = []
    func walk(_ node: EvoNode, _ depth: Int) {
        if node.isLeaf {
            out.append((depth, Dex.creature(node.id)?.rarity ?? .common))
            return
        }
        for child in node.children { walk(child, depth + 1) }
    }
    for root in EvolutionForest.roots { walk(root, 1) }
    return out
}()

private let epoch = Date(timeIntervalSinceReferenceDate: 0)

private func ripped(seed: UInt64 = 1, lens: Bool = false) -> (CompanionState, SeededGenerator) {
    var state = CompanionState()
    if lens { state.inventory[ItemKind.lens.rawValue] = 1 }
    var rng = SeededGenerator(seed: seed)
    CompanionEngine.grow(&state, by: CompanionBalance.packFill, now: epoch, using: &rng)
    return (state, rng)
}

@Suite("Companion balance")
struct CompanionBalanceTests {

    /// The point of the weighting: a one-form line and a three-form line of the same
    /// rarity cost the same to finish. If the split stopped summing, a branching line
    /// would quietly become the cheap way to farm the set.
    @Test("the stages of a line sum to its graduation total")
    func stagesSumToTotal() {
        for rarity in CreatureRarity.allCases {
            for forms in 1...3 {
                let stages = (0..<forms).map {
                    CompanionBalance.phaseThreshold(
                        rarity: rarity, forms: forms, stageIndex: $0)
                }
                let drift = abs(stages.reduce(0, +) - CompanionBalance.graduationTotal(rarity))
                #expect(drift <= forms, "\(rarity) over \(forms) forms drifted by \(drift)")
            }
        }
    }

    @Test("later stages always cost more than earlier ones")
    func stagesRise() {
        for rarity in CreatureRarity.allCases {
            for forms in 2...3 {
                let stages = (0..<forms).map {
                    CompanionBalance.phaseThreshold(
                        rarity: rarity, forms: forms, stageIndex: $0)
                }
                #expect(zip(stages, stages.dropFirst()).allSatisfy(<))
            }
        }
    }

    @Test("rarer finals cost more to reach")
    func rarityCosts() {
        let totals = CreatureRarity.allCases.sorted().map(CompanionBalance.graduationTotal)
        #expect(zip(totals, totals.dropFirst()).allSatisfy(<))
    }

    /// An Overclock that could cross two thresholds would skip a form entirely — the
    /// player pays for a shortcut and loses a card off the chain.
    @Test("one Overclock can never chain two evolutions")
    func overclockCannotChain() {
        let smallest = realRoutes.flatMap { route in
            (0..<route.forms).map {
                CompanionBalance.phaseThreshold(
                    rarity: route.rarity, forms: route.forms, stageIndex: $0)
            }
        }.min()

        #expect(smallest == 100_000_000)
        #expect(CompanionBalance.overclockGrowth < (smallest ?? 0))
    }

    /// Priced by probability, two cheap packs would beat one expensive pack and the
    /// top tier would be a trap. Priced by graduation total, the ladder holds.
    @Test("a higher pack tier is never the worse buy")
    func packLadder() {
        #expect(CompanionPack.price(guaranteeing: nil) == 200_000_000)
        #expect(CompanionPack.price(guaranteeing: .rare) == 800_000_000)
        #expect(CompanionPack.price(guaranteeing: .epic) == 1_600_000_000)

        let prices = CompanionPack.sold.map(CompanionPack.price(guaranteeing:))
        #expect(zip(prices, prices.dropFirst()).allSatisfy(<))
    }

    @Test("a free Overclock always beats a bought one")
    func freeBeatsBought() {
        #expect(ItemKind.overclock.price > CompanionBalance.overclockGrowth)
    }

    @Test("there are twenty-five traits")
    func traitCount() {
        #expect(CreatureTrait.allCases.count == 25)
        #expect(Set(CreatureTrait.allCases.map(\.rawValue)).count == 25)
    }
}

@Suite("Companion: ripping a pack")
struct CompanionRipTests {

    @Test("a pack under the fill line stays sealed")
    func sealedUntilFull() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)

        let events = CompanionEngine.grow(
            &state, by: CompanionBalance.packFill - 1, now: epoch, using: &rng)

        #expect(events.isEmpty)
        #expect(state.active == nil)
        #expect(state.packUsage == CompanionBalance.packFill - 1)
        #expect(state.packProgress < 1)
    }

    @Test("filling the pack rips it into a creature at the head of a line")
    func ripsWhenFull() {
        let (state, _) = ripped()
        let run = try! #require(state.active)

        #expect(state.packUsage == 0)
        #expect(run.stageIndex == 0)
        #expect(run.usedAtStage == 0)
        #expect(run.path == [run.rootID])
        #expect(EvolutionForest.roots.map(\.id).contains(run.rootID))
        #expect(run.plan.first == run.rootID)
        #expect(EvolutionForest.node(run.finalID)?.isLeaf == true)
    }

    /// Tokens burned while the pack was already full are growth the player has paid
    /// for. Dropping them would make a quiet week followed by a busy one worse than
    /// two average ones.
    @Test("overflow past the fill line carries into the creature")
    func overflowCarries() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 4)

        CompanionEngine.grow(
            &state, by: CompanionBalance.packFill + 40_000_000, now: epoch, using: &rng)

        #expect(state.active?.usedAtStage == 40_000_000)
    }

    @Test("the same seed rips the same creature")
    func deterministic() {
        let (a, _) = ripped(seed: 77)
        let (b, _) = ripped(seed: 77)

        #expect(a.active == b.active)
    }

    @Test("a rip reports itself, with whether it is shiny")
    func reportsRip() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)

        let events = CompanionEngine.grow(
            &state, by: CompanionBalance.packFill, now: epoch, using: &rng)

        #expect(events.count == 1)
        if case .ripped(let creature, _) = events[0] {
            #expect(creature == state.active?.rootID)
        } else {
            Issue.record("expected a rip, got \(events)")
        }
    }

    @Test("shiny is one in sixty-four, or one in forty-eight holding a Lens")
    func shinyOdds() {
        #expect(CompanionEngine.rollsShiny(roll: 0, lens: false))
        #expect(CompanionEngine.rollsShiny(roll: 64, lens: false))
        #expect(!CompanionEngine.rollsShiny(roll: 48, lens: false))
        #expect(CompanionEngine.rollsShiny(roll: 48, lens: true))
        #expect(!CompanionEngine.rollsShiny(roll: 64, lens: true))
    }

    @Test("a trait is rolled from all twenty-five")
    func traitRoll() {
        let rolled = Set((0..<200).map { CompanionEngine.rollTrait(roll: UInt64($0)) })
        #expect(rolled.count == 25)
    }

    /// The weighting that keeps the tail of the set from doubling in length.
    @Test("a line whose finals are all filed is rolled far less often")
    func exhaustedLinesFade() {
        let echo = try! #require(EvolutionForest.node("echofin"))
        let fresh = CompanionEngine.weight(of: echo, filed: [])
        let spent = CompanionEngine.weight(of: echo, filed: Set(echo.finalIDs))

        #expect(spent == fresh / CompanionBalance.exhaustedLineDivisor)
        #expect(spent >= 1, "an exhausted line must still be reachable")
    }
}

@Suite("Companion: evolving and filing")
struct CompanionGrowthTests {

    /// Walk a whole run by handing it exactly what each stage asks for.
    private func raise(seed: UInt64) -> (CompanionState, [CompanionEvent]) {
        var (state, rng) = ripped(seed: seed)
        var events: [CompanionEvent] = []
        var guardCount = 0
        while let run = state.active, guardCount < 10 {
            guardCount += 1
            events += CompanionEngine.grow(
                &state, by: run.remaining, now: epoch, using: &rng)
        }
        return (state, events)
    }

    @Test("crossing a threshold advances exactly one form and resets the meter")
    func evolvesOneStep() {
        var (state, rng) = ripped(seed: 3)
        while state.active?.plan.count ?? 0 < 2 {
            // Seed 3 might land on a single-form line; keep ripping until it does not.
            state = CompanionState()
            rng = SeededGenerator(seed: rng.next())
            CompanionEngine.grow(&state, by: CompanionBalance.packFill, now: epoch, using: &rng)
        }
        let before = try! #require(state.active)

        let events = CompanionEngine.grow(
            &state, by: before.remaining, now: epoch, using: &rng)
        let after = try! #require(state.active)

        #expect(after.stageIndex == before.stageIndex + 1)
        #expect(after.usedAtStage == 0)
        #expect(after.path == before.path + [before.plan[1]])
        #expect(events == [.evolved(from: before.currentID, to: before.plan[1])])
    }

    @Test("a finished run files its whole chain and seals a fresh pack")
    func filesAndReseals() {
        let (state, events) = raise(seed: 11)
        let entry = try! #require(state.log.last)

        #expect(state.active == nil)
        #expect(state.packUsage == 0)
        #expect(state.log.count == 1)
        #expect(entry.chain.first == entry.rootID)
        #expect(entry.chain.last == entry.finalID)
        #expect(state.filedFinals == [entry.finalID])
        #expect(state.filedSpecies == Set(entry.chain))
        #expect(events.contains { if case .filed = $0 { true } else { false } })
    }

    @Test("a whole run costs exactly its graduation total")
    func costsItsTotal() {
        for seed in UInt64(1)...12 {
            var (state, rng) = ripped(seed: seed)
            let run = try! #require(state.active)
            let total = CompanionBalance.graduationTotal(
                Dex.creature(run.finalID)?.rarity ?? .common)

            CompanionEngine.grow(&state, by: total - 1, now: epoch, using: &rng)
            #expect(state.active != nil, "seed \(seed) filed a token early")
            CompanionEngine.grow(&state, by: 1, now: epoch, using: &rng)
            #expect(state.active == nil, "seed \(seed) did not file on its total")
        }
    }

    /// Growth past the last threshold belongs to the next pack, not the bin.
    @Test("overflow at filing rolls into the next pack")
    func overflowAtFiling() {
        var (state, rng) = ripped(seed: 5)
        let run = try! #require(state.active)
        let total = CompanionBalance.graduationTotal(
            Dex.creature(run.finalID)?.rarity ?? .common)

        CompanionEngine.grow(&state, by: total + 2_000_000, now: epoch, using: &rng)

        #expect(state.log.count == 1)
        #expect(state.packUsage == 2_000_000)
    }

    @Test("enough growth at once files a run and rips the next pack")
    func runsStraightThrough() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 8)

        CompanionEngine.grow(&state, by: 8_000_000_000, now: epoch, using: &rng)

        #expect(state.log.count > 1)
        #expect(state.active != nil)
    }

    /// The completability guarantee, end to end. Nothing steers the roll toward the set
    /// except the branch preference, so if that ever stopped working this would hang on
    /// the last few cards until the guard tripped.
    @Test("raising for long enough files every leaf, and so every creature")
    func setCompletes() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 2026)
        var guardCount = 0
        while state.filedFinals.count < 33 && guardCount < 500 {
            guardCount += 1
            CompanionEngine.grow(&state, by: 500_000_000, now: epoch, using: &rng)
        }

        #expect(state.filedFinals.count == 33, "stalled at \(state.filedFinals.count) leaves")
        #expect(Set(state.log.flatMap(\.chain)) == Set(Dex.roster.map(\.id)))
    }

    @Test("growing by nothing settles a threshold that a loaded save had already crossed")
    func settlesLoadedState() {
        var (state, rng) = ripped(seed: 6)
        let threshold = try! #require(state.active).threshold
        state.active?.usedAtStage = threshold

        let events = CompanionEngine.grow(&state, by: 0, now: epoch, using: &rng)

        #expect(!events.isEmpty)
    }
}

@Suite("Companion: the ledger")
struct CompanionLedgerTests {

    @Test("the first reading seeds the baseline and credits nothing")
    func seedsWithoutCrediting() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)

        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 900_000_000], now: epoch, using: &rng)

        #expect(state.creditedTokens == 0)
        #expect(state.active == nil)
        #expect(state.packUsage == 0)
        #expect(state.claimedLifetimeTokensByProvider == ["claude": 900_000_000])
    }

    @Test("only the rise since the last reading is credited")
    func creditsTheRise() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)

        CompanionEngine.credit(&state, lifetimeByProvider: ["claude": 100], now: epoch, using: &rng)
        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 3_000_100], now: epoch, using: &rng)

        #expect(state.creditedTokens == 3_000_000)
        #expect(state.packUsage == 3_000_000)
    }

    /// Three processes read the same numbers. Crediting has to be the rise over what
    /// is already claimed, or the tray and a `ration watch` both bank the same tokens.
    @Test("the same reading twice is credited once")
    func idempotent() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)
        CompanionEngine.credit(&state, lifetimeByProvider: ["claude": 0], now: epoch, using: &rng)

        let reading = ["claude": 2_000_000, "codex": 1_000_000]
        CompanionEngine.credit(&state, lifetimeByProvider: reading, now: epoch, using: &rng)
        CompanionEngine.credit(&state, lifetimeByProvider: reading, now: epoch, using: &rng)

        #expect(state.creditedTokens == 3_000_000)
    }

    @Test("a history that shrinks credits nothing rather than going backwards")
    func shrinkingHistory() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)
        CompanionEngine.credit(&state, lifetimeByProvider: ["claude": 0], now: epoch, using: &rng)
        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 4_000_000], now: epoch, using: &rng)

        CompanionEngine.credit(&state, lifetimeByProvider: ["claude": 10], now: epoch, using: &rng)

        #expect(state.creditedTokens == 4_000_000)
        #expect(state.claimedLifetimeTokensByProvider?["claude"] == 4_000_000)
    }

    @Test("a new provider is credited from zero, not from its whole history")
    func newProvider() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)
        CompanionEngine.credit(&state, lifetimeByProvider: ["claude": 0], now: epoch, using: &rng)

        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 0, "cursor": 1_000_000], now: epoch, using: &rng)

        #expect(state.creditedTokens == 1_000_000)
    }
}

@Suite("Companion: shop and bag")
struct CompanionShopTests {

    private func rich(_ tokens: Int = 10_000_000_000) -> CompanionState {
        var state = CompanionState()
        state.creditedTokens = tokens
        return state
    }

    @Test("the shop reads as a price ladder")
    func ladder() {
        let prices = CompanionEngine.shopEntries(rich()).map(\.price)
        #expect(prices == prices.sorted())
        #expect(CompanionEngine.shopEntries(rich()).count == 6)
    }

    @Test("buying draws on the wallet and never on growth")
    func walletNotGrowth() {
        var state = rich(1_000_000_000)
        var rng = SeededGenerator(seed: 1)

        CompanionEngine.buy(.item(.overclock), &state, now: epoch, using: &rng)

        #expect(state.creditedTokens == 1_000_000_000)
        #expect(state.spentTokens == ItemKind.overclock.price)
        #expect(state.wallet == 1_000_000_000 - ItemKind.overclock.price)
        #expect(state.itemCount(.overclock) == 1)
    }

    @Test("an empty wallet buys nothing")
    func cannotOverdraw() {
        var state = CompanionState()
        var rng = SeededGenerator(seed: 1)

        let events = CompanionEngine.buy(.item(.lens), &state, now: epoch, using: &rng)

        #expect(events.isEmpty)
        #expect(state.wallet == 0)
        #expect(state.spentTokens == 0)
        #expect(!state.ownsLens)
    }

    @Test("a Lens is bought once and then held")
    func lensBoughtOnce() {
        var state = rich()
        var rng = SeededGenerator(seed: 1)

        CompanionEngine.buy(.item(.lens), &state, now: epoch, using: &rng)
        let second = CompanionEngine.buy(.item(.lens), &state, now: epoch, using: &rng)

        #expect(state.itemCount(.lens) == 1)
        #expect(second.isEmpty)
        #expect(!CompanionEngine.canBuy(.item(.lens), state))
        #expect(!CompanionEngine.canUse(.lens, state))
    }

    @Test("an Overclock adds growth and is spent doing it")
    func overclockGrows() {
        var (state, rng) = ripped(seed: 9)
        state.inventory[ItemKind.overclock.rawValue] = 1
        let before = try! #require(state.active).usedAtStage

        CompanionEngine.use(.overclock, &state, now: epoch, using: &rng)

        #expect(state.itemCount(.overclock) == 0)
        #expect((state.active?.usedAtStage ?? 0) == before + CompanionBalance.overclockGrowth)
    }

    @Test("a Refactor rolls a new trait and nothing else")
    func refactorRerolls() {
        var (state, rng) = ripped(seed: 12)
        state.inventory[ItemKind.refactor.rawValue] = 1
        let before = try! #require(state.active)

        CompanionEngine.use(.refactor, &state, now: epoch, using: &rng)
        let after = try! #require(state.active)

        #expect(after.currentID == before.currentID)
        #expect(after.usedAtStage == before.usedAtStage)
        #expect(state.itemCount(.refactor) == 0)
    }

    @Test("nothing is usable while a pack is still sealed")
    func nothingToUseWithoutACreature() {
        var state = rich()
        state.inventory[ItemKind.overclock.rawValue] = 1

        #expect(!CompanionEngine.canUse(.overclock, state))
    }

    /// A pack is a re-roll, not a shortcut: what was being raised is discarded, so the
    /// binder and the branch roll are untouched and the fresh pack starts empty.
    @Test("buying a pack discards the current run without filing it")
    func packDiscards() {
        var (state, rng) = ripped(seed: 13)
        state.creditedTokens = 10_000_000_000
        state.active?.usedAtStage = 90_000_000

        CompanionEngine.buy(.pack(.rare), &state, now: epoch, using: &rng)

        #expect(state.active == nil)
        #expect(state.packUsage == 0)
        #expect(state.packGuarantee == .rare)
        #expect(state.log.isEmpty)
        #expect(state.filedFinals.isEmpty)
    }

    @Test("a guaranteed pack always rips a line that reaches its floor")
    func guaranteeHolds() {
        for floor in [CreatureRarity.rare, .epic] {
            for seed in UInt64(1)...40 {
                var state = CompanionState()
                state.packGuarantee = floor
                var rng = SeededGenerator(seed: seed)
                CompanionEngine.grow(
                    &state, by: CompanionBalance.packFill, now: epoch, using: &rng)
                let run = try! #require(state.active)

                #expect((Dex.creature(run.finalID)?.rarity ?? .common) >= floor)
                #expect(state.packGuarantee == nil, "the promise is spent by the rip")
            }
        }
    }
}

@Suite("Companion: limit rewards")
struct CompanionRewardTests {

    private let session = LimitWindow(
        key: "claude.session", name: "5-hour", kind: .session, utilization: 100)
    private let weekly = LimitWindow(
        key: "claude.weekly", name: "Weekly", kind: .weekly, utilization: 100)

    /// Without this, updating while already at the cap pays out for a week of work
    /// that happened before any of this existed.
    @Test("the first look records the windows and pays nothing")
    func firstLookSeeds() {
        var state = CompanionState()

        let events = CompanionEngine.grantRewards(&state, windows: [session, weekly])

        #expect(events.isEmpty)
        #expect(state.itemCount(.overclock) == 0)
        #expect(state.grantsSeeded)
    }

    @Test("filling a window pays out once, however often it is checked")
    func paysOnce() {
        var state = CompanionState()
        CompanionEngine.grantRewards(&state, windows: [])

        let first = CompanionEngine.grantRewards(&state, windows: [session, weekly])
        let again = CompanionEngine.grantRewards(&state, windows: [session, weekly])

        #expect(first.count == 2)
        #expect(again.isEmpty)
        #expect(
            state.itemCount(.overclock)
                == CompanionBalance.sessionGrant + CompanionBalance.weeklyGrant)
    }

    @Test("a window that resets pays again the next time it fills")
    func paysAgainAfterReset() {
        var state = CompanionState()
        CompanionEngine.grantRewards(&state, windows: [])
        CompanionEngine.grantRewards(&state, windows: [session])

        let quiet = LimitWindow(
            key: session.key, name: session.name, kind: .session, utilization: 12)
        CompanionEngine.grantRewards(&state, windows: [quiet])
        CompanionEngine.grantRewards(&state, windows: [session])

        #expect(state.itemCount(.overclock) == CompanionBalance.sessionGrant * 2)
    }

    @Test("a window under its cap pays nothing")
    func partialWindowPaysNothing() {
        var state = CompanionState()
        CompanionEngine.grantRewards(&state, windows: [])
        let almost = LimitWindow(key: "k", name: "5-hour", kind: .session, utilization: 99.9)

        #expect(CompanionEngine.grantRewards(&state, windows: [almost]).isEmpty)
    }

    @Test("a weekly cap is worth five, a session cap one")
    func grantSizes() {
        #expect(session.grant == 1)
        #expect(weekly.grant == 5)
    }
}
