import Foundation

/// Cursor's plan usage, decoded from the dashboard payloads it already serves
/// the app.
///
/// Two shapes exist: the current billing-cycle object from
/// `GetCurrentPeriodUsage`, and the older request-count object from
/// `/auth/usage`. Both collapse into the same `UsageSnapshot` the rest of
/// Ration already knows how to draw.
public enum CursorUsage {

    public enum Error: Swift.Error, Equatable {
        case malformed
    }

    public static func snapshot(
        fromPeriod data: Data,
        planName: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        let payload: PeriodPayload
        do {
            payload = try JSONDecoder().decode(PeriodPayload.self, from: data)
        } catch {
            throw Error.malformed
        }

        guard let usage = payload.planUsage else { throw Error.malformed }

        let percent = usage.totalPercentUsed ?? usage.spendPercent
        guard let percent else { throw Error.malformed }

        let start = payload.billingCycleStart.flatMap(ISO8601.date(from:))
        let end = payload.billingCycleEnd.flatMap(ISO8601.date(from:))
        let window: TimeInterval? =
            if let start, let end { end.timeIntervalSince(start) } else { nil }

        var limits: [UsageLimit] = [
            UsageLimit(
                kind: .other("monthly"),
                group: .other("monthly"),
                percent: percent,
                severity: .derived(fromPercent: percent),
                resetsAt: end,
                isActive: true,
                windowLength: window)
        ]

        if let auto = usage.autoPercentUsed {
            limits.append(
                UsageLimit(
                    kind: .other("auto"),
                    group: .other("monthly"),
                    percent: auto,
                    severity: .derived(fromPercent: auto),
                    resetsAt: end,
                    windowLength: window))
        }
        if let api = usage.apiPercentUsed {
            limits.append(
                UsageLimit(
                    kind: .other("api"),
                    group: .other("monthly"),
                    percent: api,
                    severity: .derived(fromPercent: api),
                    resetsAt: end,
                    windowLength: window))
        }

        let spend: UsageSnapshot.Spend? = usage.spend(
            percent: percent, derived: .derived(fromPercent: percent))

        return UsageSnapshot(
            limits: limits, spend: spend, fetchedAt: fetchedAt, planName: planName)
    }

    public static func snapshot(
        fromAuthUsage data: Data,
        planName: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw Error.malformed
        }

        let bucket =
            root["gpt-4"] as? [String: Any]
            ?? root.values.compactMap { $0 as? [String: Any] }.first {
                $0["numRequests"] != nil
            }
        let used = number(bucket?["numRequests"])
        let limit = number(bucket?["maxRequestUsage"])
        guard let used, let limit, limit > 0 else { throw Error.malformed }

        let percent = min(max(used / limit * 100, 0), 100)
        let start = (root["startOfMonth"] as? String).flatMap(ISO8601.date(from:))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let end = start.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        let window: TimeInterval? =
            if let start, let end { end.timeIntervalSince(start) } else { nil }

        return UsageSnapshot(
            limits: [
                UsageLimit(
                    kind: .other("monthly"),
                    group: .other("monthly"),
                    percent: percent,
                    severity: .derived(fromPercent: percent),
                    resetsAt: end,
                    isActive: true,
                    windowLength: window)
            ],
            fetchedAt: fetchedAt,
            planName: planName)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let int as Int: Double(int)
        default: nil
        }
    }
}

// MARK: - Period wire format

private struct PeriodPayload: Decodable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let planUsage: PlanUsage?
}

private struct PlanUsage: Decodable {
    let totalSpend: Double?
    let includedSpend: Double?
    let bonusSpend: Double?
    let limit: Double?
    let totalPercentUsed: Double?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?

    /// When the dashboard omits `totalPercentUsed` but still reports cents.
    var spendPercent: Double? {
        guard let used = totalSpend, let limit, limit > 0 else { return nil }
        return used / limit * 100
    }

    func spend(percent: Double, derived: Severity) -> UsageSnapshot.Spend? {
        guard let used = totalSpend else { return nil }
        return UsageSnapshot.Spend(
            isEnabled: true,
            percent: percent,
            usedAmount: Decimal(used) / 100,
            limitAmount: limit.map { Decimal($0) / 100 },
            currencyCode: "USD",
            severity: derived)
    }
}
