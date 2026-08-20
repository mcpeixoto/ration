import CLinuxTray
import Dispatch
import Foundation
import RationKit

/// Owns everything the tray needs: the providers being polled, the icon in the
/// panel, the menu behind it, and the panel window.
///
/// The macOS app hangs the same objects off a `MenuBarExtra` scene. Here the
/// lifetime is explicit because there is no scene to hold them.
@MainActor
final class TrayApp {

    private(set) var config: AppConfig
    let registry: ProviderRegistry
    private var icon: TrayIcon?
    private var menu: Widget?
    private lazy var panel = Panel(app: self)
    private lazy var settingsWindow = SettingsWindow(app: self)
    private let notifier = TrayNotifier()

    /// The strip last drawn, so an unchanged frame does not rewrite the PNG
    /// and make the shell reload it.
    private var lastStrip: MenuBarStrip?
    private var lastPalette: Palette?
    private var openPanelItem: Widget?

    init() {
        config = AppConfig.load()
        registry = ProviderRegistry.standard(
            schedule: config.schedule, disabled: config.disabled)
        registry.primary = config.primaryProvider
    }

    // MARK: Lifecycle

    func start() {
        icon = TrayIcon(title: "Ration")
        buildMenu()

        // Onboarding gates only the provider whose first read raises a system
        // prompt; everything else reads files the user already owns.
        registry.start(allowingPrompts: config.hasCompletedOnboarding)
        if !config.hasCompletedOnboarding {
            OnboardingWindow.presentIfNeeded(app: self)
        }

        tick()
        scheduleTick()
    }

    /// One second, matching the macOS panel's timeline: reset countdowns tick
    /// while the panel is open and the icon follows every poll.
    private func scheduleTick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.tick()
            self?.scheduleTick()
        }
    }

    private func tick() {
        let palette = Palette.current()
        let strip = currentStrip()
        if strip != lastStrip || palette.isDark != lastPalette?.isDark {
            lastStrip = strip
            lastPalette = palette
            icon?.update(strip: strip, palette: palette)
            updateMenuSummary()
        }
        notifyIfNeeded()
        if panel.isOpen { panel.redraw() }
        if settingsWindow.isOpen { settingsWindow.redraw() }
    }

    // MARK: Menu

    /// The tray menu. A StatusNotifierItem has no click of its own to spend on
    /// the panel — the shell always opens the menu — so "Open Ration" is the
    /// first item and also the middle-click target.
    private func buildMenu() {
        let menu = gtk_menu_new()

        let open = gtk_menu_item_new_with_label("Open Ration")
        onSignal(open, "activate") { [weak self] in
            self?.panel.toggle()
        }
        gtk_menu_shell_append(menu, open)
        openPanelItem = open

        summaryItems = []
        for _ in 0..<3 {
            let item = gtk_menu_item_new_with_label("")
            gtk_menu_shell_append(menu, item)
            summaryItems.append(item)
        }

        gtk_menu_shell_append(menu, gtk_separator_menu_item_new())

        let refresh = gtk_menu_item_new_with_label("Refresh now")
        onSignal(refresh, "activate") { [weak self] in
            self?.refreshNow()
        }
        gtk_menu_shell_append(menu, refresh)

        let settings = gtk_menu_item_new_with_label("Settings…")
        onSignal(settings, "activate") { [weak self] in
            self?.openSettings()
        }
        gtk_menu_shell_append(menu, settings)

        gtk_menu_shell_append(menu, gtk_separator_menu_item_new())

        let quit = gtk_menu_item_new_with_label("Quit Ration")
        onSignal(quit, "activate") { [weak self] in
            self?.quit()
        }
        gtk_menu_shell_append(menu, quit)

        gtk_widget_show_all(menu)
        self.menu = menu
        icon?.attach(menu: menu)
        icon?.setPrimaryTarget(open)
    }

    private var summaryItems: [Widget?] = []

    /// Mirrors the tooltip the Mac shows on hover: every limit, one per line.
    /// A tray menu cannot hold a tooltip, so the lines become menu entries.
    private func updateMenuSummary() {
        let lines = summaryLines()
        for (index, item) in summaryItems.enumerated() {
            guard let item else { continue }
            if index < lines.count {
                gtk_menu_item_set_label(item, lines[index])
                gtk_widget_show(item)
            } else {
                gtk_widget_hide(item)
            }
        }
    }

    private func summaryLines() -> [String] {
        guard let entry = primaryEntry, let snapshot = entry.poller.state.snapshot else {
            return []
        }
        return snapshot.limits.prefix(3).map { limit in
            if let resets = limit.resetsAt {
                return
                    "\(limit.displayName): \(MenuBarPresentation.percentText(limit.percent)) · resets \(RelativeTime.short(until: resets))"
            }
            return "\(limit.displayName): \(MenuBarPresentation.percentText(limit.percent))"
        }
    }

    // MARK: Strip

    private func currentStrip() -> MenuBarStrip {
        MenuBarStrip.make(
            accounts: trayAccounts.map {
                ($0.provider, $0.poller.state, $0.poller.promptsForPermission)
            },
            mode: config.displayMode,
            useSeverityColor: config.useSeverityColor,
            showWeeklyBar: config.showWeeklyBar,
            hasCompletedOnboarding: config.hasCompletedOnboarding,
            isEverythingHidden: registry.isEverythingHidden)
    }

    private var trayAccounts: [ProviderRegistry.Entry] {
        registry.metered.filter {
            config.hasCompletedOnboarding || !$0.poller.promptsForPermission
        }
    }

    // MARK: Actions

    func openPanel() {
        panel.open()
    }

    /// Opens the panel on a named tab.
    func showPanel(on tab: PanelTab) {
        panel.tab = tab
        panel.open()
    }

    /// Renders every panel state to PNGs, without a window.
    ///
    /// The counterpart of `swift run RationPreview docs/images` on macOS: a way
    /// to look at what the panel actually draws, in every tab, without a
    /// display and without clicking through it by hand.
    func writeSnapshots(to directory: String) {
        let base = URL(fileURLWithPath: directory)
        for tab in PanelTab.allCases {
            panel.tab = tab
            panel.inspectedCreatureID = nil
            panel.revealQueue = []
            panel.resetOverlayScroll()
            panel.snapshot(to: base.appending(path: "panel-\(tab.rawValue).png").path)
        }

        // The two states that only appear over the binder. The reveal queue
        // is cleared first: drawing the binder refills it from whatever is
        // pending, and a queued card takes the screen ahead of the inspector.
        //
        // The rarest card is the interesting one to look at: it is the one
        // carrying foil, an ability, and the longest attack text.
        panel.tab = .collection
        if let creature = Dex.roster.max(by: { $0.rarity < $1.rarity }) {
            panel.revealQueue = []
            panel.inspectedCreatureID = creature.id
            panel.snapshot(to: base.appending(path: "panel-inspector.png").path)
            panel.inspectedCreatureID = nil
            panel.revealQueue = [creature]
            panel.snapshot(to: base.appending(path: "panel-catch.png").path)
            panel.revealQueue = []
        }
        print("Wrote panel snapshots to \(base.path)")
    }

    func openSettings(on section: SettingsWindow.Section? = nil) {
        panel.close()
        settingsWindow.open(on: section)
    }

    func refreshNow() {
        for entry in registry.metered {
            entry.poller.refreshNow()
        }
        refreshHistories()
    }

    func refreshHistories() {
        for entry in registry.metered {
            entry.history?.loadCheckpoint()
            entry.history?.refresh()
        }
    }

    /// Onboarding done: start the provider whose read was being held back.
    func completeOnboarding() {
        update { $0.hasCompletedOnboarding = true }
        registry.start(allowingPrompts: true)
    }

    func quit() {
        config.save()
        gtk_main_quit()
        exit(0)
    }

    /// Applies a settings change: persist, then push the parts the live
    /// objects care about.
    ///
    /// Re-read before writing. `ration` and `ration-tray` share one file, so a
    /// tray that saved its in-memory copy would undo whatever the CLI had
    /// written since launch — marking one creature revealed was enough to drop
    /// the forty-three `ration dex` had just recorded.
    func update(_ change: (inout AppConfig) -> Void) {
        var latest = AppConfig.load()
        change(&latest)
        config = latest
        config.save()
        registry.updateSchedule(config.schedule)
        for provider in Provider.all {
            registry.setEnabled(!config.disabled.contains(provider.id), for: provider)
        }
        registry.primary = config.primaryProvider
        lastStrip = nil
        tick()
        panel.redraw()
        settingsWindow.redraw()
    }

    // MARK: Panel data

    var isSetUp: Bool {
        config.hasCompletedOnboarding || !(primaryEntry?.poller.promptsForPermission ?? false)
    }

    var visibleEntries: [ProviderRegistry.Entry] {
        registry.visible
    }

    var primaryEntry: ProviderRegistry.Entry? {
        registry.primaryEntry
    }

    func entry(for providerID: String?) -> ProviderRegistry.Entry? {
        if let providerID,
            let match = registry.visible.first(where: { $0.provider.id == providerID })
        {
            return match
        }
        return registry.primaryEntry
    }

    func selectedProvider(id: String?) -> Provider {
        entry(for: id)?.provider ?? .claude
    }

    var isRefreshing: Bool {
        registry.metered.contains { $0.poller.state.status == .refreshing }
    }

    /// `max` → `Max`, shown as a capsule beside the title.
    func planLabel(providerID: String?) -> String? {
        entry(for: providerID)?.poller.planName?.capitalized
    }

    /// Everything the Pokémon tab counts: each visible tool's history, plus
    /// live gauges for tools with no transcripts.
    func dexInput() -> DexInput {
        var histories: [String: UsageHistory] = [:]
        var live: Set<String> = []
        for entry in registry.visible {
            if let history = entry.history?.history {
                histories[entry.provider.id] = history
            }
            if let snapshot = entry.poller.state.snapshot {
                if snapshot.limits.contains(where: { $0.percent > 0 })
                    || (snapshot.spend?.usedAmount ?? 0) > 0
                {
                    live.insert(entry.provider.id)
                }
            }
        }
        return DexInput(histories: histories, liveProviders: live)
    }

    var isDexScanning: Bool {
        registry.visible.contains { entry in
            if case .scanning = entry.history?.status { return true }
            return false
        }
    }

    /// How old a snapshot may be before the panel stops presenting it as
    /// current — generous, because a file-backed provider only updates while
    /// that tool runs.
    private static let freshFor: TimeInterval = 30 * 60

    func footerStatus(providerID: String?, now: Date) -> (text: String, isWarning: Bool) {
        guard let entry = entry(for: providerID) else { return ("Not updated yet", false) }
        if entry.poller.state.isStale {
            return ("Showing older numbers", true)
        }
        guard let snapshot = entry.poller.state.snapshot else {
            return ("Not updated yet", false)
        }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        let stamp = Self.elapsedText(age)
        if age > Self.freshFor {
            return ("As of \(stamp)", true)
        }
        return ("Updated \(stamp)", false)
    }

    static func elapsedText(_ elapsed: TimeInterval) -> String {
        let seconds = Int(elapsed)
        switch seconds {
        case ..<5: return "just now"
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }

    // MARK: Notifications

    private func notifyIfNeeded() {
        guard config.notifyOnThresholds else { return }
        for entry in registry.metered {
            guard let snapshot = entry.poller.state.snapshot else { continue }
            notifier.handle(snapshot, from: entry.provider)
        }
    }
}
