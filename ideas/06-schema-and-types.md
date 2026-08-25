# 06 — Saying what things are

**Status:** **closed.** 1 surveyed and refused, 2 and 3 folded into
[17](17-conditions-as-expressions.md), 4 and 5 shipped, 6 dissolved, and the
last one — a tag scope that could not reach a hand or a deck — **shipped as
`@everywhere`** (see below). Every gap is now decided.

## The last gap — a tag scope that sees a hand — **shipped as `@everywhere`**

`count:<tag>` and a tag scope (`count:<tag>@<tag>`) search grid zones only, and
that stays the default *on purpose*: most rules must not read a hand they cannot
see. What was missing was the **opt-in** — a way to count a tag *wherever the
card sits* without naming every zone one at a time. That is `@everywhere`: a
reserved scope word resolving to every card in any zone, composing with the owner
word and every measuring form (`count:gem@mine.everywhere` is one seat's gems in
play, in hand and in the bag at once). It lives in `predicate.entities_in_scope`
as one branch (`entity.each("card")`), is reserved in `validate.lua`'s
`RESERVED_SCOPES` so no zone or tag may claim the name, and is proved by
`tests/integration/conditions.lua`'s `everywhere` test.

**The gap was narrower than three games' notes claimed, and measuring it is what
showed so.** *Naming a zone by key already reaches a hand, a pile and a deck* —
`count:gem@mine.discard` counts a pile, `count:gem@vault` a deck, `count:gem@hand`
a hand, all today, because a zone scope goes through `zones.all_with_key` and
never touches `find_targets`. The board-only limit is **only** the bare tag and
the tag scope. So the two workarounds the plan recorded were not workarounds for
*this*:

- **The Crew's commander seat-walk is irreducibly per-seat.** "Whose hand holds
  the rocket 4" needs to know *which* seat, and `@everywhere` answers *how many*,
  not *whose* — `card:rocket_4@mine.hand` walked over the seats is still the
  right shape.
- **Puzzle Strike's gem pile did not need to be a grid for the scope.**
  `sum:value@mine.gem_pile` reads a `pile` just as well (proved:
  `sum:value@mine.discard` returns the pile's total). The grid is legitimate
  *display* — gems laid out so a player can see the pile's height — not a scope
  workaround, and it stays a grid for that reason.

So there is **no game migration to make**: the shipped games already found
sayable spellings, and `@everywhere` is the general answer for the one thing that
was genuinely unsayable — a tag counted across hidden zones without enumerating
them.

Six requests that were the same request wearing different clothes: the engine
should know the shape of its own data before it runs, instead of asking at every
use — and should be able to say what it knows. Most of the answer turned out to
be "it already does, or it is a different question".

---

## Gap 1 — What a zone's `type` decides — **refused, and reopened as [28](28-a-zone-by-its-parts.md)**

**The condition below has fired** (2026-08-25). Puzzle Strike's ongoing row wants a
combination no type offers — an unbounded face-up row of cards that are *in play* — and
taking `hand` for it cost four unplayable chips and nine rules that could not see them.
The survey stands; the decision is superseded. See [28](28-a-zone-by-its-parts.md).

*Urgency: none · Difficulty: high in the honest sense — the code is shallow, the
design is not · Usefulness: unproven*

**Decision (2026-08-13, at `85e51eb`): not doing this.** The survey below is the
whole of what `type` bundles, taken from every `zone_type` read in the engine at
that commit. It is kept because it is genuinely useful to have written down —
and because the answer to "should we split it" turned out to be no, for a reason
worth recording rather than rediscovering.

**This table will drift.** It is a snapshot, not a contract. Re-derive it with
`grep -rn "zone_type" game/` before trusting a cell.

### The matrix

| Trait | `deck` | `pile` | `hand` | `grid` | `options` |
|---|---|---|---|---|---|
| Layout | one stack | one stack | a row | addressed cells | a row |
| Facing | backs | faces | faces | faces | faces |
| Which cards can be acted on | top only | top only | all | all | all |
| Clickable | **never** | top only | all | all | only while open |
| Found by a tag search | **no** | yes | yes | yes | yes |
| Browsable (ctrl / long-press) | only if `face_up` | yes | yes | yes | yes |
| Addressable slots | no | no | no | **yes** | no |
| Capacity bounded | no | no | no | **yes** (by cells) | no |
| Private to its owner | no | no | **yes, if it has a seat** | no | no |
| Cards run `on_turn` | no | no | no | **yes** | no |
| Can be `sole_grid` (`place:`) | no | no | no | **yes, if not hidden** | no |
| Drawn on the board | always | always | always | always | **only while open** |
| Emptied when a choice is made | no | no | no | no | **yes** |
| A card dims when… | — | — | unplayable | — | — |
| Arrival animation | drop | drop | glide | slam | glide |
| Empty and unlabelled draws | nothing | nothing | nothing | **the cells** | nothing |
| Label chrome | back-stack + count | text at top | none | none | none |

`fan` (a style) and `page` (a tag) override the layout row; `face_up` /
`face_down` already override the facing row.

### What the matrix shows

- **`deck` and `pile` differ in one behavioural row — facing — and that row is
  already a tag.** Everything else between them is chrome or exclusion.
- **`deck`'s three exclusions have nothing to do with facing**: never clickable,
  never found by a tag search, not browsable. That is "a closed box", and it is
  *already incoherent*: a deck tagged `face_up` stays unclickable and
  unsearchable, so it looks like a pile and behaves like a box. **This is a real
  latent bug and does not need the refactor to fix** — see below.
- **`grid` is the one coherent bundle.** Slots, capacity, `sole_grid` and the
  empty-cell drawing all follow from *having addressed cells*. Only `on_turn`
  firing on grids alone is a rule wearing a layout's clothes.
- **Two rows are not about the type at all.** *Private to its owner* is `hand`
  **and has a seat** — a seatless hand is public, so the quality is ownership.
  And *dims when unplayable* is `hand` while everything else dims on `activate`,
  which is "what does clicking mean here", already half-answered by a tag.

### Why it is refused

*(This is the decision as taken, in the words it was taken in: there is no
elegant solution that does not come with its own baggage.)*

The obvious split — `type` keeps the layout row, everything else becomes a tag —
reads well in a table and badly in a game file. It trades one word every author
already knows for five or six they would have to learn and keep consistent, and
**the tagging system is not up for it**: tags are a flat unordered set with no
grouping and no defaults, so `stack` + `face_down` + `closed` + `top_only` is
four independent chances to write three of them. The alternative, half a dozen
enum fields per zone, is more honest about the structure and much more to write.

Neither is clearly better than four words that happen to bundle correctly for
every game anyone has written. **The bundles are not wrong; they are unexplained
— and explaining them is what this table is for.**

Revisit if a game genuinely wants a combination no current type offers. The one
that has come closest is a face-up deck, which is `pile` in every respect that
matters, so it is not evidence.

### Worth doing on its own, without the refactor

- **A face-up deck should be clickable and searchable.** The three exclusions
  belong to "closed", not to "face down", and today `face_up` only changes what
  is drawn. Small, and a bug rather than a design change.
- **`on_turn` on grids only** is undocumented and surprising; either widen it or
  say so in `AUTHORING.md`.

## Gaps 2 and 3 — lists everywhere, then fewer type guards — **closed into [17](17-conditions-as-expressions.md)**

Both were measured on 2026-08-16 and both came out much smaller than written.

**Gap 2, "anything tag-shaped is a list":** three fields are left, not six.
`applies`, `tags`, `zones` and `zone_empty` were already array-only, and
`patterns` had since been normalised at the door (`declaration.lua:57`) — which
*is* this gap's proposal, already done once and the model for the rest. What
remains is `pass_card` (the one with a duplicated coercion, `flow.lua:238` and
again in `validate.lua:1374`), `phases`, and `at` on a `setup.place`.

Two entries are decisions rather than tidy-ups and were left alone. A phase's
`zone` as a list means "the player acts in all of these", which is a *feature* —
and shipped as one for The Crew's open hand. And `pos` should stay as it is: a
shared zone writing `[[…]]` to match a per-seat one is worse to read for the
common case.

**Gap 3, "fewer `type(x)` guards":** the count grew 106 → 184 and *all* of the
growth is in the two files that must keep them — `declaration` and `validate`,
which read the document and are the only places malformed input arrives. That is
this gap's own goal happening by itself, so there is nothing left to do.

An hour's work with nothing downstream of it but 17, so it became 17's first
step. **Refused along the way:** validating which combinations of tags are
*legal*. Normalise the shape, leave the meaning alone — a rule about which tags
may coexist is a much larger conversation than a rule about brackets.

---

## Gap 4 — Every tag the engine knows, in one place — **shipped**

*`validate.lua`'s `ENGINE_TAGS`, eighteen words with what each attaches to and
what it does. `SCHEMA.json`'s four strings and AUTHORING's table are generated
from it, and a two-way test holds all three together.*

**Both halves shipped, and the check went further than proposed.** The document
half was the easy part. The check was to *suggest* on a near miss; it also
**refuses redefinition** — a style, a tag def or a computed tag named after a
reserved word is an error, because the engine reads the word off the entity and
would obey both meanings at once. That costs a game the ability to name a style
after an engine word, which was accepted deliberately rather than worked around.

One thing measurement changed: the near-miss check as first written flagged
`mage` as a typo for `page`. Short words collide by accident, so both the word
and the reserved one must be six letters or longer — which still catches
`activaet`, `stays_redy` and `discard_hnd`, the cases that actually fail
silently.

## Gap 5 — A tag is a boolean below the door, a list above it — **shipped**

*Urgency: low · Difficulty: small · Usefulness: readability, and it finishes
something already half done*

**Done.** Both remaining card readers take `tags_set`, and the array survives
only in `validate.lua` and `json.lua`, which meet the authored document. The
measurement below was right about the shape and wrong about the deliverable: the
validation error it proposed **already existed** (`validate.lua`, *its tags
disagree about where it goes*) — what was missing was any statement of what the
engine does *while* a game ignores it. `cards.home_zone` now answers **nothing**
when two tags name different zones, so the callers' own fallbacks decide. That
is what makes the map safe to read: it removes the file order the array
encoded without inventing a precedence to replace it, and an ambiguous home is
more honestly no home than whichever tag was typed first. The message is in
`tests/integration/validator.lua`'s `CASES` now, where every message belongs.

> *When parsing the tags, replace every single tag in memory with a boolean.
> It's drastically simpler to code against, so `tags = [a, b, c]` just becomes
> `tagsMap = { a=true, b=true, c=true }`. I just don't want this format in my
> API, because it's cumbersome and errorprone, but it's totally okay inside the
> running engine. Also throw any boolean values in there which are not yet
> marked as tags.*

**Measured 2026-08-16, and the first half is mostly shipped.** `tag_set()` in
`declaration.lua` already builds a `tags_set` map for cards (`:383`), zones
(`:421`), stats (`:441`), phases (`:457`) and every injected def — which is
exactly this proposal, at exactly the door this whole file argues for.

**A zone entity is already the finished version.** `zones.lua:89` builds the
entity with `tags = def.tags_set or {}`, so the array is gone by the time
anything plays: `z.tags.hidden`, `z.tags.activate`, `z.tags.no_peek` and
`z.tags.refill_when_empty` are all plain lookups on a boolean map. Roughly
fifteen reads across `render.lua`, `zones.lua`, `main.lua` and `flow.lua` are
already written the way the note wants.

**What is left is cards, and it is two readers.** A card def carries both the
array and the map, and only two places below the validator still walk the array:

| Site | What it does |
|---|---|
| `cards.home_zone` (`cards.lua:140`) | the **first** of a card's tags whose tag def names a zone |
| `declaration.lua:585` | whether *any* of a seat card's tags names a home zone |

The second is a plain existence test and converts to `tags_set` unchanged. **The
first cannot**, and that is the finding: it is order-dependent, and a map has no
order. Two tags both claiming a home zone give a card two homes today, and file
order silently picks one.

[Assumption: the honest fix is not to preserve the array for it but to make the
ambiguity an error — *two tags claim a home zone for this card* — at which point
order stops mattering and `tags_set` answers. That is a validation message and a
loop, which is smaller than keeping a second representation alive to encode a
precedence nobody wrote down. `validate.lua` and `json.lua` keep the array
regardless: they meet the authored document, where it genuinely is a list.]

### The second half does not survive measurement

*"Throw any boolean values in there which are not yet marked as tags"* — every
boolean actually written across the ten game files, counted:

```
22 × ends_round: true
 2 × cell_outline: false
 1 × title: false · 1 × color: false · 1 × border: false
```

Neither group can become a tag, for a different reason each:

- **`ends_round` is on a routing entry**, not on a def. A routing entry has no
  tag set and no identity — it is a step in a `next` list — so there is nothing
  for a tag to attach to.
- **The other four are `false`**, and they are style properties whose whole job
  is to *suppress* chrome ([11](11-styles-as-tags.md): `color: false` is what
  replaced `transparent_background`). **A tag set can say present; it can never
  say absent.** Turning them into tags would mean naming the negative — a
  `no_border` tag — which is the vocabulary 11 deliberately collapsed.

So the tail of the note is refused on evidence rather than on taste: there are
no stray booleans that want to be tags, because the format already put every
boolean somewhere a tag cannot reach.

---

## Gap 6 — A stat that says what kind of number it is

*From `todo.md`, alongside the Splendor cost note: "Possibly we can put the cost
into a stat by default and then just reference it? Maybe have stats that are
declared to be costs? Do we have a global stat registry where we can default
behaviour of them? E.g. `stats: { name: mana, type: cost }` or similar? This
needs some care on how we handle conflicts, where a stat could be both a cost
and also have a different meaning. For example in MTG, 'red mana' is usually a
cost, but some cards can also give you red mana, or do something else with it."*

**The registry the note asks whether we have: we do.** `stats` is a top-level
list in every game file and `declaration.G.stat_defs` is the map it becomes. A
stat already declares `label`, `icon`, `min`, `max`, `subject`, `on` (which
cards carry it, and where they start) and `tags`. So the question is not whether
there is a place to put a default — there is — but **whether "this number is a
price" is a fact about the number at all.**

### The evidence says it is not, and the note's own example is why

The note answers itself with MTG: red mana is a cost on most cards, a resource
on some, and the subject of an effect on others. `t_red` in Splendor is the
same — it is spent on a purchase, gained from the bank, and compared against a
noble's threshold. A `type: cost` on the stat's declaration would be true in one
of those three sentences and misleading in the other two, and the engine would
then have to decide what it *does* with the label. Two candidates, and neither
survives:

- **It changes behaviour** — a `cost` stat is deducted automatically somewhere.
  That is `play.cost` already, which is a map on the *moment*, not on the stat,
  and is right to be: the same number costs 2 on one card and 5 on another.
- **It changes presentation** — a `cost` stat is drawn in the price corner. Then
  the word is a style question wearing a schema's clothes, and it belongs to
  [07](07-presentation.md) gap 8, where a card face says which of its numbers it
  shows and where.

Which leaves a third reading that *is* worth something and is much smaller.

### What is actually missing: a default a stat can hand its cards

Splendor's five `cost_*` stats are declared with `on: ["development"]` and **no
`start`**, so they grant nothing, and every one of the ninety generated cards
carries all five in `card_stats` — three of them `0` on a typical card — because
the arithmetic needs the stat to exist before `stat_damage` can reach it
("an action skips a card that has none"). That is 450 numbers written down to
make 450 subtractions legal, and it is the same shape as the complaint
[07](07-presentation.md) gap 8 hits from the drawing side: a zero that is
structurally required and visually noise.

> **Checked, and the assumption was wrong.** The proposal here was `start: 0` on
> those five declarations, with the zeros deleted from the generator. The
> machinery does exist (`declaration.lua:671`), but the missing `start` is
> **deliberate**, and `tools/make_splendor.py` says so where it declares them:
> *"The ones with no `start` are the card's own to declare, and the validator
> holds the generator to it — a development card without a white cost is a bug
> in this file, not a card that costs nothing."* The 450 zeros are a checksum,
> not duplication: granting them a default would turn a card that forgot its
> price into a card that is free, silently. So the salvage is not this either,
> and what the zeros cost — a column of `0`s on the face — was answered in
> presentation instead, by [07](07-presentation.md) gap 8's `badge_zeros`.
>
> Which leaves gap 6 with nothing to build, and that is the finding: the whole
> note, including the part that looked like a real measurement underneath it,
> dissolves. A stat says its bounds, whose number it is, where they start, and
> what it looks like. It does not say what it is *for*.

### Refuse

- **A vocabulary of stat kinds.** `cost`, `resource`, `counter`, `score` — a
  closed set that is always missing somebody's, and every word in it is a
  behaviour the engine would then own. Invariant: the engine does not know one
  game's words, and "cost" is one game's word about one of its numbers, not a
  property of numbers.
- **Resolving the conflict the note names.** There is no conflict to resolve
  once the label is not there: red mana is a stat, and what a card *does* with
  it is written on the card.
