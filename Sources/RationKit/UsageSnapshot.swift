import Foundation

/// A point-in-time view of how much of your Claude plan is used up.
///
/// Decoded from `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The response carries the same information twice: once as named top-level
/// keys (`five_hour`, `seven_day`, …) and once as a generic `limits` array.
/// We prefer the array, because it lets Anthropic introduce new limit kinds
/// without an app update — an unknown `kind` still renders, just with a name
/// derived from its identifier. The named keys are only used as a fallback for
/// responses that omit the array.
public struct UsageSnapshot: Sendable, Equatable {

    /// Every limit the account is subject to, ordered for display.
    public let limits: [UsageLimit]

    /// Pay-as-you-go credit spend, when the account has credits enabled.
    public let spend: Spend?

    /// When this snapshot was fetched. Used for staleness display.
    public let fetchedAt: Date

    public init(limits: [UsageLimit], spend: Spend? = nil, fetchedAt: Date = Date()) {
        self.limits = limits.sorted(by: UsageLimit.displayOrder)
        self.spend = spend
        self.fetchedAt = fetchedAt
    }

    /// The limit worth showing in the menu bar: whichever is closest to being hit.
    public var primaryLimit: UsageLimit? {
        limits.max { $0.percent < $1.percent }
    }

    /// The worst severity across all limits, for tinting the menu bar item.
    public var overallSeverity: Severity {
        limits.map(\.severity).max { $0.rank < $1.rank } ?? .normal
    }

    /// The limit for the rolling session window, if the account has one.
    public var sessionLimit: UsageLimit? {
        limits.first { $0.kind == .session }
    }

    /// The limit for the rolling week across all models, if the account has one.
    public var weeklyLimit: UsageLimit? {
        limits.first { $0.kind == .weeklyAll }
    }
}

// MARK: - A single limit

public struct UsageLimit: Sendable, Equatable, Identifiable {

    public let kind: Kind
    public let group: Group
    /// How much of this limit is consumed, 0–100.
    public let percent: Double
    public let severity: Severity
    /// When this window rolls over. Absent for limits that do not reset.
    public let resetsAt: Date?
    /// What this limit applies to, when it is narrower than the whole account.
    public let scope: Scope?
    /// Whether this is the limit currently constraining the account.
    public let isActive: Bool

    /// Stable across refreshes, so SwiftUI animates rows instead of replacing them.
    public var id: String {
        if let model = scope?.modelDisplayName {
            return "\(kind.rawValue)|\(model)"
        }
        return kind.rawValue
    }

    public init(
        kind: Kind,
        group: Group,
        percent: Double,
        severity: Severity,
        resetsAt: Date?,
        scope: Scope? = nil,
        isActive: Bool = false
    ) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.scope = scope
        self.isActive = isActive
    }

    /// What to call this limit in the UI.
    public var displayName: String {
        let base: String
        switch kind {
        case .session: base = "Session"
        case .weeklyAll, .weeklyScoped: base = "Weekly"
        case .other(let raw): base = Self.humanize(raw)
        }

        if let model = scope?.modelDisplayName {
            return "\(base) · \(model)"
        }
        return base
    }

    /// `monthly_quantum_flux` → `Monthly Quantum Flux`.
    ///
    /// Unknown kinds are shown rather than hidden: a limit we do not recognise
    /// can still be the one that stops your work.
    static func humanize(_ raw: String) -> String {
        raw.split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Session first, then weekly, then anything new — most urgent to least.
    static func displayOrder(_ a: UsageLimit, _ b: UsageLimit) -> Bool {
        if a.kind.sortRank != b.kind.sortRank {
            return a.kind.sortRank < b.kind.sortRank
        }
        if a.percent != b.percent {
            return a.percent > b.percent
        }
        return a.id < b.id
    }
}

// MARK: - Kind

extension UsageLimit {
    /// Known limit kinds, with `other` preserving anything we have not seen.
    public enum Kind: Sendable, Hashable {
        case session
        case weeklyAll
        case weeklyScoped
        case other(String)

        public init(rawValue: String) {
            switch rawValue {
            case "session": self = .session
            case "weekly_all": self = .weeklyAll
            case "weekly_scoped": self = .weeklyScoped
            default: self = .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .session: "session"
            case .weeklyAll: "weekly_all"
            case .weeklyScoped: "weekly_scoped"
            case .other(let raw): raw
            }
        }

        var sortRank: Int {
            switch self {
            case .session: 0
            case .weeklyAll: 1
            case .weeklyScoped: 2
            case .other: 3
            }
        }
    }

    /// Which bucket a limit belongs to. Also open-ended.
    public enum Group: Sendable, Hashable {
        case session
        case weekly
        case other(String)

        public init(rawValue: String) {
            switch rawValue {
            case "session": self = .session
            case "weekly": self = .weekly
            default: self = .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .session: "session"
            case .weekly: "weekly"
            case .other(let raw): raw
            }
        }
    }

    /// What a limit is narrowed to, when it does not apply account-wide.
    public struct Scope: Sendable, Equatable {
        public let modelID: String?
        public let modelDisplayName: String?
        public let surface: String?

        public init(modelID: String? = nil, modelDisplayName: String? = nil, surface: String? = nil)
        {
            self.modelID = modelID
            self.modelDisplayName = modelDisplayName
            self.surface = surface
        }
    }
}

// MARK: - Severity

/// How close to the limit you are.
///
/// This comes from the server. We deliberately do not invent our own
/// thresholds: Anthropic knows when a limit is about to bite, and hardcoding
/// percentages here would drift out of sync with their policy.
public enum Severity: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical

    /// Unrecognised severities degrade to `normal` rather than failing the decode.
    public init(rawValue raw: String) {
        switch raw {
        case "warning": self = .warning
        case "critical": self = .critical
        default: self = .normal
        }
    }

    var rank: Int {
        switch self {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        }
    }

    /// How a percentage should be coloured on screen, never quieter than what
    /// the server reported.
    ///
    /// The server's `severity` is authoritative about policy — it knows when a
    /// limit is about to bite — but it stays `normal` until quite late, which
    /// is not much use for a glanceable bar. So we escalate on our own
    /// thresholds too and take whichever is louder. The server can only ever
    /// make the display more urgent, never less.
    public static func escalating(percent: Double, reported: Severity) -> Severity {
        let byPercent: Severity =
            switch percent {
            case ..<80: .normal
            case ..<90: .warning
            default: .critical
            }
        return byPercent.rank > reported.rank ? byPercent : reported
    }

    /// Only used when synthesising limits from the named keys, which carry no
    /// severity of their own.
    static func derived(fromPercent percent: Double) -> Severity {
        switch percent {
        case ..<80: .normal
        case ..<95: .warning
        default: .critical
        }
    }
}

// MARK: - Spend

extension UsageSnapshot {
    /// Pay-as-you-go credit usage beyond the plan's included limits.
    public struct Spend: Sendable, Equatable {
        public let isEnabled: Bool
        public let percent: Double
        /// In major units — 1250 minor units at exponent 2 becomes 12.50.
        public let usedAmount: Decimal
        public let limitAmount: Decimal?
        public let currencyCode: String?
        public let severity: Severity

        public init(
            isEnabled: Bool,
            percent: Double,
            usedAmount: Decimal,
            limitAmount: Decimal? = nil,
            currencyCode: String? = nil,
            severity: Severity = .normal
        ) {
            self.isEnabled = isEnabled
            self.percent = percent
            self.usedAmount = usedAmount
            self.limitAmount = limitAmount
            self.currencyCode = currencyCode
            self.severity = severity
        }
    }
}

// MARK: - Decoding

extension UsageSnapshot {

    public enum DecodingFailure: Error, LocalizedError {
        case notJSON

        public var errorDescription: String? {
            switch self {
            case .notJSON: "The usage response was not valid JSON."
            }
        }
    }

    /// Decodes a usage response.
    ///
    /// Individual malformed limits are dropped rather than failing the whole
    /// snapshot: one bad entry should not blank out the menu bar.
    public static func decode(from data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingFailure.notJSON
        }

        let limits =
            payload.limits.map { $0.compactMap(UsageLimit.init(wire:)) }
            ?? payload.synthesizedLimits()

        return UsageSnapshot(
            limits: limits,
            spend: payload.spend.map(Spend.init(wire:)),
            fetchedAt: fetchedAt
        )
    }
}

// MARK: - Wire format
//
// Kept private and separate from the domain types so the shape of Anthropic's
// JSON never leaks into the rest of the app.

private struct Payload: Decodable {
    let limits: [WireLimit]?
    let spend: WireSpend?

    let fiveHour: WireNamedLimit?
    let sevenDay: WireNamedLimit?
    let sevenDayOpus: WireNamedLimit?
    let sevenDaySonnet: WireNamedLimit?

    enum CodingKeys: String, CodingKey {
        case limits, spend
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    /// Builds limits from the named keys, for responses without a `limits` array.
    func synthesizedLimits() -> [UsageLimit] {
        var result: [UsageLimit] = []

        if let five = fiveHour {
            result.append(five.asLimit(kind: .session, group: .session))
        }
        if let week = sevenDay {
            result.append(week.asLimit(kind: .weeklyAll, group: .weekly))
        }
        if let opus = sevenDayOpus {
            result.append(
                opus.asLimit(
                    kind: .weeklyScoped, group: .weekly,
                    scope: .init(modelDisplayName: "Opus")))
        }
        if let sonnet = sevenDaySonnet {
            result.append(
                sonnet.asLimit(
                    kind: .weeklyScoped, group: .weekly,
                    scope: .init(modelDisplayName: "Sonnet")))
        }
        return result
    }
}

private struct WireLimit: Decodable {
    let kind: String?
    let group: String?
    let percent: Double?
    let severity: String?
    let resetsAt: String?
    let scope: WireScope?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }
}

private struct WireScope: Decodable {
    let model: WireModel?
    let surface: String?

    struct WireModel: Decodable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
}

private struct WireNamedLimit: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    func asLimit(
        kind: UsageLimit.Kind, group: UsageLimit.Group, scope: UsageLimit.Scope? = nil
    ) -> UsageLimit {
        let percent = utilization ?? 0
        return UsageLimit(
            kind: kind,
            group: group,
            percent: percent,
            severity: .derived(fromPercent: percent),
            resetsAt: resetsAt.flatMap(ISO8601.date(from:)),
            scope: scope,
            isActive: false
        )
    }
}

private struct WireSpend: Decodable {
    let used: WireMoney?
    let limit: WireMoney?
    let percent: Double?
    let severity: String?
    let enabled: Bool?

    struct WireMoney: Decodable {
        let amountMinor: Int?
        let currency: String?
        let exponent: Int?

        enum CodingKeys: String, CodingKey {
            case currency, exponent
            case amountMinor = "amount_minor"
        }

        /// 1250 minor units at exponent 2 → 12.50.
        var majorUnits: Decimal {
            Decimal(amountMinor ?? 0) / pow(Decimal(10), exponent ?? 2)
        }
    }
}

// MARK: - Wire → domain

extension UsageLimit {
    /// Returns `nil` for entries missing the fields we cannot invent.
    fileprivate init?(wire: WireLimit) {
        guard let kind = wire.kind, let percent = wire.percent else { return nil }

        self.init(
            kind: Kind(rawValue: kind),
            group: Group(rawValue: wire.group ?? "other"),
            percent: percent,
            severity: Severity(rawValue: wire.severity ?? "normal"),
            resetsAt: wire.resetsAt.flatMap(ISO8601.date(from:)),
            scope: wire.scope.flatMap(Scope.init(wire:)),
            isActive: wire.isActive ?? false
        )
    }
}

extension UsageLimit.Scope {
    fileprivate init?(wire: WireScope) {
        // A scope with nothing in it tells the user nothing.
        guard wire.model != nil || wire.surface != nil else { return nil }
        self.init(
            modelID: wire.model?.id,
            modelDisplayName: wire.model?.displayName,
            surface: wire.surface
        )
    }
}

extension UsageSnapshot.Spend {
    fileprivate init(wire: WireSpend) {
        self.init(
            isEnabled: wire.enabled ?? false,
            percent: wire.percent ?? 0,
            usedAmount: wire.used?.majorUnits ?? 0,
            limitAmount: wire.limit?.majorUnits,
            currencyCode: wire.used?.currency ?? wire.limit?.currency,
            severity: Severity(rawValue: wire.severity ?? "normal")
        )
    }
}

// MARK: - Timestamps

/// The API mixes `…+00:00` offsets with fractional seconds of varying length,
/// which no single `ISO8601DateFormatter` configuration handles. Try both.
///
/// Formatters are built per call rather than cached in a `static let`:
/// `ISO8601DateFormatter` is a non-`Sendable` class, and we parse a handful of
/// timestamps a minute, so a shared instance would buy nothing and cost
/// concurrency safety.
enum ISO8601 {
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
