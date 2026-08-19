#if os(Linux)

import Foundation

/// Reads Claude Code's credentials from the file Claude Code already wrote.
///
/// On Linux there is no keychain. Claude Code stores the same JSON blob at
/// `~/.claude/.credentials.json` (mode 0600), or under `CLAUDE_CONFIG_DIR` /
/// `CLAUDE_SECURESTORAGE_CONFIG_DIR` when those are set.
public struct FileCredentialStore: CredentialStore {

    public let fileURL: URL

    public init(fileURL: URL = PlatformPaths.claudeCredentialsFile) {
        self.fileURL = fileURL
    }

    public func credential() throws -> Credential {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CredentialError.notFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CredentialError.accessDenied
        }

        return try Credential.parse(from: data)
    }
}

/// The credential store Ration uses on Linux.
public typealias DefaultCredentialStore = FileCredentialStore

#endif
