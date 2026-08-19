import Foundation

#if os(Linux)
enum ServiceCommand {

    static func run(subcommand: String?, config: CLIConfig) {
        switch subcommand {
        case "install":
            install(config: config)
        case "uninstall":
            uninstall()
        case "status":
            status()
        default:
            FileHandle.standardError.write(Data("Unknown service command: \(subcommand ?? "")\n".utf8))
            printHelp()
            exit(1)
        }
    }

    static func printHelp() {
        print(
            """
            ration service — launch at login via systemd (Linux)

            Usage:
              ration service install    Install a user service that runs `ration watch`
              ration service uninstall  Remove the user service
              ration service status     Show whether the service is active

            Requires systemd user session and notify-send for alerts.
            """)
    }

    private static var unitURL: URL {
        PlatformPaths.home.appending(path: ".config/systemd/user/ration-watch.service")
    }

    private static func rationPath() -> String {
        ProcessInfo.processInfo.arguments[0]
    }

    private static func install(config: CLIConfig) {
        let unit = """
        [Unit]
        Description=Ration usage monitor
        After=network.target

        [Service]
        ExecStart=\(rationPath()) watch --interval \(Int(max(60, config.pollInterval)))
        Restart=on-failure
        Environment=PATH=/usr/local/bin:/usr/bin:/bin

        [Install]
        WantedBy=default.target
        """

        let url = unitURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? unit.write(to: url, atomically: true, encoding: .utf8)

        runSystemctl(["daemon-reload"])
        runSystemctl(["enable", "--now", "ration-watch.service"])
        print("Installed \(url.path)")
        print("Ration will start at login and run `ration watch`.")
    }

    private static func uninstall() {
        runSystemctl(["disable", "--now", "ration-watch.service"])
        try? FileManager.default.removeItem(at: unitURL)
        runSystemctl(["daemon-reload"])
        print("Removed ration-watch.service")
    }

    private static func status() {
        runSystemctl(["status", "ration-watch.service"], check: false)
    }

    @discardableResult
    private static func runSystemctl(_ args: [String], check: Bool = true) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemctl")
        process.arguments = ["--user"] + args
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try? process.run()
        process.waitUntilExit()
        if check, process.terminationStatus != 0 { exit(process.terminationStatus) }
        return process.terminationStatus
    }
}
#endif
