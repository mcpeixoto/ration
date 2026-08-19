import Foundation

enum CLIFormat {
    static func tokens(_ count: Int) -> String { compact(count) }

    static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        case ..<10_000: String(format: "%.1fk", Double(count) / 1_000)
        case ..<1_000_000: "\(count / 1_000)k"
        case ..<10_000_000: String(format: "%.1fM", Double(count) / 1_000_000)
        default: "\(count / 1_000_000)M"
        }
    }

    static func cost(_ amount: Double) -> String {
        amount < 10 ? String(format: "$%.2f", amount) : String(format: "$%.0f", amount)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        return formatter.string(from: Calendar.current.date(from: components) ?? Date())
            .lowercased()
    }

    static func progressBar(_ percent: Double, width: Int = 20) -> String {
        let filled = min(width, max(0, Int((percent / 100 * Double(width)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    static func heatCell(_ intensity: Double) -> String {
        switch intensity {
        case 0: "·"
        case ..<0.3: "░"
        case ..<0.55: "▒"
        case ..<0.8: "▓"
        default: "█"
        }
    }
}
