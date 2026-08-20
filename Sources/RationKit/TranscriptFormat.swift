import Foundation

/// How one tool writes its session logs.
///
/// Every tool Ration reads keeps append-only JSONL somewhere under the home
/// directory, which is why one incremental byte-offset reader serves all of
/// them. What differs is where the files live, which lines carry token counts,
/// and what those counts mean — and that is exactly what a conformance says.
public protocol TranscriptFormat: Sendable {

    /// Where this tool keeps its sessions, by default.
    var defaultRoot: URL { get }

    func transcriptFiles(under root: URL) -> [URL]

    /// Parses whole lines out of `data`.
    ///
    /// - Parameter carrying: per-file state that survives between incremental
    ///   reads. A format whose token counts and their context arrive on
    ///   *different* lines — Codex writes the model on `turn_context` and the
    ///   counts on `token_count` — would otherwise lose that context whenever a
    ///   read happens to start after it.
    /// - Returns: the events found, and how many bytes were consumed. A trailing
    ///   partial line is left unconsumed so the caller can resume from that
    ///   offset once the rest has been written.
    func parse(
        _ data: Data, from url: URL, carrying: inout FileCheckpoint
    ) -> (events: [UsageEvent], consumed: Int)

    /// A non-append-only corpus that has to be re-read as a whole when it
    /// changes — Cursor's sqlite, whose rows are rewritten in place.
    ///
    /// `nil` for formats that only have JSONL. `excludingSessionIDs` are
    /// sessions the JSONL scan already counted, so a snapshot must not add
    /// them again.
    func snapshot(excludingSessionIDs: Set<String>) -> (fingerprint: String, events: [UsageEvent])?

    /// Same job as `snapshot`, over the network. Cursor's dashboard usage log
    /// is the billing source of truth; local agent transcripts often have no
    /// token counts at all.
    ///
    /// `nil` (the default) for formats that only have files.
    func remoteSnapshot(excludingSessionIDs: Set<String>) async -> (
        fingerprint: String, events: [UsageEvent]
    )?

    /// When the remote snapshot has events, it replaces file-derived history
    /// rather than merging: the dashboard already counted those turns.
    var remoteSnapshotReplacesFiles: Bool { get }
}

extension TranscriptFormat {

    public func snapshot(excludingSessionIDs _: Set<String>) -> (
        fingerprint: String, events: [UsageEvent]
    )? { nil }

    public func remoteSnapshot(excludingSessionIDs _: Set<String>) async -> (
        fingerprint: String, events: [UsageEvent]
    )? { nil }

    public var remoteSnapshotReplacesFiles: Bool { false }

    /// Walks a directory tree for `.jsonl`, which is what all of them use.
    public func jsonlFiles(under root: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey])
        else { return [] }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "jsonl" { files.append(url) }
        }
        return files
    }
}

// MARK: - Claude Code

public struct ClaudeTranscriptFormat: TranscriptFormat {

    public init() {}

    public var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/projects")
    }

    public func transcriptFiles(under root: URL) -> [URL] {
        jsonlFiles(under: root)
    }

    public func parse(
        _ data: Data, from url: URL, carrying _: inout FileCheckpoint
    ) -> (events: [UsageEvent], consumed: Int) {
        // Claude Code repeats `cwd` and `sessionId` on every line, so nothing
        // needs carrying between reads. The directory name and file name are
        // only fallbacks for lines that omit them.
        TranscriptParser.parse(
            data,
            project: TranscriptParser.projectName(
                fromDirectory: url.deletingLastPathComponent().lastPathComponent),
            fallbackSessionID: url.deletingPathExtension().lastPathComponent)
    }
}
