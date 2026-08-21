import Foundation
import RationKit

/// The shop and the bag. Tokens already spent on real work are the currency, so this
/// never asks for money and never leaves the machine.
@MainActor
enum ShopCommand {

    static func shop(subcommand: String?, args: [String], config: CLIConfig) async {
        let state = await refreshed(config: config)

        guard subcommand == "buy" else {
            list(state)
            return
        }
        guard let key = args.first, let entry = entry(named: key) else {
            print("Usage: ration shop buy <\(keys().joined(separator: "|"))>")
            return
        }
        guard CompanionEngine.canBuy(entry, state) else {
            print(reasonCannotBuy(entry, state))
            return
        }
        let events = CompanionStore().mutate { state -> [CompanionEvent] in
            var rng = SystemRandomNumberGenerator()
            return CompanionEngine.buy(entry, &state, now: Date(), using: &rng)
        }
        DexCommand.report(events)
        list(CompanionStore().load())
    }

    static func bag(subcommand: String?, args: [String], config: CLIConfig) async {
        let state = await refreshed(config: config)

        guard subcommand == "use" else {
            printBag(state)
            return
        }
        guard let key = args.first, let kind = ItemKind(rawValue: key.lowercased()) else {
            let usable = ItemKind.allCases.filter { !$0.isPassive }.map(\.rawValue)
            print("Usage: ration bag use <\(usable.joined(separator: "|"))>")
            return
        }
        guard CompanionEngine.canUse(kind, state) else {
            print(reasonCannotUse(kind, state))
            return
        }
        let events = CompanionStore().mutate { state -> [CompanionEvent] in
            var rng = SystemRandomNumberGenerator()
            return CompanionEngine.use(kind, &state, now: Date(), using: &rng)
        }
        DexCommand.report(events)
        printBag(CompanionStore().load())
    }

    // MARK: Printing

    private static func list(_ state: CompanionState) {
        print("Wallet: \(PowerFormat.compact(state.wallet))")
        print()
        for entry in CompanionEngine.shopEntries(state) {
            let name = DexCommand.label(entry)
            let status: String
            if case .item(let kind) = entry, kind.isPassive, state.itemCount(kind) > 0 {
                status = "held"
            } else if CompanionEngine.canBuy(entry, state) {
                status = "buy \(key(entry))"
            } else {
                status = "—"
            }
            print(
                "  \(pad(name, 16))\(pad(PowerFormat.compact(entry.price), 10))\(pad(status, 16))"
                    + detail(entry))
        }
        print()
        print("  ration shop buy <name>")
    }

    private static func printBag(_ state: CompanionState) {
        guard !state.heldItems.isEmpty else {
            print("The bag is empty. Fill a limit window to earn an Overclock.")
            return
        }
        for (kind, count) in state.heldItems {
            let note = kind.isPassive ? "held" : "×\(count)"
            print("  \(pad(kind.label, 14))\(pad(note, 8))\(kind.detail)")
        }
        if state.active == nil {
            print()
            print("Nothing to use these on until the pack rips.")
        }
    }

    private static func detail(_ entry: ShopEntry) -> String {
        switch entry {
        case .item(let kind): kind.detail
        case .pack(nil): "Discards what you are raising and seals a new pack."
        case .pack(.some(let floor)): "A new pack, guaranteed to reach \(floor.label) or better."
        }
    }

    // MARK: Why not

    private static func reasonCannotBuy(_ entry: ShopEntry, _ state: CompanionState) -> String {
        if case .item(let kind) = entry, kind.isPassive, state.itemCount(kind) > 0 {
            return "You already hold a \(kind.label). It never wears out."
        }
        let short = entry.price - state.wallet
        return "Not enough in the wallet — \(PowerFormat.compact(short)) short."
    }

    private static func reasonCannotUse(_ kind: ItemKind, _ state: CompanionState) -> String {
        if kind.isPassive { return "A \(kind.label) works on its own. There is nothing to use." }
        if state.itemCount(kind) == 0 { return "No \(kind.label) in the bag." }
        return "Nothing to use it on until the pack rips."
    }

    // MARK: Names

    private static func keys() -> [String] {
        ItemKind.allCases.map(\.rawValue) + ["booster", "foil", "hobby"]
    }

    private static func key(_ entry: ShopEntry) -> String {
        switch entry {
        case .item(let kind): kind.rawValue
        case .pack(nil): "booster"
        case .pack(.rare): "foil"
        case .pack(.epic): "hobby"
        case .pack(.some(let floor)): floor.rawValue
        }
    }

    private static func entry(named key: String) -> ShopEntry? {
        let key = key.lowercased()
        if let kind = ItemKind(rawValue: key) { return .item(kind) }
        return CompanionPack.sold.first { self.key(.pack($0)) == key }.map(ShopEntry.pack)
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width
            ? text + "  " : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    /// The shop is also a poll — buying should never be done against a stale wallet.
    private static func refreshed(config: CLIConfig) async -> CompanionState {
        let registry = CLIContext.registry(config: config)
        await CLIContext.prepareHistories(registry: registry)
        return CLIContext.refreshCompanion(registry: registry, config: config).state
    }
}
