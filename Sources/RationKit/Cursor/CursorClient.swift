import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches Cursor plan utilisation from `api2.cursor.sh`.
///
/// Two endpoints, tried in order: the current dashboard period, then the
/// older request-count document. Both take the Bearer token Cursor already
/// stored on disk. Nothing else is sent.
///
/// History (Activity, Trends, Detail) is the same host: the filtered usage
/// log first, then the per-model aggregation if that log is empty. Local
/// transcripts often have no token counts, so the dashboard is what makes
/// those tabs match Claude and Codex.
public struct CursorLimitsClient: Sendable {

    public static let periodEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    public static let authUsageEndpoint = URL(string: "https://api2.cursor.sh/auth/usage")!
    public static let filteredEventsEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents")!
    public static let aggregatedEventsEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents")!

    /// Newest events first, enough for the 90-day Trends window without
    /// walking a huge team log on every launch.
    public static let historyPageSize = 500
    public static let historyMaxPages = 6

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

    /// Usage events for the Activity / Trends / Detail tabs.
    ///
    /// Empty when both dashboard history endpoints have nothing usable —
    /// the caller then keeps whatever local transcripts already found.
    public func fetchHistoryEvents(
        token: String,
        from start: Date,
        to end: Date = Date()
    ) async throws -> [UsageEvent] {
        if let events = try await fetchFilteredEvents(token: token, from: start, to: end),
            !events.isEmpty
        {
            return events
        }
        return try await fetchAggregatedEvents(token: token, from: start, to: end) ?? []
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

    private func fetchFilteredEvents(
        token: String, from start: Date, to end: Date
    ) async throws -> [UsageEvent]? {
        var all: [UsageEvent] = []
        for page in 1...Self.historyMaxPages {
            let body: [String: Any] = [
                "startDate": Self.millisString(start),
                "endDate": Self.millisString(end),
                "page": page,
                "pageSize": Self.historyPageSize,
            ]
            guard
                let data = try await postJSON(
                    url: Self.filteredEventsEndpoint, token: token, body: body)
            else { return all.isEmpty ? nil : all }

            let events = CursorUsage.events(fromFiltered: data)
            if events.isEmpty { break }
            all.append(contentsOf: events)
            if events.count < Self.historyPageSize { break }
            if let oldest = events.min(by: { $0.timestamp < $1.timestamp }),
                oldest.timestamp < start
            {
                break
            }
        }
        return all
    }

    private func fetchAggregatedEvents(
        token: String, from start: Date, to end: Date
    ) async throws -> [UsageEvent]? {
        let body: [String: Any] = [
            "teamId": -1,
            "startDate": Self.millisString(start),
            "endDate": Self.millisString(end),
        ]
        guard
            let data = try await postJSON(
                url: Self.aggregatedEventsEndpoint, token: token, body: body)
        else { return nil }
        // No per-day timestamps — stamp at the end of the window so Detail
        // still ranks models, and Activity has a point rather than going blank.
        let events = CursorUsage.events(fromAggregated: data, at: end)
        return events.isEmpty ? nil : events
    }

    /// `nil` for a 404 / empty body so a missing RPC does not fail the gauge.
    private func postJSON(url: URL, token: String, body: [String: Any]) async throws -> Data? {
        var request = request(url: url, method: "POST", token: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
            return data
        case 401, 403:
            throw LimitsError.unauthorized
        case 404, 501, 502, 503:
            return nil
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(
                TimeInterval.init)
            throw LimitsError.rateLimited(retryAfter: retryAfter)
        default:
            return nil
        }
    }

    private func request(url: URL, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(
            "Ration/\(version) (github.com/mcpeixoto/ration)",
            forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        if method == "POST" {
            request.httpBody = Data("{}".utf8)
        }
        return request
    }

    static func millisString(_ date: Date) -> String {
        String(Int((date.timeIntervalSince1970 * 1000).rounded()))
    }
}
