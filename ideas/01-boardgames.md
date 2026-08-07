# Idea 01 — Any Board Game as JSON

> *Can we improve the engine so far that it is possible for us to take any
> boardgame rule set and just turn it into a json, and then have the board game
> be simulated?* — `IDEAS.md`

**Status:** not started · **Blocked on:** [02 stage A](02-multiplayer.md#stage-a--hot-seat) for every two-player target · **Size:** large, but strictly staged

---

## The honest boundary

"Any board game" is not a reachable target and shouldn't be the goal. What *is*
reachable, and worth aiming at:

> **Any board game whose rules are a finite set of declarative conditions over
> pieces, zones and numbers, with no free-form negotiation, no real time, and no
> rules text that references itself.**

That covers chess, checkers, solitaire, Knizia's numbers games, most euros, and
a large playable subset of Hearthstone. It does not cover full Magic (the
comprehensive rules are a programming language with a priority stack and
replacement effects; a rules-complete implementation is a multi-year project on
its own) and it does not cover games whose interest is social.

The useful framing: **each target game names one missing capability.** Build to
the game, not to the abstraction. When two games ask for the same thing, that is
the signal to generalise.

---

## Capability ladder

| Target | Names the missing capability | Engine has today |
|---|---|---|
| **Checkers** | Move a piece already on the board; capture; chained moves | Cards only move by being *played from hand* |
| **Chess** | Per-piece movement geometry; blocking; check | No spatial vocabulary at all |
| **Klondike** | Ordered stacks; card-to-card drop legality; move a run | Zones are unordered lists with `move_top` |
| **Knizia (Lost Cities / Ra)** | Scoring functions over sets | `count:<tag>` only counts |
| **Hearthstone** | Triggered abilities; buffs; two players | `on_turn` is the only trigger |

---

## Gap 1 — Pieces that move (checkers)

The engine's only path from board to board is `flow.play_card`. A card already
in a grid zone can be *activated* (`flow.activate`, `game/flow.lua:352`) but
activation takes **no targets** and runs `on_activate` with an empty target
list. So "select my knight, then select a square" cannot be expressed.

**Change:**

- `flow.activate(card_id, targets)` — mirror `play_card`'s target handling:
  honour `def.target` (min/max/type/zones), enforce the count in flow so the
  CLI, debug server and GUI all agree (`game/flow.lua:319` is the pattern).
- New action `move_self_to_target` — the acting card moves into
  `ctx.targets[1]` when that target is a slot. `move_to` (`game/actions.lua:135`)
  already does slot placement for the play path; this is the same body reached
  from activation.
- `zones.place_in_slot` (`game/zones.lua:161`) **refuses occupied slots**.
  Capture needs an opt-in: `place_in_slot(card_id, slot_id, on_occupied)` where
  `on_occupied` is `"refuse"` (default, unchanged), `"destroy"`, or a zone key
  to move the occupant to (a captured-pieces tray).
- Movement must not exhaust the piece the way abilities do — or rather, for
  checkers it must, and that is exactly right: one move per piece per round is
  the *default* and a chained jump is the exception. Chained jumps = the move
  action re-pushes a targeting phase while more jumps exist.

**Milestone: checkers plays end to end, without forced-capture rules.**

## Gap 2 — Spatial vocabulary (chess)

Slots know `slot_idx` and their zone knows `grid = {cols, rows}`
(`game/zones.lua:33`). Everything needed to compute geometry is present; nothing
reads it. Targeting eligibility (`game/targeting.lua:12`) is "every empty slot",
optionally filtered by zone.

**Change — a movement spec on the card template**, in the engine's existing
`op:param` string style (DESIGN.md forbids nested arrays and code-like
expressions, so this must stay flat strings):

```json
{ "key": "rook",   "move": ["slide:orthogonal"] }
{ "key": "bishop", "move": ["slide:diagonal"] }
{ "key": "queen",  "move": ["slide:orthogonal", "slide:diagonal"] }
{ "key": "knight", "move": ["leap:1:2"] }
{ "key": "king",   "move": ["step:orthogonal:1", "step:diagonal:1"] }
{ "key": "pawn",   "move": ["step:forward:1"], "capture": ["step:diagonal_forward:1"] }
```

Verbs: `step:<dir>:<n>` (up to n squares, blocked by anything), `slide:<dir>`
(any distance until blocked), `leap:<dx>:<dy>` (ignores blocking, all eight
reflections). Directions: `orthogonal`, `diagonal`, `forward`, `any`.
`forward` needs a facing, which comes from the owner (foundation doc) — white
moves +row, black −row.

This lives in a new module `geometry.lua`, below the presentation line, whose
whole job is `geometry.reachable(card_id) -> { slot_id, ... }`, split into
"empty destinations" and "capture destinations". `targeting.start` calls it when
the spec says `"type": "move"`. One module, one function, no state — it stays
testable headless and it keeps `zones.lua` from growing a second personality.

**Milestone: chess plays, king-capture rules (no check detection).**

### Check and checkmate — read this before promising chess

Check detection is "after my move, can any enemy piece reach my king's square" —
that is one call to `geometry.reachable` per enemy piece, cheap and easy.
**Checkmate is different**: "does the opponent have any legal move that leaves
their king un-attacked" requires generating every legal move for a side and
testing each against a hypothetical board. The engine can actually do this
honestly — `entity.snapshot`/`restore` (`game/entity.lua:49`) is exactly a
make/unmake move, and it is already fast enough — but it is a real subsystem and
it should be its own milestone, not smuggled into the first one.

Recommendation: ship **capture-the-king chess** first (fully playable, teaches
the geometry layer), then add `legal_moves()` and checkmate as a follow-up. Do
not start with castling, en passant and promotion; each is a special-case card
or trigger and they are the least interesting part.

## Gap 3 — Ordered stacks and drop legality (solitaire)

Klondike is the sharpest test of "is this an engine or a card game", because it
uses almost none of what ravel has (no costs, no phases to speak of, no stats)
and all of what it lacks.

- **Order matters.** `zone.cards` is an array, so order exists, but only
  `move_top` (`game/zones.lua:74`) respects it and nothing renders a fan.
- **Drop legality is relational**: a card may land on another card only if it is
  one rank lower and the opposite colour. This is the `accepts` relation from
  the foundation doc — its first real customer.
- **Move a run**: dragging the 9♠ off a tableau takes the 8♥ and 7♠ with it.
  New action `move_stack_to_target`: the acting card *and every card above it in
  its zone* move together.
- **Rank and colour are data, not art.** Put `card_stats: { rank: 7 }` and a
  `red`/`black` tag on the templates. Do not let the renderer's colour become a
  rules input — see [03-placeholder-art](03-placeholder-art.md), which makes the
  same point from the other side.
- **Tableau zones need a new zone type** `stack`: ordered, cards drawn
  overlapping with a visible offset, drop target is the *top card*, not a slot.
  This is a render change plus a hit-test change, both in the presentation
  layer, plus `zones.has_room` returning true for it (unbounded).

Klondike is 52 templates. Generate them with a script into
`game/games/klondike.json` rather than hand-writing them, and check the
generator in — it is also the answer for any future deck-of-cards game.

**Milestone: Klondike is winnable and the win is detected.**

## Gap 4 — Scoring functions (Knizia)

A Knizia numbers game is 80% scoring rules. `count:<tag>` cannot express "the
highest expedition value", "3 points per set of three", "−20 if you started an
expedition and scored under 20".

The foundation doc's `sum:` and `max:` cover most of it. The remaining shape is
*set scoring* — "n points per complete set of k distinct tags". Resist inventing
an operator: express it as a computed tag plus a card that reads it, or accept
one narrow addition:

```json
"end_conditions": [ { "score": "sum:value@expedition_red", "at_least": 20, "then": [...] } ]
```

Pick **Lost Cities** as the target: one scoring rule per expedition, no spatial
component at all. It is the cheapest possible proof that the engine handles a
real published game, and it validates the scope work under load with almost no
new *scoring* code.

**It is two-player, and the foundation does not give you that.** This document
originally said it did, on the strength of [00](00-foundation-scope.md)'s first
draft, which had seat-based `@me` / `@opponent` scopes. That draft superseded
itself: a scope became a plain zone key or tag, deliberately, and nothing that
shipped models a seat. Concretely, today `flow.play_card` never checks the
active phase's zone (either player could play from either hand) and `plays`
always lands on the first `player`-tagged card whoever is playing. So Lost
Cities *names the missing capability*, exactly as this document's own framing
demands, and that capability is seats — build it with
[02 stage A](02-multiplayer.md#stage-a--hot-seat), not before it.

**Milestone: Lost Cities, two players hot-seat, correct scoring.**

## Gap 5 — Triggers (Hearthstone-class)

`on_turn` (`game/flow.lua:142`) is the only trigger, and it fires for all board
cards on a round wrap. A creature-combat game needs "when a card enters play",
"when this dies", "when a beast is summoned".

**Change:** a small event bus in `flow`, with a fixed, closed set of events —
this is the place where an open-ended design would let the engine sprawl.

```json
"triggers": [
  { "on": "enters",  "tag": "beast", "scope": "me", "then": ["gain_target_stat:attack:1"] },
  { "on": "dies",    "self": true,                  "then": ["gain:soul_shard"] }
]
```

Events: `enters`, `leaves`, `dies` (hp reaches 0), `damaged`, `round_start`,
`round_end`, `played`, `activated`. They fire from the handful of places that
already exist — `zones.move_card`, `zones.destroy_card`, `change_stat`,
`flow.settle`'s round boundary. Two hard rules, both learned from every card
game engine that got this wrong:

1. **Triggers queue, they never recurse.** A trigger fired during a trigger's
   resolution goes on a queue drained by `settle`, under `settle`'s existing
   64-step budget (invariant 3). This is the whole reason not to fire them
   inline at the mutation site.
2. **No continuous effects in v1.** Auras ("all your beasts have +1 attack while
   this is in play") are a recomputation problem, not an event problem, and they
   are the thing that turns a small engine into a large one. Model buffs as
   *applied stat changes* with a matching `leaves` trigger that reverses them.
   Revisit only if a target game genuinely can't be expressed that way.

**Milestone: a 20-card Hearthstone-like with summon/deathrattle, two players.**

---

## Suggested order

1. **Lost Cities + hot-seat** — one task, not two: the game names seats as its
   missing capability. Scoring is ~no new engine code. (see [02 stage A](02-multiplayer.md#stage-a--hot-seat))
2. **Checkers** — board movement + capture. (small)
3. **Chess, capture-the-king** — `geometry.lua`. (medium)
4. **Klondike** — ordered stacks + `accepts` + run moves. (medium)
5. **Chess, legal** — move generation, check, checkmate. (medium)
6. **Hearthstone-like** — triggers. (large)

Each step ships a playable game in `game/games/` and its own test in
`tests/run.lua`. **Every board game gets a scripted-game test**: a fixed
sequence of moves with asserted end state (fool's mate for chess, a forced
double-jump for checkers, a seeded winnable Klondike deal). That is a much
stronger regression net than unit tests and it costs ten lines each.

## Non-goals

Real-time anything. Rules-complete Magic. AI opponents (a move generator makes a
naive one possible for chess/checkers, but it is a separate idea). Rules text
parsed from English.

## Standing risk

The engine is small because of invariant 7 — *when in doubt, decks and cards*.
Five new subsystems is exactly how that invariant dies. The discipline that
keeps it alive: **no capability enters the engine until a second target game
asks for it**, and anything a card can already express stays a card. Geometry
and triggers earn their place; almost nothing else on this page should.
