import Foundation
import Security

/// The OAuth access token Claude Code has already obtained, plus the plan
/// metadata stored alongside it.
///
/// Ration reads this and nothing else. In particular it never reads the
/// refresh token, so it cannot mint new credentials or invalidate your
/// session — only Claude Code can do that.
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
            "No Claude Code credentials found. Sign in with Claude Code first."
        case .accessDenied:
            "Ration was denied access to the Claude Code credentials in your keychain."
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

        let expiry = (oauth["expiresAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        return Credential(
            accessToken: token,
            expiresAt: expiry,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }
}

// MARK: - Store

public protocol CredentialStore: Sendable {
    func credential() throws -> Credential
}

/// Reads Claude Code's credentials from the login keychain.
///
/// Read-only by construction: this type calls `SecItemCopyMatching` and
/// nothing else. There is no code path here that adds, updates, or deletes a
/// keychain item.
///
/// The first read triggers a system prompt, because the item's ACL was created
/// by Claude Code and does not list Ration. Choosing "Always Allow" adds Ration
/// to that ACL and the prompt does not return. `OnboardingView` explains this
/// before it happens.
public struct KeychainCredentialStore: CredentialStore {

    /// The service name Claude Code stores its credentials under.
    public static let service = "Claude Code-credentials"

    public init() {}

    public func credential() throws -> Credential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw CredentialError.malformed }
            return try Credential.parse(from: data)
        case errSecItemNotFound:
            throw CredentialError.notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            throw CredentialError.accessDenied
        default:
            throw CredentialError.keychain(status: status)
        }
    }
}

// MARK: - Caching

/// Holds a credential in memory until it is close to expiring.
///
/// Without this, Ration reads the keychain on every poll. macOS only treats an
/// "Always Allow" grant as durable for a stable code signature, so during
/// development — and after any re-signing — a read-per-poll means a password
/// prompt per poll. Reading once per token lifetime is both kinder and more
/// correct: the token does not change between refreshes.
public final class CachingCredentialStore: CredentialStore, @unchecked Sendable {

    /// Re-read this long before the token actually expires, so a refresh by
    /// Claude Code is picked up without a failed request in between.
    public static let refreshMargin: TimeInterval = 300

    private let underlying: any CredentialStore
    private let lock = NSLock()
    private var cached: Credential?

    public init(wrapping underlying: any CredentialStore = KeychainCredentialStore()) {
        self.underlying = underlying
    }

    public func credential() throws -> Credential {
        lock.lock()
        defer { lock.unlock() }

        if let cached, !cached.expires(within: Self.refreshMargin) {
            return cached
        }
        let fresh = try underlying.credential()
        cached = fresh
        return fresh
    }

    /// Drops the cached copy, forcing the next read to hit the keychain.
    /// Called when the server rejects the token, since Claude Code has
    /// probably replaced it by now.
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }
}
