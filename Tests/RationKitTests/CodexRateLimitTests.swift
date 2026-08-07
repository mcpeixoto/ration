import Foundation
import Testing

@testable import RationKit

private let stamp = Date(timeIntervalSince1970: 1_786_000_000)

// Typed, because `#expect` infers a bare `5 * 3600` on the right of an `==` as
// `Int` and the comparison against a `TimeInterval?` then never holds.
private let fiveHours: TimeInterval = 5 * 3600
private let oneWeek: TimeInterval = 7 * 24 * 3600
private let twoWeeks: TimeInterval = 14 * 24 * 3600

private func payload(_ json: String) throws -> [String: Any] {
    try #require(
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

@Suite("Codex rate limits")
struct CodexRateLimitTests {

    /// Captured verbatim from a real rollout. Note that `primary` here is the
    /// *weekly* window and `secondary` is absent — the case that breaks any
    /// implementation which assumes primary means the short window.
    private let live = """
        {"rate_limits":{"limit_id":"codex","limit_name":null,\
        "primary":{"used_percent":45.0,"window_minutes":10080,"resets_at":1786162724},\
        "secondary":null,\
        "credits":{"has_credits":false,"unlimited":false,"balance":"0"},\
        "individual_limit":null,"spend_control_reached":null,\
        "plan_type":"plus","rate_limit_reached_type":null}}
        """

    @Test("reads the live shape, weekly-in-primary and all")
    func liveShape() throws {
        let snapshot = try #require(CodexRateLimits.snapshot(from: try payload(live), at: stamp))
        let limit = try #require(snapshot.limits.first)

        #expect(snapshot.limits.count == 1)
        #expect(limit.kind == .weeklyAll)
        #expect(limit.percent == 45)
        #expect(limit.windowLength == oneWeek)
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_786_162_724))
        #expect(snapshot.planName == "plus")
    }

    /// The whole point of `fetchedAt` for a file-backed provider: the numbers
    /// are as old as the record, not as new as the read.
    @Test("dates the snapshot from the record, not from now")
    func timestampComesFromTheRecord() throws {
        let snapshot = try #require(CodexRateLimits.snapshot(from: try payload(live), at: stamp))
        #expect(snapshot.fetchedAt == stamp)
    }

    /// `primary` and `secondary` name whichever limit is currently binding, and
    /// they swap between captures. Only the duration identifies the lane.
    @Test("identifies windows by duration, not by which slot they arrived in")
    func lanesComeFromDuration() throws {
        let swapped = """
            {"rate_limits":{\
            "primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1786085561},\
            "secondary":{"used_percent":49.0,"window_minutes":10080,"resets_at":1786569758},\
            "plan_type":"plus"}}
            """
        let snapshot = try #require(CodexRateLimits.snapshot(from: try payload(swapped), at: stamp))

        let session = try #require(snapshot.limits.first { $0.kind == .session })
        let weekly = try #require(snapshot.limits.first { $0.kind == .weeklyAll })

        #expect(session.percent == 2)
        #expect(session.windowLength == fiveHours)
        #expect(weekly.percent == 49)
        #expect(weekly.windowLength == oneWeek)
    }

    @Test("accepts the other builds' field names")
    func alternateSpelling() throws {
        let alternate = """
            {"rate_limits":{\
            "primary_window":{"used_percent":33,"limit_window_seconds":18000,\
            "reset_at":1786085561},"plan_type":"pro"}}
            """
        let snapshot = try #require(
            CodexRateLimits.snapshot(from: try payload(alternate), at: stamp))
        let limit = try #require(snapshot.limits.first)

        #expect(limit.kind == .session)
        #expect(limit.percent == 33)
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_786_085_561))
    }

    @Test("keeps a window nobody has a name for")
    func unknownWindow() throws {
        let fortnight = """
            {"rate_limits":{"primary":{"used_percent":10,"window_minutes":20160,\
            "resets_at":1786085561}}}
            """
        let snapshot = try #require(
            CodexRateLimits.snapshot(from: try payload(fortnight), at: stamp))
        let limit = try #require(snapshot.limits.first)

        #expect(limit.kind == .other("window_20160m"))
        #expect(limit.windowLength == twoWeeks)
    }

    /// A window Ration has never heard of still gets a projection, because the
    /// provider stated how long it is.
    @Test("projects an unrecognised window from its stated length")
    func unknownWindowStillProjects() throws {
        let now = Date()
        let limit = UsageLimit(
            kind: .other("window_20160m"), group: .other("window"), percent: 25,
            severity: .normal, resetsAt: now.addingTimeInterval(twoWeeks / 2),
            windowLength: twoWeeks)

        let projection = try #require(WindowProjection(limit: limit, now: now))
        #expect(projection.windowLength == twoWeeks)
        #expect(abs(projection.projectedPercent - 50) < 0.01)
    }

    @Test("still infers Claude's windows, which are not stated anywhere")
    func inferredWindowsStillWork() {
        #expect(WindowProjection.length(of: .session) == fiveHours)
        let stateless = UsageLimit(
            kind: .session, group: .session, percent: 10, severity: .normal, resetsAt: nil)
        #expect(WindowProjection.length(of: stateless) == fiveHours)
    }

    @Test("derives severity, since Codex reports none")
    func severityIsDerived() throws {
        let hot = """
            {"rate_limits":{"primary":{"used_percent":97,"window_minutes":300,\
            "resets_at":1786085561}}}
            """
        let snapshot = try #require(CodexRateLimits.snapshot(from: try payload(hot), at: stamp))
        #expect(snapshot.limits.first?.severity == .critical)
    }

    @Test("reports nothing rather than something empty")
    func noLimits() throws {
        #expect(CodexRateLimits.snapshot(from: try payload("{}"), at: stamp) == nil)
        #expect(
            CodexRateLimits.snapshot(
                from: try payload(#"{"rate_limits":{"plan_type":"plus"}}"#), at: stamp) == nil)
    }

    @Test("does not report a window with no percentage")
    func missingPercent() throws {
        let empty = #"{"rate_limits":{"primary":{"window_minutes":300}}}"#
        #expect(CodexRateLimits.snapshot(from: try payload(empty), at: stamp) == nil)
    }
}

// MARK: - Tail reading

@Suite("Codex quota tail read")
struct CodexTailReadTests {

    private func write(_ lines: [String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "rollout-2026-08-07T00-00-00-abc.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    private func record(percent: Double, at seconds: Int) -> String {
        """
        {"timestamp":"2026-08-07T10:00:0\(seconds)Z","type":"event_msg","payload":\
        {"type":"token_count","info":{},"rate_limits":{"primary":{"used_percent":\(percent),\
        "window_minutes":10080,"resets_at":1786162724},"plan_type":"plus"}}}
        """
    }

    @Test("takes the last record in the file, not the first")
    func lastWins() throws {
        let url = try write([record(percent: 10, at: 1), record(percent: 45, at: 9)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = try #require(CodexUsageSource.lastRateLimits(in: url))
        #expect(snapshot.limits.first?.percent == 45)
    }

    /// Seeking to a byte offset lands mid-line. That fragment must be skipped,
    /// not treated as corruption.
    @Test("survives a tail that begins mid-line")
    func partialFirstLine() throws {
        let filler = String(repeating: "x", count: CodexUsageSource.tailBytes)
        let url = try write([
            #"{"padding":"\#(filler)"}"#,
            record(percent: 45, at: 9),
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = try #require(CodexUsageSource.lastRateLimits(in: url))
        #expect(snapshot.limits.first?.percent == 45)
    }

    @Test("reports nothing for a file with no limits in it")
    func noLimitsInFile() throws {
        let url = try write([#"{"timestamp":"2026-08-07T10:00:00Z","type":"response_item"}"#])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(CodexUsageSource.lastRateLimits(in: url) == nil)
    }

    @Test("says it is not installed when there is no Codex directory")
    func notInstalled() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(CodexUsageSource(root: missing).availability() == .notInstalled)
    }

    @Test("distinguishes installed-but-empty from not installed")
    func installedButEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(
            CodexUsageSource(root: dir).availability() == .noData(reason: "No Codex sessions yet."))
    }
}
