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
| [08](08-grid-movement-notation.md) | How a piece says where it may go | medium | **chess plays, castling included.** `patterns` (relative and absolute), capture, piece ownership, patterns as scopes. Left: the scope anchor word, check/checkmate, promotion, en passant |
| [09](09-composition.md) | One game out of several files | small + one trap | not started — `include`, and a base file of shared patterns |
| [10](10-schema-document.md) | A game file that describes itself | medium | **shipped** — `SCHEMA.json`, held to the engine both ways by a test. Nine findings; two were bugs and are fixed |
| [11](11-styles-as-tags.md) | Styles are tags too | medium-large | **shipped** — `styles`, claimed by tagging one. Absorbed `color`, `fit`, `ratio`, `checker`, `paint` and three tags; `color: false` replaced `transparent_background`. A style that is also a computed tag makes a look follow the numbers |
| [12](12-card-moments.md) | A card is a list of moments | large, mostly migration | **shipped** — `play` / `activate` / `challenge` / `receive` / `turn` / `start`. The `activate_` prefix, `requires`, `accepts` and every `on_` name are gone, and `pick` turned out to be `play` |
| [13](13-one-name-one-thing.md) | One name, one thing | small check | **shipped**, and narrower: a key is unique within its kind, and the *scope* namespace (patterns, zones, tags) may not collide. Everything else may repeat — two repeats are load-bearing |
| [14](14-kinds-and-placements.md) | Six kinds, thirty-two pieces | medium | **half shipped**: `setup.place` exists, so a card no longer says where it starts. Left is the collapse itself — six kinds, with [11](11-styles-as-tags.md) giving a piece its colour |

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
| 1 | [01](01-boardgames.md) gap 3 — **the offset stack** | high | medium | the most visible fault in a shipped game: a Lost Cities expedition is a 1×12 grid in 100px, so a played card gets eight pixels and draws as a hairline. A fan — each card a readable strip, the last one whole — is the same layout Klondike wants |
| 2 | **A nameplate and a pass-the-device overlay** | high | low-medium | hidden hands shipped — a hand is visible to its seat and nobody else. What is left is telling the players *whose turn it is* and giving them a moment to swap seats, which is what makes hot-seat playable rather than merely correct |
| ~~2~~ | ~~[07](07-presentation.md) gap 2 — **click the deck to draw**~~ | — | — | **shipped**, and it never needed the predicate: a zone carries its own `activate` block, so the deck answers rather than the card on top of it becoming clickable |
| 3 | [14](14-kinds-and-placements.md) — **six chess kinds instead of thirty-two** | medium | medium | the payoff for `setup.place` and `styles`: chess loses 26 cards and stops needing a generator. **Needs one thing first** — a style that varies by *owner*, since a white rook and a black rook differ only in how they are drawn, and dynamic styles key on computed tags, which read a card's own stats |
| 4 | [09](09-composition.md) — **`include`, then a base file of patterns** | medium | small, with one trap | the trap is the network: it ships *a file*, so includes must flatten before being sent or hashed. Cheap designed in, expensive found later |
| 5 | [06](06-schema-and-types.md) gap 1 — **zone qualities as tags** | medium | medium | `type` is still four words bundling facing, reach, layout and order. Styles took the presentation half; this is the rest, and the boolean pass just proved the pattern |
| 6 | [06](06-schema-and-types.md) gaps 2–3 — **lists everywhere, then guards at the door** | medium | medium | strictly in that order: deleting a guard before the normaliser exists turns a warning into a crash |
| 7 | [08](08-grid-movement-notation.md) — **check, as a stamped `threat` stat** | low | medium | the last rule that changes how chess plays, and the same stat gives tactical games threat maps. Not a computed tag — the doc says why |
| 8 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | low | medium | a jump takes the piece it flies past, and nothing can name that square. En passant and castling-through-check ask for the same word |
| 9 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | low | small | free: answers "is turn-based CS fun" for the price of a game file |
| 10 | [07](07-presentation.md) gap 3 — **multi-ability chooser** | low | medium | no shipped game needs it. Build it with the first card that has two abilities |

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
