# Ration — a macOS menu bar meter for Claude usage

## Context

There is no good native way to see how much of your Claude plan you have burned without typing `/usage` inside Claude Code. For someone running many long agent sessions, hitting a 5-hour limit mid-task is disruptive and invisible until it happens.

**Ration** is a small, native macOS menu bar app that keeps that number permanently visible. It is being built to open-source, so the bar is not "works on my machine" — it is a polished, notarized, `brew install`-able app with a credible security story, because it reads a live OAuth token.

Target: `/Users/mcpeixoto/Documents/Coding/Ration` (new git repo).

### Verified during research

All of the following was confirmed live on this machine, not assumed:

| Fact | Detail |
|---|---|
| Endpoint | `GET https://api.anthropic.com/api/oauth/usage` |
| Auth | `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20` |
| Token source | Keychain generic password, service `Claude Code-credentials`, JSON → `.claudeAiOauth.accessToken` |
| Token TTL | ~12h; Claude Code refreshes it. Also exposes `subscriptionType` (`max`) and `rateLimitTier` (`default_claude_max_5x`) |
| Keychain ACL | decrypt allowed only for `/usr/bin/security` → a third-party app gets a **one-time** "Always Allow" prompt |
| Toolchain | Xcode 26.6, Swift 6.3, macOS 26 (arm64) |

Live response shape (real values at time of research):

```jsonc
{
  "five_hour":  { "utilization": 32.0, "resets_at": "2026-08-06T22:20:00Z", "limit_dollars": null, ... },
  "seven_day":  { "utilization": 51.0, "resets_at": "2026-08-09T01:00:00Z", ... },
  "seven_day_opus": null, "seven_day_sonnet": null, "tangelo": null, /* feature-flagged, often null */
  "spend": { "used": {"amount_minor":0,"currency":"USD","exponent":2}, "percent":0, "enabled":false, ... },
  "extra_usage": { "is_enabled": false, ... },
  "limits": [                                   // ← render from THIS, not the named keys
    {"kind":"session",       "group":"session","percent":32,"severity":"normal","resets_at":"…","scope":null,          "is_active":false},
    {"kind":"weekly_all",    "group":"weekly", "percent":51,"severity":"normal","resets_at":"…","scope":null,          "is_active":true},
    {"kind":"weekly_scoped", "group":"weekly", "percent":3, "severity":"normal","resets_at":"…","scope":{"model":{"display_name":"Fable"}}, "is_active":false}
  ]
}
```

**Key architectural consequence:** drive the UI off the generic `limits[]` array. New limit kinds Anthropic adds then appear automatically with no app update, and `severity` comes from the server so we never invent our own thresholds. The named top-level keys are treated as a fallback only.

## Decisions made

- **Scope:** v1 = live limits API. v2 (separate cycle) = local `~/.claude/projects/**/*.jsonl` transcript analytics — per-model, per-project, cost, burn rate, sparkline. v1 must not paint v2 into a corner.
- **Name:** Ration. Avoids the Claude trademark in the product name.
- **Menu bar display:** user-selectable mode, defaulting to session %.
- **v1 features:** threshold notifications, launch at login, live reset countdowns, severity coloring.
- **Distribution:** Homebrew cask from a personal tap, backed by a notarized DMG on GitHub Releases.
- **Stack:** SwiftUI `MenuBarExtra`. No Electron, no runtime dependency, ~5 MB app.

## Security posture (non-negotiable — this is what makes it safe to open-source)

1. **Read the Keychain, never write it.** Read `accessToken` only. Never read, store, log, or transmit the refresh token.
2. **Never refresh the token.** On `401`, stop polling and show a "Sign in with Claude Code" state. Claude Code owns the refresh lifecycle. Ration can never invalidate the user's session.
3. **One network host, ever.** `api.anthropic.com`. Enforced by a unit test asserting no other host string exists in the source tree.
4. **No telemetry. No analytics. No crash reporting.** Stated in README and PRIVACY.md.
5. **Token never leaves memory.** Not written to disk, not in `UserDefaults`, not in logs. A redacting log formatter strips anything matching the token prefix.
6. Not sandboxed (v2 needs `~/.claude` reads) → hardened runtime + notarization instead. Documented in SECURITY.md.

## Architecture

Three SwiftPM targets so core logic is testable with zero UI:

```
Sources/
  RationKit/          ← pure logic, no SwiftUI, 100% unit-testable
    CredentialStore.swift    protocol + Keychain impl (SecItemCopyMatching, read-only)
    LimitsClient.swift       protocol + URLSession impl → UsageSnapshot
    UsageSnapshot.swift      Codable models; decodes limits[] generically
    Poller.swift             scheduling, backoff, sleep/wake, 30s floor
    RedactingLogger.swift
  RationUI/           ← SwiftUI views + view models
    StatusItemModel.swift    snapshot + display mode → menu bar title & tint
    LimitRingView.swift      Gauge(.accessoryCircularCapacity) hero ring
    LimitRowView.swift       secondary bars + countdown
    PopoverView.swift
    SettingsView.swift
    OnboardingView.swift     explains the Keychain prompt BEFORE triggering it
    Notifier.swift           UNUserNotificationCenter thresholds
  Ration/
    RationApp.swift          @main, ~40 lines of wiring
```

### Data flow

`Poller` tick → `CredentialStore.token()` → `LimitsClient.fetch()` → `UsageSnapshot` published on `@MainActor` → `StatusItemModel` derives the menu bar string → `PopoverView` renders `limits[]`.

Both `CredentialStore` and `LimitsClient` are protocols. Tests inject fakes plus checked-in fixture JSON — no network, no Keychain in CI.

### Polling

- 60s closed, 10s while the popover is open, configurable 30s–5m with a **hardcoded 30s floor** (be a good API citizen; document why).
- Pause on `NSWorkspace.willSleepNotification`, immediate refresh on `didWakeNotification`.
- Exponential backoff to 5 min on network failure.
- `401` → halt, show sign-in state, retry every 5 min.

### The Keychain prompt

First launch shows an onboarding panel explaining, in plain language, that macOS is about to ask permission to read the token Claude Code already stored, that Ration only reads it, and that clicking **Always Allow** is a one-time grant. README carries a screenshot. Never trigger the prompt cold. Do **not** shell out to `/usr/bin/security` to dodge it — an explicit user-consented grant is the correct posture for this app.

## Apple-style specifics

This is the "cope it out Apple style" requirement, made concrete:

- `MenuBarExtra(style: .window)` — a real SwiftUI panel like Control Center, not an `NSMenu`.
- Hero ring is a literal `Gauge(value:)` with `.gaugeStyle(.accessoryCircularCapacity)`.
- SF Symbols only — `gauge.with.dots.needle.33percent` family.
- `.regularMaterial` panel background, `.ultraThinMaterial` cards.
- Semantic colors only (`.primary`, `.secondary`, `Color.accentColor`) → light/dark/increase-contrast work for free. Severity tints: `normal` → `.secondary`, `warning` → `.orange`, `critical` → `.red`, mapped from the API's `severity`, never from our own thresholds.
- Percentages animate with `.contentTransition(.numericText())` — the Apple rolling-digit effect.
- Menu bar title rendered with **monospaced digits** so the item does not jitter as numbers change.
- `LSUIElement = true` (no Dock icon). Popover ~320pt wide.
- Respects Reduce Motion, Increase Contrast, Dynamic Type. Strings in a String Catalog from day one.
- Severity coloring is a setting, **off by default** — plenty of people want a monochrome menu bar.

## Build & repo layout

Plain-text repo, **no `.xcodeproj`** — SwiftPM plus a bundle script. Keeps everything reviewable, kills project-file merge conflicts, makes CI trivial.

```
Ration/
  Package.swift
  Sources/{RationKit,RationUI,Ration}/…
  Tests/RationKitTests/{Fixtures/*.json, …}
  Scripts/{bundle.sh, sign.sh, notarize.sh}     # assemble .app, Info.plist w/ LSUIElement, codesign, notarize
  .github/workflows/{ci.yml, release.yml}
  README.md CONTRIBUTING.md SECURITY.md PRIVACY.md LICENSE(MIT)
  docs/superpowers/specs/2026-08-06-ration-design.md
```

`README.md` must carry a clear **"Not affiliated with or endorsed by Anthropic"** disclaimer, plus the Keychain-prompt screenshot and the security posture summary.

Homebrew: create tap repo `mcpeixoto/homebrew-tap` → `brew install --cask mcpeixoto/tap/ration`. Cask submission to homebrew-cask core requires a 30-day-old repo and traction, so the tap comes first. Notarization uses the existing Apple Developer account.

## Implementation order

1. `Package.swift` + three targets + `Scripts/bundle.sh` producing a launchable `.app`. Verify an empty `MenuBarExtra` appears in the menu bar.
2. `UsageSnapshot` models + fixture-driven decode tests. **Write tests first** — fixtures are already captured in the Context section above, including the null-heavy feature-flagged keys.
3. `CredentialStore` + `LimitsClient` behind protocols; fake impls for tests.
4. `Poller` with backoff/sleep/wake; tests use an injected clock.
5. `StatusItemModel` + display-mode formatting; snapshot tests on the title string.
6. `PopoverView` / ring / rows / countdowns.
7. Onboarding, Settings, launch-at-login (`SMAppService`), notifications.
8. CI workflow, then signing + notarization + release workflow, then the tap.

## Verification

- `swift test` — decode tests against the checked-in fixtures (including a fixture with unknown future `kind` values, to prove `limits[]` degrades gracefully); aggregation and countdown formatting; the "only api.anthropic.com" source-scan test; a test asserting the refresh token is never read.
- `./Scripts/bundle.sh && open .build/Ration.app` — icon appears, popover opens, real numbers match `/usage` inside Claude Code.
- Manual: toggle each display mode; cross a threshold with a stubbed snapshot and confirm the notification; quit/relaunch with launch-at-login on; sleep the Mac and confirm it refreshes on wake; revoke Keychain access in Keychain Access.app and confirm the sign-in state appears instead of a crash.
- Confirm light mode, dark mode, and Increase Contrast all render legibly.

## Explicitly out of scope for v1

Local transcript parsing, cost estimation, per-model and per-project breakdowns, burn rate, sparklines. All v2. The `RationKit` boundary is drawn so v2 adds a `TranscriptStore` + `Aggregator` alongside `LimitsClient` without reworking anything in v1.
