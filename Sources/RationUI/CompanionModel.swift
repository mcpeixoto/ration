import Foundation
import Observation
import RationKit

/// The companion loop, as the app sees it.
///
/// The state itself lives in a file the CLI writes too, so this owns a cached copy
/// rather than the truth: `sync` folds in whatever has been read since the last look,
/// and `mutate` is the only way anything here changes it. Same shape as the Linux
/// tray's, for the same reason — three processes, one file.
@MainActor
@Observable
public final class CompanionModel {

    public private(set) var state = CompanionState()
    /// Rips, evolutions and payouts the panel has not celebrated yet.
    public var events: [CompanionEvent] = []

    private let store: CompanionStore

    public init(store: CompanionStore = CompanionStore()) {
        self.store = store
        state = store.load()
    }

    /// Bring the loop up to date from whatever the registry has read.
    ///
    /// `archive` is what the old threshold model had already unlocked. It is a closure
    /// because it is only needed once in a profile's life, and working it out means
    /// evaluating the whole old model.
    public func sync(
        lifetimeByProvider: [String: Int],
        windows: [LimitWindow],
        archive: () -> Set<String>
    ) {
        let result = CompanionSync.refresh(
            store, lifetimeByProvider: lifetimeByProvider, windows: windows, archive: archive)
        state = result.state
        events += result.events
    }

    /// Buy, use, pin — everything that changes the loop, so the re-read-before-write
    /// rule is kept in one place.
    public func mutate(_ change: (inout CompanionState) -> [CompanionEvent]) {
        var produced: [CompanionEvent] = []
        state = store.mutate { state in
            produced = change(&state)
            return state
        }
        events += produced
    }

    public func buy(_ entry: ShopEntry) {
        mutate { state in
            var rng = SystemRandomNumberGenerator()
            return CompanionEngine.buy(entry, &state, now: Date(), using: &rng)
        }
    }

    public func use(_ kind: ItemKind) {
        mutate { state in
            var rng = SystemRandomNumberGenerator()
            return CompanionEngine.use(kind, &state, now: Date(), using: &rng)
        }
    }

    public func takeEvents() -> [CompanionEvent] {
        defer { events = [] }
        return events
    }

    /// A loop part-way through, backed by a throwaway file.
    ///
    /// For `RationPreview` and SwiftUI previews only. It deliberately does not use the
    /// real store: rendering the docs images must never write to somebody's profile.
    public static func posed() -> CompanionModel {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ration-preview-\(UUID().uuidString)")
        let model = CompanionModel(store: CompanionStore(url: directory.appending(path: "c.json")))
        model.state = .posed()
        return model
    }
}
