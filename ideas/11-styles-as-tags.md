# 11 — Styles are tags too

**Shipped.** A `styles` section for cards and zones alike, claimed by tagging
one. It deleted more than it added.

## The design

`styles` is the second use of a mechanism that already existed. Top-level `tags`
says what a tag *does*; `styles` is the same table for how a thing *looks*,
resolved the same way, referenced from the same list of words. An author learns
one concept — *a word in `tags` means something, look it up* — instead of one
per field.

**The written file keeps one flat list of words.** The author never says which
kind each word is; `declaration.parse` splits one authored list into the tag set
for targeting, the behaviour lookup, and a flat resolved style table on the
entity. `render` then reads `z.style.cells` as a bare table lookup, so the
per-frame path stays as fast as `z.tags.hidden` was.

**What collapsed into it:** `color` on a card, `fit`, `ratio`, `chequer` and
`paint` on a zone, and the tags `invisible_slot_outlines`,
`invisible_title_text` and `transparent_background`. Two of those were already
tags, which was the sign the idea was right — the engine had been drifting
toward it one ad-hoc word at a time.

`color` and `transparent_background` were a field and a tag deciding the same
thing, and became one property taking a colour or `false`. The other pairs that
looked related were not: `fit` shapes a card inside a cell while `ratio` shapes
the zone, and `chequer` paints every cell while `paint` names particular ones.

`asset` did **not** move — a picture is a source, not a style, and a style may
say how a picture is drawn but never which one. `pos` did not either: every zone
is somewhere different, so a `pos` is never shared, and styles carry what *is*.

## The prize, and it worked

A card tagged with a style that is also a computed tag recolours the moment its
stat crosses, with nothing in the drawing code that knows what `wounded` means.
That was the acceptance test — *a card that changes colour when its stats
change, with no code written* — and it is why this was worth doing rather than
tidying the fields in place.

It is cheap because the parse knows which style words are computed tags, so it
marks the few entities whose style depends on one and freezes every other at
load. A game without one pays nothing per frame, which is every shipped game.

**A prerequisite turned out not to be one.** `entity_has` still does not answer
for zones and did not need to: a zone has no stats, so no computed tag can be
true of one, so a zone's look is settled at load and a plain merge does it.

## Two rules that needed deciding

**A word may be a behaviour and a style at once**, and is allowed to be.
`takeable` can mean both "you may take this" and "draw it with a highlight", and
forcing two words for one idea is the thing this avoids.

**Two styles setting the same property is an authoring conflict**, reported, not
a precedence the engine invents. List order is a tempting tiebreak and worse
than it looks: `tags` is a set for targeting, nothing else treats its order as
meaningful, and making it meaningful here only is a trap for the first author
who sorts their tags alphabetically.

## They stayed `tags`, not `traits`

"Trait" is the better word for a mixin, and the wrong word for most of what the
list holds: `"tags": ["red", "beast"]` answering `count:beast@board` is tagging
in the plain sense. Renaming would make the word accurate for `takeable` and
wrong for `red` — and the codebase had already settled the general question:
**the game's open vocabulary is `tags`; a closed set the engine defines gets its
own word.** That is `class` for pattern walking, and it is `styles` here.

## Refused

- **A style that changes rules.** The moment a rendering choice can make a card
  unplayable, every rules bug becomes a presentation bug too.
- **A style that moves a thing between containers.** It may say where a thing
  sits *inside* its box — `fit` in a cell, `fan` along a run — never which box.
  `fan` looked like a breach and is not: a fanned card is in the zone it was in,
  and the test that keeps the line honest is whether a *rule* could read the
  result. None can; the fan is computed at draw time from what the rules wrote.
- **Cascading, inheritance, selectors.** A style is a flat map. The moment one
  style names another it is a resolution order nobody can predict by reading.
- **A closed tag vocabulary.** An unknown word is free vocabulary, not an error.
- **Making the author say which kind a word is.** One list in the file; the split
  happens at load, where it costs the author nothing.
