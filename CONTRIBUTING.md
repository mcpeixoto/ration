# Contributing

Thanks for taking a look.

## Getting started

```sh
git clone https://github.com/mcpeixoto/ration.git
cd ration
swift test
./Scripts/bundle.sh && open .build/Ration.app
```

Requires macOS 14+ and Xcode 16+, or Linux with Swift 6 and `libsqlite3-dev`.

## Ground rules

**The security constraints in [SECURITY.md](SECURITY.md) are not negotiable.**
Several are enforced by tests that will fail your build. If a change genuinely
needs a second network host, a second keychain read, or networking outside
`LimitsClient.swift`, open an issue to discuss it before writing the code.

**Keep `RationKit` free of UI frameworks.** No SwiftUI, no AppKit. It is the
part that is fully testable, and that is worth protecting. Anything needing
AppKit belongs in `RationUI` or the app target.

**Logic goes in `RationKit`, with a test.** "When should we notify?" and "how
long until the next poll?" are decisions, and decisions get tests. Views should
be thin enough that not testing them is fine.

## Style

- Follow `swift-format` defaults; CI checks this.
- Comments explain *why*, not *what*. If a line needs a comment to say what it
  does, rename something instead.
- User-facing strings are sentences, in plain language. "Your Claude Code
  session has expired" beats "Error 401: unauthorized".

## Pull requests

- One concern per PR.
- Tests for behaviour changes.
- `swift test` green before you push.
- Say what you changed and why. Screenshots for UI changes, please — the
  maintainer cannot see your menu bar.

## Adding a limit type

You probably do not need to. The UI renders whatever the API returns in its
`limits[]` array, including kinds nobody has seen yet — an unknown `kind` gets a
readable name derived from its identifier and shows up like any other row. If a
new kind needs special treatment, add a case to `UsageLimit.Kind` and a fixture
in `Tests/RationKitTests/Fixtures/`.
