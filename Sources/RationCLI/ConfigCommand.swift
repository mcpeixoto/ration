import Foundation
import RationKit

/// Reads and writes the settings file `ration` and `ration-tray` share.
///
/// The tray keys are editable here too: one file, two front ends, and no
/// setting that can only be reached from the one the user is not running.
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
            FileHandle.standardError.write(
                Data("Unknown config command: \(subcommand ?? "")\n".utf8))
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
        print(
            "disabledProviders: \(config.disabledProviders.isEmpty ? "none" : config.disabledProviders.joined(separator: ", "))"
        )
        print("revealedCreatures:   \(config.revealedCreatureIDs.count)")
        print()
        print("Tray only:")
        print("displayMode:         \(config.displayMode.rawValue)")
        print("weeklyBar:           \(config.showWeeklyBar)")
        print("severityColor:       \(config.useSeverityColor)")
        print("primaryProvider:     \(config.primaryProviderID)")
        print(
            "uiScale:             \(config.uiScale == 0 ? "automatic" : String(format: "%.2f", config.uiScale))"
        )
    }

    private static func set(args: [String], config: inout CLIConfig) {
        var index = 0
        while index < args.count {
            switch args[index] {
            case "pollInterval", "interval":
                index += 1
                guard index < args.count, let value = TimeInterval(args[index]) else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set pollInterval <seconds>\n".utf8))
                    exit(1)
                }
                config.pollInterval = max(60, value)
            case "notify", "notifyOnThresholds":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set notify <true|false>\n".utf8))
                    exit(1)
                }
                config.notifyOnThresholds = args[index].lowercased() == "true"
            case "disable":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set disable <provider>\n".utf8))
                    exit(1)
                }
                if !config.disabledProviders.contains(args[index]) {
                    config.disabledProviders.append(args[index])
                }
            case "displayMode", "display":
                index += 1
                guard index < args.count,
                    let mode = MenuBarDisplayMode(rawValue: args[index])
                else {
                    let modes = MenuBarDisplayMode.allCases.map(\.rawValue)
                        .joined(separator: "|")
                    FileHandle.standardError.write(
                        Data("Usage: ration config set displayMode <\(modes)>\n".utf8))
                    exit(1)
                }
                config.displayMode = mode
            case "weeklyBar":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set weeklyBar <true|false>\n".utf8))
                    exit(1)
                }
                config.showWeeklyBar = args[index].lowercased() == "true"
            case "severityColor", "colour", "color":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set severityColor <true|false>\n".utf8))
                    exit(1)
                }
                config.useSeverityColor = args[index].lowercased() == "true"
            case "primaryProvider", "primary":
                index += 1
                guard index < args.count, let provider = Provider.named(args[index]) else {
                    FileHandle.standardError.write(
                        Data(
                            "Usage: ration config set primaryProvider <claude|codex|cursor>\n"
                                .utf8))
                    exit(1)
                }
                config.primaryProvider = provider
            case "uiScale", "scale":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set uiScale <auto|0.75-3.0>\n".utf8))
                    exit(1)
                }
                if args[index].lowercased() == "auto" {
                    config.uiScale = 0
                } else if let value = Double(args[index]), (0.75...3.0).contains(value) {
                    config.uiScale = value
                } else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set uiScale <auto|0.75-3.0>\n".utf8))
                    exit(1)
                }
            case "enable":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(
                        Data("Usage: ration config set enable <provider>\n".utf8))
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

            Tray keys (ration-tray reads the same file):
              displayMode <mode>       session|weekly|highest|icon — the number
                                       the tray gauges
              weeklyBar <true|false>   The small weekly allowance bar
              severityColor <t|f>      Amber past 80%, red past 90%
              primaryProvider <id>     Which account the panel opens on
              uiScale <auto|0.75-3.0>  How large the tray draws its windows
            """)
    }
}
