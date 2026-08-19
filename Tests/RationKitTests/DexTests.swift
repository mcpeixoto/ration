import Foundation
import Testing

@testable import RationKit

@Suite("Dex: empty history")
struct DexEmptyTests {

    @Test("catches nothing until there is usage")
    func emptyUnlocksNothing() {
        let state = Dex.evaluate(DexInput(histories: ["claude": UsageHistory()]))

        #expect(state.caught.isEmpty)
        #expect(state.stats.power == 0)
        #expect(state.uncaught.count == Dex.roster.count)
    }
}

@Suite("Dex: spending unlocks creatures")
struct DexUnlockTests {

    @Test("the first tokens catch Sparkit")
    func firstTokensCatchSparkit() {
        let state = Dex.evaluate(DexInput(histories: ["claude": history(billable: 1_000)]))

        #expect(state.caught.map(\.id) == ["sparkit"])
        #expect(state.stats.power == 1_000)
    }

    @Test("Power is the sum of billable tokens across every tool")
    func powerSumsEveryProvider() {
        let state = Dex.evaluate(
            DexInput(histories: [
                "claude": history(billable: 100_000),
                "codex": history(billable: 150_000, model: "gpt-5"),
            ]))

        #expect(state.stats.power == 250_000)
        #expect(state.caught.map(\.id).contains("tokenoth"))
    }

    @Test("two tools together catch more than either would alone")
    func combinedSpendUnlocksWhatNeitherReaches() {
        let claude = history(billable: 1_200_000)
        let codex = history(billable: 1_200_000, model: "gpt-5")

        let claudeOnly = Dex.evaluate(DexInput(histories: ["claude": claude]))
        let together = Dex.evaluate(
            DexInput(histories: ["claude": claude, "codex": codex]))

        #expect(!claudeOnly.caught.map(\.id).contains("limitwyrm"))
        #expect(together.caught.map(\.id).contains("limitwyrm"))
        #expect(together.caught.count > claudeOnly.caught.count)
    }

    @Test("a second tool with real usage catches Braidon")
    func twoProvidersCatchBraidon() {
        let state = Dex.evaluate(
            DexInput(histories: [
                "claude": history(billable: 1_000),
                "codex": history(billable: 1_000, model: "gpt-5"),
            ]))

        #expect(state.caught.map(\.id).contains("braidon"))
        #expect(state.stats.providers == ["claude", "codex"])
    }

    @Test("a live Cursor snapshot counts as a tool even without history")
    func liveCursorCountsAsAProvider() {
        let state = Dex.evaluate(
            DexInput(
                histories: [
                    "claude": history(billable: 1_000),
                    "codex": history(billable: 1_000, model: "gpt-5"),
                ],
                liveProviders: ["cursor"]))

        #expect(state.caught.map(\.id).contains("omnivore"))
        #expect(state.stats.providers == ["claude", "codex", "cursor"])
    }

    @Test("a live snapshot with no usage does not count as a tool")
    func idleLiveProviderIsIgnored() {
        let state = Dex.evaluate(
            DexInput(
                histories: ["claude": history(billable: 1_000)],
                liveProviders: []))

        #expect(!state.caught.map(\.id).contains("braidon"))
    }

    @Test("a live Cursor-only account still catches Sparkit")
    func liveCursorAloneCatchesSparkit() {
        let state = Dex.evaluate(
            DexInput(histories: [:], liveProviders: ["cursor"]))

        #expect(state.caught.map(\.id) == ["sparkit"])
        #expect(state.stats.power == 0)
    }

    @Test("enough messages catch Promptail")
    func messagesCatchPromptail() {
        let state = Dex.evaluate(
            DexInput(histories: ["claude": history(billable: 25, messages: 25)]))

        #expect(state.caught.map(\.id).contains("promptail"))
    }

    @Test("cache reads catch Cachewisp")
    func cacheReadsCatchCachewisp() {
        let state = Dex.evaluate(
            DexInput(histories: ["claude": history(billable: 1_000, cacheRead: 100_000)]))

        #expect(state.caught.map(\.id).contains("cachewisp"))
    }

    @Test("five active days catch Heatmite")
    func activeDaysCatchHeatmite() {
        let state = Dex.evaluate(
            DexInput(histories: ["claude": history(billable: 100, days: 5)]))

        #expect(state.caught.map(\.id).contains("heatmite"))
        #expect(state.stats.activeDays == 5)
    }

    @Test("a five-day streak catches Streakon")
    func streakCatchesStreakon() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 18
        components.hour = 12
        let now = calendar.date(from: components)!

        let state = Dex.evaluate(
            DexInput(
                histories: ["claude": history(billable: 100, days: 5, endingOn: now)],
                now: now,
                calendar: calendar))

        #expect(state.stats.streak == 5)
        #expect(state.caught.map(\.id).contains("streakon"))
    }

    @Test("three models catch Modelith")
    func threeModelsCatchModelith() {
        var h = UsageHistory()
        h.add([
            event(billable: 100, model: "claude-opus-5"),
            event(billable: 100, model: "claude-sonnet-5"),
            event(billable: 100, model: "claude-haiku-4"),
        ])

        let state = Dex.evaluate(DexInput(histories: ["claude": h]))

        #expect(state.caught.map(\.id).contains("modelith"))
    }

    @Test("coding after 10pm catches Nightshift")
    func lateNightCatchesNightshift() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 18
        components.hour = 23
        let stamp = calendar.date(from: components)!

        var h = UsageHistory()
        h.add([event(billable: 2_000, timestamp: stamp)], calendar: calendar)

        let state = Dex.evaluate(DexInput(histories: ["claude": h], calendar: calendar))

        #expect(state.caught.map(\.id).contains("nightshift"))
    }

    @Test("a single huge day catches Wallback")
    func hugeDayCatchesWallback() {
        let state = Dex.evaluate(
            DexInput(histories: ["claude": history(billable: 2_000_000)]))

        #expect(state.caught.map(\.id).contains("wallback"))
    }

    @Test("a hundred million Power catches Rationyx")
    func mythicNeedsAMountainOfTokens() {
        let almost = Dex.evaluate(
            DexInput(histories: ["claude": history(billable: 99_000_000)]))
        let enough = Dex.evaluate(
            DexInput(histories: ["claude": history(billable: 100_000_000)]))

        #expect(!almost.caught.map(\.id).contains("rationyx"))
        #expect(enough.caught.map(\.id).contains("rationyx"))
    }

    @Test("the hour rules read the busiest hour, not the clock")
    func hourRequirements() {
        var morning = TrainerStats()
        morning.busiestHour = 8
        var evening = TrainerStats()
        evening.busiestHour = 17
        var night = TrainerStats()
        night.busiestHour = 23

        #expect(UnlockRequirement.earlyBird.isMet(by: morning))
        #expect(!UnlockRequirement.earlyBird.isMet(by: evening))
        #expect(UnlockRequirement.dusk.isMet(by: evening))
        #expect(!UnlockRequirement.dusk.isMet(by: morning))
        #expect(UnlockRequirement.nightOwl.isMet(by: night))
        #expect(!UnlockRequirement.nightOwl.isMet(by: morning))
    }

    @Test("the estimate rule reads dollars, not tokens")
    func costRequirement() {
        var poor = TrainerStats()
        poor.cost = 4.5
        var rich = TrainerStats()
        rich.cost = 21

        #expect(!UnlockRequirement.cost(20).isMet(by: poor))
        #expect(UnlockRequirement.cost(20).isMet(by: rich))
    }
}

@Suite("Dex: progress and reveals")
struct DexProgressTests {

    @Test("progress toward the next Power catch is a 0...1 fraction")
    func progressTowardNextPowerCatch() {
        let state = Dex.evaluate(DexInput(histories: ["claude": history(billable: 25_000)]))

        let next = state.nextPowerCatch
        #expect(next?.creature.id == "gaugeling")
        #expect(next != nil)
        #expect(abs((next?.progress ?? 0) - 0.5) < 0.01)
    }

    @Test("creatures already revealed are not pending")
    func revealedCreaturesAreNotPending() {
        let caught = Dex.evaluate(DexInput(histories: ["claude": history(billable: 1_000)])).caught

        let pending = Dex.pendingReveals(caught: caught, alreadyRevealed: ["sparkit"])
        #expect(pending.isEmpty)
    }

    @Test("a newly caught creature is pending until it has been revealed")
    func newCatchIsPending() {
        let caught = Dex.evaluate(DexInput(histories: ["claude": history(billable: 1_000)])).caught

        let pending = Dex.pendingReveals(caught: caught, alreadyRevealed: [])
        #expect(pending.map(\.id) == ["sparkit"])
    }
}

@Suite("Dex: the set itself")
struct DexRosterTests {

    @Test("every creature has a unique id and collector number")
    func uniqueIdentities() {
        let ids = Dex.roster.map(\.id)
        let numbers = Dex.roster.map(\.number)

        #expect(Set(ids).count == Dex.roster.count)
        #expect(Set(numbers).count == Dex.roster.count)
        #expect(numbers == Array(1...Dex.roster.count))
    }

    @Test("the set is fifty creatures")
    func setSize() {
        #expect(Dex.roster.count == 50)
    }

    @Test("display names are plain English, not clone portmanteaus")
    func readableNames() {
        #expect(
            Dex.roster.map(\.name) == [
                "Ember", "Prompt", "Needle", "Moth", "Wisp", "Cell",
                "Session", "Coil", "Context", "Shift", "Streak", "Pace",
                "Week", "Braid", "Night", "Trio", "Wall", "Mark",
                "Spark", "Draft", "Tally", "Crumb", "Loop", "Dawn",
                "Echo", "Chip", "Thread", "Ledger", "Relay", "Kindle",
                "Sift", "Vault", "Anvil", "Lantern", "Quarry", "Prism",
                "Tide", "Cinder", "Beacon", "Forge", "Marrow", "Weave",
                "Sentinel", "Harvest", "Reckon", "Vigil", "Chorus",
                "Meridian", "Aurum", "Zenith",
            ])
    }

    @Test("the first eighteen cards keep the ids they shipped with")
    func shippingIDsAreStable() {
        #expect(
            Dex.roster.prefix(18).map(\.id) == [
                "sparkit", "promptail", "gaugeling", "tokenoth", "cachewisp",
                "heatmite", "sessiondrake", "limitwyrm", "contextaur", "modelith",
                "streakon", "burnrate", "weeklyrex", "braidon", "nightshift",
                "omnivore", "wallback", "rationyx",
            ])
    }

    @Test("collector numbers run 1…50 with no gaps and no repeats")
    func numbering() {
        #expect(Dex.roster.map(\.number) == Array(1...50))
        #expect(Set(Dex.roster.map(\.id)).count == 50)
    }

    @Test("every creature has a printed card face")
    func everyCreatureHasLore() {
        for creature in Dex.roster {
            let lore = Dex.lore[creature.id]
            #expect(lore != nil, "\(creature.id) has no lore")
            guard let lore else { continue }
            #expect(lore.life > 0)
            #expect(lore.energyCost > 0)
            #expect(lore.power > 0)
            #expect(lore.speed > 0)
            #expect(!lore.species.isEmpty)
            #expect(!lore.attacks.isEmpty)
            #expect(lore.attacks.allSatisfy { !$0.name.isEmpty && $0.damage > 0 })
            #expect(creature.artConcepts.count >= 2)
            #expect(!creature.artPrompt.isEmpty)
        }
    }

    @Test("every creature has illustration tuning, and nothing else does")
    func artParamsMatchRoster() {
        #expect(Set(Dex.artParams.keys) == Set(Dex.roster.map(\.id)))
        for creature in Dex.roster {
            let params = creature.artParams
            #expect((params.speed ?? 1) > 0)
            #expect((params.count ?? 1) > 0)
            #expect((params.rings ?? 1) > 0)
            #expect((params.rows ?? 1) > 0)
            #expect((params.sparks ?? 1) > 0)
            if let fill = params.fill {
                #expect(fill >= 0)
                #expect(fill <= 1)
            }
        }
    }

    @Test("lore has no entries for creatures that are not in the set")
    func loreMatchesRoster() {
        #expect(Set(Dex.lore.keys) == Set(Dex.roster.map(\.id)))
    }

    @Test("evolved cards say what they evolve from")
    func evolutionLines() {
        for creature in Dex.roster {
            let lore = creature.lore
            if lore.stage == .basic {
                #expect(lore.evolvesFrom == nil)
            } else {
                #expect(lore.evolvesFrom?.isEmpty == false)
            }
        }
    }

    @Test("weakness and resistance are never the card's own energy")
    func typeChart() {
        for energy in CreatureEnergy.allCases {
            #expect(energy.weakness != energy)
            #expect(energy.resistance != energy)
            #expect(!energy.glyph.isEmpty)
            #expect(!energy.label.isEmpty)
        }
    }

    @Test("retreat cost stays inside the printed one-to-three pips")
    func retreatCost() {
        for rarity in CreatureRarity.allCases {
            let cost = CreatureLore.retreat(for: rarity)
            #expect(cost >= 1)
            #expect(cost <= 3)
        }
    }

    @Test("harder cards hit harder")
    func rarityScalesTheCardFace() {
        let common = Dex.roster.filter { $0.rarity == .common }.map { $0.lore.life }
        let mythic = Dex.roster.filter { $0.rarity == .mythic }.map { $0.lore.life }

        #expect(common.max()! < mythic.min()!)
    }
}

@Suite("Creature share caption")
struct CreatureShareTests {

    @Test("names the creature, the count, and the repository")
    func caption() {
        let text = CreatureShare.caption(name: "Ember", caught: 11, of: 18)

        #expect(text.contains("Ember"))
        #expect(text.contains("11 of 18"))
        #expect(text.contains("github.com/mcpeixoto/ration"))
        #expect(!text.contains("http"))
    }
}

// MARK: - Fixtures

/// One-day history unless `days` is set, in which the same billable count
/// is split across consecutive days ending today (or `endingOn`).
/// Midday on a fixed date, so a test that does not care about the hour
/// cannot accidentally catch Nightshift just because it ran after 10pm.
private let fixtureNoon: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 12
    components.hour = 12
    return Calendar(identifier: .gregorian).date(from: components)!
}()

private func history(
    billable: Int,
    messages: Int? = nil,
    cacheRead: Int = 0,
    days: Int = 1,
    endingOn end: Date = fixtureNoon,
    model: String = "claude-opus-5",
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> UsageHistory {
    var h = UsageHistory()
    let perDay = max(billable / days, 1)
    let perMessage = messages.map { max($0 / days, 1) } ?? 1
    for offset in 0..<days {
        guard let day = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: end) else {
            continue
        }
        let count = messages == nil ? 1 : perMessage
        h.add(
            (0..<count).map { i in
                event(
                    billable: perDay / count,
                    cacheRead: cacheRead / days,
                    model: model,
                    session: "s\(offset)-\(i)",
                    timestamp: day)
            },
            calendar: calendar)
    }
    return h
}

private func event(
    billable: Int,
    cacheRead: Int = 0,
    model: String = "claude-opus-5",
    session: String = "s1",
    timestamp: Date = fixtureNoon
) -> UsageEvent {
    UsageEvent(
        timestamp: timestamp, model: model, project: "p", sessionID: session,
        inputTokens: billable, outputTokens: 0, cacheReadTokens: cacheRead)
}
