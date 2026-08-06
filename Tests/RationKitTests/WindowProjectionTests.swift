import Foundation
import Testing

@testable import RationKit

private let week: TimeInterval = 7 * 24 * 3600
private let session: TimeInterval = 5 * 3600

private func weekly(percent: Double, remaining: TimeInterval, now: Date) -> UsageLimit {
    UsageLimit(
        kind: .weeklyAll, group: .weekly, percent: percent, severity: .normal,
        resetsAt: now.addingTimeInterval(remaining))
}

@Suite("Window projection")
struct WindowProjectionTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("extrapolates the current rate to the end of the window")
    func extrapolates() throws {
        // Half the week gone, half the allowance used — lands exactly at 100%.
        let projection = try #require(
            WindowProjection(limit: weekly(percent: 50, remaining: week / 2, now: now), now: now))

        #expect(abs(projection.projectedPercent - 100) < 0.01)
        #expect(abs(projection.elapsedFraction - 0.5) < 0.01)
        #expect(abs(projection.pace - 1.0) < 0.01)
    }

    @Test("a comfortable pace projects under the limit and does not warn")
    func comfortablePace() throws {
        // Half the week gone, a quarter used.
        let projection = try #require(
            WindowProjection(limit: weekly(percent: 25, remaining: week / 2, now: now), now: now))

        #expect(abs(projection.projectedPercent - 50) < 0.01)
        #expect(!projection.willExceed)
        #expect(projection.exhaustedAt == nil)
        #expect(projection.severity == .normal)
        #expect(projection.verdict(now: now).contains("On track"))
    }

    @Test("a heavy pace predicts when the allowance runs out")
    func heavyPace() throws {
        // A quarter of the week gone, half the allowance used: double pace.
        let projection = try #require(
            WindowProjection(
                limit: weekly(percent: 50, remaining: week * 0.75, now: now), now: now))

        #expect(abs(projection.projectedPercent - 200) < 0.01)
        #expect(abs(projection.pace - 2.0) < 0.01)
        #expect(projection.willExceed)

        // At 2× pace, the remaining 50% lasts as long as the first 50% did.
        let exhausted = try #require(projection.exhaustedAt)
        #expect(abs(exhausted.timeIntervalSince(now) - week * 0.25) < 60)
        #expect(projection.severity == .critical)
        #expect(projection.verdict(now: now).contains("run out"))
    }

    @Test("warns before it is certain, once the projection nears the limit")
    func warnsNearTheLimit() throws {
        // Projects to ~95%: not going to run out, but close enough to say so.
        let projection = try #require(
            WindowProjection(limit: weekly(percent: 47.5, remaining: week / 2, now: now), now: now))

        #expect(!projection.willExceed)
        #expect(projection.severity == .warning)
    }

    @Test("an already-exhausted limit reports as reached")
    func alreadyExhausted() throws {
        let projection = try #require(
            WindowProjection(limit: weekly(percent: 100, remaining: week / 2, now: now), now: now))

        #expect(projection.severity == .critical)
        #expect(projection.verdict(now: now) == "Limit reached")
    }

    @Test("knows the session window is five hours")
    func sessionWindow() throws {
        let limit = UsageLimit(
            kind: .session, group: .session, percent: 40, severity: .normal,
            resetsAt: now.addingTimeInterval(session / 2))
        let projection = try #require(WindowProjection(limit: limit, now: now))

        #expect(projection.windowLength == session)
        #expect(abs(projection.projectedPercent - 80) < 0.01)
    }

    @Test("declines to project a limit kind whose window length is unknown")
    func unknownWindow() {
        let limit = UsageLimit(
            kind: .other("monthly_quantum_flux"), group: .other("monthly"),
            percent: 40, severity: .normal, resetsAt: now.addingTimeInterval(3600))
        #expect(WindowProjection(limit: limit, now: now) == nil)
    }

    @Test("declines when there is no reset time to measure against")
    func noResetTime() {
        let limit = UsageLimit(
            kind: .weeklyAll, group: .weekly, percent: 40, severity: .normal, resetsAt: nil)
        #expect(WindowProjection(limit: limit, now: now) == nil)
    }

    @Test("declines just after a reset, when one burst would extrapolate absurdly")
    func tooEarlyToProject() {
        // Only 1% of the window has elapsed.
        let limit = weekly(percent: 3, remaining: week * 0.99, now: now)
        #expect(WindowProjection(limit: limit, now: now) == nil)
    }

    @Test("declines once the window has already rolled over")
    func windowPassed() {
        let limit = weekly(percent: 40, remaining: -60, now: now)
        #expect(WindowProjection(limit: limit, now: now) == nil)
    }

    @Test("zero usage projects zero rather than dividing by nothing")
    func zeroUsage() throws {
        let projection = try #require(
            WindowProjection(limit: weekly(percent: 0, remaining: week / 2, now: now), now: now))

        #expect(projection.projectedPercent == 0)
        #expect(!projection.willExceed)
        #expect(projection.pace == 0)
    }
}

@Suite("Window curve")
struct WindowCurveTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func projection() -> WindowProjection {
        WindowProjection(limit: weekly(percent: 60, remaining: week / 2, now: now), now: now)!
    }

    @Test("falls back to a straight line when there is no local history")
    func straightLineFallback() {
        let curve = UsageHistory().windowCurve(for: projection(), now: now, buckets: 10)

        #expect(curve.count == 11)
        #expect(curve.first?.percent == 0)
        #expect(abs((curve.last?.percent ?? 0) - 60) < 0.01)
    }

    @Test("the curve always ends at the authoritative percentage")
    func endsAtReportedPercent() {
        var history = UsageHistory()
        let calendar = Calendar.current
        // Some real activity inside the window.
        for offset in 0..<4 {
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            history.add([
                UsageEvent(
                    timestamp: date, model: "claude-opus-5", project: "p", sessionID: "s",
                    inputTokens: 100, outputTokens: 1000 * (offset + 1), cacheReadTokens: 0)
            ])
        }

        let curve = history.windowCurve(for: projection(), now: now, buckets: 12)
        // However the shape falls, the endpoint is the number Anthropic gave us.
        #expect(abs((curve.last?.percent ?? 0) - 60) < 0.5)
    }

    @Test("the curve never goes backwards")
    func monotonic() {
        var history = UsageHistory()
        let calendar = Calendar.current
        for offset in 0..<4 {
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            history.add([
                UsageEvent(
                    timestamp: date, model: "claude-opus-5", project: "p", sessionID: "s",
                    inputTokens: 10, outputTokens: 500, cacheReadTokens: 0)
            ])
        }

        let curve = history.windowCurve(for: projection(), now: now, buckets: 12)
        for (earlier, later) in zip(curve, curve.dropFirst()) {
            #expect(later.percent >= earlier.percent - 0.001)
            #expect(later.date > earlier.date)
        }
    }
}
