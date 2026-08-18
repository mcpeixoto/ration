import Foundation
import Testing

@testable import RationKit

/// Records the request it was given and replays a canned response.
private final class StubTransport: Transport, @unchecked Sendable {
    var lastRequest: URLRequest?
    var result: Result<(Data, HTTPURLResponse), any Error>

    init(result: Result<(Data, HTTPURLResponse), any Error>) {
        self.result = result
    }

    convenience init(status: Int, body: String = "{}") {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: status, httpVersion: nil, headerFields: nil)!
        self.init(result: .success((Data(body.utf8), response)))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return try result.get()
    }
}

private let validBody = """
    {"limits":[{"kind":"session","group":"session","percent":42,
    "severity":"normal","resets_at":"2026-08-06T22:20:00Z","scope":null,"is_active":true}]}
    """

@Suite("LimitsClient requests")
struct LimitsClientRequestTests {

    @Test("calls the documented usage endpoint")
    func endpoint() async throws {
        let transport = StubTransport(status: 200, body: validBody)
        _ = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "tok")

        let request = try #require(transport.lastRequest)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
    }

    @Test("sends the bearer token and oauth beta header")
    func headers() async throws {
        let transport = StubTransport(status: 200, body: validBody)
        _ = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "secret-token")

        let headers = try #require(transport.lastRequest?.allHTTPHeaderFields)
        #expect(headers["Authorization"] == "Bearer secret-token")
        #expect(headers["anthropic-beta"] == "oauth-2025-04-20")
    }

    @Test("identifies itself honestly in the user agent")
    func userAgent() async throws {
        let transport = StubTransport(status: 200, body: validBody)
        _ = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "tok")

        let agent = try #require(transport.lastRequest?.value(forHTTPHeaderField: "User-Agent"))
        #expect(agent.hasPrefix("Ration/"))
    }

    @Test("never sends a request body")
    func noBody() async throws {
        let transport = StubTransport(status: 200, body: validBody)
        _ = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "tok")
        #expect(transport.lastRequest?.httpBody == nil)
    }
}

@Suite("LimitsClient responses")
struct LimitsClientResponseTests {

    @Test("decodes a successful response into a snapshot")
    func success() async throws {
        let transport = StubTransport(status: 200, body: validBody)
        let snapshot = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "t")

        #expect(snapshot.limits.count == 1)
        #expect(snapshot.limits.first?.percent == 42)
    }

    @Test("maps 401 to unauthorized, so the app can ask for a fresh sign-in")
    func unauthorized() async {
        let transport = StubTransport(status: 401)
        await #expect(throws: LimitsError.unauthorized) {
            try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "stale")
        }
    }

    @Test("maps 403 to unauthorized as well")
    func forbidden() async {
        let transport = StubTransport(status: 403)
        await #expect(throws: LimitsError.unauthorized) {
            try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "t")
        }
    }

    @Test("maps 429 to rateLimited and keeps the Retry-After hint")
    func rateLimited() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: 429, httpVersion: nil,
            headerFields: ["Retry-After": "120"])!
        let transport = StubTransport(result: .success((Data("{}".utf8), response)))

        do {
            _ = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "t")
            Issue.record("expected a rateLimited error")
        } catch let error as LimitsError {
            #expect(error == .rateLimited(retryAfter: 120))
        }
    }

    @Test("maps 5xx to serverError with the status code")
    func serverError() async throws {
        let transport = StubTransport(status: 503)
        do {
            _ = try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "t")
            Issue.record("expected a serverError")
        } catch let error as LimitsError {
            #expect(error == .serverError(status: 503))
        }
    }

    @Test("surfaces transport failures instead of swallowing them")
    func transportFailure() async {
        let underlying = URLError(.notConnectedToInternet)
        let transport = StubTransport(result: .failure(underlying))

        await #expect(throws: LimitsError.self) {
            try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "t")
        }
    }

    @Test("a 200 with unparseable JSON is a decoding failure, not a crash")
    func badPayload() async {
        let transport = StubTransport(status: 200, body: "<html>maintenance</html>")
        await #expect(throws: LimitsError.self) {
            try await AnthropicLimitsClient(transport: transport).fetchUsage(token: "t")
        }
    }
}

@Suite("LimitsError presentation")
struct LimitsErrorTests {

    @Test("every error has a message fit to show a user")
    func messages() {
        let errors: [LimitsError] = [
            .unauthorized,
            .rateLimited(retryAfter: 60),
            .serverError(status: 500),
            .transport(message: "offline"),
            .decoding(message: "bad json"),
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test("the unauthorized message tells the user to sign in again")
    func unauthorizedGuidance() {
        let message = LimitsError.unauthorized.errorDescription ?? ""
        #expect(message.contains("sign in"))
    }

    @Test("only unauthorized should stop polling; the rest are retryable")
    func retryability() {
        #expect(!LimitsError.unauthorized.isRetryable)
        #expect(LimitsError.rateLimited(retryAfter: 1).isRetryable)
        #expect(LimitsError.serverError(status: 500).isRetryable)
        #expect(LimitsError.transport(message: "x").isRetryable)
        #expect(LimitsError.decoding(message: "x").isRetryable)
    }
}
