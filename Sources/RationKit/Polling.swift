import Foundation

// MARK: - Schedule

/// Decides how long to wait before the next refresh.
///
/// Pure and synchronous so the policy can be tested without waiting for real
/// time to pass; `UsagePoller` supplies the clock.
public struct PollSchedule: Sendable, Equatable {

    /// The fastest Ration will ever poll.
    ///
    /// This is a hard floor, not a default. The endpoint is an undocumented
    /// convenience for the user's own account, and hammering it would be a bad
    /// citizen move that risks it being locked down for everyone.
    public static let minimumInterval: TimeInterval = 30
    public static let maximumInterval: TimeInterval = 300

    /// Ceiling for exponential backoff after repeated failures.
    public static let maximumBackoff: TimeInterval = 300

    /// How often to refresh while the popover is closed.
    public let idleInterval: TimeInterval
    /// How often to refresh while the user has the popover open.
    public let openInterval: TimeInterval

    public init(idleInterval: TimeInterval = 60, openInterval: TimeInterval = 10) {
        let clampedIdle = min(max(idleInterval, Self.minimumInterval), Self.maximumInterval)
        self.idleInterval = clampedIdle
        // Watching the popover should never be slower than not watching it.
        self.openInterval = min(max(openInterval, 0), clampedIdle)
    }

    /// Seconds until the next poll, or `nil` to stop polling altogether.
    public func delay(
        failures: Int,
        isMenuOpen: Bool,
        lastError: LimitsError?
    ) -> TimeInterval? {
        // An expired token will not recover on its own. Stop, and let the app
        // show a sign-in prompt instead of burning requests that all 401.
        if lastError == .unauthorized { return nil }

        // The server told us exactly how long to wait. Believe it.
        if case .rateLimited(let retryAfter) = lastError, let retryAfter {
            return max(retryAfter, Self.minimumInterval)
        }

        guard failures > 0 else {
            let base = isMenuOpen ? openInterval : idleInterval
            return max(base, isMenuOpen ? 0 : Self.minimumInterval)
        }

        // Exponential backoff from the idle interval, regardless of whether the
        // popover is open: a struggling server should not be polled harder just
        // because someone is watching.
        let backoff = idleInterval * pow(2, Double(failures))
        return min(backoff, Self.maximumBackoff)
    }
}

// MARK: - State

/// Everything the UI needs to render, in one value.
public struct UsageState: Sendable, Equatable {

    public enum Status: Sendable, Equatable {
        /// Nothing fetched yet.
        case idle
        case refreshing
        case ready
        /// A retryable failure. `snapshot` may still hold usable, older data.
        case failed(LimitsError)
        /// No usable credential. Only Claude Code can fix this.
        case signedOut
    }

    public private(set) var snapshot: UsageSnapshot?
    public private(set) var status: Status = .idle
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var lastError: LimitsError?
    /// Set when the credential itself is the problem, for a better message.
    public private(set) var credentialError: CredentialError?

    public init() {}

    /// Whether the displayed numbers are known to be out of date.
    public var isStale: Bool {
        snapshot != nil && consecutiveFailures > 0
    }

    public mutating func beginRefresh() {
        // Deliberately keeps `snapshot`: blanking the popover on every tick
        // would make the UI flicker once a minute.
        status = .refreshing
    }

    public mutating func recordSuccess(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        status = .ready
        consecutiveFailures = 0
        lastError = nil
        credentialError = nil
    }

    public mutating func recordFailure(_ error: LimitsError) {
        lastError = error
        consecutiveFailures += 1

        if error == .unauthorized {
            // Showing a percentage we can no longer verify would be misleading,
            // so the stale snapshot goes with the session.
            snapshot = nil
            status = .signedOut
        } else {
            status = .failed(error)
        }
    }

    public mutating func recordCredentialFailure(_ error: CredentialError) {
        credentialError = error
        consecutiveFailures += 1
        snapshot = nil
        status = .signedOut
    }
}
