import Foundation

/// Text for posting an unlocked creature. Pure, so a test can pin the words
/// without spinning up AppKit or opening a browser.
public enum CreatureShare {

    /// Caption for X, Messages, and the pasteboard.
    ///
    /// The image is attached separately. This is only the sentence, plus the
    /// repository so a stranger can find the app.
    public static func caption(name: String, caught: Int, of total: Int) -> String {
        "Unlocked \(name) in Ration — \(caught) of \(total).\n\ngithub.com/mcpeixoto/ration"
    }

    public static func caption(for creature: Creature, caughtCount: Int) -> String {
        caption(name: creature.name, caught: caughtCount, of: Dex.roster.count)
    }
}
