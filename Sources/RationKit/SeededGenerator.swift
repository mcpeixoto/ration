import Foundation

/// A reproducible random source.
///
/// The companion loop rolls for a line, a branch, a trait and a shiny, and every one
/// of those is worth pinning in a test. SplitMix64 is the whole algorithm: a fixed
/// seed always produces the same run, which is what lets the engine be tested without
/// stubbing out chance itself.
///
/// Not for anything that needs to be unguessable — this is a game, not a keystore.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
