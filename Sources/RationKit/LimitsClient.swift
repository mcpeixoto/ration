import Foundation

// MARK: - Errors

public enum LimitsError: Error, Equatable, LocalizedError {
    /// The token was rejected. Only Claude Code can fix this.
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int)
    case transport(message: String)
    case decoding(message: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your Claude Code session has expired. Open Claude Code to sign in again."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Too many requests. Retrying in \(Int(retryAfter))s."
            } else {
                "Too many requests. Retrying shortly."
            }
        case .serverError(let status):
            "Anthropic returned an error (\(status)). Retrying."
        case .transport(let message):
            "Could not reach Anthropic: \(message)"
        case .decoding(let message):
            "Could not read the usage response: \(message)"
        }
    }

    /// Everything except an outright rejection is worth retrying. An expired
    /// token will not fix itself, so polling stops until Claude Code refreshes it.
    public var isRetryable: Bool {
        self != .unauthorized
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

// MARK: - Version

public enum Ration {
    /// Kept in step with the VERSION file by Scripts/bundle.sh.
    public static let version = "0.1.0"
}
