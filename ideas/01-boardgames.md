# Idea 01 — Any Board Game as JSON

> *Can we improve the engine so far that it is possible for us to take any
> boardgame rule set and just turn it into a json, and then have the board game
> be simulated?* — `IDEAS.md`

**Status:** in progress — **Lost Cities and chess shipped** · **Size:** large, but strictly staged

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
| **Checkers** | Move a piece already on the board; capture; chained moves | *partly* — chess brought movement, capture and ownership. What is left is **the square a move passes over**: a jump takes the piece it flies past, and nothing can name it |
| **Chess** | Per-piece movement geometry; blocking; check | **done** — `patterns`, `geometry.lua`, capture, castling ([08](08-grid-movement-notation.md)). Check and checkmate are a separate milestone, still open |
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

- ~~`place_in_slot` refuses occupied slots~~ — **done** as
  `place_in_slot(card, slot, on_occupied)`: `"refuse"` (default), `"destroy"`,
  or a zone key to move the occupant into, which is how chess's captured-pieces
  tray works.

**What is genuinely left, and it is one thing: the squares a move passes over.**

A checkers jump is `[2,2]`, and it takes the piece it flies *past* — a square
that is neither where the piece started nor where it lands. Nothing in the
engine can name that square. Chess never asked, because a piece on the path just
stops the move: the path is consulted and discarded inside `geometry.reach`, and
nothing above ever sees it.

**Three unbuilt rules want the same word**, which is this document's own signal
to generalise:

| Rule | Asks about the path |
|---|---|
| A checkers jump | is there exactly one enemy on it, and take that piece |
| En passant | did a pawn pass through this square last turn |
| Castling through check | is any square on it attacked |

So: `geometry.reach` already walks the squares between origin and destination —
**return them**, and expose them as a scope anchored on the move being
considered (`count:enemy@path`, and a `destroy:path` style target for the
taking). This is close kin to [08](08-grid-movement-notation.md)'s missing
*anchor word*, and the two should be designed together rather than growing two
different ways to say "relative to something other than me".

The other half is **chained jumps**: the move action re-pushes a targeting phase
while more jumps exist. One move per piece per turn is already the default —
what a turn is bounded by is the handover, not the piece being spent — so the
chain is the exception and has to say so.

**Milestone: checkers plays end to end, without forced-capture rules.**

## Gap 2 — Spatial vocabulary (chess) — **shipped** (`5c1875e`)

**Done, and by a different notation than the one drafted here.** The
`slide:`/`step:`/`leap:` verbs this section proposed were compared against four
alternatives in [08](08-grid-movement-notation.md) and lost: they make the engine
learn a word per movement *kind*, and they force blocking to be guessed from an
offset's shape. What shipped declares direction vectors in a top-level `patterns`
block and reads them as *directions*, so blocking, leaping and range are one
concept rather than four. `geometry.lua` exists as this section predicted, below
the presentation line, pure and headless.

Chess plays with 32 pieces, blocking, capture into a per-seat tray and castling.
[08](08-grid-movement-notation.md) is the live document; [DONE.md](DONE.md) has
the summary. The rest of this section — check and checkmate — is still true and
still unbuilt.

### Check and checkmate — read this before promising chess

Check detection is "after my move, can any enemy piece reach my king's square" —
that is one call to `geometry.reach` per enemy piece, cheap and easy.
**Checkmate is different**: "does the opponent have any legal move that leaves
their king un-attacked" requires generating every legal move for a side and
testing each against a hypothetical board. The engine can actually do this
honestly — `entity.snapshot`/`restore` (`game/entity.lua:49`) is exactly a
make/unmake move, and it is already fast enough — but it is a real subsystem and
it should be its own milestone, not smuggled into the first one.

**Capture-the-king chess shipped, as recommended**, and castling came with it
because it turned out to be the thing that asked for absolute patterns rather
than a special case bolted on. What is left is unchanged: `legal_moves()` and
checkmate, as their own milestone.

One correction from building it, in [08](08-grid-movement-notation.md): check is
**not** a computed tag, however much it looks like one. A computed tag reads one
card's own stats, and "am I attacked" depends on every enemy piece's reachable
set. Stamp it as a **stat** instead — a `threat` count per square, recomputed
after each move — which is the route `rank` already took, and which hands
tactical games a threat map for the same price.

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
2. ~~**Chess, capture-the-king**~~ — **done**, and it overtook checkers because
   the notation question ([08](08-grid-movement-notation.md)) was the
   interesting one and chess is where it had to be answered. `geometry.lua`
   exists; castling came with it.
3. **Checkers** — needs the jumped-over square, which chess never asked for.
   (small, once that is named)
4. **Klondike** — ordered stacks + run moves (`accepts` already done). (medium)
5. **Chess, legal** — move generation, check, checkmate. (medium)
6. **Hearthstone-like** — triggers. (large)

Each step ships a playable game in `game/games/` and its own test. **Every board
game gets a scripted-game test**: a fixed sequence of moves with asserted end
state (fool's mate for chess, a forced double-jump for checkers, a seeded
winnable Klondike deal). That is a much stronger regression net than unit tests
and it costs ten lines each. Chess's is in `tests/run.lua`; new ones belong in
`tests/integration/`, one file per subject.

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
