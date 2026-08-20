import Foundation

/// Cursor's plan usage, decoded from the dashboard payloads it already serves
/// the app.
///
/// Two shapes exist: the current billing-cycle object from
/// `GetCurrentPeriodUsage`, and the older request-count object from
/// `/auth/usage`. Both collapse into the same `UsageSnapshot` the rest of
/// Ration already knows how to draw.
///
/// Dates on the current payload arrive as unix-milliseconds — sometimes a
/// string, sometimes a number, occasionally ISO-8601. Missing that conversion
/// is how the Usage tab could show a gauge and still hide the burn-rate card:
/// `WindowProjection` needs a reset time and a window length.
public enum CursorUsage {

    public enum Error: Swift.Error, Equatable {
        case malformed
    }

    public static func snapshot(
        fromPeriod data: Data,
        planName: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw Error.malformed
        }

        let usage = object(root["planUsage"]) ?? object(root["plan_usage"])
        guard let usage else { throw Error.malformed }

        let percent =
            CursorJSON.double(usage["totalPercentUsed"])
            ?? CursorJSON.double(usage["total_percent_used"])
            ?? spendPercent(usage)
        guard let percent else { throw Error.malformed }

        let start =
            CursorJSON.date(root["billingCycleStart"])
            ?? CursorJSON.date(root["billing_cycle_start"])
        let end =
            CursorJSON.date(root["billingCycleEnd"])
            ?? CursorJSON.date(root["billing_cycle_end"])
        let window: TimeInterval? =
            if let start, let end, end > start { end.timeIntervalSince(start) } else { nil }

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

        if let auto = CursorJSON.double(usage["autoPercentUsed"])
            ?? CursorJSON.double(usage["auto_percent_used"])
        {
            limits.append(
                UsageLimit(
                    kind: .other("auto"),
                    group: .other("monthly"),
                    percent: auto,
                    severity: .derived(fromPercent: auto),
                    resetsAt: end,
                    windowLength: window))
        }
        if let api = CursorJSON.double(usage["apiPercentUsed"])
            ?? CursorJSON.double(usage["api_percent_used"])
        {
            limits.append(
                UsageLimit(
                    kind: .other("api"),
                    group: .other("monthly"),
                    percent: api,
                    severity: .derived(fromPercent: api),
                    resetsAt: end,
                    windowLength: window))
        }

        if let onDemand = onDemandLimit(from: root, resetsAt: end, windowLength: window) {
            limits.append(onDemand)
        }

        let spend: UsageSnapshot.Spend? = spend(from: usage, percent: percent)

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
        let used = CursorJSON.double(bucket?["numRequests"])
        let limit = CursorJSON.double(bucket?["maxRequestUsage"])
        guard let used, let limit, limit > 0 else { throw Error.malformed }

        let percent = min(max(used / limit * 100, 0), 100)
        let start =
            CursorJSON.date(root["startOfMonth"])
            ?? CursorJSON.date(root["start_of_month"])
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

    // MARK: History events

    /// Per-request rows from `GetFilteredUsageEvents`. These carry timestamps,
    /// which is what the Activity calendar and Trends charts need.
    public static func events(fromFiltered data: Data) -> [UsageEvent] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        let rows =
            root["usageEventsDisplay"] as? [Any]
            ?? root["usage_events_display"] as? [Any]
            ?? root["usageEvents"] as? [Any]
            ?? root["usage_events"] as? [Any]
            ?? []

        return rows.enumerated().compactMap { index, row in
            event(fromUsageRow: object(row), index: index)
        }
    }

    /// Period totals from `GetAggregatedUsageEvents`. No per-day timestamps,
    /// so each model becomes one event stamped at `at` — enough for Detail,
    /// and a last-resort Activity/Trends point when the filtered log is empty.
    public static func events(fromAggregated data: Data, at date: Date) -> [UsageEvent] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        let rows =
            root["aggregations"] as? [Any]
            ?? object(root["aggregation"])?["aggregations"] as? [Any]
            ?? []

        return rows.enumerated().compactMap { index, row in
            guard let body = object(row) else { return nil }
            let model =
                (body["modelIntent"] as? String)
                ?? (body["model_intent"] as? String)
                ?? (body["model"] as? String)
                ?? "unknown"
            let input =
                CursorJSON.int(body["inputTokens"])
                ?? CursorJSON.int(body["input_tokens"])
                ?? 0
            let output =
                CursorJSON.int(body["outputTokens"])
                ?? CursorJSON.int(body["output_tokens"])
                ?? 0
            let cacheRead =
                CursorJSON.int(body["cacheReadTokens"])
                ?? CursorJSON.int(body["cache_read_tokens"])
                ?? 0
            let cacheWrite =
                CursorJSON.int(body["cacheWriteTokens"])
                ?? CursorJSON.int(body["cache_write_tokens"])
                ?? 0
            guard input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0 else { return nil }
            return UsageEvent(
                timestamp: date,
                model: model,
                project: "Cursor",
                sessionID: "cursor-agg-\(model)-\(index)",
                inputTokens: input,
                outputTokens: output,
                cacheWrite5mTokens: cacheWrite,
                cacheReadTokens: cacheRead)
        }
    }

    // MARK: Rows

    private static func event(fromUsageRow row: [String: Any]?, index: Int) -> UsageEvent? {
        guard let row else { return nil }
        let usage = object(row["tokenUsage"]) ?? object(row["token_usage"]) ?? row
        let input =
            CursorJSON.int(usage["inputTokens"])
            ?? CursorJSON.int(usage["input_tokens"])
            ?? 0
        let output =
            CursorJSON.int(usage["outputTokens"])
            ?? CursorJSON.int(usage["output_tokens"])
            ?? 0
        let cacheRead =
            CursorJSON.int(usage["cacheReadTokens"])
            ?? CursorJSON.int(usage["cache_read_tokens"])
            ?? 0
        let cacheWrite =
            CursorJSON.int(usage["cacheWriteTokens"])
            ?? CursorJSON.int(usage["cache_write_tokens"])
            ?? 0
        guard input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0 else { return nil }

        let timestamp =
            CursorJSON.date(row["timestamp"])
            ?? CursorJSON.date(row["createdAt"])
            ?? Date()
        let model =
            (row["model"] as? String)
            ?? (row["modelIntent"] as? String)
            ?? (row["model_intent"] as? String)
            ?? "unknown"
        let millis = Int64((timestamp.timeIntervalSince1970 * 1000).rounded())
        return UsageEvent(
            timestamp: timestamp,
            model: model,
            project: "Cursor",
            sessionID: "cursor-event-\(millis)-\(index)",
            inputTokens: input,
            outputTokens: output,
            cacheWrite5mTokens: cacheWrite,
            cacheReadTokens: cacheRead)
    }

    // MARK: Spend

    private static func spendPercent(_ usage: [String: Any]) -> Double? {
        let used =
            CursorJSON.double(usage["totalSpend"])
            ?? CursorJSON.double(usage["total_spend"])
        let limit = CursorJSON.double(usage["limit"])
        guard let used, let limit, limit > 0 else { return nil }
        return used / limit * 100
    }

    private static func spend(from usage: [String: Any], percent: Double) -> UsageSnapshot.Spend? {
        guard
            let used = CursorJSON.double(usage["totalSpend"])
                ?? CursorJSON.double(usage["total_spend"])
        else { return nil }
        let limit = CursorJSON.double(usage["limit"])
        return UsageSnapshot.Spend(
            isEnabled: true,
            percent: percent,
            usedAmount: Decimal(used) / 100,
            limitAmount: limit.map { Decimal($0) / 100 },
            currencyCode: "USD",
            severity: .derived(fromPercent: percent))
    }

    /// On-demand / spend-cap, when Cursor reports one alongside the included
    /// monthly allowance. Same card as Claude's extra rows: a second limit
    /// rather than a Cursor-only widget.
    private static func onDemandLimit(
        from root: [String: Any],
        resetsAt: Date?,
        windowLength: TimeInterval?
    ) -> UsageLimit? {
        let body =
            object(root["spendLimitUsage"])
            ?? object(root["spend_limit_usage"])
        guard let body else { return nil }

        let limit = CursorJSON.firstDouble(
            body,
            keys: [
                "pooledLimit", "pooled_limit", "individualLimit", "individual_limit", "limit",
            ])
        let used =
            CursorJSON.firstDouble(
                body,
                keys: [
                    "pooledUsed", "pooled_used", "individualUsed", "individual_used",
                    "totalSpend", "total_spend",
                ]) ?? 0
        guard let limit, limit > 0 else { return nil }
        let percent = min(max(used / limit * 100, 0), 100)
        return UsageLimit(
            kind: .other("on_demand"),
            group: .other("monthly"),
            percent: percent,
            severity: .derived(fromPercent: percent),
            resetsAt: resetsAt,
            windowLength: windowLength)
    }

    private static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }
}
