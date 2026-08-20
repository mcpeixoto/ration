import Foundation

/// Cross-platform paths to the tools Ration reads.
///
/// macOS and Linux store editor state in different locations. Centralising
/// those paths keeps every reader consistent and makes the differences visible
/// in one file rather than scattered through the sources.
public enum PlatformPaths {

    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // MARK: Claude Code

    /// Where Claude Code keeps its OAuth blob on Linux and Windows, and on
    /// macOS when the user (or Claude Code) has written the file. Claude Code
    /// itself prefers this file over the keychain item when both exist.
    public static var claudeCredentialsFile: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appending(path: ".credentials.json")
        }
        if let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
            !config.isEmpty
        {
            return URL(fileURLWithPath: config, isDirectory: true)
                .appending(path: ".credentials.json")
        }
        return home.appending(path: ".claude/.credentials.json")
    }

    // MARK: Cursor

    public static var cursorSupportDirectory: URL {
        #if os(macOS)
        home.appending(path: "Library/Application Support/Cursor")
        #else
        home.appending(path: ".config/Cursor")
        #endif
    }

    public static var cursorStateDatabase: URL {
        cursorSupportDirectory
            .appending(path: "User/globalStorage/state.vscdb")
    }
}
