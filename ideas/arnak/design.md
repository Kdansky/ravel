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
- **The market can lend the same card a third thing to do.** The `items` and
  `artifacts` zones `applies` a `for_sale_*` tag whose buy ability says
  `"merge": "this"`, so a card lying on the shelf is merchandise and its own
  two abilities go quiet. Take it into a hand and they come back.
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
| two archaeologists, no more | `workers`, set to 2 each round, spent 1 at a time by Dig and Discover |
| a space is occupied for the rest of the round | `"exhaust": 1` in the dig ability's cost. `ends_round: true` on the cleanup route readies every one of them at once |
| five resource types | five stats on the player card |
| a card's travel value, spent as a second currency | `trek` printed on the card, `travel` banked on the player and zeroed at the start of every turn |
| dig at a site: pay its travel cost, resolve its effect | one ability on the `site` tag, whose cost reads the toll off the tile: `"travel@mine.player": "toll@self"` |
| a guardian wakes when a site is discovered | `guard: 1` in the revealed tile's `card_stats`; the tile *is* the guardian |
| a guardian does not block digging | a second ability, `dig_guarded`, gated `"when": ["guard@self >= 1"]`, identical except that it raises `guarded`. `when` decides which of the two is *offered*, so the player is shown one |
| overcome one by paying a flat price | a third ability, no `exhaust`, so an exhausted space still offers it. Its price is read off the tile too — `g_arrow`, `g_tablet`, `g_jewel` |
| an archaeologist coming home from a guarded site earns a Fear card | `each_seat:fill:mine.table:fear:sum:guarded@mine.player` in `cleanup`, then the counter is cleared |
| discovery reveals a printed position | the position is a `pos_1`/`pos_2` marker card sitting in the `island` grid. Discovering it runs `destroy_self` and then `draw_from:site_1_deck:island:1`, and the freed cell is the only one the grid has |
| idols come only from discovery | `fill:mine.idols:idol:1` in the same list, before the marker destroys itself |
| slot an idol, free, once, for one of several effects | `"when": ["used@self == 0"]` and `options:idol_coin,idol_compass,idol_dig,idol_draw` |
| the card row, split by the moon staff | two zones and two rule cards in `rules_market`, gated on the round: the first round deals one artifact and five items, and every round after exiles one of each and deals **two** artifacts. The row is always six wide and one slot crosses every round, with no arithmetic in it |
| buying refills the row | `draw_from` of one, in the buy ability, so the shelf fills before the next player looks at it |
| an item costs coins, an artifact costs compasses | two tags, `for_sale_item` and `for_sale_art`, differing in one word of one cost map |
| a bought card goes to the bottom of your deck | `move:self:mine.bag:bottom` |
| round cleanup: shuffle the play area and put it under the deck | `each_seat:shuffle:mine.table` then `each_seat:return_to:mine.table:mine.bag:bottom`. Cards bought during the round are already down there, so they are drawn first — which is what the rulebook's parenthesis means |
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
4. **The guardian is folded into the site tile.** Arnak has 36 guardian tiles
   with their own costs and boons; here the tile that is revealed carries
   `guard: 1` and its own overcome price, and no boon. **§13.9** — the tile
   table is not in the rulebook either. Two prices are used: Level I guardians
   cost an arrowhead and a tablet, Level II two arrowheads and a jewel.
5. **Fear is counted, not tracked per figure.** The real rule is *this
   archaeologist came home from a site that still had a guardian*. The file
   raises `guarded` when you dig at a guarded site and lowers it when you
   overcome one, then deals that many Fear cards at cleanup. The difference
   shows only when you overcome a guardian at a site your archaeologist is not
   standing on — which the file also cannot forbid, for the same reason. See
   *What the engine has no word for*, below.
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
it is one.** `destroy_self` then `draw_from` works because there is exactly one
free cell at that instant. Two markers destroyed and then refilled would land
in whichever order the grid hands out free slots, which is not a thing the
format promises.

---

## What the engine has no word for

Neither of these was worked around with a new field — both are recorded here
and nowhere else.

**1. Dealing into a named cell.** `draw_from:<deck>:<zone>:<n>` puts arrivals in
the first free slot, and there is no spelling for "deal it into c1". That is why
the card row is two zones sized by arithmetic rather than one zone with a staff
moving across it: with a single `row` grid there is no way to say that artifacts
fill from the left and items from the right. `setup.place` already has `at`, and
`place:<who>:<where>` already names a square, so the word exists twice — just
not on the verb that deals.

**2. Who spent a card's exhaust.** The engine records that a card is exhausted
and not by whom. Arnak's Fear rule is *your* archaeologist coming home from a
guarded site, and the site space is the thing that carries the occupancy — so
the two halves cannot be joined, and divergence 5 above is the price. A stat the
engine writes on exhaustion, the way `last_acted` is written on play, would
close it: `owner_of.<the card that exhausted it>`. This is the same shape
[21](../21-lost-ruins-of-arnak.md) flagged as *`predicate` cannot read a card's
own exhaustion state back as a condition*, one step further on — it turns out
the missing thing is not the boolean but the seat.

---

## Where things are

| | |
|---|---|
| the turn, and how a round ends | `phases`: `turn`'s three `next` routes |
| the moon staff | `market_first` and `market_staff` in `rules_market`, and the two `for_sale_*` tags |
| what every kind of card does | the `tags` section — `deck_card`, `basic`, `item`, `artifact`, `site`, `assistant` |
| what a card is worth | its `card_stats`, and the badge list of the style it wears |
| discovery | `pos_1` and `pos_2`, the only two cards with abilities of their own |
| the research track | `res_1`..`res_6`, and `first_temple` in `rules_temple` |
| scoring | the `scoring` phase, and `win_south`/`win_north` in `rules_win` |
| the buttons | `end_turn` and `pass_turn`, in the `controls` zone |
| what is asserted about all of it | `tests/integration/arnak.lua` |
