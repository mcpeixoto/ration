import Foundation
import Testing

@testable import RationKit

@Suite("Update feed")
struct UpdateFeedTests {

    private let feed = """
        <?xml version='1.0' encoding='utf-8'?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <sparkle:shortVersionString>0.9.9</sparkle:shortVersionString>
            </item>
            <item>
              <sparkle:shortVersionString>0.10.0</sparkle:shortVersionString>
            </item>
            <item>
              <sparkle:shortVersionString>0.8.2</sparkle:shortVersionString>
            </item>
          </channel>
        </rss>
        """

    @Test("reports the highest version in the feed, not the first")
    func picksHighest() {
        #expect(UpdateFeedClient.newestVersion(inFeed: feed) == "0.10.0")
    }

    @Test("a feed with no versions reports nothing rather than guessing")
    func emptyFeed() {
        #expect(UpdateFeedClient.newestVersion(inFeed: "<rss></rss>") == nil)
    }

    /// Field-by-field, so a two-digit minor does not sort below a one-digit one.
    @Test("compares versions numerically")
    func comparesNumerically() {
        #expect(UpdateFeedClient.isVersion("0.9.9", olderThan: "0.10.0"))
        #expect(!UpdateFeedClient.isVersion("0.10.0", olderThan: "0.9.9"))
        #expect(!UpdateFeedClient.isVersion("1.0", olderThan: "1.0.0"))
        #expect(UpdateFeedClient.isVersion("1.0", olderThan: "1.0.1"))
    }

    /// The tray reads the feed Sparkle already reads. A second update host in
    /// a program that promises "three hosts, all listed" would be a poor trade.
    @Test("the Linux update check uses the macOS feed")
    func sameFeedAsSparkle() {
        #expect(
            UpdateFeedClient.feedURL
                == "https://raw.githubusercontent.com/mcpeixoto/ration/main/appcast.xml")
    }
}
