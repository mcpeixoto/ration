# Verdict — Ration Dex

**REDESIGN** — 9/30, with 0 on aesthetic (#3) and thoroughness (#8).

The Dex is a TCG costume over postage-stamp geometry. It does not look like a card, the creatures do not look like creatures, and the names/rings/types imitate Pokémon without earning the craft that makes those objects desirable. Sunk SwiftUI volume is not a reason to polish blobs.

## Why redesign, not refine

Total is under 20. The load-bearing failure for this surface is #3: a collectible that cannot be taken seriously as an object. Refining foil opacity or padding will not give Sparkit a silhouette. #2 and #4 are 1s because the costume (HP, Dex, Power, twelve types) fights the actual job (show what local usage unlocked).

## Highest-leverage moves

1. **#3 aesthetic — Draw creatures, not orbs with eyes.** One silhouette per id that reads at ~90pt without the type orb; no shared `eyes()` as personality. Rings, if any, must be the same language as `RingGauge` (track, trim, accent) or absent. Evidence: `dex-dark.png`; `CreaturePortrait.swift:34–44, 107–120, 348–371`; `RingGauge.swift`.

2. **#10 as little design as possible — Strip the TCG theater.** Keep illustration, name, rarity, collector number. Drop HP, unlabeled movePower, twelve types, `"RATION"` wordmark, idle mini-foil. Evidence: `CreatureCard.swift:73–155, 81, 113, 138`; `Theme.swift:80`.

3. **#4 understandable — Say collection, not Dex.** Rename tab/header; call the score what the comment already admits (token score); never print an uncaught name in “Next · …”; `"Open all"` → skip remaining. Evidence: `PanelTab.swift:27`; `CollectionView.swift:70, 80, 95, 304`; `Dex.swift:61–63`.

4. **#5 unobtrusive — Foil is a close-up material.** Animate holofoil only on the inspected/catch card. Do not auto-jump the popover from Usage to Dex. Evidence: `CollectionView.swift:127–129`; `PopoverView.swift:129`; `CreatureCard.swift:197`.

5. **#8 thorough — States and exits.** Empty collection sentence; focus ring; overlay dismiss (Esc / scrim); skip on the last catch. Evidence: missing empty/focus/disabled; `CollectionView.swift:270, 296`.

## Preserve

- `Theme.accent` / terracotta, popover width 340 (`Theme.swift:14, 21–24`).
- Local `Dex.evaluate` from existing history; no new hosts (`Dex.swift:5–8`).
- Copy/Save PNG (`CollectionView.swift:233–254`).
- `reduceMotion` foil/spring gates (`CreatureCard.swift:184`).
- Drawn in code, original creatures, not Nintendo art (`CreaturePortrait.swift:4–7`).
