import Foundation
import Testing

@testable import RationKit

/// The real Claude Code keychain payload, with the secrets replaced.
/// Field names and nesting match what Claude Code actually stores.
private let realisticPayload = """
    {
      "claudeAiOauth": {
        "accessToken": "sk-ant-oat01-EXAMPLE-ACCESS-TOKEN",
        "refreshToken": "sk-ant-ort01-EXAMPLE-REFRESH-TOKEN",
        "expiresAt": 1786074387783,
        "refreshTokenExpiresAt": 1793850387783,
        "scopes": ["user:inference", "user:profile"],
        "subscriptionType": "max",
        "rateLimitTier": "default_claude_max_5x"
      },
      "mcpOAuth": {
        "plugin:productivity:linear|abc123": { "accessToken": "should-never-be-read" }
      }
    }
    """

@Suite("Credential parsing")
struct CredentialParsingTests {

    @Test("reads the access token and plan metadata")
    func parsesPayload() throws {
        let credential = try Credential.parse(from: Data(realisticPayload.utf8))

        #expect(credential.accessToken == "sk-ant-oat01-EXAMPLE-ACCESS-TOKEN")
        #expect(credential.subscriptionType == "max")
        #expect(credential.rateLimitTier == "default_claude_max_5x")
        #expect(credential.expiresAt != nil)
    }

    @Test("converts the millisecond expiry to a Date")
    func expiryConversion() throws {
        let credential = try Credential.parse(from: Data(realisticPayload.utf8))
        let expiry = try #require(credential.expiresAt)
        #expect(abs(expiry.timeIntervalSince1970 - 1_786_074_387.783) < 0.01)
    }

    @Test("treats a seconds-since-epoch expiry as seconds, not milliseconds")
    func expiryInSeconds() throws {
        // A millisecond parse of this would land in January 1970 and look
        // expired, which is how a format change signs the user out.
        let json = #"{"claudeAiOauth": {"accessToken": "t", "expiresAt": 1786074387}}"#
        let credential = try Credential.parse(from: Data(json.utf8))
        let expiry = try #require(credential.expiresAt)
        #expect(abs(expiry.timeIntervalSince1970 - 1_786_074_387) < 0.01)
        // Seconds since 2001; milliseconds of the same integer would be 1970.
        #expect(expiry.timeIntervalSince1970 > 1_000_000_000)
    }

    @Test("a seconds expiry still in the future is not treated as signed-out")
    func futureSecondsExpiryIsUsable() throws {
        let seconds = Int(Date().timeIntervalSince1970) + 3600
        let json = #"{"claudeAiOauth": {"accessToken": "t", "expiresAt": \#(seconds)}}"#
        let credential = try Credential.parse(from: Data(json.utf8))
        #expect(!credential.isExpired)
    }

    @Test("accepts an integer millisecond expiry")
    func expiryIntegerMilliseconds() throws {
        let json = #"{"claudeAiOauth": {"accessToken": "t", "expiresAt": 1786074387783}}"#
        let credential = try Credential.parse(from: Data(json.utf8))
        let expiry = try #require(credential.expiresAt)
        #expect(abs(expiry.timeIntervalSince1970 - 1_786_074_387.783) < 0.01)
    }

    @Test("throws when the oauth block is missing")
    func missingBlock() {
        #expect(throws: CredentialError.malformed) {
            try Credential.parse(from: Data(#"{"mcpOAuth": {}}"#.utf8))
        }
    }

    @Test("throws when the payload is not JSON")
    func notJSON() {
        #expect(throws: CredentialError.malformed) {
            try Credential.parse(from: Data("nonsense".utf8))
        }
    }

    @Test("throws when the access token is empty")
    func emptyToken() {
        let json = #"{"claudeAiOauth": {"accessToken": ""}}"#
        #expect(throws: CredentialError.malformed) {
            try Credential.parse(from: Data(json.utf8))
        }
    }
}

// MARK: - Security invariants
//
// These tests exist to make a promise to anyone auditing this repo:
// Ration reads one secret, uses it for one request, and never writes,
// stores, or logs it.

@Suite("Credential security invariants")
struct CredentialSecurityTests {

    @Test("the refresh token is never read into the model")
    func refreshTokenIsNeverRead() throws {
        let credential = try Credential.parse(from: Data(realisticPayload.utf8))

        // Reflect over every stored property; none may contain the refresh token.
        for child in Mirror(reflecting: credential).children {
            let value = String(describing: child.value)
            #expect(
                !value.contains("REFRESH"),
                "property \(child.label ?? "?") leaked the refresh token")
        }
    }

    @Test("no MCP server tokens are read")
    func mcpTokensAreNeverRead() throws {
        let credential = try Credential.parse(from: Data(realisticPayload.utf8))
        for child in Mirror(reflecting: credential).children {
            #expect(!String(describing: child.value).contains("should-never-be-read"))
        }
    }

    @Test("printing a credential does not reveal the token")
    func descriptionIsRedacted() throws {
        let credential = try Credential.parse(from: Data(realisticPayload.utf8))

        #expect(!"\(credential)".contains("EXAMPLE-ACCESS-TOKEN"))
        #expect(!String(reflecting: credential).contains("EXAMPLE-ACCESS-TOKEN"))
        #expect("\(credential)".contains("redacted"))
    }

    @Test("redaction still shows enough to debug: plan tier survives")
    func descriptionKeepsNonSecrets() throws {
        let credential = try Credential.parse(from: Data(realisticPayload.utf8))
        #expect("\(credential)".contains("max"))
    }

    @Test("a credential past its expiry reports as expired")
    func expiryCheck() {
        let past = Credential(
            accessToken: "t", expiresAt: Date(timeIntervalSinceNow: -60),
            subscriptionType: nil, rateLimitTier: nil)
        let future = Credential(
            accessToken: "t", expiresAt: Date(timeIntervalSinceNow: 3600),
            subscriptionType: nil, rateLimitTier: nil)
        let unknown = Credential(
            accessToken: "t", expiresAt: nil, subscriptionType: nil, rateLimitTier: nil)

        #expect(past.isExpired)
        #expect(!future.isExpired)
        // With no expiry we assume valid and let the server decide with a 401.
        #expect(!unknown.isExpired)
    }
}

// MARK: - Repo-wide guarantees

@Suite("Source tree guarantees")
struct SourceTreeTests {

    /// Walks up from this test file to the package root.
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RationKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources")
    }

    private func swiftFiles() throws -> [(url: URL, contents: String)] {
        let enumerator = FileManager.default.enumerator(
            at: sourcesDirectory, includingPropertiesForKeys: nil)
        var files: [(URL, String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            files.append((url, text))
        }
        return files
    }

    @Test("no unexpected hosts appear anywhere in the source tree")
    func noUnexpectedHosts() throws {
        let pattern = try NSRegularExpression(pattern: #"https?://([A-Za-z0-9.-]+)"#)
        var hosts: Set<String> = []

        for file in try swiftFiles() {
            let range = NSRange(file.contents.startIndex..., in: file.contents)
            for match in pattern.matches(in: file.contents, range: range) {
                if let hostRange = Range(match.range(at: 1), in: file.contents) {
                    hosts.insert(String(file.contents[hostRange]))
                }
            }
        }

        let allowed: Set<String> = [
            // The hosts Ration sends requests to.
            "api.anthropic.com",
            "api2.cursor.sh",
            // Links the user can click to open in their browser. Ration itself
            // never requests these — see `networkingIsConfinedToTheClient`.
            "github.com",
            "buymeacoffee.com",
            "x.com",
        ]
        #expect(
            hosts.subtracting(allowed).isEmpty,
            "unexpected host(s) in source: \(hosts.subtracting(allowed))")
    }

    /// Every request Ration's *own* code makes originates in the client files.
    ///
    /// Sparkle also makes requests — update checks against the appcast, and the
    /// release download — but it does so from its own framework, not from code
    /// in this repository. `updateFeedIsTheExpectedHost` covers that half.
    @Test("all first-party networking is confined to the client files")
    func networkingIsConfinedToTheClient() throws {
        let allowed = Set(["LimitsClient.swift", "CursorClient.swift"])
        for file in try swiftFiles() where !allowed.contains(file.url.lastPathComponent) {
            for symbol in ["URLSession", "URLRequest", "NSURLConnection", "CFSocket"] {
                #expect(
                    !file.contents.contains(symbol),
                    "\(file.url.lastPathComponent) performs networking outside the client files")
            }
        }
    }

    /// The update feed is a host besides Anthropic and Cursor that the shipped
    /// app contacts. It is set in `Scripts/bundle.sh` rather than Swift, so pin
    /// it here — a silent change of update host is exactly the kind of thing this
    /// repository's promises should not allow.
    @Test("the update feed points at the project's own repository")
    func updateFeedIsTheExpectedHost() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: root.appendingPathComponent("Scripts/bundle.sh"), encoding: .utf8)

        #expect(
            script.contains("https://raw.githubusercontent.com/mcpeixoto/ration/main/appcast.xml"),
            "the default update feed changed")
    }

    @Test("the client targets exactly one URL")
    func clientHasOneEndpoint() throws {
        let client = try #require(
            try swiftFiles().first { $0.url.lastPathComponent == "LimitsClient.swift" })

        let pattern = try NSRegularExpression(pattern: #"URL\(string: "([^"]+)"\)"#)
        let range = NSRange(client.contents.startIndex..., in: client.contents)
        let urls = pattern.matches(in: client.contents, range: range).compactMap {
            Range($0.range(at: 1), in: client.contents).map { String(client.contents[$0]) }
        }

        #expect(urls == ["https://api.anthropic.com/api/oauth/usage"])
    }

    @Test("the Cursor client targets exactly its known URLs")
    func cursorClientHasKnownEndpoints() throws {
        let client = try #require(
            try swiftFiles().first { $0.url.lastPathComponent == "CursorClient.swift" })

        #expect(
            client.contents.contains(
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"))
        #expect(client.contents.contains("https://api2.cursor.sh/auth/usage"))
        #expect(
            client.contents.contains(
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents"))
        #expect(
            client.contents.contains(
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents"))

        let pattern = try NSRegularExpression(pattern: #"https?://([A-Za-z0-9.-]+)"#)
        let range = NSRange(client.contents.startIndex..., in: client.contents)
        var hosts: Set<String> = []
        for match in pattern.matches(in: client.contents, range: range) {
            if let hostRange = Range(match.range(at: 1), in: client.contents) {
                hosts.insert(String(client.contents[hostRange]))
            }
        }
        #expect(hosts == ["api2.cursor.sh"])
    }

    @Test("no source file mentions a refresh token field")
    func noRefreshTokenUsage() throws {
        for file in try swiftFiles() {
            #expect(
                !file.contents.contains("refreshToken"),
                "\(file.url.lastPathComponent) references refreshToken")
        }
    }

    /// Codex keeps its credentials in a plain file, mode 0600, with no keychain
    /// and no prompt in the way. Ration could read them; it has no reason to.
    /// Everything it shows for Codex — the token counts, the quota percentages,
    /// the reset times, even the plan tier — is in the session logs.
    ///
    /// So the invariant is not "handle those credentials carefully", it is
    /// "never go near them", and this is what holds the line.
    @Test("no source file reads another tool's credential store")
    func credentialsOfOtherToolsAreNeverTouched() throws {
        // Deliberately includes the file name itself: a comment explaining that
        // we do not read it is still a reference to it, and the way this
        // guarantee erodes is one convenience at a time.
        let forbidden = [
            "auth.json", "access_token", "id_token", "refresh_token",
            ".codex/auth", "oauth_creds", "Cookies.binarycookies",
            "WorkosCursorSessionToken",
        ]

        for file in try swiftFiles() {
            for needle in forbidden {
                #expect(
                    !file.contents.contains(needle),
                    "\(file.url.lastPathComponent) references \(needle)")
            }
        }
    }

    /// Claude Code refreshes its keychain item by deleting and recreating it,
    /// which wipes any `teamid:` ACL entry `SecItemCopyMatching` needed. The
    /// surviving read path is `/usr/bin/security find-generic-password`, the
    /// same binary Claude Code uses, because the rewritten item keeps the
    /// `apple-tool:` partition. Writing, deleting, or copying via
    /// Security.framework is how third-party readers sign the user out.
    @Test("the Claude credential store reads via security(1), never Security.framework")
    func keychainAccessIsConfinedToOneFile() throws {
        let allowed = Set(["Credential+macOS.swift"])
        for file in try swiftFiles() {
            let name = file.url.lastPathComponent
            for symbol in [
                "SecItemCopyMatching", "SecItemAdd", "SecItemUpdate", "SecItemDelete",
                "kSecClass", "add-generic-password", "delete-generic-password",
            ] {
                #expect(
                    !file.contents.contains(symbol),
                    "\(name) mutates or bypasses the Claude Code keychain item via \(symbol)")
            }
            if !allowed.contains(name) {
                #expect(
                    !file.contents.contains("/usr/bin/security"),
                    "\(name) shells out to security(1); only the Claude store may")
                #expect(
                    !file.contents.contains("find-generic-password"),
                    "\(name) reads a generic password; only the Claude store may")
            }
        }

        let macStore = try #require(
            try swiftFiles().first { $0.url.lastPathComponent == "Credential+macOS.swift" })
        #expect(macStore.contents.contains("/usr/bin/security"))
        #expect(macStore.contents.contains("find-generic-password"))
        #expect(macStore.contents.contains("-w"))
        #expect(!macStore.contents.contains("-U"))
    }
}

@Suite("File credential store")
struct FileCredentialStoreTests {

    @Test("reads Claude Code credentials from a file")
    func readsFromFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "ration-credential-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appending(path: ".credentials.json")
        try realisticPayload.write(to: file, atomically: true, encoding: .utf8)

        let store = FileCredentialStore(fileURL: file)
        let credential = try store.credential()
        #expect(credential.accessToken == "sk-ant-oat01-EXAMPLE-ACCESS-TOKEN")
        #expect(credential.subscriptionType == "max")
    }

    @Test("throws notFound when the credentials file is missing")
    func missingFile() {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "ration-missing-\(UUID().uuidString)/.credentials.json")
        #expect(throws: CredentialError.notFound) {
            try FileCredentialStore(fileURL: file).credential()
        }
    }
}

private struct StubStore: CredentialStore {
    var result: Result<Credential, CredentialError>
    func credential() throws -> Credential { try result.get() }
}

private func stubCredential(_ token: String) -> Credential {
    Credential(
        accessToken: token, expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "max", rateLimitTier: nil)
}

@Suite("Fallback credential store")
struct FallbackCredentialStoreTests {

    @Test("uses the file when it has a credential")
    func prefersPrimary() throws {
        let store = FallbackCredentialStore(
            primary: StubStore(result: .success(stubCredential("from-file"))),
            fallback: StubStore(result: .success(stubCredential("from-keychain"))))
        #expect(try store.credential().accessToken == "from-file")
    }

    @Test("falls back to the keychain only when the file is missing")
    func fallsBackWhenMissing() throws {
        let store = FallbackCredentialStore(
            primary: StubStore(result: .failure(.notFound)),
            fallback: StubStore(result: .success(stubCredential("from-keychain"))))
        #expect(try store.credential().accessToken == "from-keychain")
    }

    @Test("does not fall back when the file is unreadable")
    func doesNotFallBackOnAccessDenied() {
        let store = FallbackCredentialStore(
            primary: StubStore(result: .failure(.accessDenied)),
            fallback: StubStore(result: .success(stubCredential("from-keychain"))))
        #expect(throws: CredentialError.accessDenied) {
            try store.credential()
        }
    }

    @Test("does not fall back when the file is malformed")
    func doesNotFallBackOnMalformed() {
        let store = FallbackCredentialStore(
            primary: StubStore(result: .failure(.malformed)),
            fallback: StubStore(result: .success(stubCredential("from-keychain"))))
        #expect(throws: CredentialError.malformed) {
            try store.credential()
        }
    }
}

#if os(macOS)
@Suite("Keychain security(1) mapping")
struct KeychainCLITests {

    @Test("strips the trailing newline security(1) adds to -w output")
    func stripsTrailingNewline() throws {
        let payload = Data(realisticPayload.utf8) + Data([0x0A])
        let decoded = try KeychainCredentialStore.decodeCLI(status: 0, stdout: payload)
        let credential = try Credential.parse(from: decoded)
        #expect(credential.accessToken == "sk-ant-oat01-EXAMPLE-ACCESS-TOKEN")
    }

    @Test("maps item-not-found to notFound")
    func itemNotFound() {
        #expect(throws: CredentialError.notFound) {
            try KeychainCredentialStore.decodeCLI(status: 44, stdout: Data())
        }
    }

    @Test("maps interaction-not-allowed to accessDenied")
    func interactionNotAllowed() {
        #expect(throws: CredentialError.accessDenied) {
            try KeychainCredentialStore.decodeCLI(status: 36, stdout: Data())
        }
    }

    @Test("reads through an injected security(1) result")
    func injectedReader() throws {
        let store = KeychainCredentialStore { service in
            #expect(service == KeychainCredentialStore.service)
            return Data(realisticPayload.utf8)
        }
        let credential = try store.credential()
        #expect(credential.accessToken == "sk-ant-oat01-EXAMPLE-ACCESS-TOKEN")
    }
}
#endif

@Suite("Version consistency")
struct VersionTests {

    /// `Scripts/bundle.sh` stamps the bundle from the VERSION file while the
    /// User-Agent comes from `Ration.version`. If they drift, releases report a
    /// version they are not.
    @Test("Ration.version matches the VERSION file")
    func versionMatchesFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contents = try String(
            contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        #expect(contents.trimmingCharacters(in: .whitespacesAndNewlines) == Ration.version)
    }
}
