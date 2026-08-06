# Ration

Your Claude usage, in the macOS menu bar.

Ration puts a small gauge in your menu bar showing how much of your Claude plan
you have used. No more discovering you hit a limit halfway through a long agent
run.

<p align="center">
  <img src="docs/images/popover-dark.png" width="320" alt="Ration's panel in dark mode">
  <img src="docs/images/popover-light.png" width="320" alt="Ration's panel in light mode">
</p>

- **Native.** SwiftUI `MenuBarExtra`, about 5 MB, no Electron and no runtime to install.
- **Live.** Reads the same numbers `/usage` shows inside Claude Code, refreshed in the background.
- **Quiet.** Optional notifications when you approach a limit, and nothing else.
- **Private.** No analytics, no telemetry, nothing written to disk.

Click any limit to promote it into the ring.

> Ration is an independent open-source project. It is **not affiliated with,
> endorsed by, or supported by Anthropic**. "Claude" is a trademark of Anthropic.

## Install

```sh
brew install --cask mcpeixoto/tap/ration
```

Or [download the latest release](https://github.com/mcpeixoto/ration/releases/latest),
unzip, and drag `Ration.app` to your Applications folder.

### Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://claude.com/claude-code), signed in

Ration does not sign you in and has no account of its own. It reads the session
Claude Code already has.

## How it works

1. Claude Code stores your login session in the macOS keychain under
   `Claude Code-credentials`.
2. Ration reads the **access token** from that item — nothing else.
3. It calls `GET https://api.anthropic.com/api/oauth/usage` with that token,
   which is the same endpoint `/usage` uses inside Claude Code.
4. It draws the resulting percentages in your menu bar.

That is the whole program.

### The keychain prompt

The first time Ration runs, macOS will ask whether it may read the
`Claude Code-credentials` keychain item:

> **Ration wants to use your confidential information stored in
> "Claude Code-credentials" in your keychain.**

This is expected. The keychain item was created by Claude Code, so its access
list does not include Ration until you say so. Click **Always Allow** and macOS
will not ask again.

Ration explains this in its welcome screen *before* triggering the prompt,
because an unexplained dialog asking about your credentials is exactly the sort
of thing you should be suspicious of.

If you would rather not grant it, close the welcome window. Ration will sit
idle and read nothing.

## What Ration does and does not do

**It does:**

- Read one keychain item, read-only.
- Make one kind of network request, to `api.anthropic.com`.
- Keep the token in memory for the duration of that request.

**It does not:**

- Read your refresh token, your MCP server logins, or anything else in that
  keychain blob.
- Write to your keychain, ever.
- Refresh, rotate, or invalidate your session. Only Claude Code does that. If
  your session expires, Ration says so and waits.
- Write the token to disk, to `UserDefaults`, or to a log.
- Send analytics, telemetry, or crash reports anywhere.
- Read your prompts, your conversations, or your code.

These are enforced by tests, not just promised in a README — see
[`Tests/RationKitTests/CredentialTests.swift`](Tests/RationKitTests/CredentialTests.swift),
which fails the build if a second network host appears in the source tree, if
networking leaks outside `LimitsClient.swift`, or if anything reads the refresh
token.

More detail in [SECURITY.md](SECURITY.md) and [PRIVACY.md](PRIVACY.md).

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Menu bar shows | Session % | Session, Weekly, Highest, or icon only |
| Colour when near a limit | Off | Amber approaching, red at the limit |
| Check every | 60s | 30s minimum; faster while the panel is open |
| Notify near a limit | On | Fires once per threshold per window |
| Open at login | Off | Standard `SMAppService` login item |

### Why the 30-second floor

`/api/oauth/usage` is an undocumented convenience endpoint for your own
account. Ration will not poll it faster than every 30 seconds, and that floor is
enforced in code rather than left to configuration. Hammering it would risk it
being locked down for everyone.

## Building from source

```sh
git clone https://github.com/mcpeixoto/ration.git
cd ration
swift test          # 120 tests, no network, no keychain
./Scripts/bundle.sh # produces .build/Ration.app
open .build/Ration.app
```

Two helper scripts round out the workflow:

```sh
swift Scripts/make-icon.swift        # regenerates Resources/AppIcon.icns
swift run RationPreview docs/images  # regenerates the screenshots above
```

The icon is drawn in code and the screenshots are rendered from the real views,
so neither is a binary blob that drifts silently out of date.

Requires Xcode 16 or later. There is no `.xcodeproj` — the whole repo is plain
text, and `Scripts/bundle.sh` assembles the `.app` around the SwiftPM binary.

### Layout

```
Sources/RationKit     Pure logic: models, keychain, API client, polling. No UI.
Sources/RationUI      SwiftUI views and view models.
Sources/Ration        The executable. Wiring and AppKit lifecycle only.
Sources/RationPreview Dev tool: renders the UI to PNGs. Not shipped.
Tests/RationKitTests  Unit tests with checked-in API fixtures.
```

`RationKit` imports no UI framework, so every decision Ration makes — what to
show, when to notify, when to back off — is testable without launching an app.

## Roadmap

v1 is the live limits API, which is what this is. Planned for v2:

- Local analytics from `~/.claude/projects/**/*.jsonl`: tokens by model, by
  project, and over time
- Cost estimates
- Burn rate and a sparkline of the current session
- History beyond the current window

## Contributing

Issues and pull requests welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

If Anthropic would prefer this not exist in its current form, please open an
issue; I will work with you.

## Licence

[MIT](LICENSE).
