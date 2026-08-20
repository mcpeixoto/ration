import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSqlite3
#endif
import Testing

@testable import RationKit

// MARK: - Sample lines
//
// Shapes copied from real agent-transcript files. The secret strings exist so
// the privacy tests fail loudly if a future parser starts retaining content.

private func assistantLine(
    timestamp: String = "2026-08-20T12:00:00.000Z",
    model: String = "grok-4.6",
    cwd: String = "/Users/me/Documents/Coding/Montra",
    session: String = "sess-1",
    input: Int = 100,
    output: Int = 40,
    cacheRead: Int = 80,
    cacheWrite: Int = 20,
    secret: String = "SECRET-CURSOR-REPLY"
) -> String {
    """
    {"role":"assistant","timestamp":"\(timestamp)","model":"\(model)",\
    "cwd":"\(cwd)","sessionId":"\(session)",\
    "message":{"content":[{"type":"text","text":"\(secret)"}],\
    "usage":{"input_tokens":\(input),"output_tokens":\(output),\
    "cache_read_input_tokens":\(cacheRead),\
    "cache_creation_input_tokens":\(cacheWrite)}}}
    """
}

private let userLine = """
    {"role":"user","timestamp":"2026-08-20T12:00:00.000Z",\
    "message":{"content":[{"type":"text","text":"SECRET-CURSOR-PROMPT"}]}}
    """

private func parse(
    _ lines: [String],
    url: URL = URL(
        fileURLWithPath:
            "/tmp/projects/Users-me-Coding-Montra/agent-transcripts/019fd95b-c3b6-7ea3-97cf-64c06c87f1ec/019fd95b-c3b6-7ea3-97cf-64c06c87f1ec.jsonl"
    )
) -> [UsageEvent] {
    let data = Data((lines.joined(separator: "\n") + "\n").utf8)
    var checkpoint = FileCheckpoint(offset: 0)
    return CursorTranscriptFormat().parse(data, from: url, carrying: &checkpoint).events
}

// MARK: - JSONL parsing

@Suite("Cursor agent-transcript parsing")
struct CursorTranscriptParsingTests {

    @Test("reads usage from an assistant line")
    func basicEvent() throws {
        let event = try #require(parse([userLine, assistantLine()]).first)

        #expect(event.model == "grok-4.6")
        #expect(event.project == "Montra")
        #expect(event.sessionID == "sess-1")
        #expect(event.inputTokens == 100)
        #expect(event.outputTokens == 40)
        #expect(event.cacheReadTokens == 80)
        #expect(event.cacheWrite5mTokens == 20)
    }

    @Test("ignores user lines")
    func ignoresUserLines() {
        #expect(parse([userLine]).isEmpty)
    }

    @Test("skips assistant lines that carry no usage")
    func skipsLinesWithoutUsage() {
        let prose = """
            {"role":"assistant","message":{"content":[{"type":"text",\
            "text":"SECRET-CURSOR-REPLY without any counts"}]}}
            """
        #expect(parse([prose]).isEmpty)
    }

    @Test("accepts camelCase tokenCount on older bubbles dumped to JSONL")
    func camelCaseTokenCount() throws {
        let line = """
            {"role":"assistant","timestamp":"2026-08-20T12:00:00Z",\
            "model":"composer-2","tokenCount":{"inputTokens":10,"outputTokens":5}}
            """
        let event = try #require(parse([line]).first)
        #expect(event.inputTokens == 10)
        #expect(event.outputTokens == 5)
        #expect(event.model == "composer-2")
    }

    @Test("takes the session id from the file name when the line omits it")
    func sessionIDFromFileName() throws {
        let line = """
            {"role":"assistant","timestamp":"2026-08-20T12:00:00Z",\
            "model":"grok-4.6","usage":{"input_tokens":1,"output_tokens":1}}
            """
        let event = try #require(parse([line]).first)
        #expect(event.sessionID == "019fd95b-c3b6-7ea3-97cf-64c06c87f1ec")
    }

    @Test("names the project from the workspace slug when cwd is missing")
    func projectFromDirectory() throws {
        let line = """
            {"role":"assistant","timestamp":"2026-08-20T12:00:00Z",\
            "model":"grok-4.6","usage":{"input_tokens":1,"output_tokens":1}}
            """
        let event = try #require(parse([line]).first)
        #expect(event.project == "Montra")
    }

    @Test("leaves a partial trailing line unconsumed")
    func partialLine() {
        let complete = assistantLine() + "\n"
        let data = Data((complete + #"{"role":"assistant","usage":{"input"#).utf8)
        var checkpoint = FileCheckpoint(offset: 0)
        let url = URL(fileURLWithPath: "/tmp/agent-transcripts/s/s.jsonl")
        let (_, consumed) = CursorTranscriptFormat().parse(
            data, from: url, carrying: &checkpoint)
        #expect(consumed == complete.utf8.count)
    }

    @Test("only treats files under agent-transcripts as transcripts")
    func fileSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cursor-projects-\(UUID().uuidString)")
        let transcripts = root.appending(path: "Users-me-Montra/agent-transcripts/sess")
        let noise = root.appending(path: "Users-me-Montra/canvases")
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: noise, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: transcripts.appending(path: "sess.jsonl"))
        try Data("{}\n".utf8).write(to: noise.appending(path: "notes.jsonl"))
        defer { try? FileManager.default.removeItem(at: root) }

        let found = CursorTranscriptFormat().transcriptFiles(under: root)
        #expect(found.map(\.lastPathComponent) == ["sess.jsonl"])
    }
}

// MARK: - Privacy

@Suite("Cursor transcript parsing privacy")
struct CursorParserPrivacyTests {

    @Test("no prompt or reply text survives parsing")
    func noContentIsRetained() {
        let events = parse([userLine, assistantLine()])
        let dumped = events.map { String(describing: $0) }.joined()
        for secret in ["SECRET-CURSOR-PROMPT", "SECRET-CURSOR-REPLY"] {
            #expect(!dumped.contains(secret), "parsed output leaked: \(secret)")
        }
    }

    @Test("a usage event from Cursor exposes the same narrow surface as Claude")
    func surfaceIsIdentical() throws {
        let event = try #require(parse([assistantLine()]).first)
        let allowed: Set<String> = [
            "timestamp", "model", "project", "sessionID",
            "inputTokens", "outputTokens", "cacheWrite5mTokens", "cacheWrite1hTokens",
            "cacheReadTokens", "webSearches",
        ]
        #expect(Set(Mirror(reflecting: event).children.compactMap(\.label)) == allowed)
    }

    @Test("sqlite bubble text is not copied into a usage event")
    func composerTextIsDropped() throws {
        let url = try makeComposerDB(
            composerID: "comp-secret",
            composerJSON: """
                {"composerId":"comp-secret","createdAt":1755691200000,\
                "name":"SECRET-COMPOSER-TITLE",\
                "modelConfig":{"modelName":"grok-4.6"},\
                "workspaceIdentifier":{"uri":{"fsPath":"/Users/me/Coding/Montra"}},\
                "fullConversationHeadersOnly":[{"bubbleId":"b1","type":2}]}
                """,
            bubbles: [
                (
                    "b1",
                    """
                    {"type":2,"createdAt":1755691201000,\
                    "text":"SECRET-BUBBLE-TEXT",\
                    "tokenCount":{"inputTokens":40,"outputTokens":10}}
                    """
                )
            ])
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(
            CursorComposerStore(databaseURL: url).snapshot(excludingSessionIDs: []))
        let dumped = snapshot.events.map { String(describing: $0) }.joined()
        for secret in ["SECRET-COMPOSER-TITLE", "SECRET-BUBBLE-TEXT"] {
            #expect(!dumped.contains(secret), "composer parse leaked: \(secret)")
        }
    }
}

// MARK: - Composer sqlite

@Suite("Cursor composer sqlite")
struct CursorComposerStoreTests {

    @Test("reads token counts off assistant bubbles")
    func bubbleTokens() throws {
        let url = try makeComposerDB(
            composerID: "comp-1",
            composerJSON: """
                {"composerId":"comp-1","createdAt":1755691200000,\
                "modelConfig":{"modelName":"grok-4.6"},\
                "workspaceIdentifier":{"uri":{"fsPath":"/Users/me/Coding/Montra"}},\
                "fullConversationHeadersOnly":[\
                  {"bubbleId":"u1","type":1},\
                  {"bubbleId":"a1","type":2}]}
                """,
            bubbles: [
                ("u1", #"{"type":1,"text":"SECRET-USER","modelInfo":{"modelName":"grok-4.6"}}"#),
                (
                    "a1",
                    """
                    {"type":2,"createdAt":1755691201000,\
                    "tokenCount":{"inputTokens":200,"outputTokens":50}}
                    """
                ),
            ])
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(
            CursorComposerStore(databaseURL: url).snapshot(excludingSessionIDs: []))
        let event = try #require(snapshot.events.first)

        #expect(snapshot.events.count == 1)
        #expect(event.sessionID == "comp-1")
        #expect(event.project == "Montra")
        #expect(event.model == "grok-4.6")
        #expect(event.inputTokens == 200)
        #expect(event.outputTokens == 50)
        #expect(event.timestamp == Date(timeIntervalSince1970: 1_755_691_201))
    }

    @Test("falls back to the context meter when every bubble is zero")
    func contextMeterFallback() throws {
        let url = try makeComposerDB(
            composerID: "comp-meter",
            composerJSON: """
                {"composerId":"comp-meter","createdAt":1755691200000,\
                "modelConfig":{"modelName":"composer-2"},\
                "promptTokenBreakdown":{"totalUsedTokens":1500},\
                "fullConversationHeadersOnly":[{"bubbleId":"a1","type":2}]}
                """,
            bubbles: [
                ("a1", #"{"type":2,"tokenCount":{"inputTokens":0,"outputTokens":0}}"#)
            ])
        defer { try? FileManager.default.removeItem(at: url) }

        let event = try #require(
            CursorComposerStore(databaseURL: url).snapshot(excludingSessionIDs: [])?.events.first)
        #expect(event.inputTokens == 1500)
        #expect(event.outputTokens == 0)
        #expect(event.sessionID == "comp-meter")
    }

    @Test("skips a composer the JSONL scan already counted")
    func skipsExcludedSessions() throws {
        let url = try makeComposerDB(
            composerID: "comp-dup",
            composerJSON: """
                {"composerId":"comp-dup","createdAt":1755691200000,\
                "promptTokenBreakdown":{"totalUsedTokens":1500},\
                "fullConversationHeadersOnly":[{"bubbleId":"a1","type":2}]}
                """,
            bubbles: [
                ("a1", #"{"type":2,"tokenCount":{"inputTokens":10,"outputTokens":2}}"#)
            ])
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(
            CursorComposerStore(databaseURL: url).snapshot(excludingSessionIDs: ["comp-dup"]))
        #expect(snapshot.events.isEmpty)
    }

    @Test("returns nil when the database file is missing")
    func missingDatabase() {
        let url = URL(fileURLWithPath: "/tmp/ration-cursor-missing-\(UUID().uuidString).vscdb")
        #expect(CursorComposerStore(databaseURL: url).snapshot(excludingSessionIDs: []) == nil)
    }
}

// MARK: - Store integration

@Suite("Cursor history store")
struct CursorHistoryStoreTests {

    @Test("a sqlite-only corpus still fills history when there is no JSONL")
    @MainActor
    func sqliteWithoutJSONL() async throws {
        let db = try makeComposerDB(
            composerID: "comp-store",
            composerJSON: """
                {"composerId":"comp-store","createdAt":1755691200000,\
                "modelConfig":{"modelName":"grok-4.6"},\
                "fullConversationHeadersOnly":[{"bubbleId":"a1","type":2}]}
                """,
            bubbles: [
                (
                    "a1",
                    #"{"type":2,"createdAt":1755691200000,"tokenCount":{"inputTokens":30,"outputTokens":6}}"#
                )
            ])
        let projects = FileManager.default.temporaryDirectory
            .appending(path: "cursor-empty-projects-\(UUID().uuidString)")
        let support = FileManager.default.temporaryDirectory
            .appending(path: "ration-support-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: db)
            try? FileManager.default.removeItem(at: projects)
            try? FileManager.default.removeItem(at: support)
        }

        let store = TranscriptStore(
            provider: .cursor,
            format: CursorTranscriptFormat(projectsRoot: projects, databaseURL: db),
            root: projects,
            supportDirectory: support)
        store.refresh()
        try await waitUntilReady(store)

        #expect(!store.history.isEmpty)
        #expect(store.history.sessionIDs.contains("comp-store"))
        #expect(store.history.sortedDays.contains { $0.billableTokens == 36 })
    }
}

@Suite("Usage history merging")
struct UsageHistoryMergingTests {

    @Test("combines two independently derived days")
    func mergesDays() {
        var files = UsageHistory()
        var snapshot = UsageHistory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var day = DateComponents()
        day.year = 2026
        day.month = 8
        day.day = 20
        let date = calendar.date(from: day)!

        files.add(
            [
                UsageEvent(
                    timestamp: date, model: "grok-4.6", project: "A", sessionID: "s1",
                    inputTokens: 10, outputTokens: 5, cacheReadTokens: 0)
            ], calendar: calendar)
        snapshot.add(
            [
                UsageEvent(
                    timestamp: date, model: "composer-2", project: "B", sessionID: "s2",
                    inputTokens: 20, outputTokens: 8, cacheReadTokens: 0)
            ], calendar: calendar)

        let merged = files.merging(snapshot)
        let total = merged.total(over: merged.sortedDays)
        #expect(total.tokens == 43)
        #expect(total.sessions == 2)
        #expect(merged.sessionIDs == ["s1", "s2"])
    }

    @Test("merging an empty history is a no-op")
    func emptyIsIdentity() {
        var files = UsageHistory()
        files.add([
            UsageEvent(
                timestamp: Date(), model: "grok-4.6", project: "A", sessionID: "s",
                inputTokens: 1, outputTokens: 1, cacheReadTokens: 0)
        ])
        #expect(files.merging(UsageHistory()) == files)
        #expect(UsageHistory().merging(files) == files)
    }
}

// MARK: - sqlite fixture

private func makeComposerDB(
    composerID: String,
    composerJSON: String,
    bubbles: [(String, String)]
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ration-cursor-history-\(UUID().uuidString).vscdb")
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
        throw CursorSessionStore.Error.malformed
    }
    defer { sqlite3_close(db) }

    guard
        sqlite3_exec(db, "CREATE TABLE cursorDiskKV (key TEXT, value TEXT);", nil, nil, nil)
            == SQLITE_OK
    else {
        throw CursorSessionStore.Error.malformed
    }

    func insert(_ key: String, _ value: String) {
        let sql = "INSERT INTO cursorDiskKV (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    insert("composerData:\(composerID)", composerJSON)
    for (bubbleID, json) in bubbles {
        insert("bubbleId:\(composerID):\(bubbleID)", json)
    }
    return url
}

@MainActor
private func waitUntilReady(_ store: TranscriptStore, timeout: TimeInterval = 5) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while store.status != .ready {
        if Date() > deadline {
            Issue.record("timed out waiting for history scan")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
