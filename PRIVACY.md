# Privacy

Ration collects nothing.

## What leaves your machine

One request when Ration refreshes Claude's limits, and one when it refreshes
Cursor's:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <your Claude Code access token>
```

```
POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage
Authorization: Bearer <your Cursor access token>
```

Each token is sent only to the host that issued it. Codex makes no request at
all: Codex CLI records its own rate limits into the session files it writes, so
Ration reads the gauge from disk.

Ration also checks for its own updates:

```
GET https://raw.githubusercontent.com/mcpeixoto/ration/main/appcast.xml
```

and, if you install an update, downloads it from `github.com`. **Neither
request carries your token, your usage numbers, or any identifier.** They are
ordinary anonymous file fetches — GitHub sees an IP address and a user agent,
the same as visiting the repository in a browser. Turn automatic checks off in
Settings and Ration never contacts GitHub at all.

The app also contains a "buy me a coffee" link and a "Post on X" compose link.
Each is a link — clicking it opens your browser. Ration never contacts those
hosts itself, and not clicking them means no request is ever made. The X path
copies a card image to the pasteboard first; it does not upload the image.

There is no analytics endpoint, no crash reporter, and no telemetry of any
kind. This is enforced by tests: one fails the build if an unexpected host
appears in the source tree, one fails if networking appears outside the client
files, and one pins the update feed so it cannot be redirected without the
change showing up in a diff.

## What Ration reads

From the macOS keychain item `Claude Code-credentials`, created by Claude Code:

| Field | Read? | Used for |
| --- | --- | --- |
| `claudeAiOauth.accessToken` | Yes | Authorising the usage request |
| `claudeAiOauth.expiresAt` | Yes | Avoiding a request we know will fail |
| `claudeAiOauth.subscriptionType` | Yes | The plan badge in the panel |
| `claudeAiOauth.rateLimitTier` | Yes | Display only |
| `claudeAiOauth.refreshToken` | **No** | — |
| `mcpOAuth.*` (MCP server logins) | **No** | — |

This is the only keychain item Ration reads, and a test fails the build if
keychain calls appear anywhere but the one file that makes them.

**Codex's credentials are not read at all.** Codex stores its login in a
plain file in your home directory — no keychain, no prompt, nothing standing in
the way. Ration never opens it. It does not need to: the plan tier it displays
comes from the session log along with everything else.

**Cursor's session is read, read-only.** The Cursor app stores an access token
in a local sqlite file. Ration copies that file, reads the access token and the
cached plan name, and sends the token only to `api2.cursor.sh`. It never reads
a refresh secret and never opens the browser cookie jar. A test fails the build
if any source file names that cookie jar, Codex's credential file, or Gemini's
credential file.

Ration never reads your conversations, prompts, files, or project history.

## What Ration reads from your transcripts

Both supported tools write every session to disk — Claude Code to
`~/.claude/projects/**/*.jsonl`, Codex CLI to
`~/.codex/sessions/**/rollout-*.jsonl` (and its `archived_sessions` sibling).
Those files contain your prompts, the replies, and the contents of files you
opened.

Ration reads a handful of fields per turn and discards the rest.

From Claude Code:

| Field | Used for |
| --- | --- |
| `message.usage.*` | Token counts |
| `message.model` | Grouping by model |
| `timestamp` | Grouping by day |
| `cwd` | Grouping by project (the directory name only) |
| `sessionId` | Counting distinct sessions |

From Codex, two line types out of six:

| Field | Used for |
| --- | --- |
| `token_count` → `info.total_token_usage.*` | Token counts |
| `token_count` → `rate_limits.*` | The plan gauge and reset times |
| `turn_context.model` | Grouping by model |
| `turn_context.cwd` | Grouping by project (the directory name only) |
| `timestamp` | Grouping by day |

Codex's session id comes from the *file name*, specifically so that the first
line of each rollout — the one carrying the multi-kilobyte instruction blob —
never has to be handed to the JSON decoder at all.

**Message content is never decoded.** `TranscriptParserPrivacyTests` and
`CodexParserPrivacyTests` each assert this by putting marker strings in a
fixture transcript and failing if any appears anywhere in the parsed result. A
further test pins the exact set of fields a parsed event may carry — identical
for both tools — so adding one is a deliberate act that breaks the build rather
than a quiet expansion.

None of it leaves your machine. The history is aggregated per day and stored
locally (below); the raw transcripts are only ever read.

## What Ration stores

On disk, in `UserDefaults` (`com.mcpeixoto.Ration`):

- Your chosen menu bar display mode
- Whether icon colouring is on
- Your chosen refresh interval
- Whether notifications are on
- Whether you have completed the welcome screen
- Which tool the panel opens on

And a local history cache per tool, in
`~/Library/Application Support/Ration/history-<tool>.json`: per-day token totals
by model and project, session counts, and the byte offset reached in each
transcript file. No message content — only the numbers described above. Delete
the files to reset; Ration rebuilds them on the next launch.

Upgrading from 0.1.0 renames the old `history.json` to `history-claude.json`,
which is what it always was. Nothing is re-read and nothing is lost.

That is the complete list. Your access token is held in memory for the duration
of a request and is never written to disk, to `UserDefaults`, or to a log. The
`Credential` type redacts itself when printed, so it cannot leak through a log
line or a crash report.

## What Ration writes

Nothing to your keychain. Ration calls `SecItemCopyMatching` and no other
keychain API — there is no code path that adds, updates, or deletes a keychain
item.

## Questions

Open an issue: https://github.com/mcpeixoto/ration/issues
