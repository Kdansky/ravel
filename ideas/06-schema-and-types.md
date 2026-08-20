# 06 — Saying what things are

**Status:** not started · **Size:** medium, and mostly mechanical once the first
decision is made.

Four requests that are the same request wearing different clothes: the engine
should know the shape of its own data before it runs, instead of asking at every
use — and should be able to say what it knows.

---

## Gap 1 — What a zone's `type` decides — **surveyed, and refused**

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

### The original write-up

*Urgency: medium (half-done already) · Difficulty: medium · Usefulness: high*

`type` is four words — `deck`, `pile`, `hand`, `grid` — and each is a bundle of
unrelated decisions:

| | facing | reach | layout | slots | order |
|---|---|---|---|---|---|
| `deck` | backs | top only | one stack | no | fixed |
| `pile` | faces | top only | one stack | no | fixed |
| `hand` | faces | all | a row | no | none |
| `grid` | faces | all | cells | yes | by slot |

`deck` and `pile` differ in **one column**, and it is the one already
overridable by the `face_up` / `face_down` tags. Meanwhile the qualities that
actually vary between games have had to be added as tags anyway, because no
`type` predicted them: `shuffle`, `refill_when_empty`, `no_peek`, `hidden`,
`page`, and now `activate`.

**`activate` is the proof.** It shipped as a tag because the question it answers
— may cards here use their abilities? — cuts straight across `type`: a board and
a Lost Cities discard both say yes, a hand and an MTG graveyard both say no, and
neither pair shares a type. Every other column above will eventually do the same.

**Proposal**, matching the four styles already sketched — `stack`, `hand`,
`tiled`, `free`:

```json
{ "type": "stack", "tags": ["face_down", "shuffle"] }        the deck
{ "type": "stack", "tags": ["activate"] }                    a Lost Cities discard
{ "type": "stack", "tags": [] }                              an MTG graveyard
{ "type": "tiled", "grid": [5, 5], "tags": ["activate"] }    a board
{ "type": "free",  "tags": ["activate"] }                    an MTG battlefield
```

`type` keeps only what genuinely changes the *layout algorithm* — one stack, a
row, addressed cells, free placement — and every rule becomes a tag.

**What it costs.** Every zone in nine game files, plus the generator, plus
`zone_type ==` comparisons in `render.lua`, `zones.lua`, `targeting.lua`,
`tags.lua`, `main.lua` and `flow.lua`. It is wide but shallow, and it is much
cheaper before more games exist than after.

**What is genuinely new:** `free` does not exist — `grid` is the only positional
zone and it is slotted. Klondike's offset stack (gap 3 of
[01](01-boardgames.md)) shipped as neither a fifth layout nor a tag on `stack`,
but as a style property — see below.

**~~Refuse:~~ letting a tag change the layout algorithm** — *withdrawn, and the
`fan` property is what withdrew it.* The refusal was right about the danger and
wrong about the mechanism, and its own stated reason is what expired: "every
renderer question becomes a **search through a tag set**". Styles removed the
search. A zone's tags are resolved into one flat `style` map at load
(`declaration.lua`, `merge_styles`), so `z.style.fan` is a single table lookup —
exactly what `z.zone_type` costs, and asked in exactly the same place.

What survives is the *distinction*, sharpened by having to state it:

> **`type` says what kind of container a zone is. A style says how it is
> drawn.** A fan is drawing. The cards are one ordered list in one zone either
> way — a pile is a pile whether or not you spread it out — and the fan only
> decides where inside the zone each card sits.

**`fit` was already the precedent** and had been for as long as styles existed:
`fit: "fill"` versus `fit: "card"` decides where inside a *cell* a card lands.
The fan says the same thing about a *run* of cards instead of one cell. If
placing cards were genuinely `type`'s alone, `fit` was the violation and nobody
noticed, because a flat resolved map is not the thing the refusal was guarding
against.

**The real line is drawn where the two would contradict each other**, and that
is enforced rather than trusted: a `grid` wearing a fanning style is a
validation error. A grid places by slot and a fan by order, both answer *where
does this card go*, and a renderer taking whichever branch it reached first is
precisely the unpredictability the refusal was written to prevent. One error
message keeps the guarantee that the whole refusal was buying.

---

## Gap 2 — Anything tag-shaped is a list, always

*Urgency: medium · Difficulty: medium · Usefulness: medium*

> **Measured 2026-08-16, and it is much smaller than what follows.** Three fields
> are left, not six, and one of them the write-up itself argues against changing.
> `applies`, `tags`, `zones` and `zone_empty` were already array-only, and
> **`patterns` has since been normalised at the door** (`declaration.lua:57`) —
> which is this gap's own proposal, already done once and worth copying.
>
> | field | read at | note |
> |---|---|---|
> | `pass_card` | `flow.lua:238`, and the identical coercion again in `validate.lua:1374` | the only duplicated one |
> | `phases` | `flow.lua:102-103` | one reader |
> | `at` (setup.place) | `validate.lua:1471` | string or list, and not in the table below because it did not exist when this was written |
> | `pos` | `zones.lua:153` and its twin in validate | changing it makes shared zones write `[[…]]`, which the section below already calls the likely mistake |
>
> So this is an hour, not a track. **It is worth doing as
> [17](17-conditions-as-expressions.md)'s first step** — that is the only thing
> that needs the normalising door for its own sake — and not as an item ahead of
> it.

Several fields accept "a key, or a list of keys", and the engine re-derives
which it got at every use:

| field | forms today |
|---|---|
| `pass_card` | key or array |
| `phases` | key or array |
| `applies`, `tags`, `zones`, `zone_empty` | array only |
| `zone` (phase) | key only |
| `pos` | one rect, or one rect *per seat* |

The request is to make every one of these an array, so a reader never asks. The
right place to enforce it is **`declaration.parse`**, not the call sites: coerce
once at load, and everything downstream indexes a list. That is already where
`tags_set` is built and where the injected cards are stamped, so it is the
established home for "normalise the document".

Two carry real consequences and want deciding rather than sweeping:

- **`zone` on a phase.** A list would mean "the player acts in all of these",
  which the engine wanted three separate times (see `DONE.md` on `clicks`). It
  is the one entry here that is a feature, not a tidy-up.
- **`pos`.** A `per_seat` zone takes one rect per seat, a shared zone takes one
  rect. Always-a-list means shared zones write `[[…]]`, which is worse to read
  for the common case. This is the entry most likely to be a mistake.

**Refuse, for now, the validation.** The request explicitly defers "which
combinations are legal". Good — normalise the *shape* first and leave the
*meaning* alone, because a rule about which tags may coexist is a much larger
conversation than a rule about brackets.

---

## Gap 3 — Fewer `type(x)` guards, because the type is known

*Urgency: low · Difficulty: medium · Usefulness: medium (high for readability)*

> **Measured 2026-08-16: the count has grown from 106 to 184, and that is the
> gap working rather than rotting.** All of the growth is in the two files this
> section says must keep every guard — `validate.lua` 52 → 90 and
> `declaration.lua` 9 → 40 — and declaration growing is the stated goal, *move
> them to the door*, happening on its own as the format gained fields.
>
> The "~22 downstream" figure counted every `type(` in seven files, and most of
> them are not re-asking a known type at all: `predicate` (8) parses subject
> strings out of peer-suppliable content and says at `predicate.lua:75` why it
> must, `cards.lua:630` accepts an entity *or* a key on purpose, and the rest are
> deep copy, reflection and string guards on content. **Six would actually
> disappear if gap 2 landed** — `flow.lua:102-103`, `flow.lua:238`,
> `validate.lua:1374`, `zones.lua:153` and its validate twin, `cards.lua:574`.
>
> There is no cleanup to do here on its own. What survives is the acceptance
> criterion at the end of this section, which still holds.
>
> **The shape the surviving guards should take** (from `todo.md`, 2026-08-16):
> where a branch on `type(x)` has to stay, a module-local table reads better than
> a chain — `TABLE[type(v)](v, ...)` rather than three `elseif`s.
> [Assumption: this is a readability rule for the guards that *remain* rather
> than a second cleanup pass, and it only pays where the branches are a real set.
> `json.lua`'s encoder and `validate.lua`'s field checks are the two places with
> enough arms to be worth a table; a lone `if type(x) == "string"` guarding one
> coercion is worse as a table, not better, because the dispatch costs a name and
> a lookup to replace one word.]

There are 106 `type(` calls in `game/`:

```
validate.lua 52 · net.lua 18 · declaration.lua 9 · predicate.lua 8
flow.lua 5 · json.lua 4 · cards.lua 4 · art.lua 2 · zones/targeting/entity/actions 1 each
```

They are not all the same, and cutting them all would be a mistake:

- **`validate.lua` (52) and `json.lua` (4) must keep every one.** Their entire
  job is meeting untrusted, possibly malformed content and saying what is wrong
  with it. A validator that assumes its input is well-formed validates nothing.
- **`net.lua` (18) must keep most.** It parses data that arrived from another
  machine, which `DESIGN.md` is explicit about trusting only so far.
- **`declaration.lua` (9) is the boundary.** These should *grow*, not shrink —
  this is where the document becomes engine data, and it is the one place worth
  paying to normalise.
- **The remaining ~22, in `predicate`, `flow`, `cards`, `zones`, `targeting`,
  `actions` and `art`, are the target.** Every one of them re-asks a question
  `declaration` could have answered once at load.

So the honest shape of this task is not "remove type checks" but **"move them
all to the door"**: normalise in `declaration.parse`, then delete the
downstream guards, which is only safe *after* gap 2 lands. Ordering matters —
deleting a guard before the normaliser exists converts a warning into a crash,
and `predicate.lua` says out loud why it fails closed today:

> Everything below reads attacker-suppliable content … and must never let a
> malformed value reach a raw Lua comparison or arithmetic op — that throws an
> uncaught error and kills the process.

That comment is the acceptance criterion. The guards may go once the same
promise is kept somewhere earlier, and not before.

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

### The original write-up

*Urgency: medium (it is the most-asked authoring question) · Difficulty: low for
the document, medium for the check · Usefulness: high*

**A tag is free vocabulary until it isn't.** Most tags are the author's own
words, matched by targeting and counting, and that is the design. But a growing
number of them mean something *to the engine*, and those are scattered across
three documents and no code:

| Where they are documented now | Which |
|---|---|
| AUTHORING's card-field table | `token`, `immutable`, `invisible_title_text`, `transparent_background` |
| A paragraph under Zones | `shuffle`, `refill_when_empty`, `face_up`, `face_down`, `no_peek`, `hidden`, `activate`, `optional` |
| Hardcoded conventions | `player` |
| Nowhere as a list | whatever a reader of `render.lua` finds next |

**Two things are wanted here and they should not be confused.**

**The document.** One reference table: every engine-known tag, what it attaches
to (card, zone, or either), and what it changes. This is the todo-list item as
written, it is a couple of hours, and it needs no engine change. Grep for
`entity_has`, `tags.` and the zone tag reads to build it; the answer is a
half-dozen more than the lists above.

**The check, which is the interesting half.** A tag the engine *thought* it
knew, misspelled, is silently inert today — `"tags": ["activaet"]` gives a board
whose cards can never be used, with no error anywhere. The fix is not to reject
unknown tags (free vocabulary is the point) but to **warn on near-misses**:
`validate.lua` already has `suggest()`, and an unknown tag within edit distance
one of a known one is almost certainly the known one misspelled. That turns a
silent dead board into a line of output.

**Do the document first, because the check needs it.** The table *is* the
registry the check reads — put it in the engine as a table with the description
beside each entry, generate nothing, and let the two drift only as far as one
edit.

**Refuse:** a closed tag vocabulary. The moment unknown tags are an error, every
game file has to declare its own words before using them, and the thing that
makes targeting expressive dies to catch a typo that a suggestion catches
better.

---

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
