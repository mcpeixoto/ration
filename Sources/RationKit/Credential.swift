import Foundation

/// The OAuth access token Claude Code has already obtained, plus the plan
/// metadata stored alongside it.
///
/// Ration reads this and nothing else. In particular it never reads the
/// refresh token, so it cannot mint new credentials. Sending a *stale*
/// access token after Claude Code has rotated it *can* invalidate the
/// session, which is why the store is re-read on every poll.
public struct Credential: Sendable {

    public let accessToken: String
    public let expiresAt: Date?
    /// e.g. `max`, `pro`. Display only.
    public let subscriptionType: String?
    /// e.g. `default_claude_max_5x`. Display only.
    public let rateLimitTier: String?

    public init(
        accessToken: String,
        expiresAt: Date?,
        subscriptionType: String?,
        rateLimitTier: String?
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// Claude Code refreshes the token well before this. If we do find an
    /// expired one, the honest move is to say so rather than fire a request
    /// we know will fail.
    ///
    /// A credential with no stated expiry is assumed usable; the server will
    /// tell us with a 401 if it is not.
    public var isExpired: Bool {
        expires(within: 0)
    }

    /// Whether the token expires within `margin` seconds from now.
    /// A credential with no stated expiry never reports as expiring.
    public func expires(within margin: TimeInterval, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= margin
    }
}

// MARK: - Redaction
//
// A credential must never render its token, no matter how it ends up being
// printed — string interpolation, `dump`, a crash log, an error message.

extension Credential: CustomStringConvertible, CustomDebugStringConvertible {

    public var description: String {
        let plan = subscriptionType ?? "unknown plan"
        return "Credential(token: <redacted>, plan: \(plan))"
    }

    public var debugDescription: String { description }
}

// MARK: - Parsing

public enum CredentialError: Error, Equatable, LocalizedError {
    /// No Claude Code credentials in the keychain at all.
    case notFound
    /// The user declined the keychain prompt, or macOS denied access.
    case accessDenied
    /// Found something, but not in the shape we expect.
    case malformed
    /// An unexpected Security framework status.
    case keychain(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            #if os(macOS)
            "No Claude Code credentials found. Sign in with Claude Code first."
            #else
            "No Claude Code credentials found at \(PlatformPaths.claudeCredentialsFile.path). Sign in with Claude Code first."
            #endif
        case .accessDenied:
            #if os(macOS)
            "Ration was denied access to the Claude Code credentials in your keychain."
            #else
            "Ration could not read the Claude Code credentials file."
            #endif
        case .malformed:
            "The Claude Code credentials could not be read. Try signing in again."
        case .keychain(let status):
            "The keychain returned an unexpected error (\(status))."
        }
    }
}

extension Credential {

    /// Parses the JSON blob Claude Code stores in the keychain.
    ///
    /// Only `claudeAiOauth.accessToken` and its sibling display fields are
    /// read. The refresh token and every MCP server token in the same blob are
    /// ignored — see `CredentialSecurityTests`.
    public static func parse(from data: Data) throws -> Credential {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw CredentialError.malformed
        }

        return Credential(
            accessToken: token,
            expiresAt: Self.expiry(from: oauth["expiresAt"]),
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    /// Claude Code has stored `expiresAt` as both milliseconds and seconds
    /// since epoch. Treat a value too large to be a Unix-seconds date as
    /// milliseconds; anything else as seconds.
    static func expiry(from raw: Any?) -> Date? {
        let value: Double
        if let number = raw as? Double {
            value = number
        } else if let number = raw as? Int {
            value = Double(number)
        } else {
            return nil
        }
        // 10 billion seconds after 1970 is the year 2286. Real token
        // expiries in milliseconds are ~1.7e12; in seconds they are ~1.7e9.
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: - Store

public protocol CredentialStore: Sendable {
    func credential() throws -> Credential
}

// MARK: - File

/// Reads Claude Code's credentials from the file Claude Code already wrote.
///
/// On Linux this is the only store. On macOS it is preferred when present:
/// Claude Code itself reads `~/.claude/.credentials.json` ahead of the
/// keychain, and some users keep that file *instead* of the keychain item
/// so that token refresh cannot reset a keychain ACL and lock them out.
public struct FileCredentialStore: CredentialStore {

    public let fileURL: URL

    public init(fileURL: URL = PlatformPaths.claudeCredentialsFile) {
        self.fileURL = fileURL
    }

    public func credential() throws -> Credential {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CredentialError.notFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CredentialError.accessDenied
        }

        return try Credential.parse(from: data)
    }
}

// MARK: - Fallback

/// Tries one store, and if that store has nothing, tries another.
///
/// Used on macOS to prefer the credentials file (no prompt, no ACL) and
/// fall back to the keychain item Claude Code created. A missing file is
/// the only reason to continue — a malformed or unreadable file must not
/// silently switch stores, because the two can hold different generations
/// of the same OAuth session, and using the stale one signs the user out.
public struct FallbackCredentialStore: CredentialStore {

    private let primary: any CredentialStore
    private let fallback: any CredentialStore

    public init(primary: any CredentialStore, fallback: any CredentialStore) {
        self.primary = primary
        self.fallback = fallback
    }

    public func credential() throws -> Credential {
        do {
            return try primary.credential()
        } catch CredentialError.notFound {
            return try fallback.credential()
        }
    }
}

// MARK: - Pass-through
//
// Historically this type cached the access token until five minutes before
// `expiresAt`. Claude Code rotates the token hours before that, and sending
// the retired access token is what signed people out of Claude. It now
// always reads through. The type remains because `AnthropicUsageSource`
// still calls `invalidate()` after a 401, which is the signal to retry
// with whatever the underlying store currently has.

/// Reads through to the underlying store on every call.
///
/// `invalidate()` is a no-op: there is nothing to drop. The method stays
/// so a 401 can re-read the live store and retry without a new type.
public final class CachingCredentialStore: CredentialStore, @unchecked Sendable {

    private let underlying: any CredentialStore

    public init(wrapping underlying: any CredentialStore = DefaultCredentialStore()) {
        self.underlying = underlying
    }

    public func credential() throws -> Credential {
        try underlying.credential()
    }

    public func invalidate() {}
}
