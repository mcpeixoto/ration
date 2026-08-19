import Foundation

// MARK: - Card face data

/// Energy classes. Colour lives in Theme, not here.
public enum CreatureEnergy: String, Sendable, CaseIterable {
    case ember, signal, cache, cycle, depth, night, alloy, void

    /// Doubled damage taken. Printed on the card footer.
    public var weakness: CreatureEnergy {
        switch self {
        case .ember: .void
        case .signal: .night
        case .cache: .ember
        case .cycle: .void
        case .depth: .alloy
        case .night: .signal
        case .alloy: .depth
        case .void: .alloy
        }
    }

    /// −20 damage taken: the energy this one is strong against.
    public var resistance: CreatureEnergy {
        CreatureEnergy.allCases.first { $0.weakness == self } ?? .alloy
    }
}

public enum CreatureStage: String, Sendable {
    case basic, stage1, stage2

    public var label: String {
        switch self {
        case .basic: "Basic"
        case .stage1: "Stage 1"
        case .stage2: "Stage 2"
        }
    }
}

/// The illustration archetype a portrait draws. One animated scene per case;
/// count, speed and size vary per creature in the design.
public enum CreatureArt: String, Sendable, CaseIterable {
    case flame, orbit, gauge, wings, wisp, grid, window, spiral, slabs, prism
    case chain, comet, bars, braid, moon, cluster, wall, vortex, shards, eye
    case lattice, wave, pillars, droplet, hourglass, steps
}

public struct CreatureAttack: Sendable, Equatable {
    public let name: String
    public let energyCost: Int
    public let damage: Int
    public let text: String
}

public struct CreatureAbility: Sendable, Equatable {
    public let name: String
    public let text: String
}

public struct CreatureLore: Sendable, Equatable {
    public let energy: CreatureEnergy
    public let stage: CreatureStage
    public let evolvesFrom: String?
    public let species: String
    public let heightMetres: Double
    public let weightKilos: Double
    /// The four printed properties: Life, Energy, Power, Speed.
    public let life: Int
    public let energyCost: Int
    public let power: Int
    public let speed: Int
    public let art: CreatureArt
    public let ability: CreatureAbility?
    public let attacks: [CreatureAttack]

    /// Retreat cost, derived from rarity so it never has to be authored.
    public static func retreat(for rarity: CreatureRarity) -> Int {
        min(3, 1 + rarity.rank / 2)
    }
}

extension Dex {
    /// Card-face data, keyed by creature id.
    public static let lore: [String: CreatureLore] = [
        "sparkit": CreatureLore(
            energy: .ember, stage: .basic, evolvesFrom: nil,
            species: "Flame Creature",
            heightMetres: 0.3, weightKilos: 12.6,
            life: 50, energyCost: 1, power: 10, speed: 92,
            art: .flame, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Kindle", energyCost: 1, damage: 10,
                    text: "The one card every trainer owns before they notice they own it.")
            ]),
        "promptail": CreatureLore(
            energy: .signal, stage: .basic, evolvesFrom: nil,
            species: "Orbit Creature",
            heightMetres: 2.3, weightKilos: 14.6,
            life: 60, energyCost: 1, power: 20, speed: 76,
            art: .orbit, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Follow Up", energyCost: 1, damage: 20,
                    text: "Attacks again for 10 if the last attack missed the point.")
            ]),
        "gaugeling": CreatureLore(
            energy: .alloy, stage: .basic, evolvesFrom: nil,
            species: "Meter Creature",
            heightMetres: 1.0, weightKilos: 52.5,
            life: 60, energyCost: 1, power: 20, speed: 75,
            art: .gauge, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Read Out", energyCost: 1, damage: 20,
                    text: "Look at the top card of the week. It does not move.")
            ]),
        "tokenoth": CreatureLore(
            energy: .ember, stage: .basic, evolvesFrom: nil,
            species: "Moth Creature",
            heightMetres: 0.7, weightKilos: 21.8,
            life: 80, energyCost: 3, power: 40, speed: 36,
            art: .wings, ability: nil,
            attacks: [
                CreatureAttack(name: "Billable Dust", energyCost: 1, damage: 20, text: ""),
                CreatureAttack(
                    name: "Lampfall", energyCost: 2, damage: 40,
                    text: "Discard an energy. It could not help itself."),
            ]),
        "cachewisp": CreatureLore(
            energy: .cache, stage: .basic, evolvesFrom: nil,
            species: "Vapour Creature",
            heightMetres: 0.3, weightKilos: 11.8,
            life: 70, energyCost: 1, power: 30, speed: 68,
            art: .wisp, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Tenth Price", energyCost: 1, damage: 30,
                    text: "Costs a tenth of what it should. Nobody audits it.")
            ]),
        "heatmite": CreatureLore(
            energy: .cycle, stage: .basic, evolvesFrom: nil,
            species: "Tile Creature",
            heightMetres: 0.6, weightKilos: 20.9,
            life: 90, energyCost: 3, power: 50, speed: 39,
            art: .grid, ability: nil,
            attacks: [
                CreatureAttack(name: "Fill In", energyCost: 1, damage: 20, text: ""),
                CreatureAttack(
                    name: "Heat Map", energyCost: 2, damage: 50,
                    text: "Add 10 for each of your last five active days."),
            ]),
        "sessiondrake": CreatureLore(
            energy: .cycle, stage: .basic, evolvesFrom: nil,
            species: "Frame Creature",
            heightMetres: 0.3, weightKilos: 47.8,
            life: 90, energyCost: 2, power: 40, speed: 36,
            art: .window, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Five Hours", energyCost: 2, damage: 40,
                    text: "At the end of your turn, this card leaves play. It always comes back.")
            ]),
        "limitwyrm": CreatureLore(
            energy: .void, stage: .stage1, evolvesFrom: "Loop",
            species: "Coil Creature",
            heightMetres: 1.1, weightKilos: 15.0,
            life: 110, energyCost: 2, power: 50, speed: 80,
            art: .spiral, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Constrict", energyCost: 2, damage: 50,
                    text: "The defending creature cannot retreat until the window resets.")
            ]),
        "contextaur": CreatureLore(
            energy: .depth, stage: .stage1, evolvesFrom: "Loop",
            species: "Strata Creature",
            heightMetres: 1.1, weightKilos: 59.0,
            life: 110, energyCost: 4, power: 70, speed: 72,
            art: .slabs, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Recall", energyCost: 1, damage: 30,
                    text: "Return any card from your discard pile to your hand."),
                CreatureAttack(name: "Whole Repo", energyCost: 3, damage: 70, text: ""),
            ]),
        "modelith": CreatureLore(
            energy: .alloy, stage: .stage1, evolvesFrom: "Chip",
            species: "Facet Creature",
            heightMetres: 1.1, weightKilos: 39.0,
            life: 100, energyCost: 2, power: 40, speed: 92,
            art: .prism, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Swap Weights", energyCost: 2, damage: 40,
                    text: "Choose a new energy type for this card until end of turn.")
            ]),
        "streakon": CreatureLore(
            energy: .cycle, stage: .stage1, evolvesFrom: "Loop",
            species: "Link Creature",
            heightMetres: 0.9, weightKilos: 37.2,
            life: 120, energyCost: 2, power: 30, speed: 74,
            art: .chain, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Unbroken", energyCost: 2, damage: 30,
                    text: "Add 20 for every consecutive turn this card stayed in play.")
            ]),
        "burnrate": CreatureLore(
            energy: .ember, stage: .stage2, evolvesFrom: "Cinder",
            species: "Comet Creature",
            heightMetres: 1.8, weightKilos: 56.5,
            life: 140, energyCost: 5, power: 90, speed: 47,
            art: .comet,
            ability: CreatureAbility(
                name: "Shadow Line",
                text:
                    "While this creature is in play, your projection is always drawn 10 percent high."
            ),
            attacks: [
                CreatureAttack(name: "Run Ahead", energyCost: 2, damage: 60, text: ""),
                CreatureAttack(
                    name: "Projection", energyCost: 3, damage: 90,
                    text: "Reveal the top three cards of the week. Take the worst one anyway."),
            ]),
        "weeklyrex": CreatureLore(
            energy: .void, stage: .stage2, evolvesFrom: "Coil",
            species: "Column Creature",
            heightMetres: 1.1, weightKilos: 10.2,
            life: 160, energyCost: 6, power: 110, speed: 36,
            art: .bars,
            ability: CreatureAbility(
                name: "Slow Creep",
                text: "Damage counters on this creature are never removed by a reset."),
            attacks: [
                CreatureAttack(name: "Seven Days", energyCost: 2, damage: 50, text: ""),
                CreatureAttack(
                    name: "No Reset", energyCost: 4, damage: 110,
                    text: "Damage from this attack is not removed between turns."),
            ]),
        "braidon": CreatureLore(
            energy: .alloy, stage: .stage2, evolvesFrom: "Shift",
            species: "Strand Creature",
            heightMetres: 0.3, weightKilos: 51.8,
            life: 150, energyCost: 3, power: 80, speed: 60,
            art: .braid,
            ability: CreatureAbility(
                name: "One Score",
                text: "Energy of any type counts double while attached to this creature."),
            attacks: [
                CreatureAttack(
                    name: "Twin Feed", energyCost: 3, damage: 80,
                    text: "Attach one energy of any type from your discard pile.")
            ]),
        "nightshift": CreatureLore(
            energy: .night, stage: .stage2, evolvesFrom: "Lantern",
            species: "Crescent Creature",
            heightMetres: 1.5, weightKilos: 43.4,
            life: 190, energyCost: 6, power: 130, speed: 92,
            art: .moon,
            ability: CreatureAbility(
                name: "Small Hours",
                text:
                    "This creature cannot be put to sleep, and heals 20 at the start of every night turn."
            ),
            attacks: [
                CreatureAttack(
                    name: "Third Wind", energyCost: 2, damage: 70,
                    text: "Heal 30 if it is after 10pm where you are sitting."),
                CreatureAttack(name: "Quiet House", energyCost: 4, damage: 130, text: ""),
            ]),
        "omnivore": CreatureLore(
            energy: .alloy, stage: .stage2, evolvesFrom: "Shift",
            species: "Swarm Creature",
            heightMetres: 0.3, weightKilos: 9.4,
            life: 200, energyCost: 5, power: 120, speed: 80,
            art: .cluster,
            ability: CreatureAbility(
                name: "Any Port",
                text: "Every energy attached to this creature counts as any type you need."),
            attacks: [
                CreatureAttack(name: "Split Diet", energyCost: 1, damage: 40, text: ""),
                CreatureAttack(name: "Three Mouths", energyCost: 4, damage: 120, text: ""),
            ]),
        "wallback": CreatureLore(
            energy: .void, stage: .stage2, evolvesFrom: "Coil",
            species: "Course Creature",
            heightMetres: 0.7, weightKilos: 47.4,
            life: 210, energyCost: 8, power: 150, speed: 40,
            art: .wall,
            ability: CreatureAbility(
                name: "Hard Cap",
                text: "Attacks that would do more than 120 damage to this creature do 120 instead."),
            attacks: [
                CreatureAttack(
                    name: "Hard Stop", energyCost: 3, damage: 90,
                    text: "The defending creature cannot attack next turn."),
                CreatureAttack(name: "Rate Limit", energyCost: 5, damage: 150, text: ""),
            ]),
        "rationyx": CreatureLore(
            energy: .ember, stage: .stage2, evolvesFrom: "Kindle",
            species: "Vortex Creature",
            heightMetres: 2.3, weightKilos: 20.2,
            life: 270, energyCost: 7, power: 200, speed: 44,
            art: .vortex,
            ability: CreatureAbility(
                name: "Nothing Leaves",
                text: "No card effect can read this creature. Nothing about it is sent anywhere."),
            attacks: [
                CreatureAttack(
                    name: "Quiet Ledger", energyCost: 2, damage: 70,
                    text: "Nothing leaves the machine. Nothing needs to."),
                CreatureAttack(
                    name: "Whole Set", energyCost: 5, damage: 200,
                    text: "Add 20 for every card you have unlocked this season."),
            ]),
        "sparkline": CreatureLore(
            energy: .signal, stage: .basic, evolvesFrom: nil,
            species: "Swarm Creature",
            heightMetres: 0.3, weightKilos: 55.0,
            life: 40, energyCost: 1, power: 10, speed: 28,
            art: .cluster, ability: nil,
            attacks: [
                CreatureAttack(name: "Ping", energyCost: 1, damage: 10, text: "")
            ]),
        "draftling": CreatureLore(
            energy: .signal, stage: .basic, evolvesFrom: nil,
            species: "Strata Creature",
            heightMetres: 1.6, weightKilos: 11.5,
            life: 50, energyCost: 1, power: 20, speed: 93,
            art: .slabs, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Rough Pass", energyCost: 1, damage: 20,
                    text: "Flip a coin. On tails, do it again next turn.")
            ]),
        "tallyfin": CreatureLore(
            energy: .alloy, stage: .basic, evolvesFrom: nil,
            species: "Column Creature",
            heightMetres: 0.5, weightKilos: 52.0,
            life: 50, energyCost: 1, power: 20, speed: 90,
            art: .bars, ability: nil,
            attacks: [
                CreatureAttack(name: "Add Up", energyCost: 1, damage: 20, text: "")
            ]),
        "crumbit": CreatureLore(
            energy: .cache, stage: .basic, evolvesFrom: nil,
            species: "Vapour Creature",
            heightMetres: 1.9, weightKilos: 11.0,
            life: 40, energyCost: 1, power: 10, speed: 40,
            art: .wisp, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Scavenge", energyCost: 1, damage: 10,
                    text: "Heal 10. It found something in the context window.")
            ]),
        "loopet": CreatureLore(
            energy: .cycle, stage: .basic, evolvesFrom: nil,
            species: "Coil Creature",
            heightMetres: 0.7, weightKilos: 60.2,
            life: 60, energyCost: 1, power: 20, speed: 28,
            art: .spiral, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Again", energyCost: 1, damage: 20,
                    text: "You may use this attack twice this turn.")
            ]),
        "dawnlet": CreatureLore(
            energy: .cycle, stage: .basic, evolvesFrom: nil,
            species: "Bead Creature",
            heightMetres: 1.9, weightKilos: 63.0,
            life: 50, energyCost: 1, power: 20, speed: 52,
            art: .droplet, ability: nil,
            attacks: [
                CreatureAttack(name: "Cold Start", energyCost: 1, damage: 20, text: "")
            ]),
        "echofin": CreatureLore(
            energy: .signal, stage: .basic, evolvesFrom: nil,
            species: "Orbit Creature",
            heightMetres: 0.5, weightKilos: 61.6,
            life: 60, energyCost: 1, power: 20, speed: 90,
            art: .orbit, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Restate", energyCost: 1, damage: 20,
                    text: "Copy the last attack used against this creature.")
            ]),
        "chiplet": CreatureLore(
            energy: .alloy, stage: .basic, evolvesFrom: nil,
            species: "Mesh Creature",
            heightMetres: 2.3, weightKilos: 23.4,
            life: 70, energyCost: 1, power: 20, speed: 92,
            art: .lattice, ability: nil,
            attacks: [
                CreatureAttack(name: "Overhead", energyCost: 1, damage: 20, text: "")
            ]),
        "threadon": CreatureLore(
            energy: .signal, stage: .stage1, evolvesFrom: "Draft",
            species: "Strand Creature",
            heightMetres: 0.9, weightKilos: 50.0,
            life: 80, energyCost: 2, power: 40, speed: 42,
            art: .braid, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Long Turn", energyCost: 2, damage: 40,
                    text: "Add 10 for each other Signal creature you have in play.")
            ]),
        "ledgerite": CreatureLore(
            energy: .cycle, stage: .stage1, evolvesFrom: "Dawn",
            species: "Tile Creature",
            heightMetres: 1.0, weightKilos: 44.5,
            life: 100, energyCost: 3, power: 50, speed: 47,
            art: .grid, ability: nil,
            attacks: [
                CreatureAttack(name: "Post Entry", energyCost: 1, damage: 30, text: ""),
                CreatureAttack(
                    name: "Reconcile", energyCost: 2, damage: 50,
                    text: "Look at your discard pile. Nothing is missing."),
            ]),
        "relayon": CreatureLore(
            energy: .alloy, stage: .stage1, evolvesFrom: "Tally",
            species: "Link Creature",
            heightMetres: 1.9, weightKilos: 61.4,
            life: 90, energyCost: 2, power: 40, speed: 92,
            art: .chain, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Hand Off", energyCost: 2, damage: 40,
                    text: "Move all energy from this creature to another one you have.")
            ]),
        "kindlewyrm": CreatureLore(
            energy: .ember, stage: .stage1, evolvesFrom: "Ember",
            species: "Flame Creature",
            heightMetres: 0.3, weightKilos: 55.8,
            life: 90, energyCost: 2, power: 50, speed: 56,
            art: .flame, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Catch", energyCost: 2, damage: 50,
                    text: "Add 20 if you attacked with an Ember creature last turn.")
            ]),
        "siftmite": CreatureLore(
            energy: .cache, stage: .stage1, evolvesFrom: "Wisp",
            species: "Shard Creature",
            heightMetres: 2.3, weightKilos: 52.2,
            life: 80, energyCost: 1, power: 30, speed: 84,
            art: .shards, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Grep", energyCost: 1, damage: 30,
                    text: "Search your deck for any card and put it in your hand.")
            ]),
        "vaultoise": CreatureLore(
            energy: .cache, stage: .stage1, evolvesFrom: "Crumb",
            species: "Frame Creature",
            heightMetres: 1.8, weightKilos: 26.9,
            life: 110, energyCost: 2, power: 40, speed: 75,
            art: .window, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Warm Store", energyCost: 2, damage: 40,
                    text: "Reduce damage to this creature by 20 while it holds energy.")
            ]),
        "anvilon": CreatureLore(
            energy: .ember, stage: .stage1, evolvesFrom: "Ember",
            species: "Course Creature",
            heightMetres: 1.1, weightKilos: 15.0,
            life: 110, energyCost: 5, power: 70, speed: 52,
            art: .wall, ability: nil,
            attacks: [
                CreatureAttack(name: "Strike", energyCost: 2, damage: 50, text: ""),
                CreatureAttack(
                    name: "Set Piece", energyCost: 3, damage: 70,
                    text: "This creature takes no damage from Common creatures."),
            ]),
        "lanternfox": CreatureLore(
            energy: .night, stage: .stage1, evolvesFrom: "Crumb",
            species: "Crescent Creature",
            heightMetres: 1.9, weightKilos: 29.4,
            life: 120, energyCost: 2, power: 50, speed: 84,
            art: .moon, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Keep Watch", energyCost: 2, damage: 50,
                    text: "Heal 20 at the end of every turn this creature stays in play.")
            ]),
        "quarrion": CreatureLore(
            energy: .ember, stage: .stage1, evolvesFrom: "Ember",
            species: "Terrace Creature",
            heightMetres: 1.1, weightKilos: 32.6,
            life: 130, energyCost: 5, power: 80, speed: 64,
            art: .steps, ability: nil,
            attacks: [
                CreatureAttack(name: "Cut Deep", energyCost: 2, damage: 60, text: ""),
                CreatureAttack(
                    name: "Haul", energyCost: 3, damage: 80,
                    text: "Discard an energy from this creature."),
            ]),
        "prismarch": CreatureLore(
            energy: .depth, stage: .stage1, evolvesFrom: "Needle",
            species: "Facet Creature",
            heightMetres: 1.1, weightKilos: 56.6,
            life: 110, energyCost: 2, power: 40, speed: 68,
            art: .prism, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Split Beam", energyCost: 2, damage: 40,
                    text: "This attack hits every creature on the bench for 10.")
            ]),
        "tidewarden": CreatureLore(
            energy: .cycle, stage: .stage1, evolvesFrom: "Loop",
            species: "Swell Creature",
            heightMetres: 0.9, weightKilos: 26.0,
            life: 130, energyCost: 5, power: 80, speed: 86,
            art: .wave, ability: nil,
            attacks: [
                CreatureAttack(name: "Rise", energyCost: 2, damage: 50, text: ""),
                CreatureAttack(
                    name: "Reset", energyCost: 3, damage: 80,
                    text: "Remove all damage counters from this creature."),
            ]),
        "cinderling": CreatureLore(
            energy: .ember, stage: .stage1, evolvesFrom: "Ember",
            species: "Flame Creature",
            heightMetres: 2.3, weightKilos: 29.0,
            life: 120, energyCost: 2, power: 60, speed: 36,
            art: .flame, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Still Hot", energyCost: 2, damage: 60,
                    text: "Add 20 if this creature was damaged last turn.")
            ]),
        "beaconox": CreatureLore(
            energy: .cycle, stage: .stage1, evolvesFrom: "Cell",
            species: "Meter Creature",
            heightMetres: 0.7, weightKilos: 37.0,
            life: 140, energyCost: 3, power: 70, speed: 40,
            art: .gauge, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Signal Fire", energyCost: 3, damage: 70,
                    text: "Both players reveal their next unlock.")
            ]),
        "forgeheart": CreatureLore(
            energy: .ember, stage: .stage2, evolvesFrom: "Kindle",
            species: "Vortex Creature",
            heightMetres: 2.3, weightKilos: 41.0,
            life: 150, energyCost: 6, power: 120, speed: 28,
            art: .vortex,
            ability: CreatureAbility(
                name: "Always Lit",
                text: "At the start of your turn, attach one Ember energy from your discard pile."),
            attacks: [
                CreatureAttack(name: "Temper", energyCost: 2, damage: 60, text: ""),
                CreatureAttack(name: "Pour", energyCost: 4, damage: 120, text: ""),
            ]),
        "marrowdeep": CreatureLore(
            energy: .depth, stage: .stage2, evolvesFrom: "Context",
            species: "Strata Creature",
            heightMetres: 2.3, weightKilos: 10.6,
            life: 160, energyCost: 6, power: 110, speed: 56,
            art: .slabs,
            ability: CreatureAbility(
                name: "Warm Prefix", text: "Your first attack each turn costs one less energy."),
            attacks: [
                CreatureAttack(
                    name: "Deep Read", energyCost: 2, damage: 50,
                    text: "Draw until your hand holds six cards."),
                CreatureAttack(name: "Full Prefix", energyCost: 4, damage: 110, text: ""),
            ]),
        "weaveon": CreatureLore(
            energy: .depth, stage: .stage2, evolvesFrom: "Context",
            species: "Mesh Creature",
            heightMetres: 1.9, weightKilos: 20.6,
            life: 150, energyCost: 3, power: 80, speed: 68,
            art: .lattice,
            ability: CreatureAbility(
                name: "Held Together",
                text:
                    "This creature takes 20 less damage for every other creature you have in play."),
            attacks: [
                CreatureAttack(
                    name: "Cross Stitch", energyCost: 3, damage: 80,
                    text: "Add 10 for every energy attached to your creatures.")
            ]),
        "sentinox": CreatureLore(
            energy: .void, stage: .stage2, evolvesFrom: "Coil",
            species: "Watcher Creature",
            heightMetres: 0.3, weightKilos: 3.8,
            life: 170, energyCost: 6, power: 130, speed: 32,
            art: .eye,
            ability: CreatureAbility(
                name: "Warn Once",
                text:
                    "The first time this creature would be knocked out each game, it survives with 10 HP."
            ),
            attacks: [
                CreatureAttack(
                    name: "Threshold", energyCost: 2, damage: 60,
                    text: "Warn once at 80 percent. Never twice."),
                CreatureAttack(name: "Cutoff", energyCost: 4, damage: 130, text: ""),
            ]),
        "harvestide": CreatureLore(
            energy: .cycle, stage: .stage2, evolvesFrom: "Streak",
            species: "Grove Creature",
            heightMetres: 1.1, weightKilos: 52.6,
            life: 180, energyCost: 6, power: 120, speed: 36,
            art: .pillars,
            ability: CreatureAbility(
                name: "Two Months",
                text: "Heal 10 from each of your creatures at the end of every turn."),
            attacks: [
                CreatureAttack(
                    name: "Gather", energyCost: 2, damage: 60,
                    text: "Heal 10 for each active day in your current streak."),
                CreatureAttack(name: "Reap", energyCost: 4, damage: 120, text: ""),
            ]),
        "reckonoth": CreatureLore(
            energy: .void, stage: .stage2, evolvesFrom: "Coil",
            species: "Glass Creature",
            heightMetres: 0.7, weightKilos: 64.2,
            life: 200, energyCost: 7, power: 160, speed: 36,
            art: .hourglass,
            ability: CreatureAbility(
                name: "Due Now",
                text:
                    "Both players discard an energy at the start of every turn. Neither may decline."
            ),
            attacks: [
                CreatureAttack(name: "Estimate", energyCost: 2, damage: 70, text: ""),
                CreatureAttack(
                    name: "Settle Up", energyCost: 5, damage: 160,
                    text: "Discard every energy attached to this creature."),
            ]),
        "vigilith": CreatureLore(
            energy: .night, stage: .stage2, evolvesFrom: "Lantern",
            species: "Watcher Creature",
            heightMetres: 2.3, weightKilos: 6.6,
            life: 190, energyCost: 8, power: 150, speed: 40,
            art: .eye,
            ability: CreatureAbility(
                name: "Never Dark",
                text: "This creature is not affected by any special condition, ever."),
            attacks: [
                CreatureAttack(name: "Long Watch", energyCost: 3, damage: 90, text: ""),
                CreatureAttack(
                    name: "Unbroken Chain", energyCost: 5, damage: 150,
                    text: "Add 10 for every turn this creature has been in play."),
            ]),
        "chorusaur": CreatureLore(
            energy: .alloy, stage: .stage2, evolvesFrom: "Shift",
            species: "Swarm Creature",
            heightMetres: 0.3, weightKilos: 29.4,
            life: 200, energyCost: 8, power: 150, speed: 64,
            art: .cluster,
            ability: CreatureAbility(
                name: "Best of Six",
                text:
                    "Before you attack, look at the top six cards of your deck and put one in your hand."
            ),
            attacks: [
                CreatureAttack(name: "Ensemble", energyCost: 3, damage: 80, text: ""),
                CreatureAttack(name: "Unison", energyCost: 5, damage: 150, text: ""),
            ]),
        "meridiax": CreatureLore(
            energy: .night, stage: .stage2, evolvesFrom: "Lantern",
            species: "Meter Creature",
            heightMetres: 1.1, weightKilos: 13.4,
            life: 210, energyCost: 8, power: 160, speed: 80,
            art: .gauge,
            ability: CreatureAbility(
                name: "No Midnight", text: "Ignore the first reset of every game."),
            attacks: [
                CreatureAttack(name: "Cross Over", energyCost: 3, damage: 90, text: ""),
                CreatureAttack(name: "Zenith Hour", energyCost: 5, damage: 160, text: ""),
            ]),
        "aurumark": CreatureLore(
            energy: .ember, stage: .stage2, evolvesFrom: "Kindle",
            species: "Vortex Creature",
            heightMetres: 0.3, weightKilos: 43.8,
            life: 260, energyCost: 9, power: 220, speed: 36,
            art: .vortex,
            ability: CreatureAbility(
                name: "Gilded Ledger",
                text: "Every foil card in your binder adds 10 to this creature’s attacks."),
            attacks: [
                CreatureAttack(name: "Gilded Total", energyCost: 3, damage: 100, text: ""),
                CreatureAttack(name: "Full Ledger", energyCost: 6, damage: 220, text: ""),
            ]),
        "zenithyx": CreatureLore(
            energy: .void, stage: .stage2, evolvesFrom: "Coil",
            species: "Shard Creature",
            heightMetres: 2.3, weightKilos: 50.6,
            life: 280, energyCost: 9, power: 230, speed: 72,
            art: .shards,
            ability: CreatureAbility(
                name: "Scale Point",
                text: "Every other card in play is measured against this one. Halve their damage."),
            attacks: [
                CreatureAttack(name: "Peak Load", energyCost: 3, damage: 110, text: ""),
                CreatureAttack(
                    name: "One Day Only", energyCost: 6, damage: 230,
                    text: "This attack cannot be used again this season."),
            ]),
    ]
}

// MARK: - Printed labels

extension CreatureEnergy {

    public var label: String {
        switch self {
        case .ember: "Ember"
        case .signal: "Signal"
        case .cache: "Cache"
        case .cycle: "Cycle"
        case .depth: "Depth"
        case .night: "Night"
        case .alloy: "Alloy"
        case .void: "Void"
        }
    }

    /// The mark printed inside an energy pip. One glyph, no colour.
    public var glyph: String {
        switch self {
        case .ember: "\u{25B2}"  // ▲
        case .signal: "\u{25C9}"  // ◉
        case .cache: "\u{25A3}"  // ▣
        case .cycle: "\u{27F3}"  // ⟳
        case .depth: "\u{25C6}"  // ◆
        case .night: "\u{263D}"  // ☽
        case .alloy: "\u{2B22}"  // ⬢
        case .void: "\u{2715}"  // ✕
        }
    }
}

extension CreatureLore {

    /// Retreat cost for this card, from its rarity.
    public func retreat(for rarity: CreatureRarity) -> Int {
        CreatureLore.retreat(for: rarity)
    }

    /// "0.3 m · 12.6 kg", as printed under the illustration.
    public var size: String {
        String(format: "%.1f m · %.1f kg", heightMetres, weightKilos)
    }

    /// Total energy the printed attacks ask for.
    public var printedEnergy: Int { energyCost }
}

extension Creature {

    /// The card face for this creature. Every creature in the set has one;
    /// the fallback keeps a card drawable if lore is ever missing an id.
    public var lore: CreatureLore {
        Dex.lore[id] ?? CreatureLore.fallback(for: self)
    }
}

extension CreatureLore {

    /// A plain card face, derived from rarity, for an id with no printed lore.
    static func fallback(for creature: Creature) -> CreatureLore {
        let rank = creature.rarity.rank
        return CreatureLore(
            energy: .alloy, stage: .basic, evolvesFrom: nil,
            species: "Unknown Creature",
            heightMetres: 1.0, weightKilos: 20.0,
            life: 50 + rank * 40, energyCost: 1 + rank, power: 20 + rank * 30,
            speed: 40 + rank * 8,
            art: .orbit, ability: nil,
            attacks: [
                CreatureAttack(
                    name: "Unlisted", energyCost: 1, damage: 20 + rank * 20, text: "")
            ])
    }
}
