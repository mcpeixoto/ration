import Foundation

extension UnlockRequirement {

    /// What happened, or what still has to. Short enough for a binder tile.
    public var deed: String {
        switch self {
        case .anyUsage: "First tokens"
        case .power(let n): "\(PowerFormat.compact(n)) Score"
        case .messages(let n): "\(n) messages"
        case .sessions(let n): "\(n) sessions"
        case .cacheReads(let n): "\(PowerFormat.compact(n)) cache"
        case .activeDays(let n): "\(n) days"
        case .streak(let n): "\(n)-day streak"
        case .models(let n): "\(n) models"
        case .providers(let n): "\(n) tools"
        case .nightOwl: "After 10pm"
        case .singleDay(let n): "\(PowerFormat.compact(n)) in one day"
        case .earlyBird: "Before 11am"
        case .dusk: "4–6pm"
        case .cost(let n): "$\(Int(n)) estimate"
        }
    }

    public var hint: String {
        switch self {
        case .anyUsage: "Spend any tokens"
        case .power(let n): "Reach \(PowerFormat.compact(n)) Score"
        case .messages(let n): "Send \(n) messages"
        case .sessions(let n): "Log \(n) sessions"
        case .cacheReads(let n): "Read \(PowerFormat.compact(n)) cache tokens"
        case .activeDays(let n): "Use tokens on \(n) days"
        case .streak(let n): "Hold a \(n)-day streak"
        case .models(let n): "Use \(n) models"
        case .providers(let n): "Use \(n) tools"
        case .nightOwl: "Most tokens between 10pm and 5am"
        case .singleDay(let n): "\(PowerFormat.compact(n)) tokens in one day"
        case .earlyBird: "Most tokens between 6am and 11am"
        case .dusk: "Most tokens between 4pm and 7pm"
        case .cost(let n): "Reach a $\(Int(n)) usage estimate"
        }
    }
}

public enum PowerFormat {
    public static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...:
            String(format: "%.1fB", Double(n) / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        case 1_000...:
            String(format: "%.0fk", Double(n) / 1_000)
        default:
            "\(n)"
        }
    }
}
