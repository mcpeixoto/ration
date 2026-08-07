import Foundation

/// One AI coding tool whose usage Ration can show.
///
/// A struct rather than an enum on purpose: a fork can add a provider without
/// editing a switch in every file, and `id` is stable enough to key persisted
/// state and user defaults on.
public struct Provider: Sendable, Hashable, Identifiable, Codable {

    /// Stable across releases — it names checkpoint files and settings keys.
    public let id: String
    public let displayName: String
    /// The tool that writes the data, for sentences like "Open ⟨…⟩ and sign in".
    public let toolName: String
    public let symbolName: String

    public init(id: String, displayName: String, toolName: String, symbolName: String) {
        self.id = id
        self.displayName = displayName
        self.toolName = toolName
        self.symbolName = symbolName
    }

    public static let claude = Provider(
        id: "claude", displayName: "Claude", toolName: "Claude Code",
        symbolName: "sparkle")

    public static let codex = Provider(
        id: "codex", displayName: "Codex", toolName: "Codex CLI",
        symbolName: "chevron.left.forwardslash.chevron.right")

    public static let cursor = Provider(
        id: "cursor", displayName: "Cursor", toolName: "Cursor",
        symbolName: "cursorarrow.rays")

    public static let copilot = Provider(
        id: "copilot", displayName: "Copilot", toolName: "GitHub Copilot",
        symbolName: "airplane")

    public static let gemini = Provider(
        id: "gemini", displayName: "Gemini", toolName: "Gemini CLI",
        symbolName: "diamond")

    /// Display order, which is also the order they appear in the switcher.
    public static let all: [Provider] = [.claude, .codex, .cursor, .copilot, .gemini]

    public static func named(_ id: String) -> Provider? {
        all.first { $0.id == id }
    }
}

// MARK: - Availability

/// Why a provider does — or does not — have numbers to show.
///
/// Ration is deliberately quiet about tools you do not use: a provider that is
/// not installed is hidden rather than shown as an error.
public enum ProviderAvailability: Sendable, Equatable {

    /// Installed, with data to read.
    case ready

    /// Nothing of this tool on disk. Hidden from the switcher.
    case notInstalled

    /// Installed, but it has not written anything worth reading yet.
    case noData(reason: String)

    /// Installed, and its history may be readable, but its plan percentage is
    /// only available over the network — which Ration does not do for anyone
    /// but the provider it was built around. See `SECURITY.md`.
    case quotaNotReadable(reason: String)

    /// Whether this provider should appear in the panel's switcher at all.
    public var isVisible: Bool {
        self != .notInstalled
    }

    /// Whether a percentage gauge can ever be shown.
    public var hasQuota: Bool {
        switch self {
        case .ready, .noData: true
        case .notInstalled, .quotaNotReadable: false
        }
    }

    public var explanation: String? {
        switch self {
        case .ready: nil
        case .notInstalled: "Not installed."
        case .noData(let reason): reason
        case .quotaNotReadable(let reason): reason
        }
    }
}
