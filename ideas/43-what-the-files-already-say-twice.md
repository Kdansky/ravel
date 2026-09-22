# 43 — What the files already say twice

**Content work, no engine change.** Every item here is a thing the format
already says in one line and a shipped game says in fifty. Kept apart from
[41](41-a-name-for-a-list-of-actions.md) and
[42](42-an-if-inside-an-action-list.md) because it costs nothing to agree to,
and because the honest size of those two tracks is what is left *after* this one
lands.

The generators are the source for four of these files, so the edit is to
`tools/make_*.py` and never to the JSON.

## Verified

A candidate `spellstorm.json` was built with items 1–3 applied and checked three
ways: `check.lua` clean, an identical initial state (156 entities, zero differing
stat/zone entries), and deterministic playouts — always the first legal move,
seeds 3 and 7, at 40 and 120 moves — fingerprinting identical to the original.

### 1. A tag carries the `play` that 63 cards repeat

Spellstorm. Every card tagged `spell` plays the same way:

```json
"play": { "action": ["move_to:mine.commit"] }
```

63 of the 66 carriers write it out. One `tags.spell.play` says it once. The
three that must not — `ice`, `ash` and `curse`, the junk — opt out with
`"play": { "action": [] }`, which already means *not a move* (AUTHORING,
*A card with nothing to run is not a move*). Checked: `flow.can_play` gives the
same answer for all three, before and after.

**2,331 bytes, 63 blocks.**

### 2. A stat's `start` says what 46 cards repeat

Spellstorm declares `tier_req` with no `on` and no `start`, so all 66 spells
write their own. 46 of them write `1`.

```json
{ "key": "tier_req", "on": ["spell"], "start": 1, "min": 0, "max": 9, "display": "offscreen" }
```

The 20 exceptions still write a number. `tier_req` is carried by exactly the 66
cards tagged `spell` and by nothing else, so `on` is honest rather than
approximate.

**46 `card_stats` entries.**

### 3. A stat's `subject` that says what a bare subject already says

Twelve Spellstorm stats and seven Puzzle Strike stats declare
`"subject": "<key>@mine.player"`. A bare subject already resolves to the active
seat: `flow.summary()` is byte-identical with the field and without it, in both
games. Codex declares none and is right.

**19 lines across two files.**

## Worth doing, not yet verified

### 4. `destroy` and `move` take a count

`r_dry_ice` writes `destroy:random.mine.hand` twice. `SPEC` has
`destroy = "scope n?"` and `move = "scope zone n? pos?"`, and
`destroy:random.mine.hand:2` was checked to leave the same hand.

This also retires a note in [38](38-repeated-shapes.md): *"`move:` takes no
count, so 'discard two at random' is the line twice"* — `move` gained one since.

### 5. `power_up` twice is `power_up` once with a 2

Six Spellstorm sites write `power_up:power@mine.player:1` twice for *"gain 2
Power"*. The doubling **looks** load-bearing, because the Power Track is an
`adjusts` with an `instead` that raises the Tier, and a single gain of 2 might
raise it once where two gains of 1 raise it twice. It is not: with `wiz_derby`
in play, from `power 5 / tier 1`, both spellings give `power 1 / tier 2`.

Worth stating because the wrong conclusion here would have been a new engine
word for *repeat N times*, and the only real customer left for that word is
Spellstorm's `r_croh_redraw_1..4` — which [41](41-a-name-for-a-list-of-actions.md)
absorbs.

## Recorded, with one customer and no recommendation

### 6. A badge can only name a stat, so a keyword becomes a fake number

Puzzle Strike declares `hits`, `react` and `plus_piggy` with `"number": false`
— the file saying *this has no quantity* — and stamps them onto cards as
`card_stats`. `hits` is `1` on all 19 of its carriers; `react` is `1` on all 19
of its. Neither is read by any condition or action anywhere in the file: they
exist to draw an icon, because `styles.chip.badges` is a list of **stat keys**
and a tag cannot put a badge on a card.

This is [DESIGN](../DESIGN.md)'s *No Boolean Fields* the wrong way round — a
quality written as a value because the drawing code only reads values.
**52 `card_stats` lines, one game, no other customer in the box**, which is
below the bar the README sets for inventing a word. Recorded so the next game
that wants a keyword icon finds this rather than re-deriving it.
