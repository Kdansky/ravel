# 10 — A game file that describes itself

**Shipped** — `SCHEMA.json` at the repository root, held to the engine by
`tests/integration/schema.lua` in both directions.

## The decision

A **shape mirror**: a real `.json` file laid out exactly like a game file, with
every leaf value replaced by a sentence saying what belongs there.

**JSON Schema would have been the wrong tool**, and the purpose is the reason.
`{"type": "object", "properties": {…}}` describes the same thing while hiding
the one property under review: what a game file *looks like*. Judging a format
means seeing it the way an author meets it. `validate.lua` already does the
checking job better than any schema language — cross-references, conflicts,
did-you-mean — so this file is for **reading**, and keeping the two jobs apart
is what keeps it honest.

Being real JSON means no comments, which is the useful constraint: every
explanation is forced into a value, where the test can see it.

**One sentence per field makes it a wart detector.** A field whose sentence
grows an "or", or a "but only when", is by construction an awkward part of the
format, and that measurement was the deliverable.

## The blind spot, found by falling into it

**Both directions compare field *names*, and a word can sit outside both while
still reading as an offer.** `exhausts` did, for three passes: SCHEMA described
it inside an `activate` block, which the two-way test skips as nested;
`validate.lua` type-checked it, so it looked live; and AUTHORING recommended it.
Nothing in `game/` had read it since being-spent became a cost. A card written
from the manual tired for the round anyway — and the validator had been saying
*has a field 'exhausts' the engine doesn't read* the whole time, to nobody,
because a manual fragment is not a whole game and was never run.

The fix was not more schema matching but a **retired-vocabulary guard** in
`tests/integration/docs.lua`: every dropped word listed with what to write
instead, and no shipped game, schema, generator or manual example may carry it
as a quoted token. Prose keeps its history. `stays_ready` was caught the same
way — deleted from the engine, still emitted by a generator the suite never ran.

## What the pass found

Ten passes, one sentence per field. Two were bugs.

| # | Finding | Verdict |
|---|---|---|
| 1 | **`templates` and `cards` were two names for one section, and a file with both lost one.** The parser read `templates or cards`, so every card under `cards` was dropped — and `check.lua` called the file clean | **Removed.** The section is `cards`. No alias, so the collision cannot recur |
| 2 | **`patterns` never checked its field names**, so `"vector": [[1,0]]` loaded as a pattern with no vectors and a piece that mysteriously could not move | Fixed in the pass |
| 3–6 | **The format had grown synonyms.** `needs`/`requires`/`accepts` were one shape under three names; a routing entry's `stat` field took any subject; one condition had three spellings and the site decided which; `ROUTE_FIELDS` and `END_FIELDS` were the same table | All answered by [17](17-conditions-as-expressions.md), which deleted the struct spellings outright |
| 7 | **`pos` changes shape according to a different field** — a rect, or one per seat | Still the clearest instance, and still there |
| 8 | An unstated `activate_` convention — a prefix meaning "the same thing, for the board ability", learned by noticing | Not a wart but undocumented. [12](12-card-moments.md) removed the prefix entirely |
| 9 | Derived fields shared the authored tables, so the validator could not say that hand-writing `tags_set` is meaningless | An explicit `DERIVED` list, now also what the schema test skips |

**The pattern under 1 and 3–6 is one thing: synonyms.** None expensive alone;
together they were why the format needed explaining. What it did *not* find is
worth saying too — no missing capability, no shape that resisted one sentence,
no section whose fields disagreed with the validator. The format was consistent,
just wordier than it needed to be.

## Refused

- **Generating `validate.lua` from it** — the validator is richer, and truth
  runs the other way.
- **A second validator that reads it** — one set of error messages, or the same
  mistake gets two names.
- **Describing the engine's internal shapes** — the subject is the authored
  file; ARCHITECTURE owns the rest.
- **Letting it become the manual** — the moment it grows worked examples they
  disagree with the ones next door.
