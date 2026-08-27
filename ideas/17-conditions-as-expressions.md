# 17 — A condition is one string

**Closed.** `"gold >= 3"` is the only way a condition is written; the map form,
the comparison-object form and the `stat`+comparator struct are gone, and 112
conditions across ten game files went with them.

## The decision: comparison only

`<subject> <op> <number-or-subject>`, six operators, no arithmetic, no nesting,
no booleans. It adds no expressive power at all — which is its strength: nothing
new can be written, so nothing new can be wrong. `>`, `<` and `!=` are new only
in the sense that the struct form had no field name for them; the engine could
always evaluate them.

**Most of it already existed.** `parse_subject` already read
`[<fn>:]<arg>[@<quant>.<owner>.<scope>]`, and the right-hand side already took a
number or another subject. What shipped was an infix spelling of a thing the
engine already evaluated.

**`needs` is a list, `cost` is still a map.** A map keyed by its own condition
cannot hold one subject twice, and `"gold >= 3"` with `"gold <= 8"` is a range.
Costs did not move, and the validator says why out loud: *a cost is what gets
spent, not a condition*.

**Refusals happen at the door.** A string can be parsed before the game runs, so
`gold = 3`, `3 <= gold <= 8` and `gold >= reserve` are all authoring-time errors
now. The operands are ordinary subjects, so every check the validator already
had came along for free.

**Nothing is compiled to Lua, ever.** A game file arrives from a peer through
the same door, so compiling attacker-supplied text would be remote code
execution in a program that accepts game files from strangers by design. The
parser produces a table and `predicate` memoises per distinct string.

## Arithmetic: refused, and the reason changed

The note asked for *simple math*. Three positions were on the table: comparison
only; comparison plus the `:x:` product that action value slots already have;
and general expressions with parentheses and precedence. The third is what
DESIGN refuses outright — the difference between a format and a language.

The second looked strongest, because one parser serving both would **delete** a
notation rather than add one. It lost on measurement: across thirteen games only
15 action strings use `:x:` and **five are a disguised `if`** — a 0-or-1 stat
multiplied in because an ability had nowhere to put a condition. The pressure
reading as "the amount grammar is too weak" was mostly a missing `when`. Of the
ten real uses, all are one Lost Cities formula written five times.

And the notation cannot land without precedence: `sum:value@mine.red - 20 *
count:wager` read left to right is a rule a reader must be *taught and cannot
check*, which is the defect the positional `card_stats` array was retired for.
What position 2 actually wanted — a formula with a name, on its own line, with a
sentence saying what it means — is a `computes` entry.
See [26](26-an-if-and-a-name.md).

**Boolean operators are a separate refusal.** `and` is what a `needs` list
already means, and `or` turns a condition into a program. A card needing
*either* of two things is two abilities.

## The five rules that are behaviour, not spelling

Each was paid for by a bug, and each is asserted against the string form
specifically in `tests/integration/conditions.lua` — a grammar reads like
arithmetic and invites the reading that a missing number is zero.

| Rule | What it prevents |
|---|---|
| **An absent stat fails every comparison**, `== 0` included | "this rook has never moved" being true of a captured rook |
| **The measuring forms are exempt** — `count:`/`card:` over nothing is 0, `sum:`/`max:` of an empty pool is 0 | "these squares are empty" has to be writable |
| **A bare word on the right is a typo, not zero** | every misspelling silently comparing against 0 and passing |
| **An empty `each` scope fails** rather than passing vacuously | a cost being free exactly when nothing can pay it |
| **Nothing malformed reaches a raw Lua comparison** | an uncaught error killing the process on peer-supplied content |

## What the deletion turned up

- **The tooltip was the only presentation that read a condition.** `cost_text`
  walked a map with `pairs` and called `:match` on the key, so a list of strings
  took the interface down. It renders prose from the parsed condition now — *"at
  least 3 gold"*, not `"gold >= 3"` — because a tooltip is read by somebody who
  has never seen the game file.
- **A cost was using the condition door to ask its own question.**
  `can_afford` built `meets_all({ [subject] = n })` to mean "at least this
  much", which is why deleting the map form made every cost free.
- **`bound_ok` had no callers left.** Its rule — a bare word on the right is a
  typo — moved into the parser, where it is an authoring-time error rather than
  a silent run-time failure. That is the whole argument for the string form, in
  one function's deletion.
- **Two error messages had nowhere to live.** `exhaust` and `sacrifice:` written
  as conditions would read as misspelled stats, so `condition_ok` names them and
  says which block they belong in. Both are mistakes somebody actually made.

## Two things it did not fix

**A condition still cannot name a seat absolutely.** The owner words are
`mine`/`enemy`/`anyone`, all relative to whoever is up, and there is no way to
write *white's* at a moment when nobody in particular is to move. It cost twice
in one afternoon: chess's ending could not be an `end_condition`, because when a
king is taken "mine" is whoever moved last, and it became phase routing instead.
Tagging a seat card with its own key is the workaround and a good one — which is
why this is a paper cut — but every game with seats writes two words meaning the
same thing as the seat key it already declared. The fix is one line in
`owned_by` plus the same lookup in `parse_scope`, and *that* is the decision:
`parse_scope` is documented as pure and testable without a game, and consulting
`seat_set` ends that. Either the grammar gains a game-state dependency, or seats
keep wearing tags. `@owner_of` answers the relative question and not this one.

**`computed_tags` are still their own vocabulary.** They are asked of one entity
on the per-frame path and reach things no subject can name — `less_than_max`
reads that card's own ceiling. Folding them in wants a subject for "this card's
ceiling" first. AUTHORING says so where the comparators are listed, because
`at_least` surviving in exactly one node otherwise reads as a miss.

**Finding 6 did not fully dissolve, and that is fine.** `ROUTE_FIELDS` and
`END_FIELDS` were "the same table"; they are four fields each now and differ by
one — `ends_round` against `fired` — which is a real difference between routing
somewhere and firing once.

## What does not become an expression

- **Costs.** A cost names the stat to subtract and by how much; `mana >= 3` says
  what to check and not what to spend. Inventing a "pay this expression" rule is
  how a cost silently stops being reversible by undo.
- **`zone_empty`.** A zone with cards nobody can see is still not empty, so
  `count:card@road == 0` is not the same question.
- **The quantifier.** `hp@each.follower >= 1` still means *of every follower*,
  and that word lives inside the subject. It is the one part of the grammar that
  is not arithmetic-shaped and it must not be lost in translation.
