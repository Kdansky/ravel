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

### The original write-up

*Urgency: high (this is what players actually hit) · Difficulty: medium-high,
because most of it is judgement rather than code · Usefulness: high*

The complaints, each traceable to a specific decision:

**Titles are nearly always cut off.** `truncate` (`render.lua:89`) drops
characters until the string plus `"..."` fits one line, and card widths in a
crowded game are 33 px. "Score Red" and "Score Green" both render as `S...`.
Options, roughly in order of payoff: allow two lines for the title before
truncating; shrink the font per-card rather than truncating; or drop the word
that repeats across a set (every Lost Cities scoring card starts with "Score").

**Colours do not contrast.** `C.card_text` and `C.card_body` are fixed light
colours (`render.lua:22-23`) drawn over the card's own `color`, which content
chooses freely — white on the green expedition is the example, and it is
unreadable. The fix is not a palette, it is a **rule**: derive the text colour
from the background's luminance at draw time. That also removes an entire class
of authoring mistake, because no game file can then pick an unreadable pair.

**Line breaks are ugly.** Body text is `printf` with a wrap width and no
hyphenation, so a narrow card breaks mid-word. Now that the text band is
clipped and skipped when it will not fit (this session), the remaining question
is whether a card that small should carry prose at all, or whether the tooltip
is the right home for everything but the title.

**Tooltips want their own pass.** `tooltip.lua` composes up to six sections —
card text, zone-granted text, cost, needs, per-entity stats, ability hint,
attachments — into one `printf` with no hierarchy, no spacing and no ordering
rule. It reads as a wall. It also duplicates work `render.lua` does differently
in three other places (`:358` card face, `:502` detail panel, `:961` log), two
of which do not show zone-granted text at all, so the same card explains itself
differently depending on where you look.

**Do this one first among the three**, and do it as a whole rather than
symptom by symptom: every item above is really "there is no typographic system,
only per-site decisions".

---

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

### The original write-up

## Gap 2 — Drawing from the deck should be a gesture, not a token

*Urgency: medium · Difficulty: low for the rules, medium for the visibility rule
it needs · Usefulness: high (it removes the ugliest thing on the board)*

Lost Cities' draw step deals a single card, "Draw from the deck", into a tray
along the bottom edge. It is one card in a wide box, it is the only thing that
zone holds outside the tally, and it exists only because the deck itself cannot
be clicked.

**The rules already allow the better version, and need no change.** The discard
piles work by granting `takeable` to their contents:

```json
{ "key": "red_discard", "type": "pile", "tags": ["activate"],
  "applies": ["takeable"] }
```

The deck is the same shape. Tag it the same way and its top card offers the
same ability, gated to the same phase by the same tag. `on_top` already
restricts a stack to its top card; `zone_empty: ["deck"]` routing is untouched;
`draw_deck` and the `choice` zone's role in the draw step both disappear, leaving
`choice` for the tally alone. The draw step becomes one sentence — *click the
deck, or the top of any discard* — instead of a token that means the same thing.

**A 2×1 zone showing "the deck plus an action card" is the harder road** for a
worse result: it needs a layout mode no `type` has, and it puts a button on the
board to stand in for a gesture the board could carry directly.

**What it actually breaks is hidden information, and this is the real work.**
`card_at` (`main.lua:36`) skips deck zones entirely:

```lua
if z.zone_type ~= "deck" and zones.contains(z.place, x, y) then
```

Allowing decks through makes the top card clickable — and also **hoverable and
inspectable**, because `tooltip.update` and `inspect_at` are fed by the same
`card_at`. Hovering a face-down deck would name its top card. So this needs a
predicate the engine does not have:

> **Can this player see this card?** — false for a face-down stack, false for
> another seat's hand, true otherwise.

Clicking must consult reachability; hovering and inspecting must consult
*visibility*, and today one function answers for both.

**That predicate is worth building for its own sake.** It is exactly what hidden
hands need — the last open piece of multiplayer stage A, and the README's
current number one — and the renderer is completely seat-blind today, so in
hot-seat Lost Cities both players read each other's hands. One rule, two
features, and the second one is already wanted.

---

## Gap 3 — Choosing between several abilities — **shipped** (`d27d18a`)

*And by the route this section predicted: an ability is a thing with a name, and
the chooser is the offer overlay that already existed. `abilities` is a list
where `activate` was one thing, normalised at the door so a card with one is the
list with one entry — see [DONE.md](DONE.md), "A card that can do several
things". The refusal below held right up to the card that needed it: Coronation's
Small Council is five advisors on one card.*

### The original write-up

*Urgency: low (no shipped game needs it) · Difficulty: medium · Usefulness: low
now, load-bearing for anything MTG-shaped*

A card has one `on_activate`, and `begin_action` (`main.lua:78`) commits to one
intent the moment it is called. Modern MTG cards routinely carry two or three
activated abilities, and a card in hand may be both playable *and* activatable
once hands are allowed to activate at all.

**The engine already owns the answer:** a choice among cards is an overlay, and
`page: true` runs the *picked card's* own `on_pick`. Lost Cities' opening
question is exactly this shape. So an ability chooser is an overlay dealing one
card per ability, and needs no new interaction model.

What it needs is for an ability to be **a thing with a name**, which is the real
change:

```json
"abilities": [
  { "key": "tap_for_mana", "text": "Tap: add G", "on_activate": [...] },
  { "key": "regenerate",   "text": "2G: regenerate", "activate_cost": {...} }
]
```

`on_activate` becomes the one-ability shorthand for this list. Everything
downstream that reads an ability — `flow.can_activate`, `flow.activate`,
`cards.behaviour`, the tooltip hint, the render affordance — currently assumes
exactly one, so each learns to ask "which".

**Refuse until a game needs it.** The shorthand must keep working untouched, and
a chooser that appears for a single ability is a click tax on every existing
game. Build it with the first card that has two abilities, not before.

---

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

### The original write-up

*Urgency: medium — two of the three games anyone would show somebody end with no
screen at all · Difficulty: medium · Usefulness: high*

> *We need a good win/lose screen. With fireworks for the player if they win,
> and some sad effects if they lose. If multiple players are in the game, the
> winner should get the fireworks, and the loser(s) should get the loss screen,
> but also display in smaller text below who won.*

**The flourish is already built and the screen is already there.** `fx.celebrate`
(`fx.lua:141`) rains golden confetti for a victory and slow dark embers for a
defeat, and `render.lua:1481` draws a banner, the run summary from
`flow.summary()`, and fires the celebration once. So this gap is not "build a win
screen" — it is that **the screen is single-player and the engine has no idea
whose victory it is.**

Two separate holes, and the second is the larger one:

**1. The outcome is a word, not a seat.** `flow.outcome()` (`flow.lua:774`)
walks the open overlay's cards and returns the first `outcome` field it finds —
`"victory"` or `"defeat"`, a global fact. Six games write one, and every one of
them is solo: you against the tower, the road, the vigil. In a game with two
seats the same card would tell both players the same word, which is wrong for
exactly one of them.

**2. The two-seat games have no ending screen at all.** Chess ends with
`"end_conditions": [{ "stat": "count:king@taken", "at_least": 1, "then":
["load_game:menu.json"] }]` — the king is taken and you are dropped back to the
menu, with no announcement that anything happened. Lost Cities' `end_conditions`
is empty and its finish is a scoring pass. So the first thing to build is not
the screen but the **thing the screen reads**.

### What it needs

- **An outcome that names a seat.** *— shipped as a stat on the seat, not a
  field and not a subject; see above.* [Assumption: the smallest form that fits the
  existing vocabulary is `"outcome": { "winner": "<subject>" }` on the ending
  card — a subject, so a game says `"max:score@anyone"`-style *who* rather than
  hardcoding a seat, and Lost Cities' winner is already written exactly that way
  in a condition today (`{ "stat": "score@north_side", "at_least":
  "score@south_side" }`). The plain `"victory"` / `"defeat"` strings must keep
  working untouched, because six solo games are correct as they are and a seat is
  meaningless in them.]
- **A viewer**, which is [16](16-the-player-at-this-screen.md) gap 1 — **shipped**
  (`fb3d704`). "The winner gets the fireworks" is a sentence about the person at
  the screen, and the engine used to know only which seat was *up*, so in
  networked play the loser would have got the confetti whenever the last move
  happened to be theirs. `zones.viewer` is the seat to compare the winner
  against; the blocker is gone.
- **A name to print**, which is [16](16-the-player-at-this-screen.md) gap 2.
  Without it the smaller line reads *player_white wins*, which is a chair's key.
  It degrades honestly, so this is an ordering preference rather than a
  dependency.
- **The loser's screen says who won**, in the smaller line under the banner,
  where `flow.summary()`'s run summary already sits. That is a layout question
  the text pass (gap 1) already answered for every other panel: blocks with
  weights, measured then drawn, not one `printf`.

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

## Gap 8 — A card's numbers in a column, and what colours them — **shipped**

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
> One thing left, and it is small: a badge always draws an icon, so the token
> piles' `bank` count wears the fallback diamond on all six piles. The plate
> colour and the label say which gem it is, so this reads as clutter rather than
> as a lie — but a badge that is only a number has no spelling.
>
> **What it needs.** `stat_icon` (`render.lua:273`) returns the stat's declared
> `icon` or nothing, and `draw_stat_icon` (`render.lua:228`) draws the diamond
> for anything it does not recognise — deliberately, and `validate.lua` says so
> where it allows a colour with no shape. So the missing thing is a way for a
> stat to say it *has* no shape. [Assumption: this belongs on the stat and not
> on the style, by this gap's own colour argument — the badge and the HUD row
> (`render.lua:1144`) draw the same icon through the same call, and a style-side
> switch would make them disagree. `badge_zeros` went the other way because a
> zero is a fact about that card face; an icon is a fact about the number.]
> [Assumption: the spelling is a seventh word in the closed set — `"icon":
> "none"`, one line in `render.icons()` and one in `validate.M.ICONS`, keeping
> the field one type — rather than `"icon": false`, though `color: false` in
> [11](11-styles-as-tags.md) is a precedent for the other choice.] Both call
> sites then have to close the gap the icon left: `draw_badge` sizes the pill
> `fh + tw + 8 * S` and offsets its text by `fh + 3 * S`, and the HUD row
> indents by `fh + 4 * S`, so without the shape both must drop the `fh`.

### The original write-up


*From `todo.md`: "Instead of cards having their stats at the bottom, for
splendor it would make a lot of sense if we could list them as a column on the
card, and have icons or even coloured fonts", and — the same complaint from the
other side — "The cost shouldn't be part of the text, this makes it cumbersome
to read. This should be displayed like we display stats."*

Splendor's ninety development cards each carry their price twice. Once as
`card_stats` — `cost_white`, `cost_blue`, `cost_green`, `cost_red`,
`cost_black`, which is what the purchase arithmetic actually reads — and once as
the card's **title**, the string `"2R 1K"`, which is what a player reads.
`splendor.json`'s `market` style badges only `vp`, so the five numbers that
decide every purchase in the game are drawn nowhere and the title is doing
their job in an abbreviation nobody was taught.

The engine already has every piece of this except the layout.

- `draw_card_stats_overlay` (`render.lua:766`) draws a style's `badges` list as
  icon-and-number pills **along the bottom edge, left to right**. Five of those
  do not fit across a market card.
- `draw_cost_badge` (`render.lua:470`) already draws icon-and-number pills for a
  `play.cost` map — in the **top-left corner**, as a row. So the icon+number pill
  keyed by stat name is a shipped idiom with two call sites and two hardcoded
  placements.
- `stat_icon` (`render.lua:266`) reads the stat's declared `icon`, out of the
  closed set in `ICON_COLOR` (`render.lua:211`). A stat with none draws the
  diamond.

### What it needs

**A style says which edge its badges run along.** `badges` stays the list of
stat keys; the direction is a second field taking a word, the way `fan` already
does for a stack ("The word is the direction the next card goes"). Adding it to
`STYLE_FIELDS` (`validate.lua:225`) is append-only, and `SCHEMA.json` plus
AUTHORING's style table take the same sentence.

Two questions the note does not answer, and they are the whole of the work:

- **A zero is a line of the price that isn't there.** Every Splendor development
  card carries all five `cost_*` stats, most of them `0`, because the pricing
  arithmetic needs the stat to exist on all ninety. A column that draws
  `◆0 ◆0 ◆2 ◆0 ◆1` is worse than the abbreviation it replaces. But `power: 0`
  on a Runeterra unit must still draw, so "skip zeros" cannot be the layout's
  private rule. [Assumption: this wants to be said per style rather than per
  stat, since it is a fact about *this card face* rather than about the number —
  but the alternative, a word on the stat's own declaration, is exactly what
  gap 6 of [06](06-schema-and-types.md) is about, and if that is built this
  falls out of it instead.]
- **The icon set is shapes, and Splendor's five gems are colours.** `ICON_COLOR`
  fixes a colour per shape: `blade` is orange, so onyx would be an orange sword.
  Splendor's stats already borrow the five shapes (`t_white` is `diamond`,
  `t_black` is `blade`) and get five wrong colours. Either a stat declares its
  colour beside its icon, or badges take their colour from the style — the
  note's "or even coloured fonts" is asking for one of those and does not say
  which.

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
all gained a label they had always declared. **A grid still covers its own** —
its cells come from `zones.cell_rect` rather than from `card_places`, so LoR's
*Bench* still disappears under the first unit played into it. Left, deliberately:
it is the same fix in a different module and no game has complained.

That fix is not quite the same shape, and the difference is worth having written
down before starting. A grid's cards do not use `card_places` at all once the
zone declares `grid`: `zones.build` registers a slot per cell and `zones.resize`
gives each one `M.cell_rect(z, idx)`, which is also what hit-testing reads — so
reserving the band anywhere else would move the picture and not the target.
`cell_rect` is where it has to go, and that is the one obstacle: `zones.lua` has
no font, and the headless stub in `headless.lua` gives `love.graphics` nothing
but `getDimensions`, so a `getFont():getHeight()` call there breaks the whole
test suite. [Assumption: the way round it is the one [16](16-the-player-at-this-screen.md)
already took for `zones.viewer` — a field written from outside rather than a
call into the layer above. The renderer sets a label height on `zones` once,
`cell_rect` subtracts it from the top when `z.label` is set, and headless leaves
it zero, so `tests/integration/layout.lua` is unchanged.] A grid with no label
is untouched either way, which is chess's board and every square that has to
tile edge to edge.

**The wheel scrolled by the browser's pixel delta.** `love.wheelmoved` passed
`-dy * 3` into the inspector, and only the *sign* of `dy` is portable — natively
a notch is a small integer, under love.js it is a pixel count, so one click
scrolled a Splendor dump about eighty rows and the middle of it could not be
reached at all. Six lines a click, in the direction of the wheel.
