import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(SQLite3)
import SQLite3
#else
import CSqlite3
#endif
import Testing

@testable import RationKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "missing fixture \(name).json")
    return try Data(contentsOf: url)
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}

// MARK: - Period usage (the current dashboard payload)

@Suite("Cursor period usage decoding")
struct CursorPeriodDecodingTests {

    @Test("reads the billing-cycle percentage as the monthly gauge")
    func monthlyPercent() throws {
        let snapshot = try CursorUsage.snapshot(fromPeriod: fixture("cursor_period"))

        let monthly = try #require(snapshot.limits.first { $0.kind.rawValue == "monthly" })
        #expect(monthly.percent == 61.7)
        #expect(monthly.resetsAt == date(2026, 9, 1))
        #expect(monthly.windowLength == 31 * 24 * 3600.0)
    }

    @Test("keeps Auto and API as separate limits when the payload has them")
    func autoAndAPI() throws {
        let snapshot = try CursorUsage.snapshot(fromPeriod: fixture("cursor_period"))

        let auto = try #require(snapshot.limits.first { $0.kind.rawValue == "auto" })
        #expect(auto.percent == 40)

        let api = try #require(snapshot.limits.first { $0.kind.rawValue == "api" })
        #expect(api.percent == 21.7)
    }

    @Test("exposes spend in major units from the cent amounts")
    func spend() throws {
        let snapshot = try CursorUsage.snapshot(fromPeriod: fixture("cursor_period"))
        let spend = try #require(snapshot.spend)

        #expect(spend.usedAmount == 12.34)
        #expect(spend.limitAmount == 20)
        #expect(spend.percent == 61.7)
        #expect(spend.currencyCode == "USD")
        #expect(spend.isEnabled == true)
    }

    @Test("attaches a plan name learned from Cursor's local state")
    func planName() throws {
        let snapshot = try CursorUsage.snapshot(
            fromPeriod: fixture("cursor_period"), planName: "business")
        #expect(snapshot.planName == "business")
    }

    @Test("stamps fetchedAt from the caller, not from now inside the decoder")
    func fetchedAt() throws {
        let at = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = try CursorUsage.snapshot(fromPeriod: fixture("cursor_period"), fetchedAt: at)
        #expect(snapshot.fetchedAt == at)
    }

    @Test("throws when the payload has no usable percentage")
    func emptyPayload() {
        #expect(throws: CursorUsage.Error.malformed) {
            try CursorUsage.snapshot(fromPeriod: Data(#"{}"#.utf8))
        }
    }
}

// MARK: - Legacy request-count payload

@Suite("Cursor auth usage decoding")
struct CursorAuthUsageDecodingTests {

    @Test("turns request counts into a monthly percentage")
    func requestPercent() throws {
        let snapshot = try CursorUsage.snapshot(fromAuthUsage: fixture("cursor_auth_usage"))
        let monthly = try #require(snapshot.limits.first { $0.kind.rawValue == "monthly" })
        #expect(monthly.percent == 30)
    }

    @Test("treats startOfMonth as the window start, resetting a month later")
    func window() throws {
        let snapshot = try CursorUsage.snapshot(fromAuthUsage: fixture("cursor_auth_usage"))
        let monthly = try #require(snapshot.limits.first { $0.kind.rawValue == "monthly" })
        #expect(monthly.resetsAt == date(2026, 9, 1))
        #expect(monthly.windowLength == 31 * 24 * 3600.0)
    }

    @Test("throws when neither requests nor a limit are present")
    func emptyAuthUsage() {
        #expect(throws: CursorUsage.Error.malformed) {
            try CursorUsage.snapshot(fromAuthUsage: Data(#"{}"#.utf8))
        }
    }
}

// MARK: - Local session store (the sqlite Cursor already wrote)

@Suite("Cursor session store", .serialized)
struct CursorSessionStoreTests {

    @Test("reads the access token and plan, and nothing else")
    func readsTokenAndPlan() throws {
        let url = try makeStateDB(token: "tok-live", plan: "business")
        let session = try CursorSessionStore(databaseURL: url).session()

        #expect(session.accessToken == "tok-live")
        #expect(session.planName == "business")
        for child in Mirror(reflecting: session).children {
            let value = String(describing: child.value)
            #expect(!value.contains("refresh"), "session leaked a refresh secret")
        }
    }

    @Test("throws notFound when Cursor has not signed in")
    func missingToken() throws {
        let url = try makeStateDB(token: nil, plan: nil)
        #expect(throws: CursorSessionStore.Error.notFound) {
            try CursorSessionStore(databaseURL: url).session()
        }
    }

    @Test("throws notFound when the database file is absent")
    func missingFile() {
        let url = URL(fileURLWithPath: "/tmp/ration-cursor-missing-\(UUID().uuidString).vscdb")
        #expect(throws: CursorSessionStore.Error.notFound) {
            try CursorSessionStore(databaseURL: url).session()
        }
    }

    /// `state.vscdb` is a working database that grows without bound — 11 GB on
    /// a machine that has used Cursor for a while. Copying it to read two rows
    /// costs minutes of I/O and gigabytes of temp space on every poll, so the
    /// live file is read in place and the copy is only a fallback.
    @Test("reads the live database without copying it")
    func readsWithoutCopying() throws {
        let url = try makeStateDB(token: "tok-live", plan: "pro")
        let before = copiesPresent()

        _ = try CursorSessionStore(databaseURL: url).session()

        // Compared as a set difference rather than a count: the temp directory
        // is shared with every other test, and one of them removing its own
        // fixture must not read as this one behaving.
        #expect(copiesPresent().subtracting(before).isEmpty, "the read left a copy behind")
    }

    /// A copy left behind by a killed process is as large as Cursor's database
    /// — gigabytes — and nothing else will ever clean it up.
    @Test("a copy abandoned by an earlier run is swept away")
    func sweepsAbandonedCopies() throws {
        let temporary = FileManager.default.temporaryDirectory
        let abandoned = temporary.appending(path: "ration-cursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: abandoned.appending(path: "state.vscdb"))
        // Backdate it past the grace period a live copy sits inside.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: abandoned.path)

        // Reading a database that cannot be opened directly takes the copy
        // path, which sweeps before it copies.
        let unreadable = temporary.appending(path: "ration-fixture-\(UUID().uuidString).db")
        try Data("not a database".utf8).write(to: unreadable)
        _ = try? CursorSessionStore(databaseURL: unreadable).session()

        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        try? FileManager.default.removeItem(at: unreadable)
    }

    private func copiesPresent() -> Set<String> {
        let directory = FileManager.default.temporaryDirectory
        let contents =
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(contents.filter { $0.hasPrefix("ration-cursor-") })
    }
}

// MARK: - Client

private final class StubTransport: Transport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var results: [Result<(Data, HTTPURLResponse), any Error>]

    init(results: [Result<(Data, HTTPURLResponse), any Error>]) {
        self.results = results
    }

    convenience init(status: Int, body: String, url: String = "https://api2.cursor.sh/") {
        let response = HTTPURLResponse(
            url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
        self.init(results: [.success((Data(body.utf8), response))])
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !results.isEmpty else {
            throw LimitsError.transport(message: "no stubbed response")
        }
        return try results.removeFirst().get()
    }
}

@Suite("Cursor client")
struct CursorClientTests {

    @Test("asks the dashboard for the current period first")
    func periodEndpoint() async throws {
        let body = String(data: try fixture("cursor_period"), encoding: .utf8)!
        let transport = StubTransport(status: 200, body: body)
        _ = try await CursorLimitsClient(transport: transport).fetchUsage(token: "tok")

        let request = try #require(transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Ration/") == true)
    }

    @Test("falls back to the request-count endpoint when the dashboard has nothing")
    func fallback() async throws {
        let period = HTTPURLResponse(
            url: URL(string: "https://api2.cursor.sh/")!,
            statusCode: 200, httpVersion: nil, headerFields: nil)!
        let auth = HTTPURLResponse(
            url: URL(string: "https://api2.cursor.sh/auth/usage")!,
            statusCode: 200, httpVersion: nil, headerFields: nil)!
        let transport = StubTransport(results: [
            .success((Data(#"{}"#.utf8), period)),
            .success((try fixture("cursor_auth_usage"), auth)),
        ])

        let snapshot = try await CursorLimitsClient(transport: transport).fetchUsage(token: "tok")
        #expect(snapshot.limits.contains { $0.kind.rawValue == "monthly" && $0.percent == 30 })
        #expect(
            transport.requests.map(\.url?.path) == [
                "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                "/auth/usage",
            ])
    }

    @Test("maps 401 to unauthorized")
    func unauthorized() async {
        let transport = StubTransport(status: 401, body: "{}")
        await #expect(throws: LimitsError.unauthorized) {
            try await CursorLimitsClient(transport: transport).fetchUsage(token: "tok")
        }
    }
}

// MARK: - Source

@Suite("Cursor usage source")
struct CursorUsageSourceTests {

    @Test("is not installed when the Cursor support directory is missing")
    func notInstalled() {
        let source = CursorUsageSource(
            supportDirectory: URL(fileURLWithPath: "/tmp/ration-no-cursor-\(UUID().uuidString)"),
            store: CursorSessionStore(
                databaseURL: URL(fileURLWithPath: "/tmp/ration-no-cursor.vscdb")),
            client: CursorLimitsClient(transport: StubTransport(status: 500, body: "")))
        #expect(source.availability() == .notInstalled)
        #expect(!source.promptsForPermission)
    }

    @Test("reports noData when Cursor is installed but has no session")
    func signedOut() throws {
        let support = FileManager.default.temporaryDirectory
            .appending(path: "ration-cursor-support-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let source = CursorUsageSource(
            supportDirectory: support,
            store: CursorSessionStore(databaseURL: try makeStateDB(token: nil, plan: nil)),
            client: CursorLimitsClient(transport: StubTransport(status: 500, body: "")))
        #expect(source.availability() == .noData(reason: "Sign in to Cursor first."))
    }

    @Test("fetches a snapshot with the plan name from local state")
    func fetchAttachesPlan() async throws {
        let support = FileManager.default.temporaryDirectory
            .appending(path: "ration-cursor-support-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let body = String(data: try fixture("cursor_period"), encoding: .utf8)!
        let source = CursorUsageSource(
            supportDirectory: support,
            store: CursorSessionStore(databaseURL: try makeStateDB(token: "tok-live", plan: "pro")),
            client: CursorLimitsClient(transport: StubTransport(status: 200, body: body)))

        #expect(source.availability() == .ready)
        let snapshot = try await source.fetchUsage()
        #expect(snapshot.planName == "pro")
        #expect(snapshot.limits.contains { $0.kind.rawValue == "monthly" })
    }
}

// MARK: - sqlite fixture

private func makeStateDB(token: String?, plan: String?) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ration-cursor-\(UUID().uuidString).vscdb")
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
        throw CursorSessionStore.Error.malformed
    }
    defer { sqlite3_close(db) }

    guard
        sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT, value TEXT);", nil, nil, nil)
            == SQLITE_OK
    else {
        throw CursorSessionStore.Error.malformed
    }

    func insert(_ key: String, _ value: String) {
        let sql = "INSERT INTO ItemTable (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    if let token { insert("cursorAuth/accessToken", token) }
    if let plan { insert("cursorAuth/stripeMembershipType", plan) }
    return url
}
