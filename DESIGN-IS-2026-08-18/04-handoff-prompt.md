# Handoff — /make-plan

````
/make-plan Redesign Ration Dex cards, creatures, and naming. Current design failed audit at 9/30 with critical gaps in principles #3 aesthetic (0), #8 thorough (0), and weak #2 useful / #4 understandable / #6 honest (all 1).

Verdict paragraph (quoted from 03-verdict.md):
> The Dex is a TCG costume over postage-stamp geometry. It does not look like a card, the creatures do not look like creatures, and the names/rings/types imitate Pokémon without earning the craft that makes those objects desirable. Sunk SwiftUI volume is not a reason to polish blobs.

Why redesign and not refine: Total 9/30 is under the refine threshold; aesthetic scored 0 on the actual object (the card and the creature), so padding/foil tweaks cannot salvage it.

Preserve from current design (MUST be non-empty — at minimum, name the brand tokens):
- Theme.accent terracotta and Theme.popoverWidth 340 (Sources/RationUI/Theme.swift:14, 21–24).
- Local Dex.evaluate from existing UsageHistory / live gauges; Power as a score, never a usage total; no new network hosts (Sources/RationKit/Dex.swift:5–8, 61–63, 148–161).
- Copy card to pasteboard and Save PNG (Sources/RationUI/CollectionView.swift:233–254).
- accessibilityReduceMotion gates on foil TimelineView and catch springs (Sources/RationUI/CreatureCard.swift:184; CollectionView.swift:204–209, 312–321).
- Drawn in code; original creatures; no Nintendo art (Sources/RationUI/CreaturePortrait.swift:4–7).

Discard (MUST be non-empty — name the structural patterns causing the failures):
- Shared orb() + eyes() as the whole creature, 18 ids that only differ by 2–4 primitives and a type-colored glow. Evidence: CreaturePortrait.swift:34–44, 48–68, 363–371; DESIGN-IS-2026-08-18/dex-dark.png. Caused failure on principle #3.
- TCG costume: HP, unlabeled movePower, twelve types (SPARK…MYTH), idle holofoil on every mini card, “Dex” as the product word. Evidence: CreatureCard.swift:73–155, 81, 113; Theme.swift:80; PanelTab.swift:27. Caused failure on principles #3, #4, #6, #10.
- Analog “gauge rings” on Gaugeling/Rationyx that are not RingGauge (hardcoded 0.72 trim, accent needle). Evidence: CreaturePortrait.swift:107–120, 348–360 vs RingGauge.swift. Caused failure on principle #3.
- Forced Usage→Dex tab jump plus a catch overlay with no skip on the last card. Evidence: PopoverView.swift:129; CollectionView.swift:270, 296. Caused failure on principles #2, #5, #8.
- Portmanteau names (Sparkit, Tokenoth, Limitwyrm, Rationyx, …) that read as Pokémon clones without being Pokémon. Evidence: Dex.swift:172–257. Caused failure on principles #4, #7.

Top 3–5 moves from the audit (verbatim):
1. #3 aesthetic — Draw creatures, not orbs with eyes. One silhouette per id that reads at ~90pt without the type orb; no shared eyes() as personality. Rings, if any, must be the same language as RingGauge (track, trim, accent) or absent. Evidence: dex-dark.png; CreaturePortrait.swift:34–44, 107–120, 348–371; RingGauge.swift.
2. #10 as little design as possible — Strip the TCG theater. Keep illustration, name, rarity, collector number. Drop HP, unlabeled movePower, twelve types, "RATION" wordmark, idle mini-foil. Evidence: CreatureCard.swift:73–155, 81, 113, 138; Theme.swift:80.
3. #4 understandable — Say collection, not Dex. Rename tab/header; call the score what the comment already admits (token score); never print an uncaught name in “Next · …”; "Open all" → skip remaining. Evidence: PanelTab.swift:27; CollectionView.swift:70, 80, 95, 304; Dex.swift:61–63.
4. #5 unobtrusive — Foil is a close-up material. Animate holofoil only on the inspected/catch card. Do not auto-jump the popover from Usage to Dex. Evidence: CollectionView.swift:127–129; PopoverView.swift:129; CreatureCard.swift:197.
5. #8 thorough — States and exits. Empty collection sentence; focus ring; overlay dismiss (Esc / scrim); skip on the last catch. Evidence: missing empty/focus/disabled; CollectionView.swift:270, 296.

Redesign principles in priority order:
1. #3 Aesthetic — A caught card looks like a crafted object: one creature silhouette, one metal/paper frame, rarity told by the frame not a rainbow overlay on 15 tiles. Success: at 90pt you can tell Sparkit from Heatmite with the name covered.
2. #4 Understandable — A first-time user can name the tab, the score, and a locked card without knowing Pokémon or TCG. Success: no “Dex”, no “HP”, no spoiled uncaught names.
3. #10 As little design as possible — Every remaining layer earns its place. Success: removing foil from the binder does not make the collection worse.

Deliverables for the plan:
- New information architecture (not derived from old): Collection tab, binder, one inspect card, optional first-catch toast — not a TCG layout.
- New primary flow (low-fi, labeled, compared side-by-side to current pack-rip hijack).
- Creature art spec: silhouette rules, palette cap (≤ Theme.accent + 1 type color + ink), no shared eyes helper.
- Naming spec: 18 readable names that sound like Ration, not a fan-rom set.
- Card spec: frame, rarity, collector; explicitly list dropped fields (HP, movePower, types).
- States checklist (empty, loading, error, success, focus, disabled).
- Migration path: revealedCreatureIDs keys may change with ids/names; Power thresholds stay.
- Cutover criteria: old CreaturePortrait switch and TCG chrome retired in the same release; no flag forever.

Anti-patterns to guard against (specific to REDESIGN):
- Porting old structure under new styling (keeping HP/types/Dex and “just drawing nicer blobs”).
- Keeping both designs behind a flag indefinitely.
- Redesigning to follow a trend (new foil shader, glass, MeshGradient) rather than the principles above.
- Treating the Preserve list as optional — local evaluate, terracotta, 340pt, copy/save, reduceMotion, code-drawn originals must survive.
- Re-adding a twelve-type chart or analog rings that do not match RingGauge.
````
