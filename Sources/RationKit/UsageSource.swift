import Foundation

/// Where one provider's current usage comes from.
///
/// The important thing this abstracts is *not* "which URL to call" — it is that
/// providers differ in kind. Claude's percentages come from a request; Codex
/// writes its own rate limits into the session files it already keeps on disk.
/// A protocol shaped around a token and an endpoint could not describe the
/// second, so this one is shaped around the answer instead of the mechanism.
///
/// `fetchUsage()` deliberately takes no token: each source owns how (and
/// whether) it authenticates. That is what keeps `CredentialStore` — and the
/// keychain prompt that comes with it — confined to the one provider that needs
/// it.
public protocol UsageSource: Sendable {

    var provider: Provider { get }

    /// Cheap, synchronous, no side effects: usually a check for whether a
    /// directory exists. Called to decide whether to show the provider at all,
    /// so it must not prompt, block, or read credentials.
    func availability() -> ProviderAvailability

    /// Throws `CredentialError` when the user needs to sign in to the
    /// underlying tool, and `LimitsError` for everything else.
    func fetchUsage() async throws -> UsageSnapshot

    /// Whether the first fetch will make macOS ask the user for something.
    ///
    /// Only the keychain read does. Onboarding exists to explain that prompt
    /// before it appears, so a source that cannot cause one must not be held
    /// behind it — a provider read from the user's own files needs no consent
    /// ceremony.
    var promptsForPermission: Bool { get }

    /// Drop anything held in memory between polls.
    ///
    /// Called when the user turns a provider off. Polling stops on its own —
    /// a hidden provider leaves `metered` — but a source holding a cached
    /// credential would keep holding it for as long as the app runs, and
    /// "hidden and not read" would be only half true.
    func forget()
}

extension UsageSource {
    public var promptsForPermission: Bool { false }

    /// Most sources cache nothing between polls, so forgetting costs nothing.
    public func forget() {}
}

// MARK: - Detect-only

/// A provider Ration can see but cannot meter.
///
/// Cursor, Copilot and Gemini all keep their plan usage behind a network call —
/// in Cursor's case behind a browser session cookie. Reading any of those would
/// mean new hosts, and for one of them Ration minting and storing a credential
/// of its own. Ration does not do that, so these providers are listed honestly
/// with the reason rather than quietly omitted or half-implemented.
public struct DetectOnlyUsageSource: UsageSource {

    public let provider: Provider
    /// Existence of this path is what "installed" means for this tool.
    private let markerPath: URL
    private let reason: String

    public init(provider: Provider, markerPath: URL, reason: String) {
        self.provider = provider
        self.markerPath = markerPath
        self.reason = reason
    }

    public func availability() -> ProviderAvailability {
        guard FileManager.default.fileExists(atPath: markerPath.path) else {
            return .notInstalled
        }
        return .quotaNotReadable(reason: reason)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        throw LimitsError.unavailable(reason: reason)
    }
}

extension DetectOnlyUsageSource {

    private static func home(_ path: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: path)
    }

    public static func cursor() -> DetectOnlyUsageSource {
        DetectOnlyUsageSource(
            provider: .cursor,
            markerPath: home("Library/Application Support/Cursor"),
            reason: """
                Cursor keeps your plan usage on its website, behind the session \
                cookie in your browser. Ration will not read your browser's \
                cookies, so there is no gauge to show.
                """)
    }

    public static func copilot() -> DetectOnlyUsageSource {
        DetectOnlyUsageSource(
            provider: .copilot,
            markerPath: home(".config/github-copilot"),
            reason: """
                Copilot reports your quota over the network, to a token Ration \
                would have to create and store itself. Ration reads only what \
                your tools already wrote, so there is no gauge to show.
                """)
    }

    public static func gemini() -> DetectOnlyUsageSource {
        DetectOnlyUsageSource(
            provider: .gemini,
            markerPath: home(".gemini"),
            reason: """
                Gemini reports remaining quota over the network and writes no \
                usage totals to disk, so there is no gauge to show.
                """)
    }
}
