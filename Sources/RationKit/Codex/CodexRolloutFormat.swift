import Foundation

/// Extracts usage events from Codex CLI's rollout transcripts.
///
/// **What this reads.** Two line types out of six. `turn_context` supplies the
/// model and the working directory; `token_count` supplies the counts. Every
/// other line — the prompts, the replies, the file contents, the reasoning, and
/// the multi-kilobyte instruction blob on the first line — is skipped without
/// being decoded at all. `CodexParserPrivacyTests` enforces this.
///
/// Codex splits what Claude Code keeps together: Claude repeats `model` and
/// `cwd` on every line that carries counts, while Codex states them once per
/// turn on a separate line. That is what `FileCheckpoint.model`/`.project` are
/// for — an incremental read that resumes in the middle of a turn still knows
/// which model it is looking at.
public struct CodexRolloutFormat: TranscriptFormat {

    public init() {}

    public var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/sessions")
    }

    /// Codex writes several kinds of file under its home; only rollouts are
    /// transcripts.
    ///
    /// Archived sessions are included. Codex moves them to a sibling directory
    /// rather than deleting them, and they are still work you did — leaving them
    /// out lost 39.4M tokens across four sessions on the machine this was
    /// written against, which is exactly the kind of quiet under-count a usage
    /// meter must not have.
    public func transcriptFiles(under root: URL) -> [URL] {
        var roots = [root]
        if root.lastPathComponent == "sessions" {
            roots.append(root.deletingLastPathComponent().appending(path: "archived_sessions"))
        }

        return
            roots
            .flatMap { jsonlFiles(under: $0) }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") }
    }

    // Compact JSON with no spaces after the colons, which is what Codex emits —
    // checked against real rollouts. A line that matches neither marker is never
    // handed to the JSON decoder.
    private static let countsMarker = Data("\"last_token_usage\"".utf8)
    private static let contextMarker = Data("\"type\":\"turn_context\"".utf8)

    public func parse(
        _ data: Data, from url: URL, carrying carried: inout FileCheckpoint
    ) -> (events: [UsageEvent], consumed: Int) {

        var events: [UsageEvent] = []
        var consumed = 0
        var lineStart = data.startIndex
        let sessionID = Self.sessionID(from: url)

        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            defer { lineStart = data.index(after: newline) }
            consumed = data.distance(from: data.startIndex, to: newline) + 1

            let line = data[lineStart..<newline]
            guard !line.isEmpty else { continue }

            if line.range(of: Self.contextMarker) != nil {
                Self.absorbContext(line, into: &carried)
            } else if line.range(of: Self.countsMarker) != nil,
                let event = Self.event(from: line, carried: &carried, sessionID: sessionID)
            {
                events.append(event)
            }
        }

        return (events, consumed)
    }

    // MARK: Lines

    /// Remembers the model and project a `turn_context` announces, so the
    /// `token_count` lines that follow it can be attributed.
    private static func absorbContext(_ line: Data.SubSequence, into carried: inout FileCheckpoint)
    {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
            let payload = root["payload"] as? [String: Any]
        else { return }

        if let model = payload["model"] as? String { carried.model = model }
        if let cwd = payload["cwd"] as? String {
            carried.project = TranscriptParser.projectName(fromPath: cwd)
        }
    }

    /// The cumulative fields this format differences, in `FileCheckpoint.carry`.
    private static let counters = [
        "input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens",
    ]

    private static func event(
        from line: Data.SubSequence, carried: inout FileCheckpoint, sessionID: String
    ) -> UsageEvent? {

        guard
            let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
            let payload = root["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let info = payload["info"] as? [String: Any],
            // Differenced from the *running total*, not read from
            // `last_token_usage`.
            //
            // Codex has emitted every `token_count` twice for part of its
            // history — two records a second apart carrying an identical
            // payload — so summing the per-turn field double-counts those
            // sessions. It did that in 17 of the 44 rollouts on the machine
            // this was written against, inflating one project by 80%.
            // Differencing the cumulative is immune: a repeat of the same total
            // yields a delta of zero, and the running sum always converges on
            // the figure Codex itself reports.
            let usage = info["total_token_usage"] as? [String: Any],
            let timestamp = (root["timestamp"] as? String).flatMap(ISO8601.date(from:))
        else {
            return nil
        }

        var previous = carried.carry ?? [:]
        var delta: [String: Int] = [:]
        for key in counters {
            let total = usage[key] as? Int ?? 0
            // A total that went backwards means the session was compacted or
            // restarted, so the new total is itself the delta.
            let last = previous[key] ?? 0
            delta[key] = total < last ? total : total - last
            previous[key] = total
        }
        carried.carry = previous

        let input = delta["input_tokens"] ?? 0
        let cached = delta["cached_input_tokens"] ?? 0
        let output = delta["output_tokens"] ?? 0

        // Nothing new since the last record: a duplicate, or one of the
        // book-keeping events Codex emits between turns.
        guard input > 0 || output > 0 else { return nil }

        return UsageEvent(
            timestamp: timestamp,
            model: carried.model ?? "unknown",
            project: carried.project ?? "Unknown",
            sessionID: sessionID,
            // Codex counts cached reads *inside* `input_tokens`; Claude Code
            // reports them alongside. Subtract, or every cached token is billed
            // twice — at full price once and at the cache rate again.
            inputTokens: max(0, input - cached),
            // `reasoning_output_tokens` is a subset of `output_tokens`, so
            // adding it would double-count the thinking.
            outputTokens: output,
            // One cache tier, not two: nothing maps onto the 1-hour slot.
            cacheWrite5mTokens: delta["cache_write_input_tokens"] ?? 0,
            cacheWrite1hTokens: 0,
            cacheReadTokens: cached,
            // Codex records searches on their own event lines, unattached to any
            // turn's counts, so there is nothing to attribute them to here.
            webSearches: 0
        )
    }

    /// `rollout-2026-08-07T00-14-57-019fd95b-…-64c06c87f1ec.jsonl` → the UUID.
    ///
    /// Taken from the file name rather than from `session_meta`, so the one line
    /// carrying the instruction blob never has to be decoded.
    static func sessionID(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let candidate = String(name.suffix(36))
        return candidate.filter { $0 == "-" }.count == 4 ? candidate : name
    }
}
