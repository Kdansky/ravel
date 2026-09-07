# 07 — Presentation and the gestures on top of it

**Gaps 1–6 and 8 shipped. Gap 7 is half shipped, and three more arrived from
Puzzle Strike.** Every item is something a player sees or does, not something the
engine computes.

## Shipped — where a game puts its buttons

**A column, and it is a game file.** `games/system.json` is merged into every
game as it is read: *Save*, *Menu* and the event log in a strip down the right.
The whole of it is in `AUTHORING.md`'s *The system column*.

Three decisions are worth keeping:

**Outside the board, not inside it.** The draft here weighed a named region
against a menu layer and picked the region, because a layer "charges for it
everywhere: `pos` fractions are of the *window*, so every existing game file's
coordinates shift". That was the right worry and the wrong conclusion — the
answer is to stop the fractions being of the window. A `pos` is a fraction of
the **board**, the board is 0 to 1, and the column lives from x 1.0. Seventeen
files, not one zone moved.

**A module, not chrome.** The draft's own argument against a menu layer —
"the moment the engine draws chrome that is not made of entities, the inspector
cannot inspect it, the network does not carry it, and undo does not know about
it" — is exactly why the column is a game file. It cost nothing to honour: the
`include` machinery from [09](09-composition.md) already merged raw JSON before
parse, so the strip arrives as ordinary zones and cards.

**Its cards are not moves.** `flow.use_system_card` runs before the phase is
consulted, because a player shut out of their own menu by an automatic phase has
nowhere to go. Nothing there is gated, costed, undone or sent.

What it cost to find: routing *every* game through the merge (rather than only
files with an `include`) meant `fold` saw single files for the first time, and
it silently swallowed two things the parser diagnoses better — a key written
twice in one file read as an override, and a section written as an object
instead of a list merged into an empty list. Both now pass through untouched. A
merge that is on for everybody is held to a standard one that is opt-in is not.

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

## Shipped — where the numbers are read, and whether zeros are read at all

*From `todo.md`: "The stats on the top right are overlaid over one player's gem
pile. That isn't very nice. It would be better if we could assign the stats
window to any zone and it would be displayed there..."*

Not built as asked: the HUD is gone rather than relocated. A right-aligned
stat list had no free corner in any dense layout, and the numbers it read were
already a duplicate of what a hovered card already says. What shipped instead:

- **A seat must be somewhere on screen.** `validate.lua` warns when a seat's
  resolved zone (a `setup.place` entry, or a tag's own zone) is missing or
  `display: "offscreen"` — the engine's own default for an unhomed seat. All
  seventeen shipped games now give theirs a small visible zone via
  `setup.place`; five that were generated needed the fix in their generator,
  not the JSON. A `to_zone` field on the card def was the first shape this
  took and was pulled back out: a placement is an instance of a card, not a
  property of its def, and `setup.place` already says that for everything
  else. **One trap cost real time**, twice over: a `copies: "per_seat"`
  zone's contents are shared markers cloned into *every* seat's copy — right
  for `hand`, silently wrong for a seat's own card, which duplicated itself
  into every copy and corrupted every bare-subject stat total reading it. Two
  zone keys per seat, not one per-seat zone, is the fix everywhere it landed.
- **Hovering a seat shows its own numbers**, for free: `tooltip.lua`'s
  `blocks()` already lists every stat on whatever card is hovered, filtered
  through the same `BOOKKEEPING` set that keeps `round`/`plays`/`turn` off a
  card's own tooltip. A seat is still a card, so nothing had to be taught
  about it.
- **The corner log and undo button moved to bottom-right**, freeing
  bottom-left (or top-left) for a seat's own box — `validate.lua`'s reserved-
  corner check moved with them. A hovered seat's tooltip now also lists the
  last few log lines, a stand-in for a permanent home in a system zone
  (load/save/invite/options) not built yet.
- **Zeros were not addressed.** The hover tooltip still prints a stat sitting
  at zero — lower priority now that it is on-demand rather than always
  painted on screen. `badge_zeros: false` (cards, per style) is the
  neighbouring word if this is ever wanted, but has no customer yet.

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

## Still open — a zone that is about a seat without being one of its copies

A seat's zones now wear a colour (`render.seat_hue`, keyed on `zone_e.seat`),
and `zone_e.seat` is set by `copies: "per_seat"` and by nothing else. Every zone
a game declares twice by hand is therefore neutral among the tinted ones, and
two shipped games do that where it shows: The Crew's four `seat_box_*` boxes sit
in blue beside the hands they name, and LoR's `nexus_north`/`nexus_south` do the
same. Both are single-cell zones whose whole job is to say whose they are.

Wanted: **a way for a zone to name the seat it belongs to when it is not a
copy.** That is a new field on a zone, so the word has to be agreed before
anything is written.

`per_seat` is not the answer for these, and the reason is worth writing down:
its four rects would be fine, but a per-seat zone receives a *copy* of every
card `setup.place` puts in it, and each of these boxes holds one named seat card
— `{"card": "north", "zone": "seat_box_north"}`. There is no word for "this
seat's own card" in `setup.place`, so a `per_seat` seat box would put all four
seats in all four boxes. [Assumption: whichever way it is closed, the same field
would answer LoR's two nexuses, which are one cell each and belong to a side.]

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
