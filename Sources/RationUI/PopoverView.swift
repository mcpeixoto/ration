import RationKit
import SwiftUI

/// The panel that drops down from the menu bar.
public struct PopoverView: View {

    @Bindable var registry: ProviderRegistry
    @Bindable var settings: Settings
    @Bindable var companion: CompanionModel
    let openSettings: () -> Void
    let startSetup: () -> Void
    let quit: () -> Void

    /// Which limit the user promoted into the ring, if any. Resets when the
    /// panel closes, so the ring returns to their configured default.
    @State private var focusedLimitID: String?
    @State private var tab: PanelTab = .usage
    /// Which provider the panel is showing. Starts at the one in the menu bar
    /// so opening the panel explains the number that made you open it.
    @State private var selection: Provider?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        registry: ProviderRegistry,
        settings: Settings,
        companion: CompanionModel,
        openSettings: @escaping () -> Void,
        startSetup: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.registry = registry
        self.settings = settings
        self.companion = companion
        self.openSettings = openSettings
        self.startSetup = startSetup
        self.quit = quit
    }

    /// The entry being shown, falling back to whatever is available.
    ///
    /// Resolved against `visible`, not `entries`: a provider hidden while the
    /// panel was pointed at it must fall through to `primaryEntry` rather than
    /// keep rendering its stale, no-longer-polled state.
    private var entry: ProviderRegistry.Entry? {
        selection.flatMap { provider in registry.visible.first { $0.provider == provider } }
            ?? registry.primaryEntry
    }

    private var provider: Provider { entry?.provider ?? .claude }
    private var poller: UsagePoller? { entry?.poller }
    private var transcripts: TranscriptStore? { entry?.history }

    /// Every visible tool's history, plus live gauges for tools with no
    /// transcripts (Cursor). The collection is the one view allowed to combine
    /// them, because its total is a game score, not a usage figure.
    ///
    /// Only the one-shot migration reads this now — the loop itself runs off the
    /// per-provider lifetime ledger in `CompanionSync`.
    private var dexInput: DexInput {
        var histories: [String: UsageHistory] = [:]
        var live: Set<String> = []
        for entry in registry.visible {
            if let history = entry.history?.history {
                histories[entry.provider.id] = history
            }
            if snapshotShowsUsage(entry.poller.state.snapshot) {
                live.insert(entry.provider.id)
            }
        }
        return DexInput(histories: histories, liveProviders: live)
    }

    /// Fold whatever has been read since the last look into the companion loop.
    ///
    /// `archive` is only evaluated on a profile that has never run the loop, so the old
    /// threshold model is walked once in a lifetime rather than on every poll.
    func syncCompanion() {
        var windows: [LimitWindow] = []
        var histories: [String: UsageHistory] = [:]
        for entry in registry.visible {
            if let history = entry.history?.history {
                histories[entry.provider.id] = history
            }
            windows += CompanionSync.windows(
                providerID: entry.provider.id, snapshot: entry.poller.state.snapshot)
        }
        companion.sync(
            lifetimeByProvider: CompanionSync.lifetimeTokens(histories: histories),
            windows: windows,
            archive: {
                Set(Dex.evaluate(dexInput).caught.map(\.id))
                    .union(settings.revealedCreatureIDs)
            })
    }

    private var isDexScanning: Bool {
        registry.visible.contains { entry in
            if case .scanning = entry.history?.status { return true }
            return false
        }
    }

    private func snapshotShowsUsage(_ snapshot: UsageSnapshot?) -> Bool {
        guard let snapshot else { return false }
        if snapshot.limits.contains(where: { $0.percent > 0 }) { return true }
        if let spend = snapshot.spend, spend.usedAmount > 0 { return true }
        return false
    }

    public var body: some View {
        // Re-renders once a second so the reset countdowns tick while the panel
        // is open. TimelineView stops when the view goes away, so this costs
        // nothing while the panel is closed.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header

                // A switcher with one position is furniture, so it only appears
                // once there is a genuine choice to make.
                if isSetUp, registry.visible.count > 1, tab != .collection {
                    ProviderSwitcher(
                        providers: registry.visible.map(\.provider),
                        selection: Binding(
                            get: { provider },
                            set: { selection = $0 })
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }

                // The tab bar only appears once setup is done — before that
                // there is nothing behind any of the tabs.
                if isSetUp, tab != .collection {
                    TabSwitcher(selection: $tab)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }

                Divider()
                tabContent(now: context.date)
                Divider()
                footer(now: context.date)
            }
            .frame(width: Theme.popoverWidth)
        }
        .onAppear {
            selection = trayProvider() ?? selection ?? settings.primaryProvider
        }
    }

    /// Onboarding only gates the provider whose first read raises a system
    /// prompt. Everything else is read from files the user already owns.
    private var isSetUp: Bool {
        settings.hasCompletedOnboarding || !(poller?.promptsForPermission ?? false)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    if tab == .collection { tab = .usage }
                }
            } label: {
                Text("Ration")
                    .font(.headline)
                    .foregroundStyle(tab == .collection ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Usage")

            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    tab = .collection
                }
            } label: {
                Text("Pokémon")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        tab == .collection
                            ? Theme.accent.opacity(0.28)
                            : Color.primary.opacity(0.07),
                        in: Capsule()
                    )
                    .foregroundStyle(tab == .collection ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .help("Pokémon unlocked from Score across every tool")
            .accessibilityLabel("Pokémon")
            .accessibilityAddTraits(tab == .collection ? [.isSelected, .isButton] : .isButton)

            if tab != .collection, let plan = planLabel {
                Text(plan)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if tab != .collection {
                RefreshButton(isRefreshing: poller?.state.status == .refreshing) {
                    poller?.refreshNow()
                }
            }

            HeaderButton(symbol: "gearshape", help: "Settings", action: openSettings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    /// Which account the pointer was over when the tray was clicked.
    private func trayProvider() -> Provider? {
        let accounts = trayAccounts
        guard accounts.count > 1 else { return accounts.first?.provider }
        let strip = MenuBarStrip.make(
            accounts: accounts.map {
                ($0.provider, $0.poller.state, $0.poller.promptsForPermission)
            },
            mode: settings.displayMode,
            useSeverityColor: settings.useSeverityColor,
            showWeeklyBar: settings.showWeeklyBar,
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            isEverythingHidden: registry.isEverythingHidden)
        let widths = strip.items.map(MenuBarHitTesting.itemWidth)
        guard
            let click = MenuBarOpeningClick.location(),
            let index = MenuBarHitTesting.itemIndex(
                clickX: Double(click.x), barWidth: Double(click.width), itemWidths: widths)
        else { return nil }
        return accounts.indices.contains(index) ? accounts[index].provider : nil
    }

    private var trayAccounts: [ProviderRegistry.Entry] {
        registry.metered.filter {
            settings.hasCompletedOnboarding || !$0.poller.promptsForPermission
        }
    }

    /// `max` → `Max`. Shown as a small capsule beside the title.
    private var planLabel: String? {
        poller?.planName?.capitalized
    }

    // MARK: Content

    @ViewBuilder
    private func tabContent(now: Date) -> some View {
        // Every tab is scoped to the selected provider. Merging histories would
        // be worse than useless: a token of Claude and a token of Codex are not
        // the same unit, so a combined total is a confidently wrong number.
        let history = transcripts?.history ?? UsageHistory()
        let status = transcripts?.status ?? .ready

        switch tab {
        case .usage:
            content(now: now)
        case .activity:
            ActivityView(history: history, status: status, now: now, provider: provider)
        case .trends:
            TrendsView(history: history, status: status, now: now, provider: provider)
        case .breakdown:
            BreakdownView(history: history, status: status, now: now, provider: provider)
        case .collection:
            CollectionView(model: companion, isScanning: isDexScanning)
                // Opening the tab is also a poll: the panel is where the progress bar
                // is actually being looked at, so it should never be a minute stale.
                .onAppear(perform: syncCompanion)
        }
    }

    /// Ordered so that having usable numbers wins over a transient error:
    /// a failed refresh should never replace a working gauge with an error page.
    @ViewBuilder
    private func content(now: Date) -> some View {
        if let poller {
            usage(poller: poller, now: now)
        } else if registry.isEverythingHidden {
            StatusMessageView(
                symbol: "eye.slash",
                title: "Everything is hidden",
                message:
                    "You have turned off every account, so Ration is not reading anything. "
                    + "Turn one back on to see your usage.",
                action: ("Open Accounts", openSettings)
            )
        } else {
            StatusMessageView(
                symbol: "questionmark.circle",
                title: "Nothing to show",
                message: "No supported tool was found on this Mac."
            )
        }
    }

    @ViewBuilder
    private func usage(poller: UsagePoller, now: Date) -> some View {
        if !isSetUp {
            StatusMessageView(
                symbol: "hand.wave",
                title: "Finish setting up",
                message:
                    "Ration needs your permission to read the \(provider.toolName) session stored in your keychain.",
                action: ("Set up Ration", startSetup)
            )
        } else if case .quotaNotReadable(let reason) = poller.availability {
            ProviderUnavailableView(provider: provider, reason: reason)
        } else if poller.state.status == .signedOut {
            StatusMessageView(
                symbol: "person.crop.circle.badge.exclamationmark",
                title: "Signed out",
                message:
                    "Ration reads the session \(provider.toolName) already has. Open \(provider.toolName) and sign in, then try again.",
                tint: .orange,
                action: ("Try again", { poller.refreshNow() })
            )
        } else if let snapshot = poller.state.snapshot, !snapshot.limits.isEmpty {
            limits(snapshot: snapshot, poller: poller, now: now)
        } else if poller.state.snapshot != nil {
            StatusMessageView(
                symbol: "gauge.with.dots.needle.0percent",
                title: "No limits reported",
                message: "This account has no usage limits to show."
            )
        } else if case .failed(let error) = poller.state.status {
            StatusMessageView(
                symbol: errorSymbol(for: error),
                title: errorTitle(for: error),
                message: error.errorDescription ?? "Something went wrong.",
                action: error.isRetryable ? ("Retry", { poller.refreshNow() }) : nil
            )
        } else {
            StatusMessageView(
                symbol: "circle.dotted",
                title: "Loading",
                message: "Fetching your current usage…"
            )
        }
    }

    /// A provider read from files cannot fail to be *reached*, so offering
    /// "can't reach the network" for one would be nonsense.
    private func errorSymbol(for error: LimitsError) -> String {
        switch error {
        case .noData, .unavailable: "tray"
        default: "wifi.slash"
        }
    }

    private func errorTitle(for error: LimitsError) -> String {
        switch error {
        case .noData, .unavailable: "Nothing recorded yet"
        default: "Can't reach \(provider.displayName)"
        }
    }

    @ViewBuilder
    private func limits(snapshot: UsageSnapshot, poller: UsagePoller, now: Date) -> some View {
        let hero = heroLimit(in: snapshot)
        let rest = snapshot.limits.filter { $0.id != hero?.id }

        VStack(spacing: 0) {
            if let hero {
                VStack(spacing: 10) {
                    RingGauge(percent: hero.percent, severity: hero.severity)
                        // A new id when the focused limit changes makes the ring
                        // re-run its sweep animation for the newly chosen limit.
                        .id(hero.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))

                    VStack(spacing: 3) {
                        Text(hero.displayName)
                            .font(.subheadline.weight(.semibold))

                        if let resetsAt = hero.resetsAt {
                            Text(RelativeTime.sentence(until: resetsAt, from: now))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 18)
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: hero.id)
            }

            if !rest.isEmpty {
                VStack(spacing: 2) {
                    ForEach(rest) { limit in
                        LimitRowView(
                            limit: limit,
                            now: now,
                            isSelected: focusedLimitID == limit.id,
                            onSelect: { focus(limit) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }

            if let projection = WindowProjection(limit: hero ?? snapshot.limits[0], now: now) {
                Divider().padding(.horizontal, 16)
                ProjectionCard(
                    provider: provider,
                    projection: projection,
                    curve: (transcripts?.history ?? UsageHistory())
                        .windowCurve(for: projection, now: now),
                    now: now
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            if let spend = snapshot.spend, spend.isEnabled {
                Divider()
                    .padding(.horizontal, 16)
                SpendRowView(spend: spend)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .padding(.bottom, 6)
    }

    /// Promotes a row into the ring, or drops back to the default if it is
    /// already there.
    private func focus(_ limit: UsageLimit) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            focusedLimitID = focusedLimitID == limit.id ? nil : limit.id
        }
    }

    /// The limit the user clicked, else the one they configured, else the worst.
    private func heroLimit(in snapshot: UsageSnapshot) -> UsageLimit? {
        if let focusedLimitID,
            let focused = snapshot.limits.first(where: { $0.id == focusedLimitID })
        {
            return focused
        }
        return MenuBarPresentation.select(mode: settings.displayMode, from: snapshot)
            ?? snapshot.primaryLimit
    }

    // MARK: Footer

    private func footer(now: Date) -> some View {
        HStack(spacing: 4) {
            statusText(now: now)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            CoffeeLink()

            Button("Quit", action: quit)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// How old a snapshot may be before the panel stops presenting it as
    /// current. Generous, because a provider read from files only updates while
    /// that tool is running, and a quiet afternoon is not a fault.
    private static let freshFor: TimeInterval = 30 * 60

    @ViewBuilder
    private func statusText(now: Date) -> some View {
        if poller?.state.isStale == true {
            Label("Showing older numbers", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
        } else if let snapshot = poller?.state.snapshot {
            let age = now.timeIntervalSince(snapshot.fetchedAt)

            // A number that has not moved in hours must not read as live. This
            // is the failure mode that matters for a file-backed provider:
            // Codex stamps its quota into its session log, so the figure ages
            // whenever Codex is not running.
            if age > Self.freshFor {
                Label(
                    "As of \(updatedText(snapshot.fetchedAt, now: now))",
                    systemImage: "clock.badge.exclamationmark"
                )
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
                .monospacedDigit()
                .help(
                    "\(provider.displayName) records its usage as it runs, so this is the "
                        + "most recent figure it wrote.")
            } else {
                Text("Updated \(updatedText(snapshot.fetchedAt, now: now))")
                    .monospacedDigit()
            }
        } else {
            Text("Not updated yet")
        }
    }

    private func updatedText(_ date: Date, now: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(date))
        switch elapsed {
        case ..<5: return "just now"
        case ..<60: return "\(elapsed)s ago"
        case ..<3600: return "\(elapsed / 60)m ago"
        case ..<86400: return "\(elapsed / 3600)h ago"
        default: return "\(elapsed / 86400)d ago"
        }
    }
}

// MARK: - Spend

/// Pay-as-you-go credits, shown only when the account actually uses them.
struct SpendRowView: View {

    let spend: UsageSnapshot.Spend

    var body: some View {
        HStack {
            Label("Extra usage", systemImage: "creditcard")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(amountText)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(spend.severity.color ?? .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = spend.currencyCode ?? "USD"

        let used =
            formatter.string(from: spend.usedAmount as NSDecimalNumber)
            ?? "\(spend.usedAmount)"

        guard let limit = spend.limitAmount,
            let limitText = formatter.string(from: limit as NSDecimalNumber)
        else {
            return used
        }
        return "\(used) of \(limitText)"
    }
}
