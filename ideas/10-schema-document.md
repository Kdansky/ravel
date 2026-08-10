# 10 — A game file that describes itself

**Status:** not started · **Size:** medium, and most of it is transcription ·
**Value:** mostly in what writing it *finds*.

> *I want a file that lists every possible value we support for the game.json
> structure. Basically a schema. It should also be a JSON, and instead of the
> values everything is a string explaining what the value would be. e.g.
> `"tags": ["a list of tags"]` and `"distance": "number which tells the distance
> in squares"`. This is for me to double check that our formats are good.*

---

## What it is, and why not JSON Schema

A **shape mirror**: a real `.json` file laid out exactly like a game file, with
every leaf value replaced by a sentence saying what belongs there.

```json
{
  "title": "the game's name, shown in the window title",
  "seed": "number — fixes the RNG so a run replays identically; omit for random",
  "zones": [
    {
      "key": "unique name, referenced by cards, actions and scopes",
      "type": "one of: deck (face-down stack), pile (face-up stack), hand (row), grid (board with slots)",
      "pos": "[x1, y1, x2, y2] as fractions of the window — or one such list per seat when per_seat is true",
      "grid": "[cols, rows] — grid zones only",
      "tags": ["a list of words; the engine knows shuffle, face_up, hidden, activate, … (see the tags section)"]
    }
  ]
}
```

**JSON Schema would be the wrong tool**, and the reason is the stated purpose.
`{"type": "object", "properties": {"pos": {"oneOf": [...]}}}` describes the same
thing while hiding the one property being reviewed: what a game file *looks
like*. The request is to check that the formats are good, and judging a format
means seeing it the way an author meets it.

The engine also already has something better than a schema for the checking job
— `validate.lua` does cross-references, conflicts, and did-you-mean suggestions
that no schema language expresses. This file is for **reading**, not validating,
and keeping those two jobs apart is what keeps it honest.

## The real value: it is a wart detector

Every field gets exactly one sentence. So the fields whose sentence turns long,
or grows an "or", or needs a "but only when", are by construction the awkward
parts of the format — and that measurement is the deliverable. `README.md`
defers a syntax pass with:

> *Write more games first; the warts that actually hurt will be the ones that
> keep needing explanation.*

This document is the instrument for that. Three suspects are already named there
and all three will show up as bad sentences:

| Suspect | The sentence it will force |
|---|---|
| `pos` | "a rect — or a list of rects, one per seat, when `per_seat` is true" |
| `needs` / `requires` / `accepts` | three entries whose sentences differ by *when they are asked*, not by shape |
| `{"subject": {"at_most": n}}` | a map whose key is a subject and whose value is a comparison, which is an expression wearing a map's clothes |

**Acceptance criterion: the file plus a short list of what writing it exposed.**
A schema document with no findings attached means the pass was transcription and
the review did not happen.

## The parts that do not mirror

Three things in a game file are not shapes, and pretending they are would make
the document a lie.

**Actions are a vocabulary** — 29 verbs in `actions.lua`'s `SPEC`, each an
`op:param:param` string. `"on_play": ["an action string"]` is useless. Give them
their own block, verb → what its parameters mean, which is a list rather than a
shape and is the one deliberate exception to the mirror:

```json
"_actions": {
  "lose_stat": "lose_stat:<stat>[@<scope>]:<amount> — subtract from a stat, clamped at its minimum",
  "move_to":   "move_to:target[:<on_occupied>] — move the acting card to the chosen target"
}
```

**Conditions are one vocabulary used in six places** (`needs`, `accepts`,
`requires`, routing entries, end conditions, computed tags). Describe the
vocabulary once, in its own block, and have each of the six point at it. If that
turns out to be awkward to write, *that is a finding* — it means the six are not
as unified as `DESIGN.md` claims.

**Coordinate pairs** are the schema's one standing exception to "no nested
arrays" (`per_seat` `pos`, and pattern `vectors`). The document should say so
where they appear, because a reader who does not know that reads them as
inconsistency.

## Drift, and the test that prevents it

**A hand-written schema document is a lie within two commits**, and a confidently
wrong one is worse than none: it will describe a field that no longer exists and
be believed, because it looks machine-made.

The engine already holds the authoritative lists — `declaration.KNOWN_SECTIONS`,
and `validate.lua`'s `CARD_FIELDS`, `ZONE_FIELDS`, `PHASE_FIELDS`, `STAT_FIELDS`,
`TARGET_FIELDS`, `TAG_FIELDS`, `EFFECT_FIELDS`, `ASSET_FIELDS`, `ROUTE_FIELDS`,
`END_FIELDS`, `COMPUTED_FIELDS`. So:

> **A test loads the schema file and asserts the key sets match, both ways.**
> A field the validator knows and the document omits is a gap; a field the
> document describes and the validator rejects is a lie. Neither may pass.

This costs almost nothing — the tables exist for `check_fields` already — with
one prerequisite: they are `local` in `validate.lua` and would need exporting.
Export them there rather than duplicating them anywhere, and the document
becomes self-maintaining in the only way that matters, which is that it cannot
silently rot.

Two-way matching also picks up the *reverse* problem, which is the one nobody
looks for: a field the validator accepts that nothing documents. There are
almost certainly a few.

## Where it lives

**`SCHEMA.json` at the repository root**, beside `DESIGN.md`, `AUTHORING.md` and
`ARCHITECTURE.md`. It is a reference document and belongs with the others.

Not in `game/games/` — nothing sweeps that directory today (every game is named
explicitly in `menu.json`), so it would work, but a file there that is not a game
is an invitation for the first person who writes a sweep.

Being real JSON means **no comments**, which is a useful constraint rather than
an annoyance: every explanation is forced into a value, where the test can see
it, instead of into a comment where it cannot.

## Refuse

- **Generating `validate.lua` from it.** The validator is richer than a schema
  and the direction of truth runs the other way.
- **A second validator that reads it.** One validator, one set of error
  messages. A schema-driven check would report different words for the same
  mistake.
- **Describing the *engine's* internal shapes** — entities, `place` rects, the
  network wire format. The subject is the authored file, and `ARCHITECTURE.md`
  owns the rest.
- **Letting it become the manual.** `AUTHORING.md` explains *how to build a
  game*; this file says *what may appear where*. The moment it grows worked
  examples they will disagree with the ones next door.

## Build order

1. Export `validate.lua`'s field tables (mechanical, no behaviour change).
2. Write `SCHEMA.json` top-level-section by top-level-section, in the order
   `KNOWN_SECTIONS` lists them: `title`, `seed`, `placeholder_art`, `stats`,
   `computed_tags`, `templates`, `cards`, `zones`, `phases`, `end_conditions`,
   `setup`, `tags`, `effects`, `patterns`, `assets`.
3. The two-way key test.
4. **Write up what it found**, and fold that into `README.md`'s deferred syntax
   pass. This step is the point of the other three.
