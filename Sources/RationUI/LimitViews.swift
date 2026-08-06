import RationKit
import SwiftUI

// MARK: - Secondary row

/// One limit as a labelled bar.
///
/// Clicking promotes it into the ring above, so the panel can be steered
/// without going to Settings.
struct LimitRowView: View {

    let limit: UsageLimit
    let now: Date
    var isSelected: Bool = false
    var onSelect: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(limit.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isSelected {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(limit.severity.accentColor)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 8)

                // No `.numericText()` content transition here, for the same
                // crispness reason as the ring's readout.
                Text(MenuBarPresentation.percentText(limit.percent))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(limit.severity.color ?? .secondary)
            }

            LimitBar(percent: limit.percent, severity: limit.severity)

            if let resetsAt = limit.resetsAt {
                Text(RelativeTime.sentence(until: resetsAt, from: now))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(isHovering && onSelect != nil ? 0.06 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture { onSelect?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(limit.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(onSelect != nil ? .isButton : [])
        .accessibilityHint(onSelect != nil ? "Show this limit in the gauge" : "")
    }

    private var accessibilityValue: String {
        var value = "\(MenuBarPresentation.percentText(limit.percent)) used"
        if let resetsAt = limit.resetsAt {
            value += ", \(RelativeTime.sentence(until: resetsAt, from: now))"
        }
        return value
    }
}

// MARK: - Refresh button

/// Spins while a fetch is in flight.
///
/// Hand-rolled rather than `.symbolEffect(.rotate)`, which needs macOS 15;
/// Ration supports 14.
struct RefreshButton: View {

    let isRefreshing: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(angle))
                .foregroundStyle(isHovering ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .help("Refresh now")
        .accessibilityLabel("Refresh now")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7)) { angle += 360 }
        }
    }
}

/// A borderless icon button that responds to hover, for the panel header.
struct HeaderButton: View {

    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isHovering ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

// MARK: - Empty and error states

/// Shown when there is nothing to gauge: no session, no data, or an error.
struct StatusMessageView: View {

    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary
    var action: (title: String, perform: () -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(tint)
                .scaleEffect(hasAppeared ? 1 : 0.7)
                .opacity(hasAppeared ? 1 : 0)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            withAnimation(.smooth(duration: 0.4)) { hasAppeared = true }
        }
    }
}
