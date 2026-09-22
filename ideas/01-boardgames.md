# 01 — Any board game as JSON

> *Can we improve the engine so far that it is possible for us to take any
> boardgame rule set and just turn it into a json, and then have the board game
> be simulated?* — `IDEAS.md`

**In progress.** Lost Cities, chess and checkers shipped.

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
| **Checkers** | move a piece already on the board; capture; chained moves | **done** — `checkers.json`, hand-written, no generator. The jumped square needed no word; the chain is a route back to the same seat. Left: the button that ends a chain, which one widened word would delete |
| **Klondike** | ordered stacks; move a run | *partly* — `accepts` and `fan` are built; reordering and the reach half are not |
| **Hearthstone** | triggered abilities; buffs | not started — `turn.action` is the only trigger |

## Gap 1 — the squares a move passes over (checkers)

**Shipped.** `game/games/checkers.json`, 223 lines, hand-written, and
`tests/integration/checkers.lua` plays a game through a double jump, a crowning,
a king's backward chain and the win.

A jump takes the piece it flies *past*, and it needed no word. Two things built
for other reasons meet: **a pattern is already a scope**, and **the anchor
follows the piece** — `where` is asked with the candidate square as the anchor,
so `@enemy.down_right` from the landing square is the victim; then
`move_to:target` runs first in the action, so `pattern_slots`' fallback to
`c.slot_id` is that same landing square by the time the capture line is read and
the same words name the same square twice:

```json
{ "key": "jump_left",
  "moves": [{ "patterns": ["leap_up_left"], "fill": "empty",
              "where": ["tagged:piece@enemy.down_right"] }],
  "action": ["move_to:target", "move:enemy.down_right:taken", …] }
```

### The word that would collapse the directions is still not wanted

The cost is one **ability** per direction rather than one rule, which is worse
than this file predicted: a rule's `where` can name the square flown over, but
the *action* cannot, and an action shared by two rules would capture down the
diagonal the piece did not take. A man is 2 jump abilities, a king 4.

**Read in the file, that is fine.** The four sit under each other, differ in a
compass point, and "does a king jump backwards" is answered by counting them.
The word would save perhaps twenty lines of one game and cost `geometry.reach`
its purity. Still no — and now it has been read rather than imagined.

### The chain is a route, not a targeting word

Chained jumps turned out to be the flow question this file said they were, and
the flow words already existed. A jump leaves `chaining` standing on the piece;
the phase's own route reads it and comes back to the **same** seat
(`{ "when": "max:chaining@mine.board >= 1", "then": "red_move", "seat": "same" }`);
`on_enter` clears it when a turn actually begins, which a loop that keeps the
player does not run. One clause on every piece ability,
`max:chaining@mine.board == chaining@self`, is what stops anybody *else* moving
mid-chain: nought matches nought while nobody is jumping, and once somebody is,
only they match.

### What it cost: a button, and the one word that would delete it

**A chain cannot end itself**, so the game carries a *Done jumping* button. The
question "does this piece still have a jump" is exactly `aims:`, and `aims:`
already answers it correctly from the square just landed on — probed on a live
board, `aims:jump_right` is 1 after the first jump of a double and 0 after the
second. Two things stand between that and no button:

- an **amount** may be a number, a `count:`/`sum:` measure or a compute, and
  `aims:` is refused by name — so `stat_set:chaining@self:aims:jump_left` (then
  `stat_gain:` for the other directions) does not parse, though every part of
  what it asks for is built;
- a **compute** is bound before the action runs, so a compute summing the
  directions would be measured from the square the piece has not left yet.

Widening the amount grammar to accept `aims:` is the whole fix, and it is
measured where every other amount is: when that line runs. It would also make a
chain *forced* — with the button gone, a piece that still has a jump is the only
legal move there is — which is half of the forced-capture rule falling out for
nothing. The other half, declining the first jump, **is a rule after all** — the
rulebook makes a capture compulsory whenever one is on offer, so a step is
illegal while any jump is. Its one line is a `needs` on `step` saying no jump
aims anywhere, which is the same widened amount read the other way round, so
both halves ship together or neither does.

**Milestone met: checkers plays end to end, without forced-capture rules.**

### Two bugs found playing it

**The red men do not sit in the middle of their squares; everything else
does.** Not yet reproduced off a screen, and the obvious causes are ruled out:
both men are one `per_player` asset differing only in a colour word
(`circle:crimson:#7a5230` / `circle:white:#7a5230`), both parse to the same
`{shape = "circle", fg, bg}`, `art.paint` draws a circle at the texture's own
centre, the `piece` style hides title, border and plate for both, and the board
zone has no label band to push one end of the grid down. So the difference is
downstream of the spec, and **the next step is a look at the running board**,
not more reading. [Assumption: it is the men rather than the red *side* — the
note says "men", and red's kings are a different asset.]

**Forced capture**, above: the rule the file says it ships without, now asked
for. It is the second customer for the widened amount, and the reason that item
outranks its own button.

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

## What the shipped ones cost

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

**Checkers cost nothing but the chain.** Twenty-four pieces, two templates, and
the only engine question in it was how a turn comes back to the same player. The
board half — diagonal geometry, a rank counted from the owner's own side, a man
crowned by `transform`, art per seat on one template — was chess's, already
paid for.

*Set scoring* — "n points per complete set of k distinct tags" — is still not
directly expressible, and still should not get its own operator. Express it as a
computed tag plus a card that reads it.

## Order, non-goals, and the standing risk

Next: **Klondike** (medium) ·
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
