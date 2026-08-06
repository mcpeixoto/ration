# Security

Ration reads a live authentication token, so it deserves scrutiny. This
document describes the design constraints that make that reasonable, and how to
verify them yourself.

## Reporting a vulnerability

Open a [security advisory](https://github.com/mcpeixoto/ration/security/advisories/new),
or email the address on the maintainer's GitHub profile. Please do not open a
public issue for a vulnerability.

## Design constraints

These are not aspirations. Each is enforced by a test that fails the build.

### 1. Read the keychain, never write it

`KeychainCredentialStore` calls `SecItemCopyMatching` and nothing else. There is
no `SecItemAdd`, `SecItemUpdate`, or `SecItemDelete` anywhere in the codebase.
Ration cannot corrupt or delete your Claude Code login.

### 2. Read one secret, not the whole blob

The keychain item contains an access token, a refresh token, and every MCP
server login you have authorised. Ration parses only
`claudeAiOauth.accessToken` and three display-only metadata fields.

Verified by `refreshTokenIsNeverRead` and `mcpTokensAreNeverRead`, which reflect
over every stored property of the parsed credential and assert none contains the
other secrets. A further test fails if the string `refreshToken` appears
anywhere under `Sources/`.

### 3. Never refresh, never rotate

Ration has no code to exchange a refresh token or mint a new session. When the
token expires it stops polling and shows a "signed out" state until Claude Code
refreshes it. **Ration cannot invalidate your session or lock you out.**

### 4. One host, one endpoint

`noUnexpectedHosts` fails if any host other than `api.anthropic.com` (or the
project's own GitHub links, which are user-clickable and never requested by the
app) appears under `Sources/`.

`networkingIsConfinedToTheClient` fails if `URLSession`, `URLRequest`,
`NSURLConnection`, or `CFSocket` appears in any file other than
`LimitsClient.swift`.

`clientHasOneEndpoint` fails if `LimitsClient.swift` constructs any URL other
than `https://api.anthropic.com/api/oauth/usage`.

### 5. The token never lands anywhere

Held in memory for the duration of a request. Never written to disk, to
`UserDefaults`, or to a log. `Credential` implements
`CustomStringConvertible` and `CustomDebugStringConvertible` to render as
`Credential(token: <redacted>, plan: max)`, so it cannot leak through string
interpolation, `dump`, or a crash report. Verified by `descriptionIsRedacted`.

### 6. Consent before access

The first keychain read triggers a macOS permission prompt. Ration shows a
welcome screen explaining what is about to happen, and why, before triggering
it. Closing that window without agreeing means Ration reads nothing at all.

Ration deliberately does **not** shell out to `/usr/bin/security`, which would
inherit that binary's existing keychain grant and bypass the prompt entirely.
An explicit, user-granted keychain ACL entry is the correct posture, even though
it costs one dialog.

## Verify it yourself

```sh
git clone https://github.com/mcpeixoto/ration.git
cd ration
swift test

# The whole security surface is two files:
wc -l Sources/RationKit/Credential.swift Sources/RationKit/LimitsClient.swift

# Confirm what the shipped binary can reach:
strings /Applications/Ration.app/Contents/MacOS/Ration | grep -E 'https?://'
```

### 7. Transcripts are read for numbers, not content

The Activity and Metrics tabs are built from Claude Code's local transcripts,
which contain your prompts, Claude's replies, and file contents. The parser
decodes five fields per turn — token counts, model, timestamp, working
directory, session id — and nothing else.

Enforced by `TranscriptParserPrivacyTests`: one test plants a marker string in a
fixture transcript and fails if it survives into the parsed result; another pins
the exact field set a parsed event may expose, so widening it breaks the build.
Transcripts are read, never written.

## Sandboxing

Ration is not App Sandboxed: reading Claude Code's transcripts from
`~/.claude/projects` requires filesystem access the sandbox would block.
Releases are signed with a Developer ID, use the hardened runtime, and are
notarised by Apple.

## Scope

Ration is a read-only viewer. It cannot spend your quota, change your plan,
modify your account, or alter anything in Claude Code.
