# The companion loop

Ration's collection is a loop, not a checklist. A sealed pack fills as you burn
tokens, rips into a creature, the creature evolves along a route decided the
moment the pack opened, and files itself into the binder — then a fresh pack is
sealed and it starts again.

Everything here is decided on your machine from usage Ration already reads.
There is no host, no account, and nothing to sign into. See [PRIVACY.md](../PRIVACY.md).

## The shape of a run

```
sealed pack ──5M──▶ rip ──▶ creature ──▶ evolve ──▶ … ──▶ file ──▶ sealed pack
```

Set 01 is already an evolution forest: fifteen root creatures, all fifty
reachable, branching up to five ways, three forms deep, thirty-three distinct
routes from a root to a final form. `EvolutionForest` resolves that from the
`evolvesFrom` names printed on the cards, and `EvolutionForestTests` is what
keeps it honest — nothing else validates those names.

**Ripping** picks a root, weighted by its rarity, then plans the whole route
through the line in one go. The route is known from the first frame but is never
shown: the header names the form on screen, and the evolution strip draws a
question mark for every form still to come.

**The branch preference** is the load-bearing rule. At each fork the roll prefers
children that still lead to a final nobody has filed. That is what makes the set
completable without making early pulls predictable — and once a line is
exhausted the preference has nothing left to prefer, so a favourite can still be
replayed for a shiny.

## Balance

Every number lives in `CompanionBalance`, with its reasoning attached.

| | |
|---|---|
| Pack fill | 5M tokens |
| Shiny | 1 in 64, or 1 in 48 holding a Lens |
| Traits | 25, rolled at the rip, cosmetic |
| Exhausted-line weight | ÷8 |

Graduation total, by the rarity of the **final** form a run reaches:

| common | uncommon | rare | epic | legendary | mythic |
|---|---|---|---|---|---|
| 150M | 300M | 600M | 1.2B | 2B | 3B |

Split across the line so the stages of a `k`-form run sum to exactly that total
whatever `k` is, and later stages cost more than earlier ones:

    stage i of k  =  total · (i+1) / (k(k+1)/2)

A three-form epic line is therefore 200M, 400M, 600M. A two-form rare line is
200M, 400M. A one-form line pays the whole total at once. Without that, a
branching line would quietly become the cheap way to farm the set.

**What that adds up to.** Simulated over two thousand seeded runs: a full fifty
takes a median of 44 rips and about 43B tokens — roughly six months of heavy use,
a year and a half of steady use. The first rare lands around the second run, the
first mythic around the twenty-fourth.

## The shop

The wallet is tokens you have already burned: `credited − spent`. Spending draws
on the wallet and never on growth, so buying something never costs you progress.

| | price | |
|---|---|---|
| Refactor | 50M | Rolls a new trait |
| Booster Pack | 200M | Discards what you are raising, seals a new pack |
| Overclock | 250M | +50M growth |
| Lens | 600M | Shiny odds 1 in 64 → 1 in 48, permanently |
| Foil Pack | 800M | Guaranteed to reach rare or better |
| Hobby Pack | 1.6B | Guaranteed to reach epic or better |

Filling a limit window pays an Overclock — one for a 5-hour cap, five for a
weekly one. It pays once per fill, survives a restart, and the first run after
updating only records the state rather than paying out for last week's work.

Two deliberate prices:

- **Guaranteed packs are priced off the graduation-total ratio, not the
  probability ratio.** Priced by probability, two cheap packs would beat one
  expensive pack on every axis at the same spend and the higher tier would be a
  trap.
- **An Overclock costs five times the growth it grants**, so the free one from
  filling a limit is always the better deal.

The top two tiers are not sold. A guaranteed mythic is the whole game bought
outright.

## Shinies

One rip in sixty-four. Fixed at the rip and kept through every evolution.

A shiny is the same creature drawn in a colourway rotated 168° around the wheel,
keeping saturation and lightness. One number rather than fifty authored colours,
guaranteed to differ from the original, and each creature's shiny still differs
from every other creature's. Pairing each energy with the one it is weak to was
tried first and abandoned: three of the eight pairs are both warm, so those
shinies were indistinguishable from their normals.

The maths is in `RationKit.ShinyPalette` because both renderers need it and a
second copy would drift without either side ever looking wrong.

## State on disk

`~/.config/ration/companion.json` on Linux, `~/Library/Application
Support/Ration/companion.json` on macOS — beside `config.json`, so a profile is
one directory.

`Ration.app`, `ration-tray` and `ration watch` can all be running at once against
that one file, so:

- Every change goes through `CompanionStore.mutate`, which re-reads immediately
  before applying and writes atomically. A change that changed nothing is not
  written at all.
- Crediting is **idempotent**: the ledger stores lifetime tokens already claimed
  per provider, and growth is the rise over that. Whoever writes first takes the
  delta and the rest see nothing left to take. Lifetime rather than daily,
  because a daily baseline double-credits across a date boundary with two
  writers.
- Decoding is forgiving. One unreadable field degrades to its default and one
  corrupt row of the catch log drops itself, rather than costing somebody their
  binder. A file that is not a state at all is moved aside as `companion.corrupt.json`.

## Migrating from Set 01

The first time a profile runs the loop:

1. Whatever the old thresholds had already unlocked is written into the **Set 01
   archive** — a read-only mark. Those cards stay in the binder, stay
   inspectable and stay shareable; they do not count toward the new total and do
   not steer the roll.
2. The ledger baseline is seeded from the current reading, so a two-year history
   is not paid out as one enormous credit.
3. A pack is sealed at 0 / 5M.

The old thresholds (`UnlockRequirement`) still print on every card as the
creature's deed. They no longer decide anything; `Dex.evaluate` reads them once,
for step 1.

## Driving it without waiting

Walking the loop costs tens of billions of tokens, so there is a debug path:

```sh
export RATION_DEBUG=1
export RATION_STATE_DIR=/tmp/ration-play    # never touch a real profile

ration dex                       # sealed pack, 0 / 5M
ration dex simulate 5_000_000    # rips
ration dex simulate 400_000_000  # evolves
ration dex simulate 3_000_000_000
ration shop && ration shop buy foil
ration bag use overclock
```

`RATION_STATE_DIR` exists because `NSHomeDirectory()` ignores `HOME` on Linux, so
pointing `HOME` at a scratch directory does not work. `ration-tray --screenshot`
honours it too.
