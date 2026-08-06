import RationKit
import SwiftUI

// MARK: - Hero ring

/// The headline gauge: one big ring for whichever limit matters most.
struct LimitRingView: View {

    let limit: UsageLimit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Gauge(value: min(max(limit.percent, 0), 100), in: 0...100) {
            EmptyView()
        } currentValueLabel: {
            Text(percentText)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                // The Apple rolling-digit effect. Skipped under Reduce Motion.
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(limit.severity.accentColor)
        .scaleEffect(Theme.ringSize / 58)  // the accessory style draws at a fixed 58pt
        .frame(width: Theme.ringSize, height: Theme.ringSize)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: limit.percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.displayName)
        .accessibilityValue("\(percentText) used")
    }

    private var percentText: String {
        MenuBarPresentation.percentText(limit.percent)
    }
}

// MARK: - Secondary row

/// One limit as a labelled bar. Used for everything below the hero ring.
struct LimitRowView: View {

    let limit: UsageLimit
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(MenuBarPresentation.percentText(limit.percent))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(limit.severity.color ?? .secondary)
            }

            ProgressView(value: min(max(limit.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(limit.severity.accentColor)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: limit.percent)

            if let resetsAt = limit.resetsAt {
                Text(RelativeTime.sentence(until: resetsAt, from: now))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(limit.displayName)
        .accessibilityValue(accessibilityValue)
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

/// A refresh button that spins while a fetch is in flight.
///
/// Hand-rolled rather than using `.symbolEffect(.rotate)`, which needs
/// macOS 15; Ration supports 14.
struct RefreshButton: View {

    let isRefreshing: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(angle))
        }
        .buttonStyle(.borderless)
        .help("Refresh now")
        .accessibilityLabel("Refresh now")
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.8)) { angle += 360 }
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

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(tint)
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
        .padding(.horizontal, 12)
    }
}
