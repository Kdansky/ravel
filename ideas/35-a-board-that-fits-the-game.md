# 35 — A board that fits the game

**Status:** not started. Came out of Spellstorm's clutter: a screen carrying
every character's furniture while two characters are being played.

Two of the three complaints that started this were answered without a format
word and are shipped — the wizards became a `roster` zone dealt with `options:`
(so nobody plays a mirror match), and everything a wizard alone needs goes in a
per-seat `sidecar`, an unlabelled `row` that draws nothing while it is empty.
What is left is the case those two do not reach.

## The shelf — several zones, one rect

**Shipped as `pos` naming a zone.** `"pos": "battle"` reads as *wherever that one
is*, costs no new key, and gives the overlap check the sentence it was missing —
two zones that are never both open declare it, and every overlap nobody declared
stays an error. The whole of it is in `AUTHORING.md`'s *A shelf*.

Two decisions worth keeping:

**Which one shows is not declared, it is observed.** The zone drawn is the first
holding a card, host first and then the tenants in file order; empty, it is the
host, so a label and its art do not blink out between moves. A condition per zone
would have been `shown_when` arriving through the back door.

**The group is derived from the file, not stored on the entity.** `G.shelf_of`
is built once in `parse` from the zone list and held under every member's key, so
nothing about the layout crosses the wire or a save — both peers have the file.
The rect is likewise read off the *host's def* rather than its entity, so the two
may be built in any order.

The customer it was written for is in: Spellstorm's face-down card was exiled to a
strip down the right edge purely to satisfy the overlap check, and the reveal was
a slide across the screen. `commit` sits on `battle` now and the card turns over
where it lay.

## `shown_when` — and why to resist it

The general version is a condition on a zone deciding whether it draws.
`display` is already a live entity field (`zones.lua:127` copies it at creation
and every consumer reads the entity), so a runtime `display: "offscreen"` is one
field write and already round-trips through save, undo and the network for free
— the mechanism is not the problem.

The problem is that a condition evaluated every frame is a new thing in the
engine, and a zone that vanishes leaves a hole unless something else takes the
space. **The shelf went first and may have answered it**: two zones sharing a
rect ask "which one is showing" and get a bounded answer, computed rather than
declared. Before building `shown_when`, find a customer the shelf does not
already serve — a zone with nothing to hand its space to.

## The seat's own name

**Shipped, and in use.** `transform` — the shape drafted here first — turned out
unsafe rather than merely unpicked: it swaps a card's `def_key`, and every seat
lookup (`turn_seat`, `active_seat`, per-seat zones, `@mine`) is keyed by the seat
card's original one. The fallthrough-to-a-zone option needed an unstated
convention for which zone.

What shipped needed no new read path: a seat declares `"text": "{name}"` and a
`"name"` beside it, `label.fill` already reads the live entity before the def,
and `set_name:<scope>:<field>@<source-scope>` writes the entity's `name`. Both
halves are in `AUTHORING.md`'s *A caption that reads the board*.

**The trap, three times over: a read path that bypassed `label.fill`.** Each one
printed the literal `{name}`, and each was found only by giving a real seat a
template — `label.lua`'s own `seat_text`, `render.lua`'s duplicate of it (deleted
in favour of exporting the first), and `flow.winner()`, which is the end-of-game
banner and the one a player was most likely to see. Anything else that reads a
card's `text` off the def is the fourth.
