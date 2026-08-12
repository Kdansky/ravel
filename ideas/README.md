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
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | small | **closed** — named assets, remote pictures, and a generated placeholder when one cannot be produced. Art stays in git: that gap was a misunderstanding, and remote art was the real requirement |
| [06](06-schema-and-types.md) | Saying what things are | medium | not started — zone qualities as tags, lists everywhere, guards at the door, the tag registry |
| [07](07-presentation.md) | Presentation and its gestures | medium-large | **text, contrast, board chrome and zone ratios shipped.** Left: clicking the deck (needs the visibility predicate) and the multi-ability chooser |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | medium | **chess plays, castling and check included.** `patterns` (relative and absolute), capture, ownership, patterns as scopes, and `@reach` — so check is a question the game file asks. Left: the scope anchor word, checkmate, promotion, en passant |
| [09](09-composition.md) | One game out of several files | small + one trap | not started — `include`, and a base file of shared patterns |
| [10](10-schema-document.md) | A game file that describes itself | medium | **shipped** — `SCHEMA.json`, held to the engine both ways by a test. Nine findings; two were bugs and are fixed |
| [11](11-styles-as-tags.md) | Styles are tags too | medium-large | **shipped** — `styles`, claimed by tagging one. Absorbed `color`, `fit`, `ratio`, `checker`, `paint` and three tags; `color: false` replaced `transparent_background`. A style that is also a computed tag makes a look follow the numbers |
| [12](12-card-moments.md) | A card is a list of moments | large, mostly migration | **shipped** — `play` / `activate` / `challenge` / `receive` / `turn` / `start`. The `activate_` prefix, `requires`, `accepts` and every `on_` name are gone, and `pick` turned out to be `play` |
| [13](13-one-name-one-thing.md) | One name, one thing | small check | **shipped**, and narrower: a key is unique within its kind, and the *scope* namespace (patterns, zones, tags) may not collide. Everything else may repeat — two repeats are load-bearing |
| [15](15-many-on-one-square.md) | Several cards on one square | answered: *not yet* | **refused for now.** Three questions in one: cards on a card is `attach_to_target`, **built and unused**; a count on a square is a slot stat, half built; an ordered run is a zone with `fan`, shipped. What is left over — identity *and* order *and* a square — no target game asks for |
| [14](14-kinds-and-placements.md) | Six kinds, thirty-two pieces | medium | **shipped** — chess is 13 cards and 279 lines, and its generator is deleted. Ownership is placement state, squares are named (`"at": ["a1", "h1"]`), and a named asset takes one picture per player. Dynamic styles turned out to be the wrong route, and the doc says why |

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
| ~~1~~ | ~~[01](01-boardgames.md) gap 3 — **the offset stack**~~ | — | — | **shipped** as the `fan` style property, not as a zone type. Lost Cities' expeditions are piles that spread out, every played card showing a strip with its name; the tally tray uses it too. Klondike still wants the *reach* half — dropping onto the top card rather than onto the zone |
| ~~—~~ | ~~**A nameplate and a pass-the-device overlay**~~ | — | — | **refused.** Hot-seat is a testing mode — two seats driven by one person — so a handover ceremony has nobody to hand over to. The real multiplayer path is networked, where each machine has its own active seat and the leak cannot happen. See [DONE.md](DONE.md), stage A |
| ~~2~~ | ~~[07](07-presentation.md) gap 2 — **click the deck to draw**~~ | — | — | **shipped**, and it never needed the predicate: a zone carries its own `activate` block, so the deck answers rather than the card on top of it becoming clickable |
| ~~—~~ | ~~[14](14-kinds-and-placements.md) — **six chess kinds instead of thirty-two**~~ | — | — | **shipped.** 39 cards to 13, 704 lines to 279, and `make_chess.py` deleted. The blocker was not a style that varies by owner — a computed tag reads one stat, so it cannot say "rook *and* black" — it was a named asset taking one picture per player |
| — | [09](09-composition.md) — **`include`, then a base file of patterns** | — | — | **paused**, and the pause is a decision rather than a backlog: the collision rule wanted is union-with-identical-or-error, not override, and how far a path may reach turned out to touch the network — a peer's game text parses through the same door, so an include in it reads local files and forwards them. Worth re-opening with that settled |
| 2 | [06](06-schema-and-types.md) gap 1 — **zone qualities as tags** | medium | medium | `type` is still four words bundling facing, reach, layout and order. Styles took the presentation half; this is the rest, and the boolean pass just proved the pattern |
| 3 | [06](06-schema-and-types.md) gaps 2–3 — **lists everywhere, then guards at the door** | medium | medium | strictly in that order: deleting a guard before the normaliser exists turns a warning into a crash |
| ~~—~~ | ~~[08](08-grid-movement-notation.md) — **check, as a stamped `threat` stat**~~ | — | — | **shipped, and not as a stat.** A threat map is the engine deciding chess is special; `@reach` is a scope word the game file asks with (`count:king@enemy.reach`), computed from the `moves` each piece already declares. Left: refusing a move that leaves your king attacked, and checkmate |
| 4 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | low | medium | a jump takes the piece it flies past, and nothing can name that square. En passant and castling-through-check ask for the same word |
| 5 | [15](15-many-on-one-square.md) — **a number on a square** | low | small | a slot is already an entity whose stats a condition can read (`row@target`); it just cannot declare one, so `gain_stat` aimed at a square does nothing. One field on the grid. **Correction:** this was filed as "wanted twice, [08](08-grid-movement-notation.md) needs it for `threat`" and that is wrong — `threat` is stamped by the *engine*, like `col` and `row`, and an engine-stamped stat never needed declaring. The field is for numbers an *author* writes, and no game asks yet |
| 6 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | low | small | free: answers "is turn-based CS fun" for the price of a game file |
| 7 | [07](07-presentation.md) gap 3 — **multi-ability chooser** | low | medium | no shipped game needs it. Build it with the first card that has two abilities |

**The draw path is still where bugs hide, and there is now a way to look.** The
text pass found six faults no test could see — a wrap splitting "Yellow 9" into
"Yello"/"w 9", a badge sitting where the title goes, the tooltip reporting the
engine's own counters as card statistics — every one of them obvious in the
first screenshot. `ideas/07` records the scratch harness and the two things that
stop it working (`captureScreenshot` is asynchronous; the canvas needs
`stencil = true`). Any visual item below should be done against it.

**The syntax pass is done**, and `players` and `setup.place` finished it: a card no longer says whether it is a seat or where it starts. [10](10-schema-document.md) measured it — nine
findings, two of them bugs — and the diagnosis held: **the format had grown
synonyms**. Those are gone. Two names for the card section became `cards`; three
names for one gate became `needs`, with the block saying what it gates; the
`activate_` prefix became structure; seven ways to say how a thing looks became
`styles`. A card is now what it *is*, then the moments it has.

What the schema pass found and this did **not** fix, in case it still itches:
one condition still has three spellings and the site decides which is legal
(finding 5), and a routing entry's `stat` field still takes any subject
(finding 4). Both are additive to fix — nothing would have to be rewritten to
benefit — and neither has cost anybody anything yet.

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
