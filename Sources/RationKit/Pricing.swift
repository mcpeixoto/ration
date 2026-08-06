import Foundation

/// Estimates what usage *would* have cost on the pay-as-you-go API.
///
/// **This is not a bill.** On a Claude subscription you pay a flat monthly fee,
/// not per token. This number answers "what would this have cost through the
/// API?", which is a useful sense of scale and nothing more. The UI labels it
/// as an estimate everywhere it appears.
///
/// Rates are USD per million tokens, from Anthropic's published pricing.
/// They change; `PricingTests` guards the arithmetic, not the numbers.
public enum Pricing {

    /// Per-million-token rates for one model.
    public struct Rate: Sendable, Equatable {
        public let input: Double
        public let output: Double

        public init(input: Double, output: Double) {
            self.input = input
            self.output = output
        }

        /// Writing to the cache costs more than a plain input token: 1.25× for
        /// the 5-minute TTL, 2× for the 1-hour TTL.
        public var cacheWrite5m: Double { input * 1.25 }
        public var cacheWrite1h: Double { input * 2.0 }

        /// Reading from the cache is the cheap part — a tenth of input.
        public var cacheRead: Double { input * 0.1 }
    }

    /// Known models. Matching is by prefix, so dated snapshots
    /// (`claude-haiku-4-5-20251001`) resolve to their family.
    static let rates: [(prefix: String, rate: Rate)] = [
        // Most specific first — `claude-opus-4-8` must not be shadowed by `claude-opus`.
        ("claude-fable-5", Rate(input: 10, output: 50)),
        ("claude-mythos-5", Rate(input: 10, output: 50)),
        ("claude-opus-5", Rate(input: 5, output: 25)),
        ("claude-opus-4", Rate(input: 5, output: 25)),
        ("claude-opus", Rate(input: 15, output: 75)),
        ("claude-sonnet-5", Rate(input: 3, output: 15)),
        ("claude-sonnet-4", Rate(input: 3, output: 15)),
        ("claude-sonnet", Rate(input: 3, output: 15)),
        ("claude-haiku-4", Rate(input: 1, output: 5)),
        ("claude-haiku", Rate(input: 0.8, output: 4)),
    ]

    /// The rate for a model, or `nil` for models we have no pricing for —
    /// including the `<synthetic>` entries Claude Code writes for local turns.
    public static func rate(forModel model: String) -> Rate? {
        rates.first { model.hasPrefix($0.prefix) }?.rate
    }

    /// Estimated API-equivalent cost of one turn, in USD.
    ///
    /// Returns 0 for models with no known rate rather than guessing.
    public static func cost(of event: UsageEvent) -> Double {
        guard let rate = rate(forModel: event.model) else { return 0 }

        let millions = 1_000_000.0
        return
            (Double(event.inputTokens) * rate.input
            + Double(event.outputTokens) * rate.output
            + Double(event.cacheWrite5mTokens) * rate.cacheWrite5m
            + Double(event.cacheWrite1hTokens) * rate.cacheWrite1h
            + Double(event.cacheReadTokens) * rate.cacheRead) / millions
    }
}
