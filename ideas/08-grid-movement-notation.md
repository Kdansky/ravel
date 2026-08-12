# Idea 08 — How a piece says where it may go

**Status: mostly shipped (`5c1875e`).** Option E was chosen and built; chess
plays, castling included. The comparison below is kept because it is the record
of *why* directions beat destinations, and the **Build order** at the end of this
file marks each step's state and what building it taught. Check shipped as the
`@reach` scope and **promotion** as the `become` action — the latter needing no
movement machinery at all, since `rank` was already counted from a piece's own
side. Still open: the scope anchor word (step 3), checkmate and the legality
filter that goes with it (step 5), en passant.

Three notations for the same five chess pieces, written out so they can be
compared rather than argued about.

The question is narrow: **a card on a grid needs to name its legal
destinations, without the engine learning the word "bishop".** Everything else
already exists — `activate_target` selects, `move_to:target` moves the acting
card into the chosen slot (`actions.lua:216`), and `targets_legal`
(`flow.lua:119`) re-derives candidates so the constraint *is* the rule, not a UI
courtesy.

---

## Shared machinery (every option needs it)

These are not what the options differ on, so they are settled once here.

**Axes.** `x` is the column, increasing rightward. `y` is the row, **increasing
forward for whoever is acting**. Both seats therefore write `y+1` for "one step
ahead", so there is one `pawn` template rather than a white one and a black one.

**Two readings of a row.** `row` is absolute (1–8, fixed to the board). `rank` is
counted from the acting seat's own back line, so a pawn's home is `rank 2` for
both colours and promotion is `rank 8` for both.

**What may be landed on** — a `fill` word on the target spec, because "empty" is
not enough once capture exists:

| `fill` | Means |
|---|---|
| `empty` | an unoccupied slot — today's only behaviour, so it stays the default |
| `enemy` | a slot holding a card owned by another seat |
| `open` | empty *or* enemy — "anywhere I'm not blocked by my own" |
| `any` | any slot at all |

**Blocking is the one thing that is not shared**, and it is what separates the
options. A notation that names *destinations* (A, B, C) has to reconstruct the
path and decide when there is one; a notation that names *directions* (D) never
has a path to reconstruct. See each option.

**Capture** is `place_in_slot(card, slot, on_occupied)` with `on_occupied` being
`refuse` (default, unchanged), `destroy`, or a zone key — chess names a tray, so
taken material stays visible.

---

## Option A — predicate scopes

Geometry arrives as new scope words (`@delta`, `@from`), and the existing
condition language does the rest. A target spec gains `where`, evaluated per
candidate with `@self` = the acting card and `@target` = the candidate slot.

`@delta` carries `dx dy` (signed, forward-oriented), `adx ady`, `dist`
(Chebyshev), `walk` (Manhattan), `blockers`. A list of specs means "any of".

```json
{ "key": "rook", "on_activate": ["move_to:target"],
  "activate_target": [
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "dx@delta": { "equals": 0 }, "ady@delta": 1,
                 "blockers@delta": { "equals": 0 } } },
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "dy@delta": { "equals": 0 }, "adx@delta": 1,
                 "blockers@delta": { "equals": 0 } } } ] }

{ "key": "bishop", "on_activate": ["move_to:target"],
  "activate_target": [
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "adx@delta": { "equals": "ady@delta" }, "ady@delta": 1,
                 "blockers@delta": { "equals": 0 } } } ] }

{ "key": "queen", "on_activate": ["move_to:target"],
  "activate_target": [
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "dx@delta": { "equals": 0 }, "ady@delta": 1,
                 "blockers@delta": { "equals": 0 } } },
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "dy@delta": { "equals": 0 }, "adx@delta": 1,
                 "blockers@delta": { "equals": 0 } } },
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "adx@delta": { "equals": "ady@delta" }, "ady@delta": 1,
                 "blockers@delta": { "equals": 0 } } } ] }

{ "key": "knight", "on_activate": ["move_to:target"],
  "activate_target": [
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "adx@delta": { "equals": 1 }, "ady@delta": { "equals": 2 } } },
    { "type": "slot", "zones": ["board"], "fill": "open",
      "where": { "adx@delta": { "equals": 2 }, "ady@delta": { "equals": 1 } } } ] }

{ "key": "pawn", "on_activate": ["move_to:target"],
  "activate_target": [
    { "type": "slot", "zones": ["board"], "fill": "empty",
      "where": { "dx@delta": { "equals": 0 }, "dy@delta": { "equals": 1 } } },
    { "type": "slot", "zones": ["board"], "fill": "empty",
      "where": { "dx@delta": { "equals": 0 }, "dy@delta": { "equals": 2 },
                 "rank@from": { "equals": 2 }, "blockers@delta": { "equals": 0 } } },
    { "type": "slot", "zones": ["board"], "fill": "enemy",
      "where": { "adx@delta": { "equals": 1 }, "dy@delta": { "equals": 1 } } } ] }
```

The king, for completeness, is one entry: `{ "dist@delta": { "equals": 1 } }`.

**What the engine learns:** two scopes and a `where` filter. No new comparison
code — `predicate.meets_all` runs unchanged, which is why `adx == ady` can be
written at all.

**Cost:** the boilerplate is brutal. `"type": "slot", "zones": ["board"],
"fill": "open"` appears three times in a queen, and a reader has to hold
`adx`/`ady`/`dist`/`blockers` in their head to see a diagonal.

---

## Option B — a flat array of offsets, one string per destination

One string names exactly one reachable square. `x+3`, `y-2`, `x+1;y+2`. An
omitted axis is zero. `;` separates axis terms (`,` cannot: JSON arrays already
use it, and every list in this engine is comma-separated).

```json
{ "key": "rook", "moves": [
  "x+1","x+2","x+3","x+4","x+5","x+6","x+7",
  "x-1","x-2","x-3","x-4","x-5","x-6","x-7",
  "y+1","y+2","y+3","y+4","y+5","y+6","y+7",
  "y-1","y-2","y-3","y-4","y-5","y-6","y-7" ] }

{ "key": "bishop", "moves": [
  "x+1;y+1","x+2;y+2","x+3;y+3","x+4;y+4","x+5;y+5","x+6;y+6","x+7;y+7",
  "x+1;y-1","x+2;y-2","x+3;y-3","x+4;y-4","x+5;y-5","x+6;y-6","x+7;y-7",
  "x-1;y+1","x-2;y+2","x-3;y+3","x-4;y+4","x-5;y+5","x-6;y+6","x-7;y+7",
  "x-1;y-1","x-2;y-2","x-3;y-3","x-4;y-4","x-5;y-5","x-6;y-6","x-7;y-7" ] }

{ "key": "queen", "moves": [ /* the rook's 28 and the bishop's 28: 56 strings */ ] }

{ "key": "knight", "moves": [
  "x+1;y+2","x+2;y+1","x+2;y-1","x+1;y-2",
  "x-1;y-2","x-2;y-1","x-2;y+1","x-1;y+2" ] }

{ "key": "king", "moves": [
  "x+1","x-1","y+1","y-1","x+1;y+1","x+1;y-1","x-1;y+1","x-1;y-1" ] }
```

The pawn is where the flat form runs out. Its three rules differ in *what may be
on the destination* and one of them has a precondition, and a string cannot carry
either. So a rule may also be written long-hand, and a bare array is shorthand
for a single rule with `fill: "open"`:

```json
{ "key": "pawn", "moves": [
  { "offsets": ["y+1"], "fill": "empty" },
  { "offsets": ["y+2"], "fill": "empty", "needs": { "rank@from": { "equals": 2 } } },
  { "offsets": ["x+1;y+1","x-1;y+1"], "fill": "enemy" } ] }
```

**Blocking** has to be derived, because a string names where the piece lands and
says nothing about how it got there. The rule: an offset is *aligned* when
`dx == 0`, `dy == 0` or `|dx| == |dy|`; an aligned destination requires every
slot strictly between to be empty, and a non-aligned one is a leap. That gets
chess right — the knight needs no `jumps` flag and nothing else needs a `blocked`
flag — but it is a guess about intent, and it guesses wrong for a piece that is
meant to leap along a line (a 0,2 leaper), which then needs an override.

**What the engine learns:** parse `x±n;y±n`, apply the offset to the actor's
slot, check `fill`, test alignment, walk the path. Roughly forty lines and no new
condition vocabulary at all.

**Cost:** 56 strings for a queen, and every list is **written for an 8×8 board**.
A 10×10 variant is a different rook.

---

## Option C — the same flat strings, with two wildcards

Identical to B, except a magnitude may be `*` and a sign may be `±`.

- `*` means **any distance ≥ 1**, and where a string uses `*` on both axes it is
  the *same* distance on each — which is exactly what makes a diagonal a
  diagonal, and makes the notation board-size independent.
- `±` means **both signs**, varying independently across axes.

```json
{ "key": "rook",   "moves": ["x±*", "y±*"] }
{ "key": "bishop", "moves": ["x±*;y±*"] }
{ "key": "queen",  "moves": ["x±*", "y±*", "x±*;y±*"] }
{ "key": "knight", "moves": ["x±1;y±2", "x±2;y±1"] }
{ "key": "king",   "moves": ["x±1", "y±1", "x±1;y±1"] }

{ "key": "pawn", "moves": [
  { "offsets": ["y+1"], "fill": "empty" },
  { "offsets": ["y+2"], "fill": "empty", "needs": { "rank@from": { "equals": 2 } } },
  { "offsets": ["x±1;y+1"], "fill": "enemy" } ] }
```

That is the whole of chess movement in nine lines, and it stays readable: `x±*`
is "any distance sideways", `x±1;y±2` is visibly the knight's L.

The two wildcards are independent — `±` could be dropped, costing a rook nothing
(`["x+*","x-*","y+*","y-*"]`) and a knight six extra strings.

**What the engine learns:** B's parser plus expanding `*` into a ray and `±` into
sign combinations. Maybe fifteen lines more than B.

---

## Option D — integer pairs, read as directions

Drop the strings. A move is `[dx, dy]`, and `x`/`y` need no naming because every
board has exactly two axes. The pair is a **direction, repeated up to `range`
times** (default 1), and each repetition after the first must land on an empty
slot.

```json
{ "key": "rook",   "range": "*",
  "moves": [[1,0],[-1,0],[0,1],[0,-1]] }

{ "key": "bishop", "range": "*",
  "moves": [[1,1],[1,-1],[-1,1],[-1,-1]] }

{ "key": "queen",  "range": "*",
  "moves": [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]] }

{ "key": "knight",
  "moves": [[1,2],[2,1],[2,-1],[1,-2],[-1,-2],[-2,-1],[-2,1],[-1,2]] }

{ "key": "king",
  "moves": [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]] }

{ "key": "pawn", "moves": [
  { "vectors": [[0,1]], "fill": "empty" },
  { "vectors": [[0,1]], "range": 2, "fill": "empty",
    "needs": { "rank@from": { "equals": 2 } } },
  { "vectors": [[1,1],[-1,1]], "fill": "enemy" } ] }
```

Five pieces, five lines, and a bare array of pairs is shorthand for one rule with
`range: 1` and `fill: "open"` — the pawn is again the only piece that pays for
the long form.

**Blocking, leaping, sliding and limited range stop being four ideas.** Because
the pair is a step that gets repeated, the cells "in between" are just the
earlier repetitions:

- The knight's `[1,2]` at range 1 has no earlier repetition, so **it leaps, and
  there is nothing to flag.** No alignment test exists to guess wrong.
- The rook's `[1,0]` at range `*` walks outward and stops at the first occupant,
  so **blocking is by construction** rather than by a `blockers == 0` condition.
- A 0,2 leaper is `[[0,2]]` at range 1 and correctly jumps; a short rook is
  `range: 3`. Neither needs a new word.

**What the engine learns:** walk a vector up to `range` times, stop on
occupancy, check `fill` on the landing slot. No parser, no alignment rule, no
wildcards — noticeably *less* than B or C.

**Cost:** it breaks the letter of the "arrays of strings" schema rule, though not
its intent (see below). And a direction cannot express a destination that isn't
reachable by repeating a step — no such chess piece exists, but a "teleport to
any corner" card would want a different field.

| | A — predicate scopes | B — flat, exhaustive | C — flat, wildcards | D — integer pairs |
|---|---|---|---|---|
| Rook | 2 specs, 8 JSON lines | 28 strings | 2 strings | **4 pairs, 1 line** |
| Bishop | 1 spec, 4 lines | 28 strings | 1 string | **4 pairs, 1 line** |
| Queen | 3 specs, 12 lines | 56 strings | 3 strings | **8 pairs, 1 line** |
| Knight | 2 specs, 6 lines | 8 strings | 2 strings | **8 pairs, 1 line** |
| Pawn | 3 specs, 12 lines | 3 rules | 3 rules | 3 rules |
| Readable at a glance | no | by the yard | yes | **yes** |
| Survives a 10×10 board | yes | **no** | yes | yes |
| Blocking | a `blockers` condition | derived from alignment | derived from alignment | **structural — free** |
| Leaping | absence of a condition | derived from alignment | derived from alignment | **structural — free** |
| Limited range (short rook) | `ady at_most 3` | more strings | not expressible | **`range: 3`** |
| New engine vocabulary | 2 scopes + `where` | an offset parser | parser + 2 wildcards | **none** |
| Fits the schema rule | yes | yes | yes | **bends it (see below)** |

**Where they are not competitors.** A answers a question C cannot: *"how many
allies are standing next to me"* — a support bonus is `count:ally@neighbours`
with no movement involved, and that is a scope, not an offset list. C answers a
question A only answers verbosely: *where may this piece go*. The two solve
adjacent problems and a grid engine plausibly wants one of each: **offsets for
movement, scopes for reading the neighbourhood.**

**Where neither is enough.** Connect 4's "the piece falls to the lowest free cell
in its column" is anchored on the *candidate*, not on a piece already standing
somewhere — the actor is in hand and has no slot, so every offset in B and C is
meaningless and `@delta` is undefined. It needs a rule about the destination
itself ("the slot under this one is occupied, or this is the bottom row"), which
is a third small thing: a directional scope anchored on the candidate. Worth
noting, not worth building until a second game asks.

## Option E — D, but the pairs are declared once and named

A top-level `patterns` block. A bare array of pairs is a set of directions used
once; the long form adds tags saying how they are walked.

```json
"patterns": {
  "adjacent":   { "vectors": [[1,0],[0,1],[1,1]], "class": ["step", "mirrored"] },
  "knight":     { "vectors": [[1,2],[2,1]],       "class": ["step", "mirrored"] },
  "line_ortho": { "vectors": [[1,0],[0,1]],       "class": ["ray",  "mirrored"] },
  "line_diag":  { "vectors": [[1,1]],             "class": ["ray",  "mirrored"] },
  "forward":    { "vectors": [[0,1]],             "class": ["step"] },
  "run_fwd":    { "vectors": [[0,1]],             "class": ["ray:2"] },
  "diag_fwd":   { "vectors": [[1,1],[-1,1]],      "class": ["step"] }
}
```

A bare array of pairs is shorthand for `"class": ["step"]`, which is the common
case.

**It is `class`, not `tags`.** Card and zone tags are a different thing that
happens to share the shape — a game's own vocabulary, matched by `count:<tag>`
and granted by zones — and one word for both would make them
indistinguishable at a glance. This list is a closed set the engine defines, so
it gets its own name; renaming the one that does not exist yet is free, and
refactoring the one that does is not.

Chess is then pattern names, and **every card def goes back to being an array of
strings** — schema form 2, no bend at all:

```json
{ "key": "rook",   "moves": ["line_ortho"] }
{ "key": "bishop", "moves": ["line_diag"] }
{ "key": "queen",  "moves": ["line_ortho", "line_diag"] }
{ "key": "knight", "moves": ["knight"] }
{ "key": "king",   "moves": ["adjacent"] }

{ "key": "pawn", "moves": [
  { "patterns": ["forward"],  "fill": "empty" },
  { "patterns": ["run_fwd"],  "fill": "empty",
    "needs": { "rank@from": { "equals": 2 } } },
  { "patterns": ["diag_fwd"], "fill": "enemy" } ] }
```

The coordinate pairs now exist in exactly one block in the whole game file, which
is where the schema rule's existing exception already points.

### The class vocabulary

`range: "*"` was doing two unrelated jobs — how far the vector repeats, and
whether anything on the way stops you. Those vary independently, so they are two
words rather than one number.

| Class | Means | Default |
|---|---|---|
| `step` | the vector applies exactly once | **yes** |
| `ray` | the vector repeats until something stops it | |
| `ray:n` | …up to `n` times (`ray:2` is the pawn's opening run) | |
| `phasing` | nothing on the way stops it — the path is not consulted | |
| `mirrored` | each axis is negated independently, so one vector stands for its whole family | |

`ray:n` is the `op:param` form the engine already uses for zone `contents`
(`"card_key:count"`), so the parameterised word is not a new idea.

**`phasing` is what `step` gets for free.** A single step has no intermediate
cells, so nothing can obstruct it — the knight leaps because of its geometry, not
because it was declared to. `phasing` therefore only means something on a `ray`,
where it describes a piece that slides along a line regardless of what stands in
it. (`unblocked` is the plainer name if `phasing` reads as jargon.)

**`mirrored` negates each axis independently**, which is one sentence and cuts
every symmetric list by a factor of four:

```
[[1,0],[0,1]]  + mirrored  →  the 4 orthogonals
[[1,1]]        + mirrored  →  the 4 diagonals
[[1,2],[2,1]]  + mirrored  →  the knight's 8
```

It is opt-in for a reason, and the pawn is the reason: `diag_fwd` is
`[[1,1],[-1,1]]` written out, because mirroring `[[1,1]]` would hand it two
backward captures.

**Deliberately not in the set yet:** `hopper` (must jump exactly one piece —
Xiangqi's cannon), `transposed` (swap the axes, so `[[1,2]]` alone covers the
knight), and `must_capture` (checkers' forced jump). Each is one word in a list
when a game asks, which is the point of making this a list rather than a scalar.

### The same names become scopes

A pattern names a shape, and a shape is equally an answer to *"where may I go"*
and *"what is standing near me"*. So `entities_in_scope` learns pattern names,
and the whole existing condition and action vocabulary reaches the neighbourhood
with no new syntax:

```
count:piece@mine.adjacent        my pieces standing next to me
sum:atk@enemy.adjacent           the attack of everything hostile beside me
max:hp@line_ortho                the toughest thing on my rank or file
```

One grammar addition: an **anchor** word, alongside the existing quantifier and
owner words, saying whose neighbourhood is meant. It defaults to `self`.

```
@mine.adjacent          my pieces next to me         (anchor: self, implied)
@mine.target.adjacent   my pieces next to the target
```

`parse_scope` already takes leading known words in any order and treats the
remainder as the name; this is a third word class and a loop bound of 3 instead
of 2.

### The worked example

> *Deal `self.ATK` damage to a neighbouring enemy piece, +1 for every
> neighbouring friendly piece, and +2 for every friendly piece neighbouring the
> attacked target.*

```json
{ "key": "warrior", "tags": ["piece"],
  "card_stats": { "atk": 3, "hp": 5, "power": 0 },
  "moves": ["adjacent"],
  "activate_target": { "type": "card", "pattern": "adjacent",
                       "owner": "enemy", "tags": ["piece"], "count": 1 },
  "on_activate": [
    "set_stat:power@self:sum:atk@self",
    "gain_stat:power@self:count:piece@mine.adjacent",
    "gain_stat:power@self:2:x:count:piece@mine.target.adjacent",
    "lose_stat:hp@target:sum:power@self" ] }
```

Every one of those four verbs already exists and is unchanged. `2:x:count:…` is
the product form `amount()` already parses (`actions.lua:78`), and accumulating
into a scratch stat before spending it is the same shape Lost Cities uses to
distribute `(sum − 20) × wagers` across two actions.

Three things this example settles:

- **It has to be four lines, not one.** `amount()` multiplies but does not add,
  and adding `+` would make the value slot an expression language — the thing
  `DESIGN.md` refuses. Accumulating into `power` is the existing idiom and it is
  also *more* correct: one `lose_stat` is one hit, so a future "when damaged"
  trigger fires once rather than three times.
- **The scratch stat must be declared** (`"power": 0` in `card_stats`), because
  `bearers` deliberately refuses to invent a stat on a card that never had one.
- **`@mine.target.adjacent` includes the attacker**, which is standing next to
  its own victim. Whether that +2 counts is a rules decision, and the notation is
  precise enough to force it into the open rather than leave it to chance. Give
  the attacker a tag the count excludes, or accept it.

**What the engine learns:** the `patterns` block and its five class words, one
anchor word in `parse_scope`, one branch in `entities_in_scope`, and `pattern` on
a target spec. The vector-walking loop is the same one D needed — `step`, `ray`,
`ray:n` and `phasing` are its loop bound and its one `break`.

## Option F — "neighbour" as a dynamic tag (rejected, with the part worth keeping)

The appeal is obvious: `count:<tag>` already works everywhere, so if a card next
to me carried a `neighbour` tag, the whole ability would need no new vocabulary
at all. Two versions, and they fail differently.

**As a computed tag** — no. `tags.entity_has` derives a computed tag from the
card's *own stats* (`computed_tags[tag]` against `less_than` / `at_least` /
`equals`). Neighbourhood is not a property of a card, it is a property of a
*pair*: neighbour of whom? Every such tag would be true or false depending on who
is asking, and nothing in the tag lookup has an asker.

**As a stamped tag** — an action that writes the tag onto whatever the pattern
reaches, then reads it back:

```
"mark:adjacent:near", "gain_stat:power@self:count:near", "unmark:near"
```

This does work, and it dissolves the anchor problem, because `mark` runs inside
an action context that already knows `@self` and `@target`. It fails on three
other counts:

- **It cannot gate.** `needs`, costs and `can_activate` all run *before* any
  action, so nothing has been marked yet. "Only attack if two friendly pieces are
  beside you" is unwritable — and that is half of what neighbourhood is for.
- **It leaks.** A forgotten `unmark` makes every later `count:near` quietly
  wrong. Silent wrong answers are precisely what `predicate.lua`'s fail-closed
  discipline exists to prevent, and a tag that is usually correct is worse than
  one that is absent.
- **It needs per-entity tags, which don't exist.** A card's tags live on its
  *def* (`tags_set`), shared by every instance of that card; there is no
  per-instance tag set to write into.

And underneath all three: `tags.lua:8` says the zone-`applies` mechanism is
"bounded on purpose to a fixed list declared on the zone, so this stays one
lookup and never becomes the recomputation problem that auras are." A neighbour
tag *is* that recomputation problem — one move invalidates it for up to eight
cards — arriving through the door that comment was written to hold shut.

**The part worth keeping.** The idea is exactly right for board facts that belong
to *one* card and need no anchor. Give a card on a grid the stats `col`, `row`
and `rank`, and computed tags work today, unchanged:

```json
"computed_tags": { "promoting": { "stat": "rank", "at_least": 8 } }
```

That is pawn promotion with no new machinery whatsoever — **and it shipped that
way.** The detection is exactly the `rank@self` this section predicted; the only
verb that had to be added was `transform:<scope>:<card>`, which swaps a card for
another keeping its square, zone and owner, and is a general one (a crowned
checker, a levelled unit, a flipped tile). The choice of piece is the engine's
`options` offer — see [DONE.md](DONE.md) — which deals a card per choice, opens
over the board, remembers the pawn that asked, and hands it to the chosen card
as its target. Chess writes `transform:target:queen` and nothing else.

Two things drafting it turned up, both in the engine's favour: `resolve_challenge`
is the conditional (no new one was needed), and `flow.play_card` **already pops an
overlay before the chosen card's action runs**, so a card that pops again takes
the phase underneath with it. The first draft did exactly that.

So: **relational
questions are scopes, positional ones are tags** — and the split is not a
compromise, it is the same line the engine already draws between what a card *is*
and what a card is *near*.

## The schema question D raises

`DESIGN.md:68`: *"Nested arrays are allowed in exactly one place — a `per_seat`
zone's `pos`, which is one rect per seat — and that is a list of coordinates, not
structure."*

A list of `[dx, dy]` pairs is the same category as the exception already granted:
coordinates, not structure. It carries no keys, no nesting beyond depth two, and
no evaluation order — the thing the rule exists to prevent. So D is a second
instance of an existing exception rather than a new bend, and the rule's wording
should be widened to say so: *coordinate pairs, wherever a position or a
direction is meant.*

The non-programmer test also passes better than the strings do. `[1,2]` beside a
picture of a knight explains itself; `"x±1;y±2"` has to be learned.

## Recommendation

**E** — D's integer pairs, declared once in a top-level `patterns` block and used
by name.

D already won on mechanism: reading a pair as a *direction* rather than a
destination makes blocking, leaping and range one concept instead of four, and
costs a loop rather than a parser. Naming the pattern adds the three things D
lacked:

1. **Card defs go back to arrays of strings.** The coordinate pairs exist in one
   block, which is where the schema rule's existing exception already points.
   D's bend disappears.
2. **One name serves three consumers** — a move list, a target filter, and a
   scope. That is the whole reason the ability above needs no new verbs: the
   shape that says where a piece may walk is the shape that says what stands
   beside it.
3. **`line_ortho` beats a raw vector list and a `range`** at the place it is read
   most, which is the card. And because the *how* is a `class` list rather than a
   scalar, `hopper` or `must_capture` arrive later as one word rather than as a
   new field.

Rejected: **F**, tags for neighbourhood — relational, so it cannot gate and
cannot be written per-instance; its good half (positional computed tags) is kept.
**A** survives only as the thing E's scopes grew out of.

### Build order

1. ~~**Shared machinery**~~ — **done.** `fill` on a slot target spec, `col`/`row`
   as slot stats, `place_in_slot(card, slot, on_occupied)`, and the third
   argument to `move_to`. Two things the plan had not foreseen, both forced by
   the first test:

   - **Pieces needed owners before `fill` could mean anything.** A chessboard is
     one shared zone, so every piece on it was unowned and `enemy` named nothing.
     A card tagged with a seat's key now belongs to that seat
     (`predicate.owner_of`), which costs no new field because a seat is already
     a card key.
   - **Ownership then had to reach `flow.reachable`**, which asked the *zone*
     whose card it was — so white could move black's rook, both being "on the
     board". Asking the card instead exposed the split between "whose piece is
     this" (`owner_of`) and "who does this card answer for" (`seat_of`): a party
     game tags four characters `player`, making four seats, and all four must
     stay clickable on one turn. You are not among the things you own.

   `rank` (a row counted from the acting seat's own side) is *not* built. It has
   no meaning until a pattern is walked with a facing, so it belongs to step 2.
2. ~~**`patterns` + the walk**~~ — **done.** `geometry.lua` (slot_at, facing,
   rank, reach), the `patterns` section, `moves` on a card def, and `moves` on a
   target spec. `game/games/chess.json` is written by hand and
   plays: 32 pieces, blocking, leaping, capture into a per-seat tray, alternating
   turns. Movement is six pattern entries shared by both colours.

   What the build taught, beyond the design:

   - **The pawn's opening run is not a special case.** It is `ray:2`, so a piece
     directly in front stops it by the same rule that stops a rook. The design
     had it as a `range: 2` exception; it is just a short ray.
   - **`rank` wanted to be a stat on the piece, not a scope.** Stamping `col`,
     `row` and `rank` as the piece takes a square makes `rank@self` work with no
     new scope at all, and hands promotion to an ordinary computed tag. The
     `@from` scope the design reserved for this is not needed.
   - **Ownership had to move out of `predicate.lua`.** `zones` stamps `rank`,
     which counts from the owner's side, and `predicate` is built on top of
     `zones` — so `owner_of` lives in `tags.lua`, which both can reach.
   - **Activation is not a play**, so `ends_after` cannot end a turn made of
     moves. The move ends it: `on_activate` is `["move_to:target:taken",
     "next_phase"]`. `exhausts: false` for the same reason — what bounds a turn
     to one move is the handover, not the piece being spent.

   Not built, and not needed for the milestone: castling, en passant, promotion
   (the computed tag exists; nothing consumes it yet), check and checkmate.
3. **Patterns as scopes** — **half done**, and castling is what asked for it.
   `entities_in_scope` now resolves a pattern name to the cards standing on the
   squares it picks out, so `count:piece@adjacent` (a neighbourhood, anchored on
   the acting card) and `count:piece@castle_k_path` (named cells) both work.
   Still missing: the **anchor word**, so `count:piece@mine.target.adjacent` —
   "my pieces next to the one I am attacking" — cannot yet be said. That is the
   `warrior` example's third line and the only part of it still unbuilt.

4. **Absolute patterns and castling** — **done.** Castling has four
   destinations that never change, so it is a card rather than a move:

   - **`absolute` is a class word, not a marker in the pair.** `[1,1]` cannot be
     told apart from `[1,1]` by looking, so the label sits one level up and
     covers the whole list. It is a *kind* — no path, nothing to repeat — so the
     walking words are refused beside it. An absolute pattern names its `zone`,
     because a square belongs to a board where a direction belongs to whoever is
     moving. Mixing both in one piece is just two rules.
   - **`place:<who>:<col>:<row>`** — the move that names *where*, not *how*.
   - **A pattern being a scope removed the condition this step was going to
     need.** The plan called for a `slot_empty` sibling to `zone_empty`;
     `count:piece@castle_k_path` says it with what already existed.
   - **`can_play`'s escape hatch had to learn a limit.** A gated card becomes
     playable when nothing else in its zone is, so a mandatory play cannot
     soft-lock a hand — but all four castling cards are illegal most of the game,
     and that is their normal state, not a lock. Zones tagged `optional` opt out.
   - **The captured-rook trap was a bug in the engine, not a rule for authors.**
     A stat nobody carries summed to zero, so `moves_made@w_rook_h equals 0` was
     *true* of a rook taken twenty moves ago. The first fix was a `card:<key>`
     presence term beside every such gate — which is a footgun waiting for the
     one author who forgets. The real fix is in `predicate.met`: an absent stat
     now fails every comparison, `equals: 0` included, and the presence terms
     came back out. The counting and aggregate forms stay exempt, because a
     count of nothing genuinely is zero and that is how "these squares are
     empty" is written.

   Not built: castling through check (needs check), promotion (the `rank` stat
   and a computed tag exist; nothing consumes them yet), en passant.

5. **What only playing it found.** Both of these passed every test in the suite
   and were obvious within a minute of a human at a mouse:

   - **Capture was unclickable.** Hit-testing returns the topmost *card*; a
     slot-typed spec's eligible list holds *slots*; the two never met. Every test
     called `targeting.candidates` directly and so never crossed the seam. The
     fix is `targeting.aim` — pointing at a piece means pointing at its square —
     placed in `targeting` rather than in `main` so that a rule about what a
     click *means* sits where the tests can reach it.
   - **Hovering a castling card crashed the game.** `cards.cost_text` renders
     `needs` and `accepts` as well as `cost`, and only a cost is always a plain
     number; the comparison form has been legal since Lost Cities, but no card
     had ever carried one *and* been hovered. It concatenated a table.

   The lesson is not "write more tests" but where to aim them: both bugs lived in
   the gap between the rules layer, which the suite covers thoroughly, and the
   presentation layer, which it barely touches.

5. **Check** — **shipped, and by neither route this list proposed.** A computed
   tag was correctly refused here: it reads one card's own stats, and "am I
   attacked" depends on every enemy piece's reachable set.

   But the fallback proposed above — *stamp a `threat` count on every square,
   recomputed after each move* — is also wrong, and for a reason worth keeping:
   **it is the engine deciding chess is special.** A number the engine writes
   after every move, whose meaning no game file states, that has to be keyed by
   side and generalises badly past two seats.

   What shipped is a **scope word**: `@reach`, the squares a set of pieces could
   move onto, answered as the things standing there. Check is then something the
   game file *says*:

   ```json
   { "count:king@enemy.reach": { "equals": 0 } }
   ```

   Nothing is stored, so there is no recompute timing to get wrong; the owner
   word (`mine.` / `enemy.`) does the side-keying that the stat would have needed
   a second field for, and it already works for four seats. The engine gained one
   `elseif`.

   **It needed no new computation at all** — `find_moves` was already answering
   "where can this piece go" to offer the squares, and it honours `fill`, which
   is where the game file draws the line between moving and threatening. A pawn's
   step is `"fill": "empty"` and so cannot reach an occupied square; its take is
   `"fill": "enemy"` and can.

   Checkmate is strictly harder and stays its own milestone, along with refusing
   a move that leaves your own king attacked — that one needs the position
   *after* a hypothetical move, which is `entity.snapshot`/`restore`.

**Settled:** `moves` sits top-level on the card def and the engine writes the
`activate_target` from it. The alternative — spelling the spec out on every piece
— would have cost four repeated fields per template for a distinction that only
matters on a board with two grids, which no game has.
