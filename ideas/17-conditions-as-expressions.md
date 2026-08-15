# 17 — A condition is one string

**Status:** not started, and it needs a decision before it needs code ·
**Size:** large — the engine change is small, the migration is every game file,
and the design question is the format's biggest open one.

> *Consider instead of complex `{stat "at_least": 8}` struct to just use small
> eval blocks, which look more like `"a.b@c.d > e.f@g.h"`, allowing simple math
> and lookup logic. This might just be easier, and we can parse this on
> validation and generate lambda functions for it all instead of having to write
> unique special cases for every field type.*

This is the same finding [10](10-schema-document.md) measured from the outside,
arriving from the inside. Finding 5 — *one condition, three spellings, and the
site decides which is legal* — is the biggest thing the schema pass turned up
and the one it recommended starting from, and finding 4 (`stat` is a field name
that does not mean a stat) and finding 6 (`ROUTE_FIELDS` and `END_FIELDS` are
the same table) both dissolve into it.

---

## What already exists, and it is most of it

**The operands are built.** `predicate.parse_subject` (`predicate.lua:61`) reads
`[<fn>:]<arg>[@<quant>.<owner>.<scope>]`, which is the whole of the left-hand
side: `sum:value@mine.red`, `count:king@enemy.reach`, `hp@each.follower`,
`moves_made@w_rook_h_home`. Nothing about that changes.

**The right-hand side is already an operand too.** `bound()`
(`predicate.lua:310`) takes a number *or* another subject, which is what lets a
card compare itself to what it is being played onto. The comparison is therefore
already `subject <op> subject`; it is just spelled as a map.

**So what is actually being proposed is an infix spelling of a thing the engine
already evaluates**, plus arithmetic, which it does not. Those two halves are
worth deciding separately — see *The arithmetic question*.

## One thing the grammar is missing, found by building an ending screen

**A condition cannot name a seat.** The owner word is `mine` / `enemy` /
`anyone` (`OWNERS`, `predicate.lua:33`), all three relative to
`zones.active_seat()`. That is right for a rule a player is playing — and there
is no way to write *white's*, absolutely, at a moment when nobody in particular
is to move.

It cost twice in one afternoon ([07](07-presentation.md) gap 6). Chess's ending
could not be an `end_condition`, because at the moment a king is taken "mine" is
whoever moved last, which is an accident of turn order; it became phase routing
instead, since a phase called `white_move` does know its colour. And writing the
winner down needed an absolute handle too, so chess's seat cards gained a tag
each — the trick Lost Cities was already using for `score@north_side`.

**Tagging a seat card is the workaround, and it is a good one**, which is why
this is a paper cut rather than a blocker. But it means every game with seats
writes two words that mean the same thing as the seat key it already declared.
[Assumption: the fix is one line in `owned_by` — an owner word that is not one
of the three known ones and *is* a key in `G.seat_set` matches that seat — plus
the same lookup in `parse_scope`, which is what makes it a decision rather than
a patch: `parse_scope` is documented as pure and testable without a game, and
consulting `seat_set` ends that. Either the grammar gains a game-state
dependency, or seats keep wearing tags.]

## The three shapes it collapses

| Shape | Written | Where it is legal today |
|---|---|---|
| map | `{ "gold": 3 }` | `needs`, `receive.needs`, `challenge.needs`, costs |
| comparison | `{ "max:value@mine.red": { "at_most": 6 } }` | the same four |
| object | `{ "stat": "count:king@taken", "at_least": 1 }` | routing entries, `end_conditions`, computed tags |

One expression form reads the same in all six places:

```json
"needs":  { "gold >= 3": true }                          ← the map form's shape fights it
"needs":  ["gold >= 3", "max:value@mine.red <= 6"]       ← a list of expressions
"end_conditions": [{ "when": "count:king@taken >= 1", "then": ["load_game:menu.json"] }]
```

[Assumption: a `needs` becomes a **list of strings** rather than a map with
`true` values. A map keyed by an expression is the current shape wearing a new
grammar, and it cannot hold the same subject twice — `gold >= 3` and `gold <= 8`
is a range, and a range is an ordinary thing to want. A list also matches
`DESIGN.md`'s allowed form 2, arrays of strings, which no other reading of this
does.]

That last point is the one to weigh honestly: **form 3 exists precisely because
comparisons could not be written any other way**, and DESIGN.md records it as a
deliberate bend with a stated bound. An expression string is a *different* bend
— arguably a smaller one, since arrays of strings are already the format's
second allowed form and action strings are already parsed vocabulary — but it is
a bend, and the document has to be rewritten rather than quietly outgrown.

## The behaviour that must survive, and it is not syntax

This is the acceptance criterion, and it is where a rewrite of `predicate.lua`
would go wrong. Every one of these is a *rule*, not a spelling, and each was
paid for by a bug:

| Rule | Where it is written | What it prevents |
|---|---|---|
| **An absent stat fails every comparison**, `equals: 0` included | `predicate.met` (`predicate.lua:355`), `DESIGN.md:99` | "this rook has never moved" being true of a captured rook |
| **The measuring forms are exempt** — `count:`/`card:` over nothing is 0, `sum:`/`max:` of an empty pool is 0 | same | "these squares are empty" has to be writable |
| **A bare word on the right is a typo, not zero** | `bound()` (`predicate.lua:310`) | every misspelling silently comparing against 0 and passing |
| **An empty `each` scope fails rather than passing vacuously** | `predicate.met` (`predicate.lua:359`) | a cost being free exactly when nothing can pay it |
| **Nothing malformed reaches a raw Lua comparison** | the comment at `predicate.lua:75` | an uncaught error killing the process on peer-supplied content |

A grammar makes those *harder* to state, not easier: `a > b` reads like
arithmetic and invites the reading that a missing `a` is 0. Whatever the parser
produces has to keep answering "absent" differently from "zero", which means the
evaluator still returns a tri-state internally however the string looks.

## Compile at the door, and never with `loadstring`

The note's own suggestion — *parse on validation and generate lambda functions*
— is right about the place and must be careful about the mechanism.

**The place is `declaration.parse`**, which [06](06-schema-and-types.md) gap 3
already names as the boundary worth paying to normalise, and which
[11](11-styles-as-tags.md) used for exactly this shape: resolve once at load,
leave a flat thing behind for the hot path. A condition parsed once into a
closure is strictly better than `parse_subject` running on every read, which is
what happens today — `predicate.total` re-parses its subject string every time a
card's gate is re-derived, which is every frame for every dimmable card in a
hand.

**The mechanism must be a closure built from a fixed grammar, never Lua source
handed to `load`.** A game file arrives from a peer through `net.accept_game`
and is parsed through the very same door (`declaration.lua`), which is the trap
[09](09-composition.md) found for includes and it is sharper here: compiling
attacker-supplied text into Lua would be remote code execution in a program that
already accepts game files from strangers by design. The grammar is small enough
that this costs nothing — a recursive-descent parse into a tree of closures over
`predicate.total` is maybe eighty lines. [Assumption: the parser lives beside
`predicate.parse_subject` rather than in `declaration`, so it stays testable
without a game loaded, and `declaration` only calls it.]

## The arithmetic question, which is the real decision

The note asks for *simple math*, and that is the half that is genuinely new.
`DESIGN.md:66` says: **no s-expressions, no command trees, no arbitrary
expressions**, and the whole schema section exists to keep the format writable
by non-programmers.

Three positions, and they should be chosen between rather than blurred:

1. **Comparison only.** `<subject> <op> <subject|number>`, one operator, no
   nesting. This is exactly what the engine evaluates today, spelled infix. It
   collapses three shapes into one, fixes findings 4, 5 and 6, and adds no
   expressive power at all — which is its strength: nothing new can be written,
   so nothing new can be wrong.
2. **Comparison plus the arithmetic that already exists elsewhere.** Action
   value slots already take a product (`actions.lua:78`'s `amount`):
   `"gain_stat:score:sum:value@mine.red:x:count:wager"`. That `:x:` is arithmetic
   in colon-separated clothing, and it exists because Lost Cities needed
   `(sum − 20) × wagers`. One parser serving both would **delete** a notation
   rather than add one, and that is the strongest argument in this file for going
   past position 1.
3. **General expressions** — `+ - * /`, parentheses, precedence. This is the one
   DESIGN.md refuses, and the refusal has not expired: it is the difference
   between a format and a language, and the moment it lands, every rules bug can
   be an arithmetic bug in a string.

[Assumption: 1, then 2, and never 3 without a game that cannot be written
otherwise — with the test for 2 being that it *replaces* `:x:` rather than
sitting beside it. Two arithmetic notations is worse than either alone, and this
repository has just spent a whole pass (the syntax pass) removing synonyms.]

**Boolean operators are a separate refusal.** `and` is already what a `needs`
list means — every entry must hold — and `or` is the thing that turns a
condition into a program. A card that needs *either* of two things is two
abilities, which the engine now has (`abilities`, shipped).

## What does not become an expression

- **Costs.** `{ "mana": 3 }` on a `play.cost` is not a gate, it is a
  *payment*: it names the stat to subtract and by how much. `mana >= 3` says
  what to check and not what to spend, and inventing a "pay this expression"
  rule is how a cost silently stops being reversible by undo. Costs stay a map,
  and the fact that they *look* like the map form of a condition is worth
  writing down as a difference rather than leaving as a resemblance.
- **`zone_empty`.** It is a list of zone keys, not a comparison, and
  `count:card@road == 0` is not the same question — a zone with cards nobody can
  see is still not empty. [Assumption: it survives as its own entry rather than
  being folded in; the alternative is a subject that means "how many cards are in
  this container regardless of tags", which does not exist today.]
- **The quantifier.** `hp@each.follower >= 1` still means *of every follower*,
  and that word lives inside the subject where it already is. It is the one part
  of the grammar that is not arithmetic-shaped and it must not be lost in the
  translation.

## What it costs

Measured, not guessed: **51 comparison keys** (`equals` / `at_least` /
`at_most`) and **46 `needs` blocks** across the ten game files, plus every map
entry that is a bare number. Two of the files are generated
(`tools/make_lost_cities.py`), so they regenerate. Also `SCHEMA.json`'s
`_conditions` block and the two-way schema test, `validate.lua`'s
`ROUTE_FIELDS`/`END_FIELDS`/`COMPUTED_FIELDS` and its comparison checks
(`validate.lua:520-560`), `AUTHORING.md`'s condition section, and `DESIGN.md`'s
form 3.

**The golden traces are the proof**, exactly as they were for
[12](12-card-moments.md): a faithful migration changes no behaviour, so
`castle.log` and `kingdom.log` must come out byte-identical. That is what makes
a rewrite of the condition vocabulary safe to do at all.

## Build order

1. **The parser, alone.** String → tree of closures, pure, no game loaded, and a
   test per rule in *the behaviour that must survive* above. It is not wired to
   anything yet.
2. **The object form learns the string**, additively: a routing entry and an
   `end_condition` accept `"when": "<expression>"` beside the shape they take
   today. Nothing migrates; the two forms are held equal by a test that runs the
   same game both ways.
3. **`needs` as a list of expressions**, then the migration, one game per
   commit, traces unchanged.
4. **Delete the old shapes** and the branches in `predicate.met`/`meets_all`
   that read them — which is the point at which findings 4, 5 and 6 are actually
   fixed rather than papered over.
5. **Only then**, position 2 above: one parser for action value slots too, and
   `:x:` goes.
