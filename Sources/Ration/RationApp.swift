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
                registry: appDelegate.registry,
                settings: appDelegate.settings,
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
            MenuBarLabel(strip: appDelegate.presentation)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appDelegate.settings.pollInterval) { _, _ in
            appDelegate.registry.updateSchedule(appDelegate.settings.schedule)
        }
        .onChange(of: appDelegate.settings.primaryProvider) { _, provider in
            appDelegate.registry.primary = provider
        }
        .onChange(of: appDelegate.registry.primary) { _, provider in
            // Only while the registry actually has a menu bar to hand to
            // someone. With every account hidden it falls back to a provider
            // the user never chose, and persisting that would quietly overwrite
            // the choice they did make — re-enabling later would land them on
            // Claude with no record they had ever picked anything else.
            guard appDelegate.registry.primaryEntry != nil else { return }
            appDelegate.settings.primaryProvider = provider
        }

        Settings {
            SettingsView(
                settings: appDelegate.settings,
                registry: appDelegate.registry,
                updater: appDelegate.updater)
        }
    }
}

/// Owns the long-lived objects and bridges AppKit lifecycle events into
/// `RationKit`, which deliberately knows nothing about AppKit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    let settings = Settings()
    let registry: ProviderRegistry
    let updater = UpdateController()
    private let notifier = Notifier()

    private var onboardingWindow: NSWindow?

    override init() {
        self.registry = ProviderRegistry.standard(
            schedule: settings.schedule,
            disabled: settings.disabledProviders)
        super.init()
        registry.primary = settings.primaryProvider
    }

    /// What the menu bar item should look like right now.
    ///
    /// Every account that is on, in registry order. A single account keeps the
    /// original gauge; two or more sit side by side, each with its own symbol.
    var presentation: MenuBarStrip {
        MenuBarStrip.make(
            accounts: registry.metered.map {
                ($0.provider, $0.poller.state, $0.poller.promptsForPermission)
            },
            mode: settings.displayMode,
            useSeverityColor: settings.useSeverityColor,
            showWeeklyBar: settings.showWeeklyBar,
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            isEverythingHidden: registry.isEverythingHidden
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // On by default, once. A gauge that is not running warns nobody.
        settings.applyLoginItemDefaultIfNeeded()

        for entry in registry.entries {
            let provider = entry.provider
            entry.poller.onStateChange = { [weak self] state in
                guard let self, let snapshot = state.snapshot else { return }
                Task {
                    await self.notifier.handle(
                        snapshot, from: provider, enabled: self.settings.notifyOnThresholds)
                }
            }
        }

        observeSleepAndWake()

        // The first keychain read triggers a system permission prompt. Explain
        // it before it appears, rather than after. Providers read from the
        // user's own files start regardless — they ask nobody for anything.
        registry.start(allowingPrompts: settings.hasCompletedOnboarding)
        if !settings.hasCompletedOnboarding { showOnboarding() }
    }

    // MARK: Sleep and wake

    /// A laptop in a bag should not wake to make network calls, and the numbers
    /// on screen after a wake are stale by definition.
    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.registry.suspend() }
        }

        center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.registry.resume() }
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
        registry.start(allowingPrompts: true)
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
