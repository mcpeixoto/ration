# Scope — Ration Dex cards, creatures, naming

Audited: 2026-08-18
Surface: shipped Dex tab in Ration (macOS 14+ SwiftUI menu-bar popover, 340pt wide)

## What is being audited

User-facing collectible layer only:

- Full and mini **cards** (`CreatureCard`, `HoloFoil`, inspect overlay, catch overlay)
- **Creature portraits** (the 18 drawn bodies + type orbs / gauge rings)
- **Naming**: creature names, types, moves, flavour, collector numbers, rarity labels, requirement hints, “Dex” / “Power” chrome

Out of scope for this audit: unlock math, persistence, share/copy plumbing except where it affects the visual/copy surface.

Primary files:

- `Sources/RationUI/CollectionView.swift`
- `Sources/RationUI/CreatureCard.swift`
- `Sources/RationUI/CreaturePortrait.swift`
- `Sources/RationUI/Theme.swift` (rarity/type tokens)
- `Sources/RationKit/Dex.swift` (roster copy)

## Who and primary task

- Primary user: a Ration user who already meters Claude / Codex / Cursor.
- Primary task: see what they caught from real local usage, feel it is a *card*, optionally copy it for an X post.
- Secondary audience: a 20–30s upbeat video; the first pack-rip has to read on camera.

## Constraints

- Native SwiftUI, drawn in code (no Pokémon IP, no bitmap mascots).
- Must sit in the existing 340pt popover; terracotta accent, quiet/private brand.
- Catch state is local; Power is a game score, not a usage total.

## References named by the user

- Pokémon TCG card anatomy (foil, HP, type, collector number) — *feeling*, not likeness.
- Current Ration UI: `RingGauge`, `Theme.accent`, menu-bar restraint.
