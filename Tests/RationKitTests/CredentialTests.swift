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
            // The one host Ration sends requests to.
            "api.anthropic.com",
            // Links the user can click to open in their browser. Ration itself
            // never requests these — see `networkingIsConfinedToTheClient`.
            "github.com",
            "buymeacoffee.com",
        ]
        #expect(
            hosts.subtracting(allowed).isEmpty,
            "unexpected host(s) in source: \(hosts.subtracting(allowed))")
    }

    /// Every request Ration's *own* code makes originates in one file.
    ///
    /// Sparkle also makes requests — update checks against the appcast, and the
    /// release download — but it does so from its own framework, not from code
    /// in this repository. `updateFeedIsTheExpectedHost` covers that half.
    @Test("all first-party networking is confined to LimitsClient")
    func networkingIsConfinedToTheClient() throws {
        for file in try swiftFiles() where file.url.lastPathComponent != "LimitsClient.swift" {
            for symbol in ["URLSession", "URLRequest", "NSURLConnection", "CFSocket"] {
                #expect(
                    !file.contents.contains(symbol),
                    "\(file.url.lastPathComponent) performs networking outside LimitsClient")
            }
        }
    }

    /// The update feed is the one host besides Anthropic that the shipped app
    /// contacts. It is set in `Scripts/bundle.sh` rather than Swift, so pin it
    /// here — a silent change of update host is exactly the kind of thing this
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

    @Test("no source file mentions a refresh token field")
    func noRefreshTokenUsage() throws {
        for file in try swiftFiles() {
            #expect(
                !file.contents.contains("refreshToken"),
                "\(file.url.lastPathComponent) references refreshToken")
        }
    }
}

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
