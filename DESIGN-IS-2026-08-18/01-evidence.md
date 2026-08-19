# Evidence — Ration Dex cards, creatures, naming

Consolidated from structural, visual, copy, weight, and accessibility subagents plus rendered `dex-dark.png` (RationPreview, 680×960). No scores in this file.

## A. Screenshot (observed)

File: `DESIGN-IS-2026-08-18/dex-dark.png` (from `/tmp/ration-dex-review/dex-dark.png`).

Observed on the rendered binder (preview history, 11 of 18 caught):

- Header: “Dex” + “11 of 18 caught”; trailing “5.3M Power”; hunt “Next · Burnrate” at 53% (uncaught name printed).
- 3-column mini cards. Caught commons: grey border. Uncommons: green glow/border. Later rows: blue/purple.
- Every portrait: type-colored radial orb + two white dots for eyes + 2–4 primitive shapes (capsule, circle, square). No line art, no limbs, no species silhouette that differs at stamp size beyond color.
- Foil/glow reads as a colored bloom, not a card holofoil. Card chrome is a rounded rect + name + 8pt rarity.

## B. Structure

Sources: `CollectionView.swift` 1–335, `CreatureCard.swift` 1–250, `CreaturePortrait.swift` 1–410, `PanelTab.swift` 1–88, `PopoverView.swift` 50–196.

- Interactive declared: **29** (5 tabs + 18 grid buttons + inspect scrim/copy/save/close + overlay Next + Open all). `CollectionView.swift:122–183, 296–306`; `PanelTab.swift:55–57`.
- Nesting: chrome depth **7**; wallback silhouette **12**. `CollectionView.swift:34` → `CreatureCard.swift:73` → `CreaturePortrait.swift:13–15`.
- Repeated patterns: **8** (full card in inspect/catch/export; two scrims; shared portraitFrame/foil/stroke/shadow; `"???"` twice; prominent+borderless button pairs).
- Dead: `AppKit` import on `CreatureCard.swift:1`; `PanelTab.symbol` unused by `TabSwitcher` (`PanelTab.swift:31–39` vs `:61`); `.common` foilColors unreachable (`Theme.swift:80, 84`).
- Catch scrim is **not** tappable (`CollectionView.swift:270`); inspect scrim is (`:165–167`). Last catch has no Skip (`:296`).
- `PopoverView.swift:129`: `if hasPendingCatches { tab = .dex }` on appear.

## C. Visual tokens

Sources: `CreatureCard.swift`, `CreaturePortrait.swift`, `Theme.swift:67–130`, `RingGauge.swift:1–100`.

- Spacing literals (pt): `[0, 2, 4, 5, 6, 8, 10, 12, 14, 16]`.
- Type: 8 / 9 / caption2 / caption / subheadline / headline / title3. Mini rarity is **8pt**.
- Distinct color expressions on this surface: **61** (4 Theme + 5 system + 9 named foil + 30 portrait RGB + 9 type RGB + 4 rarity pairs).
- Every creature draws `orb()` (`CreaturePortrait.swift:34–44`) and `eyes()` (`:363–371`). `braidon` calls `eyes()` twice (`:289–290`).
- Gaugeling ring: accent stroke + Capsule needle at 48° (`:107–120`). Rationyx: trim **hardcoded 0.72**, white stroke (`:348–360`). `RingGauge.swift` uses `Theme.ringSize` 116, line 11, `Theme.track`, live `percent` AngularGradient. **Not the same geometry.**
- Foil on every caught uncommon+ mini: `hasFoil >= .uncommon` (`Theme.swift:80`); binder `foilPlaying: animates && caught` (`CollectionView.swift:127–129`); 15 of 18 roster entries qualify (`Dex.swift:170–260`).
- States: loading present (`CollectionView.swift:151–157`). Empty / error / focus / disabled **missing**. 0-caught still draws 18 slots.

## D. Copy

Sources: `Dex.swift:170–261`, `CreatureCard.swift:54–140, 222–249`, `CollectionView.swift:67–334`, `PanelTab.swift:27`.

18 names: Sparkit, Promptail, Gaugeling, Tokenoth, Cachewisp, Heatmite, Sessiondrake, Limitwyrm, Contextaur, Modelith, Streakon, Burnrate, Weeklyrex, Braidon, Nightshift, Omnivore, Wallback, Rationyx. 14/18 portmanteau + creature suffix; 4 English compounds.

- `"Power"` = sum of billable tokens (`Dex.swift:61–63, 273`; `CollectionView.swift:80`). Card also shows unlabeled `movePower` (`CreatureCard.swift:113`) and `"HP \(n)"` (`:81`). HP/movePower **unused** by `UnlockRequirement.isMet` (`Dex.swift:79–95`).
- `"Dex"` tab + header (`PanelTab.swift:27`, `CollectionView.swift:70`). Overlay CTA `"Into the Dex"` (`:296`).
- `"Next · \(hunt.creature.name)"` prints uncaught name (`CollectionView.swift:95`); mini uses `"???"` (`CreatureCard.swift:54`).
- `"Open all"` → `skipAllReveals` (`CollectionView.swift:213–215, 304`).
- `"Spend any tokens"` vs `power > 0 || !providers.isEmpty` (`Dex.swift:81`; `CreatureCard.swift:226`).
- `"Code after 10pm"` vs `hour >= 22 || hour <= 5` (`Dex.swift:90–92`; `CreatureCard.swift:235`).
- Types rendered `.uppercased()`: SPARK PAPER LIMIT CACHE HEAT TOKEN SESSION MODEL FLAME TOOL NIGHT MYTH (`CreatureCard.swift:76`; `Dex.swift:28–33`).
- Wordmark `"RATION"` (`CreatureCard.swift:138`) vs app `"Ration"` (`PopoverView.swift:143`).

## E. Weight / motion

- JS bytes: **0**. Dex network: **0**.
- Idle binder: up to **15** playing `TimelineView`s at 24 fps (`CreatureCard.swift:197`; 15 uncommon+). Parent popover 1 Hz `TimelineView` (`PopoverView.swift:95`). Catch overlay does not unmount binder, so foils continue underneath.
- Initial attention if pending: **2** (forced Dex tab + CatchOverlay). `reduceMotion` gates foil and springs; **does not** gate `tab = .dex` (`PopoverView.swift:129`).

## F. Accessibility (inferred contrast)

- `CreaturePortrait` `.accessibilityHidden(true)` (`CreaturePortrait.swift:31`).
- Uncaught a11y: `"Undiscovered, {hint}"` (`CollectionView.swift:132–135`).
- Only keyboard shortcut: overlay `.defaultAction` (`CollectionView.swift:301`). No cancel/skip-link/modal trait.
- Foil overlay sits **above** all card text (`CreatureCard.swift:69, 151, 181–216`).
- Type-colored 9pt labels: night on dark ~2.5:1 (fail). Overlay headlines in rarity color on black 0.72 fail in light. Secondary on card ~3.8:1 (fail 4.5:1).

## Known gaps

- Runtime Instruments not run; 15 foils is an upper bound if LazyVGrid culls.
- Live NSPopover fill not a hex in source; contrast uses preview proxies.
- Foil overlay blend contrast unmeasured.
