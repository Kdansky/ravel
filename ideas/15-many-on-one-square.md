# 15 — Several cards on one square

**Status:** answered, and the answer is *not yet* · **Size:** small for two
thirds of it, which are already built; large for the third that is not.

> *Do we need the ability to stack cards in one zone square?*

No. The question turns out to be three questions wearing one coat, and two of
them are already answered by things in the engine today — one of them by a
mechanism nobody has ever used.

---

## The three things it means

| What is wanted | Example | What answers it |
|---|---|---|
| Cards **on a card** | a buff, a weapon, a meeple on a tile, a checkers king | `attach_to_target` — **built, and unused** |
| A **count** on a square | armies on a territory, workers on an action space | a stat on the slot — **half built** |
| An **ordered run** you read down | a tableau, an expedition, a trick pile | a zone with `fan` — **shipped** |

Only the leftovers of the middle one are worth building, and none of it is
stacking.

---

## Reading 1 — cards on a card, which already works

`attach_to_target` (`actions.lua:418`) makes the acting card a child of its
target: it moves into the target's zone, takes a `parent_id`, and is appended to
the parent's `attached` list. Many children per parent, no limit. The card face
draws a badge with the count (`render.lua:698`) and the tooltip carries an
"Attached" row.

**No shipped game uses it.** Not one game file mentions `attach` — while both
`AUTHORING.md` and `SCHEMA.json` advertise it, so it is offered to authors and
taken up by none of them. That is the first thing to check before designing a
second mechanism for the same shape, and it is also a warning: a handler with no
user has never been played, only tested, so expect to find the parts nobody has
needed yet — detaching, destroying a parent that has children, what a child
costs to play, whether a child can be targeted apart from its parent.

A **checkers king is not this**, incidentally, however much the physical game
stacks two pieces. It is a promotion, which is a tag.

---

## Reading 2 — a number on a square, which is nearly built

Where the pieces are interchangeable — five armies, three workers, a stack of
backgammon checkers you never name individually — what is wanted is a *number*,
not five card entities. And a square is already an entity that can carry one:

```lua
stats = { col = (idx - 1) % cols + 1, row = math.floor((idx - 1) / cols) + 1 }
```

`zones.lua:74`, with the comment that says why: *"as ordinary stats, so a
condition reads it with the vocabulary it already has (`row@target`) rather than
the engine growing a second way to ask for a number."* That is the whole design
already made.

**Reading works.** `predicate.total("row@target", ctx)` on a live chessboard
returns the square's row.

**Writing does not, and the reason is not the one you would guess.**
`change_stat` has no idea what kind of entity it is given — anything with a
`stats` table is fair game. The block is one line in `predicate.bearers`
(`predicate.lua:193`):

```lua
if e.stats and e.stats[p.arg] ~= nil then out[#out + 1] = e end
```

A stat may only be *changed* on something that already has it, and a square has
no way to declare a starting one. So `stat_gain:armies@target:5` aimed at a
square silently does nothing.

**The whole feature is therefore: let a grid declare per-square stats.** One
field on the zone, defaults copied into each slot where `col` and `row` are
already written. Reading, arithmetic, conditions, targeting and the tooltip all
work the moment the number exists, because none of them ever cared that the
bearer was a card.

**It is not, however, what check needs**, which is how it was first filed here.
`threat` is stamped by the *engine* after each move, exactly as `col` and `row`
are stamped when the square is built — and a stat the engine writes never needed
declaring, because `bearers` only asks that the stat already exist. The field
below is for numbers an *author* writes, and the honest position is that no game
has asked for one yet.

---

## Reading 3 — an ordered run, which shipped

The `fan` style property, see [DONE.md](DONE.md). A tableau, an expedition and a
pile of won tricks are all a *zone*, not a square, and a zone that spreads out is
readable now. Klondike still wants the reach half — dropping onto the top card
rather than onto the zone — and that is [01](01-boardgames.md) gap 3.

---

## What none of the three covers

A stack where each card keeps **its identity, its order, and an addressed
square**, all three at once. Backgammon is the clean example: which point, how
many, and whose — and the order matters because only the top one moves.

**Nothing on the capability ladder asks for it.** Checkers' king is a tag,
Klondike's columns are zones, Hearthstone's buffs are attachments, chess and Go
are one per square by rule. The first honest customer is a game nobody has
proposed.

## What it would cost

`occupant` is a single id, read in sixteen places across `targeting.lua`,
`zones.lua`, `geometry.lua`, `predicate.lua` and `render.lua`. The count is not
the problem — the *questions* are. One line carries most of it
(`geometry.lua:82`):

```lua
if not pat.phasing and entity.get(sid).occupant then break end
```

Movement blocking asks a square "is anybody there". A stack turns that into "how
many, whose, and does one enemy still block a slide" — and every rule that says
*the piece on that square* has to start saying **which** piece. `place_in_slot`'s
`on_occupied` (`zones.lua:303`) currently chooses between refusing, destroying,
and moving the occupant to a tray; with a stack it needs to say *which occupant*,
or that the arrival goes on top and displaces nobody, which is a fourth answer
and a different rule.

**The rendering is no longer an argument either way.** It used to be the visible
objection; `fan` solves it for free, and a square-sized fan is the same
arithmetic in a smaller box.

---

## Refuse, for now

- **Building it before a game needs it.** The discipline that produced `fan` was
  waiting until Lost Cities was unreadable and Klondike had asked for the same
  thing independently. Nothing has asked for this once.
- **Making `occupant` a list "just in case".** Every one of those sixteen reads
  becomes a question with two answers, and the second answer is a guess until a
  real game says which it wants.
- **A second attachment mechanism.** If many-on-one is what a game needs, the
  first move is to use `attach_to_target` and find out where it is thin.

## Do instead, when something asks

1. **Per-square stats** — small, and it removes most of the demand for stacking
   by removing the cases where the pieces are alike. Not urgent: no game has
   asked, and the second customer this was filed with turned out not to be one.
2. **Play something through `attach_to_target`**, so the mechanism that already
   exists stops being theoretical.
3. **Only then**, and only with a game in hand, decide whether a square holds a
   run of cards — and expect it to look like a `fan` in a cell, because the
   layout question is the one part already answered.
