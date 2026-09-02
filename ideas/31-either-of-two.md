# 31 — Either of two

*From `todo.md`: "'Where' lists a bunch of requirements which are ANDed together,
but sometimes we need an OR. How do we solve this? Multiple where clauses?
Explicit OR syntax?"*

**Not started. It is one decision, and the decision is the whole of it** — every
spelling below is between three and ten lines of engine.

## What the format can say today

A condition is one comparison ([17](17-conditions-as-expressions.md)), and a
*list* of them is the only combinator: `predicate.meets_all` walks the list and
fails on the first miss. That one function is where fourteen call sites meet —
`needs`, `where` (both the move-rule and the target-spec one), `when` on an
ability, a reaction's `where` and `when`, `accepts`, `requires`, `chosen_where`.
So **whatever spelling wins, it lands in one place and every consumer gets it at
once**, which is the strongest fact here.

17 refused `or` *inside* a condition string, and that refusal still holds: `or`
in the string turns a comparison into an expression with precedence, which is the
line between a format and a language. This is the other question — `or` *between*
conditions, where the list already is the `and`.

**Why "write two abilities" does not answer it**, though it is the answer 17
gave. It works when the alternatives are two ways to *do* something. It does not
work for `where`, because a `where` narrows a list of candidates the player is
about to be *offered*: two abilities offer two separate choices, and "target a
damaged creature or an enemy one" is one choice out of a union. Splitting it also
duplicates the whole rule — its cost, its patterns, its action list — to vary one
clause, which is the shape [09](09-composition.md) exists to stop.

## The candidates

**A — a named entry in the list: `{ "any": ["a", "b"] }`.** A list element is
either a condition string (all of which must hold, as now) or an object with one
key, `any`, holding conditions of which one must. One branch in `meets_all`,
nothing to parse, and it reads as what it means at the point of use. It is
**AND-of-ORs**, which is what the request actually asks for; OR-of-ANDs would
need `all` inside `any`, and that is the boolean language. [Assumption: depth is
capped at one and the validator refuses an `any` inside an `any` or an `all`
anywhere, so the grammar cannot grow a second level without somebody deciding to
let it.]

**B — bare nesting: `["a", ["b", "c"]]`.** Same semantics as A with no word for
it. Cheaper to type and worse to read: a list inside a list already means
something else two fields over (`patterns` is a list of coordinate pairs), so the
reader has to know which kind of list they are looking at. Rejected unless A's
one word turns out to be in the way.

**C — a second field, `where_any` beside `where`.** Flat, no nesting, and the
meaning is in the field name. Its cost is per-consumer: `needs_any`, `when_any`,
`accepts_any` — the field table grows by one for every list of conditions in the
format, and the two fields have an unstated relationship (AND of the `where` and
the OR of the `where_any`) that a reader must be taught. It is the spelling that
scales worst with exactly the thing the format has most of.

**D — a named condition, declared once and referenced.** `patterns` already does
this for geometry: a top-level block naming a thing, used by key in three
consumers. `conditions: { "reachable": ["..."] }` and `where: ["@reachable"]`
would answer composition and reuse as well as OR — and it answers OR only if the
named thing may itself be a disjunction, so it needs A anyway underneath.
[Assumption: it is a later idea and not this one; the request is for a
combinator, and reuse has no customer yet that has been counted.]

**Recommended: A.** It is the only one that is a single word, lands in a single
function, and gives every one of the fourteen consumers the same answer.

## What has to be decided before building it

- **Whether `cost` gets it too.** A cost is a map, not a list
  ([17](17-conditions-as-expressions.md)), and *pay either of these* is a real
  rule in card games. [Assumption: no — a cost that can be paid two ways is
  already `pays_for` on the stat ([20](20-puzzle-strike.md)), and a disjunctive
  cost has undo consequences a condition does not.]
- **What the tooltip says.** `cost_text` renders a parsed condition into prose,
  and it is the only presentation that reads conditions. *"at least 3 gold"* has
  an obvious plural; *"either at least 3 gold or a red creature"* wants a
  sentence builder, and getting that wrong is worse than not shipping the
  feature, because a player reads the tooltip and not the file.
- **A real customer, written out.** No card in the corpus is blocked on this
  today — the note is from authoring pressure, not from a chip that cannot be
  transcribed. [Assumption: Puzzle Strike's Color Panic ("narrowing chosen as the
  chip runs") and Martial Mastery ("not that pile") are the nearest, and neither
  is actually a disjunction — they are a choice made at run time and a negation.
  Find the honest one before building, the way every other track here did.]
