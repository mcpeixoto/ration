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

### 3b. No other tool's credentials, except the one Cursor already stored

Ration reads two credentials, both of which the underlying tool already wrote:

- Claude Code's access token, from the keychain item it created.
- Cursor's access token, from the sqlite file the Cursor app created.

It never writes either. It never reads a refresh secret. It never opens Codex's
credential file, Cursor's cookie jar, or Gemini's credential file.

`credentialsOfOtherToolsAreNeverTouched` fails the build if any file under
`Sources/` so much as *names* Codex's credential file, Cursor's cookie jar, or
Gemini's credential file. The list of forbidden strings deliberately includes
the file names themselves: a comment explaining that we do not read something
is still a reference to it, and this guarantee is the kind that erodes one
convenience at a time.

`keychainAccessIsConfinedToOneFile` fails if keychain calls appear anywhere but
`Credential.swift`, so a second provider cannot quietly introduce a second
permission prompt. Cursor's token is not in the keychain, which is why adding
it did not add a prompt.

### 4. Two credentialed hosts

Claude's token goes to `api.anthropic.com`. Cursor's token goes to
`api2.cursor.sh`. Each token is sent only to the host that issued it.

Codex added no host: it is read from disk. Cursor could not be, so this file
and the host-allow tests changed in the same commit that added it.

`noUnexpectedHosts` fails if any host other than those two (or the project's
own GitHub links, which are user-clickable) appears under `Sources/`.
`networkingIsConfinedToTheClient` fails if `URLSession`, `URLRequest`,
`NSURLConnection`, or `CFSocket` appears in any file other than
`LimitsClient.swift` and `CursorClient.swift`.
`clientHasOneEndpoint` fails if `LimitsClient.swift` constructs any URL other
than `https://api.anthropic.com/api/oauth/usage`.
`cursorClientHasKnownEndpoints` fails if `CursorClient.swift` constructs any
URL other than its two dashboard endpoints.

Ration does contact a second host — `raw.githubusercontent.com` for the update
feed, and `github.com` to download a release you chose to install. Those
requests come from Sparkle, carry no credentials, no usage data, and no
identifier, and stop entirely if you turn off automatic checks.
`updateFeedIsTheExpectedHost` pins the feed URL so it cannot be repointed
without the change appearing in a diff.

### 4b. Updates are signed, and the signature is checked

Every update is signed with an EdDSA key. The matching public key is compiled
into the app bundle (`SUPublicEDKey`), and Sparkle refuses any update whose
signature does not verify against it.

This means the download host is **not** trusted: an attacker who compromised
GitHub Releases, or who intercepted the download, still could not make Ration
install a modified build. The private key lives only in the maintainer's
keychain and in one GitHub Actions secret — never in this repository.

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

# The whole security surface:
wc -l Sources/RationKit/Credential.swift \
      Sources/RationKit/LimitsClient.swift \
      Sources/RationKit/Cursor/*.swift

# Confirm what the shipped binary can reach:
strings /Applications/Ration.app/Contents/MacOS/Ration | grep -E 'https?://'
```

### 7. Transcripts are read for numbers, not content

The Activity, Trends and Detail tabs are built from local transcripts, which
contain your prompts, the replies, and file contents. The parsers decode token
counts, model, timestamp, working directory and session id — and nothing else.
Each tool has its own parser and its own privacy suite, and all produce the
same narrow event type, pinned by a test that reflects over its properties.

Codex's parser never decodes the first line of a rollout at all — the line
carrying its instruction blob — because the session id it would have taken from
there is available in the file name instead. Cursor's parser does the same with
the JSONL file name, and never copies bubble text out of sqlite.

Enforced by `TranscriptParserPrivacyTests`, `CodexParserPrivacyTests` and
`CursorParserPrivacyTests`: one test plants a marker string in a fixture
transcript and fails if it survives into the parsed result; another pins the
exact field set a parsed event may expose, so widening it breaks the build.
Transcripts are read, never written.

## Sandboxing

Ration is not App Sandboxed: reading session transcripts from `~/.claude/projects`,
`~/.codex/sessions` and `~/.cursor/projects` requires filesystem access the
sandbox would block.
Releases are signed with a Developer ID, use the hardened runtime, and are
notarised by Apple.

## Scope

Ration is a read-only viewer. It cannot spend your quota, change your plan,
modify your account, or alter anything in the tools it reads. It opens their
files for reading and never writes to them.
