import Foundation
import Testing

@testable import RationKit

// MARK: - Fixtures

/// One assistant line, shaped exactly like Claude Code writes them.
private func transcriptLine(
    timestamp: String = "2026-08-06T12:00:00.000Z",
    model: String = "claude-opus-5",
    cwd: String = "/Users/me/Documents/Coding/Montra",
    session: String = "sess-1",
    input: Int = 10,
    output: Int = 200,
    cacheWrite5m: Int = 0,
    cacheWrite1h: Int = 1000,
    cacheRead: Int = 5000,
    webSearches: Int = 0,
    type: String = "assistant"
) -> String {
    """
    {"type":"\(type)","cwd":"\(cwd)","sessionId":"\(session)",\
    "timestamp":"\(timestamp)","message":{"model":"\(model)","usage":{\
    "input_tokens":\(input),"output_tokens":\(output),\
    "cache_creation_input_tokens":\(cacheWrite5m + cacheWrite1h),\
    "cache_read_input_tokens":\(cacheRead),\
    "server_tool_use":{"web_search_requests":\(webSearches)},\
    "cache_creation":{"ephemeral_5m_input_tokens":\(cacheWrite5m),\
    "ephemeral_1h_input_tokens":\(cacheWrite1h)}}}}
    """
}

/// A user line — carries no usage and must be ignored.
private let userLine = """
    {"type":"user","cwd":"/Users/me/x","sessionId":"sess-1",\
    "timestamp":"2026-08-06T12:00:00.000Z",\
    "message":{"role":"user","content":"my secret prompt text"}}
    """

private func parse(_ lines: [String], trailingNewline: Bool = true) -> (
    events: [UsageEvent], consumed: Int
) {
    var text = lines.joined(separator: "\n")
    if trailingNewline { text += "\n" }
    return TranscriptParser.parse(
        Data(text.utf8), project: "fallback", fallbackSessionID: "fallback-session")
}

// MARK: - Parser

@Suite("Transcript parsing")
struct TranscriptParserTests {

    @Test("extracts a usage event from an assistant line")
    func parsesAssistantLine() {
        let (events, _) = parse([transcriptLine()])
        let event = events.first

        #expect(events.count == 1)
        #expect(event?.model == "claude-opus-5")
        #expect(event?.inputTokens == 10)
        #expect(event?.outputTokens == 200)
        #expect(event?.cacheWrite1hTokens == 1000)
        #expect(event?.cacheReadTokens == 5000)
        #expect(event?.project == "Montra")
        #expect(event?.sessionID == "sess-1")
    }

    @Test("ignores user lines, which carry no usage")
    func ignoresUserLines() {
        let (events, _) = parse([userLine])
        #expect(events.isEmpty)
    }

    @Test("splits cache writes by TTL, since they are priced differently")
    func splitsCacheWrites() {
        let (events, _) = parse([transcriptLine(cacheWrite5m: 300, cacheWrite1h: 700)])
        #expect(events.first?.cacheWrite5mTokens == 300)
        #expect(events.first?.cacheWrite1hTokens == 700)
        #expect(events.first?.cacheCreationTokens == 1000)
    }

    @Test("falls back to the cache total when no TTL split is present")
    func cacheWriteFallback() {
        let line = """
            {"type":"assistant","timestamp":"2026-08-06T12:00:00Z","cwd":"/x/Proj",\
            "sessionId":"s","message":{"model":"claude-opus-5","usage":{\
            "input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":500,\
            "cache_read_input_tokens":0}}}
            """
        let (events, _) = parse([line])
        #expect(events.first?.cacheCreationTokens == 500)
    }

    @Test("counts web searches")
    func countsWebSearches() {
        let (events, _) = parse([transcriptLine(webSearches: 3)])
        #expect(events.first?.webSearches == 3)
    }

    @Test("parses many lines in one pass")
    func parsesMultipleLines() {
        let (events, _) = parse([
            transcriptLine(session: "a"), userLine, transcriptLine(session: "b"),
        ])
        #expect(events.count == 2)
        #expect(Set(events.map(\.sessionID)) == ["a", "b"])
    }

    @Test("stops at the last complete line, so a half-written line is not lost")
    func handlesPartialTrailingLine() {
        let complete = transcriptLine()
        let text = complete + "\n" + #"{"type":"assistant","cwd":"/x","mess"#
        let (events, consumed) = TranscriptParser.parse(
            Data(text.utf8), project: "p", fallbackSessionID: "s")

        #expect(events.count == 1)
        // Everything up to and including the newline, and nothing more.
        #expect(consumed == complete.utf8.count + 1)
    }

    @Test("skips malformed lines without losing the rest")
    func skipsMalformedLines() {
        let text = "not json at all\n" + transcriptLine() + "\n"
        let (events, _) = TranscriptParser.parse(
            Data(text.utf8), project: "p", fallbackSessionID: "s")
        #expect(events.count == 1)
    }

    @Test("prefers cwd over the mangled directory name for the project")
    func projectFromCwd() {
        let (events, _) = parse([transcriptLine(cwd: "/Users/me/Documents/Coding/Rifas")])
        #expect(events.first?.project == "Rifas")
    }

    @Test("derives a project name from Claude Code's mangled directory names")
    func projectFromDirectory() {
        #expect(
            TranscriptParser.projectName(fromDirectory: "-Users-me-Documents-Coding-Montra")
                == "Montra")
    }

    @Test("handles a trailing slash on the cwd")
    func projectPathTrailingSlash() {
        #expect(TranscriptParser.projectName(fromPath: "/Users/me/Coding/Montra/") == "Montra")
    }
}

// MARK: - Privacy
//
// Transcripts contain prompts, completions, and file contents. The parser must
// take the numbers and leave everything else behind.

@Suite("Transcript parsing privacy")
struct TranscriptParserPrivacyTests {

    @Test("message content is never read into a usage event")
    func doesNotReadMessageContent() {
        let secret = "SECRET-PROMPT-CONTENT-12345"
        let line = """
            {"type":"assistant","timestamp":"2026-08-06T12:00:00Z","cwd":"/x/P",\
            "sessionId":"s","message":{"model":"claude-opus-5",\
            "content":[{"type":"text","text":"\(secret)"}],\
            "usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":0}}}
            """
        let (events, _) = parse([line])
        let event = try? #require(events.first)

        for child in Mirror(reflecting: event as Any).children {
            #expect(!String(describing: child.value).contains(secret))
        }
    }

    @Test("a usage event exposes only counts and identifiers")
    func eventSurfaceIsNarrow() {
        let (events, _) = parse([transcriptLine()])
        guard let event = events.first else { return }

        let allowed: Set<String> = [
            "timestamp", "model", "project", "sessionID",
            "inputTokens", "outputTokens", "cacheWrite5mTokens", "cacheWrite1hTokens",
            "cacheReadTokens", "webSearches",
        ]
        let actual = Set(Mirror(reflecting: event).children.compactMap(\.label))
        #expect(actual == allowed, "UsageEvent gained a field: \(actual.subtracting(allowed))")
    }
}

// MARK: - Model naming

@Suite("Model display names")
struct ModelNameTests {

    @Test("turns model IDs into readable names")
    func readableNames() {
        #expect(UsageEvent.displayName(forModel: "claude-opus-5") == "Opus 5")
        #expect(UsageEvent.displayName(forModel: "claude-sonnet-5") == "Sonnet 5")
        #expect(UsageEvent.displayName(forModel: "claude-opus-4-8") == "Opus 4.8")
        #expect(UsageEvent.displayName(forModel: "claude-fable-5") == "Fable 5")
    }

    @Test("drops a trailing date stamp")
    func dropsDateStamp() {
        #expect(UsageEvent.displayName(forModel: "claude-haiku-4-5-20251001") == "Haiku 4.5")
    }

    @Test("names synthetic entries rather than showing the raw marker")
    func syntheticEntries() {
        #expect(UsageEvent.displayName(forModel: "<synthetic>") == "Other")
    }

    @Test("passes through an unrecognised id rather than mangling it")
    func unknownModel() {
        #expect(!UsageEvent.displayName(forModel: "some-future-model").isEmpty)
    }
}

// MARK: - Pricing

@Suite("Pricing")
struct PricingTests {

    @Test("prices the well-known models")
    func knownRates() {
        #expect(Pricing.rate(forModel: "claude-opus-5")?.input == 5)
        #expect(Pricing.rate(forModel: "claude-opus-5")?.output == 25)
        #expect(Pricing.rate(forModel: "claude-sonnet-5")?.output == 15)
        #expect(Pricing.rate(forModel: "claude-fable-5")?.input == 10)
        #expect(Pricing.rate(forModel: "claude-haiku-4-5-20251001")?.input == 1)
    }

    @Test("returns no rate for models it does not know")
    func unknownModelHasNoRate() {
        #expect(Pricing.rate(forModel: "<synthetic>") == nil)
        #expect(Pricing.rate(forModel: "some-future-model") == nil)
    }

    @Test("cache reads are a tenth of input; writes cost more than input")
    func cacheMultipliers() throws {
        let rate = try #require(Pricing.rate(forModel: "claude-opus-5"))
        #expect(rate.cacheRead == rate.input * 0.1)
        #expect(rate.cacheWrite5m == rate.input * 1.25)
        #expect(rate.cacheWrite1h == rate.input * 2.0)
        #expect(rate.cacheWrite1h > rate.cacheWrite5m)
    }

    @Test("computes a turn's cost from its token mix")
    func costArithmetic() {
        // 1M input + 1M output on Opus 5 = $5 + $25.
        let event = UsageEvent(
            timestamp: Date(), model: "claude-opus-5", project: "p", sessionID: "s",
            inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 0)
        #expect(abs(Pricing.cost(of: event) - 30) < 0.0001)
    }

    @Test("cache reads are far cheaper than fresh input")
    func cacheReadsAreCheap() {
        let cached = UsageEvent(
            timestamp: Date(), model: "claude-opus-5", project: "p", sessionID: "s",
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 1_000_000)
        let fresh = UsageEvent(
            timestamp: Date(), model: "claude-opus-5", project: "p", sessionID: "s",
            inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0)

        #expect(abs(Pricing.cost(of: cached) - 0.5) < 0.0001)
        #expect(Pricing.cost(of: fresh) > Pricing.cost(of: cached) * 9)
    }

    @Test("an unpriced model contributes nothing rather than a guess")
    func unknownModelCostsNothing() {
        let event = UsageEvent(
            timestamp: Date(), model: "<synthetic>", project: "p", sessionID: "s",
            inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 0)
        #expect(Pricing.cost(of: event) == 0)
    }

    @Test("every rate is positive and output costs more than input")
    func ratesAreSane() {
        for (_, rate) in Pricing.rates {
            #expect(rate.input > 0)
            #expect(rate.output > rate.input)
        }
    }

    @Test("more specific model prefixes win over generic ones")
    func prefixOrdering() {
        // `claude-opus-5` must not resolve via the generic `claude-opus` row.
        #expect(Pricing.rate(forModel: "claude-opus-5")?.input == 5)
        #expect(Pricing.rate(forModel: "claude-opus-3")?.input == 15)
    }
}

// MARK: - Aggregation

@Suite("Usage history")
struct UsageHistoryTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func event(
        day: Int, hour: Int = 12, model: String = "claude-opus-5",
        project: String = "Montra", session: String = "s1", output: Int = 1000
    ) -> UsageEvent {
        UsageEvent(
            timestamp: date(day, hour: hour), model: model, project: project,
            sessionID: session, inputTokens: 100, outputTokens: output, cacheReadTokens: 500)
    }

    @Test("groups events into days")
    func groupsByDay() {
        var history = UsageHistory()
        history.add(
            [event(day: 1, hour: 9), event(day: 1, hour: 22), event(day: 2)],
            calendar: calendar)

        #expect(history.days.count == 2)
        #expect(history.day(date(1), calendar: calendar)?.messages == 2)
    }

    @Test("sums tokens by model")
    func tokensByModel() {
        var history = UsageHistory()
        history.add(
            [
                event(day: 1, model: "claude-opus-5"),
                event(day: 1, model: "claude-opus-5"),
                event(day: 1, model: "claude-sonnet-5"),
            ], calendar: calendar)

        let day = history.day(date(1), calendar: calendar)
        #expect(day?.tokensByModel["claude-opus-5"] == 2200)
        #expect(day?.tokensByModel["claude-sonnet-5"] == 1100)
    }

    @Test("counts distinct sessions rather than messages")
    func countsSessions() {
        var history = UsageHistory()
        history.add(
            [
                event(day: 1, session: "a"), event(day: 1, session: "a"),
                event(day: 1, session: "b"),
            ], calendar: calendar)

        #expect(history.day(date(1), calendar: calendar)?.sessionCount == 2)
        #expect(history.day(date(1), calendar: calendar)?.messages == 3)
    }

    @Test("cache reads are excluded from billable tokens")
    func billableExcludesCacheReads() {
        var history = UsageHistory()
        history.add([event(day: 1)], calendar: calendar)
        let day = history.day(date(1), calendar: calendar)

        #expect(day?.billableTokens == 1100)  // 100 input + 1000 output
        #expect(day?.cacheReadTokens == 500)
        #expect(day?.totalTokens == 1600)
    }

    @Test("a window fills quiet days so the calendar has no holes")
    func windowFillsGaps() {
        var history = UsageHistory()
        history.add([event(day: 1), event(day: 5)], calendar: calendar)

        let window = history.window(days: 7, endingOn: date(7), calendar: calendar)
        #expect(window.count == 7)
        #expect(window.filter { $0.billableTokens > 0 }.count == 2)
    }

    @Test("a window is ordered oldest first")
    func windowOrdering() {
        var history = UsageHistory()
        history.add([event(day: 1), event(day: 3)], calendar: calendar)

        let window = history.window(days: 5, endingOn: date(5), calendar: calendar)
        #expect(window.map(\.date) == window.map(\.date).sorted())
    }

    @Test("totals roll up across a window")
    func totals() {
        var history = UsageHistory()
        history.add(
            [
                event(day: 1, project: "Montra"),
                event(day: 2, project: "Rifas"),
                event(day: 2, project: "Montra"),
            ], calendar: calendar)

        let totals = history.total(
            over: history.window(days: 7, endingOn: date(7), calendar: calendar))

        #expect(totals.messages == 3)
        #expect(totals.tokens == 3300)
        #expect(totals.activeDays == 2)
        #expect(totals.tokensByProject["Montra"] == 2200)
        #expect(totals.rankedProjects.first?.name == "Montra")
    }

    @Test("ranked models are ordered by usage and named readably")
    func rankedModels() {
        var history = UsageHistory()
        history.add(
            [
                event(day: 1, model: "claude-sonnet-5", output: 10),
                event(day: 1, model: "claude-opus-5", output: 5000),
            ], calendar: calendar)

        let totals = history.total(
            over: history.window(days: 2, endingOn: date(1), calendar: calendar))
        #expect(totals.rankedModels.first?.name == "Opus 5")
    }

    @Test("identifies the busiest day")
    func busiestDay() {
        var history = UsageHistory()
        history.add(
            [event(day: 1, output: 100), event(day: 2, output: 9000)], calendar: calendar)

        let totals = history.total(
            over: history.window(days: 7, endingOn: date(7), calendar: calendar))
        #expect(totals.busiestDay?.date == calendar.startOfDay(for: date(2)))
    }

    @Test("averages over active days, not calendar days")
    func averagePerActiveDay() {
        var history = UsageHistory()
        history.add([event(day: 1), event(day: 5)], calendar: calendar)

        let totals = history.total(
            over: history.window(days: 30, endingOn: date(7), calendar: calendar))
        #expect(totals.averageTokensPerActiveDay == 1100)
    }

    @Test("counts a run of consecutive active days")
    func streak() {
        var history = UsageHistory()
        history.add(
            [event(day: 3), event(day: 4), event(day: 5)], calendar: calendar)
        #expect(history.currentStreak(endingOn: date(5), calendar: calendar) == 3)
    }

    @Test("a gap breaks the streak")
    func streakBreaks() {
        var history = UsageHistory()
        history.add([event(day: 1), event(day: 4), event(day: 5)], calendar: calendar)
        #expect(history.currentStreak(endingOn: date(5), calendar: calendar) == 2)
    }

    @Test("an unused today does not break a streak that is still alive")
    func todayNotYetStartedKeepsStreak() {
        var history = UsageHistory()
        history.add([event(day: 4), event(day: 5)], calendar: calendar)
        // Nothing yet on the 6th — yesterday's streak still stands.
        #expect(history.currentStreak(endingOn: date(6), calendar: calendar) == 2)
    }

    @Test("two idle days end the streak")
    func streakEndsAfterTwoIdleDays() {
        var history = UsageHistory()
        history.add([event(day: 4)], calendar: calendar)
        #expect(history.currentStreak(endingOn: date(6), calendar: calendar) == 0)
    }

    @Test("history survives a round trip through disk")
    func codableRoundTrip() throws {
        var history = UsageHistory()
        history.add([event(day: 1), event(day: 2)], calendar: calendar)

        let data = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(UsageHistory.self, from: data)

        #expect(restored == history)
    }
}

// MARK: - Incremental reading

@Suite("Incremental transcript reading")
struct TranscriptStoreTests {

    private func makeFile(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "session.jsonl")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("reads a file from the start when there is no checkpoint")
    func firstRead() throws {
        let url = try makeFile(transcriptLine() + "\n")
        let result = TranscriptReader.readNewBytes(of: url, since: nil)

        #expect(result?.events.count == 1)
        #expect(result?.checkpoint.offset ?? 0 > 0)
    }

    @Test("reads only the appended bytes on a second visit")
    func incrementalRead() throws {
        let first = transcriptLine(session: "a") + "\n"
        let url = try makeFile(first)

        let initial = TranscriptReader.readNewBytes(of: url, since: nil)
        let checkpoint = try #require(initial?.checkpoint)

        // Append a second turn.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((transcriptLine(session: "b") + "\n").utf8))
        try handle.close()

        let second = TranscriptReader.readNewBytes(of: url, since: checkpoint)
        #expect(second?.events.count == 1, "should re-read only the new turn")
        #expect(second?.events.first?.sessionID == "b")
    }

    @Test("returns nothing when the file has not grown")
    func noNewBytes() throws {
        let url = try makeFile(transcriptLine() + "\n")
        let first = TranscriptReader.readNewBytes(of: url, since: nil)
        let checkpoint = try #require(first?.checkpoint)

        #expect(TranscriptReader.readNewBytes(of: url, since: checkpoint) == nil)
    }

    @Test("re-reads from the start when a file shrinks, since it was replaced")
    func handlesTruncation() throws {
        let url = try makeFile(transcriptLine() + "\n" + transcriptLine() + "\n")
        _ = TranscriptReader.readNewBytes(of: url, since: nil)

        // Replace with something shorter.
        try Data((transcriptLine(session: "new") + "\n").utf8).write(to: url)

        let stale = FileCheckpoint(offset: 100_000)
        let result = TranscriptReader.readNewBytes(of: url, since: stale)
        #expect(result?.events.first?.sessionID == "new")
    }

    @Test("does not consume a half-written trailing line")
    func partialLineIsNotConsumed() throws {
        let complete = transcriptLine() + "\n"
        let url = try makeFile(complete + #"{"type":"assist"#)

        let result = TranscriptReader.readNewBytes(of: url, since: nil)
        #expect(result?.events.count == 1)
        #expect(result?.checkpoint.offset == complete.utf8.count)
    }

    @Test("finds transcripts nested under project directories")
    func findsNestedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ration-root-\(UUID().uuidString)")
        let project = root.appending(path: "-Users-me-Coding-Montra")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appending(path: "a.jsonl"))
        try Data("{}".utf8).write(to: project.appending(path: "notes.txt"))

        let found = TranscriptReader.transcriptFiles(under: root)
        #expect(found.count == 1)
        #expect(found.first?.lastPathComponent == "a.jsonl")
    }

    @Test("a missing directory yields no files rather than throwing")
    func missingDirectory() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(TranscriptReader.transcriptFiles(under: missing).isEmpty)
    }
}
