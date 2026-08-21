import Foundation
import RationKit

@main
struct RationCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "status"
        let rest = Array(args.dropFirst())
        var config = CLIConfig.load()

        switch command {
        case "status", "show":
            await StatusCommand.run(
                options: CLIOptions(args: rest), watch: false, config: config)
        case "watch":
            await StatusCommand.run(
                options: CLIOptions(args: rest), watch: true, config: config)
        case "activity":
            await HistoryCommands.activity(options: CLIOptions(args: rest), config: config)
        case "trends":
            await HistoryCommands.trends(options: CLIOptions(args: rest), config: config)
        case "detail", "breakdown":
            await HistoryCommands.detail(options: CLIOptions(args: rest), config: config)
        case "dex", "pokemon", "collection":
            await DexCommand.run(options: CLIOptions(args: rest), config: config)
        case "shop":
            await ShopCommand.shop(
                subcommand: rest.first, args: Array(rest.dropFirst()), config: config)
        case "bag":
            await ShopCommand.bag(
                subcommand: rest.first, args: Array(rest.dropFirst()), config: config)
        case "config":
            ConfigCommand.run(
                subcommand: rest.first, args: Array(rest.dropFirst()), config: &config)
        #if os(Linux)
        case "service":
            ServiceCommand.run(subcommand: rest.first, config: config)
        #endif
        case "version", "-v", "--version":
            print("ration \(Ration.version)")
        case "help", "-h", "--help":
            printHelp()
        default:
            let message = "Unknown command: \(command)\n"
            FileHandle.standardError.write(Data(message.utf8))
            printHelp()
            exit(1)
        }
    }

    private static func printHelp() {
        var commands = """
              status      Show current usage (default)
              watch       Refresh usage on an interval
              activity    Calendar heat map, streaks, and rhythm
              trends      Totals and daily usage over 7/30/90 days
              detail      Breakdown by model and project
              dex         Your companion, the binder, and the catch log
              shop        Spend tokens on packs and items
              bag         What you are holding, and use it
              config      View or change CLI settings
            """
        #if os(Linux)
        commands += """
              service     Install launch-at-login via systemd
            """
        #endif
        commands += """
              version     Print the version
              help        Show this message
            """
        print(
            """
            ration — your AI coding usage, in the terminal

            Usage:
              ration [command] [options]

            Commands:
            \(commands)
            Options:
              --provider <id>   claude, codex, or cursor
              --interval <sec>  Poll interval for watch (default: 60, minimum: 60)
              --days <n>        History window: 7, 30, or 90 (default: 30)
              --notify          Desktop alerts when approaching limits (watch)
              --json            Print machine-readable JSON

            Examples:
              ration status
              ration watch --notify
              ration activity --provider claude
              ration trends --days 7
              ration dex --json
              ration config set notify true
            """)
    }
}
