import Foundation

/// Codex's quota, read from the files Codex already keeps.
///
/// No request, no credential, no host. Codex stamps its own rate limits into
/// every `token_count` record it writes, so the most recent one is the current
/// answer. Ration never opens Codex's credential store — the plan tier is in the
/// rollout too.
///
/// The cost of that is staleness: these numbers age while Codex is not running.
/// `UsageSnapshot.fetchedAt` carries the record's own timestamp rather than the
/// time of the read, so the panel reports the numbers as what they are.
public struct CodexUsageSource: UsageSource {

    public var provider: Provider { .codex }

    /// How far back from the end of a file to look for the last rate-limit
    /// record. Rollouts reach tens of megabytes; a gauge must not read them.
    /// The tail of an active session is dense with `token_count` records, so
    /// this is generous.
    static let tailBytes = 256 * 1024

    /// How many recent files to try before giving up. More than one because the
    /// newest file may be a session that ended before Codex reported a limit.
    static let filesToTry = 5

    private let root: URL
    private let format = CodexRolloutFormat()

    public init(root: URL? = nil) {
        self.root = root ?? CodexRolloutFormat().defaultRoot
    }

    public func availability() -> ProviderAvailability {
        guard FileManager.default.fileExists(atPath: root.path) else { return .notInstalled }
        guard !format.transcriptFiles(under: root).isEmpty else {
            return .noData(reason: "No Codex sessions yet.")
        }
        return .ready
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let files = newestFirst()
        guard !files.isEmpty else {
            throw LimitsError.noData(reason: "No Codex sessions yet.")
        }

        for file in files.prefix(Self.filesToTry) {
            if let snapshot = Self.lastRateLimits(in: file) { return snapshot }
        }

        throw LimitsError.noData(
            reason: "Codex has not recorded a usage limit yet. Run a Codex session.")
    }

    /// Most recently written first — which is the most recently *used* session,
    /// not the one with the newest name.
    private func newestFirst() -> [URL] {
        format.transcriptFiles(under: root)
            .compactMap { url -> (URL, Date)? in
                guard
                    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate
                else { return nil }
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: Tail reading

    /// Finds the last record in `file` that carries rate limits.
    ///
    /// Reads only the tail. Scans the lines it finds in reverse so the newest
    /// answer wins, and tolerates a truncated first line — seeking to a byte
    /// offset lands mid-line, and that fragment is simply skipped.
    static func lastRateLimits(in file: URL) -> UsageSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let marker = Data("\"rate_limits\"".utf8)

        for line in data.split(separator: 0x0A).reversed() {
            guard line.range(of: marker) != nil else { continue }
            guard
                let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                let payload = root["payload"] as? [String: Any],
                let timestamp = (root["timestamp"] as? String).flatMap(ISO8601.date(from:)),
                let snapshot = CodexRateLimits.snapshot(from: payload, at: timestamp)
            else { continue }

            return snapshot
        }

        return nil
    }
}
