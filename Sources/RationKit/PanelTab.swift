import Foundation

/// Metered views plus Pokémon, which lives in the title bar rather than the tab strip.
public enum PanelTab: String, CaseIterable, Identifiable, Codable {
    /// Live plan limits, and whether the current window survives them.
    case usage
    /// Calendar heat map, streaks, and time-of-day rhythm.
    case activity
    /// Totals and daily charts over a chosen range.
    case trends
    /// Where the tokens went — by model and by project.
    case breakdown
    /// Creatures unlocked from lifetime usage across every tool.
    case collection

    public var id: String { rawValue }

    /// Usage, Activity, Trends, Detail — Pokémon lives in the title bar.
    public static var meterTabs: [PanelTab] { [.usage, .activity, .trends, .breakdown] }

    public var title: String {
        switch self {
        case .usage: "Usage"
        case .activity: "Activity"
        case .trends: "Trends"
        case .breakdown: "Detail"
        case .collection: "Pokémon"
        }
    }

    public var symbol: String {
        switch self {
        case .usage: "gauge.with.dots.needle.67percent"
        case .activity: "calendar"
        case .trends: "chart.line.uptrend.xyaxis"
        case .breakdown: "chart.pie.fill"
        case .collection: "square.grid.3x3.fill"
        }
    }
}
