# 28 — A zone by its parts

**Status:** design, not started · **Size:** large, mechanical ·
**Reopens:** [06](06-schema-and-types.md) gap 1, refused 2026-08-13 on a
condition that has now fired.

> *A zone's `type` answers five questions at once, and a game may only have the
> five bundles somebody thought of. Ask the five questions separately.*

## Why this is open again

Gap 1 of [06](06-schema-and-types.md) surveyed the whole matrix and refused the
split, for a reason it wrote down and a condition it named:

> Revisit if a game genuinely wants a combination no current type offers. The
> one that has come closest is a face-up deck, which is `pile` in every respect
> that matters, so it is not evidence.

Puzzle Strike is the evidence. Its ongoing chips are laid face up in a row in
front of one player: an unbounded row of separately readable cards that are **in
play**. Every existing type gets one half of that and loses the other — `grid`
is in play and bounded to a fixed count of cells, `hand` is an unbounded row and
secret and not in play. It took `hand`, and the bill came in twice:

- **`from: "board"` could not reach it.** Every reaction on a laid-out chip was
  unreachable, so Dragon Form, Panda's Bargain, Hundred-Fist Frenzy and
  Combinatorics were dead. Patched by letting a reaction name its zone —
  which works, and is a workaround for this.
- **Eight more rules still cannot see it.** `count:<tag>`, `card:<key>`,
  `tagged:`, a bare tag scope, `@all`'s player walk, `sacrifice:<tag>` twice
  over, and `on_turn` all read "in play" as `zone_type == "grid"`
  (`predicate.lua:160,305,358,360,364`, `flow.lua:373,708,744`,
  `reactions.lua:52`). A chip on the ongoing row is not counted, cannot be
  sacrificed, and never acts by itself.

The refusal also stands against the shape it was offered in. It was refused as
**tags** — *"tags are a flat unordered set with no grouping and no defaults, so
`stack` + `face_down` + `closed` + `top_only` is four independent chances to
write three of them"* — and named fields as the more honest alternative. A
validator can reject a contradiction; it cannot supply a default or keep two
words that must move together in step. So: fields.

## The five questions

Re-derived from every `zone_type` read in the engine at `a159994`. Each row is
one question the engine asks and `type` currently answers by proxy.

| Field | Values | What it decides | Read at |
|---|---|---|---|
| `layout` | `stack` · `row` · `grid` | Where each card is drawn, the arrival animation (`drop`/`glide`/`slam`), whether an empty box draws its cells, whether the label takes a band off the top, whether there are addressable slots — and therefore whether capacity is bounded | `render.lua:435,1120,1530,1819`, `zones.lua:147,353,455,623,642` |
| `visibility` | `public` · `owner` · `secret` | Purely what is drawn and what may be read: card faces or backs, whether the browser scrambles the order, whether a tooltip answers | `zones.lua:289,310,332`, `render.lua:1157,1205,1243` |
| `reach` | `all` · `top` | Which of the zone's cards exist as far as the rules go: what may be played, activated, targeted or clicked | `flow.lua:116`, `targeting.lua:207`, `zones.lua:683`, `tags.lua:84` |
| `use` | `play` · `activate` · `none` | What may be done with a card here **at all** — the ceiling, which a phase's `zone` then narrows | `main.lua:251`, `flow.lua:976`, `render.lua:640` (today: the `activate` tag) |
| `in_play` | `true` · `false` | Whether the rules can see it: tag scopes, `count:`, `card:`, `sacrifice:`, `on_turn`, `from: "board"` | the nine sites listed above |

Plus `offscreen` (`true`/`false`), which is today's `hidden` tag: the zone is not
drawn and nothing in it can be clicked. It needs its own word because
`visibility: secret` is a different fact — a deck is drawn, counted, and
unreadable — and one word cannot be both.

`stack` rather than `deck`/`pile`: a list of cards where the top one gets special
treatment. That is the whole of what those two share, and facing is what
separated them — which is now `visibility`, one axis over.

## The current types are presets over those

```
deck    = stack · secret · top · use none      · not in play
pile    = stack · public · top · use play      · not in play
hand    = row   · owner  · all · use play      · not in play
grid    = grid  · public · all · use activate  · in play
options = row   · public · all · use play      · not in play · offer
```

Which is the point: the bundles were never wrong, only closed. What the split
buys is the combinations nobody was allowed to write.

- **The ongoing row** — `row · public · all · use activate · in play`. The case
  that reopened this.
- **An infinite board** — the same thing without the activation. Capacity is
  bounded by `grid: [cols, rows]` being present at all, so a board that is a row
  has no ceiling and needs no new field.
- **Exile, trash, the removed-from-game pile** — `stack · public · all · use
  none · not in play`. Cards there are still *nameable*, because naming a zone
  reaches it and always has; what they are not is clickable, countable, or
  sacrificeable. There is no way to say that today: any zone a rule can name is
  a zone whose cards a tag search finds.
- **A face-down board** — in play and unreadable, which is two axes the old
  bundle welded into one. [06](06-schema-and-types.md) already flagged the
  mirror of it: **a face-up deck stays unclickable and unsearchable**, because
  the three exclusions belong to *closed*, not to *face down*. That was written
  up as "a bug worth fixing on its own"; here it stops being possible.

## What each axis costs to build

Shallow in the code and wide in the files, which is the [17](17-conditions-as-expressions.md)
shape — that one moved 112 conditions across ten games and was worth it.

- `layout`, `visibility`, `reach` — mechanical. Nineteen call sites, each one
  already asking a narrower question than `zone_type` answers.
- `use` — a rename of the `activate` zone tag (three reads) plus a new refusal
  for `none`. The interesting half is that **playability is a phase's property
  today**, not a zone's: `zone`/`zone_list` on the phase says where you may play
  from. `use` is the ceiling and the phase stays the gate, so a phase naming an
  exile zone still gets nothing.
- `in_play` — nine call sites, all spelling `{ grid = true }` for a question that
  has nothing to do with cells.
- `offscreen` — a rename.
- The files: **137 zone declarations across the four games, 155 more in tests and
  fixtures**, plus four generators and the AUTHORING/SCHEMA sections.

## Decided

- **Fields, not tags.** The 2026-08-13 reason still holds and is the reason.
- **No `type` shorthand kept alongside.** One question, one spelling
  (`DESIGN.md`); a preset word beside the fields it expands to is the same
  question asked twice, and the migration is mechanical either way.
- **`face_up` / `face_down` stop being tags** and become `visibility` values, for
  the same reason. They are values on that axis wearing tag clothing.
- **Visibility is rendering only.** A card in play may be unreadable and a card
  nobody can touch may be perfectly visible, so nothing else may read this field.

## Open

1. **May `use` hold more than one value?** A hand you may also activate out of is
   a real thing (Puzzle Strike's ongoing row is activate-only, but a game that
   lets you both play and use a card from hand is not exotic). Either `use` takes
   a list, or it stays one word and the rarer half goes back to being a tag.
2. **What does `reach: top` mean for a browser?** A buried pile card is readable
   in the browse view and not playable, which is right — so `reach` must not be
   read by the renderer. Worth stating, since `zones.card_at` currently mixes the
   two.
3. **`style.fan` already breaks the bundle.** Lost Cities' expedition columns fan
   every card, hit-test every card, and refuse all but the top. That is correct
   for Lost Cities and it happens by side effect — under the split it becomes
   `layout: stack` + `reach: top` + a fanned style, said on purpose. Check no
   other style is doing the same trick.
4. **Defaults.** Five fields per zone is a lot to write; most zones want
   `public · all · not in play`. Defaults do most of the work, and picking them
   badly is how the old refusal's "five or six words to keep consistent" comes
   true after all.
