# A row that closes up

A market row where cards enter at one end, slide along as neighbours are bought,
and are exiled from the other end. Position on the shelf *is* how old the card
is, which is the part the format could not say. **Shipped 2026-09-07**; what is
left here is the reason it was worth doing, for the next game that wants a river.

Arnak is the customer. The rule (`arnak/rules.md` §6) is one row of seven cells:
artifacts, the **moon staff**, then items — 1 artifact and 5 items at setup, and
the staff steps one cell right every round, so the artifact side grows and the
item side shrinks while the row stays seven wide. Buying slides the row *toward*
the staff to open the outer end, and a new card of that type is dealt there.
Round cleanup exiles the two cards flanking the staff before it steps.

## Shipped

**The row is one `grid: [7, 1]` zone and the staff is a card standing in it.**
Everything the two halves used to say by arithmetic the board now says by
position: which card is exiled is the one beside the staff, and where a card sits
is how long it has been on show.

- The exile is `destroy:beside` and the step is `place:self:one_right`, both on
  the staff's own ability, run by `activate_zone:row:by_column:step` at round
  start. Naming the ability is what keeps the row's other cards out of it, since
  `activate_zone` reads neither `phases` nor `cost`.
- `place` used to demand `zones.sole_grid()`, which Arnak has not got. It reads
  the board off the piece being placed now and falls back to the sole grid — a
  piece standing on a board moves about *that* board.
- A cell on `draw_from` shipped as a cell in the position argument every
  destination op already had. `tests/integration/named_cell.lua` is that word;
  `test_arnak_the_moon_staff_steps_along_the_row` is the row walking a1 to g1
  over six rounds.

**The one open question dissolved rather than being answered.** It asked how two
buy abilities in one `for_sale` tag could both claim `merge: "this"` without the
validator calling it a contradiction. The answer is that there is one buy: a card
in the row costs what it prints, in the currency it prints, so `coin_price` and
`compass_price` replace `price` and each card carries one of them. An artifact's
price badge draws a compass now, which two abilities would never have got.

And the refill needed no condition either, because **a deal aimed at an occupied
cell does nothing**: the buy compacts both sides and deals at `a1` and `g1`, and
whichever end did not open refuses its own card. Six words for both halves, with
nothing anywhere asking what was bought.

## What it is not

**A zone that closes itself up, declared once instead of asked for.** Rejected
2026-09-07 on the row this track built: Arnak's packs in *two* directions at
once, split by the staff, so a zone with one answer could not describe it — and
compaction on removal breaks the staff's own step, sliding an item into the cell
`place:self:one_right` is about to move it into. The direction and the moment
are both the caller's to know, which is what makes it a verb.

**An "until full" word on the deal.** Rejected the same day: a count is already
a maximum, and `draw_from` stops when the source empties or the destination
fills. `draw_from:deck:row:99` is a number that overshoots on purpose, and a
word for it would be a second spelling of what the count already does.

## Why it is worth more than Arnak

A row that closes up is not one game's rule. Any market with a river — Century,
Through the Ages, the deck-builder shelf pattern generally — wants cards to enter
at one end and age toward the other, and before this every one of them had to
either not care which card leaves or split the row into fixed cells. `compact`
and a cell on the deal are the whole of it; neither mentions a market.
