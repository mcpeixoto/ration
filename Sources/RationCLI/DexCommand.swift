import Foundation
import RationKit

@MainActor
enum DexCommand {

    static func run(options: CLIOptions, config: inout CLIConfig) async {
        let registry = CLIContext.registry(config: config)
        await CLIContext.prepareHistories(registry: registry)

        for entry in registry.metered where entry.history == nil {
            entry.poller.start()
            if entry.poller.state.status == .idle {
                await waitForRefresh(entry.poller)
            }
            entry.poller.suspend()
        }

        let state = Dex.evaluate(CLIContext.dexInput(registry: registry))
        let pending = Dex.pendingReveals(caught: state.caught, alreadyRevealed: config.revealed)

        if options.json {
            printDexJSON(state: state)
            return
        }

        if !pending.isEmpty {
            print("New unlocks:")
            for creature in pending {
                print("  ✦ \(creature.name) (\(creature.rarity.label))")
            }
            config.revealedCreatureIDs = Array(config.revealed.union(Set(pending.map(\.id))))
            config.save()
            print()
        }

        print("Pokémon — \(state.caught.count) of \(Dex.roster.count) unlocked")
        print("Score: \(PowerFormat.compact(state.stats.power))")
        print()

        if let hunt = state.nextPowerCatch {
            let progress = Int(hunt.progress * 100)
            print("Next unlock: \(hunt.creature.name) (\(progress)% — \(hunt.creature.requirement.hint))")
            print()
        } else if state.uncaught.isEmpty {
            print("The set is complete.")
            print()
        }

        for creature in Dex.roster {
            let caught = state.caught.contains { $0.id == creature.id }
            let marker = caught ? "✓" : "·"
            let name = caught ? creature.name : "???"
            print(
                "  \(marker) \(creature.collectorNumber)  \(name.padding(toLength: 14, withPad: " ", startingAt: 0))  "
                    + "\(creature.rarity.label.padding(toLength: 10, withPad: " ", startingAt: 0))  "
                    + (caught ? creature.requirement.deed : creature.requirement.hint))
        }
    }

    private static func waitForRefresh(_ poller: UsagePoller) async {
        let deadline = Date().addingTimeInterval(30)
        while poller.state.status == .idle || poller.state.status == .refreshing {
            if Date() > deadline { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func printDexJSON(state: DexState) {
        let payload: [String: Any] = [
            "caught": state.caught.count,
            "total": Dex.roster.count,
            "score": state.stats.power,
            "creatures": Dex.roster.map { creature in
                let caught = state.caught.contains { $0.id == creature.id }
                return [
                    "id": creature.id,
                    "name": caught ? creature.name : "???",
                    "caught": caught,
                    "rarity": creature.rarity.rawValue,
                    "number": creature.number,
                ] as [String: Any]
            },
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted]),
            let text = String(data: data, encoding: .utf8)
        {
            print(text)
        }
    }
}
