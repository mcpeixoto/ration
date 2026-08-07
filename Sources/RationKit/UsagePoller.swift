import Foundation
import Observation

/// Drives refreshes and publishes the result.
///
/// Deliberately knows nothing about AppKit or SwiftUI. Sleep/wake handling
/// lives in the app layer and reaches this type through `suspend()`/`resume()`,
/// which keeps the polling logic testable without a running app.
@MainActor
@Observable
public final class UsagePoller {

    public private(set) var state = UsageState()
    public private(set) var isRunning = false

    /// The plan tier (`max`, `plus`, …), for display only. Never sent anywhere.
    /// Kept across a failed refresh so the capsule does not flicker.
    public private(set) var planName: String?

    /// Which tool this poller is metering.
    public var provider: Provider { source.provider }

    /// Whether starting this poller can raise a system permission dialog.
    public var promptsForPermission: Bool { source.promptsForPermission }

    /// Whether this provider has anything to poll for. Re-read on every refresh,
    /// so a tool installed while Ration is running is picked up.
    public private(set) var availability: ProviderAvailability = .ready

    /// How often to re-check after the session has expired, in case Claude Code
    /// has refreshed the token in the meantime. Slow on purpose: every attempt
    /// while signed out is a request we expect to fail.
    public static let recoveryInterval: TimeInterval = 300

    private let source: any UsageSource
    private var schedule: PollSchedule
    private var isMenuOpen = false
    private var loop: Task<Void, Never>?

    /// Called after every state change, so the app can raise notifications.
    /// Set before `start()`.
    public var onStateChange: (@MainActor (UsageState) -> Void)?

    public init(source: any UsageSource, schedule: PollSchedule = PollSchedule()) {
        self.source = source
        self.schedule = schedule
        self.availability = source.availability()
    }

    /// Claude, assembled from its parts. Kept as its own initialiser because
    /// tests substitute the credential store and the client independently.
    public convenience init(
        credentialStore: any CredentialStore = CachingCredentialStore(),
        client: any LimitsClient = AnthropicLimitsClient(),
        schedule: PollSchedule = PollSchedule()
    ) {
        self.init(
            source: AnthropicUsageSource(credentialStore: credentialStore, client: client),
            schedule: schedule)
    }

    // No `deinit` cancellation: `deinit` is nonisolated and cannot touch
    // main-actor state. The loop captures `self` weakly and exits on its next
    // wake once the poller is gone, so nothing leaks. Callers that want the
    // loop torn down promptly should call `suspend()`.

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        restart(refreshImmediately: true)
    }

    /// Stops polling. Used when the machine sleeps — a laptop in a bag should
    /// not be waking to make network calls.
    public func suspend() {
        loop?.cancel()
        loop = nil
        isRunning = false
    }

    /// Resumes after sleep with an immediate refresh, because whatever is on
    /// screen is by definition out of date.
    public func resume() {
        guard !isRunning else { return }
        isRunning = true
        restart(refreshImmediately: true)
    }

    /// The popover opened or closed. Open means faster polling and an immediate
    /// refresh, so the numbers are current the moment they are looked at.
    public func setMenuOpen(_ open: Bool) {
        guard open != isMenuOpen else { return }
        isMenuOpen = open
        guard isRunning else { return }
        restart(refreshImmediately: open)
    }

    public func updateSchedule(_ new: PollSchedule) {
        guard new != schedule else { return }
        schedule = new
        guard isRunning else { return }
        restart(refreshImmediately: false)
    }

    /// Refresh now, e.g. from a "Refresh" menu item.
    public func refreshNow() {
        guard isRunning else { return }
        restart(refreshImmediately: true)
    }

    // MARK: The loop

    private func restart(refreshImmediately: Bool) {
        loop?.cancel()
        loop = Task { [weak self] in
            guard let self else { return }

            if !refreshImmediately {
                guard await self.sleepUntilNextPoll() else { return }
            }

            while !Task.isCancelled {
                await self.refresh()
                guard await self.sleepUntilNextPoll() else { return }
            }
        }
    }

    /// Waits for the scheduled delay. Returns `false` if the task was cancelled.
    private func sleepUntilNextPoll() async -> Bool {
        let delay =
            schedule.delay(
                failures: state.consecutiveFailures,
                isMenuOpen: isMenuOpen,
                lastError: state.lastError
            ) ?? Self.recoveryInterval

        do {
            try await Task.sleep(for: .seconds(delay))
            return true
        } catch {
            return false  // cancelled
        }
    }

    private func refresh() async {
        state.beginRefresh()
        availability = source.availability()

        do {
            let snapshot = try await source.fetchUsage()
            // Only overwrite a known plan with another known one: a provider
            // that reports usage but not tier should not blank the capsule.
            planName = snapshot.planName ?? planName
            state.recordSuccess(snapshot)
        } catch let error as CredentialError {
            state.recordCredentialFailure(error)
        } catch let error as LimitsError {
            state.recordFailure(error)
        } catch {
            state.recordFailure(.transport(message: error.localizedDescription))
        }

        onStateChange?(state)
    }
}
