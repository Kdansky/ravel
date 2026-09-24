# 38 — The shapes that repeat

A survey of the three biggest games in the box — Codex (425 cards, 279
abilities), Puzzle Strike (195 / 30) and Spellstorm (150 / 234) — for structure
that appears often enough to be a spelling rather than a card. Counted
mechanically: action n-grams, ability shapes with the numbers blanked, target
blocks compared whole, and `mine`/`enemy` mirror pairs.

Two kinds of finding, kept apart because they cost different things. The first
kind is a sentence the format already holds and the file does not use — content
work, no engine change, and the only real question is whether the validator
should have said so. The second kind is a word that is missing.

## Already sayable

- **Codex's combat macro, written out three times** — built. All 33 duel
  passes sit on `tags.fighter` now, in one place. The lesson it paid for: the
  three `strike_*` abilities differed in nothing but which zone they aimed at,
  and reading them side by side was the only way to see it.
- The rest of this kind is [43](43-what-the-files-already-say-twice.md), which
  surveyed the same three files again and found a tag that carries 63 identical
  `play` blocks, a stat `start` worth 46 `card_stats` entries, and 19 `subject`
  lines that say what a bare subject already says.

## Missing words, in the order worth building

### 4. The death half

An arrival is a moment the engine fires, and 49 `activate_zone:rules_arrive`
lines went when it learned to. `rules_death` is the other half, appears 54 times
in Codex, and is **not done**, deliberately. Four hooks were worked through and
every one of them failed, all for the same reason, and the reason is the useful
part.

**The 54 calls, measured.** 46 are the last line of a list that damaged or
destroyed something — `["harm:hp@target:2", "harm:life@target:2",
"harm:integrity@target:2", "activate_zone:rules_death"]`, forty-six times with a
different first line each. The duplicated text is one string. 8 are
load-bearing: `shadow_blade` and `nature_reclaims` call it *mid*-list because
the next step needs the deaths settled first, three attack abilities call it
because the killing happened eleven nested passes deep in the duel column, the
`draw` phase calls it before the endturn walks, and `deteriorate` and `sickness`
call it because they hand out a −1/−1 rune rather than damage. Whatever replaced
the 46 has to be idempotent, because those 8 would fire it again — and the column
is, since a board with no corpses does nothing.

**There are two roads to a death, and they do not overlap.** Measured on a live
board:

```
destroy: a unit    →  emits "died"    hp still 2, card already in the discard
harm to zero       →  emits nothing   hp now 0,  card still standing in the army
```

`destroy:` moves the card, so `leaves` fires and Codex's
`tags.unit.leaves` already turns that into `emit:died` — **14 of the 54 need no
engine change at all and never did.** The other 40 are a number crossing a floor:
30 damage lines, 4 nested walks, 3 stats written straight to nought, 3 runes.
`destroy` catches none of those, and a threshold catches none of the 14.

**What was tried, and why each failed.**

- *A global `moments` block.* Wrong shape and rightly rejected: an arrival
  belongs to the place it happens in, not to a table of hooks. Its replacement
  for arrival, a word on the zone, is what shipped.
- *A zone-level `leaves`, symmetric to `arrives`.* Cannot drive these. Every
  payout rule reads the corpse **while it is still standing** —
  `count:dead@mine.patrol.at_scav >= 1` is asking which patrol slot it died in —
  and `r_units` at the bottom of the column is what finally moves it. The
  departure is the last step of resolving the death, not its trigger.
- *A computed tag that announces itself when a card starts wearing it.* The
  best-shaped of the four, and the only one still worth proposing. `dead` is
  already `hp@self < 1`, so the game has written down what death means; the
  engine sees every stat change and could announce the transition. Two costs: a
  computed tag carries nothing today except `buffs`, whose carve-out sentence
  says "and nothing else", so this becomes the second exception; and "started
  wearing it" needs the previous answer remembered. That second one is cheaper
  than it first looked — keyed by *tag name* it is a string key already, unlike
  the card-id set that forced `re_answered` to be a list.
- *Arriving in a grave zone as the death event.* Circular for the damage road,
  and the tags say why:

```json
"returning": { "needs": ["homing@self >= 1",       "hp@self < 1"] }
"reviving":  { "needs": ["tagged:juggernaut@self", "hp@self < 1", "lives@self == 0"] }
"claimed":   { "needs": ["insured@self >= 1",      "hp@self < 1"] }
```

  **Codex has death replacement.** A card at nought is not on its way to the
  graveyard: Brave Knight goes to *hand*, Justice Juggernaut is healed back up
  and never dies at all, and the Insurance Agent pays out before it leaves.
  Arriving in the graveyard is the *answer* the rules produce, not the question
  that starts them.

**So the one fact all four hit.** Arrival is a moment, which is why a word for it
worked. **Death here is not a moment — it is a state the rules then resolve**,
and the corpse standing at nought carries what nothing else does: which slot it
died in, whose it was, whether it is insured, whether it has a second life. Any
hook that moves it first throws that away.

Which leaves one shape that fits: *check the board for pending deaths, now.* The
46 calls are the author saying exactly that, 46 times. A word for it is one
**engine zone tag** on the column that gets walked — the weight of `shuffle` and
`refill_when_empty`, not a section of its own. Built once as a top-level `sweep`
section and reverted: a section is a claim that the game declares a new kind of
thing, and this is a property of one zone.

**One thing left here that needs no engine change at all** — the mirror pairs
went first, and are written up in §1; they were the bigger duplication.

- **The `destroy` road may have a live bug.** `r_scav` reads
  `count:dead@mine.patrol.at_scav` — a *destroyed* patroller has already left the
  patrol, so the Scavenger pays nothing, where in Codex it pays however the unit
  dies. Worth checking before any word is added, since it changes what the word
  would have to cover.

### 6. A printed stat that steps

Codex heroes read *"Levels 1-3 2/3, levels 4-6 3/3, level 7 4/3"*. The file says
it as the 36 `lvlN` abilities that §"Already sayable" could not collapse, each
`stat_set`ting `atk` and `life` on the way past — which is also why levelling
heals, as an accident of `stat_set` rather than because anything says so.

`card_stats` already takes an object where a plain number will not do
(`"life": { "value": 3, "max": 3 }`). A stepped form would let the card say its
own sentence and would take the accident out. `buffs` cannot do this: the amount
"is a plain number, never a subject" by design, so it cannot vary per card.

### 7. An ability cannot act and then ask

**The gate half of this split shipped** as gates in `needs`
([46](46-one-list-of-conditions.md)): all 22 of Spellstorm's `cast2`/`cast3`
abilities were a gate and not one a genuine second step, and they are lines
in `cast` now. What stays here is the
`cast_ask` half — acting and then asking, which is about the offer queue rather
than about a condition.

29 Spellstorm cards split their resolution into `cast` and `cast_ask`, with the
answer landing in `chosen`. The resolve phase then walks the zone four times —
`cast`, `cast2`, `cast3`, `cast_ask` — and the ordering of a card's own
resolution lives in the spelling of its ability keys. Codex does the same thing
harder, walking the duel zone eleven times.

Naming a step is the right word for *"every unit works out its damage, then
every keyword reduces it, then every unit takes it"* — that is a genuine
resolution in passes, and actions.lua says so at length. It is the wrong word
for "this one card does a thing and then asks a question", which is one card's
business and is being paid for by every card in the zone.

## Smaller, and already noted in the generators

- `move:` and `destroy:` both take a count now (`move = "scope zone n? pos?"`),
  so "discard two at random" is one line — and Spellstorm still writes it twice.
  See [43](43-what-the-files-already-say-twice.md).
- A one-tracker toggle like initiative is two writes and cannot be said as one
  (make_spellstorm.py:45).
- `needs` has no `or`, which is deliberate and on `todo.md`. Worth recording
  that the `any_of` workaround is now load-bearing in all three games: `hidden`,
  `buildable`, `finished`, `hasty`, `ranged`, `exhaustable` in Codex, `held` and
  `curse_or_ice` in Spellstorm, `stowed` in Puzzle Strike.
- "Is this card mine?" has no word — two clumsy spellings and no clean one.
  Most of the sites went when a card learned to read as its own side, which made
  the guards tautologies; the question is [17](17-conditions-as-expressions.md)'s
  now, ranking row 70.
