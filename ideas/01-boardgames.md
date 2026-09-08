# 01 — Any board game as JSON

> *Can we improve the engine so far that it is possible for us to take any
> boardgame rule set and just turn it into a json, and then have the board game
> be simulated?* — `IDEAS.md`

**In progress.** Lost Cities and chess shipped.

## The honest boundary

"Any board game" is not a reachable target. What is:

> **Any board game whose rules are a finite set of declarative conditions over
> pieces, zones and numbers, with no free-form negotiation, no real time, and no
> rules text that references itself.**

That covers chess, checkers, solitaire, Knizia's numbers games, most euros and a
large playable subset of Hearthstone. It does not cover full Magic — the
comprehensive rules are a programming language with a priority stack and
replacement effects — and it does not cover games whose interest is social.

**Each target game names one missing capability.** Build to the game, not to the
abstraction; when two games ask for the same thing, that is the signal to
generalise.

## The ladder

| Target | Names | State |
|---|---|---|
| **Knizia (Lost Cities)** | two seats; scoring functions; drop legality | **done** — seats, `sum:`/`max:`/products, `accepts` |
| **Chess** | per-piece movement geometry; blocking; check | **done** — `patterns`, `geometry.lua`, capture, castling, check. Checkmate is [08](08-grid-movement-notation.md)'s own milestone |
| **Checkers** | move a piece already on the board; capture; chained moves | *partly* — chess brought movement, capture and ownership. Left: **the square a move passes over** |
| **Klondike** | ordered stacks; move a run | *partly* — `accepts` and `fan` are built; reordering and the reach half are not |
| **Hearthstone** | triggered abilities; buffs | not started — `turn.action` is the only trigger |

## Gap 1 — the squares a move passes over (checkers)

A checkers jump is `[2,2]`, and it takes the piece it flies *past* — a square
that is neither where the piece started nor where it lands.

**This file said no word could name that square. It was wrong** (probed
2026-09-08), and both halves — asking about the mid square and taking the piece
on it — work today:

```json
"patterns": { "hop_ne": { "vectors": [[2, 2]] }, "back_sw": { "vectors": [[-1, -1]] } },
"abilities": [
  { "key": "hop",
    "moves": [{ "patterns": ["hop_ne"], "fill": "empty",
                "where": ["count:piece@back_sw == 1"] }],
    "action": ["move_to:target", "destroy:back_sw"] }
]
```

An empty mid square offers no jump; with a victim on d4 the jump to e5 is
offered, and taking it removes the victim. Two things that were built for other
reasons meet: **a pattern is already a scope** (`entities_in_scope` has a branch
for `pattern_defs`, so `@back_sw` names whoever stands there), and **the anchor
follows the piece** — `where` is asked with `anchor = sid`, so the pattern is
read from the *destination*; then `move_to:target` runs first in the action, so
`pattern_slots`' fallback to `c.slot_id` is the landing square by the time
`destroy:back_sw` is read. The same pattern names the same square twice, for two
different reasons.

Castling through check is the asking half alone and needs nothing either — an
absolute pattern named as a scope is `count:piece@castle_path`.

### The word, if it is ever wanted — **only implement when needed**

The cost of the spelling above is **one rule per direction**. A pattern is a set
of vectors and the mid square depends on which vector was taken, so
`[[2,2],[-2,2]]` in one pattern would make `@back_sw` name a square the piece
never flew over. A checkers man is 2 rules and 4 patterns; a king is 4 and 8.
Verbose, correct, and it ships today.

A word would collapse that to one rule: *the squares this move passed over*,
anchored on the move actually made. It is not free — `geometry.reach` returns a
flat list of slot ids and would have to report which vector produced each
square, which changes what a pure function hands back, and interpolation is only
defined for vectors that are a line (a knight's `[1,2]` has no meaningful
midpoint). **Do not build it until checkers is written and the four-rule version
has actually been read.** If it reads fine, the word is not wanted.

### What is genuinely left

**Chained jumps**: the move action re-pushes a targeting phase while more jumps
exist. One move per piece per turn is already the default — what bounds a turn
is the handover, not the piece being spent — so the chain is the exception and
has to say so. This is a flow question, not a targeting word, and it is the only
part of this gap that needs anything new.

**Milestone: checkers plays end to end, without forced-capture rules.**

## Gap 3 — ordered stacks and drop legality (Klondike)

Klondike is the sharpest test of "is this an engine or a card game", because it
uses almost none of what ravel has — no costs, no phases to speak of, no stats —
and all of what it lacks.

Built: **order** (`zone.cards` was always an array; what was missing was
anything that *drew* the order, and `fan` does), **drop legality** (`accepts` on
the destination — Klondike expected to be its first customer and Lost Cities got
there first), and the **tableau layout**, as a style rather than a zone type.

Left:

- **Reordering within a stack has no verb.**
- **Move a run**: dragging the 9♠ off a tableau takes the 8♥ and 7♠ with it. A
  new action — the acting card *and every card above it in its zone* move
  together.
- **The reach half**: the drop target is the *top card*, not a slot. Lost Cities
  never asked, because an expedition is targeted as a zone and its cards are
  never touched once played. A render change plus a hit-test change, both in the
  presentation layer, plus `has_room` returning true for an unbounded fan.

**Rank and colour are data, not art.** `card_stats: { rank: 7 }` and a
`red`/`black` tag on the templates. Do not let the renderer's colour become a
rules input.

Klondike is 52 templates: generate them with a script and check the generator
in — it is also the answer for any future deck-of-cards game.

**Milestone: Klondike is winnable and the win is detected.**

## Gap 5 — triggers (Hearthstone-class)

`turn.action` is the only trigger, and it fires for all board cards on a round
wrap. A creature-combat game needs "when a card enters play", "when this dies",
"when a beast is summoned". [18](18-legends-of-runeterra.md) names the same
absent moment from its own side: `activate` is the click moment, and yet
`activate_zone` runs those same lists with no click — a word doing two jobs.

**A small event bus in `flow`, with a fixed, closed set of events** — this is
where an open-ended design would let the engine sprawl. `enters`, `leaves`,
`dies`, `damaged`, `round_start`, `round_end`, `played`, `activated`, fired from
the handful of places that already exist.

Two hard rules, both learned from every card game engine that got this wrong:

1. **Triggers queue, they never recurse.** A trigger fired during a trigger's
   resolution goes on a queue drained by `settle`, under its existing 64-step
   budget. This is the whole reason not to fire them inline at the mutation
   site. [27](27-reactions-and-the-stack.md)'s stack is the same discipline and
   should be looked at first — a trigger may turn out to be a reaction that
   nobody may answer.
2. **No continuous effects in v1.** Auras are a recomputation problem, not an
   event problem, and they are the thing that turns a small engine into a large
   one. Model buffs as *applied stat changes* with a matching `leaves` trigger
   that reverses them.

**Milestone: a 20-card Hearthstone-like with summon/deathrattle, two players.**

## What the two shipped ones cost

**Chess overtook checkers** because the notation question was the interesting
one and chess is where it had to be answered. The `slide:`/`step:`/`leap:` verbs
this file originally proposed lost to direction vectors in a `patterns` block:
they make the engine learn a word per movement *kind* and force blocking to be
guessed from an offset's shape.

**One correction, and it is recorded here because this file got it wrong twice.**
Check is not a computed tag — a computed tag reads one card's own stats, and "am
I attacked" depends on every enemy piece's reachable set. But the fallback this
file then proposed, *a `threat` count stamped on every square*, is also wrong:
it is the engine deciding chess is special. What shipped is the `@reach` scope,
so check is something the game file says. See [08](08-grid-movement-notation.md).

**Lost Cities named seats**, which this document originally claimed the
foundation already gave you. It did not. Two content tricks worth stealing: the
route marker is tagged `wager` so `count:wager` *is* the multiplier with no
arithmetic, and a destination marker in each expedition gives the empty case
something to target.

*Set scoring* — "n points per complete set of k distinct tags" — is still not
directly expressible, and still should not get its own operator. Express it as a
computed tag plus a card that reads it.

## Order, non-goals, and the standing risk

Next: **checkers** (small, once the path is named) · **Klondike** (medium) ·
**chess, legal** — move generation and checkmate (medium) · **a
Hearthstone-like** (large).

Each step ships a playable game in `game/games/` and its own test. **Every board
game gets a scripted-game test**: a fixed sequence of moves with an asserted end
state — fool's mate for chess, a forced double-jump for checkers, a seeded
winnable Klondike deal. That is a much stronger regression net than unit tests
and costs ten lines each.

**Non-goals:** real-time anything, rules-complete Magic, AI opponents, rules
text parsed from English.

**Standing risk.** The engine is small because of *when in doubt, decks and
cards*. Five new subsystems is exactly how that dies. The discipline that keeps
it alive: **no capability enters the engine until a second target game asks for
it**, and anything a card can already express stays a card.
