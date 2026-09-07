# 25 — A stat that keeps itself

**Closed 2026-09-07, unbuilt.** The question was whether a stat should carry a
`from` saying how it is kept, once `computes` had shipped a formula that sits at
its use site with a name on it. The way to answer it was to migrate everything
`computes` could reach and look at what was left. What is left does not want
`from`.

## What the migration found

Three scratch stats went, and **not one of them for the reason this file
predicted**:

- **The Crew's `best`** was `max:contend@trick` written onto every card in the
  trick so that one compute could read it back. It is inside the compute now
  (`behind` is `max:contend@trick - contend@self`), which deletes the stat and
  the pass that filled it.
- **Splendor's `plenty`** was `max(0, stock - 3)` per gem plate, restated once a
  turn, spent as a cost to gate "take two of one colour". It was never
  arithmetic: it existed because the generator believed *an ability is gated by
  its cost and its phase and by nothing else*, which is false — `usable_rules`
  reads an ability's `needs` (`flow.lua:1088`). It is `stock@self >= 4` now, and
  ten actions and a stat went with it.
- **Puzzle Strike's `to_pick`** was `max(0, 10 - count:puzzle@bank)`. The floor
  is unreachable — nobody can draft an eleventh chip — so it is an ordinary
  compute read straight into the deal's count slot.

## Why `from` has no customer

**Every derived number still standing in the corpus is a sequence, not an
expression.** That is the whole finding. `from` says one thing once; the
arithmetic these games do is a little program:

- **Chained intermediates.** Splendor's price is `due = max(0, cost - bonus)`,
  then `short = max(0, due - tokens)`, then `due -= short` — six lines per
  colour, five colours. The noble check folds five shortfalls into one boolean.
  Codex's draw is `min(hand + 2, 5)`, which is the floor used twice.
- **A stat reassigned from its own derivative.** Puzzle Strike's `sent` is
  `max(0, crashed@mine - crashed@enemy)`, and the two lines after it write
  `crashed` on *both* seats using it. Codex's `over` sits between two writes to
  `to_draw`.
- **A conditional write.** The Crew's `contend` is set by whichever of two
  `when`-gated abilities matches — following and trumping are two ways to be in
  the running. `from` has no if.

`from` as drafted refused chaining and refused sitting on a stat anything writes.
Held to that, it expresses none of the above. Loosened enough to reach them it is
a dependency graph with an evaluation order, which is the thing the draft was
right to refuse.

## The three blocking questions were the wrong three

- **"What does `@owner` mean on a card nobody owns?"** — thought most likely to
  sink it. It is not a blocker at all: `mine` is not a context. `owned_by` reads
  `zones.active_seat()` off the game (`predicate.lua:143`), so a declaration
  resolves `b_white@mine.player` exactly as an action list does.
- **"How much arithmetic?"** — not the cap either. Computes chain, in the order
  the ability lists them, and Codex chains eighteen.
- **"When is it evaluated?"** — the whole of it, and the corpus shows the answer
  is *not* on read. `sent` and `over` are both read between two mutations of
  the numbers they are made of. A derived value whose inputs move inside the
  list that reads it has to be **frozen at a step**, and a stored register is
  what freezing looks like. A stat that keeps itself is the opposite of what
  these games want.

## What `computes` cannot reach, for the next time it comes up

The clamp: `from` on a compute is `+ - *` and no floor, where
`stat_damage` against `min: 0` is `max(0, a - b)` — the identity most of this
corpus's arithmetic is made of. And a compute is bound by a *rule*, so a
**computed tag** and a **phase's `actions`** cannot name one (both are asked with
nobody acting); that alone keeps Codex's `left`, Splendor's `ok` and The Crew's
`gap` as stats. Recorded in AUTHORING.md under `computes`.

Reopen this only with a number that is (a) one expression, (b) read at more than
one moment, and (c) never reassigned. Nothing in seventeen games is all three.
