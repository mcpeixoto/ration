# Launch post — drafts

Attach `docs/images/demo.mp4`. Pick one and edit it into your own voice; these
read as written-by-you, not written-by-committee, but they're drafts, not
finished copy.

---

## A — the problem first (recommended)

> I kept hitting my Claude limit mid-task with no warning.
>
> So I built Ration: a macOS menu bar app that shows exactly how much of your
> plan is left, plus a calendar of everything you've run and where the tokens
> went.
>
> Native SwiftUI. No telemetry. MIT.
>
> github.com/mcpeixoto/ration

**Why this one:** leads with the frustration, which is the part other people
recognise instantly. The features land as the answer rather than a list.

---

## B — short and confident

> Your Claude usage, in the menu bar.
>
> Live plan limits, an activity calendar, and where your tokens actually go —
> by model and by project.
>
> Native macOS, no telemetry, open source.
>
> github.com/mcpeixoto/ration

**Why this one:** fastest to read. Good if the video is doing the persuading.

---

## C — for a technical audience

> Built a menu bar app for Claude usage, and open-sourced it.
>
> The interesting part isn't the gauge — it's that it reads your OAuth token
> from the keychain to hit the same endpoint `/usage` uses, and the whole
> security posture is enforced by tests rather than promised in a README. One
> credentialed host, refresh token never touched, transcripts parsed for token
> counts and nothing else.
>
> github.com/mcpeixoto/ration

**Why this one:** the "enforced by tests" angle is the genuinely unusual thing
here and the crowd most likely to star a repo is the crowd that cares about it.

---

## Follow-up post (optional, thread)

> A detail I'm oddly pleased with: the screenshots and the demo video in the
> README are rendered from the real SwiftUI views by a tool in the repo, not
> captured by hand. `swift run RationPreview` regenerates them.
>
> So they can't silently drift out of date as the UI changes.

---

## Notes before you post

- **The repo has no release yet.** Anyone clicking through can build from
  source, but `brew install` won't work until you cut `v0.1.0`. Either ship a
  release first or expect "how do I install this?" replies.
- Consider posting mid-morning US Eastern on a weekday — that's when this
  audience is most active.
- If it gets traction, the most common follow-up questions will be "does it
  work with Pro?" (yes — it reads whatever plan your account has) and "is my
  token safe?" (point them at SECURITY.md).
