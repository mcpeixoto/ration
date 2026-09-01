import CLinuxTray
import Dispatch
import Foundation
import RationKit

/// `ration-tray` — the Linux counterpart of the macOS menu bar app.
///
/// Same gauge, same panel, same five tabs; drawn with Cairo and published to
/// the desktop's tray through libayatana-appindicator3.

if CommandLine.arguments.contains("--version") {
    print("ration-tray \(Ration.version)")
    exit(0)
}

if CommandLine.arguments.contains("--help") {
    print(
        """
        ration-tray — your AI coding usage, in the tray

        Usage:
          ration-tray            Run the tray item (the default)
          ration-tray --open-panel [--tab usage|activity|trends|breakdown|collection]
                                 Run, and open the panel at once
          ration-tray --open-settings [--section General|Accounts|About]
                                 Run, and open Settings at once
          ration-tray --screenshot <dir>
                                 Render every panel state to PNGs and exit
          ration-tray --write-icon <path> [--icon-size N]
                                 Draw the application icon as a PNG
          ration-tray --version  Print the version
          ration-tray --help     Show this message

        The tray icon carries the gauge; clicking it opens the panel with
        Usage, Activity, Trends, Detail, and Pokémon. On GNOME the shell opens
        the tray menu on a single click — Ration turns that into the panel.
        Refresh, Settings and Quit also live in the right-click menu. For a
        terminal-only view of the same numbers, run `ration`.
        """)
    exit(0)
}

// Writing the icon needs Cairo but not a display, so it runs before the
// GTK check — a packaging step on a build machine has no X server.
if let index = CommandLine.arguments.firstIndex(of: "--write-icon"),
    index + 1 < CommandLine.arguments.count
{
    let path = CommandLine.arguments[index + 1]
    let size =
        CommandLine.arguments.firstIndex(of: "--icon-size")
        .flatMap { position -> Int? in
            guard position + 1 < CommandLine.arguments.count else { return nil }
            return Int(CommandLine.arguments[position + 1])
        } ?? 512
    guard AppIcon.write(to: path, size: size) else {
        FileHandle.standardError.write(Data("ration-tray: could not write \(path)\n".utf8))
        exit(1)
    }
    print("Wrote \(path) (\(size)×\(size))")
    exit(0)
}

guard gtk_init_check(nil, nil) != 0 else {
    FileHandle.standardError.write(
        Data("ration-tray: no display available — run `ration` instead.\n".utf8))
    exit(1)
}

/// Progress notes for diagnosing a tray that does not appear. Off unless
/// `RATION_TRAY_TRACE` is set, so a normal run stays silent.
func trace(_ message: String) {
    guard ProcessInfo.processInfo.environment["RATION_TRAY_TRACE"] != nil else { return }
    FileHandle.standardError.write(Data("ration-tray: \(message)\n".utf8))
}

trace("gtk ready")
let app = TrayApp()
app.start()
trace("app started")

// Opening the panel straight away is how the tray is checked without a
// pointer — a screenshot run, or a desktop where the shell swallows the click.
if let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
    index + 1 < CommandLine.arguments.count
{
    // Histories are read in the background; give the scan a moment so the
    // charts have something in them.
    let directory = CommandLine.arguments[index + 1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        app.writeSnapshots(to: directory)
        exit(0)
    }
}

if CommandLine.arguments.contains("--open-settings") {
    let section =
        CommandLine.arguments.firstIndex(of: "--section")
        .flatMap { index -> SettingsWindow.Section? in
            guard index + 1 < CommandLine.arguments.count else { return nil }
            return SettingsWindow.Section.allCases.first {
                $0.rawValue.lowercased() == CommandLine.arguments[index + 1].lowercased()
            }
        }
    app.openSettings(on: section)
}

if CommandLine.arguments.contains("--open-panel") {
    if let index = CommandLine.arguments.firstIndex(of: "--tab"),
        index + 1 < CommandLine.arguments.count,
        let tab = PanelTab(rawValue: CommandLine.arguments[index + 1])
    {
        app.showPanel(on: tab)
    } else {
        app.openPanel()
    }
}

MainLoop.run()
