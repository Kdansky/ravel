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

## Open: a *field* name means one thing too

The shipped rule is about **keys** — what a game file names. It says nothing
about **fields**, what the format names, and `from` has grown three unrelated
meanings there:

| where | what `from` means |
|---|---|
| `computes[].from` | the arithmetic expression the number is made of (`SCHEMA.json:59`) |
| `reactions[].from` | where answering happens — `"hand"`, `"board"`, or a zone by name (`SCHEMA.json:190`) |
| `leaves.from` | which departure is meant — a zone by name (`SCHEMA.json:243`) |

Two of the three mean a place and one means an expression, so a reader who has
learned one is actively misled by the next. Raised 2026-09-15 while looking for
a word for a ward's side: `from` was the obvious name and had to be refused,
which is how the collision surfaced at all.

[Assumption: the fix is renaming two of the three, not the format learning a
per-section lookup. Which two, and to what, is the decision — `computes[].from`
is the odd one out semantically but has the most sites, while the two "place"
readings are closest to each other and so are the pair most likely to be
confused with *each other*.]

Worth a sweep for the same shape in other field names before renaming anything:
this was found by accident, so there is no reason to think it is the only one.
The check is cheap and mechanical — every field name the engine reads, grouped
by what it holds — and it is the kind of thing that only gets harder as more
games are written against the current spellings.

**Why it matters beyond tidiness:** one name for two logics is where bugs come
from. The format has been bitten by exactly this before — `gain` inferred its
zone from tags and silently dropped the card in the hand when two tags
disagreed, and it was found by asking what the *longer* spelling did differently
(README, "The verbs grew them too, and a synonym hides a bug").
