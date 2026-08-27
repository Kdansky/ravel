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
