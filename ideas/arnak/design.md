# Arnak, as a game file

What `game/games/arnak.json` is, what it does with each of the rulebook's
rules, and every place it says something the printed game does not. Read
[rules.md](rules.md) first for what the game actually is; read
[../21-lost-ruins-of-arnak.md](../21-lost-ruins-of-arnak.md) for the research
that priced it. This file is the third thing: the record of the build.

```
luajit check.lua arnak.json      silent
luajit play.lua arnak.json 7     two seats, five rounds
luajit tests/run.lua arnak       nine scripted tests
```

Hand-written, no generator. Sixty-one card templates and twenty-one zones is
past the "write a script" line [AUTHORING](../../AUTHORING.md) draws at a
couple of dozen — and the reason it stays readable is that **no card in the
file carries an action list.** Every rule lives on a tag; a card is its name,
its picture and the numbers printed on it. Nineteen site tiles, sixteen market
cards, four assistants and three basics, and between them not one duplicated
line of behaviour for a generator to have kept in step.

---

## The one decision the file rests on

**A hand is a zone of abilities, not a zone of plays.**

Arnak's central verb is that a card in hand is played *either* for its printed
effect *or* for its travel value, never both. Ravel has one `play` block per
card, so the choice has to live somewhere else, and there were three places it
could:

| | Why not |
|---|---|
| `play.action: ["options:for_effect,for_travel"]` | the effect would then have to be reached with `copy:`, and `copy` carries no targets and pays no costs — a whole second set of rules to keep straight |
| two destination zones, `move_to:target`, and the destination's `receive.action` | four more zones of screen for a distinction the play area does not draw |
| **`use: "abilities"` on the hand, and two abilities per card** | — |

The third is what the file does. `hand` says `"use": "abilities"`, and every
card in the deck carries an `effect` ability and a `travel` ability. Clicking a
card opens the chooser the engine already builds for a card with more than one
thing to do; each half is gated separately by its own `cost`, which is exactly
the difference the rulebook draws — playing for travel is free, playing an item
for its effect is your main action.

**The two halves live on tags, not on cards.** `deck_card` grants the travel
ability to everything in a deck; `basic`, `item` and `artifact` each grant the
effect half with the cost that kind of card charges — nothing, a main action, a
main action and a tablet. `site` grants the three a site space has, and
`assistant` the one an assistant has. A card names its tags and prints its
numbers, and that is the whole of a card.

Three more things fall out of it that no other spelling gives:

- **Fear is a card with one ability.** No `effect` half at all, so the chooser
  never appears and clicking it spends it for travel. *This chip does nothing*
  said without a special case.
- **The market can lend the same card a third thing to do.** The `row` zone
  `applies` a `for_sale` tag whose buy ability says `"merge": "this"`, so a card
  lying on the shelf is merchandise and its own two abilities go quiet. Take it
  into a hand and they come back. The moon staff stands in the same zone and so
  is handed the same ability — which is why its own step says `"merge": "this"`
  too, or the shelf would have silenced the furniture.
- **`ends_after` never had to be right.** Activating is not playing, so the
  play counter is not measuring anything, and the turn ends when a button says
  it does.

Nothing else in the file is a new idea. Everything below is bookkeeping around
that one.

---

## Rule to construct

| The rulebook says | The file says |
|---|---|
| five rounds, then score | `round_no` on the `clock` card, raised in `round_start`; the route out is `{ "when": "round_no@clock >= 6", "then": "scoring" }` |
| one main action a turn, plus free actions | a `main` stat, set to 1 by the `turn` phase's `actions`, spent as `{ "main@mine.player": 1 }` by everything the rulebook calls a main action |
| pass, and be skipped for the rest of the round | a `passed` stat and three routes on `turn`: both passed → `cleanup`; the *other* one passed → `turn` with `"seat": "same"`; otherwise `turn` with `"seat": "next"` |
| two archaeologists, no more | two `digger` cards in each seat's `camp`. They are the limit, so there is no number to keep: a figure out on the board is not at home to be sent |
| a space is occupied for the rest of the round | a figure is standing on it. `where: ["count:digger@attached_to.target == 0"]` on the dig, so a site with somebody on it is not offered — a fact about the board rather than a number on either player |
| five resource types | five stats on the player card |
| a card's travel value, spent as a second currency | `trek` printed on the card, `travel` banked on the player and zeroed at the start of every turn |
| dig at a site: pay its travel cost, resolve its effect | one ability on the `site` tag, whose cost reads the toll off the tile: `"travel@mine.player": "toll@self"` |
| a guardian wakes when a site is discovered | the island's `receive` deals one from `guard_deck` onto the arriving site: `draw_from:guard_deck:target:1`, a destination that names a card. The five that start face up are cleared in `setup` |
| a guardian does not block digging | nothing in the dig asks about `guard`, so one ability serves both. The two used to differ by a line that raised a counter, and the counter is gone |
| overcome one by paying a flat price | the guardian's own ability. It knows its price (`sum:g_arrow@self`) and asks who is standing under it — `count:digger@mine.attached_to.host_of.self >= 1`, *one of mine is on the site I am lying on*. No `exhaust`, so a figure spent digging can still fight later, which is the rulebook |
| an archaeologist coming home from a guarded site earns a Fear card | literally that. `afraid` is a computed tag, `["count:guardian@attached_to.host_of.self >= 1"]` — *something is still lying on the site I am standing on* — and `cleanup` deals `count:afraid@mine.everywhere` before `move:each.digger:origin` sends the figures home |
| discovery reveals a printed position | the position is a `pos_1`/`pos_2` marker card sitting in the `island` grid, tagged `level_1`/`level_2`. A figure is sent to it: `purge:target` and then `draw_from:site_1_deck:island:1`, and the freed cell is the only one the grid has. Two abilities rather than one, because two decks are two things |
| idols come only from discovery | `create:mine.idols:idol:1` in the same list, before the marker is destroyed |
| slot an idol, free, once, for one of several effects | `"when": ["used@self == 0"]` and `options:idol_coin,idol_compass,idol_dig,idol_draw` |
| the card row, split by the moon staff | one `grid: [7, 1]` zone with the staff standing in it as a card. Its own ability is `purge:beside`, `place:self:one_right`, a `compact` of each side and two artifacts dealt at the near end — run by `activate_zone:row:by_column:step` at round start, which names the ability so that nothing else in the row is activated. Position on the shelf is how old a card is, so the exile is the rulebook's card rather than an arbitrary one |
| buying refills the row | the buy compacts both sides towards the staff and deals at `a1` and `g1`. Whichever end did not open refuses its own card, since a cell holds one — so one list serves both halves and nothing asks what was bought |
| an item costs coins, an artifact costs compasses | one `for_sale` tag, and two price stats: a card costs what it prints, in the currency it prints. `coin_price` on the items, `compass_price` on the artifacts, each drawn with its own icon |
| a bought card goes to the bottom of your deck | `move:self:mine.bag:bottom` |
| round cleanup: shuffle the play area and put it under the deck | `each_seat:shuffle:mine.table` then `each_seat:move:mine.table:mine.bag:99:bottom`. Cards bought during the round are already down there, so they are drawn first — which is what the rulebook's parenthesis means |
| research: two tokens, the notebook never above the glass | six row cards, each with a `glass` and a `note` ability. The notebook's is gated `["note@mine.player == n−1", "glass@mine.player >= n"]`, and that second clause is the whole rule |
| the Lost Temple is the glass's alone | `res_6` has no `note` ability |
| first to the temple scores most | `activate_zone:rules_temple`, one card, `"when": ["temple_taken@clock == 0"]` |
| assistants recruited from the track, exhausted on use, refreshed at cleanup | `draw_from:assistant_box:mine.assistants:1` on two notebook rows; `"cost": { "exhaust": 1 }` on each assistant; the round boundary readies them with everything else |
| final scoring, six categories | six `each_seat:` lines in `scoring`, then `activate_zone:rules_win` to set the reserved `won` stat |

---

## What a card says without being read

A card's yield is **one number, read twice**: the badge draws it and the ability
spends it. `it_camera` prints `y_tablet: 2` and `y_coin: 1`, its style lists
those keys among its badges, and the ability the `item` tag grants says

```json
"stat_gain:tablet@mine.player:sum:y_tablet@self",
"stat_gain:coin@mine.player:sum:y_coin@self",
```

for every resource, unconditionally. A card that prints none of a thing gains
none of it and says nothing about it: `sum:` over a card with no such stat is
zero, `change_stat` returns early on a delta of nothing, and a badge list with
`badge_zeros: false` leaves the line out. So one action list serves forty cards,
the printed card and the rule can never drift apart, and
`test_arnak_a_card_pays_out_exactly_what_it_prints` is the assertion that says
so.

Written the obvious way instead — an action list per card — the badge would have
been a *second* copy of the same number, and the file's own record of what a
card does would be the thing least likely to be right.

Two rules keep the badges legible, and both are about width rather than taste:

- **`badge_run: "down"` wherever a card is portrait** (hand cards, market
  tiles), because a column leaves the title its full width and a row takes it
  away. Board tiles are wide and short, so their badges run along the bottom.
- **No deck card yields more than two things**, which caps its badge column at
  five — price, points, travel value and two yields — and that is what a market
  tile is tall enough to draw. `it_tent` was the one card over the line and gives
  two coins and a compass instead of three separate things.

The other constraint is the screen's, not the format's: **the stat readout is
hard-anchored to the top-right corner**, so roughly `x > 0.86, y < 0.40` is
unusable and the layout is built around a hole. That is
[07](../07-presentation.md)'s open gap, met from the authoring side.

---

## Where it says something the printed game does not

Every one of these is deliberate. The ones marked **§13** are places the
rulebook's own numbers did not survive text extraction, so the file is
inventing a number rather than diverging from one.

1. **Two seats, always.** The 2-player blocking tiles are in force, which the
   real rules say means every starting site has exactly one space — so the file
   never has to model a second space at a site at all. Three and four players
   would need the second spaces, and those are one more card each, not a
   different shape.
2. **One travel currency instead of five icons and a hierarchy.** A card's
   `trek` is a number and a site's `toll` is a number. The Travel Hierarchy is
   **§13.1** — it exists, it is printed on the quick-reference sheet, and it did
   not survive extraction. `pays_for` on the stats section would express it
   exactly, one line per icon, the day the ordering is known. Nothing else in
   the file would change.
3. **Site and region costs are invented** (**§13.2**), as are the per-site
   yields. They are priced to be playable, not to match the board.
4. ~~**The guardian is folded into the site tile.**~~ **Closed.** A guardian is a
   card lying on the site, dealt from `guard_deck` by the island's own `receive`
   as the site arrives, and it carries its own price. Eleven of them, sixteen
   tiles; the real game has 36 with boons as well, and the boons are still out
   (**§13.9** — that table is not in the rulebook either). The five sites that
   start face up are cleared in `setup`, which is the sense in which they are
   known: `purge:each.guardian` before the first round.
5. ~~**Fear is counted, not tracked per figure.**~~ **Closed.** It is tracked per
   figure now, because there are figures: an archaeologist is a card standing on
   the site, `afraid` is the computed tag `["guard@host_of.self >= 1"]`, and
   cleanup counts it. The exploit it left behind — dig the best-yielding guarded
   site, then pay off the cheapest guardian anywhere on the board, because
   `overcome`'s only gate was a per-seat tally — is closed with it. See
   [36](../36-a-card-on-a-card.md).
6. **You keep nothing from your hand.** The rulebook lets a player choose which
   hand cards to keep into the next round; here the whole hand joins the play
   area at cleanup and everyone draws five fresh. Keeping would want an offer
   per seat inside an automatic phase, which is a `show:` in a place the engine
   deliberately refuses to move a seat from.
7. **Buying an artifact does not resolve it for free.** In the real game an
   artifact goes to your play area and you may use its effect at once, and only
   a *later* replay from hand costs the tablet. Here every bought card goes to
   the bottom of the deck, and playing an artifact from hand costs the main
   action plus the tablet. The surcharge is kept because it is the
   characteristic rule; the free first use is dropped because it is the half
   that needs `copy:`.
8. **Research rows score 2 points each and the track is a line, not a graph.**
   Six rows, one edge between each pair, one price per row. The real track
   branches and its row values are irregular; the branching is content, not a
   gap — one card per position and one ability per edge — and it is left out
   only for size. Temple tiles are folded into the Lost Temple's own 5 points
   plus 5 for arriving first.
9. **Four idol effects, on the idol rather than on four numbered player-board
   slots**, and no empty-slot bonus (**§13.6** — the printed values were not
   recovered). An idol is worth 3 points whether slotted or not, which is the
   real rule.
10. **Four assistants, one side each.** No silver/gold upgrade, so the research
    rows that would upgrade one recruit another instead.
11. **Starting resources follow the secondary source** (**§13.5**): South opens
    with 2 coins, North with 1 coin and 1 compass, written as `card_stats` on
    the seat cards.
12. **Score may go below zero.** Real Arnak scores never do in practice; the
    stat's floor is −99 so that a player who does nothing at all still reads
    −2 for their two Fear cards rather than a clamped 0, which would be a lie.

---

## What the build found that the research did not

[21](../21-lost-ruins-of-arnak.md) predicted the shape of worker placement
correctly — the space carries the `exhaust`, the player carries a capped
counter, and the two gates compose. It was right, and
`test_arnak_a_space_is_taken_and_an_archaeologist_is_spent` is that prediction
written as an assertion. Three things it did not say:

**`when` gates whether an ability is *offered*, not only whether it happens.**
`flow.usable_abilities` asks `predicate.meets_all(a.when, ctx)` alongside the
phase and the cost, so a card with three abilities and mutually exclusive
`when` clauses shows the player exactly the one or two that apply — a site with
a guardian offers *Dig* and *Overcome*, and the same site once cleared offers
one. AUTHORING describes `when` as "whether the ability happens at all", which
is true and is not the half that carries this file.

**`merge: "this"` is load-bearing for any card that is merchandise before it is
a card.** Without it, a card lying on the shelf would offer its own *play it
for travel* to whoever is up. Puzzle Strike's bank found this first; a market
row of cards that are also hand cards is the case that makes it unavoidable.

**A grid cell freed and refilled in one action list is safe, and only because
it is one.** `purge:self` then `draw_from` works because there is exactly one
free cell at that instant. Two markers destroyed and then refilled would land
in whichever order the grid hands out free slots, which is not a thing the
format promises.

---

## What the engine has no word for

Neither of these was worked around with a new field — both are recorded here
and nowhere else.

**~~1. Dealing into a named cell.~~ Shipped 2026-09-07**, and the card row with
it: one `grid: [7, 1]` zone, the moon staff a card standing in it, `purge:beside`
for the exile and `place:self:one_right` for the step. The word is a cell in the
position argument every destination op already carried, so `draw_from:item_deck:row:1:g1`
deals at the far end and a deal aimed at an occupied cell does nothing — which is
what lets one refill serve both halves of the row without asking what was bought.

**1. ~~Who spent a card's exhaust~~ — the question stopped being asked.** The
engine records that a card is exhausted and not by whom, and the shared site
space is the thing that hurt. Two answers were written; the second is the one
that shipped.

**The stamp**, which worked and was not used: the ability paying the exhaust
names the spender itself — `stat_set:spender@self:sum:side@mine.player` — and the
gate asks it back. Checked end to end on a two-seat fixture and offered to the
spender alone. It costs a stat declared on every bearer, a wipe on the round
boundary that nobody may forget, and a number standing where a pointer was meant.

**The figure**, which shipped. A stamp is a number where a pointer was meant: it
says *you took some space*, never *you took this one*, and it needs declaring on
every bearer, wiping every round, and a cleanup line nobody may forget. An
archaeologist standing on the site is a card, cards have owners, and the site is
occupied because somebody is on it. `guarded`, `workers` and the `exhaust` on the
space all went; `overcome` gates on `guard@host_of.self`. See
[36](../36-a-card-on-a-card.md), and `tests/integration/attachment.lua` for the
engine half.

**One thing got worse, on purpose.** Discovery no longer earns a Fear card. The
figure that discovers cannot be put on the site it turned up: `draw_from` deals
into a grid cell and nothing can name the card that lands in it, so there is no
host to attach it to. The guardian is dealt there and waits for whoever digs
next, which is a smaller divergence than the counter was. Closing it wants a card
that is already on the board face down rather than a deal — an unexplored
position holding its site tile from the start — which is a different feature and
has no other customer yet.

---

## Where things are

| | |
|---|---|
| the turn, and how a round ends | `phases`: `turn`'s three `next` routes |
| the moon staff | the `moon_staff` card, and `market_first` in `rules_market` for the opening deal |
| what every kind of card does | the `tags` section — `deck_card`, `basic`, `item`, `artifact`, `site`, `assistant` |
| what a card is worth | its `card_stats`, and the badge list of the style it wears |
| discovery | `pos_1` and `pos_2`, the only two cards with abilities of their own |
| the research track | `res_1`..`res_6`, and `first_temple` in `rules_temple` |
| scoring | the `scoring` phase, and `win_south`/`win_north` in `rules_win` |
| the buttons | `end_turn` and `pass_turn`, in the `controls` zone |
| what is asserted about all of it | `tests/integration/arnak.lua` |
