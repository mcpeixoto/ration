# Accounts Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Settings → Tools with Settings → Accounts, where each supported tool can be turned off — hiding it from the panel and menu bar, and stopping Ration from reading it.

**Architecture:** `ProviderRegistry` gains a `disabled` set that filters `visible` (and therefore `metered`, which every lifecycle method already iterates), so hiding a provider stops its polling with no change to those methods. `Settings` mirrors the set into `UserDefaults` for persistence. A new `MenuBarPresentation.allHidden` covers the everything-off state.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-accounts-tab-design.md`.
- **Do not read `~/.codex/auth.json`** or any other tool's credential store. Two existing guarantee tests in `Tests/RationKitTests/` enforce this and must stay green: *"only the Anthropic credential store touches the keychain"* and *"no source file reads another tool's credential store"*.
- No email or account id is displayed anywhere. Claude accounts are identified by plan name only (`UsagePoller.planName`).
- No new network hosts. No new files read.
- Store the **disabled** set, never the enabled set. An empty set means everything is on.
- Formatting: CI runs `swift format lint --recursive --strict Sources Tests`. Run `swift format --in-place --recursive Sources Tests` before the final commit.
- Full suite command: `swift test`. It currently passes with 235 tests.
- `ProviderRegistry`, `UsagePoller` and `Settings` are all `@MainActor`; tests touching them need `@MainActor` on the test function.

---

### Task 1: Let a source forget what it cached

Hiding a provider must mean Ration stops reading it. Polling stops on its own once the provider leaves `metered`, but `AnthropicUsageSource` holds a credential in memory via `CachingCredentialStore` between polls — so without this, "hidden and not read" is only half true for as long as the app keeps running.

**Files:**
- Modify: `Sources/RationKit/UsageSource.swift:15-39`
- Modify: `Sources/RationKit/LimitsClient.swift:150-190` (`AnthropicUsageSource`)
- Modify: `Sources/RationKit/UsagePoller.swift:77-81`
- Test: `Tests/RationKitTests/UsagePollerTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `UsageSource.forget()`, `UsagePoller.disable()`. Task 2 calls `disable()`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/RationKitTests/UsagePollerTests.swift`:

```swift
// MARK: - Forgetting

/// Counts how many times the underlying store was actually consulted, so a
/// test can tell a cache hit from a real read.
private final class CountingCredentialStore: CredentialStore, @unchecked Sendable {

    private let lock = NSLock()
    private var count = 0

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func credential() throws -> Credential {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return Credential(
            accessToken: "token",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            subscriptionType: "max",
            rateLimitTier: nil)
    }
}

@Suite("Forgetting a source")
struct SourceForgetTests {

    @Test("a cached credential is served without re-reading the store")
    func cachesBetweenReads() throws {
        let counting = CountingCredentialStore()
        let caching = CachingCredentialStore(wrapping: counting)

        _ = try caching.credential()
        _ = try caching.credential()

        #expect(counting.reads == 1)
    }

    @Test("forgetting drops the cached credential, so the next read hits the store")
    func forgetInvalidatesCache() throws {
        let counting = CountingCredentialStore()
        let caching = CachingCredentialStore(wrapping: counting)
        let source = AnthropicUsageSource(credentialStore: caching)

        _ = try caching.credential()
        #expect(counting.reads == 1)

        source.forget()
        _ = try caching.credential()

        #expect(counting.reads == 2)
    }

}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SourceForgetTests`
Expected: FAIL — `value of type 'AnthropicUsageSource' has no member 'forget'`.

- [ ] **Step 3: Add `forget()` to the protocol**

In `Sources/RationKit/UsageSource.swift`, add to the `UsageSource` protocol body, after `promptsForPermission`:

```swift
    /// Drop anything held in memory between polls.
    ///
    /// Called when the user turns a provider off. Polling stops on its own —
    /// a hidden provider leaves `metered` — but a source holding a cached
    /// credential would keep holding it for as long as the app runs, and
    /// "hidden and not read" would be only half true.
    func forget()
```

And extend the existing default-implementation extension:

```swift
extension UsageSource {
    public var promptsForPermission: Bool { false }

    /// Most sources cache nothing between polls, so forgetting costs nothing.
    public func forget() {}
}
```

- [ ] **Step 4: Implement it for the one source that caches**

In `Sources/RationKit/LimitsClient.swift`, add to `AnthropicUsageSource` immediately after `fetchUsage()`:

```swift
    /// The cached credential is the only thing this source keeps between
    /// polls. Dropping it means the next read goes to the keychain again.
    public func forget() {
        (credentialStore as? CachingCredentialStore)?.invalidate()
    }
```

- [ ] **Step 5: Add `disable()` to the poller**

In `Sources/RationKit/UsagePoller.swift`, add immediately after `suspend()`:

```swift
    /// Stops polling *and* drops whatever the source cached.
    ///
    /// Deliberately distinct from `suspend()`, which is for sleep: waking from
    /// sleep should not have to re-earn a keychain prompt, but turning a
    /// provider off should.
    public func disable() {
        suspend()
        source.forget()
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter SourceForgetTests`
Expected: PASS, 2 tests.

Then run: `swift test`
Expected: PASS, 237 tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/RationKit/UsageSource.swift Sources/RationKit/LimitsClient.swift \
        Sources/RationKit/UsagePoller.swift Tests/RationKitTests/UsagePollerTests.swift
git commit -m "feat: let a usage source forget what it cached"
```

---

### Task 2: Teach the registry which providers are off

**Files:**
- Modify: `Sources/RationKit/ProviderRegistry.swift`
- Create: `Tests/RationKitTests/ProviderRegistryTests.swift`

**Interfaces:**
- Consumes: `UsagePoller.disable()` from Task 1.
- Produces:
  - `ProviderRegistry.disabled: Set<Provider.ID>` (read-only from outside; `Provider.ID` is `String`)
  - `ProviderRegistry.init(entries:primary:disabled:)`
  - `ProviderRegistry.setEnabled(_ enabled: Bool, for provider: Provider)`
  - `ProviderRegistry.isEnabled(_ provider: Provider) -> Bool`
  - `ProviderRegistry.standard(schedule:disabled:)`

  Task 5 calls `setEnabled` and `isEnabled`; Task 6 calls `standard(schedule:disabled:)` and reads `disabled`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/RationKitTests/ProviderRegistryTests.swift`:

```swift
import Foundation
import Testing

@testable import RationKit

/// A source that reports whatever availability the test wants and never
/// succeeds at fetching, so no test depends on network or disk.
private struct FakeSource: UsageSource {

    let provider: Provider
    var reported: ProviderAvailability = .ready

    func availability() -> ProviderAvailability { reported }

    func fetchUsage() async throws -> UsageSnapshot {
        throw LimitsError.unavailable(reason: "test double")
    }
}

@MainActor
private func makeRegistry(
    disabled: Set<String> = [],
    primary: Provider = .claude
) -> ProviderRegistry {
    ProviderRegistry(
        entries: [
            ProviderRegistry.Entry(
                provider: .claude,
                poller: UsagePoller(source: FakeSource(provider: .claude)),
                history: nil),
            ProviderRegistry.Entry(
                provider: .codex,
                poller: UsagePoller(source: FakeSource(provider: .codex)),
                history: nil),
        ],
        primary: primary,
        disabled: disabled)
}

@Suite("ProviderRegistry visibility")
struct ProviderRegistryVisibilityTests {

    @Test("everything is enabled by default")
    @MainActor
    func defaultsToAllEnabled() {
        let registry = makeRegistry()

        #expect(registry.disabled.isEmpty)
        #expect(registry.visible.count == 2)
        #expect(registry.isEnabled(.claude))
        #expect(registry.isEnabled(.codex))
    }

    @Test("a disabled provider leaves visible and metered")
    @MainActor
    func disabledIsHidden() {
        let registry = makeRegistry(disabled: ["codex"])

        #expect(registry.visible.map(\.id) == ["claude"])
        #expect(registry.metered.map(\.id) == ["claude"])
        #expect(!registry.isEnabled(.codex))
    }

    @Test("hiding the primary promotes the next one")
    @MainActor
    func hidingPrimaryPromotesNext() {
        let registry = makeRegistry(primary: .claude)

        registry.setEnabled(false, for: .claude)

        #expect(registry.primaryEntry?.provider == .codex)
    }

    @Test("hiding everything leaves no primary entry")
    @MainActor
    func hidingAllLeavesNothing() {
        let registry = makeRegistry()

        registry.setEnabled(false, for: .claude)
        registry.setEnabled(false, for: .codex)

        #expect(registry.visible.isEmpty)
        #expect(registry.primaryEntry == nil)
    }

    @Test("re-enabling brings a provider back")
    @MainActor
    func enablingRestores() {
        let registry = makeRegistry(disabled: ["codex"])

        registry.setEnabled(true, for: .codex)

        #expect(registry.disabled.isEmpty)
        #expect(registry.visible.count == 2)
    }
}

@Suite("ProviderRegistry polling")
struct ProviderRegistryPollingTests {

    @Test("start does not start a disabled provider")
    @MainActor
    func startSkipsDisabled() {
        let registry = makeRegistry(disabled: ["codex"])

        registry.start()

        #expect(registry.entry(for: .claude)?.poller.isRunning == true)
        #expect(registry.entry(for: .codex)?.poller.isRunning == false)
    }

    @Test("disabling a running provider stops it immediately")
    @MainActor
    func disablingStopsPolling() {
        let registry = makeRegistry()
        registry.start()
        #expect(registry.entry(for: .codex)?.poller.isRunning == true)

        registry.setEnabled(false, for: .codex)

        #expect(registry.entry(for: .codex)?.poller.isRunning == false)
    }

    @Test("enabling a provider starts it without waiting for a relaunch")
    @MainActor
    func enablingStartsPolling() {
        let registry = makeRegistry(disabled: ["codex"])
        registry.start()

        registry.setEnabled(true, for: .codex)

        #expect(registry.entry(for: .codex)?.poller.isRunning == true)
    }

    @Test("setting the state it is already in changes nothing")
    @MainActor
    func settingSameStateIsANoOp() {
        let registry = makeRegistry()
        registry.start()

        registry.setEnabled(true, for: .codex)

        #expect(registry.disabled.isEmpty)
        #expect(registry.entry(for: .codex)?.poller.isRunning == true)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProviderRegistry`
Expected: FAIL — no `disabled:` parameter on the initialiser, no `setEnabled`, no `isEnabled`.

- [ ] **Step 3: Add the disabled set and the initialiser parameter**

In `Sources/RationKit/ProviderRegistry.swift`, replace the `entries` / `primary` / `init` block (currently lines 33-51) with:

```swift
    public private(set) var entries: [Entry]

    /// Providers the user has turned off in Settings → Accounts.
    ///
    /// The *disabled* set is stored rather than the enabled one so that an
    /// empty set is the correct fresh-install state, and a provider added in a
    /// later release arrives switched on instead of silently hidden.
    public private(set) var disabled: Set<Provider.ID>

    /// Which provider owns the menu bar. Persisted by the app layer.
    public var primary: Provider {
        didSet {
            guard !visible.contains(where: { $0.provider == primary }) else { return }
            // Selected a provider that has since vanished — fall back rather
            // than showing an empty menu bar item.
            primary = visible.first?.provider ?? .claude
        }
    }

    public init(
        entries: [Entry],
        primary: Provider = .claude,
        disabled: Set<Provider.ID> = []
    ) {
        self.entries = entries
        self.disabled = disabled
        self.primary =
            entries.contains { $0.provider == primary }
            ? primary
            : entries.first?.provider ?? .claude
    }
```

- [ ] **Step 4: Filter `visible`, and fix `primaryEntry` to respect it**

In the same file, replace `visible` (currently lines 55-57) and `primaryEntry` (currently lines 68-70) with:

```swift
    /// The providers worth putting in front of the user: installed, not turned
    /// off, whatever else is true of them. A tool you do not use is not an
    /// error to report.
    public var visible: [Entry] {
        entries.filter { $0.availability.isVisible && !disabled.contains($0.id) }
    }
```

```swift
    /// Resolved against `visible`, not `entries`: a provider the user turned
    /// off must not come back through the menu bar's own lookup.
    public var primaryEntry: Entry? {
        visible.first { $0.provider == primary } ?? visible.first
    }
```

- [ ] **Step 5: Add `isEnabled` and `setEnabled`**

In the same file, add immediately after `entry(for:)`:

```swift
    public func isEnabled(_ provider: Provider) -> Bool {
        !disabled.contains(provider.id)
    }

    /// Turns a provider on or off.
    ///
    /// Takes effect now rather than at next launch: a poller just disabled is
    /// stopped and told to forget what it cached, and one just enabled starts
    /// polling. Hiding the provider that owns the menu bar promotes the next
    /// one, which `primary`'s own fallback handles.
    public func setEnabled(_ enabled: Bool, for provider: Provider) {
        guard enabled != isEnabled(provider) else { return }

        if enabled {
            disabled.remove(provider.id)
            if let entry = entry(for: provider), entry.availability.hasQuota {
                entry.poller.start()
                entry.history?.refresh()
            }
        } else {
            disabled.insert(provider.id)
            entry(for: provider)?.poller.disable()
        }

        // Re-run the fallback: the menu bar's provider may have just been
        // hidden, or the only visible one may have just come back.
        let current = primary
        primary = current
    }
```

- [ ] **Step 6: Let `standard` take a disabled set**

In the same file, change the signature of `standard` (currently line 115) and its returned registry:

```swift
    public static func standard(
        schedule: PollSchedule = PollSchedule(),
        disabled: Set<Provider.ID> = []
    ) -> ProviderRegistry {
        ProviderRegistry(
            entries: [
```

and change the closing of that call from `])` to:

```swift
            ],
            disabled: disabled)
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter ProviderRegistry`
Expected: PASS, 8 tests.

Then run: `swift test`
Expected: PASS, 245 tests.

- [ ] **Step 8: Commit**

```bash
git add Sources/RationKit/ProviderRegistry.swift Tests/RationKitTests/ProviderRegistryTests.swift
git commit -m "feat: let the registry turn a provider off"
```

---

### Task 3: A menu bar presentation for "everything is hidden"

**Files:**
- Modify: `Sources/RationKit/MenuBarPresentation.swift:172-181`
- Test: `Tests/RationKitTests/MenuBarPresentationTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `MenuBarPresentation.allHidden`. Task 6 returns it from `AppDelegate.presentation`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/RationKitTests/MenuBarPresentationTests.swift`:

```swift
@Suite("All hidden")
struct AllHiddenPresentationTests {

    @Test("shows an icon and nothing else")
    func isIconOnly() {
        let presentation = MenuBarPresentation.allHidden

        #expect(presentation.title == nil)
        #expect(presentation.tint == nil)
        #expect(presentation.bar == nil)
    }

    @Test("is not the same thing as needing setup")
    func differsFromSetupRequired() {
        #expect(MenuBarPresentation.allHidden != MenuBarPresentation.setupRequired)
    }

    @Test("says where to turn an account back on")
    func pointsAtTheAccountsTab() {
        #expect(MenuBarPresentation.allHidden.tooltip.contains("Accounts"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AllHiddenPresentationTests`
Expected: FAIL — `type 'MenuBarPresentation' has no member 'allHidden'`.

- [ ] **Step 3: Add the case**

In `Sources/RationKit/MenuBarPresentation.swift`, add immediately after the `setupRequired` declaration:

```swift
    /// Every account has been turned off in Settings → Accounts.
    ///
    /// Deliberately not `setupRequired`: "you hid everything" and "no supported
    /// tool was found" are different sentences pointing at different fixes.
    public static let allHidden = MenuBarPresentation(
        title: nil,
        symbolName: "eye.slash",
        tint: nil,
        accessibilityLabel: "Ration: all accounts hidden",
        tooltip: "Every account is hidden. Turn one on in Settings → Accounts."
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AllHiddenPresentationTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/RationKit/MenuBarPresentation.swift Tests/RationKitTests/MenuBarPresentationTests.swift
git commit -m "feat: a menu bar presentation for every account hidden"
```

---

### Task 4: Persist the disabled set

`Settings` lives in `RationUI`, which has no test target today — `Package.swift` declares only `RationKitTests`. This task adds one, so the persistence this feature depends on is actually covered.

**Files:**
- Modify: `Package.swift:36-40`
- Modify: `Sources/RationUI/Settings.swift`
- Create: `Tests/RationUITests/SettingsTests.swift`

**Interfaces:**
- Consumes: `Provider.named(_:)` from `RationKit`.
- Produces: `Settings.disabledProviders: Set<String>`. Tasks 5 and 6 read and write it.

- [ ] **Step 1: Write the failing test**

Create `Tests/RationUITests/SettingsTests.swift`:

```swift
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
```

- [ ] **Step 2: Add the test target**

In `Package.swift`, add after the existing `RationKitTests` test target and before the closing `]`:

```swift
        .testTarget(
            name: "RationUITests",
            dependencies: ["RationUI"]
        ),
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter DisabledProvidersSettingsTests`
Expected: FAIL — `value of type 'Settings' has no member 'disabledProviders'`.

- [ ] **Step 4: Add the setting**

In `Sources/RationUI/Settings.swift`, add to the `Key` enum:

```swift
        static let disabledProviders = "disabledProviders"
```

Add to the end of `init(defaults:)`:

```swift
        // Ids from a future release are dropped rather than kept: an unknown
        // provider cannot be shown in the Accounts tab, so a set holding one
        // would be impossible to clear from the UI.
        self.disabledProviders = Set(
            (defaults.stringArray(forKey: Key.disabledProviders) ?? [])
                .filter { Provider.named($0) != nil })
```

Add the stored property, immediately after `primaryProvider`:

```swift
    /// Providers the user turned off in Settings → Accounts.
    ///
    /// Hidden means hidden *and* unread: the registry stops polling them. The
    /// disabled set is stored rather than the enabled one so a fresh install
    /// stores nothing, and a provider added in a later release arrives
    /// switched on instead of silently hidden.
    ///
    /// Sorted on the way out purely so the stored value is stable and diffable.
    public var disabledProviders: Set<String> {
        didSet {
            defaults.set(disabledProviders.sorted(), forKey: Key.disabledProviders)
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter DisabledProvidersSettingsTests`
Expected: PASS, 4 tests.

Then run: `swift test`
Expected: PASS, 252 tests.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/RationUI/Settings.swift Tests/RationUITests/SettingsTests.swift
git commit -m "feat: persist which providers are turned off"
```

---

### Task 5: The Accounts tab

**Files:**
- Delete: `Sources/RationUI/ProvidersSettingsView.swift`
- Create: `Sources/RationUI/AccountsSettingsView.swift`
- Modify: `Sources/RationUI/SettingsView.swift:24-27`
- Modify: `README.md` (the "Settings → Tools" sentence)

**Interfaces:**
- Consumes: `ProviderRegistry.isEnabled(_:)` and `setEnabled(_:for:)` (Task 2), `Settings.disabledProviders` (Task 4), `UsagePoller.planName`.
- Produces: `AccountsSettingsView(registry:settings:)`.

- [ ] **Step 1: Move the file**

```bash
git mv Sources/RationUI/ProvidersSettingsView.swift Sources/RationUI/AccountsSettingsView.swift
```

- [ ] **Step 2: Replace its contents**

Write `Sources/RationUI/AccountsSettingsView.swift`:

```swift
import RationKit
import SwiftUI

/// The account behind every tool Ration knows about, and a switch for each one
/// it can actually meter.
///
/// Listing tools it cannot meter is deliberate. "Where is Cursor?" deserves an
/// answer in the app rather than in an issue thread, and the answer — its usage
/// lives behind a login on its website, and Ration will not read your browser's
/// cookies to get it — is a design decision worth stating out loud.
///
/// There is deliberately no way to add a *second* account of the same tool.
/// Claude Code and Codex each store only the account you are signed into, and
/// Ration reads what they stored rather than keeping credentials of its own.
struct AccountsSettingsView: View {

    @Bindable var registry: ProviderRegistry
    @Bindable var settings: Settings

    /// Providers that can be metered and have not been switched off.
    private var selectable: [Provider] {
        registry.metered.map(\.provider)
    }

    /// Everything that can carry a gauge, switched on or not — so turning one
    /// off does not make its own switch disappear.
    private var accounts: [ProviderRegistry.Entry] {
        registry.entries.filter { $0.availability.hasQuota }
    }

    private var unmetered: [ProviderRegistry.Entry] {
        registry.entries.filter { !$0.availability.hasQuota }
    }

    var body: some View {
        Form {
            Section {
                Picker("Menu bar shows", selection: $settings.primaryProvider) {
                    ForEach(selectable) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .disabled(selectable.count < 2)

                Text(
                    "The menu bar reports one account. The panel shows them all — "
                        + "switch at the top of it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Accounts") {
                ForEach(accounts) { entry in
                    AccountRow(
                        entry: entry,
                        isEnabled: Binding(
                            get: { registry.isEnabled(entry.provider) },
                            set: { setEnabled($0, for: entry.provider) }
                        ))
                }

                if registry.visible.isEmpty {
                    Text(
                        "Every account is off. Ration is not reading anything, "
                            + "and the menu bar shows no usage."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !unmetered.isEmpty {
                Section("Not metered") {
                    ForEach(unmetered) { entry in
                        UnmeteredRow(entry: entry)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The registry is the live truth; settings only persists it. Writing both
    /// here keeps that one-way relationship in one place.
    private func setEnabled(_ enabled: Bool, for provider: Provider) {
        registry.setEnabled(enabled, for: provider)
        settings.disabledProviders = registry.disabled
    }
}

/// One metered account: what it is, what Ration reads for it, and a switch.
private struct AccountRow: View {

    let entry: ProviderRegistry.Entry
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.provider.symbolName)
                .frame(width: 16)
                .foregroundStyle(isEnabled ? Theme.accent : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Show \(entry.provider.toolName)")
        }
        .accessibilityElement(children: .contain)
    }

    /// The plan is the only name Ration has for an account: the session
    /// Claude Code stores carries no email and no account id.
    private var title: String {
        guard let plan = entry.poller.planName, !plan.isEmpty else {
            return entry.provider.toolName
        }
        return "\(entry.provider.toolName) — \(plan.capitalized)"
    }

    private var detail: String {
        guard isEnabled else { return "Hidden, and not being read." }

        switch entry.availability {
        case .ready:
            if let percent = entry.poller.state.snapshot?.primaryLimit?.percent {
                return "\(Int(percent.rounded()))% of the current window used."
            }
            return "Ready."
        default:
            return entry.availability.explanation ?? "Ready."
        }
    }
}

/// A tool Ration can see but cannot meter. No switch: there is nothing to
/// turn off.
private struct UnmeteredRow: View {

    let entry: ProviderRegistry.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.provider.symbolName)
                .frame(width: 16)
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.provider.toolName)
                    .foregroundStyle(.secondary)
                Text(entry.availability.explanation ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: Point the tab at it**

In `Sources/RationUI/SettingsView.swift`, replace lines 24-27:

```swift
            if let registry {
                AccountsSettingsView(registry: registry, settings: settings)
                    .tabItem { Label("Accounts", systemImage: "person.2") }
            }
```

- [ ] **Step 4: Update the README**

In `README.md`, replace `**Settings → Tools**` with `**Settings → Accounts**` in the sentence beginning "The last three are listed in".

- [ ] **Step 5: Verify it builds and nothing regressed**

Run: `swift build`
Expected: build succeeds.

Run: `swift test`
Expected: PASS, 252 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/RationUI/AccountsSettingsView.swift Sources/RationUI/SettingsView.swift README.md
git commit -m "feat: replace the Tools tab with an Accounts tab"
```

---

### Task 6: Wire it into the app

**Files:**
- Modify: `Sources/Ration/RationApp.swift:31-36`, `:60-62`, `:70-81`
- Modify: `Sources/RationUI/PopoverView.swift:148-158`

**Interfaces:**
- Consumes: `ProviderRegistry.standard(schedule:disabled:)`, `MenuBarPresentation.allHidden`, `Settings.disabledProviders`.
- Produces: nothing further.

- [ ] **Step 1: Load the disabled set at launch**

In `Sources/Ration/RationApp.swift`, replace the body of `override init()` (currently lines 59-63):

```swift
    override init() {
        self.registry = ProviderRegistry.standard(
            schedule: settings.schedule,
            disabled: settings.disabledProviders)
        super.init()
        registry.primary = settings.primaryProvider
    }
```

- [ ] **Step 2: Distinguish "hidden everything" from "nothing installed"**

In the same file, replace the first `guard` of `presentation` (currently line 71):

```swift
        guard let entry = registry.primaryEntry else {
            // Two different dead ends, and they need different sentences: one
            // is fixed in the Accounts tab, the other by installing a tool.
            return registry.entries.contains { $0.availability.isVisible }
                ? .allHidden
                : .setupRequired
        }
```

- [ ] **Step 3: Keep the menu bar's provider in step**

Hiding the account that owns the menu bar makes the registry promote the next
one on its own. Without this the promotion is forgotten at quit, because only
`Settings` is persisted.

In the same file, keep the existing `.onChange(of: appDelegate.settings.primaryProvider)`
modifier (currently lines 34-36) exactly as it is, and add this one directly
after it:

```swift
        .onChange(of: appDelegate.registry.primary) { _, provider in
            appDelegate.settings.primaryProvider = provider
        }
```

The two do not loop: the second writes the setting, which fires the first,
which assigns `registry.primary` a value it already holds — and SwiftUI's
`onChange` only fires on an actual change.

- [ ] **Step 4: Say so in the panel**

In `Sources/RationUI/PopoverView.swift`, replace the `else` branch of `content(now:)` (currently lines 151-157):

```swift
        } else if registry.entries.contains(where: { $0.availability.isVisible }) {
            StatusMessageView(
                symbol: "eye.slash",
                title: "Everything is hidden",
                message:
                    "You have turned off every account, so Ration is not reading anything. "
                    + "Turn one back on to see your usage.",
                action: ("Open Accounts", openSettings)
            )
        } else {
            StatusMessageView(
                symbol: "questionmark.circle",
                title: "Nothing to show",
                message: "No supported tool was found on this Mac."
            )
        }
```

- [ ] **Step 5: Verify**

Run: `swift build`
Expected: build succeeds.

Run: `swift test`
Expected: PASS, 252 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/Ration/RationApp.swift Sources/RationUI/PopoverView.swift
git commit -m "feat: honour hidden accounts in the menu bar and the panel"
```

---

### Task 7: Format, verify, install

**Files:**
- Modify: whatever `swift format` touches.

- [ ] **Step 1: Format**

Run: `swift format --in-place --recursive Sources Tests`

- [ ] **Step 2: Check CI's exact gate**

Run: `swift format lint --recursive --strict Sources Tests`
Expected: no output, exit 0.

- [ ] **Step 3: Full suite**

Run: `swift test`
Expected: PASS, 252 tests.

- [ ] **Step 4: Run it for real**

```bash
DEVELOPER_ID="Developer ID Application: Miguel Peixoto (H874DPF6H5)" ./Scripts/install.sh release
```

Open Settings → Accounts. Confirm by hand:
- Toggling Codex off removes it from the panel's provider switcher.
- Toggling both off leaves the menu bar showing the `eye.slash` icon with no percentage, and the panel showing "Everything is hidden" with a working "Open Accounts" button.
- Toggling one back on restores the gauge without relaunching.
- Quitting and relaunching preserves whatever was toggled off.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "style: swift-format the Accounts tab work"
```

The work is on the `accounts-tab` branch. Landing it on `main` happens after
the final whole-branch review, not here.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| 1. Where the on/off state lives | 2 (registry), 4 (persistence) |
| 2. What hiding does | 1 (forget/disable), 2 (visible filter, setEnabled) |
| 3. Hiding the menu bar's provider | 2 (`primaryEntry` resolved against `visible`), 6 (step 3) |
| 4. Hiding every account | 3 (presentation), 6 (steps 2 and 4) |
| 5. The tab | 5 |
| 6. Testing — registry visibility/lifecycle | 2 |
| 6. Testing — settings round-trip, unknown ids | 4 |
| 6. Testing — presentation distinct from setupRequired | 3 |
| 6. Testing — credential cache dropped on disable | 1 |
| Migration: none needed | 2 and 4 both default to an empty set |

**Type consistency:** `Provider.ID` is `String` (`Provider` is `Identifiable` with `let id: String`), so `Set<Provider.ID>` on the registry and `Set<String>` on `Settings` are the same type and assign directly — used in Task 5 step 2 (`settings.disabledProviders = registry.disabled`) and Task 6 step 1. `ProviderRegistry.Entry.id` is `provider.id`, which is what the `visible.map(\.id)` assertions in Task 2 compare against.

**Known risk:** Task 4 adds the first test target for `RationUI`. If linking SwiftUI in a SwiftPM test target fails on this toolchain, move `disabledProviders` persistence behind a small plain type in `RationKit` and test it there instead — do not skip the coverage.
