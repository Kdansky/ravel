# 11 — Styles are tags too

**Status:** **shipped.** Every field and tag in the table below now lives in
`styles`, for zones as well as cards ·
**Size:** medium-large, and it *deletes* more than it adds ·
**Supersedes:** `ratio` and `fit` as zone fields ([07](07-presentation.md)
gaps 4 and 5, both shipped and both now on the wrong side of this).

**What shipped first, and why `color`:** it had exactly one reader
(`render.lua:299`), which made the machinery provable before anything wide
depended on it. The payoff was immediate — 83 cards carrying a colour became 12
style entries and a tag each, and Lost Cities' 70 dropped to five.

The dynamic case is built and tested: a card tagged with a style that is also a
computed tag recolours the moment its stat crosses, with nothing in the drawing
code that knows what `wounded` means. Nothing per frame is paid by a game
without one — the parse lists which style words are computed tags, and that list
is empty in every shipped game.

> *A top-level list of styles, which can have specialised fields for rendering.
> These styles are also loaded in the tags set, which gets rid of `fit` as its
> own thing. This also allows dynamic styles, because tags can be dynamic.
> `"key": "chess_board", "tags": ["square", "black_and_white", "no_square_lines",
> "immutable"]` is the easiest solution. We're not in a statically typed language
> and we don't need to enforce unique collections for different lists of strings.*

---

## The engine already did this once, for behaviour

This is not a new mechanism, it is the second use of one that shipped in
`7b524de`. Top-level `tags` already defines what a tag *does*:

```json
"tags": { "item": { "zone": "inventory" }, "takeable": { "on_activate": [...] } }
```

`cards.behaviour(entity, field)` resolves it, and `DESIGN.md` records the rule:
where a card is decides what it can do. **`styles` is the same table for how a
thing looks**, resolved the same way, referenced from the same list of words.

That is the whole argument for the design, and it is a strong one: an author
learns one concept — *a word in `tags` means something, look it up* — instead of
one per field.

## What collapses into it

The payoff is not the new section, it is the six scattered fields and two ad-hoc
tags it absorbs. Everything below is presentation living somewhere bespoke today:

| Today | Becomes |
|---|---|
| `fit: "card"` / `"fill"` on a zone | a style word, and the default when nothing says otherwise |
| `ratio: 1` / `"grid"` on a zone | a style property — see the note at the end |
| `chequer: ["#f0d9b5", "#b58863"]` on a zone | a style, and `black_and_white` is a shipped one |
| `paint: {...}` on a zone | a style property |
| `invisible_slot_outlines` tag | already a tag; becomes a style, shorter: `no_square_lines` |
| `invisible_title_text` card tag | a style |
| `transparent_background` card tag | a style |
| `color: [r,g,b]` on a card | a style property — **and `false` on the same property replaced `transparent_background`** |

**One overlap turned out to be real.** A card's `color` and the tag
`transparent_background` were a field and a tag deciding the same thing: what is
behind the art. They collapsed into one property that takes a colour or `false`.
The other pairs that looked related are not: `fit` shapes a card inside a cell
while `ratio` shapes the zone, and `chequer` paints every cell while `paint`
names particular ones — different subjects, kept apart.

**The prerequisite turned out not to be one.** `entity_has` still does not answer
for zones, and did not need to: a zone has no stats, so no computed tag can be
true of one, so a zone's look is settled at load and a plain merge does it.

Two of those are already tags, which is the sign the idea is right: the engine
has been drifting toward it one ad-hoc word at a time, and this is the pass that
notices.

`asset` does **not** move. A picture is a *source*, not a style, and it already
has its own top-level table for the same reason this one is being added — see
[05](05-assets-and-repo.md). A style may say how a picture is drawn; it never
says which picture.

`pos` does **not** move either. Every zone is somewhere different, so a `pos` is
never shared, and a style whose properties are all unique to one user is a
detour. This is what separates this proposal from the "top-level layout section"
it started as: styles carry what is *shared*, `pos` is what is not.

## Resolution, and the one rule that needs deciding

A word in a zone's or card's `tags` may now mean three things, and this is
deliberately not a partition:

1. nothing the engine knows — free vocabulary, matched by targeting and counting
2. a behaviour, defined in top-level `tags`
3. a style, defined in top-level `styles`

**A word may be two and three at once, and should be allowed to.** `takeable`
can mean both "you may take this" and "draw it with a highlight", and forcing two
words for one idea is exactly the "unique collections" this is meant to avoid.
The validator notes it; it does not refuse it.

**Two styles setting the same property is the case that needs a rule.**
`["square", "wide"]` both claim the cell shape. The engine's existing stance
(`DESIGN.md`, *Tags Are Mixins*) is that an overlap is an authoring conflict the
validator reports rather than a precedence the engine invents, and that should
hold here: **no silent winner.** List order is a tempting tiebreak and it is
worse than it looks — `tags` is also a set for targeting, so nothing else in the
engine treats its order as meaningful, and making it meaningful *here only* is a
trap for the first author who sorts their tags alphabetically.

## The prize: a style that changes itself

Computed tags are derived from stats:

```json
"computed_tags": { "wounded": { "stat": "hp", "less_than": 3 } }
```

If `wounded` is also a style, a card renders differently the moment its `hp`
drops, with **no new machinery at all** — no render-time condition, no per-card
state, nothing in `render.lua` that knows what wounded means. Same for
`promoting` on a chess pawn that reaches the last rank, which already exists as
a computed tag and currently has nothing consuming it.

That is the strongest reason to do this rather than tidy the fields in place,
and it should be the acceptance test: **a card that changes colour when its
stats change, with no code written.**

## One list in the file, several tables in memory

**The written file keeps one flat list of words.** An author writes `"tags":
["square", "black_and_white", "immutable"]` and never says which kind each word
is — that is the entire point, and any design that makes them declare it has
lost the plot.

Inside, they are separated. `declaration.parse` is already the place this repo
pays for exactly this, and [06](06-schema-and-types.md) gap 3 says so in as many
words:

> *`declaration.lua` is the boundary. These should grow, not shrink — this is
> where the document becomes engine data, and it is the one place worth paying to
> normalise.*

So the parse splits one authored list into what each consumer needs: the tag set
for targeting and counting, the behaviour lookup, and a **flat resolved style
table** on the entity. `render` then reads `z.style.cells` as a bare table
lookup — no walk, no per-property resolution, and the hot path stays as fast as
`z.tags.hidden` is today.

That matters because of what `cards.lua:83` says about `def()`:

> *Deliberately not folded into `behaviour()`: that is a bare table lookup on the
> per-frame path for render, targeting, costs and tooltips, and it must stay one.*

### Which makes the dynamic case cheap too

Splitting at load also answers the only hard part. A style word that is a
*computed* tag cannot be resolved once, because it derives from stats that
change — but **the parse knows which words those are**, since `computed_tags` is
declared in the same file. So it can mark the handful of entities whose style
depends on one and leave every other entity's style frozen at load.

A game with no dynamic styles pays **nothing per frame**, which is every shipped
game today. A game with them re-resolves only the entities that actually carry
one. No cache invalidation, no stat versioning, and no measuring required to know
it is fast enough.

## Prerequisite: `entity_has` does not work for zones

`tags.entity_has` (`tags.lua:11`) reads definition tags only under
`if e.kind == "card"`, and computed tags for anything. Zones get neither — every
zone tag read in the engine today is a direct `z.tags.hidden` table lookup.

So styles on zones need `entity_has` to answer for a zone as it does for a card.
That is a small change and it must come first, because half the collapsing list
above is zone-side.

## Naming: they stay `tags`, not `traits`

Asked and settled. "Trait" is the better word for a *mixin* — Rust and Scala use
it for exactly the thing `DESIGN.md` calls "Tags Are Mixins" — but it is the
wrong word for the majority of what the list holds. `"tags": ["red", "beast"]`
answering `count:beast@board` is tagging in the plain sense: a label matched on.
Renaming would make the word accurate for `takeable` and wrong for `red`.

The codebase also settled the general question once already, in `validate.lua`:

> *How a pattern's vectors are walked. A closed set the engine defines, unlike
> card and zone tags, which are the game's own vocabulary — hence the different
> word for it in the JSON.*

**The game's open vocabulary is `tags`; a closed set the engine defines gets its
own word.** That is `class` for pattern walking, and it is `styles` here — which
is the same reason this proposal adds a section rather than more special words
inside `tags`.

The cost side is one-way too: the rename touches every game file, both
generators, four documents and any file written outside this repository, to
exchange one word for a synonym. Nothing reads better afterwards.

If the discomfort is that "tag" undersells what some of them now do, the fix is
the single reference table in [06](06-schema-and-types.md) gap 4 — one place
saying which words the engine knows and what each changes — not the identifier.

## Refuse

- **A style that changes rules.** It may not decide legality, targeting or cost.
  Behaviour is what top-level `tags` is for, and the moment a rendering choice can
  make a card unplayable, every rules bug becomes a presentation bug too.
- **A style that moves a thing between containers.** It may say where a thing
  sits *inside* the box it is in — that is what `fit` does for a cell and `fan`
  does for a run of cards — but never *which* box it is in. That is the rules'
  answer, and position by cascade is CSS, and CSS is a language.

  *Sharpened by `fan`, which looked at first like a breach of this.* It is not:
  a fanned card is in the same zone it was in, drawn where that zone chose to
  draw it. The test that keeps the line honest is whether a *rule* could read
  the result — nothing does, because the fan is computed at draw time from
  `zone.cards`, which the rules wrote.
- **Cascading, inheritance, selectors.** A style is a flat map of properties.
  The moment one style names another the whole thing becomes a resolution order
  nobody can predict from reading the file.
- **A closed tag vocabulary.** Unchanged from [06](06-schema-and-types.md) gap 4:
  an unknown word is free vocabulary, not an error. A near-miss of a *known*
  style should suggest, exactly as a near-miss of a known tag should.
- **Making the author say which kind a word is.** No `"styles": [...]` list
  beside `"tags": [...]` on the entity, no `style:` prefix on the word. One list
  in the file; the split happens at load, where it costs the author nothing.

## Migration and build order

1. **`entity_has` answers for zones.** No behaviour change, one test.
2. **The `styles` section, and resolution with the flat per-entity cache.**
   Nothing consumes it yet; the test is that a style resolves.
3. **One property through the whole path** — `no_square_lines`, because it is
   already a tag and so proves the mechanism without a migration.
4. **Collapse the rest**, one field per commit, each with the game files it
   touches. `fit` last: it has the most users and the least interesting
   semantics.
5. **The dynamic test** — a card that recolours when a stat crosses a threshold,
   written entirely in JSON.

**Both generators regenerate**, so `make_chess.py` and `make_lost_cities.py`
change rather than their output.

## The debt this creates, stated plainly

`ratio` and `invisible_slot_outlines` shipped just before this was designed.

- `invisible_slot_outlines` is **already a tag**, so it is on the right side of
  the line and needs only a rename and a move into `styles`.
- `ratio` is a zone field and is **on the wrong side**. It stays until step 4,
  because removing it now would leave the chessboard a rhombus again for no gain,
  and because a field with one user in one generated file is the cheapest
  possible migration. When it goes, the arbitrary number goes with it into a
  named style — which is what makes it acceptable, and is the same answer
  `assets` gave: options belong in a named, shared, reusable entry, and the thing
  using them just says a word.
