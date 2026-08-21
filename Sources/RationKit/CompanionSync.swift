import Foundation

/// The one path every front end takes to move the loop forward.
///
/// The macOS app, the Linux tray and the CLI all poll the same providers and all write
/// the same file, so the order of operations — migrate, pay out, credit — lives here
/// rather than three times over. Each of them supplies numbers; none of them decides
/// rules.
public enum CompanionSync {

    /// Lifetime billable tokens per provider — the reading the ledger is a difference
    /// against. Same figure as the Score, kept per provider so a tool that disappears
    /// from a profile cannot make the total go backwards.
    public static func lifetimeTokens(histories: [String: UsageHistory]) -> [String: Int] {
        histories.mapValues { history in
            history.total(over: history.sortedDays).tokens
        }
    }

    /// The limit windows worth paying out on.
    ///
    /// The key is provider plus the limit's own id — kind, and model where it is
    /// scoped. Never the reset time: a key built from that looks like a brand new
    /// window every few hours and pays out for ever. Limits in a group Ration does not
    /// recognise are skipped rather than guessed at.
    public static func windows(providerID: String, snapshot: UsageSnapshot?) -> [LimitWindow] {
        guard let snapshot else { return [] }
        return snapshot.limits.compactMap { limit in
            let kind: LimitWindow.Kind
            switch limit.group {
            case .session: kind = .session
            case .weekly: kind = .weekly
            case .other: return nil
            }
            return LimitWindow(
                key: "\(providerID)|\(limit.id)",
                name: limit.displayName,
                kind: kind,
                utilization: limit.percent)
        }
    }

    /// Bring the saved loop up to date with what the tools have been used for.
    ///
    /// A profile with no save file yet is migrated first: `archive` is what the old
    /// threshold model had already unlocked, kept as a read-only Set 01 mark, and the
    /// ledger is seeded from the current reading so a long history is not paid out as
    /// one enormous credit. `archive` is a closure because working it out means
    /// evaluating the whole old model, which is wasted on every launch after the first.
    @discardableResult
    public static func refresh(
        _ store: CompanionStore,
        lifetimeByProvider: [String: Int],
        windows: [LimitWindow] = [],
        now: Date = Date(),
        archive: () -> Set<String> = { [] }
    ) -> (state: CompanionState, events: [CompanionEvent]) {
        // Read before the mutate writes, or the migration window closes underneath us.
        let unstarted = store.isUnstarted
        return store.mutate { state in
            if unstarted {
                state = CompanionStore.migrated(
                    archive: archive(), lifetimeByProvider: lifetimeByProvider)
            }
            var rng = SystemRandomNumberGenerator()
            var events = CompanionEngine.grantRewards(&state, windows: windows)
            events += CompanionEngine.credit(
                &state, lifetimeByProvider: lifetimeByProvider, now: now, using: &rng)
            return (state, events)
        }
    }
}
