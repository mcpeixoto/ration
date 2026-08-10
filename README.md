# Ration

Your AI coding usage, in the macOS menu bar.

Ration puts a small gauge in your menu bar showing how much of your plan you
have used — for **Claude Code** and **Codex**. No more discovering you hit a
limit halfway through a long agent run.

<p align="center">
  <img src="docs/images/demo.gif" width="320" alt="Ration cycling through its three tabs">
</p>

<p align="center">
  <img src="docs/images/popover-dark.png" width="260" alt="Live plan limits">
  <img src="docs/images/activity-dark.png" width="260" alt="Calendar heat map of past activity">
  <img src="docs/images/trends-dark.png" width="260" alt="Daily usage trends">
</p>

The menu bar item carries a small vertical gauge for the weekly allowance — the limit that
creeps up on you, since a session window resets often enough to watch itself.
It stays monochrome while everything is fine, turns amber past 80% and red past
90% — so colour in your menu bar always means something.

Four tabs:

- **Usage** — live plan limits, and a projection of the current window: *at
  this rate, do you run out before it resets?* Click any limit to promote it
  into the ring; the projection follows.
- **Activity** — a calendar heat map of the last five months, plus streaks and
  which hours of the day you actually work.
- **Trends** — totals and daily charts over 7/30/90 days, across
  tokens, messages, sessions, or estimated cost, with a 7-day trend line.
- **Detail** — where the tokens went, by model and by project.

- **Native.** SwiftUI `MenuBarExtra`, about 5 MB, no Electron and no runtime to install.
- **Live.** Reads the same numbers `/usage` shows inside Claude Code, refreshed in the background.
- **Quiet.** Optional notifications when you approach a limit, and nothing else.
- **Private.** No analytics, no telemetry. Two hosts, both listed below, and nothing else — **adding Codex added no third one.**
- **Self-updating.** Signed updates via Sparkle; nothing to re-download by hand.

> Ration is an independent open-source project. It is **not affiliated with,
> endorsed by, or supported by Anthropic or OpenAI**. "Claude" is a trademark of
> Anthropic; "Codex" is a trademark of OpenAI.

## Supported tools

| Tool | Plan gauge | History | How |
|---|---|---|---|
| **Claude Code** | yes | yes | one request to `api.anthropic.com`, using the token Claude Code already stored |
| **Codex CLI** | yes | yes | entirely from `~/.codex/sessions` — no request, no credential |
| Cursor | no | no | its usage lives behind a login on its website; Ration will not read your browser cookies |
| GitHub Copilot | no | no | quota is only readable over the network, with a token Ration would have to mint and store itself |
| Gemini CLI | no | no | quota is only readable over the network; nothing usable is written to disk |

The last three are listed in **Settings → Tools** with that explanation, rather
than quietly omitted. If one of them starts writing its usage to disk, it
becomes a twenty-line adapter — the seam is already there.

Codex is the interesting case: it stamps its own rate limits into every session
log it writes, so Ration reads the gauge and the history out of the same files.
That is why a second provider cost zero new network hosts. The trade is
freshness — those numbers age while Codex is not running, so the panel says how
old they are instead of presenting them as live.

## Install

[**Download Ration 0.2.0**](https://github.com/mcpeixoto/ration/releases/latest/download/Ration-0.2.0.dmg)
— open the DMG and drag `Ration.app` to Applications.

Signed with a Developer ID and notarised by Apple, so it opens without a
Gatekeeper warning. It updates itself from then on.

A Homebrew cask is coming; the formula in `Casks/` is ready but the tap is not
published yet.

### Requirements

- macOS 14 (Sonoma) or later
- At least one supported tool: [Claude Code](https://claude.com/claude-code)
  signed in, or Codex CLI with at least one session

Ration does not sign you in and has no account of its own. It reads what your
tools already have.

## How it works

**Live limits (the Usage tab).**

1. Claude Code stores your login session in the macOS keychain under
   `Claude Code-credentials`.
2. Ration reads the **access token** from that item — nothing else.
3. It calls `GET https://api.anthropic.com/api/oauth/usage` with that token,
   which is the same endpoint `/usage` uses inside Claude Code.
4. It draws the resulting percentages in your menu bar.

**Codex, entirely from disk.** Codex CLI writes its sessions to
`~/.codex/sessions/**/rollout-*.jsonl`, and stamps its *own rate limits* into
every `token_count` record it writes — the percentage used, the window length,
and when it resets. So Ration reads the Codex gauge and the Codex history out of
the same files, with no request and no credential. It never opens Codex's
credential store; it does not need to, because even the plan tier is in the
session log. A test fails the build if any source file so much as names those
files.

The trade is freshness: a figure Codex wrote three hours ago is three hours old.
Ration timestamps the snapshot from the record rather than from the read, so the
panel says *"As of 3h ago"* instead of showing a stale number as live.

**History (the Activity, Trends and Detail tabs).** Both tools write a
transcript of every session — Claude Code to `~/.claude/projects/**/*.jsonl`,
Codex to `~/.codex/sessions/**/rollout-*.jsonl`. Ration reads the token counts
out of those files, and only the token counts. Your prompts, the replies, and
the contents of files you opened are never decoded, never retained, and never
leave your machine. The first scan reads the whole corpus in the background (a
few seconds for a gigabyte); after that it reads only the bytes appended since
the last check.

Each tool gets its own history, and the panel shows one at a time. Merging them
would produce a confidently wrong number: a Claude token and a Codex token are
not the same unit, and adding them up implies they are.

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
- Send your token to exactly one host, `api.anthropic.com`, and keep it in
  memory only for that request.
- Check `raw.githubusercontent.com` for an update feed, and download releases
  from `github.com` when you install one. **Your token is never sent there** —
  update checks carry no credentials and no usage data.

**It does not:**

- Read your refresh token, your MCP server logins, or anything else in that
  keychain blob.
- Touch any other tool's credentials. Codex keeps its login in a plain file that
  Ration could read; it never does, and a test fails the build if a source file
  even mentions it.
- Read your prompts, the replies, or file contents out of your transcripts —
  only token counts, model, timestamp, project, and session id.
- Write to your keychain, ever.
- Refresh, rotate, or invalidate your session. Only Claude Code does that. If
  your session expires, Ration says so and waits.
- Write the token to disk, to `UserDefaults`, or to a log.
- Send analytics, telemetry, or crash reports anywhere.
- Read your prompts, your conversations, or your code.

## Updates

Ration checks for updates once a day and can install them itself. Each update
is signed with an EdDSA key; the matching public key is compiled into the app,
and an update that isn't signed by the Ration key is refused — so a compromised
download host still can't ship you a modified Ration.

Turn automatic checks off in Settings if you'd rather update by hand.

## What Ration does and does not do (continued)

These are enforced by tests, not just promised in a README — see
[`Tests/RationKitTests/CredentialTests.swift`](Tests/RationKitTests/CredentialTests.swift),
which fails the build if a second network host appears in the source tree, if
networking leaks outside `LimitsClient.swift`, if the keychain is touched outside
`Credential.swift`, if anything reads a refresh token, or if any source file
names another tool's credential file.

Those assertions did not have to be loosened to add Codex — the host allow-list
is character-for-character what it was in 0.1.0. That is the point of reading a
provider from disk: the second tool arrived with no new attack surface at all.

More detail in [SECURITY.md](SECURITY.md) and [PRIVACY.md](PRIVACY.md).

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Menu bar shows | Session % | Session, Weekly, Highest, or icon only |
| Weekly usage bar | On | A small vertical gauge beside the icon, filling as the week is spent |
| Colour when near a limit | On | Amber past 80%, red past 90% |
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
swift test          # 235 tests, no network, no keychain
./Scripts/bundle.sh # produces .build/Ration.app
open .build/Ration.app
```

To install your own build into `/Applications` instead of running it out of
`.build`:

```sh
./Scripts/install.sh                      # builds, installs, launches
DEVELOPER_ID="Developer ID Application: You (TEAMID)" \
  ./Scripts/install.sh                    # ...and signs it on the way
```

It quits any running copy first, since a bundle cannot be replaced while it is
executing. Notarisation is not part of this path and does not need to be: a
locally built app never crosses a quarantine boundary, so Gatekeeper never asks
about it. The DMG in Releases is the notarised one.

Two helper scripts round out the workflow:

```sh
swift Scripts/make-icon.swift             # regenerates Resources/AppIcon.icns
swift run RationPreview docs/images       # regenerates the screenshots above
swift run RationPreview video && \
  ./Scripts/make-video.sh                 # regenerates the demo video and GIF
```

The icon is drawn in code, and the screenshots and demo video are rendered
frame by frame from the real SwiftUI views — the motion in the GIF above is the
app, not a mockup. Nothing here is a binary blob that drifts silently out of
date.

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

- Burn rate and a live sparkline of the current session
- Export history as CSV
- A wider window than 90 days in Metrics

## Contributing

Issues and pull requests welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

If Anthropic would prefer this not exist in its current form, please open an
issue; I will work with you.

## Support

Ration is free and always will be. If it saved you from one mid-task limit
wall, you can [buy me a coffee](https://buymeacoffee.com/mcpeixoto) — entirely
optional, and it changes nothing about the app.

## Licence

[MIT](LICENSE).
