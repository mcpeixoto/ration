# Accounts tab

**Date:** 2026-08-10
**Status:** approved, ready for planning

## Summary

Replace Settings → **Tools** with Settings → **Accounts**: one tab that shows
which account each supported tool is signed in as, and lets the user turn any
of them off. Turning one off hides it everywhere *and* stops Ration reading it.

## Why

Today the Tools tab is read-only. It answers "what does Ration know about?" but
not "stop looking at this one." A user with Codex installed but unused, or who
wants Ration to leave their Claude session alone for a while, has no control
short of quitting the app.

## What this is not

This is a visibility and status tab, **not** multi-account support.

Ration cannot show two Claude accounts at once, and this design does not try
to. Claude Code stores exactly one credential blob in the keychain under
`Claude Code-credentials`, and that blob carries no email and no account id —
only `subscriptionType` and `rateLimitTier`. Codex stores one account in
`~/.codex/auth.json`. Watching a second account of either tool would require
Ration to obtain and store credentials of its own, which reverses the
read-only-by-construction guarantee in `SECURITY.md` and the promises in
`PRIVACY.md`.

Two existing guarantee tests encode that boundary and must stay green:

- *"only the Anthropic credential store touches the keychain"*
- *"no source file reads another tool's credential store"*

In particular, `~/.codex/auth.json` stays unread. It holds access and refresh
tokens, and the only thing it would buy is a display email.

## Design

### 1. Where the on/off state lives

`ProviderRegistry` gains `disabled: Set<Provider.ID>`. This mirrors how
`primary` already works: the registry holds the live value, and the app layer
persists it (`RationApp.swift:34` and `:62`).

`Settings` gains a matching `disabledProviders: Set<String>` behind one new
`UserDefaults` key, `disabledProviders`. `RationApp` syncs it into the registry
on launch and on change, exactly as it does for `primaryProvider`.

**Store *disabled*, not *enabled*.** An empty set is then the correct
fresh-install state, and a provider added in a later release is on by default.
Storing the enabled set instead would silently hide every new provider from
every existing user.

Unknown ids read back from defaults are ignored rather than treated as errors,
so downgrading after a release that adds a provider does not corrupt the set.

### 2. What hiding does

`ProviderRegistry.visible` becomes `installed && !disabled`. `metered` already
derives from `visible`, and `start`, `resume` and `setMenuOpen` already iterate
`metered` — so a hidden provider stops being polled without editing any of
those methods.

One new method, `setEnabled(_:for:)`, flips the set and then suspends a poller
that was just disabled, or starts one that was just enabled. Without it the
toggle would only take effect at next launch.

For Claude, "not polled" must mean no request to `api.anthropic.com` and no
keychain read. The `CachingCredentialStore` holds a token in memory between
polls, so disabling also drops that cached copy. Otherwise "hidden and not
read" would be only half true for as long as the app stays running. This needs
a way to ask a `UsageSource` to forget what it is holding: a protocol method
defaulting to a no-op, implemented by the Anthropic source to invalidate its
credential cache.

### 3. Hiding the provider that owns the menu bar

No new logic. `primary`'s existing `didSet` falls back when the selected
provider is no longer available, so hiding the menu bar's account promotes the
next one automatically.

**Amended during review:** the fallback resolves against `metered`, not
`visible`. §5 keeps Cursor, Copilot and Gemini listed and visible with no
toggle, so on any Mac with one of them installed `visible` is never empty —
§4 would be unreachable, and the menu bar would promote a tool that has no
gauge to show and sit on "Loading usage…" forever. The Accounts tab and the
panel's switcher still resolve `visible` independently, so those tools stay
listed exactly as described. §4's discriminator follows: it lives on the
registry as `isEverythingHidden` and asks whether any *meterable* provider is
installed, rather than any installed provider at all.

### 4. Hiding every account

Allowed, and it means Ration goes quiet: icon only, no gauge, no polling, no
network.

This needs a new `MenuBarPresentation` case, distinct from the existing
`.setupRequired`. "You have hidden everything" and "no supported tool was
found" are different sentences and need different recovery: the first points at
this tab, the second at installing a tool.

`RationApp.presentation` (currently `RationApp.swift:71`, which returns
`.setupRequired` whenever `primaryEntry` is nil) chooses between the two by
asking whether any installed provider exists at all.

The panel shows a short line saying everything is hidden, with a button that
opens Settings → Accounts.

### 5. The tab

`ProvidersSettingsView` becomes `AccountsSettingsView`; the tab label becomes
"Accounts". Three sections:

1. **Menu bar** — the existing primary-provider picker, unchanged, now listing
   only providers that are both meterable and enabled.
2. **Accounts** — one row per meterable provider (Claude, Codex): display name,
   plan name from `UsagePoller.planName`, the current window's percentage, and
   a `Toggle`. Each row states what Ration reads for that provider — the Claude
   Code keychain session for one, session files on disk for the other.
3. **Not metered** — Cursor, Copilot and Gemini, greyed, carrying today's
   explanations from `ProviderAvailability`, with no toggle. Keeps the "where is
   Cursor?" answer where users already find it.

A provider reporting `notInstalled` gets no toggle either; there is nothing to
turn off.

No email is displayed anywhere, and no new file is read.

### 6. Testing

New:

- Registry: hiding a provider removes it from `visible` and `metered`; hiding
  the primary promotes the next; hiding all leaves `primaryEntry == nil`;
  re-enabling restores it.
- Registry lifecycle: `start()` does not start a disabled provider's poller.
  This is the test that guards the "not polled" promise.
- Registry: `setEnabled` suspends a poller on disable and starts one on enable.
- Credential cache: disabling Claude makes the source forget its cached
  credential, so the next enable reads the keychain afresh.
- Settings: `disabledProviders` round-trips through `UserDefaults`; unknown ids
  are ignored; the default is empty, meaning everything is enabled.
- Presentation: the all-hidden case renders icon-only with no title, tint or
  bar, and is distinguishable from `.setupRequired`.

Unchanged and expected to stay green: both credential-boundary guarantee tests,
and every existing presentation test.

## Migration

None. The new default is an empty disabled set, so an existing install behaves
exactly as it does today.
