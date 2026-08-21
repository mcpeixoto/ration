import Foundation
import RationKit

@MainActor
enum DexCommand {

    static func run(options: CLIOptions, config: CLIConfig) async {
        let registry = CLIContext.registry(config: config)
        await CLIContext.prepareHistories(registry: registry)

        for entry in registry.metered where entry.history == nil {
            entry.poller.start()
            if entry.poller.state.status == .idle {
                await waitForRefresh(entry.poller)
            }
            entry.poller.suspend()
        }

        // A run of `ration dex` is also a poll: crediting here means the loop moves
        // for somebody who only ever uses the terminal.
        var (state, events) = CLIContext.refreshCompanion(registry: registry, config: config)

        // Walking the whole loop costs tens of billions of tokens, which is not a thing
        // anybody can do to check a change. Behind RATION_DEBUG so it cannot be reached
        // by accident, and it moves the wallet as well as the growth so the shop is
        // reachable too — otherwise it would only exercise half the feature.
        if let simulated = simulatedGrowth(options.args) {
            state = CompanionStore().mutate { state in
                var rng = SystemRandomNumberGenerator()
                state.creditedTokens += simulated
                events += CompanionEngine.grow(
                    &state, by: simulated, now: Date(), using: &rng)
                return state
            }
        }

        if options.json {
            printJSON(state)
            return
        }

        report(events)
        printCompanion(state)
        printCollection(state)
    }

    // MARK: What is being raised

    private static func printCompanion(_ state: CompanionState) {
        if let run = state.active {
            let creature = Dex.creature(run.currentID)
            let stage = Dex.lore[run.currentID]?.stage.label ?? "Basic"
            let shiny = run.isShiny ? " ✦ shiny" : ""
            print("\(creature?.name ?? run.currentID) · \(stage) · \(run.trait.label)\(shiny)")
            // Never name what it is growing into — the destination is the surprise.
            let toward = run.isFinalForm ? "to file" : "to evolve"
            print(
                "  \(CLIFormat.progressBar(run.progress * 100))  "
                    + "\(PowerFormat.compact(run.remaining)) \(toward)")
            print("  \(lineStrip(run))")
        } else {
            let promise = state.packGuarantee.map { " · \(CompanionPack.label($0))" } ?? ""
            print("Sealed pack\(promise)")
            print(
                "  \(CLIFormat.progressBar(state.packProgress * 100))  "
                    + "\(PowerFormat.compact(state.packRemaining)) to rip")
        }
        print()
    }

    /// Forms reached, then a question mark for each one still to come. The count is not
    /// a secret — which creatures they are is.
    private static func lineStrip(_ run: ActiveRun) -> String {
        let reached = run.revealed.map { Dex.creature($0)?.name ?? $0 }
        let ahead = Array(repeating: "?", count: max(0, run.forms - run.revealed.count))
        return (reached + ahead).joined(separator: " → ")
    }

    // MARK: The binder

    private static func printCollection(_ state: CompanionState) {
        let filed = state.filedSpecies
        let archived = state.archive.subtracting(filed)
        print("Binder — \(filed.count) of \(Dex.roster.count) filed")
        if !archived.isEmpty {
            print("Set 01 archive — \(archived.count)")
        }
        print("Wallet: \(PowerFormat.compact(state.wallet))")
        let held = state.heldItems.map { "\($0.kind.label) ×\($0.count)" }
        if !held.isEmpty {
            print("Bag: \(held.joined(separator: ", "))")
        }
        print()

        if !state.log.isEmpty {
            print("Recent")
            for entry in state.log.suffix(5).reversed() {
                let name = Dex.creature(entry.finalID)?.name ?? entry.finalID
                print(
                    "  \(entry.isShiny ? "✦" : " ") \(pad(name, 14))"
                        + "\(pad(entry.rarity.label, 11))"
                        + "\(pad(entry.trait.label, 12))"
                        + CLIFormat.shortDate(entry.filedAt))
            }
            print()
        }

        for creature in Dex.roster {
            let marker: String
            let name: String
            if filed.contains(creature.id) {
                marker = "✓"
                name = creature.name
            } else if state.archive.contains(creature.id) {
                marker = "·"
                name = creature.name
            } else {
                marker = " "
                name = "???"
            }
            let note =
                state.archive.contains(creature.id) && !filed.contains(creature.id)
                ? "Set 01" : creature.requirement.deed
            print(
                "  \(marker) \(creature.collectorNumber)  \(pad(name, 14))"
                    + "\(pad(creature.rarity.label, 11))"
                    + (filed.contains(creature.id) || state.archive.contains(creature.id)
                        ? note : ""))
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width
            ? text + "  " : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    // MARK: Events

    static func report(_ events: [CompanionEvent]) {
        guard !events.isEmpty else { return }
        for event in events {
            switch event {
            case .ripped(let id, let shiny):
                let name = Dex.creature(id)?.name ?? id
                print("  ✦ The pack rips open — \(name)\(shiny ? ", and it is shiny" : "").")
            case .evolved(let from, let to):
                print(
                    "  ✦ \(Dex.creature(from)?.name ?? from) evolved into "
                        + "\(Dex.creature(to)?.name ?? to).")
            case .filed(let id, let shiny, let rarity):
                print(
                    "  ✦ \(Dex.creature(id)?.name ?? id) (\(rarity.label))"
                        + "\(shiny ? " ✦" : "") is filed in the binder.")
            case .granted(let item, let count, let window):
                print("  ✦ \(window) filled — \(count) × \(item.label).")
            case .traitRolled(let trait):
                print("  ✦ New trait: \(trait.label).")
            case .boosted(let amount):
                print("  ✦ +\(PowerFormat.compact(amount)) growth.")
            case .bought(let entry):
                print("  ✦ Bought \(label(entry)).")
            }
        }
        print()
    }

    static func label(_ entry: ShopEntry) -> String {
        switch entry {
        case .item(let kind): kind.label
        case .pack(let floor): CompanionPack.label(floor)
        }
    }

    // MARK: Debug

    /// `ration dex simulate <tokens>`, only when RATION_DEBUG is set.
    private static func simulatedGrowth(_ args: [String]) -> Int? {
        guard ProcessInfo.processInfo.environment["RATION_DEBUG"] != nil,
            let index = args.firstIndex(of: "simulate"), args.indices.contains(index + 1)
        else { return nil }
        return Int(args[index + 1].replacingOccurrences(of: "_", with: ""))
    }

    private static func waitForRefresh(_ poller: UsagePoller) async {
        let deadline = Date().addingTimeInterval(30)
        while poller.state.status == .idle || poller.state.status == .refreshing {
            if Date() > deadline { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func printJSON(_ state: CompanionState) {
        let filed = state.filedSpecies
        var companion: [String: Any] = [:]
        if let run = state.active {
            companion = [
                "creature": run.currentID,
                "stage": run.stageIndex,
                "forms": run.forms,
                "trait": run.trait.rawValue,
                "shiny": run.isShiny,
                "progress": run.progress,
                "remaining": run.remaining,
            ]
        } else {
            companion = [
                "pack": true,
                "progress": state.packProgress,
                "remaining": state.packRemaining,
                "guarantee": state.packGuarantee?.rawValue as Any,
            ]
        }
        let payload: [String: Any] = [
            "companion": companion,
            "filed": filed.count,
            "total": Dex.roster.count,
            "archived": state.archive.subtracting(filed).count,
            "wallet": state.wallet,
            "bag": state.heldItems.reduce(into: [String: Int]()) {
                $0[$1.kind.rawValue] = $1.count
            },
            "log": state.log.map { entry in
                [
                    "id": entry.id,
                    "final": entry.finalID,
                    "chain": entry.chain,
                    "rarity": entry.rarity.rawValue,
                    "trait": entry.trait.rawValue,
                    "shiny": entry.isShiny,
                    "filedAt": ISO8601DateFormatter().string(from: entry.filedAt),
                ] as [String: Any]
            },
            "creatures": Dex.roster.map { creature in
                [
                    "id": creature.id,
                    "name": creature.name,
                    "number": creature.number,
                    "rarity": creature.rarity.rawValue,
                    "filed": filed.contains(creature.id),
                    "archived": state.archive.contains(creature.id),
                ] as [String: Any]
            },
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        {
            print(text)
        }
    }
}
