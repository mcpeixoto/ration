import SwiftUI

/// The panel's four views.
///
/// Four rather than three because Metrics grew past what a menu bar panel can
/// show without scrolling. The split is by question: *how am I doing right
/// now* (Usage), *when do I work* (Activity), *how is it trending* (Trends),
/// *what is it going into* (Breakdown).
public enum PanelTab: String, CaseIterable, Identifiable, Codable {
    /// Live plan limits, and whether the current window survives them.
    case usage
    /// Calendar heat map, streaks, and time-of-day rhythm.
    case activity
    /// Totals and daily charts over a chosen range.
    case trends
    /// Where the tokens went — by model and by project.
    case breakdown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .usage: "Usage"
        case .activity: "Activity"
        case .trends: "Trends"
        case .breakdown: "Detail"
        }
    }

    public var symbol: String {
        switch self {
        case .usage: "gauge.with.dots.needle.67percent"
        case .activity: "calendar"
        case .trends: "chart.line.uptrend.xyaxis"
        case .breakdown: "chart.pie.fill"
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
                    Text(tab.title)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
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

    init(options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    /// Convenience for enums that expose their own title.
    init(options: [Option], selection: Binding<Option>, label keyPath: KeyPath<Option, String>) {
        self.init(options: options, selection: selection, label: { $0[keyPath: keyPath] })
    }

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
