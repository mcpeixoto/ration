import Foundation
import Testing

@testable import RationKit

@Suite("Evolution forest: the graph the set already had")
struct EvolutionForestTests {

    /// The printed `evolvesFrom` names are the only thing tying the set together, and
    /// nothing else validates them — a typo would quietly orphan a line and the app
    /// would launch anyway. This is that check.
    @Test("every printed parent resolves to a real creature")
    func parentsResolve() {
        #expect(EvolutionForest.diagnostics.unresolvedParents == [:])
        #expect(EvolutionForest.diagnostics.ambiguousNames == [])
        #expect(EvolutionForest.diagnostics.brokenCycles == [])
        #expect(EvolutionForest.diagnostics.isClean)
    }

    @Test("fifteen lines cover all fifty creatures, once each")
    func coverage() {
        let reached = EvolutionForest.roots.flatMap { EvolutionForest.reachable(from: $0.id) }

        #expect(EvolutionForest.roots.count == 15)
        #expect(reached.count == Dex.roster.count)
        #expect(Set(reached) == Set(Dex.roster.map(\.id)))
    }

    /// A creature names one parent, so the graph must be a forest. If it ever became a
    /// DAG, a filed final could no longer be recorded as a bare id.
    @Test("every creature belongs to exactly one line")
    func singleParent() {
        for creature in Dex.roster {
            let owners = EvolutionForest.roots.filter {
                EvolutionForest.reachable(from: $0.id).contains(creature.id)
            }
            #expect(owners.count == 1, "\(creature.id) is in \(owners.count) lines")
        }
    }

    @Test("the roots are exactly the basic creatures")
    func rootsAreBasic() {
        let rootIDs = Set(EvolutionForest.roots.map(\.id))
        let basics = Set(Dex.roster.filter { Dex.lore[$0.id]?.stage == .basic }.map(\.id))

        #expect(rootIDs == basics)
    }

    /// Printed stage and real depth are authored separately, so they can drift. A
    /// Stage 2 card sitting one step below its root would print a lie.
    @Test("printed stage matches the creature's depth in its line")
    func stageMatchesDepth() {
        let expected: [CreatureStage] = [.basic, .stage1, .stage2]
        for creature in Dex.roster {
            guard let lineage = EvolutionForest.lineage(to: creature.id),
                let stage = Dex.lore[creature.id]?.stage
            else {
                Issue.record("\(creature.id) has no lineage or no lore")
                continue
            }
            #expect(lineage.count <= expected.count, "\(creature.id) is deeper than Stage 2")
            #expect(
                stage == expected[min(lineage.count - 1, expected.count - 1)],
                "\(creature.id) prints \(stage) at depth \(lineage.count)")
        }
    }

    @Test("no line runs deeper than three forms, and there are thirty-three of them")
    func shape() {
        let leafPaths = Dex.roster.filter { EvolutionForest.node($0.id)?.isLeaf == true }

        #expect(EvolutionForest.roots.map(\.depth).max() == 3)
        #expect(leafPaths.count == 33)
    }

    @Test("Loop is the widest line and reaches the only mythic in it")
    func loopLine() {
        let loop = EvolutionForest.node("loopet")

        #expect(loop?.children.count == 4)
        #expect(loop?.depth == 3)
        #expect(EvolutionForest.bestFinal(of: "loopet") == .mythic)
        #expect(EvolutionForest.lineage(to: "weeklyrex")?.first == "loopet")
    }

    @Test("a creature outside the set has no line")
    func unknownCreature() {
        #expect(EvolutionForest.node("nobody") == nil)
        #expect(EvolutionForest.lineage(to: "nobody") == nil)
        #expect(EvolutionForest.finals(of: "nobody") == [])
        #expect(EvolutionForest.reachable(from: "nobody") == [])
    }
}

@Suite("Evolution forest: planning a run")
struct EvolutionPlanTests {

    @Test("a plan starts at the root and ends on a leaf")
    func planShape() {
        var rng = SeededGenerator(seed: 1)
        for root in EvolutionForest.roots {
            let plan = EvolutionForest.plan(from: root.id, avoiding: [], using: &rng)

            #expect(plan.first == root.id)
            #expect(EvolutionForest.node(plan.last ?? "")?.isLeaf == true)
            #expect(plan.count == Set(plan).count)
        }
    }

    @Test("the same seed plans the same run")
    func deterministic() {
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)

        #expect(
            EvolutionForest.plan(from: "loopet", avoiding: [], using: &a)
                == EvolutionForest.plan(from: "loopet", avoiding: [], using: &b))
    }

    /// The completability guarantee. Loop reaches nine finals; with eight of them
    /// filed, every plan has to walk to the ninth.
    @Test("a fork avoids branches whose finals are already filed")
    func avoidsFiled() {
        let finals = EvolutionForest.finals(of: "loopet")
        let filed = Set(finals.dropLast())
        let target = finals.last!

        for seed in UInt64(0)..<50 {
            var rng = SeededGenerator(seed: seed)
            let plan = EvolutionForest.plan(from: "loopet", avoiding: filed, using: &rng)
            #expect(plan.last == target)
        }
    }

    /// Once the line is exhausted the preference has nothing left to prefer, so it
    /// must fall back to the whole tree rather than stalling.
    @Test("an exhausted line still plans a run")
    func exhaustedLineStillPlans() {
        let filed = Set(EvolutionForest.finals(of: "loopet"))
        var seen: Set<String> = []
        for seed in UInt64(0)..<50 {
            var rng = SeededGenerator(seed: seed)
            let plan = EvolutionForest.plan(from: "loopet", avoiding: filed, using: &rng)
            #expect(EvolutionForest.node(plan.last ?? "")?.isLeaf == true)
            seen.insert(plan.last ?? "")
        }
        #expect(seen.count > 1, "a replayed line should still vary")
    }

    @Test("a floor keeps every plan at or above the promised rarity")
    func rarityFloor() {
        let rarity = Dictionary(uniqueKeysWithValues: Dex.roster.map { ($0.id, $0.rarity) })
        for tier in [CreatureRarity.rare, .epic, .legendary] {
            let candidates = EvolutionForest.roots(reaching: tier)
            #expect(!candidates.isEmpty)
            for root in candidates {
                for seed in UInt64(0)..<20 {
                    var rng = SeededGenerator(seed: seed)
                    let plan = EvolutionForest.plan(
                        from: root.id, avoiding: [], atLeast: tier, using: &rng)
                    #expect(
                        rarity[plan.last ?? ""] ?? .common >= tier,
                        "\(root.id) planned \(plan) under \(tier)")
                }
            }
        }
    }

    @Test("only the lines that can reach a tier are offered for it")
    func rootsReaching() {
        #expect(
            EvolutionForest.roots(reaching: .mythic).map(\.id).sorted() == ["loopet", "sparkit"])
        #expect(EvolutionForest.roots(reaching: .common).count == EvolutionForest.roots.count)
    }

    @Test("a single-form line plans a run of one")
    func singleForm() {
        var rng = SeededGenerator(seed: 7)

        #expect(EvolutionForest.plan(from: "promptail", avoiding: [], using: &rng) == ["promptail"])
    }
}
