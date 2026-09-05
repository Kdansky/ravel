# A row that closes up

A market row where cards enter at one end, slide along as neighbours are bought,
and are exiled from the other end. Position on the shelf *is* how old the card
is, which is the part the format cannot currently say.

Arnak is the customer. The rule (`arnak/rules.md` §6) is one row of seven cells:
artifacts, the **moon staff**, then items — 1 artifact and 5 items at setup, and
the staff steps one cell right every round, so the artifact side grows and the
item side shrinks while the row stays seven wide. Buying slides the row *toward*
the staff to open the outer end, and a new card of that type is dealt there.
Round cleanup exiles the two cards flanking the staff before it steps.

## What the file does instead

`arnak.json` splits the row into two fixed `grid: [5, 1]` zones and models the
staff by counting: `market_staff` runs `destroy:artifacts:1`, `destroy:items:1`,
`draw_from:artifact_deck:artifacts:2`, netting one artifact more and one item
fewer each round. `test_arnak_the_moon_staff_moves_one_slot_a_round` asserts
1/5 → 2/4 and six cards, which is all the file can promise.

**Which card is exiled is arbitrary.** `destroy` (`actions.lua:689`) collects the
scope, `table.sort(doomed)` on entity id, and takes the first. Ids are handed out
at setup in the deck's `contents` order and `zones.shuffle` permutes `z.cards`,
not the ids — so the lowest id on the shelf has nothing to do with how long it
has been on display. Deterministic per seed, wrong per the rulebook. No test can
see it, because there is nothing to compare against.

## The shape

One `grid: [7, 1]` zone, and **the staff is a card standing in it.** Two thirds
of the rule then need no new words:

- **The exile is `destroy:beside`** on the staff's own ability. `beside` is the
  documented pattern `{"vectors": [[1,0],[-1,0]], "class": ["step"]}`, a pattern
  used as a scope anchors on the acting card's square, and a gap breaks adjacency
  for free — so a flank already bought is simply not destroyed, which is right.
- **The staff steps with `place:self:<pattern>`.** `place` already resolves a
  pattern to a square (`actions.lua:1030`).

This also deletes the offscreen `market_staff` counter, which is bookkeeping
pretending to be a marker.

## What is missing

**1. ~~`compact:<scope>:<pattern>`~~ — shipped 2026-09-05.** Every card the scope
names slides as far along the pattern as free cells allow. Scope-first the way
`move` is, so the two sides of the staff are two lines.

The ordering was the part that needed thinking about and it is not what this
file first said. Sliding each card as far as it goes is *not* order-independent:
taken as the scope hands them over, a card behind can reach the far end first
and overtake one in front, and the row then holds the same cards while saying
nothing true about them. The handler sorts by position along the direction and
moves the furthest card first, so everything behind stops against a wall that is
already final — one pass, no settling loop, and the same answer whatever order
the scope produces. `test_compact_a_gap_closes_and_the_order_survives` is that,
written as the case that would silently pass without it.

The direction is the pattern's, taken as written rather than turned around per
owner: a shelf slides one way for everything on it. How far is the pattern's
too — a `ray` runs to the end, a bare pair is a one-cell nudge — so the
validator's job is only to refuse what has no direction at all: an absolute
pattern, or one carrying more than a single vector.

**2. A cell on `draw_from`, still open.** After compaction the free cells are the two outer
ends, and `draw_from` fills through `zones.auto_slot`, which takes the first free
slot *by index* — a1 for artifacts, which is right, and the leftmost free cell
for items, which is exactly wrong. `draw_from:<deck>:<zone>:<n>:<cell>`. The word
exists on three verbs already (`setup.place.at`, `place:<who>:<where>`, `move_to`
into a slot); this is the fourth.

Cleanup then reads:

```json
["destroy:beside", "place:self:staff_step",
 "compact:row.artifact:rightward", "compact:row.item:leftward",
 "draw_from:artifact_deck:row:1:a1", "draw_from:item_deck:row:1:g1"]
```

**The buy does the same thing, minus the staff.** `for_sale_item`/`for_sale_art`
today end in `draw_from:item_deck:items:1`, which drops the new card into the
hole the bought one left — under the new shape the hole must close first and the
card enter at the end, so each buy gains a `compact` and its `draw_from` gains a
cell. The rulebook says "at the end of a turn that bought a card"; the file
refills inside the buy, and that stays, being the same moment in practice.

## The one open question

Sharing a zone means the `applies` tag can no longer say which kind a card is —
one zone hands out one set of tags to everything lying in it. The card templates
already carry `item` and `artifact` tags, so the buy gates move to
`tagged:artifact@self >= 1` and the two buys become two abilities of one
`for_sale` tag.

Both need `merge: "this"`, without which a card on the shelf offers its own
*play it for travel* to whoever is up — the reason design.md calls that field
load-bearing. **And two abilities of one tag both claiming `merge: "this"` is
what `validate.lua` now warns about**, in the message fixed on 2026-09-05.

The warning is static and does not read `when`, so it cannot tell a real
contradiction from two claims that are mutually exclusive by construction. Either
the two buys are written so only one claims, or the check learns that exclusive
`when` clauses are not a contradiction. [Assumption: the second is the truer
answer, since a card that is merchandise *and* has a type is not a rare shape —
but it widens a diagnostic that exists precisely because it is cheap and static,
so it is a decision rather than a fix.]

## Why it is worth more than Arnak

A row that closes up is not one game's rule. Any market with a river — Century,
Through the Ages, the deck-builder shelf pattern generally — wants cards to enter
at one end and age toward the other, and every one of them currently has to
either not care which card leaves or split the row into fixed cells.
