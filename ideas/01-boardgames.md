# Idea 01 — Any Board Game as JSON

> *Can we improve the engine so far that it is possible for us to take any
> boardgame rule set and just turn it into a json, and then have the board game
> be simulated?* — `IDEAS.md`

**Status:** in progress — **Lost Cities shipped** · **Size:** large, but strictly staged

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

| Target | Names the missing capability | State |
|---|---|---|
| **Knizia (Lost Cities)** | Two seats; scoring functions; drop legality | **done** — seats, `sum:`/`max:`/products, `accepts` |
| **Checkers** | Move a piece already on the board; capture; chained moves | *partly* — activation takes targets and `move_to:target` moves the acting card; capture still needs `place_in_slot` to allow an occupied slot |
| **Chess** | Per-piece movement geometry; blocking; check | not started — no spatial vocabulary at all |
| **Klondike** | Ordered stacks; move a run | *partly* — `accepts` is built (it was Lost Cities that asked); zones are still unordered lists with `move_top` |
| **Hearthstone** | Triggered abilities; buffs | not started — `on_turn` is the only trigger |

---

## Gap 1 — Pieces that move (checkers)

**Two thirds of this is already built** — this section was written against an
older engine and both halves it asked for arrived for other reasons.

- ~~`flow.activate(card_id, targets)`~~ — **done** (`13b27b7`, before any of
  this ladder). Activation honours `activate_target` and flow enforces the
  count, so "select my knight, then select a square" *is* expressible.
- ~~A `move_self_to_target` action~~ — **done**, as `move_to:target`: the
  acting card moves into the chosen target's zone or slot. Lost Cities asked
  for it ("advance the expedition, or discard it"), which is the discipline
  working — no new verb, and `target` was already a scope word.

**What is genuinely left:**

- `zones.place_in_slot` **refuses occupied slots**.
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

> **Superseded by [idea 08](08-grid-movement-notation.md).** The `slide:`/`step:`/
> `leap:` verbs below were compared against four other notations and lost: they
> make the engine learn a word per movement *kind*, and they force blocking to be
> guessed from an offset's shape. The chosen design declares direction vectors in
> a top-level `patterns` block and reads them as *directions*, which makes
> blocking, leaping and range one concept instead of four. The rest of this
> section — the gap it names, and the `geometry.reachable` shape — still holds.

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
- ~~**Drop legality is relational**~~ — **done.** `accepts` on the destination
  is built: `{ "rank@target": { "equals": 8 } }` plus a `black` tag in the
  target spec is the whole of "a red 7 goes on a black 8". Klondike expected to
  be its first customer; Lost Cities got there first and paid for it.
- **Move a run**: dragging the 9♠ off a tableau takes the 8♥ and 7♠ with it.
  New action `move_stack_to_target`: the acting card *and every card above it in
  its zone* move together.
- **Rank and colour are data, not art.** Put `card_stats: { rank: 7 }` and a
  `red`/`black` tag on the templates. Do not let the renderer's colour become a
  rules input — see [placeholder art](DONE.md), which makes the
  same point from the other side.
- **Tableau zones need a new zone type** `stack`: ordered, cards drawn
  overlapping with a visible offset, drop target is the *top card*, not a slot.
  This is a render change plus a hit-test change, both in the presentation
  layer, plus `zones.has_room` returning true for it (unbounded).

Klondike is 52 templates. Generate them with a script into
`game/games/klondike.json` rather than hand-writing them, and check the
generator in — it is also the answer for any future deck-of-cards game.

**Milestone: Klondike is winnable and the win is detected.**

## Gap 4 — Scoring functions (Knizia) — **shipped**

Lost Cities is in `game/games/lost_cities.json`, generated by
`tools/make_lost_cities.py`. What it needed and got — comparisons in either
direction and against another subject, products in numeric slots, and `accepts`
on a destination — is recorded in [DONE.md](DONE.md). The rest of this section
is the original plan, kept because the ladder above and below it still applies.

**Shipped** (`b606810`) — `game/games/lost_cities.json`, generated by
`tools/make_lost_cities.py`.

A Knizia numbers game is 80% scoring rules, and `count:<tag>` alone could
express none of them. What it took:

- `sum:` and `max:` from the foundation, plus **products** (`:x:`) — because
  an expedition scores `(sum − 20) × wagers` and repeated addition cannot
  stand in for a multiplication. It distributes into two ordinary actions
  rather than needing a nested expression.
- **Comparisons the other way and against another subject** — the winner is
  `{ "stat": "score@north_side", "at_least": "score@south_side" }`.
- **Seats**, which this document originally claimed the foundation already
  gave you. It did not: 00's *first* draft had seat-based `@me`/`@opponent`
  scopes and superseded itself, so nothing shipped modelled a seat at all.
  Lost Cities named that gap, which is this document's own framing working.
- **`accepts`**, for the ascending rule (see gap 3 above).

Two content tricks worth stealing: the route marker is tagged `wager` so
`count:wager` *is* the multiplier `1 + wagers` with no arithmetic, and a
destination marker in each expedition gives the empty case something to target.

*Set scoring* — "n points per complete set of k distinct tags" — is still not
directly expressible, and still should not get its own operator. Express it as
a computed tag plus a card that reads it.

**Milestone: Lost Cities, two players hot-seat, correct scoring. — done.**

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

1. ~~**Lost Cities + hot-seat**~~ — **done.** It named seats, `accepts`,
   products and subject-valued comparisons, and every one of those landed as
   vocabulary rather than as a special case.
2. **Checkers** — board movement + capture. (small)
3. **Chess, capture-the-king** — `geometry.lua`. (medium)
4. **Klondike** — ordered stacks + run moves (`accepts` already done). (medium)
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
