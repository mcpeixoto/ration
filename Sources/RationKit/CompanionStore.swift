import Foundation

/// The companion state on disk, and the discipline three processes need to share it.
///
/// `Ration.app`, `ration-tray` and `ration watch` can all be running at once against
/// one file. Every change therefore goes through `mutate`, which re-reads immediately
/// before applying and writes atomically — the same rule the tray already follows for
/// `AppConfig` after marking one creature revealed dropped the forty-three the CLI had
/// just written. Crediting is idempotent on top of that (`CompanionEngine.credit`), so
/// two writers racing costs a re-read, never a double payout.
public struct CompanionStore: Sendable {

    public let url: URL

    public init(url: URL = CompanionStore.defaultURL) {
        self.url = url
    }

    /// Beside `AppConfig`, so a profile is one directory.
    ///
    /// `RATION_STATE_DIR` moves it, which is the only way to exercise the loop without
    /// writing to a real profile: `NSHomeDirectory()` ignores `HOME` on Linux, so
    /// pointing `HOME` at a scratch directory does not work. Used by the screenshot
    /// harness and by anyone driving `ration dex simulate`.
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["RATION_STATE_DIR"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appending(path: "companion.json")
        }
        return AppConfig.url.deletingLastPathComponent().appending(path: "companion.json")
    }

    // MARK: Reading and writing

    /// The state on disk, or a fresh one. A file that cannot be parsed at all is moved
    /// aside first so the next launch starts clean instead of failing the same way for
    /// ever — and so the wreckage is still there to look at.
    public func load() -> CompanionState {
        guard let data = try? Data(contentsOf: url) else { return CompanionState() }
        if let state = try? Self.decoder.decode(CompanionState.self, from: data) {
            return state
        }
        quarantine()
        return CompanionState()
    }

    /// Dates are ISO-8601 so the file reads as text when somebody opens it. The two
    /// strategies have to be set together — an encoder on ISO-8601 against a decoder on
    /// the default silently loses every date, which here means every filed creature.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func save(_ state: CompanionState) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Read, change, write. The read happens here rather than at the call site so a
    /// caller cannot accidentally hold a stale copy across a poll.
    ///
    /// A change that changed nothing is not written. The tray calls this on a timer and
    /// most of those calls have no new tokens to credit; rewriting an identical file
    /// every few seconds would churn the disk and, worse, make every one of those ticks
    /// a chance to lose a race with the CLI for no gain at all.
    @discardableResult
    public func mutate<T>(_ change: (inout CompanionState) -> T) -> T {
        let before = load()
        var state = before
        let result = change(&state)
        if state != before { save(state) }
        return result
    }

    private func quarantine() {
        let wreck = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        try? FileManager.default.removeItem(at: wreck)
        try? FileManager.default.moveItem(at: url, to: wreck)
    }

    // MARK: Starting from what is already there

    /// Fold the old threshold-based collection into a new save, once.
    ///
    /// The unlocks somebody already has become a read-only Set 01 mark rather than a
    /// head start: they stay visible in the binder and stay shareable, but the new loop
    /// begins from an empty binder and a sealed pack. `revealedCreatureIDs` folds in
    /// too, so nobody is greeted by a reveal queue for cards they saw months ago.
    ///
    /// The ledger baseline is seeded from the current reading in the same breath. Skip
    /// that and a two-year history lands as one enormous credit, filing a dozen
    /// creatures in the first poll after an update.
    public static func migrated(
        archive: Set<String>,
        lifetimeByProvider: [String: Int]
    ) -> CompanionState {
        var state = CompanionState()
        state.archive = archive
        state.claimedLifetimeTokensByProvider = lifetimeByProvider.mapValues { max(0, $0) }
        return state
    }

    /// True when this profile has never run the loop. Callers use it to decide whether
    /// to migrate; the file's absence is the only signal, so writing anything at all
    /// ends the migration window.
    public var isUnstarted: Bool {
        !FileManager.default.fileExists(atPath: url.path)
    }
}
