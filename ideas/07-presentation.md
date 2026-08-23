# 07 — Presentation and the gestures on top of it

**Status:** **reopened.** Gaps 1–6 shipped: chess and Lost Cities announce a
winner, and the same card reads as a victory on one machine and a defeat on the
other. Gaps 7 and 8 came back off `todo.md` after seven games had been laid out
by hand — both are complaints about *where a thing sits on the screen*, which is
what this track is, and neither existed as a question until there were enough
games to see the same answer typed seven times.

The rules are in better shape than the surface they are shown through. Every
item here is something a player sees or does, not something the engine computes.

---

## Gap 1 — A pass on text, contrast and layout — **shipped**

*Both halves: the card face, and the tooltip.*

**What changed, and why each.**

- **The text band is gone.** A card was split into a picture and a slab of
  colour holding its name; the picture now fills the card and the name sits over
  it on a dark gradient. That is where the height went, and why a hand card
  showed a stamp above two clipped lines.
- **Contrast is settled by construction, not by palette.** The band drew fixed
  light text over whatever colour the *game* chose — white on a green expedition
  was unreadable and no palette could have fixed it. Light text with a dark
  outline on a darkened strip reads on anything.
- **A title is fitted, not cut.** Largest size that fits on one line; failing
  that two lines, but only where there is a space to break at; then smaller
  still; and only then an ellipsis. "Score Green" used to render as `S...` in
  Lost Cities and now reads.
- **Prose needs room to be prose.** Below about 92px a card carries a name or a
  paragraph, not both — and the name is what a player is choosing between. The
  description is a hover away, which is where the long version always lived.
- **Whole lines only.** The old band clipped mid-glyph at the card's edge.

**The tooltip is a list of blocks, measured then drawn.** It used to concatenate
up to six sections into one string and hand the lot to a single `printf` in one
colour at one size — the card's prose, its price and the hint about clicking it
were indistinguishable, and it never said the card's *name*. Now each piece
knows what it is:

| Block | Weight |
|---|---|
| title | main font, brightest |
| prose | small, dimmer — the card's own words, then what its zone says about lying there |
| rule | a hairline, between groups |
| row | label left and dim, value right and bright, so a column reads down |
| hint | accent colour: green to click, amber for exhausted or out of phase |

Two passes rather than one, so the panel is the size of what is in it — guessing
the height is what left the old one padded on a short card and tight on a long
one. And the engine's own counters (`round`, `plays`, `turn`) are filtered out:
they are bookkeeping it keeps on whichever card happens to be the seat, and on
castle's throne room they read as two of its statistics.

**And the text was blurry, for two reasons that only show on a screen.** Every
position was fractional — a zone's rect is a fraction of the window, so a card
lands on `x = 371.4` and its glyphs are sampled between two texels. And
`main.lua` sets a linear default filter, which is right for card art and wrong
for a glyph atlas: that is rasterised at exactly the size it will be drawn, so
sampling it smoothly can only soften edges that were sharp.

Rounding is wrapped once in `render` rather than applied at forty call sites,
where the forty-first would forget; the tooltip and the inspector round at
source, since they measure everything from a pad and an origin.

**It is invisible at 960×540**, where the scale is exactly 1 and most positions
land on whole numbers anyway. Check any other size — 1100×620 gives 1.146 — or
the fix looks like it did nothing.

**Two traps worth recording.** `getWrap` splits a word it cannot fit, so
"Yellow 9" comes back as "Yello" / "w 9" — which passes a width check and reads
as nonsense; rejoining the lines and comparing to the original is what tells a
real break from a broken word. And a card's hp badge sits in the bottom-left
corner, which is now where the title is: the title starts to its right instead.

**It was done by looking.** A scratch LÖVE harness rendered each game to a PNG
between edits — `love.graphics.captureScreenshot` is asynchronous and writes
nothing if you quit, so a canvas with `stencil = true` and a synchronous
`newImageData():encode` is the thing that works. Every problem above was visible
in the first screenshot and none of them was visible in the test suite.

## Gap 2 — Drawing from the deck should be a gesture, not a token — **shipped**

*And by a better route than the one designed below.*

The plan here was to grant the deck's top card a `takeable` ability, which meant
letting `card_at` return it — and therefore letting it be *hovered*, and
therefore needing a visibility rule so that pointing at a face-down deck did not
read out the card you were about to draw. That is the "real work" this section
identifies, and it was real.

**The deck answers instead.** A zone carries its own `activate` block now, in a
card's words:

```json
{ "key": "deck", "type": "deck", "tooltip": "Take the top card. Ends your turn.",
  "activate": { "phases": ["draw"], "action": ["draw_from:deck:hand:1", "next_phase"] } }
```

A deck is a box, not a stack of clickable cards, so there is nothing to hide and
no predicate to write. Lost Cities loses the `draw_deck` token and its draw step
becomes one sentence: *click the deck, or take the top of a discard.*

What it replaced is `on_click`, which fired in any phase, answered to nothing but
the overlay lock, and carried a DESIGN warning that it was not a move and must
not be used as one. No shipped game used it. A zone's ability is gated exactly
as a card's is — the phase, the cost, and whose zone it is — so it *is* a move,
and the warning goes with the field.

The hover half shipped with it: a zone with a tooltip or an ability now
describes itself, which a deck previously could not do at all.

**Note the distinction it creates**, because the two words look alike:
`applies` grants an ability to the cards *lying in* a zone (that is how a
discard becomes takeable); `activate` is the zone's *own*. A discard pile has
both, and they are different sentences.

## Gap 3 — Choosing between several abilities — **shipped** (`d27d18a`)

*And by the route this section predicted: an ability is a thing with a name, and
the chooser is the offer overlay that already existed. `abilities` is a list
where `activate` was one thing, normalised at the door so a card with one is the
list with one entry — see [DONE.md](DONE.md), "A card that can do several
things". The refusal below held right up to the card that needed it: Coronation's
Small Council is five advisors on one card.*

## Gap 4 — A thing that should not be drawn — **shipped**

*Shipped as the zone tag `invisible_slot_outlines`. The reasoning below is what
picked that name over a general `invisible`, and the eligibility rule at the end
is the part that keeps the board playable. [11](11-styles-as-tags.md) later
renames it `no_square_lines` and moves it into `styles` — being a tag already, it
needs nothing else.*

`draw_grid_empty` (`render.lua:645`) outlines every unoccupied slot. On a board
with no art that outline **is** the board, and it is the right default. On a
chessboard it is a rounded rectangle drawn inside 32 painted squares, and it
reads as a mistake.

The narrow fix is four characters of condition. The question is what the tag
should be called, and how far it reaches — the request was *"possibly an
`invisible` tag on any component we have"*, and that is worth resisting in its
general form:

| Reading | What it would mean | Verdict |
|---|---|---|
| `invisible` on a **zone**'s empty slots | skip the outline | this is the actual request |
| `invisible` on a **zone** | draw no background, no label, no outline — but still lay out and hit-test | useful; `hidden` already exists and means something stronger (not drawn *and* not clickable, for offer zones and fate decks) |
| `invisible` on a **card** | ? A card that is not drawn but occupies a square is a rules ghost | **refuse** — there is no honest meaning, and `card_at` would hand the player something they cannot see |

So: **one tag word, applied only to zones**, and it must be a different word from
`hidden` because the difference between "invisible but live" and "gone" is
exactly the bug this would otherwise introduce. *Shipped as
`invisible_slot_outlines`* — named after the one shape it suppresses rather than
after a general idea of chrome, which is what makes it safe to add the next one
beside it.

**The engine already has the precedent and it is a card tag**:
`transparent_background` means "no plate behind the art", and
`invisible_title_text` means "no title band". Both are per-card, both suppress
one piece of chrome, and both are named after the piece rather than after
invisibility. Follow that: a zone tag per piece of chrome beats one `invisible`
that means four things — and it stops the eventual argument about whether an
invisible zone can still be clicked.

**Eligibility is not chrome and is drawn either way.** During targeting the
highlight on a reachable square is the only thing telling a player where a piece
may go, so a board that suppressed it would be a board nobody can move on. The
tag hides the resting outline and nothing else — which is also what makes the
test exact: flipping it removes precisely one rectangle per empty square, 32 on
an opening board.

---

## Gap 5 — A board that stays square when the window does not — **shipped**

*Shipped as a `ratio` field on the zone: a number (width over height) or
`"grid"`. Chess uses `"grid"`. What follows is the design as written; two things
went differently and are marked below.*

**Field, not tag** — the question came up and the answer generalises. A tag is a
word, which suits a quality a zone either has or hasn't (`invisible_slot_outlines`
is rightly one). A ratio is a number, and there are infinitely many. As a tag it
would be either a closed set of words that is always missing somebody's aspect,
or a number parsed out of a tag string, which is a field in a tag's clothes. One
field also keeps one question in one place: `"grid"` is a second *value*, not a
second tag, and any later source of a shape — the zone's own picture, say — is
another word in the same field rather than a rival tag that must never appear
beside the first.

**`"ratio": "asset"` is deliberately not built.** It is one more branch in
`keep_ratio`, but a remote picture arrives after the layout has run, so it needs
a re-layout when the image lands — which is a per-frame check for something no
game asks for yet. Build it with the first zone that wants it.

> **Superseded by [11](11-styles-as-tags.md).** The field is right about the
> shape and wrong about the place: a specialised rendering field on the zone is
> what `assets` already refused to be. `ratio` becomes a property of a named
> style, and the zone says a word. It stays until that pass, because removing it
> now leaves the chessboard a rhombus for no gain, and one user in one generated
> file is the cheapest migration there is.

`zones.resize` (`zones.lua:342`) multiplies a zone's fractional `pos` by the
window size, straight through. A chessboard given `[0.25, 0.05, 0.75, 0.95]` is
therefore square only at one window aspect and a rhombus everywhere else, and
`cell_rect` divides that rect by `[cols, rows]`, so every square is stretched the
same way. Cards inside cells survive it — `fit: "card"` keeps their proportions
— which is exactly why the *board* looking wrong is easy to miss in a screenshot
of the cards.

**The rule to add:** a zone may declare the shape it must keep, and the layout
gives it the largest rect of that shape inside the space it was allotted.

```json
{ "key": "board", "type": "grid", "grid": [8, 8], "pos": [...], "ratio": 1 }
```

Three decisions to make, none of them large:

1. **What `ratio` means.** `w / h`, a number. `1` is square. Deriving it from
   `grid` automatically is tempting and wrong: a `[8, 8]` grid of *cards* wants
   cells shaped like cards, not squares, and the fit is already a separate
   choice (`fit`). Say it explicitly, and let `"ratio": "grid"` mean "take it
   from the cell count" for the boards that do want that.
2. **Where the slack goes.** Centre it, and say so once. Anything else needs an
   alignment field, which is a second concept for a case nobody has.
3. **What else moves.** Nothing. The whole point is that the *other* zones keep
   their fractions; a board that shrinks leaves a gap, it does not push the
   hands around. A layout where that gap matters is a layout that wanted a
   different `pos`.

**Where it goes:** inside `zones.resize`, after the rect is computed and before
the slots are — six lines, and every consumer downstream reads `z.place` and is
unaffected. `validate.lua` gets a range check, and the overlap warning keeps
working because a ratio-corrected rect is strictly smaller than the one it was
checked against.

**Test it in `render_smoke`** — *changed*: `zones.resize` is arithmetic and draws
nothing, so it went to `tests/integration/layout.lua`, where it runs headless on
both interpreters. Chess is measured at 1600×900 and 600×1000, and the board is
square in both.

**One bug worth remembering, and it was in the test rather than the feature:**
`("%dx%d"):format(w, h)` passes under LuaJIT and *raises* under Lua 5.4, which
refuses `%d` for a float with no integer representation. The suite is run under
both for exactly this reason. It bit in a failure-detail string, which is
evaluated eagerly even on the passing path — so a detail message can break a
test that would otherwise pass.

---

## Gap 6 — An ending that knows who won — **shipped**

**A win is a number on the seat that won.** `won` is stamped on every seat card
at load and set by an ordinary action — `gain_stat:won@white_side:1` — and
`flow.outcome()` reads it against `zones.watching()`, so one state ends as a
victory on one machine and a defeat on the other. The `"victory"` / `"defeat"`
word on a card stays exactly as it was for the six solo games. Chess ends with a
screen instead of the menu; Lost Cities' two ending phases gained one action each.

**It was a field on the ending card first, and a stat is better.** The first
version put `"outcome": { "winner": "<seat key>" }` on the revealed card. It
worked, and it was def data — invisible to the rules, absent from the snapshot,
untouched by undo. A stat is *state*: the network carries it because it carries
every stat, undo takes it back because it takes back everything, and a condition
can read `won@mine`, which a field could never offer. Nothing had to be passed
anywhere, which was the point.

**What stayed a card is the screen.** The alternative sketch — jump to a phase
the engine hardcodes and let it draw the ending — costs the games their own
words: chess's *"The black king is taken"* and Lost Cities' *"South should have
hedged"* live on the revealed card, and the six solo endings are cards already.
The flag decides *what the banner says*; the game still decides what the screen
holds.

Four things the build settled, and only the third was foreseen:

- **A winner cannot be a subject.** The design below assumed
  `"winner": "<subject>"` so a game could say *who* rather than hardcode a chair.
  A subject evaluates to a **number** — `max:score@anyone` is the score, never
  the seat holding it — so no subject can name anybody. Both two-seat games
  already route to a per-winner phase (`north_end` / `south_end`), so the seat
  is known where the ending is decided, and one action writes it down.
- **"decided" is the third answer, and it is what the hot-seat refusal looks
  like in code.** Victory and defeat need somebody to be about. With no seat
  claimed there is no "you" in the room, so the banner reads *Black wins* — the
  winner announced to the room rather than one of the two people in it being
  told they lost. That is also the spectator's screen, for free.
- **`zones.watching()` is exported and answers nil**, where
  [16](16-the-player-at-this-screen.md) gap 1 left it a local that fell back to
  the turn. Hiding a hand must name somebody and hot-seat means the seat to play;
  an ending has nobody to congratulate and says so. The fallback moved to the two
  visibility call sites, where it belongs.
- **Chess's ending could not be an `end_condition`, and that is a finding about
  conditions rather than about chess.** A condition can only say `mine` /
  `enemy`, which are relative to the *active seat* — and at the end of a game
  that is an accident of who moved last. **There is no way to name a seat
  absolutely in a condition.** The four phases already know their colour
  (`white_move` is white's), so the routing that picks "black is in check" picks
  "white won" from the same place, and `end_conditions` is empty. Worth carrying
  to [17](17-conditions-as-expressions.md): an owner word that accepts a seat key
  would have made this one line.

**The numbers under the banner were wrong for the same reason the banner was**,
and the flag does not fix them. `flow.summary()` and the stat HUD both go through
`predicate.total`, where `mine` is resolved from `zones.active_seat()` several
layers down — so a row labelled *Your score* read the score of whoever was to
move. Measured in Lost Cities with north on 111 and south on 222: viewer north,
turn south, readout **222**. The fix is `zones.as_seat(seat, fn)`, a scoped
override of `active_seat()` that the two display paths wrap their reads in.
Every consumer of "mine" — subjects, zone lookups, ownership — asks that one
function, so one override answers for all of them instead of a seat parameter
being threaded through six. **Reads only**, and restored even when the body
raises: an engine that quietly stays somebody else is worse than a crash.

**No second line under the banner**, and the request asked for one — *display in
smaller text below who won*. The ending card is drawn in the overlay two inches
under the banner, titled "White wins", with the story beneath it. A copy of that
sentence between them would be the same screen saying the same thing twice.

**One thing fixed in passing, because regenerating was part of the job:**
`tools/make_lost_cities.py` still emitted `stays_ready`, deleted from the engine
in `8856432`, and wrote a trailing newline the checked-in file did not have — so
the generator had not reproduced its own output for two commits. It does now.

### Refuse

- **A second ending mechanism.** An ending is an overlay holding a card, and
  that is `12`'s and the offer's shape both. Whatever names the winner goes *on
  that card*, not into a new engine concept with its own state to snapshot.
- **Per-seat screens in hot-seat.** One screen, one person: the handover
  ceremony was already refused ([DONE.md](DONE.md), stage A), so a hot-seat
  ending announces the winner by name to the room rather than pretending the
  loser is not looking.

---

## Gap 7 — Where a game puts its buttons — *half shipped*

*From `todo.md`: "The save button in chess is not great, it should just be in the
same area as the how to play button. We need a more elegant way to have menus,
possibly most games should just reserve a right-hand column for menu-stuff."*

Two things, and only the second is this gap.

**The immediate one is a typo-sized content fix.** `chess.json` puts its
`controls` hand at `[0.03, 0.44, 0.24, 0.56]` — the left edge — and its `rules`
pile at `[0.76, 0.45, 0.97, 0.55]`, the right. So the two buttons a player is
never in doubt about, *Save* and *How to play*, sit at opposite ends of the
board with the game between them. Moving `controls` into the right column beside
`rules` is one line in one game file and needs nothing from the engine.
**Done** — both are now a narrow strip at `x` 0.82–0.92, stacked, and the
validator caught the first attempt overlapping the captured-pieces pile, which
is a rule (`validate.lua:1517`) worth knowing exists: the lower-left corner
belongs to the undo button and the event log, and a zone reaching into it is
refused rather than drawn over.

**The rest of the gap is untouched**, and is what the table below is about.

**The real one: seven games have each invented their own chrome.** The button
strip is a zone, which is right — a button is a card and a card lies somewhere —
but *where* it lies is retyped per game, in fractions, against no shared
vocabulary:

| game | the chrome it invented |
|---|---|
| `chess.json` | `controls` hand left, `rules` pile right, both hand-placed |
| `lor.json` | `controls` grid `[0.82, 0.32, 0.98, 0.68]`, per seat, between the decks |
| `splendor.json` | buttons in the play area with the cards they act on |
| `menu.json` | one hand zone that *is* the whole screen |

Nothing is wrong with any of them individually. What is wrong is that a game
author has to answer "where do the buttons go" before they can put a button
anywhere, and the answer is arithmetic rather than a word.

### What it would need

[Assumption: the shape below is inferred from how `pos` and per-seat zones
already work — the todo note says only "reserve a right-hand column", not how.]

The cheap version is a **named region**: a zone's `pos` takes a word instead of
four fractions, out of a closed set (`"sidebar"`, and whatever the second
customer asks for), and `zones.resize` (`zones.lua:342`) resolves it to a rect
the same way `ratio` already post-processes one. That is one branch in one
function, and it makes "the buttons go in the usual place" a thing a game can
say.

The expensive version is a **menu layer** — chrome that is not a zone at all,
drawn outside the board rect, with the board given the remaining space. That
buys a right-hand column every game gets for free, and charges for it
everywhere: `pos` fractions are of the *window* today, so every existing game
file's coordinates shift the moment something reserves part of it.

**The cheap version first, and possibly only.** A word for a rect keeps the
model — a button is a card in a zone — and the moment the engine draws chrome
that is not made of entities, the inspector cannot inspect it, the network does
not carry it and undo does not know about it.

### What this is not

- **Not a settings screen.** `save_game:<slot>` is a card with an action, as
  [24](24-save-and-load.md) built it, and that is the right shape. The complaint
  is where the card sits, not what it is.
- **Not a per-seat question.** LoR's controls are per seat because each seat
  passes and attacks; chess's *Save* is neither seat's. A named region has to
  keep working for both, which the per-seat `pos` list already does.

---

## Gap 8 — A card's numbers in a column, and what colours them — **shipped**, twice

> **Three words, and a fourth thing that was the real find.** `badge_run:
> "down"` runs a card's badges down the left edge instead of along the bottom;
> `badge_zeros: false` leaves out a badge whose number is zero; and a stat
> declares `color` beside its `icon`, in the palette vocabulary `art.colour`
> already reads. Splendor's ninety market cards print their price as a column of
> gems and their title is now what the card *gives* you.
>
> The find is underneath all three: **`badges` named on a zone's style is read
> by nobody.** `cards.style` asks the card, and a style is claimed by carrying a
> tag of its name — so `splendor.json` had `badges` on three zone styles
> (`market`, `counter`, and `market` again through the nobles) and drew none of
> them. Not one of the three was an error: the property is legal, the style
> exists, and there is nothing to find by reading the file. The token piles have
> shown their remaining count for the first time as a result — which decides
> whether two of a colour may be taken, and had never been on screen.
> `validate.lua` now refuses a style that names badges no card wears, and the
> case is in `tests/integration/validator.lua` as *the one that cost a year*.
>
> The two questions the write-up said were the work were answered as it guessed
> for one and against for the other. Zeros: **per style, not per stat** —
> `badge_zeros` is a style property, because the alternative it pointed at
> ([06](06-schema-and-types.md) gap 6) turned out to have nothing in it. Colour:
> **on the stat, not on the style** — the HUD row and the badge draw the same
> icon and would otherwise disagree, and Splendor's onyx was an orange sword in
> both places.
>
> **The one thing left is shipped too.** `"icon": "none"` is the seventh word in
> the closed set — a shape name rather than `icon: false`, so the field stays one
> type — and it draws nothing, closing the gap where the shape would have been.
> On the stat and not the style, by this gap's own colour argument. Splendor's
> `bank` claims it, and the six token plates read `4 Diamond` instead of
> `◆ 4 Dia…`.
>
> **And the second find is the better one: the title was clearing a fraction of
> the card where there is a number to be had.** `draw_card_face` reserved
> `vis.w * 0.62` for a row of badges and `0.42` for one — half a token plate for
> a two-character count. `badge_size` now returns what `draw_badge` will actually
> draw, the one formula with two callers, and the title starts clear of *that*.
> It is what made "Diamond" fit where "Dia…" did not, and it is why every card in
> the corpus recentred slightly.
>
> **"A column takes none of the title's line" was true only of tall cards.** A
> noble is four requirements on a plate two thirds the height of a market card,
> so the fourth badge lands in the corner the title starts from and printed a
> `3` over the word — the same collision the hp badge caused in gap 1, one axis
> round. The title now gives way to a column that reaches it, which is knowable
> only after the title has a height, so it is fitted twice: a second fit can only
> make it smaller, and smaller only makes the collision truer, so it cannot come
> back. Beside it `badge_keys`, because the badges a card *shows* are the ones it
> must clear — a title giving way to a badge that `badge_zeros` left out would be
> off-centre for nothing.
>
> **And a noble is no longer titled.** Every one of them is called "Noble": the
> word says nothing the plate has not said and it was costing four requirements
> their room. `title: false` on the style, which [11](11-styles-as-tags.md)
> already had for exactly this.

### What falls out for free

`vp` on a Splendor card has no `icon` and draws the diamond, while `score` — the
same number, on the seat — declares `banner`. That is the third `todo.md` note
("Prestige is important enough that it needs an icon, right?") and it is one line
in `tools/make_splendor.py`, not part of this gap. It stays on `todo.md`.

### Refuse

- **A per-card layout.** The direction belongs to the style, which is how
  [11](11-styles-as-tags.md) settled every other look: ninety cards claim one
  word, they do not each carry a rect.
- **The engine knowing that `cost_white` is a cost.** It is a stat with an icon
  and a place on the face. Whether the *format* should have a word for "this
  number is a price" is [06](06-schema-and-types.md) gap 6, and it must not be
  answered by the renderer noticing a prefix.

---

## What the same pass found on the way past

Two things fixed because the work above could not be seen without them.

**A named zone was named only while it was empty.** `draw_zone_label` prints
along the top edge and `card_places` laid the first card over it, so a hand with
anything in it lost its name — which is the half of the time a name is worth
having. `card_places` now reserves the label's height at the top of a non-grid
zone (`render.lua`, the hand branch) and centres the cards in what is left.
Splendor's *Bought* and *Reserved*, The Crew's *Said*, and the menu's two lists
all gained a label they had always declared. **A grid now keeps its own clear
too** — the half left over, shipped in the same pass as `icon: "none"` below.

`zones.label_h` is the band, written from outside exactly as
[16](16-the-player-at-this-screen.md) writes `zones.viewer`: `zones.lua` has no
font and must not require the module that has, so the renderer measures it once
in `rescale` and `cell_rect` subtracts it whenever `z.label` is set. Headless
leaves it zero, so `tests/integration/layout.lua` is untouched and chess renders
byte-identically. It had to go in `cell_rect` because `zones.resize` gives every
slot its rect from there and that is what hit-testing reads — reserving the band
anywhere else would move the picture and not the target. `keep_ratio` subtracts
it too, and that was not in the plan: a named square board is a square with a
line of text above it, not a square with a bite out of its top.

**`love.resize` had to swap its two lines.** It called `zones.resize()` and then
`render.rescale()`, and the band is measured in the second — so the first frame
after every window change laid the cells out against last size's band. Fonts
first, layout second.

**The band comes out of the cards, and in a wide one-row grid it comes out
sideways.** A plate there is height-bound — the cell is wider than the card, so
the card's width is its height over the card ratio — and taking twenty pixels
off the top took fifteen off the width of every token pile in Splendor. That is
the honest cost of the fix, and the game file pays it: `supply` grew from
`0.47` to `0.52` and got a row of gems that spell their names out. **A zone that
declares a label wants more room than one that does not**, which is now in
`AUTHORING.md` beside the field.

**The wheel scrolled by the browser's pixel delta.** `love.wheelmoved` passed
`-dy * 3` into the inspector, and only the *sign* of `dy` is portable — natively
a notch is a small integer, under love.js it is a pixel count, so one click
scrolled a Splendor dump about eighty rows and the middle of it could not be
reached at all. Six lines a click, in the direction of the wheel.
