# Collection Cards Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the TCG-costume Dex with a Ration collection: distinctive code-drawn silhouettes, quiet cards, readable names, and share-to-X.

**Architecture:** Keep `Dex.evaluate` and stable creature `id`s. Drop HP/types/moves from `Creature`. Portraits become per-id `Path` silhouettes (no shared eyes/orb). Cards keep illustration, name, rarity, collector, flavor. Foil only on the inspect/catch card. Share copies a PNG and opens an X compose URL; `NSSharingServicePicker` covers the rest.

**Tech Stack:** Swift 6, SwiftUI, AppKit share picker, Swift Testing.

**Spec:** `DESIGN-IS-2026-08-18/03-verdict.md` and `04-handoff-prompt.md`.

## Global Constraints

- No Nintendo art or Pokémon-clone names.
- No new network *requests*. `x.com` is a user-clicked link, like `github.com` — add it to the host allowlist.
- Local `Dex.evaluate` unchanged in spirit; Power thresholds stay; ids stay (`sparkit` … `rationyx`).
- Theme.accent, popover 340pt, reduceMotion, copy/save PNG survive.
- No auto-jump from Usage to Catch.
- `swift format --in-place --recursive Sources Tests` before commit.
- `swift test` must be green.

## Files

- Modify: `Sources/RationKit/Dex.swift` — drop type/hp/move; rename display names
- Modify: `Tests/RationKitTests/DexTests.swift` — names, share caption
- Create: `Sources/RationKit/CreatureShare.swift` — caption (pure)
- Rewrite: `Sources/RationUI/CreaturePortrait.swift`
- Rewrite: `Sources/RationUI/CreatureCard.swift`
- Rewrite: `Sources/RationUI/CollectionView.swift`
- Modify: `Sources/RationUI/Theme.swift`, `PanelTab.swift`, `PopoverView.swift`
- Modify: `Sources/RationUI/OnboardingView.swift` (`Links.xCompose`)
- Modify: `Tests/RationKitTests/CredentialTests.swift` — allow `x.com`
- Modify: `Sources/RationPreview/*`, `VERSION` at release

## Names (id unchanged)

Ember, Prompt, Needle, Moth, Wisp, Cell, Session, Coil, Context, Shift, Streak, Pace, Week, Braid, Night, Trio, Wall, Mark.

## Card

Keep: art, name, rarity (frame color), collector `001/018`, flavor on inspect.
Drop: HP, movePower, types, Dex, RATION wordmark, idle mini-foil.
Share on inspect: Copy, Save, Share…, Post on X.

---

- [x] Task 1: Plan locked (this file)
- [x] Task 2: Model + names + share caption tests
- [x] Task 3: Portraits + cards + collection + X share
- [x] Task 4: Wire tab, no hijack, hosts, preview
- [x] Task 5: Format, test, commit, tag, push
