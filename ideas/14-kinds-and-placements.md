# 14 — Six kinds, thirty-two pieces

**Shipped.** Chess is thirteen cards, six of which are the pieces, and
`tools/make_chess.py` is deleted — the file is written and read by hand. 704
lines became 279.

Across the 32 piece templates it replaced, only four fields genuinely varied per
piece — `key`, `tags`, `to_slot`, `tooltip` — and every one is a *placement*
fact: what this piece is called, where it starts, whose it is. `moves` had six
distinct values, which is what a kind is. The template was doing three jobs, and
32 copies is what that cost.

## What it took

| | |
|---|---|
| `setup.place` | already built. What it lacked was `owner` and a way to name a square |
| **Ownership as placement state** | written where the piece is put down. The `owns` field and the `white`/`black` tags are gone |
| Squares by name | `"at": ["a1", "h1"]` — a column letter and a rank from the near edge. A list is that many cards, so eight pawns are one line |
| **One picture per player** | `"src": ["light.png", "dark.png"]` on a named asset, chosen by whose card wears it |
| Castling by square | no new machinery |

Ownership as an entity field costs something against DESIGN's standing claim
that *ownership needs no per-card controller field*. The claim was already
broken by chess — a shared board has no per-zone owner to fall back on — and the
tag was the workaround. An entity field snapshots for free.

## The one thing the write-up got wrong

It said the presentation half was [11](11-styles-as-tags.md)'s dynamic styles —
*a style keyed on the owner, choosing the light or dark sprite*. **That cannot
work.** A dynamic style fires on a computed tag, and a computed tag reads one of
the card's own stats and compares it to a number. So it can express "is black".
It cannot express **"is a rook *and* is black"** — and that is the question,
because the sprite depends on both. Six kinds times two owners is twelve
pictures, and a style keyed on the owner offers two. Encoding both facts into one
number (`kind * 2 + owner`, twelve computed tags) is the boolean-field mistake in
a different hat.

**So the picture varies where pictures are declared, not where looks are
claimed:** a named asset takes one source per seat. That also kept `asset` out of
`styles`, where it would have been the odd entry, and it generalises to every
game with coloured pieces — checkers, draughts, go, backgammon.

## Castling needs no reference to a piece

It looked like the blocker: the gates read `moves_made@w_rook_h`, which names
one rook, and eight identical pawns have no names to use. But castling's real
condition is about *squares* — a rook of mine stands on h1 and has never moved,
my king stands on e1 and has never moved, the squares between are empty. Every
clause is positional, and patterns-as-scopes had already shipped.

It is also more *correct*. The by-name version would happily accept a
**different** rook that had wandered onto h1 having never moved, which is a real
position after a promotion.

## What it deleted

26 of 32 piece templates and the whole generator; the `white`/`black` tags, and
with them the last collision [13](13-one-name-one-thing.md) had to design
around; the 32 self-tags; the `owns` field and `seat_owns`; and `slot` on a
placement — one way to name a cell, not two.

## The proof

Chess has no golden trace, so the scripted opening in `tests/run.lua` is it. It
had to be rewritten anyway — it addressed pieces by template key, which cannot
survive eight cards keyed `pawn` — and it addresses them **by square** now,
which is both the only thing that works and how chess is actually written.

**It earned its keep immediately.** The first generated file passed the rank
where the grid row was wanted, so white castled onto black's back rank and the
king landed on g8. Nothing else would have noticed: the file validated clean,
the board rendered, and castling "worked".

## Refused

- **Instance keys.** The moment a placement can be named, conditions will name
  one and every argument above unwinds. Something that genuinely needs to single
  out a piece uses a stat on that piece, which is what `moves_made` already is.
- **Placement expressions.** `"at": "a2..h2"` is a range over a board, the same
  category as a pattern's coordinate list. Anything cleverer is a language.
- **Per-instance overrides in `place`.** A placement says which kind, whose, and
  where. A piece that needs different *rules* is a different kind.
