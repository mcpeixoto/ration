import RationKit
import SwiftUI

/// The panel that drops down from the menu bar.
public struct PopoverView: View {

    @Bindable var poller: UsagePoller
    @Bindable var settings: Settings
    let openSettings: () -> Void
    let startSetup: () -> Void
    let quit: () -> Void

    public init(
        poller: UsagePoller,
        settings: Settings,
        openSettings: @escaping () -> Void,
        startSetup: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.poller = poller
        self.settings = settings
        self.openSettings = openSettings
        self.startSetup = startSetup
        self.quit = quit
    }

    public var body: some View {
        // Re-renders once a second so the reset countdowns tick while the
        // popover is open. TimelineView stops when the view goes away, so this
        // costs nothing when the panel is closed.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header
                Divider()
                content(now: context.date)
                Divider()
                footer(now: context.date)
            }
            .frame(width: Theme.popoverWidth)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Ration")
                .font(.headline)

            if let plan = planLabel {
                Text(plan)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RefreshButton(isRefreshing: poller.state.status == .refreshing) {
                poller.refreshNow()
            }

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// `max` → `Max`. Shown as a small capsule beside the title.
    private var planLabel: String? {
        poller.planName?.capitalized
    }

    // MARK: Content

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

        VStack(spacing: 14) {
            if let hero {
                VStack(spacing: 8) {
                    LimitRingView(limit: hero)

                    VStack(spacing: 2) {
                        Text(hero.displayName)
                            .font(.subheadline.weight(.medium))
                        if let resetsAt = hero.resetsAt {
                            Text(RelativeTime.sentence(until: resetsAt, from: now))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 14)
            }

            if !rest.isEmpty {
                VStack(spacing: 12) {
                    ForEach(rest) { limit in
                        LimitRowView(limit: limit, now: now)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            if let spend = snapshot.spend, spend.isEnabled {
                SpendRowView(spend: spend)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 12)
    }

    /// The limit the user chose to watch, falling back to the worst one.
    private func heroLimit(in snapshot: UsageSnapshot) -> UsageLimit? {
        MenuBarPresentation.select(mode: settings.displayMode, from: snapshot)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        .padding(.top, 2)
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
