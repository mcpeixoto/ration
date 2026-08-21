import Foundation
import Testing

@testable import RationKit

private func scratch() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "ration-companion-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appending(path: "companion.json")
}

private let epoch = Date(timeIntervalSinceReferenceDate: 0)

@Suite("Companion store: on disk")
struct CompanionStoreTests {

    @Test("a profile that has never run the loop starts empty")
    func freshProfile() {
        let store = CompanionStore(url: scratch())

        #expect(store.isUnstarted)
        #expect(store.load() == CompanionState())
    }

    @Test("a whole state survives a round trip, dates and all")
    func roundTrip() {
        let store = CompanionStore(url: scratch())
        var state = CompanionState()
        var rng = SeededGenerator(seed: 5)
        CompanionEngine.credit(&state, lifetimeByProvider: ["claude": 0], now: epoch, using: &rng)
        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 900_000_000], now: epoch, using: &rng)
        state.inventory[ItemKind.overclock.rawValue] = 2
        state.archive = ["sparkit", "promptail"]
        state.pinnedID = "sparkit"

        store.save(state)
        let read = store.load()

        #expect(read == state)
        #expect(!read.log.isEmpty, "the fixture should have filed something")
        #expect(read.log.first?.filedAt == epoch, "dates must survive, not silently vanish")
        #expect(!store.isUnstarted)
    }

    /// Losing a binder to one bad key would be the worst possible failure here, so the
    /// decode is deliberately forgiving.
    @Test("one unreadable field costs its own default and nothing else")
    func lenientField() throws {
        let url = scratch()
        let json = """
            {
              "creditedTokens": "not a number",
              "spentTokens": 40,
              "filedFinals": ["weeklyrex"],
              "archive": ["sparkit"],
              "inventory": {"overclock": 3},
              "packUsage": 12,
              "grantsSeeded": true,
              "log": []
            }
            """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let state = CompanionStore(url: url).load()

        #expect(state.creditedTokens == 0)
        #expect(state.spentTokens == 40)
        #expect(state.filedFinals == ["weeklyrex"])
        #expect(state.archive == ["sparkit"])
        #expect(state.itemCount(.overclock) == 3)
        #expect(state.packUsage == 12)
    }

    @Test("a corrupt entry in the catch log drops itself, not the log")
    func lossyLogRow() throws {
        let url = scratch()
        let json = """
            {
              "log": [
                {"id": "a", "rootID": "loopet", "finalID": "weeklyrex",
                 "chain": ["loopet", "limitwyrm", "weeklyrex"], "trait": "eager",
                 "isShiny": false, "filedAt": "2026-08-21T09:00:00Z"},
                {"id": "b", "rootID": "loopet"},
                {"id": "c", "rootID": "sparkit", "finalID": "sparkit",
                 "chain": ["sparkit"], "trait": "wry",
                 "isShiny": true, "filedAt": "2026-08-21T10:00:00Z"}
              ]
            }
            """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let state = CompanionStore(url: url).load()

        #expect(state.log.map(\.id) == ["a", "c"])
        #expect(state.log.last?.isShiny == true)
    }

    /// An unknown floor must degrade to "no promise". Inventing one would hand out a
    /// guarantee nobody paid for.
    @Test("an unreadable pack guarantee becomes no guarantee")
    func unknownGuarantee() throws {
        let url = scratch()
        try #"{"packGuarantee": "ultra", "packUsage": 9}"#
            .write(to: url, atomically: true, encoding: .utf8)

        let state = CompanionStore(url: url).load()

        #expect(state.packGuarantee == nil)
        #expect(state.packUsage == 9)
    }

    /// Absent and unreadable have to stay different: absent re-seeds from the current
    /// reading, unreadable is already seeded and must not credit a whole history.
    @Test("a missing ledger seeds, an empty one does not")
    func ledgerAbsenceIsMeaningful() throws {
        let missing = scratch()
        try "{}".write(to: missing, atomically: true, encoding: .utf8)
        let empty = scratch()
        try #"{"claimedLifetimeTokensByProvider": {}}"#
            .write(to: empty, atomically: true, encoding: .utf8)

        #expect(CompanionStore(url: missing).load().claimedLifetimeTokensByProvider == nil)
        #expect(CompanionStore(url: empty).load().claimedLifetimeTokensByProvider == [:])

        var seeded = CompanionStore(url: empty).load()
        var rng = SeededGenerator(seed: 1)
        CompanionEngine.credit(
            &seeded, lifetimeByProvider: ["claude": 800_000_000], now: epoch, using: &rng)
        #expect(seeded.creditedTokens == 800_000_000, "an empty ledger credits from zero")
    }

    @Test("a file that is not a state at all is moved aside, not read")
    func quarantine() throws {
        let url = scratch()
        try "this is not json".write(to: url, atomically: true, encoding: .utf8)
        let store = CompanionStore(url: url)

        let state = store.load()
        let wreck = url.deletingPathExtension().appendingPathExtension("corrupt.json")

        #expect(state == CompanionState())
        #expect(FileManager.default.fileExists(atPath: wreck.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// The three-writer case. Two stores over one file must not bank the same tokens
    /// twice, because `mutate` re-reads and crediting is a rise over what is claimed.
    @Test("two processes over one file credit a spend exactly once")
    func twoWritersCreditOnce() {
        let url = scratch()
        let tray = CompanionStore(url: url)
        let cli = CompanionStore(url: url)
        let reading = ["claude": 3_000_000, "codex": 1_000_000]

        for store in [tray, cli] {
            store.mutate { state in
                var rng = SeededGenerator(seed: 1)
                CompanionEngine.credit(
                    &state, lifetimeByProvider: ["claude": 0, "codex": 0], now: epoch, using: &rng)
            }
        }
        for store in [tray, cli, tray, cli] {
            store.mutate { state in
                var rng = SeededGenerator(seed: 1)
                CompanionEngine.credit(
                    &state, lifetimeByProvider: reading, now: epoch, using: &rng)
            }
        }

        #expect(tray.load().creditedTokens == 4_000_000)
    }

    /// The tray calls this on a timer and most ticks have nothing to credit. Rewriting
    /// an identical file every few seconds would churn the disk and turn every idle
    /// tick into a chance to lose a race with the CLI for nothing.
    @Test("a change that changed nothing is not written")
    func noOpDoesNotWrite() throws {
        let url = scratch()
        let store = CompanionStore(url: url)
        store.mutate { $0.pinnedID = "sparkit" }
        let stamp =
            try FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        store.mutate { state in state.pinnedID = "sparkit" }
        let after =
            try FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        #expect(after == stamp)
        #expect(store.load().pinnedID == "sparkit")
    }

    /// Migration only runs while the file is absent, so the first sync has to leave
    /// something behind even for somebody with no tools set up yet — otherwise it
    /// migrates again on every launch.
    @Test("the first sync writes a file even with nothing to credit")
    func firstSyncLandsOnDisk() {
        let store = CompanionStore(url: scratch())

        CompanionSync.refresh(store, lifetimeByProvider: [:], archive: { [] })

        #expect(!store.isUnstarted)
        #expect(store.load().claimedLifetimeTokensByProvider == [:])
    }

    @Test("mutate writes what it changed and hands back its result")
    func mutateWrites() {
        let store = CompanionStore(url: scratch())

        let pinned = store.mutate { state -> String in
            state.pinnedID = "sparkit"
            return state.pinnedID ?? ""
        }

        #expect(pinned == "sparkit")
        #expect(store.load().pinnedID == "sparkit")
    }
}

@Suite("Companion store: migration from the old collection")
struct CompanionMigrationTests {

    /// Midday on a fixed date, so a run after 10pm cannot catch Nightshift by accident
    /// — the same trap `DexTests` documents.
    private static let noon: Date = {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 12
        parts.hour = 12
        return Calendar(identifier: .gregorian).date(from: parts)!
    }()

    private func oldCollection(billable: Int) -> DexState {
        var history = UsageHistory()
        history.add(
            [
                UsageEvent(
                    timestamp: Self.noon, model: "claude-opus-5", project: "p", sessionID: "s",
                    inputTokens: billable, outputTokens: 0, cacheReadTokens: 0)
            ],
            calendar: Calendar(identifier: .gregorian))
        return Dex.evaluate(
            DexInput(
                histories: ["claude": history], now: Self.noon,
                calendar: Calendar(identifier: .gregorian)))
    }

    @Test("what the old model unlocked becomes a read-only Set 01 mark")
    func archivesOldUnlocks() {
        let previous = oldCollection(billable: 3_000_000)

        let state = CompanionStore.migrated(
            archive: Set(previous.caught.map(\.id)),
            lifetimeByProvider: ["claude": 3_000_000])

        #expect(!previous.caught.isEmpty, "the fixture should unlock something")
        #expect(state.archive == Set(previous.caught.map(\.id)))
        #expect(state.log.isEmpty)
        #expect(state.filedSpecies.isEmpty)
        #expect(state.active == nil)
        #expect(state.packUsage == 0)
    }

    /// Skip this and a long history lands as one credit, filing a dozen creatures in
    /// the first poll after the update.
    @Test("the ledger starts from today, so no history is paid out retroactively")
    func noRetroactiveWindfall() {
        var state = CompanionStore.migrated(
            archive: Set(oldCollection(billable: 5_000_000_000).caught.map(\.id)),
            lifetimeByProvider: ["claude": 5_000_000_000])
        var rng = SeededGenerator(seed: 1)

        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 5_000_000_000], now: epoch, using: &rng)

        #expect(state.creditedTokens == 0)
        #expect(state.wallet == 0)
        #expect(state.active == nil)
    }

    @Test("creatures already revealed do not queue up a reveal storm")
    func foldsRevealed() {
        let state = CompanionStore.migrated(
            archive: Set(oldCollection(billable: 1_000).caught.map(\.id))
                .union(["modelith", "streakon"]),
            lifetimeByProvider: [:])

        #expect(state.archive.contains("modelith"))
        #expect(state.archive.contains("streakon"))
    }

    @Test("growth after migrating starts the loop normally")
    func loopStartsAfterMigration() {
        var state = CompanionStore.migrated(
            archive: Set(oldCollection(billable: 900_000_000).caught.map(\.id)),
            lifetimeByProvider: ["claude": 900_000_000])
        var rng = SeededGenerator(seed: 3)

        CompanionEngine.credit(
            &state, lifetimeByProvider: ["claude": 905_000_000], now: epoch, using: &rng)

        #expect(state.creditedTokens == 5_000_000)
        #expect(state.active != nil, "the first five million should rip a pack")
    }
}
