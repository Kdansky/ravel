# 07 — Presentation and the gestures on top of it

**Status:** not started · **Size:** gap 1 is the largest design job in this
list; the other four are small and specific.

The rules are in better shape than the surface they are shown through. Every
item here is something a player sees or does, not something the engine computes.

---

## Gap 1 — A pass on text, contrast and layout — **shipped**

*The card face is the part that shipped: the picture takes the whole card and
the words float over it, outlined, fitted rather than cut. The tooltip pass
below is still open.*

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

## Gap 3 — Choosing between several abilities

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
