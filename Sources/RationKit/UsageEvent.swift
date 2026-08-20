import Foundation

/// One assistant turn, reduced to the numbers Ration cares about.
///
/// Deliberately narrow: this is derived from Claude Code's transcripts, which
/// also contain your prompts, your completions, and your file contents. None
/// of that is read into this type — see `TranscriptParser`.
public struct UsageEvent: Sendable, Equatable {

    public let timestamp: Date
    public let model: String
    /// The project directory the turn happened in, as a display name.
    public let project: String
    public let sessionID: String

    public let inputTokens: Int
    public let outputTokens: Int
    /// Cache writes are split by TTL because they are priced differently:
    /// the 1-hour cache costs more to fill than the 5-minute one.
    public let cacheWrite5mTokens: Int
    public let cacheWrite1hTokens: Int
    public let cacheReadTokens: Int
    public let webSearches: Int

    public init(
        timestamp: Date,
        model: String,
        project: String,
        sessionID: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWrite5mTokens: Int = 0,
        cacheWrite1hTokens: Int = 0,
        cacheReadTokens: Int,
        webSearches: Int = 0
    ) {
        self.timestamp = timestamp
        self.model = model
        self.project = project
        self.sessionID = sessionID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.webSearches = webSearches
    }

    /// All cache writes, regardless of TTL.
    public var cacheCreationTokens: Int {
        cacheWrite5mTokens + cacheWrite1hTokens
    }

    /// Every token that passed through, cached or not.
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Tokens the model actually had to think about, ignoring cache reads.
    ///
    /// This is the more honest measure of "work done": a cache read is
    /// context that was already paid for.
    public var billableTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens
    }
}

// MARK: - Model naming

extension UsageEvent {
    /// `claude-opus-4-8` → `Opus 4.8`, for display.
    public var modelDisplayName: String {
        Self.displayName(forModel: model)
    }

    public static func displayName(forModel model: String) -> String {
        // Synthetic entries appear in transcripts for local, non-API turns.
        guard !model.hasPrefix("<") else { return "Other" }
        // Codex attributes a turn only once its context line has been read; an
        // incremental read that started mid-turn may not have seen one yet.
        guard model != "unknown" else { return "Unknown" }

        // Cursor prefixes its own routing id: `cursor-grok-4.6-high-fast`.
        if model.hasPrefix("cursor-") {
            return displayName(forModel: String(model.dropFirst("cursor-".count)))
        }

        // OpenAI identifiers are already the marketed name: the dashes separate
        // a version from a codename, not a family from a dotted version, so the
        // rule below would render `gpt-5.6-sol` as "Gpt 5.6.sol".
        if model.hasPrefix("gpt-") {
            var parts = model.dropFirst("gpt-".count).split(separator: "-").map(String.init)
            guard !parts.isEmpty else { return model }
            let version = parts.removeFirst()
            let codename =
                parts
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return codename.isEmpty ? "GPT-\(version)" : "GPT-\(version) \(codename)"
        }

        if model.hasPrefix("grok-") {
            var parts = model.dropFirst("grok-".count).split(separator: "-").map(String.init)
            guard !parts.isEmpty else { return model }
            let version = parts.removeFirst()
            let rest =
                parts
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return rest.isEmpty ? "Grok \(version)" : "Grok \(version) \(rest)"
        }

        var name = model
        for prefix in ["claude-", "anthropic.", "us.anthropic."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }

        // Drop a trailing date stamp: `haiku-4-5-20251001` → `haiku-4-5`.
        var parts = name.split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, Int(last) != nil {
            parts.removeLast()
        }
        // Drop a trailing API version suffix: `-v1:0`.
        parts = parts.filter { !$0.hasPrefix("v1:") }

        guard let family = parts.first else { return model }
        let version = parts.dropFirst().joined(separator: ".")

        let capitalised = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? capitalised : "\(capitalised) \(version)"
    }
}
