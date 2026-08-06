import AppKit
import RationKit
import RationUI
import SwiftUI

@main
struct RationApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                poller: appDelegate.poller,
                settings: appDelegate.settings,
                transcripts: appDelegate.transcripts,
                openSettings: {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                },
                startSetup: { appDelegate.showOnboarding() },
                quit: { NSApp.terminate(nil) }
            )
        } label: {
            // Computed rather than cached: `poller` and `settings` are
            // @Observable, so SwiftUI re-evaluates this when either changes and
            // a settings change is reflected without waiting for the next poll.
            MenuBarLabel(presentation: appDelegate.presentation)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appDelegate.settings.pollInterval) { _, _ in
            appDelegate.poller.updateSchedule(appDelegate.settings.schedule)
        }

        Settings {
            SettingsView(settings: appDelegate.settings, updater: appDelegate.updater)
        }
    }
}

/// Owns the long-lived objects and bridges AppKit lifecycle events into
/// `RationKit`, which deliberately knows nothing about AppKit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    let settings = Settings()
    let poller: UsagePoller
    let transcripts = TranscriptStore()
    let updater = UpdateController()
    private let notifier = Notifier()

    private var onboardingWindow: NSWindow?

    override init() {
        self.poller = UsagePoller(schedule: settings.schedule)
        super.init()
    }

    /// What the menu bar item should look like right now.
    var presentation: MenuBarPresentation {
        guard settings.hasCompletedOnboarding else { return .setupRequired }
        return MenuBarPresentation.make(
            state: poller.state,
            mode: settings.displayMode,
            useSeverityColor: settings.useSeverityColor,
            showWeeklyBar: settings.showWeeklyBar
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        poller.onStateChange = { [weak self] state in
            guard let self else { return }
            if let snapshot = state.snapshot {
                Task {
                    await self.notifier.handle(snapshot, enabled: self.settings.notifyOnThresholds)
                }
            }
        }

        observeSleepAndWake()

        // The first keychain read triggers a system permission prompt. Explain
        // it before it appears, rather than after.
        if settings.hasCompletedOnboarding {
            poller.start()
            startHistory()
        } else {
            showOnboarding()
        }
    }

    // MARK: Sleep and wake

    /// A laptop in a bag should not wake to make network calls, and the numbers
    /// on screen after a wake are stale by definition.
    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poller.suspend() }
        }

        center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poller.resume() }
        }
    }

    // MARK: Onboarding

    func showOnboarding() {
        // Already open — just bring it forward.
        if let existing = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView { [weak self] in
            self?.completeOnboarding()
        }

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Ration"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Centre after the hosting controller has sized the window, otherwise
        // it centres a zero-size frame and lands off to one side.
        window.setContentSize(controller.view.fittingSize)
        window.center()

        // Temporarily a regular app so the window can take focus and appear in
        // the app switcher; reverted once onboarding is done.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
    }

    private func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        onboardingWindow?.close()
        poller.start()
        startHistory()
    }

    /// Loads the cached history immediately, then scans for anything new.
    /// Reading transcripts needs no permission — they are the user's own files
    /// in their own home directory.
    private func startHistory() {
        transcripts.loadCheckpoint()
        transcripts.refresh()
    }
}

// MARK: - Onboarding window lifecycle

extension AppDelegate: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === onboardingWindow else { return }
        onboardingWindow = nil
        // Back to a menu-bar-only app.
        NSApp.setActivationPolicy(.accessory)

        // Dismissing without agreeing is a valid answer: do not read the
        // keychain. The popover offers a way back in.
    }
}
