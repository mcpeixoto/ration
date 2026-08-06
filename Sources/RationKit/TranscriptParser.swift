import Foundation

/// Extracts usage events from Claude Code's JSONL transcripts.
///
/// **What this reads.** Only `message.usage`, `message.model`, `timestamp`,
/// `cwd`, and `sessionId`. The same lines also carry your prompts, Claude's
/// replies, and the contents of files you have opened — none of which is
/// decoded, retained, or written anywhere. `TranscriptParserPrivacyTests`
/// enforces this.
public enum TranscriptParser {

    /// Only assistant turns carry token counts. Testing for this substring
    /// before decoding skips roughly half the lines for the cost of a memcmp,
    /// which matters when the corpus is a gigabyte.
    private static let usageMarker = Data("\"output_tokens\"".utf8)

    /// Parses whole lines out of `data`.
    ///
    /// - Returns: the events found, and how many bytes were consumed. A
    ///   trailing partial line is left unconsumed so the caller can resume from
    ///   that offset once the rest has been written.
    public static func parse(
        _ data: Data,
        project: String,
        fallbackSessionID: String
    ) -> (events: [UsageEvent], consumed: Int) {

        var events: [UsageEvent] = []
        var consumed = 0
        var lineStart = data.startIndex

        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            defer { lineStart = data.index(after: newline) }
            consumed = data.distance(from: data.startIndex, to: newline) + 1

            let line = data[lineStart..<newline]
            guard !line.isEmpty else { continue }
            guard line.range(of: usageMarker) != nil else { continue }

            if let event = event(from: line, project: project, fallback: fallbackSessionID) {
                events.append(event)
            }
        }

        return (events, consumed)
    }

    private static func event(
        from line: Data.SubSequence,
        project: String,
        fallback: String
    ) -> UsageEvent? {

        guard
            let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
            root["type"] as? String == "assistant",
            let message = root["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any],
            let model = message["model"] as? String,
            let timestamp = (root["timestamp"] as? String).flatMap(ISO8601.date(from:))
        else {
            return nil
        }

        let serverTools = usage["server_tool_use"] as? [String: Any]

        // Cache writes are reported both as a total and split by TTL. Prefer
        // the split — the two TTLs are priced differently — and fall back to
        // attributing the total to the 5-minute cache.
        let cacheDetail = usage["cache_creation"] as? [String: Any]
        let write1h = cacheDetail?["ephemeral_1h_input_tokens"] as? Int
        let write5m = cacheDetail?["ephemeral_5m_input_tokens"] as? Int
        let cacheTotal = usage["cache_creation_input_tokens"] as? Int ?? 0

        return UsageEvent(
            timestamp: timestamp,
            model: model,
            // `cwd` is the real project path; the enclosing directory name is a
            // mangled version of it, so prefer `cwd` when present.
            project: (root["cwd"] as? String).map(projectName(fromPath:)) ?? project,
            sessionID: root["sessionId"] as? String ?? fallback,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheWrite5mTokens: write5m ?? (write1h == nil ? cacheTotal : 0),
            cacheWrite1hTokens: write1h ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            webSearches: serverTools?["web_search_requests"] as? Int ?? 0
        )
    }

    /// `/Users/me/Documents/Coding/Montra` → `Montra`.
    public static func projectName(fromPath path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? trimmed : name
    }

    /// Claude Code names transcript directories after the project path with the
    /// separators replaced: `-Users-me-Documents-Coding-Montra` → `Montra`.
    /// Used only when a line has no `cwd` of its own.
    public static func projectName(fromDirectory directory: String) -> String {
        directory.split(separator: "-").last.map(String.init) ?? directory
    }
}
