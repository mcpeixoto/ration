import Foundation
import Testing

@testable import RationKit

@Suite("Poll schedule")
struct PollScheduleTests {

    let schedule = PollSchedule()

    @Test("polls at the idle interval when the popover is closed and healthy")
    func idleInterval() {
        #expect(schedule.delay(failures: 0, isMenuOpen: false, lastError: nil) == 60)
    }

    @Test("does not poll faster while the user is looking at the popover")
    func openInterval() {
        #expect(schedule.delay(failures: 0, isMenuOpen: true, lastError: nil) == 60)
    }

    @Test("backs off exponentially after failures")
    func exponentialBackoff() {
        let first = schedule.delay(
            failures: 1, isMenuOpen: false, lastError: .serverError(status: 500))
        let second = schedule.delay(
            failures: 2, isMenuOpen: false, lastError: .serverError(status: 500))
        let third = schedule.delay(
            failures: 3, isMenuOpen: false, lastError: .serverError(status: 500))

        #expect(first == 120)
        #expect(second == 240)
        #expect(third == 300)  // capped
    }

    @Test("backoff never exceeds five minutes")
    func backoffCap() {
        for failures in 1...20 {
            let delay = schedule.delay(
                failures: failures, isMenuOpen: false, lastError: .transport(message: "x"))
            #expect((delay ?? 0) <= 300)
        }
    }

    @Test("an open popover does not defeat backoff")
    func backoffWinsOverOpenMenu() {
        let delay = schedule.delay(
            failures: 3, isMenuOpen: true, lastError: .transport(message: "x"))
        #expect(delay == 300)
    }

    @Test("honours Retry-After when the server sends one")
    func retryAfterHonoured() {
        let delay = schedule.delay(
            failures: 1, isMenuOpen: false, lastError: .rateLimited(retryAfter: 180))
        #expect(delay == 180)
    }

    @Test("never polls faster than the floor, even if Retry-After is tiny")
    func retryAfterFloor() {
        let delay = schedule.delay(
            failures: 1, isMenuOpen: true, lastError: .rateLimited(retryAfter: 2))
        #expect(delay == PollSchedule.minimumInterval)
    }

    @Test("stops polling entirely once the token is rejected")
    func haltsOnUnauthorized() {
        #expect(schedule.delay(failures: 1, isMenuOpen: false, lastError: .unauthorized) == nil)
        #expect(schedule.delay(failures: 1, isMenuOpen: true, lastError: .unauthorized) == nil)
    }

    @Test("a user-chosen interval is clamped to the supported range")
    func clampsUserInterval() {
        #expect(PollSchedule(idleInterval: 1).idleInterval == PollSchedule.minimumInterval)
        #expect(PollSchedule(idleInterval: 99_999).idleInterval == PollSchedule.maximumInterval)
        #expect(PollSchedule(idleInterval: 120).idleInterval == 120)
    }

    @Test("a matching open interval stays at the idle pace")
    func matchingOpenDoesNotSpeedUp() {
        let even = PollSchedule(idleInterval: 120, openInterval: 120)
        #expect(even.delay(failures: 0, isMenuOpen: true, lastError: nil) == 120)
        #expect(even.delay(failures: 0, isMenuOpen: false, lastError: nil) == 120)
    }

    @Test("the open-popover interval never exceeds the idle interval")
    func openIsNeverSlowerThanIdle() {
        // A user who picks a 2-minute idle interval should not get slower
        // updates while actively watching the popover.
        let slow = PollSchedule(idleInterval: 120)
        let open = slow.delay(failures: 0, isMenuOpen: true, lastError: nil) ?? .infinity
        let closed = slow.delay(failures: 0, isMenuOpen: false, lastError: nil) ?? .infinity
        #expect(open <= closed)
    }
}

@Suite("Usage state transitions")
struct UsageStateTests {

    private func snapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(limits: [
            UsageLimit(
                kind: .session, group: .session, percent: percent,
                severity: .normal, resetsAt: nil, isActive: true)
        ])
    }

    @Test("starts with nothing loaded")
    func initialState() {
        let state = UsageState()
        #expect(state.snapshot == nil)
        #expect(state.status == .idle)
        #expect(state.consecutiveFailures == 0)
    }

    @Test("a successful refresh clears prior failures")
    func successResetsFailures() {
        var state = UsageState()
        state.recordFailure(.serverError(status: 500))
        state.recordFailure(.serverError(status: 500))
        #expect(state.consecutiveFailures == 2)

        state.recordSuccess(snapshot(percent: 10))
        #expect(state.consecutiveFailures == 0)
        #expect(state.status == .ready)
        #expect(state.snapshot?.limits.first?.percent == 10)
    }

    @Test("a failure keeps the last good snapshot on screen")
    func failureKeepsStaleData() {
        var state = UsageState()
        state.recordSuccess(snapshot(percent: 42))
        state.recordFailure(.transport(message: "offline"))

        #expect(state.snapshot?.limits.first?.percent == 42)
        #expect(state.status == .failed(.transport(message: "offline")))
        #expect(state.isStale)
    }

    @Test("fresh data is not stale")
    func freshIsNotStale() {
        var state = UsageState()
        state.recordSuccess(snapshot(percent: 42))
        #expect(!state.isStale)
    }

    @Test("an unauthorized failure signs the user out and drops stale data")
    func unauthorizedSignsOut() {
        var state = UsageState()
        state.recordSuccess(snapshot(percent: 42))
        state.recordFailure(.unauthorized)

        #expect(state.status == .signedOut)
        // Showing a percentage we can no longer verify would be a lie.
        #expect(state.snapshot == nil)
    }

    @Test("a missing credential signs the user out")
    func missingCredentialSignsOut() {
        var state = UsageState()
        state.recordCredentialFailure(.notFound)
        #expect(state.status == .signedOut)
    }

    @Test("refreshing does not blank the current snapshot")
    func refreshingKeepsData() {
        var state = UsageState()
        state.recordSuccess(snapshot(percent: 42))
        state.beginRefresh()

        #expect(state.status == .refreshing)
        #expect(state.snapshot?.limits.first?.percent == 42)
    }
}
