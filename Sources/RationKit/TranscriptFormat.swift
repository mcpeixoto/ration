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
}

extension TranscriptFormat {

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
