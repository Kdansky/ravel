# 06 — Saying what things are

**Status:** not started · **Size:** medium, and mostly mechanical once the first
decision is made.

Four requests that are the same request wearing different clothes: the engine
should know the shape of its own data before it runs, instead of asking at every
use — and should be able to say what it knows.

---

## Gap 1 — Zone qualities belong in tags, not in `type`

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
[01](01-boardgames.md)) is a fifth layout, or a tag on `stack`.

**Refuse:** letting a tag change the layout algorithm. Tags decide rules; `type`
decides geometry. The moment a tag moves cards around, every renderer question
becomes a search through a tag set.

---

## Gap 2 — Anything tag-shaped is a list, always

*Urgency: medium · Difficulty: medium · Usefulness: medium*

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

## Gap 4 — Every tag the engine knows, in one place

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
