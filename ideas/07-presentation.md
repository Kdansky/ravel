# 07 — Presentation and the gestures on top of it

**Status:** not started · **Size:** the first gap is the largest design job in
this list; the other two are small and specific.

The rules are in better shape than the surface they are shown through. Every
item here is something a player sees or does, not something the engine computes.

---

## Gap 1 — A pass on text, contrast and layout

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
