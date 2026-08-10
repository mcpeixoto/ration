import Foundation
import RationKit
import Testing

@testable import RationUI

/// A throwaway defaults domain, so tests never touch the real preferences.
private func scratchDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Settings: disabled providers")
struct DisabledProvidersSettingsTests {

    @Test("a fresh install has nothing disabled")
    @MainActor
    func defaultsToEmpty() {
        let settings = Settings(defaults: scratchDefaults("ration.tests.empty"))

        #expect(settings.disabledProviders.isEmpty)
    }

    @Test("the set survives a relaunch")
    @MainActor
    func roundTrips() {
        let defaults = scratchDefaults("ration.tests.roundtrip")

        let first = Settings(defaults: defaults)
        first.disabledProviders = ["codex"]

        let second = Settings(defaults: defaults)
        #expect(second.disabledProviders == ["codex"])
    }

    @Test("an id from a release that knew more providers is ignored")
    @MainActor
    func unknownIdsAreDropped() {
        let defaults = scratchDefaults("ration.tests.unknown")
        defaults.set(["codex", "something-else"], forKey: "disabledProviders")

        let settings = Settings(defaults: defaults)

        #expect(settings.disabledProviders == ["codex"])
    }

    @Test("emptying the set persists as empty rather than reverting")
    @MainActor
    func emptyingPersists() {
        let defaults = scratchDefaults("ration.tests.emptying")

        let first = Settings(defaults: defaults)
        first.disabledProviders = ["codex"]
        first.disabledProviders = []

        let second = Settings(defaults: defaults)
        #expect(second.disabledProviders.isEmpty)
    }
}
