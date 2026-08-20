import Foundation
import Testing

@testable import RationKit

@Suite("Platform paths")
struct PlatformPathsTests {

    @Test("Cursor state database follows the platform convention")
    func cursorDatabase() {
        #if os(macOS)
        #expect(
            PlatformPaths.cursorStateDatabase.path
                .hasSuffix("Library/Application Support/Cursor/User/globalStorage/state.vscdb"))
        #else
        #expect(
            PlatformPaths.cursorStateDatabase.path
                .hasSuffix(".config/Cursor/User/globalStorage/state.vscdb"))
        #endif
    }

    @Test("Cursor agent transcripts live under ~/.cursor/projects on every platform")
    func cursorProjects() {
        #expect(PlatformPaths.cursorProjectsDirectory.path.hasSuffix(".cursor/projects"))
    }

    @Test("Claude credentials default to ~/.claude/.credentials.json")
    func claudeCredentialsDefault() {
        #expect(
            PlatformPaths.claudeCredentialsFile.path
                .hasSuffix(".claude/.credentials.json"))
    }
}
