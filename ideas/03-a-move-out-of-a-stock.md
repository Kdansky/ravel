# 03 — A move out of a stock

**Shipped.** `take:<supply scope>:<zone>[:<n>][:top|bottom]`, and the count on
`move` before it. Puzzle Strike's 95 fill-plus-decrement pairs are 95 statements,
and the crash animation is no longer a guess.

What is worth keeping from the working-through:

**A supply keeping one entity per kind is deliberate and load-bearing.** The
promise that makes it safe is that its cards are *interchangeable*, enforced by
nothing being able to point at one — `targeting.candidates` drops them,
`reactions.placed` refuses them. A rule that could aim at a particular gem would
be able to find out there is only one. That is why `take` had to be a verb rather
than `move` learning about stocks: `move` would carry off the card that *is* the
stack.

**The first argument names the shelf, not the goods.** Everywhere else a scope
says what moves. That inversion is the whole reason this is a second word instead
of a flag: two spellings that read alike and mean opposite things would be worse.

**`fill` stays and means something else.** "Put a copy of this card here" is the
honest answer for a starting deck built out of nothing — 63 of Puzzle Strike's
uses and all 157 of Codex's. Two questions, two words.

**Buying lost a convenience and gained three true statements.** `stock@self` as a
cost checked the stack, paid for the chip and recorded where it came from all at
once. It is now a `when`, a cost and a `take`: one line longer, and each line
says one thing.

## Left, and it is [28](28-a-zone-by-its-parts.md)'s

**Where a destroyed card goes.** `zones.add` reclaims a card *into* a supply and
`zones.take` now takes one out; nothing reclaims what is destroyed, so a finite
box still has to name the bank at every site that removes a component. With that
the box is closed both ways — in with `move`, out with `take`, gone with
`destroy` returning to the box rather than the void.
