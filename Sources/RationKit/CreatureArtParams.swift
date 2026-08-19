import Foundation

/// Per-creature tuning for the illustration its `CreatureArt` archetype draws.
///
/// The archetype decides the scene; these decide how many of a thing there
/// are, how fast it moves, and which of the archetype's variants is in play.
/// Straight from the set's design, so two Flame creatures are recognisably
/// the same animal and still tell each other apart.
public struct CreatureArtParams: Sendable, Equatable {
    /// Seconds for the scene's primary loop. Meaning is per archetype.
    public var speed: Double?
    /// How many of the repeated element — cells, satellites, shards, bars.
    public var count: Int?
    /// Concentric rings, for the spiral and vortex scenes.
    public var rings: Int?
    /// Rows of brick, for the wall scene.
    public var rows: Int?
    /// Rising embers, for the flame scene.
    public var sparks: Int?
    /// How far round the arc a meter has swept, 0…1.
    public var fill: Double?
    /// A second, smaller flame.
    public var twin: Bool
    /// The oversized variant.
    public var big: Bool
    /// The undersized variant.
    public var small: Bool
    /// Gold highlights, for the mythic vortex.
    public var gold: Bool
    /// A finer mesh, for the lattice scene.
    public var dense: Bool
    /// The cold, blue-lit variant of the eye.
    public var night: Bool
    /// A lantern hanging under the crescent.
    public var lantern: Bool
    /// A fourth band of split light, for the prism.
    public var fan: Bool

    public init(
        speed: Double? = nil,
        count: Int? = nil,
        rings: Int? = nil,
        rows: Int? = nil,
        sparks: Int? = nil,
        fill: Double? = nil,
        twin: Bool = false,
        big: Bool = false,
        small: Bool = false,
        gold: Bool = false,
        dense: Bool = false,
        night: Bool = false,
        lantern: Bool = false,
        fan: Bool = false
    ) {
        self.speed = speed
        self.count = count
        self.rings = rings
        self.rows = rows
        self.sparks = sparks
        self.fill = fill
        self.twin = twin
        self.big = big
        self.small = small
        self.gold = gold
        self.dense = dense
        self.night = night
        self.lantern = lantern
        self.fan = fan
    }
}

extension Dex {

    /// Illustration tuning, keyed by creature id. Missing ids draw the
    /// archetype's defaults, which is a complete picture on its own.
    public static let artParams: [String: CreatureArtParams] = [
        "sparkit": CreatureArtParams(speed: 2.2),
        "promptail": CreatureArtParams(speed: 7, count: 4),
        "gaugeling": CreatureArtParams(fill: 0.62),
        "tokenoth": CreatureArtParams(speed: 1.5),
        "cachewisp": CreatureArtParams(count: 3),
        "heatmite": CreatureArtParams(count: 16),
        "sessiondrake": CreatureArtParams(),
        "limitwyrm": CreatureArtParams(rings: 4),
        "contextaur": CreatureArtParams(count: 4),
        "modelith": CreatureArtParams(),
        "streakon": CreatureArtParams(count: 5),
        "burnrate": CreatureArtParams(speed: 3.2),
        "weeklyrex": CreatureArtParams(count: 7),
        "braidon": CreatureArtParams(),
        "nightshift": CreatureArtParams(),
        "omnivore": CreatureArtParams(count: 3, big: true),
        "wallback": CreatureArtParams(),
        "rationyx": CreatureArtParams(rings: 5),
        "sparkline": CreatureArtParams(count: 6),
        "draftling": CreatureArtParams(count: 3),
        "tallyfin": CreatureArtParams(speed: 2.6, count: 5),
        "crumbit": CreatureArtParams(count: 4, small: true),
        "loopet": CreatureArtParams(speed: 9, rings: 3),
        "dawnlet": CreatureArtParams(),
        "echofin": CreatureArtParams(speed: 11, count: 6),
        "chiplet": CreatureArtParams(),
        "threadon": CreatureArtParams(speed: 5),
        "ledgerite": CreatureArtParams(speed: 3.4, count: 20),
        "relayon": CreatureArtParams(speed: 3.2, count: 3),
        "kindlewyrm": CreatureArtParams(speed: 1.7, twin: true),
        "siftmite": CreatureArtParams(count: 5),
        "vaultoise": CreatureArtParams(),
        "anvilon": CreatureArtParams(rows: 2),
        "lanternfox": CreatureArtParams(lantern: true),
        "quarrion": CreatureArtParams(count: 5),
        "prismarch": CreatureArtParams(fan: true),
        "tidewarden": CreatureArtParams(count: 9),
        "cinderling": CreatureArtParams(speed: 1.2, sparks: 7),
        "beaconox": CreatureArtParams(fill: 0.86, big: true),
        "forgeheart": CreatureArtParams(speed: 7, rings: 4),
        "marrowdeep": CreatureArtParams(speed: 5, count: 6),
        "weaveon": CreatureArtParams(dense: true),
        "sentinox": CreatureArtParams(),
        "harvestide": CreatureArtParams(count: 6),
        "reckonoth": CreatureArtParams(),
        "vigilith": CreatureArtParams(night: true),
        "chorusaur": CreatureArtParams(count: 7, big: true),
        "meridiax": CreatureArtParams(speed: 14, fill: 0.97, big: true),
        "aurumark": CreatureArtParams(speed: 11, rings: 6, gold: true),
        "zenithyx": CreatureArtParams(count: 7, big: true),
    ]
}

extension Creature {
    /// Illustration tuning for this creature.
    public var artParams: CreatureArtParams {
        Dex.artParams[id] ?? CreatureArtParams()
    }
}
