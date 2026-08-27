# 19 — Mage Knight

**Researched, and ranked last of the three deckbuilders.** Not started, and
should not be: two compounding engine gaps — hex geometry, and a map whose
*extent* grows — plus a change to the arithmetic grammar. Buildable only as a
stripped prototype, and the cuts are dishonest ones. Also depends on
[01](01-boardgames.md) gap 1 (the square a move passes over) and gap 5
(triggers).

> *One of three deckbuilder candidates — Mage Knight, Puzzle Strike, Lost
> Ruins of Arnak. Research all three, write down their rules, and find out
> which one the engine can actually reach.*

**Objective.** Mage Knight is widely considered the most mechanically dense
deckbuilder in print: a hand of cards that can each be played in multiple
distinct ways (basic vs. "powered" by matching mana, plus a card-specific
top/bottom effect), a hex map built tile by tile as players explore it,
day/night mana rules that change which colors are free to spend, block-then-
damage combat against monsters with armor and resistances, and a Fame/
Reputation leveling track. This file's job is not to design a game yet — it
is to find out how much of that is actually reachable, because several pieces
(hex geometry, a fog-of-war map built during play, one card meaning four
different things depending how it's cast) sound like they may need real
engine work rather than content.

---

## Stage 1 — the rules document

**Deliverable:** `ideas/mage_knight/rules.md`, written from a verified
source where one is reachable, and marked plainly wherever a detail is
recalled rather than checked. Must cover:

- The core round structure (day/night, movement, one "turn" as a sequence of
  card plays).
- The exact shape of a card: name, its basic effect, its two mana-powered
  effects (or however many a real card carries), and which of those change
  by color.
- The mana system: the source die pool, which colors are free by day vs.
  night, banked crystals vs. drawn dice.
- Combat resolution in order: ranged/siege, block, assign damage, attack,
  resistances and armor.
- Map construction: tile types, how exploration reveals new tiles, site
  types (village, monastery, dungeon, city) and what interacting with each
  does.
- Fame, Reputation, leveling, and end-of-game/scenario scoring.
- The solo and cooperative scenario structure, since that's the mode this
  engine is best positioned to support.

**Done** — [ideas/mage_knight/rules.md](mage_knight/rules.md). Built from
UltraBoardGames' rules pages, BGG forum threads on specific mechanics, and
Wikipedia framing; the official WizKids/CGE PDFs and the mageknight.net
walkthrough exceeded what this session's tools could fetch whole. Every
number that couldn't be cross-checked across two independent sources is
flagged inline as approximate or unverified (§10 of the rules doc collects
them) rather than stated flat.

## Stage 2 — what it names that the engine lacks

**Deliverable:** a table in the shape of [18](18-legends-of-runeterra.md)'s —
one row per Mage Knight rule, mapped to what ravel already has, what's
expressible with existing vocabulary, and what's a genuine gap. Close with a
verdict: buildable as a full game, buildable as a stripped prototype (which
pieces get cut and why), or not worth attempting this year.

| Mage Knight rule | Ravel today |
|---|---|
| Personal 16-card Hero deck, hand of 5, draw back up each turn | `per_seat` deck + hand zones, `shuffle` — **exists** |
| Recruiting Units/Advanced Actions from a shared offer, paid in Influence | the overlay/`options` offer plus `cost` — **exists**, same shape as the draft-one-of-three pattern |
| Round counter, auto-incrementing | the reserved `round` stat on the injected system card — **exists** |
| Day/Night alternating every round, gating which cards and mana are legal | a stat flipped by a round-boundary `turn.action`, plus `phases` on a card (or a tag that grants `phases`) restricting it to the current day/night phase — **expressible**, no engine work; this is MTG's sorcery-speed idiom, already documented |
| Tactic cards: simultaneous hidden per-seat pick that sets *this round's* turn order | **genuine gap**, two-part — see below |
| Sideways play: any non-Wound card becomes a flat 1 of Move/Influence/Attack/Block, player's choice, ignoring its own printed text | **expressible, verbose** — extra `abilities` entries (or a tag every card carries) each bumping one of four pool stats by 1; mechanical repetition across ~150 cards, a generator's job (`tools/make_lost_cities.py` is the precedent), not a missing primitive |
| A card's basic (free) vs. mana-powered (costs 1 die/crystal of a named color) effect | **exists** — `abilities`, two entries, one with an empty cost and one costing the printed color; exactly AUTHORING's "A card that can do several things" |
| Spell cards: top and bottom are two *differently named* effects, the bottom castable only at Night | **expressible** — `abilities` again, the second entry's `phases` gated to the night phase |
| Artifact cards: the powered effect destroys the card on use | **exists** — `destroy_self` at the end of an ability's `action` list |
| Wound cards: unplayable, count only against hand size, enter hand as combat damage | **expressible** — a `token`-tagged card with no `play` block, created via `gain:card:n` inside the damage-assignment action list |
| Source: a shared pool of colored mana dice, day/night restricts which colors are legal to take, returned and rerolled at round end | **expressible** — a shared (non-`per_seat`) zone of color-tagged token cards; day/night legality is the same `phases` tag-grant as for cards; "reroll" is `return_to` + `shuffle` + redeal, the documented "roll / draw randomly" idiom |
| At most one die taken from the Source per turn | **expressible** — a per-turn counter stat and a `needs` check, the same shape the engine's own `plays` stat already uses for "at least one card played," just inverted |
| Mana crystals, capped at 3 per color, banked indefinitely | **exists** — `card_stats` plus a `<stat>_max` companion, the engine's ordinary clamp-to-max convention |
| Combat: ranged/siege sub-phase, then block, then damage assignment, then attack, all against one enemy token inside one player's own turn | **expressible as ordered phases** — no real-time or hidden-information problem at all, since it is PvE inside one seat's turn; `push_phase` for the sub-steps, routing/`needs` comparing an accumulated attack-pool stat against the enemy's `armor` stat to skip ahead when an earlier phase already wins |
| Assigning unblocked damage across a player's own Units before the Hero, one Wound-plus-armor-deduction at a time, player's choice of order | **expressible but heavy** — a repeated `options:` choice-and-resolve loop, authored per fight rather than a new primitive; closest existing precedent is `challenge`'s pass/fail branching, stretched thin |
| Physical resistance halves an attack, rounded down, unless it's Fire or Ice | **genuine gap** — the amount grammar is products only ("no division, no subtraction inside one amount," AUTHORING's own refusal list); halving-and-flooring is exactly that arithmetic, just at smaller scale than the one LoR already refused |
| Armor as a flat damage-to-defeat threshold, Fame awarded on defeat | **exists** — a stat comparison (`needs`/routing `at_least`) plus `stat_gain:fame:n`, identical in shape to any boss-HP check |
| Fortified sites/enemies: only Siege attacks work before blocking, and a Reputation cost to even attempt | **exists** — `receive.needs`/`play.needs` tag-gating on a `fortified` tag, plus an ordinary `stat_damage` in the action list |
| Hex map, built tile-by-tile as Heroes explore, revealed on first move onto an unrevealed tile | **genuine gap**, two-part — see below |
| Fame track driving Hero level, alternating stat boosts and new-card unlocks | **exists/expressible** — an ordinary stat, `computed_tags` for threshold checks, `gain:card:n` for the unlocked Advanced Action |
| Reputation track modifying Influence once per turn; the "X" space blocks all interaction | **expressible** — `sum:reputation@self` as an amount (Castle's `sum:defense@standing` is the same idiom), and `receive.needs`/`play.needs` gating interaction cards on the reputation stat |
| Units attached to and travelling with a Hero, limited by Command tokens | **expressible, and a good match** — `attach_to_target` (`game/actions.lua:513`), built and, per [15](15-many-on-one-square.md), shipped in no game yet; a Unit riding along with its Hero is at least as natural a first customer as LoR's blocking pair |
| Shared win/lose condition across all seats in co-op | **exists** — ordinary `end_conditions`, already seat-agnostic; AUTHORING's "party" pattern (several `player`-tagged cards under one fate) already covers several Heroes sharing one outcome |
| Dummy-player round clock (no AI, a pure countdown that ends the round when its deck runs out) | **exists, almost verbatim** — the engine's own `round` stat plus an `end_conditions` threshold *is* a dummy-player clock; the single easiest piece of the whole game |
| Terrain movement cost varying by hex type and day/night | **small, already-named gap** — wants an author-declared stat on a grid slot, which [ideas/README](README.md)'s open item 6 already lists as wanted by no game yet; Mage Knight would be its first customer |

### Hex geometry — a real gap, not a content trick

`grep -rniI hex` across the repo turns up exactly one relevant hit outside
test fixtures and an unrelated JSON unicode-escape variable: a comment in
`game/zones.lua:457` that name-drops "a hex map" purely as an example of a
non-square shape needing aspect-ratio preservation on screen — nothing about
adjacency or coordinates. `game/geometry.lua` is built entirely on `[cols,
rows]` rectangles: `M.slot_at` computes a row-major index from a column and a
1-based rank, and `M.reach` walks a pattern by repeatedly adding `[dx, dy]` to
`(col, row)`. None of that is hex-shaped. A hex board needs either offset
coordinates (neighbor vectors that flip depending on row parity) or a switch
to axial/cube coordinates entirely — a different number space than
`[col, row]`, not a variant of the existing one — and it would touch
`geometry.slot_at`, `geometry.reach`, the `patterns` vector format itself, and
`M.square`'s algebraic-name parsing (hex boards have no natural "a1"). This is
the one place the stub's fear is correct: it is engine work of the same shape
`patterns`/`geometry.lua` already was for chess, not something a game file can
route around.

### The growing map — a known-shape gap, not a novel one

Mage Knight's map starts as a handful of tiles and grows, unbounded in every
direction, as Heroes explore. `DESIGN.md`'s "Setup Is the Manual, Not the
Cards" already explains why `setup.place`'s order is load-bearing — entity IDs
are handed out as cards are created, so a seeded replay only holds if setup
builds the board the same way every time — but that constrains *when* content
is created, not whether it can be: `fill:zone:card:n` and `gain:card:n`
already create entities mid-game under the same seeded RNG. What doesn't fit
is that a `grid` zone's `[cols, rows]` size is fixed at zone-creation time,
and Mage Knight's map is not a fixed rectangle slowly filling in — its extent
itself grows. [21](21-lost-ruins-of-arnak.md) already named this exact
question for Arnak's personal exploration board, tracing it back to "the
'board that grows as you play' question Hive and Carcassonne already raised
in the earlier board-game survey" — Mage Knight is a third instance of the
same named gap, not a fresh one, and it compounds with hex geometry rather
than standing apart from it: a growing hex board is two gaps stacked.

### The four-things-per-card fear resolves in ravel's favor

The one worry in the objective that turns out *not* to be a gap: `abilities`
already covers a card offering several distinct action blocks, each with its
own cost, target and action — AUTHORING's own words for the feature. Basic vs.
mana-powered is two ability entries, one costing nothing and one costing the
card's printed color. The universal "sideways" fallback (any card becomes a
flat 1 of whichever pool the situation needs) is the same four ability
entries, functionally identical, on every card in the game — repetitive, and
a generator's job past a handful of cards, but not a new engine concept.
Nothing here asks for anything `abilities` doesn't already do.

### Combat sequencing needs no real-time anything

The stub's other explicit worry — does block-then-assign-damage need
simultaneous resolution, a stated non-goal — has a clean answer: no. A Mage
Knight fight is one seat, alone, against enemy tokens that never act on their
own initiative; nothing about it is PvP, let alone simultaneous. Ranged/siege,
block, damage assignment and attack are four ordered sub-phases inside one
player's own turn, exactly the shape `push_phase`/routing already handles.
The real cost sits elsewhere: the halving-with-floor arithmetic physical
resistance needs (a genuine, small extension to the amount grammar — see the
table), and the weight of authoring a player-choice damage-allocation loop per
fight (expressible today, but heavy content, not a missing primitive).

### Verdict

**Buildable only as a deliberately stripped prototype, and even that costs
more than either of the other two deckbuilder candidates.** The honest cuts:
drop the competitive "Conquest" mode entirely (already out of scope per the
objective — simultaneous hidden Tactic picks are exactly the kind of
per-seat-hidden-simultaneous-choice AUTHORING's "rules that do not fit"
already refuses, on top of turn order needing to be *re-derived* every round
rather than fixed by the phase list, which nothing in `phase`/routing
supports); replace the halving-with-floor resistance rule with a binary
"immune unless elemental" flag, which fits the existing product-only grammar
without touching it; and pre-place a modest, fixed-size, mostly-hidden map at
setup — tiles exist as `setup.place`d cards from the start and "exploring"
just flips one face-up, rather than growing the grid. That third cut buys
back both the hex-geometry gap and the growing-map gap in one move, at the
real cost of the map no longer being a hex map, nor unbounded — the least
honest cut of the three, since Mage Knight's terrain and sight lines are not
flavor, they shape movement cost and which enemies can be provoked. What
survives those three cuts — Hero decks with `abilities`-based basic / powered
/ sideways play, the Source as a shared color-tagged zone, ordered-phase
combat, Fame/Reputation/leveling, a co-op scenario riding the engine's
existing `round`-stat clock — is genuinely reachable with today's vocabulary
plus one small, already-named addition (an author-declared slot stat) and one
small grammar exception (a bounded division/floor operator, the same kind of
deliberate, bounded bend `DESIGN.md` already made once for subject-valued
comparisons). Weighed against the other two candidates: [20](20-puzzle-strike.md)
is close to free — its own file already expects "buildable now, mostly
content," a Dominion-shaped loop the engine plausibly already supports.
[21](21-lost-ruins-of-arnak.md) names one real, well-scoped gap (worker
placement as a slot-occupancy rule) and nothing else structural. Mage Knight,
even after amputating its hex board and its resistance math, still asks for
two compounding gaps rather than one, plus a change to the arithmetic grammar
itself, plus a heavier-than-usual content-authoring burden per card and per
fight. It is worth attempting only if hex-grid geometry is wanted as a
standalone engine feature in its own right — otherwise rank it behind both
other deckbuilder candidates, not alongside them.
