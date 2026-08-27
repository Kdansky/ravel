# 08 — How a piece says where it may go

**Mostly shipped** (`5c1875e`). Chess plays: patterns, capture, castling, check,
promotion, en passant. **Still open: the scope anchor word, and checkmate.**

The question was narrow: a card on a grid names its legal destinations without
the engine learning the word "bishop".

## Still open

**1. The anchor word.** `entities_in_scope` resolves a pattern name to the cards
standing on the squares it picks out, so `count:piece@adjacent` (anchored on the
acting card) and `count:piece@castle_k_path` (named cells) both work. What
cannot be said is *whose* neighbourhood is meant:

```
@mine.adjacent          my pieces next to me         (anchor: self, implied)
@mine.target.adjacent   my pieces next to the target  ← not sayable
```

`parse_scope` already takes leading known words in any order and treats the
remainder as the name; this is a third word class and a loop bound of 3 instead
of 2.

**2. Checkmate, and refusing a move that leaves your own king attacked.** Both
need the position *after* a hypothetical move, which is
`entity.snapshot`/`restore`. Castling through check needs the same.

## Why directions beat destinations

Five notations were written out in full and compared. The record that matters is
one sentence each:

| | Why it lost |
|---|---|
| **A — predicate scopes** | says *which squares qualify* rather than *how the piece walks*, so blocking, leaping and range are four separate conditions. Survives as what E's scopes grew out of, and `where` shipped on its own for en passant |
| **B — one string per destination** | board-size dependent: a rook on a 10-wide board is a different card |
| **C — B with wildcards** | `*` and `±` are a parser, and a diagonal only works because `*` secretly means *the same distance on both axes* — a rule that has to be taught |
| **D — integer pairs as directions** | **won on mechanism**, lost on where it put the numbers: coordinate pairs on every card def |
| **F — "neighbour" as a tag** | neighbourhood is a property of a *pair*, and nothing in a tag lookup has an asker; as a stamped tag it cannot gate a move, because the stamp is an action and the gate runs first |

**E is D with the pairs declared once in a top-level `patterns` block and used
by name.** Reading a pair as a *direction repeated* makes blocking, leaping and
range one concept and costs a loop rather than a parser; naming it puts the
coordinates in one block, and **one name serves three consumers** — a move list,
a target filter, and a scope. That is why the neighbourhood needs no new verbs:
the shape that says where a piece may walk is the shape that says what stands
beside it.

## The class vocabulary

`range: "*"` was doing two unrelated jobs — how far the vector repeats, and
whether anything on the way stops you — so they are two words rather than one
number: `step`, `ray`, `ray:n`, `phasing`, `mirrored`, `absolute`.

**`phasing` is what `step` gets for free.** A single step has no intermediate
cells, so the knight leaps because of its geometry, not because it was declared
to. `phasing` only means something on a `ray`.

**`mirrored` negates each axis independently**, cutting every symmetric list by
four. It is opt-in, and the pawn is the reason: `diag_fwd` is `[[1,1],[-1,1]]`
written out, because mirroring `[[1,1]]` would hand it two backward captures.

**`absolute` is a class word, not a marker in the pair.** `[1,1]` cannot be told
apart from `[1,1]` by looking, so the label sits one level up and covers the
whole list. It is a *kind* — no path, nothing to repeat — so the walking words
are refused beside it, and it names its `zone`, because a square belongs to a
board where a direction belongs to whoever is moving.

Deliberately not in the set yet: `hopper` (Xiangqi's cannon), `transposed`, and
`must_capture` (checkers' forced jump). Each is one word in a list when a game
asks, which is the point of making this a list rather than a scalar.

## What building it taught

- **The pawn's opening run is not a special case.** It is `ray:2`, so a piece in
  front stops it by the same rule that stops a rook.
- **`rank` wanted to be a stat on the piece, not a scope.** Stamping `col`, `row`
  and `rank` as a piece takes a square makes `rank@self` work with no new scope,
  and hands promotion to an ordinary computed tag. The `@from` scope the design
  reserved for it was not needed — and promotion then needed no movement
  machinery at all.
- **Pieces needed owners before `fill` could mean anything.** A chessboard is one
  shared zone, so every piece was unowned and `enemy` named nothing.
- **Ownership then had to reach `flow.reachable`**, which asked the *zone* whose
  card it was — so white could move black's rook, both being "on the board".
  Asking the card exposed the split between "whose piece is this" (`owner_of`)
  and "who does this card answer for" (`seat_of`): a party game tags four
  characters `player`, and all four must stay clickable on one turn. **You are
  not among the things you own.**
- **Activation is not a play**, so `ends_after` cannot end a turn made of moves.
  The move ends it, and what bounds a turn to one move is the handover, not the
  piece being spent.
- **A pattern being a scope removed a condition the plan needed.** It called for
  a `slot_empty` sibling to `zone_empty`; `count:piece@castle_k_path` says it
  with what already existed.
- **`can_play`'s escape hatch had to learn a limit.** All four castling cards are
  illegal most of the game, and that is their normal state, not a soft-lock.
  Zones tagged `optional` opt out.
- **The captured-rook trap was an engine bug, not a rule for authors.** A stat
  nobody carries summed to zero, so `moves_made@w_rook_h == 0` was *true* of a
  rook taken twenty moves ago. The first fix was a presence term beside every
  such gate — a footgun waiting for the one author who forgets. The real fix is
  that an absent stat fails every comparison, and the presence terms came back
  out.

## Check shipped by neither proposed route

A computed tag was correctly refused: it reads one card's own stats, and "am I
attacked" depends on every enemy piece's reachable set. But the fallback —
*stamp a `threat` count on every square, recomputed after each move* — is also
wrong, and for a reason worth keeping: **it is the engine deciding chess is
special.** A number the engine writes after every move, whose meaning no game
file states, keyed by side and generalising badly past two seats.

What shipped is a scope word. `@reach` is the squares a set of pieces could move
onto, answered as the things standing there, so check is something the game file
*says*: `count:king@enemy.reach == 0`. Nothing is stored, so there is no
recompute timing to get wrong; the owner word does the side-keying the stat would
have needed a second field for, and it already works for four seats. The engine
gained one `elseif`, and it needed **no new computation at all** — `find_moves`
was already answering "where can this piece go", and it honours `fill`, which is
where the game file draws the line between moving and threatening.

## What only playing it found

Both passed every test in the suite and were obvious within a minute of a human
at a mouse:

- **Capture was unclickable.** Hit-testing returns the topmost *card*; a
  slot-typed spec's eligible list holds *slots*; the two never met. Every test
  called `targeting.candidates` directly and so never crossed the seam. The fix
  is in `targeting` rather than `main`, so a rule about what a click *means*
  sits where the tests can reach it.
- **Hovering a castling card crashed the game.** `cost_text` renders `needs` as
  well as `cost`, and only a cost is always a plain number.

The lesson is not "write more tests" but where to aim them: both lived in the gap
between the rules layer, which the suite covers thoroughly, and the presentation
layer, which it barely touches.

**Settled:** `moves` sits top-level on the card def and the engine writes the
`activate_target` from it. Spelling the spec out on every piece would have cost
four repeated fields per template for a distinction that only matters on a board
with two grids, which no game has.
