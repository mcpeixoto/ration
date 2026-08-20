#if os(macOS)

import Foundation

/// Reads Claude Code's credentials the same way Claude Code itself does.
///
/// Claude Code refreshes its OAuth token by replacing the keychain item
/// wholesale. The replacement is created with the default `apple-tool:`
/// partition, which is the partition the `security` CLI already holds.
/// Reading through that same CLI therefore keeps working after every
/// refresh, without a login-password prompt and without knocking Claude
/// Code out of its own item.
///
/// Going through Security.framework as Ration.app does not: it needs a
/// team-id ACL entry that the replacement wipes. This type only runs
/// `find-generic-password` with `-w` (print the secret, then exit). It
/// never writes, updates, or deletes the item.
public struct KeychainCredentialStore: CredentialStore {

    /// The service name Claude Code stores its credentials under.
    public static let service = "Claude Code-credentials"

    /// Absolute path of the binary Claude Code uses to read and write the item.
    public static let securityTool = "/usr/bin/security"

    private let read: @Sendable (String) throws -> Data

    public init() {
        self.init(read: Self.readViaSecurityCLI)
    }

    init(read: @escaping @Sendable (String) throws -> Data) {
        self.read = read
    }

    public func credential() throws -> Credential {
        try Credential.parse(from: try read(Self.service))
    }

    /// Maps `/usr/bin/security find-generic-password -w` into a credential
    /// blob or a `CredentialError`. Exposed so the mapping can be tested
    /// without touching a real keychain.
    static func decodeCLI(status: Int32, stdout: Data) throws -> Data {
        switch status {
        case 0:
            var data = stdout
            if data.last == 0x0A { data.removeLast() }
            if data.last == 0x0D { data.removeLast() }
            guard !data.isEmpty else { throw CredentialError.malformed }
            return data
        case 44:  // errSecItemNotFound
            throw CredentialError.notFound
        case 36, 51, 128:  // interaction not allowed / auth failed / canceled
            throw CredentialError.accessDenied
        default:
            throw CredentialError.keychain(status: status)
        }
    }

    private static func readViaSecurityCLI(service: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityTool)
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CredentialError.accessDenied
        }
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        return try decodeCLI(status: process.terminationStatus, stdout: data)
    }
}

/// macOS store: the credentials file when the user (or Claude Code) wrote
/// one, otherwise the keychain item, via `/usr/bin/security`.
public struct MacCredentialStore: CredentialStore {

    private let wrapped: FallbackCredentialStore

    public init(
        fileURL: URL = PlatformPaths.claudeCredentialsFile,
        keychain: KeychainCredentialStore = KeychainCredentialStore()
    ) {
        self.wrapped = FallbackCredentialStore(
            primary: FileCredentialStore(fileURL: fileURL),
            fallback: keychain)
    }

    public func credential() throws -> Credential {
        try wrapped.credential()
    }
}

/// The credential store Ration uses on macOS.
public typealias DefaultCredentialStore = MacCredentialStore

#endif
