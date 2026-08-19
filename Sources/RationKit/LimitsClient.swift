import Foundation

// MARK: - Errors

public enum LimitsError: Error, Equatable, LocalizedError {
    /// The token was rejected. Only Claude Code can fix this.
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int)
    case transport(message: String)
    case decoding(message: String)
    /// This provider has nothing to report and never will — it is installed,
    /// but its usage is not readable the way Ration reads things.
    case unavailable(reason: String)
    /// Installed, readable in principle, but nothing has been written yet.
    case noData(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your session has expired. Open the tool to sign in again."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Too many requests. Retrying in \(Int(retryAfter))s."
            } else {
                "Too many requests. Retrying shortly."
            }
        case .serverError(let status):
            "The usage service returned an error (\(status)). Retrying."
        case .transport(let message):
            "Could not reach the usage service: \(message)"
        case .decoding(let message):
            "Could not read the usage response: \(message)"
        case .unavailable(let reason), .noData(let reason):
            reason
        }
    }

    /// Everything except an outright rejection is worth retrying. An expired
    /// token will not fix itself, so polling stops until Claude Code refreshes it.
    ///
    /// `unavailable` is likewise permanent: retrying a provider whose usage is
    /// not readable would burn a poll every minute to learn the same thing.
    public var isRetryable: Bool {
        switch self {
        case .unauthorized, .unavailable: false
        default: true
        }
    }
}

// MARK: - Transport
//
// A seam for tests. The live implementation is a thin URLSession wrapper;
// tests substitute a stub and never touch the network.

public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LimitsError.transport(message: "unexpected response type")
        }
        return (data, http)
    }
}

// MARK: - Client

public protocol LimitsClient: Sendable {
    func fetchUsage(token: String) async throws -> UsageSnapshot
}

/// Fetches plan utilisation from Anthropic.
///
/// This is the only network call Ration makes, to the only host it knows.
public struct AnthropicLimitsClient: LimitsClient {

    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// The beta header Claude Code sends for OAuth-scoped endpoints.
    static let oauthBeta = "oauth-2025-04-20"

    private let transport: any Transport
    private let version: String

    public init(transport: any Transport = URLSessionTransport(), version: String = Ration.version)
    {
        self.transport = transport
        self.version = version
    }

    public func fetchUsage(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.oauthBeta, forHTTPHeaderField: "anthropic-beta")
        // Identify ourselves rather than impersonating the official client.
        request.setValue(
            "Ration/\(version) (github.com/mcpeixoto/ration)",
            forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as LimitsError {
            throw error
        } catch {
            throw LimitsError.transport(message: error.localizedDescription)
        }

        switch response.statusCode {
        case 200..<300:
            do {
                return try UsageSnapshot.decode(from: data)
            } catch {
                throw LimitsError.decoding(message: error.localizedDescription)
            }
        case 401, 403:
            throw LimitsError.unauthorized
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(
                TimeInterval.init)
            throw LimitsError.rateLimited(retryAfter: retryAfter)
        default:
            throw LimitsError.serverError(status: response.statusCode)
        }
    }
}

// MARK: - Source

/// Claude's usage, as a `UsageSource`.
///
/// Owns the keychain read as well as the request, because the two belong
/// together: the token is read, used once, and never held anywhere else. Every
/// other provider Ration supports is read from files, so this is the only
/// source that touches a credential at all.
public struct AnthropicUsageSource: UsageSource {

    public var provider: Provider { .claude }

    private let credentialStore: any CredentialStore
    private let client: any LimitsClient

    public init(
        credentialStore: any CredentialStore = CachingCredentialStore(),
        client: any LimitsClient = AnthropicLimitsClient()
    ) {
        self.credentialStore = credentialStore
        self.client = client
    }

    /// Always `ready`. Unlike the file-backed providers there is nothing on disk
    /// to look for, and probing the keychain here would fire the permission
    /// prompt from a method documented not to.
    public func availability() -> ProviderAvailability { .ready }

    /// On macOS the keychain item belongs to Claude Code, so the system asks
    /// before letting Ration read it. Linux reads a file Claude Code already
    /// wrote, so there is nothing to prompt for.
    public var promptsForPermission: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let credential = try credentialStore.credential()

        // Claude Code normally refreshes well before this. If it has not, say so
        // rather than firing a request we know will be rejected.
        guard !credential.isExpired else { throw LimitsError.unauthorized }

        do {
            let snapshot = try await client.fetchUsage(token: credential.accessToken)
            return snapshot.withPlan(credential.subscriptionType)
        } catch LimitsError.unauthorized {
            // A rejected token means Claude Code has probably rotated it, so
            // drop the cached copy and read the keychain again next time.
            (credentialStore as? CachingCredentialStore)?.invalidate()
            throw LimitsError.unauthorized
        }
    }

    /// The cached credential is the only thing this source keeps between
    /// polls. Dropping it means the next read goes to the keychain again.
    public func forget() {
        (credentialStore as? CachingCredentialStore)?.invalidate()
    }
}

// MARK: - Version

public enum Ration {
    /// Kept in step with the VERSION file by Scripts/bundle.sh.
    public static let version = "0.7.0"
}
