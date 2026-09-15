# 13 — One name, one thing

**Shipped**, and narrower than proposed.

## The rule as built

1. **Within a kind, a key names one thing.** Two cards, zones, stats or phases
   sharing a key is a conflict, reported by name.
2. **Across kinds, only what a *scope* resolves must be unambiguous** —
   patterns, zones and tags, asked in that order. Styles are tag words, since
   that is where they are named.

The proposal was *every declared name unique across every kind*, and that was
too strong. Everything else may repeat, and two repeats are load-bearing rather
than tolerated: a chess piece is a card key *and* a tag so another piece's
condition can name it, and **a style sharing a computed tag's name is what makes
a look follow the numbers**. The strong rule would have cost two of the engine's
better mechanisms to prevent a confusion nobody had.

## What it cost to find out

**Patterns were never checked at all**, and they resolve *first* — a pattern
named `board` would silently have beaten the zone.

The rule looked most expensive where it was free. Chess tagged each piece with
its own key so a castling gate could write `moves_made@w_rook_h`; unique names
let a bare scope resolve a card *by key*, so the 32 self-tags were deleted and
no condition changed. Ownership moved to an `owner` field on the way, which is
what made `@white` stop meaning both the seat card and its pieces.

## Refused

- **Namespacing to dodge it** (`zone:board` / `card:board`) — the precedence
  rule wearing a prefix.
- **A warning rather than an error** — a mistake in a list of warnings is a
  mistake that gets made.
- **Reserving more words** — every reserved word is one an author cannot use
  for the obvious thing.

## A *field* name means one thing too

**Shipped 2026-09-15.** The rule above is about **keys**; this half is about
**fields**, and `from` had grown three unrelated meanings:

| where | was | is |
|---|---|---|
| `computes[].from` | the arithmetic the number is made of | **`value`** |
| `reactions[].from` | where the card has to be to answer | **`in`** |
| `leaves.from` | which departure is meant | `from`, unchanged |

`from` keeps the departure, which is the only one of the three that is actually
a *from*. A compute is a number, so it says `value` — the same word a stat's own
entry uses for the same question, one as a literal and one as an expression. A
reaction says `in` because the card does not come from there: it answers *while
it is there*, and the old spelling had readers looking for a movement that never
happens. `in` is a Lua keyword, so the engine writes `reaction["in"]` once and
binds it to a local; `ROUTE_FIELDS` already carried `["then"]` for the same
reason.

Both old spellings are **refused by name** rather than left to the generic
"the engine doesn't read this" — `from` is still a word the format has, so a
reader who writes it has a reason and needs telling which one. No aliases: two
ways to say one thing is the synonym-with-a-schedule the README warns about.

## What it cost to find out

**The sweep that was supposed to catch this missed `at`.** The first pass listed
every field name used under more than one parent — which is the shape of the bug
— and `at` was invisible to it, because `setup.place[].at` was the only parent it
had. `at` was proposed, accepted, and applied across the engine and five game
files before the collision surfaced. Worse than a near-miss: `place` writes
`zone` and `at` side by side, where `at` explicitly means *not the zone, the
square inside it*, so a zone under `at` would have contradicted the one block
where both words appear together.

`source` was proposed next and is worse still — `@source` is a scope meaning
*the card that is acting*, in twelve live conditions. A place-word it is not.

The lesson is the check, not the word: **a name-collision sweep has to compare a
candidate against every name in use, not only against names that already
collide.** A word is free or it isn't; whether its current owner has company
says nothing about that.

Nothing else collided. `where` reads conditions on *the thing the block judges*
(a target candidate, a move's square, a revealed card, a reaction's event) and
`needs` reads conditions on *the card itself*, consistently in all four places;
`type`, `fill`, `seat`, `zone`, `owner`, `spent` and `then` each mean one thing
in every parent they appear in.

## Refused

- **Aliases beside the new spelling**, with the old one deprecated on a
  schedule. Two ways to say one thing is what this whole track exists to stop.
- **`at`**, and **`source`** — both taken. See above.
