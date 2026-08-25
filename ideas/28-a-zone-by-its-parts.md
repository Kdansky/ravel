# 28 — A zone by its parts

**Status:** design, not started · **Size:** large, mechanical ·
**Reopens:** [06](06-schema-and-types.md) gap 1, refused 2026-08-13 on a
condition that has now fired.

> *A zone's `type` answers seven questions at once, and a game may only have the
> five bundles somebody thought of. Ask the seven questions separately.*

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

## The seven questions

Re-derived from every `zone_type` read in the engine at `a159994`. Each row is
one question the engine asks and `type` currently answers by proxy.

| Field | Values | Default | What it decides | Read at |
|---|---|---|---|---|
| `layout` | `stack` · `row` · `grid` · `page` | — | Where each card is drawn, the arrival animation (`drop`/`glide`/`slam`), whether an empty box draws its cells, whether the label takes a band off the top, whether there are addressable slots — and therefore whether capacity is bounded | `render.lua:435,1120,1530,1819`, `zones.lua:147,353,455,623,642` |
| `visibility` | `public` · `owner` · `secret` | `public` | Purely what is drawn and what may be read: card faces or backs, whether the browser scrambles the order, whether a tooltip answers | `zones.lua:289,310,332`, `render.lua:1157,1205,1243` |
| `reach` | `all` · `top` | `all` | Which of the zone's cards exist as far as the rules go: what may be played, activated, targeted or clicked | `flow.lua:116`, `targeting.lua:207`, `zones.lua:683`, `tags.lua:84` |
| `use` | `play` · `abilities` · `none` | `none` | What may be done with a card here **at all** — the ceiling, which a phase's `zone` then narrows. One at a time: no game has wanted both | `main.lua:251`, `flow.lua:976`, `render.lua:640` (today: the `activate` tag) |
| `in_play` | `board` · `exile` | `exile` | Whether the rules can see it: tag scopes, `count:`, `card:`, `sacrifice:`, `on_turn`, `from: "board"` | the nine sites listed above |
| `display` | `onscreen` · `offscreen` | `onscreen` | Whether the zone is drawn and whether anything in it can be clicked | today's `hidden` tag |
| `copies` | `one` · `per_seat` | `one` | One zone, or one per seat — and therefore whether `visibility: owner` means anything | today's `per_seat` tag |

**Enums, never booleans.** `in_play: "board"` and `display: "onscreen"` rather
than two flags: a word says which of several things it is, and leaves room for
the next one. MTG's graveyard is the case waiting — not in play, and read
constantly by rules that name it — which is `exile` plus naming the zone today,
with a slot free if it ever needs its own word.

**A value names its own parameter field.** `layout: "grid"` makes `grid:` a legal
field holding `[cols, rows]`; `layout: "row"` makes `row:` legal holding the fan
direction. This is not new — `type: "grid"` + `grid: [4, 1]` is how the format
already works — it is that idiom made a rule, so a parameter never needs a name
invented for it and never needs a home in `style`.

Every enum value on every one of the seven fields is therefore **reserved**:
nothing else may take that field name. Checked against `ZONE_FIELDS`, `activate`
is the only live collision and `grid` is the intended one.

**Row absorbs fan.** A row is a fan whose overlap is off, so they are one layout
with a direction: `layout: "row"` for a hand, `layout: "row", "row": "down"` for
a Lost Cities expedition column. Named `row` rather than `fan` because the
absent parameter must be the common case — call it `fan` and every hand in every
game writes `"fan": "none"` to say it is not one.

`page` stays its own value: the engine's reveal overlay, no game uses it, and it
is a layout wearing a tag exactly as `fan` was.

`stack` stays its own value too, though it is strictly the far end of the same
overlap continuum — 73 of the corpus's 137 zones are stacks, and
`"layout": "row", "row": "stacked"` is a worse spelling of the commonest thing
in the format.

`use` defaults to `none` for the same reason `in_play` defaults to `exile`: a
zone is inert until it says otherwise, so exile costs nothing to write and a
mistake fails closed. The corpus agrees — 73 stack zones that are inert against
116 `activate` tags and 32 hands.

`display` needs its own word rather than folding into `visibility`, because
`secret` is a different fact: a deck is drawn, counted, and unreadable. One word
cannot be both.

`stack` rather than `deck`/`pile`: a list of cards where the top one gets special
treatment. That is the whole of what those two share, and facing is what
separated them — which is now `visibility`, one axis over.

## The current types are presets over those

```
deck    = stack · secret · top · none      · exile
pile    = stack · public · top · play      · exile
hand    = row   · owner  · all · play      · exile · per_seat
grid    = grid  · public · all · abilities · board
options = row   · public · all · play      · exile · offer
```

Which is the point: the bundles were never wrong, only closed. What the split
buys is the combinations nobody was allowed to write.

- **The ongoing row** — `row · public · all · abilities · board · per_seat`. The case
  that reopened this.
- **An infinite board** — the same thing without the activation. Capacity is
  bounded by `grid: [cols, rows]` being present at all, so a board that is a row
  has no ceiling and needs no new field.
- **Exile, trash, the removed-from-game pile** — `stack · public · all · none ·
  exile`, which is every default but the layout. Cards there are still *nameable*, because naming a zone
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
- `display`, `copies` — renames of the `hidden` and `per_seat` tags.
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

## Settled since

1. **`use` holds one value.** No game has wanted a zone you may both play from
   and activate in, and the ceiling is easier to explain as one word.
2. **Playability needs zone *and* phase to agree** — a creature is castable when
   it is your turn *and* it is in your hand. `use` is the ceiling, the phase's
   `zone`/`zone_list` is the gate, and neither alone is permission.
3. **`style.fan` becomes the `row` layout's parameter.** It is a layout and
   always was: today it silently overrides the `type` row at `render.lua:450`
   and hit-tests every card while `flow.on_top` refuses all but the top. Under
   the split that is `layout: "row", "row": "down"` + `reach: "top"`, said on
   purpose. Check no other style is doing the same trick.
4. **`use: "activate"` renamed to `"abilities"`.** The parameter rule settles
   this mechanically rather than by taste: the value would reserve `activate:`,
   which a zone already uses for its *own* ability — how a deck gets drawn from
   — and that is not a parameter of anything. The value moves, not the block:
   `activate:` appears in 116 places and the value in none yet.
5. **`row` absorbs `fan`; `stack` and `page` stay.** See above.

## Open

1. **`no_peek` has no home.** It means no tooltip and no browsing the *buried*
   cards, which is a different question from what is drawn — a pile with it is
   public on top and secret underneath. Two uses in the corpus, so it can stay a
   tag, but then `visibility` is not quite the one axis it claims to be.
2. **The offer role is none of the seven.** An `options` zone lends a card that
   whoever is up may reach *regardless of who owns it* (`flow.lua:54`), and
   empties itself when the question is answered (`flow.lua:931`). Neither fact
   is a layout, a visibility, a reach, a use, an in-play or a display. Either an
   eighth field or it stays a role.
3. **What the validator must refuse**, beyond the existing `check_fields` walk
   at `validate.lua:1771`: an unknown value on any of the seven fields, and a
   parameter field whose value was not chosen — `grid: [4, 1]` beside
   `layout: "row"` is a zone that thinks it is two shapes.
