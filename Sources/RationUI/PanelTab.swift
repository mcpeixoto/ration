import SwiftUI

/// The panel's three views.
public enum PanelTab: String, CaseIterable, Identifiable, Codable {
    /// Live plan limits — the reason the app exists.
    case usage
    /// Calendar heat map of past activity.
    case activity
    /// Token and cost breakdowns.
    case metrics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .usage: "Usage"
        case .activity: "Activity"
        case .metrics: "Metrics"
        }
    }

    public var symbol: String {
        switch self {
        case .usage: "gauge.with.dots.needle.67percent"
        case .activity: "calendar"
        case .metrics: "chart.bar.fill"
        }
    }
}

/// A compact segmented switcher styled for the panel.
///
/// Hand-rolled rather than a `Picker(.segmented)`: the stock control renders
/// with its own chrome and won't take the accent colour or the icon+label
/// layout used here.
struct TabSwitcher: View {

    @Binding var selection: PanelTab
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 9))
                        Text(tab.title)
                            .font(.caption)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundStyle(selection == tab ? Color.primary : .secondary)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.primary.opacity(0.09))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }
}

/// A small segmented control matching `TabSwitcher`.
///
/// Same reason as `TabSwitcher`: the stock macOS segmented picker keeps the
/// system accent colour, which clashes in an app with its own palette.
struct SegmentedChoice<Option: Hashable>: View {

    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(selection == option ? Color.primary : .secondary)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.accent.opacity(0.22))
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }
}
