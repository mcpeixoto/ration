import Foundation
import Testing

@testable import RationKit

// MARK: - Doubles

private struct FakeCredentialStore: CredentialStore {
    var result: Result<Credential, CredentialError>

    static func valid() -> FakeCredentialStore {
        FakeCredentialStore(
            result: .success(
                Credential(
                    accessToken: "token",
                    expiresAt: Date(timeIntervalSinceNow: 3600),
                    subscriptionType: "max",
                    rateLimitTier: "default_claude_max_5x")))
    }

    static func expired() -> FakeCredentialStore {
        FakeCredentialStore(
            result: .success(
                Credential(
                    accessToken: "token",
                    expiresAt: Date(timeIntervalSinceNow: -1),
                    subscriptionType: "max",
                    rateLimitTier: nil)))
    }

    func credential() throws -> Credential {
        try result.get()
    }
}

private final class FakeLimitsClient: LimitsClient, @unchecked Sendable {
    var results: [Result<UsageSnapshot, LimitsError>]
    private(set) var callCount = 0
    private(set) var tokensSeen: [String] = []

    init(results: [Result<UsageSnapshot, LimitsError>]) {
        self.results = results
    }

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        tokensSeen.append(token)
        let result = results[min(callCount, results.count - 1)]
        callCount += 1
        return try result.get()
    }
}

private func snapshot(_ percent: Double) -> UsageSnapshot {
    UsageSnapshot(limits: [
        UsageLimit(
            kind: .session, group: .session, percent: percent,
            severity: .normal, resetsAt: nil, isActive: true)
    ])
}

/// Lets the poller's `Task` run to its first suspension without racing on
/// wall-clock time.
///
/// Generously over-yields on purpose. How many scheduler hops one refresh costs
/// depends on how deep the `UsageSource` behind the poller is — a source that
/// reads a file suspends a different number of times from one that awaits a
/// request — and that is not something these tests should be pinning. Yields
/// are free; a count tuned to today's call depth is a trap for the next change.
@MainActor
private func settle(untilReady poller: UsagePoller, fromReady: Bool = false) async {
    let deadline = Date().addingTimeInterval(5)
    if fromReady {
        while Date() < deadline && poller.state.status != .refreshing {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
    while Date() < deadline {
        switch poller.state.status {
        case .refreshing, .idle:
            try? await Task.sleep(for: .milliseconds(25))
        default:
            return
        }
    }
}

// MARK: - Tests

@Suite("UsagePoller")
@MainActor
struct UsagePollerTests {

    @Test("fetches on start and publishes the snapshot")
    func fetchesOnStart() async {
        let client = FakeLimitsClient(results: [.success(snapshot(42))])
        let poller = UsagePoller(
            credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()

        #expect(client.callCount >= 1)
        #expect(poller.state.snapshot?.limits.first?.percent == 42)
        #expect(poller.state.status == .ready)
    }

    @Test("passes the keychain token through to the client")
    func usesCredentialToken() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()

        #expect(client.tokensSeen.first == "token")
    }

    @Test("signs out when there is no credential, without calling the API")
    func noCredential() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(
            credentialStore: FakeCredentialStore(result: .failure(.notFound)), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()

        #expect(poller.state.status == .signedOut)
        #expect(client.callCount == 0, "should not call the API without a credential")
    }

    @Test("does not spend a request on a token it knows is expired")
    func expiredCredentialShortCircuits() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.expired(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()

        #expect(client.callCount == 0)
        #expect(poller.state.status == .signedOut)
    }

    @Test("keeps the last good numbers when a refresh fails")
    func keepsStaleDataOnFailure() async {
        let client = FakeLimitsClient(results: [
            .success(snapshot(42)),
            .failure(.transport(message: "offline")),
        ])
        let poller = UsagePoller(
            credentialStore: FakeCredentialStore.valid(), client: client,
            schedule: PollSchedule(idleInterval: 30, openInterval: 0))

        poller.start()
        await settle(untilReady: poller)
        poller.refreshNow()
        await settle(untilReady: poller, fromReady: true)
        poller.suspend()

        #expect(poller.state.snapshot?.limits.first?.percent == 42)
        #expect(poller.state.isStale)
    }

    @Test("drops the snapshot when the session expires, rather than showing a stale percentage")
    func unauthorizedClearsSnapshot() async {
        let client = FakeLimitsClient(results: [
            .success(snapshot(42)),
            .failure(.unauthorized),
        ])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.refreshNow()
        await settle(untilReady: poller, fromReady: true)
        poller.suspend()

        #expect(poller.state.status == .signedOut)
        #expect(poller.state.snapshot == nil)
    }

    @Test("suspend stops the loop")
    func suspendStops() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()
        let countAfterSuspend = client.callCount

        await settle(untilReady: poller)
        #expect(client.callCount == countAfterSuspend)
        #expect(!poller.isRunning)
    }

    @Test("resume refreshes immediately, because post-sleep data is always stale")
    func resumeRefreshes() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()
        let before = client.callCount

        poller.resume()
        await settle(untilReady: poller, fromReady: true)
        poller.suspend()

        #expect(client.callCount > before)
    }

    @Test("opening the popover triggers an immediate refresh")
    func openingMenuRefreshes() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        let before = client.callCount

        poller.setMenuOpen(true)
        await settle(untilReady: poller, fromReady: true)
        poller.suspend()

        #expect(client.callCount > before)
    }

    @Test("closing the popover does not spend an extra request")
    func closingMenuDoesNotRefresh() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        await settle(untilReady: poller)
        poller.setMenuOpen(true)
        await settle(untilReady: poller)
        let before = client.callCount

        poller.setMenuOpen(false)
        await settle(untilReady: poller)
        poller.suspend()

        #expect(client.callCount == before)
    }

    @Test("start is idempotent")
    func startIsIdempotent() async {
        let client = FakeLimitsClient(results: [.success(snapshot(1))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        poller.start()
        poller.start()
        await settle(untilReady: poller)
        poller.suspend()

        #expect(client.callCount == 1)
    }

    @Test("reports every state change so the app can raise notifications")
    func reportsStateChanges() async {
        let client = FakeLimitsClient(results: [.success(snapshot(96))])
        let poller = UsagePoller(credentialStore: FakeCredentialStore.valid(), client: client)

        var observed: [UsageState.Status] = []
        poller.onStateChange = { (state: UsageState) in observed.append(state.status) }

        poller.start()
        await settle(untilReady: poller)
        poller.suspend()

        #expect(observed.contains(.ready))
    }
}

// MARK: - Forgetting

/// Counts how many times the underlying store was actually consulted, so a
/// test can tell a cache hit from a real read.
private final class CountingCredentialStore: CredentialStore, @unchecked Sendable {

    private let lock = NSLock()
    private var count = 0

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func credential() throws -> Credential {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return Credential(
            accessToken: "token",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            subscriptionType: "max",
            rateLimitTier: nil)
    }
}

@Suite("Forgetting a source")
struct SourceForgetTests {

    @Test("a cached credential is served without re-reading the store")
    func cachesBetweenReads() throws {
        let counting = CountingCredentialStore()
        let caching = CachingCredentialStore(wrapping: counting)

        _ = try caching.credential()
        _ = try caching.credential()

        #expect(counting.reads == 1)
    }

    @Test("forgetting drops the cached credential, so the next read hits the store")
    func forgetInvalidatesCache() throws {
        let counting = CountingCredentialStore()
        let caching = CachingCredentialStore(wrapping: counting)
        let source = AnthropicUsageSource(credentialStore: caching)

        _ = try caching.credential()
        #expect(counting.reads == 1)

        source.forget()
        _ = try caching.credential()

        #expect(counting.reads == 2)
    }

}
