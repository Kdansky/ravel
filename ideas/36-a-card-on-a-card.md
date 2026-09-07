# 36 — A card on a card

**Status:** the engine is in — steps 1–3 below, with `tests/integration/attachment.lua`
as the record. **Left:** step 4, Arnak's rework, which is content.

A meeple stands on a site. A guardian tile lies on it. Both are one card sitting
on another, visibly, and readable apart from it — and that is the thing
[15](15-many-on-one-square.md) filed under "cards on a card", built as
`attach_to_target` and then never asked for. It is asked for now, **twice in one
game file**, which is the bar that file set for building it.

## Why Arnak needs it and a counter will not do

The engine records that a card is exhausted and not by whom, and a site space is
shared, so "who is standing here" has no answer. `overcome` was written around
that hole: it has no `exhaust` in its cost, deliberately, so you can come back
for a guardian later — and its only ownership gate is `guarded@mine.player >= 1`,
a per-seat tally. A tally is not a pointer, so **dig the site with the best
yield, then pay off the cheapest Level I guardian anywhere on the board**: the
counter drops, no Fear arrives at cleanup, and `guardians` is 5 points each.

The archaeologist as a real card is the rulebook's own noun and closes it at the
root rather than gating it. "Occupied" and "by whom" become one fact, `exhaust`
stops standing in for a figure, `guarded` stops being a tally, and
[arnak](arnak/design.md)'s divergence 5 disappears instead of being patched.
The guardian deck then restores divergence 4 — 36 tiles with their own prices —
as content, one deck per tier in the shape `site_1_deck`/`site_2_deck` already
has.

## What is built, and the three things that are not

`attach_to_target` (actions.lua:1142) moves the child into the parent's zone,
sets `child.parent_id`, appends to `parent.attached`. Codex uses it twice for
auras (codex.json:3839, 4345), so the idea file's "used by nothing" is stale.

**1. The link does not survive anything.** `parent_id` has one write and **zero
readers** in all of `game/`; `attached` is appended to and never emptied, read
only by tooltip.lua:123 and render.lua:1009, both counting. So there is no
detach, a destroyed parent eats its children, and a parent that moves leaves
them orphaned in the old zone still claiming it — very likely a live Codex bug,
since attach puts the aura in the creature's zone and nothing moves it when the
creature moves.

**2. Nothing can ask.** The whole design needs *"is there a token on this site,
and is it mine"*, and no scope reaches across the link in either direction.

**3. An attached card has no place.** It lands with no slot, so it never draws
and the badge is standing in for a card that is not on screen. Worse in a grid:
`move_card` falls through to `auto_slot`, so an attached card in a grid zone
**takes a free cell of its own** — it has not bitten only because Codex's
`army`/`patrol` are not grids.

## How

### 1. Attachment survives, and it is zones.lua's job

Not the ops. `move_card` and `destroy_card` are what every op funnels through,
which is the reason the supply rule is already written there rather than in
`add` — a draw, a take, a fill and a reclaim then all land right without knowing
attachment exists.

| | |
|---|---|
| a **child** moves anywhere | it detaches |
| a **parent** moves | its children follow, still attached |
| a **parent** is destroyed | its children detach and go to `origin`, so nothing is eaten |
| a child is attached | it holds **no slot of its own** — it stands on its host, so `auto_slot` skips it |

Sending the meeples home at cleanup then needs no new word at all:
`move`'s first argument is a scope and its third accepts `origin`
(actions.lua:708), which restores `origin_slot_id` too — so one line on the
route that already ends the round returns every figure to its exact spot in the
player's row.

### 2. Two scopes, spelled the way `owner_of` already is

- `attached_to.<scope>` — the cards attached to what it names.
  `count:meeple@attached_to.self`, `sum:side@attached_to.self`
- `host_of.<scope>` — the card they are attached to. `guard@host_of.self`, which
  is how the meeple's *second* activation reads the tile it stands on

**[Assumption: the spelling, not the words.** They were agreed as `attached` and
`host`; the prefix form is forced by `parse_scope`, which takes leading words
while they are a known quant or owner and treats the rest as a name — so
`@self.attached` parses as a zone called "self.attached". A relation is already
spelled as a prefix over an inner scope: `owner_of.target`, predicate.lua:325.
Same two words, fitted to the idiom that exists.**]**

Both go in `entities_in_scope` beside `owner_of`, and both are pools, so the
quantifier and owner words narrow them as anywhere else — `count:meeple@mine.attached_to.self`
is my figures on this site.

### 3. A child draws on its host

Place it at an offset off the parent's rect rather than counting it. **The badge
went entirely**, rather than staying as a fallback: a rider is always in its
host's zone, so it always draws, and a purple "2" over two small cards is the
same fact twice. The "Attached" row in the tooltip keeps the count where a count
is what is wanted.

### 4. Then Arnak, which is content

Two or three `meeple` cards per seat in their own row, activated onto a site;
`workers@mine.player` stops being a counter; `overcome` gates on
`sum:side@attached_to.self`; guardians become a deck per tier; cleanup is
`move:each.meeple:origin` on the route that already readies everything.

## Order

1. ~~Attachment survives — zones.lua, and an attached card holds no slot.~~
   **done.** `zones.attach` owns the invariant, `detach`/`release` are wired into
   `move_card` and `destroy_card`, and `auto_slot` skips a rider.
2. ~~The two scopes.~~ **done**, beside `owner_of` in `entities_in_scope`, with
   `RELATION_SCOPES` in validate.lua so a typo inside the prefix is still caught
   as a typo in an ordinary scope.
3. ~~Drawing a child on its host.~~ **done**, as a pass over whatever the layout
   worked out, so no layout knows attachment exists. The count badge went with
   it — it was standing in for a card that never drew, and the card draws now.
4. Arnak: meeples, guardian decks, the rules rewrite.

4 is where
[21](21-lost-ruins-of-arnak.md)'s remaining flag — that `predicate` cannot read
a card's own exhaustion back as a condition — stops mattering, because nothing
is asking about exhaustion any more.

## What this supersedes

[arnak](arnak/design.md)'s **who spent a card's exhaust** — the `spender` stamp,
ranked as item 33. It was the cheap answer to the same question and it stays
correct; it is struck because a figure standing on the site answers it without a
number, a stamp to wipe, or a cleanup line that must not be forgotten.
