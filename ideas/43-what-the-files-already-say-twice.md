# 43 — What the files already say twice

**Content work, no engine change.** Items 1–5 shipped 2026-09-23: the `spell`
tag carries the play 63 cards wrote out, `tier_req` starts at 1 so 46 cards stop
saying so, 19 redundant `subject` lines are gone from two files, and the doubled
`destroy:random` and `power_up` lines are one line with a count.

What is left is one thing, and it is recorded rather than recommended.

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

## Noticed while item 5 was being done, not measured

Nine adjacent `stat_gain:mana@mine.player:1` pairs in Spellstorm are the same
shape as the Power pairs item 5 folded. Nothing declares an `adjusts` on `mana`
and no verb wraps it, so the fold looks free — but it was left alone because it
was outside what item 5 had been checked against, and a stat with no aura today
is not a stat with no aura tomorrow. *[Assumption: whoever does it repeats item
5's check rather than reasoning from the absence of an aura.]*
