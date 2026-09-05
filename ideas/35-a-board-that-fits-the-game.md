# 35 — A board that fits the game

**Status:** not started. Came out of Spellstorm's clutter: a screen carrying
every character's furniture while two characters are being played.

Two of the three complaints that started this were answered without a format
word and are shipped — the wizards became a `roster` zone dealt with `options:`
(so nobody plays a mirror match), and everything a wizard alone needs goes in a
per-seat `sidecar`, an unlabelled `row` that draws nothing while it is empty.
What is left is the case those two do not reach.

## The shelf — several zones, one rect

`validate.lua:2482` refuses overlapping zones, and is right to: nothing in the
format says two zones are never open at once. So a game with two zones that
*are* mutually exclusive has to find two rects for one idea.

It already has customers, and they were written down before this was asked for:

- **`commit` and `battle`** in `make_spellstorm.py:1378` carry a comment saying
  in as many words that *"they would share a rect if they could — the two are
  never both occupied, so the reveal would be the card turning over where it
  lay"*. They are two zones and not one because `visibility` is a property of
  the place; the face-down card is exiled to a strip down the right edge purely
  to satisfy the overlap check, and the reveal is a slide instead of a flip.
- **A character's furniture.** The sidecar handles the *one* row case. A wizard
  wanting a grid, or two zones, in the same space as another wizard's is the
  shelf.

The spelling to argue about: **`pos` naming a zone instead of four numbers.**
`"pos": "commit"` reads as *where that one is*, costs no new key, and gives the
overlap check exactly the sentence it is missing — two zones on one shelf are
declared as such, and every other overlap stays an error.
**[Assumption: nothing was checked about what `zones.resize` does with a `pos`
that is not four numbers, nor what `copies: "per_seat"` means when the zone it
points at is per-seat too — presumably seat *n* follows seat *n*. Both are
reading, not design.]**

What a shelf does **not** decide is which of its zones is showing. An empty
unlabelled zone already draws nothing, so for the two customers above the answer
falls out of the contents.

## `shown_when` — and why to resist it

The general version is a condition on a zone deciding whether it draws.
`display` is already a live entity field (`zones.lua:127` copies it at creation
and every consumer reads the entity), so a runtime `display: "offscreen"` is one
field write and already round-trips through save, undo and the network for free
— the mechanism is not the problem.

The problem is that a condition evaluated every frame is a new thing in the
engine, and a zone that vanishes leaves a hole unless something else takes the
space. **So the shelf comes first**: with two zones sharing a rect, "which one
is showing" is a question with a bounded answer, and `shown_when` on its own is
a licence to punch holes in a layout.

## The seat's own name

Separate axis, raised in the same conversation and deliberately parked: once
wizards are picked, *"Player One"* is the wrong name for a seat, and the react
bar (`render.lua:1481`) prints it faithfully. `{owner}` cannot fix it —
`seat_name` returns the seat card's `text`, and Spellstorm's seat cards are
literally `"text": "Player One"`. Something has to rename the seat.

Three shapes, none picked:

1. **`seat_name` falls through** to a zone the seat owns — the wizard zone's one
   card names the seat once it holds one.
2. **A `name:` verb**, so a pick writes the seat's own text.
3. **`transform`**, with a per-wizard seat card, which the format already has.

**[Assumption: 1 is the cheapest and the only one needing no format word, but
which zone to fall through to is either a convention or a field, and a
convention here is the kind of unstated default this repo has been burned by.]**
