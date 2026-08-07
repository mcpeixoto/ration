import Foundation
import Testing

@testable import RationKit

// MARK: - Sample lines
//
// Shapes copied from real rollout files, trimmed to the fields the parser looks
// at plus enough of the surrounding prose to prove it is ignored.

private func contextLine(
    model: String = "gpt-5.6-sol",
    cwd: String = "/Users/me/Documents/Coding/Montra"
) -> String {
    """
    {"timestamp":"2026-08-07T10:00:00.000Z","type":"turn_context","payload":\
    {"turn_id":"abc","cwd":"\(cwd)","current_date":"2026-08-07",\
    "approval_policy":"never","model":"\(model)","effort":"high"}}
    """
}

/// A `token_count` record, expressed the way Codex writes it: as the session's
/// **running totals**.
///
/// `last_token_usage` is deliberately filled with nonsense. It is the field
/// that looks like the obvious one to read, and reading it is wrong — these
/// fixtures fail loudly if anyone switches back to it.
private func countsLine(
    input: Int = 16859,
    cached: Int = 11008,
    cacheWrite: Int = 0,
    output: Int = 350,
    reasoning: Int = 117,
    timestamp: String = "2026-08-07T10:00:05.000Z",
    rateLimits: String = ""
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count",\
    "info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
    "cache_write_input_tokens":\(cacheWrite),"output_tokens":\(output),\
    "reasoning_output_tokens":\(reasoning),"total_tokens":\(input + output)},\
    "last_token_usage":{"input_tokens":999999,"cached_input_tokens":999999,\
    "cache_write_input_tokens":999999,"output_tokens":999999,\
    "reasoning_output_tokens":999999,"total_tokens":999999},\
    "model_context_window":258400}\(rateLimits)}}
    """
}

/// The first line of every rollout: the instruction blob the parser must never
/// decode.
private let metaLine = """
    {"timestamp":"2026-08-07T09:59:00.000Z","type":"session_meta","payload":\
    {"session_id":"019fd95b-c3b6-7ea3-97cf-64c06c87f1ec","cwd":"/Users/me/secret-project",\
    "originator":"codex-tui","cli_version":"0.146.1",\
    "base_instructions":"You are Codex. TOP SECRET INSTRUCTIONS."}}
    """

private let proseLine = """
    {"timestamp":"2026-08-07T10:00:02.000Z","type":"response_item","payload":\
    {"type":"message","role":"assistant","content":[{"type":"output_text",\
    "text":"Here is my SECRET REPLY about last_token_usage and turn_context."}]}}
    """

private func parse(_ lines: [String], carrying: inout FileCheckpoint) -> [UsageEvent] {
    let data = Data((lines.joined(separator: "\n") + "\n").utf8)
    let url = URL(
        fileURLWithPath:
            "/tmp/sessions/2026/08/07/rollout-2026-08-07T00-14-57-019fd95b-c3b6-7ea3-97cf-64c06c87f1ec.jsonl"
    )
    return CodexRolloutFormat().parse(data, from: url, carrying: &carrying).events
}

private func parse(_ lines: [String]) -> [UsageEvent] {
    var checkpoint = FileCheckpoint(offset: 0)
    return parse(lines, carrying: &checkpoint)
}

// MARK: - Parsing

@Suite("Codex rollout parsing")
struct CodexRolloutParsingTests {

    @Test("reads a turn's counts and attributes them to the preceding context")
    func basicEvent() throws {
        let events = parse([metaLine, contextLine(), proseLine, countsLine()])
        let event = try #require(events.first)

        #expect(events.count == 1)
        #expect(event.model == "gpt-5.6-sol")
        #expect(event.project == "Montra")
        #expect(event.sessionID == "019fd95b-c3b6-7ea3-97cf-64c06c87f1ec")
    }

    /// The single most important line in this file. Codex counts cached reads
    /// inside `input_tokens`; Claude Code reports them alongside. Getting this
    /// backwards inflates every Codex figure by the cache hit rate — which on a
    /// real corpus is over 95% of all input.
    @Test("subtracts cached reads from input, because Codex counts them inside it")
    func cachedTokensAreNotDoubleCounted() throws {
        let event = try #require(parse([contextLine(), countsLine(input: 16859, cached: 11008)]).first)

        #expect(event.inputTokens == 5851)
        #expect(event.cacheReadTokens == 11008)
        // Billable input plus the cache read must reconstruct what Codex wrote.
        #expect(event.inputTokens + event.cacheReadTokens == 16859)
    }

    @Test("does not add reasoning tokens to output, since they are part of it")
    func reasoningIsNotAddedTwice() throws {
        let event = try #require(parse([contextLine(), countsLine(output: 350, reasoning: 117)]).first)
        #expect(event.outputTokens == 350)
    }

    @Test("maps cache writes to the only tier OpenAI has")
    func singleCacheTier() throws {
        let event = try #require(parse([contextLine(), countsLine(cacheWrite: 4096)]).first)
        #expect(event.cacheWrite5mTokens == 4096)
        #expect(event.cacheWrite1hTokens == 0)
    }

    @Test("differences the running total rather than trusting the per-turn field")
    func differencesTheCumulative() throws {
        // Every fixture's `last_token_usage` is 999999. Reading it would be
        // unmistakable.
        let event = try #require(parse([contextLine(), countsLine()]).first)
        #expect(event.outputTokens == 350)
        #expect(event.totalTokens < 20_000)
    }

    @Test("events sum back to the totals Codex reports")
    func eventsSumToTotal() {
        let events = parse([
            contextLine(),
            countsLine(input: 100, cached: 20, output: 10),
            countsLine(input: 350, cached: 70, output: 40),
            countsLine(input: 750, cached: 160, output: 45),
        ])

        // The last record's totals, reconstructed from the individual events.
        #expect(events.map { $0.inputTokens + $0.cacheReadTokens }.reduce(0, +) == 750)
        #expect(events.map(\.cacheReadTokens).reduce(0, +) == 160)
        #expect(events.map(\.outputTokens).reduce(0, +) == 45)
    }

    /// Codex emitted every `token_count` twice for part of its history — two
    /// records a second apart with an identical payload. 17 of the 44 rollouts
    /// on the machine this was written against are affected, and summing the
    /// per-turn field inflated one project by 80%.
    @Test("counts a repeated record once")
    func duplicateRecordsAreIgnored() {
        let events = parse([
            contextLine(),
            countsLine(input: 100, cached: 20, output: 10, timestamp: "2026-08-07T10:00:05.000Z"),
            countsLine(input: 100, cached: 20, output: 10, timestamp: "2026-08-07T10:00:06.000Z"),
            countsLine(input: 350, cached: 70, output: 40, timestamp: "2026-08-07T10:00:20.000Z"),
            countsLine(input: 350, cached: 70, output: 40, timestamp: "2026-08-07T10:00:21.000Z"),
        ])

        #expect(events.count == 2)
        #expect(events.map { $0.inputTokens + $0.cacheReadTokens }.reduce(0, +) == 350)
        #expect(events.map(\.outputTokens).reduce(0, +) == 40)
    }

    @Test("treats a total that went backwards as a fresh start, not a negative turn")
    func compactionResetsTheBaseline() {
        let events = parse([
            contextLine(),
            countsLine(input: 900, cached: 100, output: 50),
            // Compaction: Codex starts the totals over.
            countsLine(input: 120, cached: 20, output: 5),
        ])

        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.inputTokens >= 0 && $0.outputTokens >= 0 })
        #expect(events.map { $0.inputTokens + $0.cacheReadTokens }.reduce(0, +) == 1020)
    }

    @Test("skips book-keeping turns that consumed nothing")
    func emptyTurnsAreSkipped() {
        #expect(parse([contextLine(), countsLine(input: 0, cached: 0, output: 0)]).isEmpty)
    }

    @Test("follows the model when it changes mid-session")
    func modelSwitch() {
        let events = parse([
            contextLine(model: "gpt-5.5"),
            countsLine(input: 100, cached: 20, output: 10),
            contextLine(model: "gpt-5.6-sol"),
            countsLine(input: 300, cached: 60, output: 25),
        ])

        #expect(events.map(\.model) == ["gpt-5.5", "gpt-5.6-sol"])
    }

    @Test("carries the model and the running total across an incremental read")
    func contextSurvivesResume() throws {
        // First read sees the context line; the second sees only counts, which
        // is exactly what happens when Codex appends while Ration is running.
        var checkpoint = FileCheckpoint(offset: 0)
        _ = parse(
            [contextLine(model: "gpt-5.5"), countsLine(input: 100, cached: 20, output: 10)],
            carrying: &checkpoint)

        let resumed = try #require(
            parse([countsLine(input: 350, cached: 70, output: 40)], carrying: &checkpoint).first)

        #expect(resumed.model == "gpt-5.5")
        #expect(resumed.project == "Montra")
        // Differenced against the total carried over, not restarted from zero —
        // otherwise a resumed read re-counts the whole session.
        #expect(resumed.inputTokens + resumed.cacheReadTokens == 250)
        #expect(resumed.outputTokens == 30)
    }

    @Test("says so rather than guessing when no context has been seen yet")
    func unknownWithoutContext() throws {
        let event = try #require(parse([countsLine()]).first)
        #expect(event.model == "unknown")
        #expect(UsageEvent.displayName(forModel: event.model) == "Unknown")
    }

    @Test("leaves a partial trailing line unconsumed")
    func partialLine() {
        let complete = contextLine() + "\n" + countsLine() + "\n"
        let data = Data((complete + #"{"timestamp":"2026-08-07T10:01:00.00"#).utf8)
        var checkpoint = FileCheckpoint(offset: 0)
        let url = URL(fileURLWithPath: "/tmp/rollout-a-b-c-d-e.jsonl")

        let (events, consumed) = CodexRolloutFormat().parse(
            data, from: url, carrying: &checkpoint)

        #expect(events.count == 1)
        #expect(consumed == complete.utf8.count)
    }

    @Test("only treats rollout files as transcripts")
    func fileSelection() throws {
        let home = try makeCodexHome()
        defer { try? FileManager.default.removeItem(at: home) }

        for name in ["rollout-2026-08-07T00-00-00-abc.jsonl", "history.jsonl", "notes.txt"] {
            try Data("{}\n".utf8).write(to: home.appending(path: "sessions/\(name)"))
        }

        let found = CodexRolloutFormat().transcriptFiles(under: home.appending(path: "sessions"))
        #expect(found.map(\.lastPathComponent) == ["rollout-2026-08-07T00-00-00-abc.jsonl"])
    }

    /// Codex archives sessions by moving them to a sibling directory. Skipping
    /// it dropped 39.4M tokens across four sessions on the machine this was
    /// written against — an under-count, which is the worse way for a usage
    /// meter to be wrong.
    @Test("includes archived sessions alongside live ones")
    func archivedSessionsAreIncluded() throws {
        let home = try makeCodexHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try Data("{}\n".utf8).write(
            to: home.appending(path: "sessions/rollout-2026-08-07T00-00-00-live.jsonl"))
        try Data("{}\n".utf8).write(
            to: home.appending(path: "archived_sessions/rollout-2026-02-01T00-00-00-old.jsonl"))

        let found = CodexRolloutFormat()
            .transcriptFiles(under: home.appending(path: "sessions"))
            .map(\.lastPathComponent)
            .sorted()

        #expect(
            found == [
                "rollout-2026-02-01T00-00-00-old.jsonl",
                "rollout-2026-08-07T00-00-00-live.jsonl",
            ])
    }

    @Test("does not look for an archive beside an unrelated directory")
    func archiveLookupIsScopedToSessions() throws {
        let home = try makeCodexHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try Data("{}\n".utf8).write(
            to: home.appending(path: "archived_sessions/rollout-2026-02-01T00-00-00-old.jsonl"))

        // A root that is not the sessions directory gets no sibling treatment.
        #expect(CodexRolloutFormat().transcriptFiles(under: home).count == 1)
    }

    /// A stale checkpoint cannot be corrected in place — cost and token totals
    /// are computed as events are parsed and only the sums are kept — so it must
    /// be discarded rather than trusted.
    @Test("discards a checkpoint written by an older parser or price list")
    @MainActor
    func staleCheckpointIsRebuilt() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ration-ckpt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        // Shaped like a pre-versioning checkpoint: no `version` key at all.
        let legacy = """
            {"history":{"days":{}},"files":{"/x.jsonl":{"offset":999}},\
            "savedAt":\(Date().timeIntervalSinceReferenceDate)}
            """
        try Data(legacy.utf8).write(to: support.appending(path: "history-codex.json"))

        let store = TranscriptStore(
            provider: .codex, format: CodexRolloutFormat(),
            root: URL(fileURLWithPath: "/nonexistent"), supportDirectory: support)
        store.loadCheckpoint()

        // Nothing adopted: a fresh store, ready to scan from the beginning.
        #expect(store.history.isEmpty)
        #expect(store.lastScan == nil)
    }

    private func makeCodexHome() throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-\(UUID().uuidString)")
        for sub in ["sessions", "archived_sessions"] {
            try FileManager.default.createDirectory(
                at: home.appending(path: sub), withIntermediateDirectories: true)
        }
        return home
    }
}

// MARK: - Privacy

@Suite("Codex rollout parsing privacy")
struct CodexParserPrivacyTests {

    /// Rollouts embed the full conversation. Ration extracts counters from two
    /// line types and never decodes the rest — including the first line, which
    /// carries the instruction blob.
    @Test("no prompt, reply, or instruction text survives parsing")
    func noContentIsRetained() {
        let events = parse([metaLine, contextLine(), proseLine, countsLine()])
        let dumped = events.map { String(describing: $0) }.joined()

        for secret in ["TOP SECRET INSTRUCTIONS", "SECRET REPLY", "secret-project"] {
            #expect(!dumped.contains(secret), "parsed output leaked: \(secret)")
        }
    }

    @Test("a usage event from Codex exposes the same narrow surface as one from Claude")
    func surfaceIsIdentical() throws {
        let event = try #require(parse([contextLine(), countsLine()]).first)

        let allowed: Set<String> = [
            "timestamp", "model", "project", "sessionID",
            "inputTokens", "outputTokens", "cacheWrite5mTokens", "cacheWrite1hTokens",
            "cacheReadTokens", "webSearches",
        ]
        #expect(Set(Mirror(reflecting: event).children.compactMap(\.label)) == allowed)
    }

    /// The session id comes from the file name so that the one line carrying the
    /// instruction blob never has to be handed to the JSON decoder.
    @Test("identifies the session without decoding the metadata line")
    func sessionIDFromFileName() {
        let url = URL(
            fileURLWithPath:
                "/x/rollout-2026-08-07T00-14-57-019fd95b-c3b6-7ea3-97cf-64c06c87f1ec.jsonl")
        #expect(CodexRolloutFormat.sessionID(from: url) == "019fd95b-c3b6-7ea3-97cf-64c06c87f1ec")
    }

    @Test("falls back to the whole name when it is not a rollout name")
    func sessionIDFallback() {
        #expect(CodexRolloutFormat.sessionID(from: URL(fileURLWithPath: "/x/odd.jsonl")) == "odd")
    }
}

// MARK: - Display names

@Suite("OpenAI model display names")
struct OpenAIModelNameTests {

    @Test("renders OpenAI identifiers as their marketed names")
    func names() {
        #expect(UsageEvent.displayName(forModel: "gpt-5.5") == "GPT-5.5")
        #expect(UsageEvent.displayName(forModel: "gpt-5.6-sol") == "GPT-5.6 Sol")
        #expect(UsageEvent.displayName(forModel: "gpt-5.3-codex") == "GPT-5.3 Codex")
    }

    @Test("still renders Claude identifiers the old way")
    func claudeUnaffected() {
        #expect(UsageEvent.displayName(forModel: "claude-opus-4-8") == "Opus 4.8")
    }
}
