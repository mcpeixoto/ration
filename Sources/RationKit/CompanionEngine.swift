import Foundation

/// The rules of the loop: a sealed pack fills, rips into a creature, the creature
/// evolves along the route planned at the rip, and files itself into the binder — then
/// a fresh pack is sealed.
///
/// Deliberately a bag of free functions over `inout CompanionState` with the clock and
/// the random source handed in. No I/O, nothing `async`, no shared instance: every rule
/// here can be driven from a test with a fixed seed and a fixed date.
///
/// The whole thing is offline. The set is compiled in and the art is drawn in code, so
/// there is no species to fetch, no chain to look up, and none of the prefetching and
/// retry machinery a network-backed version of this would need.
public enum CompanionEngine {

    // MARK: Crediting usage

    /// Fold the latest per-provider lifetime totals into the loop.
    ///
    /// Idempotent by construction, which matters because `Ration.app`, `ration-tray`
    /// and `ration watch` can all be running against one file: growth is the rise over
    /// what has already been claimed, so whoever writes first takes it and the rest
    /// see nothing. Totals that went backwards — a rotated log, a cleared history —
    /// credit nothing rather than going negative.
    @discardableResult
    public static func credit(
        _ state: inout CompanionState,
        lifetimeByProvider: [String: Int],
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [CompanionEvent] {
        guard var claimed = state.claimedLifetimeTokensByProvider else {
            state.claimedLifetimeTokensByProvider = lifetimeByProvider.mapValues { max(0, $0) }
            return []
        }
        var delta = 0
        for (provider, total) in lifetimeByProvider {
            let prior = claimed[provider] ?? 0
            if total > prior { delta += total - prior }
            claimed[provider] = max(prior, total)
        }
        state.claimedLifetimeTokensByProvider = claimed
        guard delta > 0 else { return [] }
        state.creditedTokens += delta
        return grow(&state, by: delta, now: now, using: &rng)
    }

    /// Push growth through the loop: fill the pack, rip it, evolve, file, seal the next
    /// one — as far as the growth reaches.
    ///
    /// Passing zero is meaningful: it settles a threshold that was already crossed but
    /// never resolved, which is how a state loaded from disk catches up.
    @discardableResult
    public static func grow(
        _ state: inout CompanionState,
        by amount: Int,
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [CompanionEvent] {
        var events: [CompanionEvent] = []
        var carry = max(0, amount)
        // Every pass either banks the carry and stops, or crosses a threshold and
        // resets the meter, so this terminates. The cap is only here so a nonsense
        // threshold in a hand-edited save cannot spin the poll thread.
        for _ in 0..<200 {
            if state.active == nil {
                let room = max(0, CompanionBalance.packFill - state.packUsage)
                if carry < room {
                    state.packUsage += carry
                    return events
                }
                carry -= room
                state.packUsage = 0
                events += rip(&state, now: now, using: &rng)
                continue
            }
            let run = state.active!
            let room = max(0, run.threshold - run.usedAtStage)
            if carry < room {
                state.active?.usedAtStage += carry
                return events
            }
            carry -= room
            state.active?.usedAtStage = run.threshold
            if run.isFinalForm {
                events += file(&state, now: now)
            } else {
                events += evolve(&state, using: &rng)
            }
        }
        return events
    }

    // MARK: Ripping a pack

    /// Open the sealed pack: pick a line, plan the whole route through it, and roll the
    /// two things that make this animal itself.
    ///
    /// The route is settled here rather than at each fork so the run has a known cost
    /// from the first frame. It is not shown — the header names the form on screen and
    /// the evolution strip draws question marks past it.
    @discardableResult
    public static func rip(
        _ state: inout CompanionState,
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [CompanionEvent] {
        let floor = state.packGuarantee
        let promised = floor.map { EvolutionForest.roots(reaching: $0) } ?? EvolutionForest.roots
        // A floor nothing can satisfy means the roster changed under a bought pack.
        // Rip something rather than stranding the player on a pack that never opens.
        let candidates = promised.isEmpty ? EvolutionForest.roots : promised
        guard let root = pickLine(from: candidates, filed: state.filedFinals, using: &rng) else {
            return []
        }
        let plan = EvolutionForest.plan(
            from: root.id, avoiding: state.filedFinals, atLeast: floor, using: &rng)
        let shiny = rollsShiny(roll: rng.next(), lens: state.ownsLens)
        let trait = rollTrait(roll: rng.next())

        state.active = ActiveRun(
            rootID: root.id, path: [root.id], plan: plan, stageIndex: 0, usedAtStage: 0,
            isShiny: shiny, trait: trait, startedAt: now)
        state.packUsage = 0
        state.packGuarantee = nil
        return [.ripped(creature: root.id, shiny: shiny)]
    }

    /// Weighted pick of a line. A line whose finals are all filed still comes up, so a
    /// favourite can be replayed for a shiny, but at a fraction of the weight — without
    /// that, the last few cards of the set take twice as long as the first forty.
    static func pickLine(
        from candidates: [EvoNode], filed: Set<String>, using rng: inout some RandomNumberGenerator
    ) -> EvoNode? {
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map { line in weight(of: line, filed: filed) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates.first }
        var roll = Int(rng.next(upperBound: UInt64(total)))
        for (line, weight) in zip(candidates, weights) {
            roll -= weight
            if roll < 0 { return line }
        }
        return candidates.last
    }

    static func weight(of line: EvoNode, filed: Set<String>) -> Int {
        let base = Dex.creature(line.id)?.rarity.pullWeight ?? CreatureRarity.common.pullWeight
        let exhausted = line.finalIDs.allSatisfy(filed.contains)
        return exhausted ? max(1, base / CompanionBalance.exhaustedLineDivisor) : base
    }

    /// Pure, so the odds can be pinned without stubbing chance itself.
    public static func rollsShiny(roll: UInt64, lens: Bool) -> Bool {
        roll % (lens ? CompanionBalance.lensShinyDenominator : CompanionBalance.shinyDenominator)
            == 0
    }

    public static func rollTrait(roll: UInt64) -> CreatureTrait {
        CreatureTrait.allCases[Int(roll % UInt64(CreatureTrait.allCases.count))]
    }

    // MARK: Evolving and filing

    private static func evolve(
        _ state: inout CompanionState, using rng: inout some RandomNumberGenerator
    ) -> [CompanionEvent] {
        guard let run = state.active else { return [] }
        let from = run.currentID
        let next = run.stageIndex + 1
        // Normally the planned form is simply the next one along. It can fail to be
        // one — a save written against a different roster — in which case re-plan from
        // where we actually stand rather than dropping the run on the floor.
        let node = EvolutionForest.node(from)
        let planned = run.plan.indices.contains(next) ? run.plan[next] : nil
        let child =
            node?.children.first { $0.id == planned }
            ?? node.flatMap {
                EvolutionForest.step(from: $0, avoiding: state.filedFinals, using: &rng)
            }
        guard let child else {
            // Nowhere left to go: treat the current form as the end of the line.
            state.active?.plan = Array(run.path.prefix(run.stageIndex + 1))
            return []
        }
        var repaired = run
        repaired.path = Array(run.path.prefix(run.stageIndex + 1)) + [child.id]
        if planned != child.id {
            repaired.plan =
                repaired.path
                + EvolutionForest.plan(
                    from: child.id, avoiding: state.filedFinals, using: &rng
                ).dropFirst()
        }
        repaired.stageIndex = next
        repaired.usedAtStage = 0
        state.active = repaired
        return [.evolved(from: from, to: child.id)]
    }

    private static func file(_ state: inout CompanionState, now: Date) -> [CompanionEvent] {
        guard let run = state.active else { return [] }
        let final = run.currentID
        state.filedFinals.insert(final)
        state.log.append(
            CatchEntry(
                rootID: run.rootID, finalID: final, chain: run.revealed,
                trait: run.trait, isShiny: run.isShiny, filedAt: now))
        state.active = nil
        state.packUsage = 0
        return [
            .filed(
                creature: final, shiny: run.isShiny,
                rarity: Dex.creature(final)?.rarity ?? .common)
        ]
    }

    // MARK: Items

    public static func canUse(_ kind: ItemKind, _ state: CompanionState) -> Bool {
        guard state.itemCount(kind) > 0, !kind.isPassive else { return false }
        return state.active != nil
    }

    @discardableResult
    public static func use(
        _ kind: ItemKind,
        _ state: inout CompanionState,
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [CompanionEvent] {
        guard canUse(kind, state) else { return [] }
        state.inventory[kind.rawValue] = state.itemCount(kind) - 1
        switch kind {
        case .overclock:
            let growth = CompanionBalance.overclockGrowth
            return [.boosted(growth)] + grow(&state, by: growth, now: now, using: &rng)
        case .refactor:
            let rolled = rollTrait(roll: rng.next())
            state.active?.trait = rolled
            return [.traitRolled(rolled)]
        case .lens:
            return []
        }
    }

    // MARK: Shop

    /// Rows in price order, so the shop reads as a ladder. A pack is only offered once
    /// the ledger is running — buying one before the first token is counted would spend
    /// a wallet nobody has earned.
    public static func shopEntries(_ state: CompanionState) -> [ShopEntry] {
        let items = ItemKind.allCases.map(ShopEntry.item)
        let packs = CompanionPack.sold.map(ShopEntry.pack)
        return (items + packs).sorted { $0.price < $1.price }
    }

    public static func canBuy(_ entry: ShopEntry, _ state: CompanionState) -> Bool {
        guard state.wallet >= entry.price else { return false }
        if case .item(let kind) = entry, kind.isPassive, state.itemCount(kind) > 0 {
            return false
        }
        return true
    }

    @discardableResult
    public static func buy(
        _ entry: ShopEntry,
        _ state: inout CompanionState,
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [CompanionEvent] {
        guard canBuy(entry, state) else { return [] }
        state.spentTokens += entry.price
        switch entry {
        case .item(let kind):
            state.inventory[kind.rawValue] = state.itemCount(kind) + 1
            return [.bought(entry)]
        case .pack(let floor):
            // A pack restarts the loop: whatever was being raised is discarded, not
            // filed, so the binder and the branch roll are untouched. The fresh pack
            // starts empty, which is what keeps re-rolling from being free.
            state.active = nil
            state.packUsage = 0
            state.packGuarantee = floor
            return [.bought(entry)]
        }
    }

    // MARK: Limit rewards

    /// Pay out for windows that have filled since the last look, and forget the ones
    /// that have reset.
    ///
    /// The set of paid windows is persisted, so filling a weekly cap grants five
    /// Overclocks once rather than five on every launch for the rest of the week. The
    /// first call after the feature appears only records the state — otherwise updating
    /// while already at the cap pays out for work done before any of this existed.
    @discardableResult
    public static func grantRewards(
        _ state: inout CompanionState, windows: [LimitWindow]
    ) -> [CompanionEvent] {
        let full = Set(windows.filter(\.isFull).map(\.key))
        guard state.grantsSeeded else {
            state.grantsSeeded = true
            state.grantedWindows = full
            return []
        }
        // Drop windows that have reset, so the next fill pays again.
        state.grantedWindows.formIntersection(Set(windows.map(\.key)).intersection(full))
        var events: [CompanionEvent] = []
        for window in windows where window.isFull && !state.grantedWindows.contains(window.key) {
            state.grantedWindows.insert(window.key)
            state.inventory[ItemKind.overclock.rawValue] =
                state.itemCount(.overclock) + window.grant
            events.append(
                .granted(item: .overclock, count: window.grant, window: window.name))
        }
        return events
    }
}
