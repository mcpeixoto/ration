import Foundation
import Observation

/// Builds usage history from one tool's session transcripts, incrementally.
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

    public let provider: Provider

    /// A scan is in flight. The CLI waits on this rather than on `.scanning`,
    /// because a sqlite/API snapshot with no JSONL files never paints a
    /// progress bar and would otherwise look "ready" while still empty.
    public var isRefreshing: Bool { scanTask != nil }

    private let root: URL
    private let format: any TranscriptFormat
    private let checkpointURL: URL
    private var checkpoints: [String: FileCheckpoint] = [:]
    private var scanTask: Task<Void, Never>?
    /// JSONL-derived history. Published `history` is this merged with the
    /// snapshot, so a sqlite rebuild cannot double-count file events.
    private var fileHistory = UsageHistory()
    private var snapshotHistory = UsageHistory()
    private var snapshotFingerprint: String?

    public init(
        provider: Provider = .claude,
        format: any TranscriptFormat = ClaudeTranscriptFormat(),
        root: URL? = nil,
        supportDirectory: URL? = nil
    ) {
        self.provider = provider
        self.format = format
        self.root = root ?? format.defaultRoot

        let support =
            supportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "Ration")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.checkpointURL = support.appending(path: "history-\(provider.id).json")

        migrateSingleProviderCheckpoint(in: support)
    }

    /// Adopts the checkpoint written by versions that only knew about Claude.
    ///
    /// Every byte in that file is Claude history, so it is renamed rather than
    /// re-derived — otherwise upgrading would mean re-reading a gigabyte of
    /// transcripts to arrive at the numbers already sitting on disk.
    private func migrateSingleProviderCheckpoint(in support: URL) {
        guard provider == .claude else { return }

        let legacy = support.appending(path: "history.json")
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path),
            !manager.fileExists(atPath: checkpointURL.path)
        else { return }

        try? manager.moveItem(at: legacy, to: checkpointURL)
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
        // A scan already under way is adding events into `history` as it goes,
        // advancing `checkpoints` in step. Swapping both out from under it
        // discards everything read so far and rewinds the offsets that would
        // have found it again, so the scan in flight wins — it ends at the
        // same numbers, and sooner.
        guard scanTask == nil else { return }

        guard let data = try? Data(contentsOf: checkpointURL),
            let stored = try? JSONDecoder().decode(Checkpoint.self, from: data)
        else { return }

        // A checkpoint from an older parser or price list is not worth keeping:
        // its totals cannot be corrected in place, only re-derived. Starting
        // over is a background scan; keeping it is a wrong number with no way
        // for anyone to notice.
        guard stored.version == Checkpoint.currentVersion else { return }

        fileHistory = stored.history
        snapshotHistory = stored.snapshotHistory ?? UsageHistory()
        snapshotFingerprint = stored.snapshotFingerprint
        checkpoints = stored.files
        lastScan = stored.savedAt
        publishHistory()
        status = .ready
    }

    private func scan() async {
        let isFirstScan = checkpoints.isEmpty && snapshotFingerprint == nil

        let files = await Task.detached(priority: .utility) { [root, format] in
            TranscriptReader.transcriptFiles(under: root, format: format)
        }.value
        if isFirstScan { status = .scanning(progress: 0) }

        for (index, file) in files.enumerated() {
            if Task.isCancelled { return }

            let key = file.path
            let previous = checkpoints[key]

            // Hop off the main actor for the file read, then back to publish.
            let read = await Task.detached(priority: .utility) { [format] in
                TranscriptReader.readNewBytes(of: file, since: previous, format: format)
            }.value
            guard let (events, checkpoint) = read else { continue }

            fileHistory.add(events)
            checkpoints[key] = checkpoint
            publishHistory()

            if isFirstScan, !files.isEmpty {
                status = .scanning(progress: Double(index + 1) / Double(files.count))
                // Yield so the progress bar can actually paint during the
                // first scan rather than after it.
                await Task.yield()
            }
        }

        await applySnapshot()
        await applyRemoteSnapshot()

        lastScan = Date()
        status = .ready
        saveCheckpoint()
    }

    private func applySnapshot() async {
        let skip = fileHistory.sessionIDs
        let snapshot = await Task.detached(priority: .utility) { [format] in
            format.snapshot(excludingSessionIDs: skip)
        }.value

        guard let snapshot else { return }
        guard snapshot.fingerprint != snapshotFingerprint else { return }

        var next = UsageHistory()
        next.add(snapshot.events)
        snapshotHistory = next
        snapshotFingerprint = snapshot.fingerprint
        publishHistory()
    }

    private func applyRemoteSnapshot() async {
        let skip = format.remoteSnapshotReplacesFiles ? [] : fileHistory.sessionIDs
        let snapshot = await Task.detached(priority: .utility) { [format] in
            await format.remoteSnapshot(excludingSessionIDs: skip)
        }.value

        guard let snapshot else { return }
        guard !snapshot.events.isEmpty else { return }
        guard snapshot.fingerprint != snapshotFingerprint else { return }

        var next = UsageHistory()
        next.add(snapshot.events)
        snapshotHistory = next
        snapshotFingerprint = snapshot.fingerprint
        publishHistory()
    }

    private func publishHistory() {
        if format.remoteSnapshotReplacesFiles,
            let fingerprint = snapshotFingerprint,
            fingerprint.hasPrefix("remote:"),
            !snapshotHistory.isEmpty
        {
            history = snapshotHistory
        } else {
            history = fileHistory.merging(snapshotHistory)
        }
    }

    private func saveCheckpoint() {
        let checkpoint = Checkpoint(
            history: fileHistory,
            files: checkpoints,
            savedAt: Date(),
            snapshotHistory: snapshotHistory,
            snapshotFingerprint: snapshotFingerprint)
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: checkpointURL, options: .atomic)
    }

}

// MARK: - Reading
//
// Deliberately outside the @MainActor class: reading a gigabyte of transcripts
// must not run on the main thread, or the first scan freezes the UI.

public enum TranscriptReader {

    public static func transcriptFiles(
        under root: URL, format: any TranscriptFormat = ClaudeTranscriptFormat()
    ) -> [URL] {
        format.transcriptFiles(under: root)
    }

    /// Reads only the bytes added since the last visit.
    ///
    /// Returns `nil` when there is nothing new. A file that shrank was
    /// truncated or replaced, so it is re-read from the start.
    public static func readNewBytes(
        of url: URL,
        since checkpoint: FileCheckpoint?,
        format: any TranscriptFormat = ClaudeTranscriptFormat()
    ) -> (events: [UsageEvent], checkpoint: FileCheckpoint)? {

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int
        else { return nil }

        var carried = checkpoint ?? FileCheckpoint(offset: 0)
        if size < carried.offset { carried = FileCheckpoint(offset: 0) }  // truncated or replaced
        guard size > carried.offset else { return nil }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        try? handle.seek(toOffset: UInt64(carried.offset))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let start = carried.offset
        let (events, consumed) = format.parse(data, from: url, carrying: &carried)

        // Only advance past whole lines; a partial trailing line is re-read
        // next time, once the rest has been written.
        carried.offset = start + consumed
        return (events, carried)
    }
}

// MARK: - Persistence

/// How far into one file we have read, plus anything the format needs to
/// remember about it between reads.
public struct FileCheckpoint: Codable, Sendable, Equatable {

    public var offset: Int

    /// The model in effect at `offset`. Only used by formats that announce the
    /// model on a different line from the token counts.
    public var model: String?

    /// The project this file belongs to, when the format states it once at the
    /// top of the file rather than on every line.
    public var project: String?

    /// Format-specific running counters. A format that reports cumulative totals
    /// rather than per-turn deltas has to remember the previous total to
    /// difference against, and that has to survive between reads.
    public var carry: [String: Int]?

    public init(
        offset: Int, model: String? = nil, project: String? = nil, carry: [String: Int]? = nil
    ) {
        self.offset = offset
        self.model = model
        self.project = project
        self.carry = carry
    }
}

private struct Checkpoint: Codable {

    /// Bump whenever a parser or the pricing table changes.
    ///
    /// The rolled-up history is *derived* data: cost is computed once, as each
    /// event is parsed, and then only the total is kept. So a corrected parser
    /// or a new rate does nothing for usage that has already been scanned — the
    /// old answer stays frozen in this file forever, and the app quietly keeps
    /// reporting it.
    ///
    /// Both happened while 0.2 was being written: the fix for Codex's duplicated
    /// records, and the rates for the models Codex runs. A checkpoint from an
    /// hour earlier would have survived both. Re-deriving costs a few seconds in
    /// the background; being wrong costs the user's trust in every number on
    /// screen.
    static let currentVersion = 2

    var version: Int = 1
    let history: UsageHistory
    let files: [String: FileCheckpoint]
    let savedAt: Date
    let snapshotHistory: UsageHistory?
    let snapshotFingerprint: String?

    init(
        history: UsageHistory,
        files: [String: FileCheckpoint],
        savedAt: Date,
        snapshotHistory: UsageHistory? = nil,
        snapshotFingerprint: String? = nil
    ) {
        self.version = Self.currentVersion
        self.history = history
        self.files = files
        self.savedAt = savedAt
        self.snapshotHistory = snapshotHistory
        self.snapshotFingerprint = snapshotFingerprint
    }

    /// Files written before versioning are version 1, which no longer matches.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        history = try container.decode(UsageHistory.self, forKey: .history)
        files = try container.decode([String: FileCheckpoint].self, forKey: .files)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        snapshotHistory = try container.decodeIfPresent(
            UsageHistory.self, forKey: .snapshotHistory)
        snapshotFingerprint = try container.decodeIfPresent(
            String.self, forKey: .snapshotFingerprint)
    }
}
