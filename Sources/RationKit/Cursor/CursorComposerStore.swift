import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSqlite3
#endif

/// Usage events from the sqlite Cursor already wrote.
///
/// Agent JSONL often has no token counts. The same conversations live in
/// `state.vscdb` as composers and bubbles, with `tokenCount` on assistant
/// turns and a conversation-level context meter as a fallback. Ration copies
/// the file (Cursor keeps it locked), opens the copy read-only, and pulls
/// those numbers — never the bubble text.
struct CursorComposerStore: Sendable {

    let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func snapshot(excludingSessionIDs: Set<String>) -> (fingerprint: String, events: [UsageEvent])?
    {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        guard let fingerprint = Self.fingerprint(of: databaseURL) else { return nil }

        do {
            let events = try readEvents(excludingSessionIDs: excludingSessionIDs)
            return (fingerprint, events)
        } catch {
            return (fingerprint, [])
        }
    }

    // MARK: Fingerprint

    /// Size and mtime of the db plus its WAL, so a rewrite we did not
    /// incrementally watch still forces a re-read.
    static func fingerprint(of url: URL) -> String? {
        var parts: [String] = []
        for path in [url.path, url.path + "-wal"] {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let size = attributes[.size] as? Int
            else { continue }
            let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(size):\(mtime)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "|")
    }

    // MARK: Reading

    private func readEvents(excludingSessionIDs: Set<String>) throws -> [UsageEvent] {
        let copy = try snapshotCopy()
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(copy.path, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let table = Self.tableName(in: db)
        let composers = Self.rows(in: db, table: table, prefix: "composerData:")
        guard !composers.isEmpty else { return [] }

        var bubblesByComposer: [String: [String: [String: Any]]] = [:]
        for (key, value) in Self.rows(in: db, table: table, prefix: "bubbleId:") {
            let parts = key.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let composerID = String(parts[1])
            let bubbleID = parts.dropFirst(2).joined(separator: ":")
            guard let body = Self.object(value) else { continue }
            bubblesByComposer[composerID, default: [:]][bubbleID] = body
        }

        var events: [UsageEvent] = []
        for (key, value) in composers {
            let composerID = String(key.dropFirst("composerData:".count))
            guard !composerID.isEmpty, !excludingSessionIDs.contains(composerID) else { continue }
            guard let composer = Self.object(value) else { continue }
            events.append(
                contentsOf: Self.events(
                    composerID: composerID,
                    composer: composer,
                    bubbles: bubblesByComposer[composerID] ?? [:]))
        }
        return events
    }

    private static func events(
        composerID: String,
        composer: [String: Any],
        bubbles: [String: [String: Any]]
    ) -> [UsageEvent] {
        let project = projectName(from: composer)
        let sessionModel =
            ((composer["modelConfig"] as? [String: Any])?["modelName"] as? String) ?? "unknown"
        let headers = composer["fullConversationHeadersOnly"] as? [[String: Any]] ?? []
        let fallbackDate =
            CursorJSON.date(composer["lastUpdatedAt"] ?? composer["createdAt"]) ?? Date()

        var events: [UsageEvent] = []
        var currentModel = sessionModel

        let orderedIDs: [String]
        if headers.isEmpty {
            orderedIDs = Array(bubbles.keys)
        } else {
            orderedIDs = headers.compactMap { $0["bubbleId"] as? String }
        }

        for bubbleID in orderedIDs {
            guard let bubble = bubbles[bubbleID] else { continue }
            let type = CursorJSON.int(bubble["type"])
            if let model = modelName(from: bubble) { currentModel = model }
            // 1 is the user turn; 2 (and the occasional 0) are assistant/tool.
            if type == 1 { continue }

            let tokens = tokenCount(from: bubble)
            guard
                tokens.input > 0 || tokens.output > 0 || tokens.cacheRead > 0
                    || tokens.cacheWrite > 0
            else { continue }

            let timestamp =
                CursorJSON.date(bubble["createdAt"])
                ?? CursorJSON.date(
                    headers.first { ($0["bubbleId"] as? String) == bubbleID }?["createdAt"])
                ?? fallbackDate

            events.append(
                UsageEvent(
                    timestamp: timestamp,
                    model: currentModel,
                    project: project,
                    sessionID: composerID,
                    inputTokens: tokens.input,
                    outputTokens: tokens.output,
                    cacheWrite5mTokens: tokens.cacheWrite,
                    cacheReadTokens: tokens.cacheRead))
        }

        if !events.isEmpty { return events }

        // Current Cursor builds often write `{0,0}` per bubble. The composer's
        // own context meter is then the only local figure. One event per
        // conversation, stamped at creation so a re-parse does not wander.
        let meter =
            CursorJSON.int((composer["promptTokenBreakdown"] as? [String: Any])?["totalUsedTokens"])
            ?? CursorJSON.int(composer["contextTokensUsed"])
            ?? 0
        guard meter > 0 else { return [] }

        return [
            UsageEvent(
                timestamp: CursorJSON.date(composer["createdAt"]) ?? fallbackDate,
                model: sessionModel,
                project: project,
                sessionID: composerID,
                inputTokens: meter,
                outputTokens: 0,
                cacheReadTokens: 0)
        ]
    }

    private static func tokenCount(from bubble: [String: Any]) -> (
        input: Int, output: Int, cacheRead: Int, cacheWrite: Int
    ) {
        let usage =
            bubble["tokenCount"] as? [String: Any]
            ?? bubble["usage"] as? [String: Any]
            ?? [:]
        return (
            CursorJSON.int(usage["inputTokens"]) ?? CursorJSON.int(usage["input_tokens"]) ?? 0,
            CursorJSON.int(usage["outputTokens"]) ?? CursorJSON.int(usage["output_tokens"]) ?? 0,
            CursorJSON.int(usage["cacheReadTokens"])
                ?? CursorJSON.int(usage["cache_read_input_tokens"]) ?? 0,
            CursorJSON.int(usage["cacheWriteTokens"])
                ?? CursorJSON.int(usage["cache_creation_input_tokens"]) ?? 0
        )
    }

    private static func modelName(from bubble: [String: Any]) -> String? {
        let info = bubble["modelInfo"] as? [String: Any]
        let name = info?["modelName"] as? String
        return name?.isEmpty == false ? name : nil
    }

    private static func projectName(from composer: [String: Any]) -> String {
        let workspace = composer["workspaceIdentifier"] as? [String: Any]
        let uri = workspace?["uri"] as? [String: Any]
        if let path = (uri?["fsPath"] as? String) ?? (uri?["path"] as? String) {
            return TranscriptParser.projectName(fromPath: path)
        }
        if let repos = composer["trackedGitRepos"] as? [[String: Any]],
            let path = repos.first?["repoPath"] as? String
        {
            return TranscriptParser.projectName(fromPath: path)
        }
        if let cwd = composer["cwd"] as? String {
            return TranscriptParser.projectName(fromPath: cwd)
        }
        return "Cursor"
    }

    // MARK: sqlite

    private func snapshotCopy() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(
                path: "ration-cursor-history-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appending(path: databaseURL.lastPathComponent)
        try FileManager.default.copyItem(at: databaseURL, to: dest)
        for suffix in ["-wal", "-shm"] {
            let extra = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: extra.path) {
                try? FileManager.default.copyItem(
                    at: extra, to: URL(fileURLWithPath: dest.path + suffix))
            }
        }
        return dest
    }

    private static func tableName(in db: OpaquePointer) -> String {
        for name in ["cursorDiskKV", "ItemTable"] where hasTable(name, in: db) {
            return name
        }
        return "cursorDiskKV"
    }

    private static func hasTable(_ name: String, in db: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, name, -1, transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func rows(in db: OpaquePointer, table: String, prefix: String) -> [(
        String, String
    )] {
        // Table names are from a fixed allow-list, never from the file.
        let sql = "SELECT key, value FROM \(table) WHERE key LIKE ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "\(prefix)%", -1, transient)

        var rows: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPointer = sqlite3_column_text(stmt, 0) else { continue }
            let key = String(cString: keyPointer)
            let value: String
            if let pointer = sqlite3_column_text(stmt, 1) {
                value = String(cString: pointer)
            } else if let blob = sqlite3_column_blob(stmt, 1) {
                let length = Int(sqlite3_column_bytes(stmt, 1))
                value = String(decoding: Data(bytes: blob, count: length), as: UTF8.self)
            } else {
                continue
            }
            rows.append((key, value))
        }
        return rows
    }

    private static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }
}
