import Foundation

/// Decodes the `rate_limits` object Codex writes into its rollout files.
///
/// Codex records its own quota alongside the token counts, which means Ration
/// can show a Codex gauge without asking anyone for anything — no request, no
/// credential, no new host. The catch is that the numbers are only as fresh as
/// the last time Codex ran, which is why the timestamp travels with them.
public enum CodexRateLimits {

    /// Builds a snapshot from one `token_count` record's payload.
    ///
    /// Returns `nil` when the record carries no rate limits, which is normal —
    /// only some records do.
    public static func snapshot(from payload: [String: Any], at timestamp: Date) -> UsageSnapshot? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }

        var parsed: [UsageLimit] = []
        for key in ["primary", "secondary", "primary_window", "secondary_window"] {
            if let window = limits[key] as? [String: Any],
                let limit = self.limit(from: window, now: timestamp)
            {
                parsed.append(limit)
            }
        }
        // Some builds report extras in a list rather than as named keys.
        for window in limits["additional_rate_limits"] as? [[String: Any]] ?? [] {
            if let limit = self.limit(from: window, now: timestamp) { parsed.append(limit) }
        }

        guard !parsed.isEmpty else { return nil }

        return UsageSnapshot(
            limits: deduplicated(parsed),
            fetchedAt: timestamp,
            planName: limits["plan_type"] as? String)
    }

    /// One window.
    ///
    /// Field names differ between Codex builds — `window_minutes`/`resets_at`
    /// in the current one, `limit_window_seconds`/`reset_at` in others — so both
    /// spellings are accepted rather than pinning whichever happened to be
    /// installed when this was written.
    static func limit(from window: [String: Any], now: Date) -> UsageLimit? {
        guard let percent = number(window["used_percent"]) else { return nil }

        let seconds: TimeInterval? =
            number(window["window_minutes"]).map { $0 * 60 }
            ?? number(window["limit_window_seconds"])

        // Epoch seconds, not the ISO8601 string Anthropic uses.
        let resetsAt =
            (number(window["resets_at"]) ?? number(window["reset_at"]))
            .map(Date.init(timeIntervalSince1970:))

        let kind = self.kind(forWindowOf: seconds)

        return UsageLimit(
            kind: kind,
            group: group(for: kind),
            percent: min(max(percent, 0), 100),
            // Codex reports no severity of its own, so it is derived from the
            // percentage using the same thresholds as everywhere else.
            severity: Severity.derived(fromPercent: percent),
            resetsAt: resetsAt,
            isActive: false,
            windowLength: seconds)
    }

    /// Which lane a window belongs to, decided by **how long it is**.
    ///
    /// Not by whether Codex called it `primary` or `secondary`. Those name
    /// whichever limit is currently binding, and they swap: on the machine this
    /// was written against, `primary` was the weekly window and `secondary` was
    /// absent, while an earlier capture had `primary` as the 5-hour one. Reading
    /// the position instead of the duration mislabels the gauge roughly half
    /// the time.
    static func kind(forWindowOf seconds: TimeInterval?) -> UsageLimit.Kind {
        guard let seconds else { return .other("window") }
        switch seconds {
        case 5 * 3600: return .session
        case 7 * 24 * 3600: return .weeklyAll
        default: return .other("window_\(Int(seconds / 60))m")
        }
    }

    private static func group(for kind: UsageLimit.Kind) -> UsageLimit.Group {
        switch kind {
        case .session: .session
        case .weeklyAll, .weeklyScoped: .weekly
        case .other(let raw): .other(raw)
        }
    }

    /// The same window can appear under two keys across builds. Keep the first.
    private static func deduplicated(_ limits: [UsageLimit]) -> [UsageLimit] {
        var seen: Set<String> = []
        return limits.filter { seen.insert($0.id).inserted }
    }

    /// JSON numbers arrive as `Int` or `Double` depending on how they were
    /// written; `45` and `45.0` mean the same thing here.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let int as Int: Double(int)
        default: nil
        }
    }
}
