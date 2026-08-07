import Foundation
import RationKit

/// Stand-ins so previews render without a keychain or a network.
struct PreviewCredentialStore: CredentialStore {
    func credential() throws -> Credential {
        Credential(
            accessToken: "preview", expiresAt: Date(timeIntervalSinceNow: 3600),
            subscriptionType: "max", rateLimitTier: "default_claude_max_5x")
    }
}

struct PreviewLimitsClient: LimitsClient {
    let snapshot: UsageSnapshot
    func fetchUsage(token: String) async throws -> UsageSnapshot { snapshot }
}

/// A scratch directory so a preview run never touches the real checkpoint.
/// A provider whose numbers come from a fixture rather than from the machine.
///
/// Used for both halves of the preview registry, so the renders are identical
/// on any Mac regardless of which tools happen to be installed on it.
struct PreviewUsageSource: UsageSource {
    let provider: Provider
    let snapshot: UsageSnapshot

    func availability() -> ProviderAvailability { .ready }
    func fetchUsage() async throws -> UsageSnapshot { snapshot }
}

/// The registry the preview renders against.
///
/// Claude is populated; Codex exists so the provider switcher appears in the
/// screenshots, which is the point of having one.
@MainActor
func previewRegistry(snapshot: UsageSnapshot, transcripts: TranscriptStore) -> ProviderRegistry {
    ProviderRegistry(entries: [
        ProviderRegistry.Entry(
            provider: .claude,
            poller: UsagePoller(
                source: PreviewUsageSource(provider: .claude, snapshot: snapshot)),
            history: transcripts),
        ProviderRegistry.Entry(
            provider: .codex,
            poller: UsagePoller(
                source: PreviewUsageSource(provider: .codex, snapshot: snapshot)),
            history: transcripts),
    ])
}

func temporaryPreviewSupport() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ration-preview-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a synthetic transcript corpus so the Activity and Metrics tabs have
/// something plausible to draw.
///
/// Deterministic — a hash of the day index stands in for randomness, so the
/// generated screenshots are stable across runs.
func sampleTranscriptRoot(days: Int = 150, endingOn end: Date = Date()) -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "ration-preview-transcripts-\(UUID().uuidString)")

    let projects = ["Montra", "Ration", "MealMind", "GuardaRios", "Rifas"]
    let models = ["claude-opus-5", "claude-sonnet-5", "claude-opus-4-8", "claude-fable-5"]
    let calendar = Calendar.current
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]

    var linesByProject: [String: [String]] = [:]

    for offset in 0..<days {
        guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }

        // A deterministic pseudo-random weight per day, with weekends quieter.
        let seed = (offset &* 2_654_435_761) % 100
        let isWeekend = calendar.isDateInWeekend(day)
        let turns = isWeekend ? seed % 4 : seed % 14
        guard turns > 0 else { continue }

        let project = projects[offset % projects.count]
        let model = models[(offset / 3) % models.count]

        for turn in 0..<turns {
            guard let stamp = calendar.date(byAdding: .hour, value: 9 + (turn % 10), to: day)
            else { continue }

            let output = 400 + (seed * 37 + turn * 211) % 4000
            let line = """
                {"type":"assistant","cwd":"/Users/preview/Coding/\(project)",\
                "sessionId":"sess-\(offset)-\(turn / 5)",\
                "timestamp":"\(formatter.string(from: stamp))",\
                "message":{"model":"\(model)","usage":{"input_tokens":12,\
                "output_tokens":\(output),"cache_read_input_tokens":\(output * 8),\
                "cache_creation":{"ephemeral_5m_input_tokens":0,\
                "ephemeral_1h_input_tokens":\(output * 2)}}}}
                """
            linesByProject[project, default: []].append(line)
        }
    }

    for (project, lines) in linesByProject {
        let directory = root.appending(path: "-Users-preview-Coding-\(project)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = lines.joined(separator: "\n") + "\n"
        try? Data(contents.utf8).write(to: directory.appending(path: "\(project).jsonl"))
    }

    return root
}
