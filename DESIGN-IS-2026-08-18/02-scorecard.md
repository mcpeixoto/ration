# Scorecard — Ration Dex

Each principle 0–3. Tie-breaker: lower score. Score the worst instance, not the mean. Total /30.

## 1. Good design is innovative — Score: 1/3

Evidence: TCG anatomy (HP, type, collector `001/018`, foil, “Dex”) in `CreatureCard.swift:73–155` and `PanelTab.swift:27`; portraits are shared `orb()` + `eyes()` (`CreaturePortrait.swift:34–44, 363–371`). Screenshot `dex-dark.png`: stamp-size blobs, not a new card language.

Justification: Refreshes nobody’s pattern — it imitates Pokémon TCG chrome with a local-history twist, which is a minor variation on a competitor’s collectible, not a new form.

## 2. Good design makes a product useful — Score: 1/3

Evidence: Primary Dex task (see a catch, treat it as a card, copy it) requires overlay queue (`CollectionView.swift:36–48, 194–198`), then tap postage-stamp (`:122–131`), then Copy (`:177`). Forced `tab = .dex` (`PopoverView.swift:129`) intercepts the usage meter. Hunt bar spoils the uncaught name (`CollectionView.swift:95` vs `CreatureCard.swift:54`).

Justification: The task is reachable, but only after detours that the usage app did not ask for; the card itself is too small to serve “inspect / share a special object.”

## 3. Good design is aesthetic — Score: 0/3

Evidence: `dex-dark.png` — identical two-dot eyes, radial orbs, 2–4 primitives per creature. 61 color expressions (`01-evidence.md` §C). Mini rarity 8pt (`CreatureCard.swift:57–60`). Foil is a colored bloom overlay, not a card material (`CreatureCard.swift:202–216`). Rings on Gaugeling/Rationyx do not match `RingGauge.swift`.

Justification: Active visual noise and no executed card/creature system — the collectible does not look collected.

## 4. Good design makes a product understandable — Score: 1/3

Evidence: `"Dex"` with no expansion (`PanelTab.swift:27`). `"Power"` vs unlabeled `movePower` vs `"HP n"` (`CollectionView.swift:80`; `CreatureCard.swift:81, 113`). Types `CACHE`/`MYTH` (`CreatureCard.swift:76`). `"Open all"` skips (`CollectionView.swift:304, 213–215`). `"Next · Burnrate"` vs binder `"???"`.

Justification: The grid is tappable, but two or three primary labels do not name what they do; jargon is load-bearing.

## 5. Good design is unobtrusive — Score: 1/3

Evidence: Up to 15 idle 24fps foils (`CreatureCard.swift:197`; `Theme.swift:80`). Catch scrim 0.72 (`CollectionView.swift:270`). Foil overlay on text (`CreatureCard.swift:151`). Forced Dex tab (`PopoverView.swift:129`) not reduceMotion-gated.

Justification: Decoration (foil, bloom, hijack overlay) competes with the creature, which should be the figure.

## 6. Good design is honest — Score: 1/3

Evidence: HP/movePower unused by unlocks (`Dex.swift:79–95` vs `CreatureCard.swift:81, 113`). `"caught"` is derived history (`Dex.swift:152`; `Settings.swift:87–88`). `"Spend any tokens"` vs live provider with 0 tokens (`Dex.swift:81`). `"Code after 10pm"` vs hours ≤5 (`Dex.swift:90–92`). Rarity headlines imply scarcity; roster is fixed (`CollectionView.swift:325–333`).

Justification: Two or more inflations plus one dark-pattern-adjacent hijack; not a deceptive checkout, but the card claims to be a game it is not.

## 7. Good design is long-lasting — Score: 1/3

Evidence: Tab name `"Dex"` (`PanelTab.swift:27`); 14/18 Pokémon-style portmanteaus (`Dex.swift:172–257`); idle holofoil (`Theme.swift:79–80`); TCG HP row (`CreatureCard.swift:81`).

Justification: Two or three dated markers (Dex naming, clone morphology, fad foil) that will read as a 2026 meme, not Ration.

## 8. Good design is thorough down to the last detail — Score: 0/3

Evidence: No empty state (0 of 18 still 18 slots). No error. No focus ring (`.buttonStyle(.plain)`, `CollectionView.swift:131`). No disabled. Overlay: no tap-dismiss, no cancel shortcut (`CollectionView.swift:270, 301` only `.defaultAction`). Last catch cannot skip.

Justification: Four or more states missing or default.

## 9. Good design is environmentally friendly — Score: 2/3

Evidence: Native, 0 JS, 0 Dex network (`Package.swift`; Dex files have no URLSession). `reduceMotion` pauses foil (`CreatureCard.swift:184`). Dark scheme used. Idle: 15×24fps TimelineViews when the binder is full (`01-evidence.md` §E).

Justification: Motion is gated and the bundle is native, but idle animation is the default, so not a 3.

## 10. Good design is as little design as possible — Score: 1/3

Evidence: Full card stacks type, HP, portrait, name, symbol, rarity, divider, move, movePower, flavor, collector, `"RATION"`, foil, shadow, 3D tilt (`CreatureCard.swift:73–155`). Mini still has foil+gradient+orb. Hunt row duplicates the next name.

Justification: Three to five layers can be removed without breaking “see what I unlocked.”

---

**Total: 9 / 30**
