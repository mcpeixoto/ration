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
    ///
    /// The cache multipliers are stored rather than computed because they are a
    /// property of the *vendor*, not of arithmetic: Anthropic charges a premium
    /// to write to the cache and prices two TTLs, OpenAI charges nothing extra
    /// to write and has one tier. Deriving them from `input` baked one vendor's
    /// billing model into every provider.
    public struct Rate: Sendable, Equatable {
        public let input: Double
        public let output: Double
        public let cacheWrite5m: Double
        public let cacheWrite1h: Double
        public let cacheRead: Double

        public init(
            input: Double, output: Double,
            cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double
        ) {
            self.input = input
            self.output = output
            self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h
            self.cacheRead = cacheRead
        }

        /// Writing to the cache costs more than a plain input token: 1.25× for
        /// the 5-minute TTL, 2× for the 1-hour TTL. Reading is a tenth.
        public static func anthropic(input: Double, output: Double) -> Rate {
            Rate(
                input: input, output: output,
                cacheWrite5m: input * 1.25, cacheWrite1h: input * 2.0,
                cacheRead: input * 0.1)
        }

        /// No charge for writing to the cache, one TTL, and cached input at a
        /// tenth of the price.
        public static func openAI(input: Double, output: Double) -> Rate {
            Rate(
                input: input, output: output,
                cacheWrite5m: 0, cacheWrite1h: 0,
                cacheRead: input * 0.1)
        }
    }

    /// Known models. Matching is by prefix, so dated snapshots
    /// (`claude-haiku-4-5-20251001`) resolve to their family.
    static let rates: [(prefix: String, rate: Rate)] = anthropicRates + openAIRates

    private static let anthropicRates: [(prefix: String, rate: Rate)] = [
        // Most specific first — `claude-opus-4-8` must not be shadowed by `claude-opus`.
        ("claude-fable-5", .anthropic(input: 10, output: 50)),
        ("claude-mythos-5", .anthropic(input: 10, output: 50)),
        ("claude-opus-5", .anthropic(input: 5, output: 25)),
        ("claude-opus-4", .anthropic(input: 5, output: 25)),
        ("claude-opus", .anthropic(input: 15, output: 75)),
        ("claude-sonnet-5", .anthropic(input: 3, output: 15)),
        ("claude-sonnet-4", .anthropic(input: 3, output: 15)),
        ("claude-sonnet", .anthropic(input: 3, output: 15)),
        ("claude-haiku-4", .anthropic(input: 1, output: 5)),
        ("claude-haiku", .anthropic(input: 0.8, output: 4)),
    ]

    /// OpenAI's published per-million rates for the models Codex runs.
    private static let openAIRates: [(prefix: String, rate: Rate)] = [
        ("gpt-5.6", .openAI(input: 1.25, output: 10)),
        ("gpt-5.5", .openAI(input: 1.25, output: 10)),
        ("gpt-5.4", .openAI(input: 1.25, output: 10)),
        ("gpt-5.3", .openAI(input: 1.25, output: 10)),
        ("gpt-5", .openAI(input: 1.25, output: 10)),
    ]

    /// The rate for a model, or `nil` for models we have no pricing for —
    /// including the `<synthetic>` entries Claude Code writes for local turns,
    /// and any model released after this table was last updated.
    public static func rate(forModel model: String) -> Rate? {
        rates.first { model.hasPrefix($0.prefix) }?.rate
    }

    /// Estimated API-equivalent cost of one turn, in USD.
    ///
    /// `nil` — not zero — when the model has no known rate.
    ///
    /// The difference matters. Silently costing an unpriced model at zero makes
    /// a total that is quietly too low look complete, and the moment a provider
    /// ships a model this table has not caught up with, every figure in the app
    /// starts under-reporting with no sign that it is doing so. `nil` lets the
    /// UI say "and some tokens I can't price", which is the truth.
    public static func cost(of event: UsageEvent) -> Double? {
        guard let rate = rate(forModel: event.model) else { return nil }

        let millions = 1_000_000.0
        return
            (Double(event.inputTokens) * rate.input
            + Double(event.outputTokens) * rate.output
            + Double(event.cacheWrite5mTokens) * rate.cacheWrite5m
            + Double(event.cacheWrite1hTokens) * rate.cacheWrite1h
            + Double(event.cacheReadTokens) * rate.cacheRead) / millions
    }
}
