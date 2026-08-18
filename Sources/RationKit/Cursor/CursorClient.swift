import Foundation

/// Fetches Cursor plan utilisation from `api2.cursor.sh`.
///
/// Two endpoints, tried in order: the current dashboard period, then the
/// older request-count document. Both take the Bearer token Cursor already
/// stored on disk. Nothing else is sent.
public struct CursorLimitsClient: Sendable {

    public static let periodEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    public static let authUsageEndpoint = URL(string: "https://api2.cursor.sh/auth/usage")!

    private let transport: any Transport
    private let version: String

    public init(transport: any Transport = URLSessionTransport(), version: String = Ration.version)
    {
        self.transport = transport
        self.version = version
    }

    public func fetchUsage(token: String, planName: String? = nil) async throws -> UsageSnapshot {
        let periodRequest = request(url: Self.periodEndpoint, method: "POST", token: token)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(periodRequest)
        } catch let error as LimitsError {
            throw error
        } catch {
            throw LimitsError.transport(message: error.localizedDescription)
        }

        switch response.statusCode {
        case 401, 403:
            throw LimitsError.unauthorized
        case 200..<300:
            if let snapshot = try? CursorUsage.snapshot(
                fromPeriod: data, planName: planName)
            {
                return snapshot
            }
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(
                TimeInterval.init)
            throw LimitsError.rateLimited(retryAfter: retryAfter)
        default:
            break
        }

        return try await fetchAuthUsage(token: token, planName: planName)
    }

    private func fetchAuthUsage(token: String, planName: String?) async throws -> UsageSnapshot {
        let request = request(url: Self.authUsageEndpoint, method: "GET", token: token)
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
                return try CursorUsage.snapshot(fromAuthUsage: data, planName: planName)
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

    private func request(url: URL, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Ration/\(version) (github.com/mcpeixoto/ration)",
            forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        if method == "POST" {
            request.httpBody = Data("{}".utf8)
        }
        return request
    }
}
