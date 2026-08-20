import Foundation

#if canImport(FoundationNetworking)
// URLSession lives in a separate module on Linux.
import FoundationNetworking
#endif

/// Reads the release feed and reports the newest published version.
///
/// macOS installs updates itself through Sparkle, which fetches this same
/// appcast and verifies the download against a signing key. A Linux tarball has
/// no equivalent installer, so the tray reports what is available and leaves
/// installing it to the user.
///
/// Deliberately the same feed rather than the GitHub API: it is the host the
/// app already documents and the tests already pin, and adding a second update
/// host to a program whose whole promise is "three hosts, all listed" would be
/// a poor trade for a version string.
public struct UpdateFeedClient: Sendable {

    /// The feed `Scripts/bundle.sh` writes into the macOS bundle.
    public static let feedURL =
        "https://raw.githubusercontent.com/mcpeixoto/ration/main/appcast.xml"

    public init() {}

    /// The newest `shortVersionString` in the feed, or `nil` when it cannot be
    /// read. Carries no credential and no usage data.
    public func latestVersion() async -> String? {
        guard let url = URL(string: Self.feedURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Ration/\(Ration.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let xml = String(data: data, encoding: .utf8)
        else { return nil }

        return Self.newestVersion(inFeed: xml)
    }

    /// Pulls every published version out of the feed and returns the highest.
    ///
    /// Order in the file is not trusted — a re-published item could sit
    /// anywhere — so the versions are compared numerically.
    public static func newestVersion(inFeed xml: String) -> String? {
        guard
            let pattern = try? NSRegularExpression(
                pattern: #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#)
        else { return nil }

        let range = NSRange(xml.startIndex..., in: xml)
        let versions = pattern.matches(in: xml, range: range).compactMap { match in
            Range(match.range(at: 1), in: xml).map { String(xml[$0]) }
        }
        return versions.max { isVersion($0, olderThan: $1) }
    }

    /// Compares dotted versions field by field, so 0.10.0 beats 0.9.9.
    public static func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}
