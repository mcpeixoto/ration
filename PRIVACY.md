# Privacy

Ration collects nothing.

## What leaves your machine

One request, when Ration refreshes:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <your Claude Code access token>
anthropic-beta: oauth-2025-04-20
User-Agent: Ration/<version> (github.com/mcpeixoto/ration)
```

That is the only network request Ration makes, and `api.anthropic.com` is the
only host it contacts. There is no analytics endpoint, no crash reporter, no
update checker, and no telemetry of any kind.

This is enforced by a test that fails the build if a second host appears
anywhere in the source tree, and by another that fails if any networking code
appears outside `Sources/RationKit/LimitsClient.swift`.

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

Ration never reads your conversations, prompts, files, or project history.

## What Ration stores

On disk, in `UserDefaults` (`com.mcpeixoto.Ration`):

- Your chosen menu bar display mode
- Whether icon colouring is on
- Your chosen refresh interval
- Whether notifications are on
- Whether you have completed the welcome screen

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
