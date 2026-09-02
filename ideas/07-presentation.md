# 07 — Presentation and the gestures on top of it

**Gaps 1–6 and 8 shipped. Gap 7 is half shipped, and three more arrived from
Puzzle Strike.** Every item is something a player sees or does, not something the
engine computes.

## Still open — where a game puts its buttons

*From `todo.md`: "The save button in chess is not great, it should just be in the
same area as the how to play button. We need a more elegant way to have menus,
possibly most games should just reserve a right-hand column for menu-stuff."*

The immediate half was a content fix and is **done**: chess's *Save* and *How to
play* sat at opposite ends of the board and are now a narrow stacked strip at
`x` 0.82–0.92. The validator caught the first attempt overlapping the
captured-pieces pile, which is a rule worth knowing exists — the lower-left
corner belongs to the undo button and the event log, and a zone reaching into it
is refused rather than drawn over.

**The rest is untouched. Seven games have each invented their own chrome:**

| game | the chrome it invented |
|---|---|
| `chess.json` | `controls` hand left, `rules` pile right, both hand-placed |
| `lor.json` | `controls` grid `[0.82, 0.32, 0.98, 0.68]`, per seat, between the decks |
| `splendor.json` | buttons in the play area with the cards they act on |
| `menu.json` | one hand zone that *is* the whole screen |

Nothing is wrong with any of them individually. What is wrong is that an author
must answer "where do the buttons go" before putting a button anywhere, and the
answer is arithmetic rather than a word.

**The cheap version is a named region**: a zone's `pos` takes a word instead of
four fractions, out of a closed set (`"sidebar"`, and whatever the second
customer asks for), resolved in `zones.resize` the way `ratio` already
post-processes a rect. One branch in one function.

**The expensive version is a menu layer** — chrome that is not a zone at all,
drawn outside the board rect. That buys a right-hand column every game gets free
and charges for it everywhere: `pos` fractions are of the *window*, so every
existing game file's coordinates shift the moment something reserves part of it.

**The cheap version first, and possibly only.** A word for a rect keeps the model
— a button is a card in a zone — and the moment the engine draws chrome that is
not made of entities, the inspector cannot inspect it, the network does not carry
it, and undo does not know about it.

*Not a settings screen*: `save_game:<slot>` is a card with an action and that is
the right shape; the complaint is where the card sits. *Not a per-seat question*:
LoR's controls are per seat because each seat passes and attacks, chess's *Save*
is neither seat's, and a named region must keep working for both.

## Shipped — a card that fills the zone it is in

`fit: "fill"` existed and was read on the grid branch of `card_places` and
nowhere else, so every button in the corpus was a portrait card floating in a
wide rect. It is read everywhere now, and `AUTHORING.md` and `SCHEMA.json` say
so where the field is listed. **A filled row has no card ratio to lay out
against**, so the column search needed a different question: every count tiles
the same area, and the cells closest to square is what settles it.

**It does not fix Puzzle Strike's buttons, and the measurement is the finding.**
Its five controls are ~28px wide because the zone is 179×46px — the only gap the
right column has, bracketed by the two gem piles above and below and the stashes
to the left, every one of which the validator measures against. Filling gains
about a quarter of the width and the whole of the height, and "End turn" still
does not fit. **Five readable buttons need somewhere else to stand**, which is
gap 7 above and not this.

## Still open — where the numbers are read, and whether zeros are read at all

*From `todo.md`: "The stats on the top right are overlaid over one player's gem
pile. That isn't very nice. It would be better if we could assign the stats
window to any zone and it would be displayed there. In this case this would work
perfectly for "played this turn" if right-aligned. Also it should not show 0
values (this should be a toggleable feature of whether we want to show 0
values)."*

`draw_stats` is hard-anchored: `x = W - 10 * S`, `y = 10 * S`, rows down the
right edge (`render.lua:1285`). Nothing in a game file can move it, so any game
whose layout uses its top-right corner has the readout printed over the top of
that corner — which is the same complaint gap 7 makes about buttons, one level
up: **the chrome has no vocabulary and the games have the whole window.**

Two halves, and they are independent:

- **A place.** [Assumption: the spelling is a zone naming itself as the
  readout's home rather than the readout naming a zone — a zone already knows its
  rect, its seat and whether it is drawn, and a top-level `stats_at: "<zone>"`
  would be a second place to keep a zone key in step.] Either way it wants
  consent on the word before it exists. The drawing is the easy half:
  `draw_stats` already computes every row's width for `stat_hud`, so right-
  aligning inside a rect instead of inside the window is a changed `x` and a
  changed `y`, not a changed function. **Careful with `stat_pos`** — floating
  deltas read `stat_hud` for where a number lives, and its fallback is the
  top-right corner in pixels.
- **Zeros.** `badge_zeros: false` already exists and is *per style*, deciding
  whether a card's badge draws a zero. The HUD is the same question at the other
  end of the screen and has no answer at all. [Assumption: it wants the same
  spelling and the same default — visible unless the game says otherwise — and
  belongs beside whatever names the place, not on each stat def, since "do not
  show me empty rows" is one preference about a readout and not forty
  statements about forty numbers.] The `hidden` tag on a stat def is the
  neighbouring word and is a different one: `hidden` means never, this means not
  while it is nothing.

## Still open — an offer of fifty-one

*From `todo.md`: "The bank draft screen shows all fifty-one plates in one offer,
which is a lot of cards at once. It works, but it wants a layout of its own."*

The hand branch's row/column search already keeps every card readable by adding
rows rather than shrinking cards, so fifty-one plates *fit*; what they do not do
is read as a thing you choose from. [Assumption: what is wanted is not a new
layout algorithm but the `page` layout the seven fields already reserve
(`layout: "page"` in [28](28-a-zone-by-its-parts.md)) actually doing something —
a fixed grid with a next/previous, so an offer is a page of twelve rather than a
wall of fifty-one.] Worth confirming against the screenshot harness before
building anything: the draft may only look bad because the two draft buttons in
the same row are 23px squares, which is the gap above and not this one.

## What shipped, and what each cost to find

**Text, contrast and layout.** The text band is gone — a card was a picture plus
a slab of colour holding its name, which is where the height went. Contrast is
settled by construction rather than by palette: the band drew fixed light text
over whatever colour the *game* chose, and no palette could have fixed white on
a green expedition. A title is fitted, not cut. Below about 92px a card carries a
name or a paragraph, not both, and the name is what a player is choosing between.

The tooltip is a list of measured blocks rather than six sections concatenated
into one `printf` — it never said the card's *name* before. Two passes, so the
panel is the size of what is in it. The engine's own counters (`round`, `plays`,
`turn`) are filtered out: they are bookkeeping kept on whichever card happens to
be the seat, and on castle's throne room they read as two of its statistics.

Three traps: **`getWrap` splits a word it cannot fit**, so "Yellow 9" comes back
as "Yello"/"w 9", which passes a width check and reads as nonsense — rejoining
and comparing to the original is what tells a real break from a broken word.
**Text was blurry for two reasons that only show on a screen** — every position
was fractional, and `main.lua`'s linear default filter is right for card art and
wrong for a glyph atlas rasterised at exactly its draw size. It is invisible at
960×540 where the scale is exactly 1, so check any other size. And **it was done
by looking**: a scratch harness rendered each game to a PNG between edits, and
every problem was visible in the first screenshot and none in the test suite.

**Drawing from the deck**, by a better route than designed. The plan was to grant
the deck's top card an ability, which meant letting it be hovered, which needed a
visibility rule so pointing at a face-down deck did not read out the card you
were about to draw. Instead **the deck answers**: a zone carries its own
`activate` block. A deck is a box, not a stack of clickable cards, so there is
nothing to hide and no predicate to write. It replaced `on_click`, which fired in
any phase and carried a DESIGN warning that it was not a move; a zone's ability
is gated exactly as a card's, so it *is* one. Note the distinction it creates:
`applies` grants an ability to the cards *lying in* a zone; `activate` is the
zone's *own*. A discard pile has both, and they are different sentences.

**A thing that should not be drawn.** The request was *"possibly an `invisible`
tag on any component"*, and the general form was resisted: one word per piece of
chrome, applied only to zones, and never to a card — a card that is not drawn but
occupies a square is a rules ghost, and `card_at` would hand the player something
they cannot see. **Eligibility is not chrome and draws either way**: during
targeting the highlight is the only thing telling a player where a piece may go.

**A board that stays square.** `ratio` as a field, not a tag: a tag suits a
quality a zone has or hasn't, and a ratio is a number, of which there are
infinitely many. Deriving it from `grid` automatically is tempting and wrong — an
`[8, 8]` grid of *cards* wants cells shaped like cards — so `"ratio": "grid"` is
a second *value*. Slack is centred, and nothing else moves: a board that shrinks
leaves a gap rather than pushing the hands around.

One bug worth remembering, and it was in the test rather than the feature:
`("%dx%d"):format(w, h)` passes under LuaJIT and *raises* under Lua 5.4, which
refuses `%d` for a float. It bit in a failure-detail string, which is evaluated
eagerly even on the passing path — so a detail message can break a passing test.

**An ending that knows who won.** A win is a stat on the seat that won, read
against `zones.watching()`, so one state ends as a victory on one machine and a
defeat on the other.

It was a *field* on the ending card first, and a stat is better: a field is def
data — invisible to the rules, absent from the snapshot, untouched by undo. A
stat is state, so the network carries it, undo takes it back, and a condition can
read `won@mine`. Nothing had to be passed anywhere, which was the point. What
stayed a card is the *screen*: chess's "The black king is taken" and Lost Cities'
"South should have hedged" live on the revealed card. The flag decides what the
banner says; the game still decides what the screen holds.

Four things the build settled:

- **A winner cannot be a subject.** The design assumed `"winner": "<subject>"` so
  a game could say *who*. A subject evaluates to a **number** — `max:score@anyone`
  is the score, never the seat holding it — so no subject can name anybody.
- **"decided" is the third answer**, and it is the hot-seat refusal in code.
  Victory and defeat need somebody to be about; with no seat claimed the banner
  reads *Black wins*, announced to the room rather than one of two people being
  told they lost. That is the spectator's screen for free.
- **Chess's ending could not be an `end_condition`**, and that is a finding about
  conditions rather than about chess: at the moment a king is taken, "mine" is
  whoever moved last. Carried to [17](17-conditions-as-expressions.md).
- **The numbers under the banner were wrong for the same reason the banner was.**
  `summary()` and the stat HUD both resolve `mine` from `active_seat()` several
  layers down, so a row labelled *Your score* read the score of whoever was to
  move — measured at north 111, south 222, viewer north, readout **222**. Fixed
  with `zones.as_seat(seat, fn)`, a scoped override the two display paths wrap
  their reads in, so one function answers for subjects, zone lookups and
  ownership alike instead of a seat parameter threaded through six. Reads only,
  and restored even when the body raises: an engine that quietly stays somebody
  else is worse than a crash.

**A card's numbers in a column.** `badge_run: "down"`, `badge_zeros: false`, and
`color` on a stat. Zeros are **per style**; colour is **on the stat**, because
the HUD row and the badge draw the same icon and would otherwise disagree —
Splendor's onyx was an orange sword in both places. `"icon": "none"` is the
seventh word in the closed set, a shape name rather than `icon: false`, so the
field stays one type.

The find underneath all three: **`badges` named on a *zone's* style is read by
nobody.** `cards.style` asks the card. Splendor had `badges` on three zone styles
and drew none of them, and not one was an error — the property is legal, the
style exists, and there is nothing to find by reading the file. The token piles
have shown their remaining count for the first time as a result, which decides
whether two of a colour may be taken and had never been on screen. The validator
now refuses a style naming badges no card wears, and the case is in the suite as
*the one that cost a year*.

**And the title was clearing a fraction of the card rather than the badges.**
`draw_card_face` reserved 62% of the width for a row of badges and 42% for one.
`badge_size` returns what `draw_badge` will actually draw now — one formula, two
callers — which is what made "Diamond" fit where "Dia…" did not. "A column takes
none of the title's line" was true only of tall cards: a noble is four
requirements on a short plate, so the fourth badge printed a `3` over the word.
The title gives way to a column that reaches it, fitted twice — a second fit can
only make it smaller, and smaller only makes the collision truer, so it cannot
come back.

## What the same pass found on the way past

**A named zone was named only while it was empty.** The label prints along the
top edge and the first card was laid over it, so a hand with anything in it lost
its name — which is the half of the time a name is worth having. The band is
written from outside, as `zones.viewer` is: `zones.lua` has no font and must not
require the module that has, so the renderer measures it once in `rescale` and
`cell_rect` subtracts it. It had to go in `cell_rect` because that is what
hit-testing reads — reserving the band anywhere else moves the picture and not
the target.

**The band comes out of the cards, and in a wide one-row grid it comes out
sideways.** A plate there is height-bound, so twenty pixels off the top took
fifteen off the width of every token pile in Splendor. The game file pays it, and
**a zone that declares a label wants more room than one that does not** is in
AUTHORING beside the field.

**`love.resize` had to swap its two lines.** It called `zones.resize()` then
`render.rescale()`, and the band is measured in the second — so the first frame
after every window change laid out against last size's band. Fonts first.

**The wheel scrolled by the browser's pixel delta.** Only the *sign* of `dy` is
portable: natively a notch is a small integer, under love.js it is a pixel count,
so one click scrolled a Splendor dump about eighty rows.

## Refused

- **A second ending mechanism.** An ending is an overlay holding a card. Whatever
  names the winner goes *on that card*, not into a new engine concept with its
  own state to snapshot.
- **Per-seat screens in hot-seat.** One screen, one person.
- **No second line under the banner**, though it was asked for. The ending card
  is drawn two inches under the banner with the story beneath it; a copy of that
  sentence between them is the same screen saying the same thing twice.
- **A per-card badge layout.** The direction belongs to the style: ninety cards
  claim one word, they do not each carry a rect.
- **The engine knowing that `cost_white` is a cost.** It is a stat with an icon
  and a place on the face, and it must not be answered by the renderer noticing
  a prefix.
- **`"ratio": "asset"`.** A remote picture arrives after layout has run, so it
  needs a re-layout when the image lands — a per-frame check for something no
  game asks for. Build it with the first zone that wants it.
