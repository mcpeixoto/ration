import Foundation
import Testing

@testable import RationKit

// MARK: - Helpers

private func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "missing fixture \(name).json"
    )
    return try Data(contentsOf: url)
}

private func decode(_ name: String) throws -> UsageSnapshot {
    try UsageSnapshot.decode(from: fixture(name))
}

// MARK: - The happy path

@Suite("UsageSnapshot decoding")
struct UsageSnapshotDecodingTests {

    @Test("decodes the limits array from a typical response")
    func typical() throws {
        let snapshot = try decode("usage_typical")

        #expect(snapshot.limits.count == 3)

        let session = try #require(snapshot.limits.first { $0.kind == .session })
        #expect(session.percent == 32)
        #expect(session.severity == .normal)
        #expect(session.group == .session)
        #expect(session.isActive == false)
        #expect(session.scope == nil)

        let weekly = try #require(snapshot.limits.first { $0.kind == .weeklyAll })
        #expect(weekly.percent == 51)
        #expect(weekly.isActive == true)

        let scoped = try #require(snapshot.limits.first { $0.kind == .weeklyScoped })
        #expect(scoped.percent == 3)
        #expect(scoped.scope?.modelDisplayName == "Fable")
    }

    @Test("parses fractional-second ISO8601 timestamps with offsets")
    func timestamps() throws {
        let snapshot = try decode("usage_typical")
        let session = try #require(snapshot.limits.first { $0.kind == .session })
        let resets = try #require(session.resetsAt)

        // 2026-08-06T22:20:00.980592+00:00
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 6
        components.hour = 22
        components.minute = 20
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let expected = try #require(calendar.date(from: components))

        #expect(abs(resets.timeIntervalSince(expected)) < 1.0)
    }

    @Test("decodes spend when the plan has credits enabled")
    func spend() throws {
        let snapshot = try decode("usage_critical")
        let spend = try #require(snapshot.spend)

        #expect(spend.isEnabled == true)
        #expect(spend.percent == 25)
        #expect(spend.usedAmount == 12.50)
        #expect(spend.currencyCode == "USD")
    }

    @Test("treats a disabled spend block as not enabled")
    func spendDisabled() throws {
        let snapshot = try decode("usage_typical")
        let spend = try #require(snapshot.spend)
        #expect(spend.isEnabled == false)
        #expect(spend.usedAmount == 0)
    }
}

// MARK: - Forward compatibility
//
// The whole point of decoding `limits[]` generically is that Anthropic can add
// new limit kinds without breaking the app. These tests are the contract.

@Suite("Forward compatibility")
struct ForwardCompatibilityTests {

    @Test("keeps unknown limit kinds instead of dropping them")
    func unknownKindsSurvive() throws {
        let snapshot = try decode("usage_unknown_kinds")

        #expect(snapshot.limits.count == 4)
        #expect(snapshot.limits.contains { $0.kind == .other("monthly_quantum_flux") })
        #expect(snapshot.limits.contains { $0.kind == .other("brand_new_thing") })
    }

    @Test("gives unknown kinds a readable display name")
    func unknownKindsAreReadable() throws {
        let snapshot = try decode("usage_unknown_kinds")
        let flux = try #require(snapshot.limits.first { $0.kind == .other("monthly_quantum_flux") })
        #expect(flux.displayName == "Monthly Quantum Flux")
    }

    @Test("keeps unknown groups")
    func unknownGroupsSurvive() throws {
        let snapshot = try decode("usage_unknown_kinds")
        let new = try #require(snapshot.limits.first { $0.kind == .other("brand_new_thing") })
        #expect(new.group == .other("some_future_group"))
    }

    @Test("falls back to normal for an unrecognised severity rather than failing")
    func unknownSeverityIsNormal() throws {
        let snapshot = try decode("usage_unknown_kinds")
        let new = try #require(snapshot.limits.first { $0.kind == .other("brand_new_thing") })
        #expect(new.severity == .normal)
    }

    @Test("tolerates a null resets_at")
    func nullResetsAt() throws {
        let snapshot = try decode("usage_unknown_kinds")
        let new = try #require(snapshot.limits.first { $0.kind == .other("brand_new_thing") })
        #expect(new.resetsAt == nil)
    }
}

// MARK: - Fallback to the named keys

@Suite("Named-key fallback")
struct NamedKeyFallbackTests {

    @Test("synthesises limits from named keys when limits[] is absent")
    func synthesisesFromNamedKeys() throws {
        let snapshot = try decode("usage_named_only")

        #expect(snapshot.limits.count == 3)

        let session = try #require(snapshot.limits.first { $0.kind == .session })
        #expect(session.percent == 64.5)

        let weekly = try #require(snapshot.limits.first { $0.kind == .weeklyAll })
        #expect(weekly.percent == 22)

        let opus = try #require(snapshot.limits.first { $0.kind == .weeklyScoped })
        #expect(opus.percent == 71)
        #expect(opus.scope?.modelDisplayName == "Opus")
    }

    @Test("ignores null named keys")
    func ignoresNullNamedKeys() throws {
        let snapshot = try decode("usage_named_only")
        #expect(snapshot.limits.allSatisfy { $0.percent > 0 })
    }

    @Test("derives severity from percent when synthesising")
    func derivedSeverity() throws {
        let snapshot = try decode("usage_named_only")
        let opus = try #require(snapshot.limits.first { $0.kind == .weeklyScoped })
        #expect(opus.severity == .normal)  // 71% is below the warning threshold

        let session = try #require(snapshot.limits.first { $0.kind == .session })
        #expect(session.severity == .normal)  // 64.5%
    }

    @Test("an entirely empty response decodes to no limits rather than throwing")
    func emptyResponse() throws {
        let snapshot = try decode("usage_empty")
        #expect(snapshot.limits.isEmpty)
    }
}

// MARK: - Derived presentation values

@Suite("Snapshot presentation")
struct SnapshotPresentationTests {

    @Test("primary limit is the highest-percent one, so the worst number is what you see")
    func primaryIsWorst() throws {
        let snapshot = try decode("usage_typical")
        let primary = try #require(snapshot.primaryLimit)
        #expect(primary.kind == .weeklyAll)  // 51% beats 32% and 3%
    }

    @Test("primary limit is nil when there are no limits")
    func primaryNilWhenEmpty() throws {
        let snapshot = try decode("usage_empty")
        #expect(snapshot.primaryLimit == nil)
    }

    @Test("overall severity is the worst severity present")
    func overallSeverity() throws {
        #expect(try decode("usage_typical").overallSeverity == .normal)
        #expect(try decode("usage_critical").overallSeverity == .critical)
        #expect(try decode("usage_unknown_kinds").overallSeverity == .critical)
    }

    @Test("limits are ordered session first, then weekly, then everything else")
    func ordering() throws {
        let snapshot = try decode("usage_unknown_kinds")
        let kinds = snapshot.limits.map(\.kind)
        let sessionIndex = try #require(kinds.firstIndex(of: .session))
        let weeklyIndex = try #require(kinds.firstIndex(of: .weeklyScoped))
        let otherIndex = try #require(kinds.firstIndex(of: .other("monthly_quantum_flux")))
        #expect(sessionIndex < weeklyIndex)
        #expect(weeklyIndex < otherIndex)
    }

    @Test("well-known limits get human display names")
    func displayNames() throws {
        let snapshot = try decode("usage_typical")
        let names = Dictionary(
            uniqueKeysWithValues: snapshot.limits.map { ($0.kind, $0.displayName) })

        #expect(names[.session] == "Session")
        #expect(names[.weeklyAll] == "Weekly")
        #expect(names[.weeklyScoped] == "Weekly · Fable")
    }

    @Test("each limit has a stable identity across refreshes")
    func stableIdentity() throws {
        let a = try decode("usage_typical")
        let b = try decode("usage_typical")
        #expect(a.limits.map(\.id) == b.limits.map(\.id))
        #expect(Set(a.limits.map(\.id)).count == a.limits.count)
    }
}

// MARK: - Malformed input

@Suite("Malformed input")
struct MalformedInputTests {

    @Test("throws a typed error on invalid JSON rather than crashing")
    func invalidJSON() {
        #expect(throws: (any Error).self) {
            try UsageSnapshot.decode(from: Data("not json at all".utf8))
        }
    }

    @Test("a limit missing its percent is skipped, the rest still decode")
    func partiallyMalformedLimits() throws {
        let json = """
            {"limits": [
              {"kind": "session", "group": "session", "severity": "normal", "is_active": true},
              {"kind": "weekly_all", "group": "weekly", "percent": 40, "severity": "normal", "is_active": true}
            ]}
            """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        #expect(snapshot.limits.count == 1)
        #expect(snapshot.limits.first?.kind == .weeklyAll)
    }
}
