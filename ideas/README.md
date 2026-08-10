# Ravel — Idea Workstreams

`IDEAS.md` is the raw list. These files are the worked-through versions: what
each idea actually requires, where it lands in the code, what order to build it
in, and what to refuse to build.

**Start with [DONE.md](DONE.md).** It records everything already built — what it
does, which files it lives in, the decisions that are load-bearing and the traps
that cost real time — so that finding out what exists does not mean reading the
whole engine. The design documents for shipped ideas have been folded into it
and deleted; their content is all there, minus the parts that were speculation
about how it might go.

| # | Idea | Size | State |
|---|---|---|---|
| [DONE](DONE.md) | **Everything already built** | — | stats on cards · seats and hot-seat · the engine's own RNG · procedural art · Lost Cities · networked play · stacks and mixins · chess · named and remote assets · the inspector |
| [01](01-boardgames.md) | Any board game as JSON | large, staged | **Lost Cities and chess shipped.** Left: checkers' jumped square, Klondike, triggers |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | medium | not started — unblocked, and smaller than written |
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | small | **named assets shipped.** Left: the placeholder fallback, and art out of git |
| [06](06-schema-and-types.md) | Saying what things are | medium | not started — zone qualities as tags, lists everywhere, guards at the door, the tag registry |
| [07](07-presentation.md) | Presentation and its gestures | medium-large | not started — the text/contrast pass, clicking the deck, board chrome, zone ratios, multi-ability choice |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | medium | **chess plays, castling included.** `patterns` (relative and absolute), capture, piece ownership, patterns as scopes. Left: the scope anchor word, check/checkmate, promotion, en passant |
| [09](09-composition.md) | One game out of several files | small + one trap | not started — `include`, and a base file of shared patterns |
| [10](10-schema-document.md) | A game file that describes itself | medium | not started — `SCHEMA.json`, a shape mirror with a sentence per field, kept honest by a two-way test |
| [11](11-styles-as-tags.md) | Styles are tags too | medium-large | not started — a `styles` section referenced by tag, absorbing `fit`, `ratio`, `checker`, `paint` and two card tags. Dynamic styles fall out of computed tags for free |

---

## Where things stand

The engine can express a two-player Knizia game, play it between two computers
over the internet with no server, and hand the game file itself to somebody who
has never seen it. It can express a piece that moves across a board — chess
plays, in six pattern entries and no engine knowledge of what a bishop is. Its
pictures can live on somebody else's server, which is what makes a game file
shareable without shipping binaries with it. What it cannot yet promise is that
your opponent is honest.

## What to do next

Ordered by urgency × difficulty × what it unblocks — cheap things that let other
things happen come first.

| # | Item | Urgency | Difficulty | Why here |
|---|---|---|---|---|
| 1 | [05](05-assets-and-repo.md) gap 1 — **placeholder when a picture is missing** | high | low | one branch in `cards.asset_image`; the *only* thing blocking item 2. Note it is now two changes, not one — see the gap |
| 2 | [05](05-assets-and-repo.md) gap 3 — **art out of git, JSON stays** | high | low | wanted now. The JSON is already tracked; the art is what has to go. Decided: small art that is *part of the rules* stays, so chess keeps its 12 sprites, and history is not rewritten |
| 3 | [07](07-presentation.md) gap 1 — **the text, contrast and tooltip pass** | high | medium-high | the thing players actually hit. Mostly judgement, not code |
| 4 | **Hidden hands, a nameplate, a pass-the-device overlay** | high | medium | the last of multiplayer stage A. [07](07-presentation.md) gap 2 needs the same "can this player see this card" predicate, so build it once |
| ~~5~~ | ~~[07](07-presentation.md) gap 5 — **zones that keep their shape**~~ | — | — | **shipped** — `"ratio"` on the zone, a number or `"grid"`. A field and not a tag: the gap says why, and the reasoning applies to the next thing that looks tag-shaped |
| ~~6~~ | ~~[07](07-presentation.md) gap 4 — **a zone tag for board chrome**~~ | — | — | **shipped** — `invisible_slot_outlines`, which *is* rightly a tag. Eligibility still draws, or the board is unplayable |
| 7 | [06](06-schema-and-types.md) gap 4 — **every engine-known tag in one table** | medium | low | the most-asked authoring question, and the table is what a typo check would later read |
| 7½ | [10](10-schema-document.md) — **`SCHEMA.json`, one sentence per field** | medium | medium, mostly transcription | do it beside item 7; both are "say what the engine already knows". Its output is not the file but the **list of warts** writing it exposes, which is what the deferred syntax pass below is waiting for |
| 8½ | [11](11-styles-as-tags.md) — **styles named by tag** | medium | medium-large | the correction to items 5 and 6: presentation belongs in one named, shared section like `assets`, not as another field per zone. It *deletes* `fit`, `ratio`, `checker` and `paint`, and computed tags then give conditional rendering with no code. Do it after [10](10-schema-document.md) — writing a sentence per field is the cheapest way to find every field this should absorb |
| 8 | [07](07-presentation.md) gap 2 — **click the deck to draw** | medium | low + item 4 | deletes the ugliest card on the Lost Cities board; rules already allow it |
| 9 | [09](09-composition.md) — **`include`, then a base file of patterns** | medium | small, with one trap | the trap is the network: it ships *a file*, so includes must flatten before they are sent or hashed. Cheap if designed in, expensive if found later |
| 10 | [06](06-schema-and-types.md) gap 1 — **zone qualities as tags** | medium | medium | `activate` already proved the shape. Cheaper now than after more games exist |
| 11 | [06](06-schema-and-types.md) gaps 2–3 — **lists everywhere, then guards at the door** | medium | medium | strictly in that order: deleting a guard before the normaliser exists turns a warning into a crash |
| 12 | [08](08-grid-movement-notation.md) — **check, as a stamped `threat` stat** | low | medium | chess and castling are shipped. Check is the last rule that changes how chess plays, and the same stat gives tactical games threat maps. Not a computed tag — see the doc for why |
| 13 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | low | medium | checkers' jump, en passant and castling-through-check all ask for it. Design it with 08's anchor word or they diverge |
| 14 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | low | small | free: answers "is turn-based CS fun" for the price of a game file |
| 15 | [07](07-presentation.md) gap 3 — **multi-ability chooser** | low | medium | no shipped game needs it. Build it with the first card that has two abilities |

**The presentation layer is where bugs now live.** The rules layer is covered
thoroughly and the draw path barely: both chess bugs that reached a human — an
unclickable capture, a crash on hovering a castling card — passed the whole
suite. Items 3, 5 and 6 are all in that layer, which is an argument for doing
them together rather than by urgency alone.

A syntax pass over the JSON is worth doing at some point but **not yet** —
`needs`/`requires`/`accepts` are three names for one shape, `{"subject":
{"at_most": n}}` is a map pretending to be an expression, and `pos` means either
a rect or a list of rects. Write more games first; the warts that actually hurt
will be the ones that keep needing explanation.

## Worktrees: still the same advice

**Yes — but for two or three at a time, not five, and not for docs.**

Worktrees pay off when branches touch **disjoint files**. Measured against this
repo they mostly don't: `predicate.lua`, `actions.lua`, `validate.lua` and
`tests/run.lua` are the hot files, and most ideas want to edit all four.

The conventions that keep it cheap when you do:

- **`actions.lua`'s `SPEC` and `HANDLERS`** — append new entries at the **end**,
  never insert alphabetically. Git merges append-only hunks cleanly; sorted
  insertion conflicts every time.
- **`validate.lua`'s field tables and `tests/integration/validator.lua`'s
  `CASES`** — same rule.
  `CASES` is "every error message, once", so a new message is a new line at the
  bottom.
- **Game files** — one new `.json` per track plus one line in `menu.json`.
  Resolve by taking both. A generated game conflicts in the generator, not the
  output: regenerate after merging rather than merging the JSON.
- **`AUTHORING.md` / `DESIGN.md` / `ARCHITECTURE.md`** — the real conflict
  magnet. **Rule: no track edits the shared docs.** Each writes its user-facing
  documentation into its own `ideas/` file, and one pass on `main` folds them in
  — which is exactly how `DONE.md` came to exist.

### When *not* to use one

- Anything central. A second branch touching `predicate.lua`, `flow.lua` or
  `zones.lua` while another is in flight is pure cost.
- Anything you would finish in an afternoon on `main`.
- These docs. They are additive files with no conflicts.

```fish
git worktree list                    # what's out there
git worktree remove ../ravel-art     # when merged
git worktree prune                   # after deleting a directory by hand
```

Each worktree is a full checkout, so the tests, `play.lua` and `docker compose
up` all work inside it unchanged — everything resolves relative to the repo root
(`headless.lua` sets `package.path` to `game/?.lua`). One caveat:
`docker-compose.yml` binds a fixed port, so don't run two stacks at once without
changing it.
