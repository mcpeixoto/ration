import Foundation

/// Extracts usage events from Cursor's agent-transcript JSONL.
///
/// **What this reads.** Token counts, model, timestamp, working directory and
/// session id. The same lines also carry prompts, replies, and tool inputs —
/// none of which is decoded into the event. `CursorParserPrivacyTests`
/// enforces this.
///
/// Cursor writes two shapes. Recent transcripts repeat Claude Code's
/// `message.usage` object on assistant lines. Older ones have no counts at
/// all; those lines are skipped, and `CursorComposerStore` fills the gap from
/// the sqlite Cursor already keeps.
public struct CursorTranscriptFormat: TranscriptFormat {

    public let defaultRoot: URL
    public let databaseURL: URL
    public var remoteSnapshotReplacesFiles: Bool { true }

    private let client: CursorLimitsClient
    private let sessionStore: CursorSessionStore

    public init(
        projectsRoot: URL? = nil,
        databaseURL: URL? = nil,
        client: CursorLimitsClient = CursorLimitsClient(),
        sessionStore: CursorSessionStore? = nil
    ) {
        self.defaultRoot = projectsRoot ?? PlatformPaths.cursorProjectsDirectory
        self.databaseURL = databaseURL ?? PlatformPaths.cursorStateDatabase
        self.client = client
        self.sessionStore = sessionStore ?? CursorSessionStore(databaseURL: self.databaseURL)
    }

    /// Only files under `agent-transcripts`. `.cursor/projects` also holds
    /// editor chrome that happens to use `.jsonl`, and walking those would
    /// burn a first scan on noise.
    public func transcriptFiles(under root: URL) -> [URL] {
        jsonlFiles(under: root).filter { url in
            url.pathComponents.contains("agent-transcripts")
        }
    }

    private static let usageMarkers: [Data] = [
        Data("\"usage\"".utf8),
        Data("\"tokenCount\"".utf8),
        Data("\"input_tokens\"".utf8),
        Data("\"inputTokens\"".utf8),
        Data("\"output_tokens\"".utf8),
        Data("\"outputTokens\"".utf8),
    ]

    public func parse(
        _ data: Data, from url: URL, carrying _: inout FileCheckpoint
    ) -> (events: [UsageEvent], consumed: Int) {

        var events: [UsageEvent] = []
        var consumed = 0
        var lineStart = data.startIndex
        let sessionID = Self.sessionID(from: url)
        let project = Self.projectName(from: url)
        let fallbackDate = Self.fileDate(of: url)

        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            defer { lineStart = data.index(after: newline) }
            consumed = data.distance(from: data.startIndex, to: newline) + 1

            let line = data[lineStart..<newline]
            guard !line.isEmpty else { continue }
            guard Self.containsUsageMarker(line) else { continue }

            if let event = Self.event(
                from: line, project: project, sessionID: sessionID, fallbackDate: fallbackDate)
            {
                events.append(event)
            }
        }

        return (events, consumed)
    }

    public func snapshot(excludingSessionIDs: Set<String>) -> (
        fingerprint: String, events: [UsageEvent]
    )? {
        CursorComposerStore(databaseURL: databaseURL).snapshot(
            excludingSessionIDs: excludingSessionIDs)
    }

    public func remoteSnapshot(excludingSessionIDs: Set<String>) async -> (
        fingerprint: String, events: [UsageEvent]
    )? {
        let session: CursorSession
        do {
            session = try sessionStore.session()
        } catch {
            return nil
        }
        let end = Date()
        let start =
            Calendar.current.date(byAdding: .day, value: -90, to: end)
            ?? end.addingTimeInterval(-90 * 24 * 3600)
        let events: [UsageEvent]
        do {
            events = try await client.fetchHistoryEvents(
                token: session.accessToken, from: start, to: end)
        } catch {
            return nil
        }
        let kept = events.filter { !excludingSessionIDs.contains($0.sessionID) }
        guard !kept.isEmpty else { return nil }
        let tokens = kept.reduce(0) { $0 + $1.billableTokens }
        let last = kept.map(\.timestamp).max()?.timeIntervalSince1970 ?? 0
        return ("remote:\(kept.count):\(tokens):\(Int(last))", kept)
    }

    // MARK: Lines

    private static func containsUsageMarker(_ line: Data.SubSequence) -> Bool {
        usageMarkers.contains { line.range(of: $0) != nil }
    }

    private static func event(
        from line: Data.SubSequence,
        project: String,
        sessionID: String,
        fallbackDate: Date
    ) -> UsageEvent? {

        guard let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
        else { return nil }

        let kind = (root["role"] as? String) ?? (root["type"] as? String)
        if kind == "user" { return nil }

        let message = root["message"] as? [String: Any]
        let usage =
            message?["usage"] as? [String: Any]
            ?? root["usage"] as? [String: Any]
            ?? message?["tokenCount"] as? [String: Any]
            ?? root["tokenCount"] as? [String: Any]
            ?? [:]

        let cacheDetail = usage["cache_creation"] as? [String: Any]
        let write1h = CursorJSON.int(cacheDetail?["ephemeral_1h_input_tokens"])
        let write5m = CursorJSON.int(cacheDetail?["ephemeral_5m_input_tokens"])
        let cacheTotal =
            CursorJSON.int(usage["cache_creation_input_tokens"])
            ?? CursorJSON.int(usage["cacheWriteTokens"])
            ?? CursorJSON.int(usage["cache_write_tokens"])
            ?? CursorJSON.int(usage["cache_write_input_tokens"])
            ?? 0

        let input =
            CursorJSON.int(usage["input_tokens"])
            ?? CursorJSON.int(usage["inputTokens"])
            ?? CursorJSON.int(root["input_tokens"])
            ?? 0
        let output =
            CursorJSON.int(usage["output_tokens"])
            ?? CursorJSON.int(usage["outputTokens"])
            ?? CursorJSON.int(root["output_tokens"])
            ?? 0
        let cacheRead =
            CursorJSON.int(usage["cache_read_input_tokens"])
            ?? CursorJSON.int(usage["cacheReadTokens"])
            ?? CursorJSON.int(usage["cache_read_tokens"])
            ?? CursorJSON.int(root["cache_read_tokens"])
            ?? 0
        let cacheWrite5m = write5m ?? (write1h == nil ? cacheTotal : 0)
        let cacheWrite1h = write1h ?? 0

        guard input > 0 || output > 0 || cacheRead > 0 || cacheWrite5m > 0 || cacheWrite1h > 0
        else {
            return nil
        }

        let modelInfo =
            (message?["modelInfo"] as? [String: Any]) ?? (root["modelInfo"] as? [String: Any])
        let model =
            (message?["model"] as? String)
            ?? (root["model"] as? String)
            ?? (root["model_id"] as? String)
            ?? (modelInfo?["modelName"] as? String)
            ?? "unknown"

        let cwd = (root["cwd"] as? String) ?? (message?["cwd"] as? String)
        let timestamp =
            CursorJSON.date(root["timestamp"] ?? root["createdAt"] ?? message?["timestamp"])
            ?? fallbackDate

        let serverTools = usage["server_tool_use"] as? [String: Any]

        return UsageEvent(
            timestamp: timestamp,
            model: model,
            project: cwd.map(TranscriptParser.projectName(fromPath:)) ?? project,
            sessionID: (root["sessionId"] as? String) ?? (root["conversation_id"] as? String)
                ?? sessionID,
            inputTokens: input,
            outputTokens: output,
            cacheWrite5mTokens: cacheWrite5m,
            cacheWrite1hTokens: cacheWrite1h,
            cacheReadTokens: cacheRead,
            webSearches: CursorJSON.int(serverTools?["web_search_requests"]) ?? 0
        )
    }

    /// `…/agent-transcripts/<uuid>/<uuid>.jsonl` → the UUID.
    ///
    /// Taken from the file name so the parser never has to read a metadata
    /// line that might carry the prompt.
    static func sessionID(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// `…/projects/Users-me-Coding-Montra/agent-transcripts/…` → `Montra`.
    static func projectName(from url: URL) -> String {
        let parts = url.pathComponents
        if let index = parts.lastIndex(of: "agent-transcripts"), index > 0 {
            return TranscriptParser.projectName(fromDirectory: parts[index - 1])
        }
        return TranscriptParser.projectName(
            fromDirectory: url.deletingLastPathComponent().lastPathComponent)
    }

    private static func fileDate(of url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? Date()
    }
}

// MARK: - JSON numbers

enum CursorJSON {

    static func int(_ value: Any?) -> Int? {
        double(value).map { Int($0.rounded(.towardZero)) }
    }

    static func double(_ value: Any?) -> Double? {
        // Do not reject `NSNumber(1)` via `is Bool` — JSON integers 0 and 1
        // bridge to Bool on Apple and Linux, which would drop real token
        // counts of 1.
        if value == nil || value is NSNull { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let int64 = value as? Int64 { return Double(int64) }
        if let uint64 = value as? UInt64 { return Double(uint64) }
        if let string = value as? String { return Double(string) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    static func firstDouble(_ body: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = double(body[key]) { return value }
        }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if value == nil || value is NSNull { return nil }
        if let string = value as? String {
            if let iso = ISO8601.date(from: string) { return iso }
            if let number = Double(string) { return date(fromEpoch: number) }
            return nil
        }
        if let number = value as? NSNumber {
            return date(fromEpoch: number.doubleValue)
        }
        if let double = value as? Double {
            return date(fromEpoch: double)
        }
        if let int = value as? Int {
            return date(fromEpoch: Double(int))
        }
        if let int64 = value as? Int64 {
            return date(fromEpoch: Double(int64))
        }
        return nil
    }

    /// Cursor stamps sqlite rows in milliseconds, JSONL in ISO-8601, and the
    /// odd hook payload in seconds. A value past 1e12 is milliseconds.
    private static func date(fromEpoch value: Double) -> Date {
        Date(timeIntervalSince1970: value > 1_000_000_000_000 ? value / 1000 : value)
    }
}
