import RationKit
import SwiftUI

/// The panel that drops down from the menu bar.
public struct PopoverView: View {

    @Bindable var poller: UsagePoller
    @Bindable var settings: Settings
    @Bindable var transcripts: TranscriptStore
    let openSettings: () -> Void
    let startSetup: () -> Void
    let quit: () -> Void

    /// Which limit the user promoted into the ring, if any. Resets when the
    /// panel closes, so the ring returns to their configured default.
    @State private var focusedLimitID: String?
    @State private var tab: PanelTab = .usage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        poller: UsagePoller,
        settings: Settings,
        transcripts: TranscriptStore,
        openSettings: @escaping () -> Void,
        startSetup: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.poller = poller
        self.settings = settings
        self.transcripts = transcripts
        self.openSettings = openSettings
        self.startSetup = startSetup
        self.quit = quit
    }

    public var body: some View {
        // Re-renders once a second so the reset countdowns tick while the panel
        // is open. TimelineView stops when the view goes away, so this costs
        // nothing while the panel is closed.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header

                // The tab bar only appears once setup is done — before that
                // there is nothing behind any of the tabs.
                if settings.hasCompletedOnboarding {
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
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Text("Ration")
                .font(.headline)

            if let plan = planLabel {
                Text(plan)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RefreshButton(isRefreshing: poller.state.status == .refreshing) {
                poller.refreshNow()
            }

            HeaderButton(symbol: "gearshape", help: "Settings", action: openSettings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    /// `max` → `Max`. Shown as a small capsule beside the title.
    private var planLabel: String? {
        poller.planName?.capitalized
    }

    // MARK: Content

    @ViewBuilder
    private func tabContent(now: Date) -> some View {
        switch tab {
        case .usage:
            content(now: now)
        case .activity:
            ActivityView(history: transcripts.history, status: transcripts.status, now: now)
        case .metrics:
            MetricsView(
                history: transcripts.history, status: transcripts.status,
                now: now, snapshot: poller.state.snapshot)
        }
    }

    /// Ordered so that having usable numbers wins over a transient error:
    /// a failed refresh should never replace a working gauge with an error page.
    @ViewBuilder
    private func content(now: Date) -> some View {
        if !settings.hasCompletedOnboarding {
            StatusMessageView(
                symbol: "hand.wave",
                title: "Finish setting up",
                message:
                    "Ration needs your permission to read the Claude Code session stored in your keychain.",
                action: ("Set up Ration", startSetup)
            )
        } else if poller.state.status == .signedOut {
            StatusMessageView(
                symbol: "person.crop.circle.badge.exclamationmark",
                title: "Signed out",
                message:
                    "Ration reads the session Claude Code already has. Open Claude Code and sign in, then try again.",
                tint: .orange,
                action: ("Try again", { poller.refreshNow() })
            )
        } else if let snapshot = poller.state.snapshot, !snapshot.limits.isEmpty {
            limits(snapshot: snapshot, now: now)
        } else if poller.state.snapshot != nil {
            StatusMessageView(
                symbol: "gauge.with.dots.needle.0percent",
                title: "No limits reported",
                message: "This account has no usage limits to show."
            )
        } else if case .failed(let error) = poller.state.status {
            StatusMessageView(
                symbol: "wifi.slash",
                title: "Can't reach Anthropic",
                message: error.errorDescription ?? "Something went wrong.",
                action: ("Retry", { poller.refreshNow() })
            )
        } else {
            StatusMessageView(
                symbol: "circle.dotted",
                title: "Loading",
                message: "Fetching your current usage…"
            )
        }
    }

    @ViewBuilder
    private func limits(snapshot: UsageSnapshot, now: Date) -> some View {
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

            Button("Quit", action: quit)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func statusText(now: Date) -> some View {
        if poller.state.isStale {
            Label("Showing older numbers", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
        } else if let snapshot = poller.state.snapshot {
            Text("Updated \(updatedText(snapshot.fetchedAt, now: now))")
                .monospacedDigit()
        } else {
            Text("Not updated yet")
        }
    }

    private func updatedText(_ date: Date, now: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(date))
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        return "\(elapsed / 60)m ago"
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
