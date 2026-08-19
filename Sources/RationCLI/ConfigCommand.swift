import Foundation

enum ConfigCommand {

    static func run(subcommand: String?, args: [String], config: inout CLIConfig) {
        switch subcommand {
        case nil, "show":
            show(config: config, json: args.contains("--json"))
        case "set":
            set(args: args, config: &config)
        case "path":
            print(CLIConfig.url.path)
        default:
            fputs("Unknown config command: \(subcommand ?? "")\n", stderr)
            printConfigHelp()
            exit(1)
        }
    }

    private static func show(config: CLIConfig, json: Bool) {
        if json {
            if let data = try? JSONEncoder().encode(config),
                let text = String(data: data, encoding: .utf8)
            {
                print(text)
            }
            return
        }

        print("Config: \(CLIConfig.url.path)")
        print()
        print("pollInterval:        \(Int(config.pollInterval))s")
        print("notifyOnThresholds:  \(config.notifyOnThresholds)")
        print("disabledProviders: \(config.disabledProviders.isEmpty ? "none" : config.disabledProviders.joined(separator: ", "))")
        print("revealedCreatures:   \(config.revealedCreatureIDs.count)")
    }

    private static func set(args: [String], config: inout CLIConfig) {
        var index = 0
        while index < args.count {
            switch args[index] {
            case "pollInterval", "interval":
                index += 1
                guard index < args.count, let value = TimeInterval(args[index]) else {
                    fputs("Usage: ration config set pollInterval <seconds>\n", stderr)
                    exit(1)
                }
                config.pollInterval = max(60, value)
            case "notify", "notifyOnThresholds":
                index += 1
                guard index < args.count else {
                    fputs("Usage: ration config set notify <true|false>\n", stderr)
                    exit(1)
                }
                config.notifyOnThresholds = args[index].lowercased() == "true"
            case "disable":
                index += 1
                guard index < args.count else {
                    fputs("Usage: ration config set disable <provider>\n", stderr)
                    exit(1)
                }
                if !config.disabledProviders.contains(args[index]) {
                    config.disabledProviders.append(args[index])
                }
            case "enable":
                index += 1
                guard index < args.count else {
                    fputs("Usage: ration config set enable <provider>\n", stderr)
                    exit(1)
                }
                config.disabledProviders.removeAll { $0 == args[index] }
            default:
                break
            }
            index += 1
        }
        config.save()
        print("Config saved.")
    }

    static func printConfigHelp() {
        print(
            """
            ration config — manage CLI settings

            Usage:
              ration config [show] [--json]
              ration config path
              ration config set <key> <value> ...

            Keys:
              pollInterval <seconds>   Minimum 60
              notify <true|false>      Threshold notifications in watch mode
              disable <provider>       Hide a provider (claude, codex, cursor)
              enable <provider>        Re-enable a provider
            """)
    }
}
