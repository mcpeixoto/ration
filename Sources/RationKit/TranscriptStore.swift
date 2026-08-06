import Foundation
import Observation

/// Builds usage history from Claude Code's transcripts, incrementally.
///
/// A full scan of a gigabyte corpus takes a few seconds, so the first run reads
/// everything in the background. After that only the bytes appended since the
/// last scan are parsed, which is normally a few kilobytes and effectively
/// instant.
///
/// The checkpoint — per-file byte offsets and the rolled-up daily history — is
/// persisted to Application Support so a relaunch does not re-read the corpus.
@MainActor
@Observable
public final class TranscriptStore {

    public enum Status: Sendable, Equatable {
        case idle
        /// First-time scan. `progress` is 0…1 over files, for a progress bar.
        case scanning(progress: Double)
        case ready
        case failed(String)
    }

    public private(set) var history = UsageHistory()
    public private(set) var status: Status = .idle
    /// When the last successful scan finished.
    public private(set) var lastScan: Date?

    private let root: URL
    private let checkpointURL: URL
    private var checkpoints: [String: FileCheckpoint] = [:]
    private var scanTask: Task<Void, Never>?

    public init(
        root: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/projects"),
        supportDirectory: URL? = nil
    ) {
        self.root = root

        let support =
            supportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "Ration")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.checkpointURL = support.appending(path: "history.json")
    }

    // MARK: Scanning

    /// Reads anything new. Safe to call often — with no new bytes it does
    /// almost nothing.
    public func refresh() {
        guard scanTask == nil else { return }

        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.scan()
            self.scanTask = nil
        }
    }

    public func loadCheckpoint() {
        guard let data = try? Data(contentsOf: checkpointURL),
            let stored = try? JSONDecoder().decode(Checkpoint.self, from: data)
        else { return }

        history = stored.history
        checkpoints = stored.files
        lastScan = stored.savedAt
        status = .ready
    }

    private func scan() async {
        let isFirstScan = checkpoints.isEmpty
        if isFirstScan { status = .scanning(progress: 0) }

        let files = await Task.detached(priority: .utility) { [root] in
            TranscriptReader.transcriptFiles(under: root)
        }.value
        guard !files.isEmpty else {
            status = .ready
            return
        }

        for (index, file) in files.enumerated() {
            if Task.isCancelled { return }

            let key = file.path
            let previous = checkpoints[key]

            // Hop off the main actor for the file read, then back to publish.
            let read = await Task.detached(priority: .utility) {
                TranscriptReader.readNewBytes(of: file, since: previous)
            }.value
            guard let (events, checkpoint) = read else { continue }

            history.add(events)
            checkpoints[key] = checkpoint

            if isFirstScan {
                status = .scanning(progress: Double(index + 1) / Double(files.count))
                // Yield so the progress bar can actually paint during the
                // first scan rather than after it.
                await Task.yield()
            }
        }

        lastScan = Date()
        status = .ready
        saveCheckpoint()
    }

    private func saveCheckpoint() {
        let checkpoint = Checkpoint(history: history, files: checkpoints, savedAt: Date())
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: checkpointURL, options: .atomic)
    }

}

// MARK: - Reading
//
// Deliberately outside the @MainActor class: reading a gigabyte of transcripts
// must not run on the main thread, or the first scan freezes the UI.

public enum TranscriptReader {

    public static func transcriptFiles(under root: URL) -> [URL] {
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

    /// Reads only the bytes added since the last visit.
    ///
    /// Returns `nil` when there is nothing new. A file that shrank was
    /// truncated or replaced, so it is re-read from the start.
    public static func readNewBytes(
        of url: URL, since checkpoint: FileCheckpoint?
    ) -> (events: [UsageEvent], checkpoint: FileCheckpoint)? {

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int
        else { return nil }

        var offset = checkpoint?.offset ?? 0
        if size < offset { offset = 0 }  // truncated or replaced
        guard size > offset else { return nil }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let project = TranscriptParser.projectName(
            fromDirectory: url.deletingLastPathComponent().lastPathComponent)
        let sessionID = url.deletingPathExtension().lastPathComponent

        let (events, consumed) = TranscriptParser.parse(
            data, project: project, fallbackSessionID: sessionID)

        // Only advance past whole lines; a partial trailing line is re-read
        // next time, once the rest has been written.
        return (events, FileCheckpoint(offset: offset + consumed))
    }
}

// MARK: - Persistence

public struct FileCheckpoint: Codable, Sendable, Equatable {
    public var offset: Int

    public init(offset: Int) { self.offset = offset }
}

private struct Checkpoint: Codable {
    let history: UsageHistory
    let files: [String: FileCheckpoint]
    let savedAt: Date
}
