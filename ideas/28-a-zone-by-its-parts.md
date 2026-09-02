# 28 — A zone by its parts

**Shipped** (2026-08-26). A zone's `type` answered seven questions at once; the
seven are asked separately now.

## Still open — where a destroyed card goes

*From `todo.md`: "the bank should be where trashed cards go by default, in all
cases — so if Argagarg's Bubble Shield takes a gem off a pile it goes back to the
bank without extra logic. The zone half of this is done (`status: "supply"`, and
moving a card into one already turns it back into stock); what is missing is the
default destination, so nothing has to name the bank."*

`zones.add` already reclaims: put a gem into a supply and it stops being a card
and becomes that pile's `stock` going up. What has no answer is the *other*
direction. `destroy_card` unhooks the card from its zone and clears its stats
(`zones.lua:569`), and `HANDLERS["destroy"]` calls it directly — so a chip that
leaves a player's deck leaves the game, and a game whose components are finite
has to name the bank at every site that removes one.

The rule wanted is: **a destroyed card goes back to the supply that stocks its
kind, if there is one, and out of the game otherwise.** No verb changes, no field
is added, and `destroy:` keeps meaning "take this out of play".

Three things it has to decide, and none of them is obvious:

- **What "the supply that stocks its kind" means when two zones do.** [Assumption:
  the lookup is by `def_key` against the supply zones that already hold a face
  card of it, which is what `face_card` answers; a def stocked by two supplies is
  an authoring error the validator should refuse rather than a precedence rule
  the engine invents.]
- **Whether a supply that has never held the def counts.** A bank that starts
  with eight 1-gems has a face card for `gem_1`; a bank that has been emptied to
  zero still has one, because `zones.add` keeps the face card and moves the
  number. [Assumption: a supply that has *never* held the kind is not its home,
  so a game that wants the box to take back a card it never dealt says so with a
  `contents` line of `:0`.]
- **Whether this is `destroy` or something beside it.** Reclaiming is a real
  change to what `destroy:` does in every game that has a supply — Splendor's
  tokens, Puzzle Strike's gems. [Assumption: it is the same verb; the games where
  it changes behaviour are the games that wanted it, and a second verb makes
  every author choose between two words for one act.]

`zones.destroy_card` is the single choke point — `HANDLERS["destroy"]`,
`destroy_self` and the grid's `on_occupied: "destroy"` all reach it — so the
change is one lookup there.

## Why it reopened

[06](06-schema-and-types.md) gap 1 surveyed the matrix and refused the split,
naming the condition to revisit on: *a game genuinely wants a combination no
current type offers.*

Puzzle Strike is it. Its ongoing chips are laid face up in a row in front of one
player — an unbounded row of separately readable cards that are **in play**.
Every existing type gets one half and loses the other: `grid` is in play and
bounded to fixed cells, `hand` is an unbounded row and secret and not in play.
It took `hand`, and the bill came in twice: `from: "board"` could not reach it,
so four chips were dead; and eight more rules read "in play" as
`zone_type == "grid"`, so a chip on the row was not counted, could not be
sacrificed, and never acted by itself.

The refusal also stood against the *shape* it was offered in — tags. A validator
can reject a contradiction; it cannot supply a default or keep two words that
must move together in step. So: fields.

## The seven

| Field | Values | Default | What it decides |
|---|---|---|---|
| `layout` | `stack` · `row` · `grid` · `page` | `stack` | where cards are drawn, the arrival animation, whether there are addressable slots — and therefore whether capacity is bounded |
| `visibility` | `public` · `owner` · `secret` | `public` | purely what is drawn and what may be read |
| `reach` | `all` · `top` | `top` on a stack, else `all` | which cards exist as far as the rules go |
| `use` | `play` · `abilities` · `none` | `play`; `none` where nothing can be seen | what may be done with a card here **at all** — the ceiling, which a phase's `zone` narrows |
| `status` | `board` · `exile` · `offer` · `supply` | `board` on a grid, else `exile` | what standing a card here has in the rules |
| `display` | `onscreen` · `offscreen` | `onscreen` | whether the zone is drawn and anything in it clickable |
| `copies` | `one` · `per_seat` | `one` | one zone, or one per seat |

**Enums, never booleans.** The room was wanted immediately: `offer` is a third
`status` and `supply` a fourth, and it is why the field is not `in_play` — a question that stops being
a yes/no must stop wearing a yes/no's name. MTG's graveyard is the next one
waiting.

**A value names its own parameter field.** `layout: "grid"` makes `grid:` legal
holding `[cols, rows]`; `layout: "row"` makes `row:` legal holding the fan
direction. Not new — it is the existing idiom made a rule, so a parameter never
needs a name invented for it. Every enum value on all seven fields is therefore
reserved against being a field name.

**Row absorbs fan**, because a row is a fan whose overlap is off. Named `row`
rather than `fan` because the absent parameter must be the common case: call it
`fan` and every hand writes `"fan": "none"`. `stack` stays its own value though
it is the far end of the same continuum — 73 of 137 zones are stacks, and
`"layout": "row", "row": "stacked"` is a worse spelling of the commonest thing
in the format. `display` needs its own word rather than folding into
`visibility`, because a deck is drawn, counted, and unreadable, and one word
cannot be both.

## The old types were presets

```
deck    = stack · secret · top · none      · exile
pile    = stack · public · top · play      · exile
hand    = row   · owner  · all · play      · exile · per_seat
grid    = grid  · public · all · abilities · board
options = row   · public · all · play      · offer
```

The bundles were never wrong, only closed. What the split buys is the
combinations nobody was allowed to write: the ongoing row; an infinite board
(the same without the activation — capacity is bounded by `grid:` being present
at all); a trash that is nameable but not clickable, countable or sacrificeable;
and a face-down board, whose mirror — a face-up deck that stays unsearchable —
06 had already flagged as a bug worth fixing on its own.

## What changed on the way

**`use` defaults to `play`, not to `none`.** Inert-until-it-says-otherwise is
right for `status`, where a forgotten word leaves a card uncounted; for `use` it
fails the wrong way, since a game whose zones are all `none` has nothing
clickable and no way to tell why. What made it cheap anyway is the second half —
**cards nobody can see cannot be picked out of the zone** — so a secret zone is
`none` unless it says otherwise, and that alone is what makes a deck a deck. A
deck is two words now.

**Two more defaults come from a neighbouring field**: a `stack` is reached from
the top, a `grid` is in play. Without them the corpus would write
`"reach": "top"` seventy-three times and this would have delivered exactly the
"five or six words a game must keep consistent" that 06 refused it for. Each is
a default and not a rule — Lost Cities' expedition is a `row` that says
`reach: "top"`, a scoreboard is a `grid` that says `status: "exile"` — which is
the whole difference between this and reading the rules off the shape.

**`use: "abilities"`, not `"activate"`.** The parameter rule settled it
mechanically rather than by taste: the value would reserve `activate:`, which a
zone already uses for its own ability. The value moves, not the block.

**One latent bug fell out.** Puzzle Strike's Bubble Shield answers a crash from
the ongoing row and never said `from: "board"` — it was caught by the *default*,
"a reaction played out of a hand", because that row was a `hand` as far as the
engine was concerned. Once the row said what it is, the default stopped covering
for it. Same class as the four this idea opened on, found by the fix.

The corpus got **shorter**: 292 zone declarations, four generators and both
documents moved, and three defaults come from a neighbour.

## Decided

- **Fields, not tags**, for 06's reason.
- **No `type` shorthand kept alongside.** One question, one spelling; a preset
  beside the fields it expands to is the same question asked twice.
- **`face_up`/`face_down` stop being tags** — they are `visibility` values that
  were wearing tag clothing.
- **Visibility is rendering only.** A card in play may be unreadable and a card
  nobody can touch may be plain to see, so nothing else may read it.
- **`use` holds one value.** No game has wanted a zone you may both play from
  and activate in.
- **Playability needs zone *and* phase to agree.** `use` is the ceiling, the
  phase's `zone` is the gate, neither alone is permission.

## Refused

**`no_peek` deleted rather than given a field.** All three uses sat on zones that
were already offscreen, and an offscreen zone cannot be hovered or browsed, so it
had never refused anything. What went with it is a combination nothing has asked
for — the top card public and the rest unsearchable — because browsing
deliberately reaches past `reach: "top"`. A known hole rather than an oversight.
