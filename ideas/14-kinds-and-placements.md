# 14 — Six kinds, thirty-two pieces

**Status:** half shipped. **`setup.place` exists** — a card no longer says where
it starts, and the placement list is the manual. What is left is the collapse
itself: six kinds instead of thirty-two pieces, which needs the presentation
half.

**Size:** medium · **Depends on:** [11](11-styles-as-tags.md), now shipped, for
the presentation half — a white rook and a black rook differ in `asset` and
`text`, and with six kinds that difference has to come from *whose it is*.

> *For chess, I believe the correct game.json says that there is a type pawn, of
> which there are 16, 8 of which are for each player. When the game is set up,
> this is just a matter of stating "hey these go to that player's ownership". No
> tags or references needed? Or are there?*

**Right, and the numbers say so.** Across chess's 32 piece templates:

| Field | Distinct values |
|---|---|
| `moves` | **6** — one per kind, which is what a kind is |
| `card_stats`, `on_activate`, `exhausts`, `to_zone`, `auto_play` | **1** each |
| `asset`, `text` | **12** — six kinds × two owners |
| `key`, `tags`, `to_slot`, `tooltip` | **32** |

Only the last row genuinely varies per piece, and every one of those four is a
*placement* fact: what this piece is called, where it starts, whose it is. The
template is doing three jobs — **a kind, a placement, and a presentation** — and
32 copies is what that costs.

The generator's own docstring already admits it:

> *the engine has no notion of "an instance with parameters" — a card that starts
> in play does so via `to_slot`, one template per square.*

---

## The shape

Six kinds, and a setup that places them:

```json
"cards": [
  { "key": "pawn", "moves": [...], "card_stats": { "rank": 0, "moves_made": 0 }, ... },
  { "key": "rook", "moves": ["line_ortho"], ... }
],

"setup": {
  "place": [
    { "card": "rook", "owner": "player_white", "zone": "board", "at": ["a1", "h1"] },
    { "card": "pawn", "owner": "player_white", "zone": "board", "at": "a2..h2" }
  ]
}
```

**Ownership becomes instance state**, set where the piece is placed, which is
where it is actually decided. `owner_of` reads it directly, and the `white` tag
stops existing — so this also finishes [13](13-one-name-one-thing.md)'s job by
removing the collision rather than renaming around it.

Note what this costs against `DESIGN.md`'s standing claim that *"ownership needs
no per-card controller field and no new state to snapshot"*. It does now. The
answer is that the claim was already broken by chess — a shared board has no
per-zone owner to fall back on — and the tag was the workaround. An entity field
snapshots for free, because entities are what `snapshot`/`restore` copy.

## The three things it needs

**1. Placement as data** — ~~needed~~ **built.** `auto_play`, `to_zone` and
`to_slot` are gone; `setup.place` names the card, the zone and the cell, in the
order the manual would say it, and a card may be placed more than once. That
last part is what the collapse needs: eight pawns are eight entries naming one
card. The engine's own placements (the system card, an injected player, a seat)
are prepended rather than written down, because a seat has to exist before it
can act.

What it still lacks for chess is `owner` on the entry — see below.

**2. Presentation that varies by owner.** `asset` and `text` have twelve values
because a white rook and a black rook are drawn differently and named
differently. With six kinds, the difference has to come from *whose it is* —
which is [11](11-styles-as-tags.md)'s dynamic styles, and a good test of them: a
style keyed on the owner, choosing the light or dark sprite. Until 11 lands, this
one can't fully land either.

**3. A way to talk about a particular piece** — and this is the question worth
answering carefully.

## Castling needs no reference to a piece

It looks like the blocker. Chess's castling gates read `moves_made@w_rook_h`,
which names one rook — and with eight identical pawns and two identical rooks,
instances have no names to use.

**They do not need any.** Castling's real condition is about *squares*:

> a rook of mine stands on h1 and has never moved, my king stands on e1 and has
> never moved, and the squares between them are empty

Every clause there is positional, and the last one is *already* written that way
— `count:piece@w_castle_k_path` uses an absolute pattern as a scope. So do the
other two:

```json
"needs": {
  "count:rook@w_rook_h_home": 1,
  "moves_made@w_rook_h_home": { "equals": 0 },
  "count:piece@w_castle_k_path": { "equals": 0 }
}
```

`w_rook_h_home` is an absolute pattern naming one square. This needs **no new
machinery** — patterns as scopes shipped with chess — and it is more honest than
what is there now, because castling is a rule about squares and pieces that have
not moved, not about two cards with particular names.

It is also more *correct*. A rook that leaves h1 and returns has `moves_made > 0`
and is refused either way, but the positional form additionally refuses a
*different* rook that has wandered onto h1 having never moved — which the
by-name version would happily accept, and which is a real position after a
promotion.

**So: no tags, and no references to pieces. References to squares.**

## What it deletes

- 26 of 32 piece templates.
- The `white` / `black` tags, and with them the last collision
  [13](13-one-name-one-thing.md) has to design around.
- The 32 self-tags (`w_rook_h` as a tag on `w_rook_h`), whose only consumer was
  castling.
- `auto_play`, `to_zone`, `to_slot` as card fields.
- Most of `make_chess.py`. A file this size stops needing a generator, which is
  the real prize: **chess becomes a game file a person can read.**

## Refuse

- **Instance keys.** The moment a placement can be named, conditions will name
  one, and every argument above unwinds. If something genuinely needs to single
  out a piece, it is a stat on that piece, which is what `moves_made` already is.
- **Placement expressions.** `"at": "a2..h2"` is a range over a board, which is
  the same category as a pattern's coordinate list. Anything cleverer is a
  language.
- **Per-instance overrides in `place`.** A placement says which kind, whose, and
  where. A piece that needs different *rules* is a different kind.

## Build order

1. `setup.place`, owner as entity state, `owner_of` reading it. Chess keeps its
   32 templates and gains nothing yet — but the golden traces must not move,
   which is what proves the placement path is equivalent.
2. Castling by square. Delete the 32 self-tags. Traces unchanged again.
3. [11](11-styles-as-tags.md), then presentation by owner.
4. Collapse to six kinds and delete most of the generator. **The traces are the
   proof**: the same opening moves, the same captures, the same transcript, from
   a sixth of the file.
