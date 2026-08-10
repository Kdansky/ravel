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
| [DONE](DONE.md) | **Everything already built** | — | stats on cards · seats and hot-seat · the engine's own RNG · procedural art · Lost Cities · networked play |
| [01](01-boardgames.md) | Any board game as JSON | large, staged | **Lost Cities shipped.** Next: checkers, chess, Klondike, triggers |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | medium | not started — unblocked, and smaller than written |
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | small | not started — placeholder fallback, `asset` prefixes, art out of git |
| [06](06-schema-and-types.md) | Saying what things are | medium | not started — zone qualities as tags, lists everywhere, guards at the door |
| [07](07-presentation.md) | Presentation and its gestures | medium-large | not started — the text/contrast pass, clicking the deck, multi-ability choice |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | medium | **chess plays, castling included.** `patterns` (relative and absolute), capture, piece ownership, patterns as scopes. Left: the scope anchor word, check/checkmate, promotion, en passant |

---

## Where things stand

The engine can express a two-player Knizia game, play it between two computers
over the internet with no server, and hand the game file itself to somebody who
has never seen it. It can now also express a piece that moves across a board —
chess plays, in six pattern entries and no engine knowledge of what a bishop is.
What it cannot yet promise is that your opponent is honest.

## What to do next

Ordered by urgency × difficulty × what it unblocks — cheap things that let other
things happen come first.

| # | Item | Urgency | Difficulty | Why here |
|---|---|---|---|---|
| 1 | [05](05-assets-and-repo.md) gap 1 — **placeholder when a picture is missing** | high | low | one branch in `cards.image`; the *only* thing blocking item 2 |
| 2 | [05](05-assets-and-repo.md) gap 3 — **art out of git, JSON stays** | high | low | wanted now. Note the premise correction: the JSON is already tracked, the art is what has to go |
| 3 | [07](07-presentation.md) gap 1 — **the text, contrast and tooltip pass** | high | medium-high | the thing players actually hit. Mostly judgement, not code |
| 4 | **Hidden hands, a nameplate, a pass-the-device overlay** | high | medium | the last of multiplayer stage A. [07](07-presentation.md) gap 2 needs the same "can this player see this card" predicate, so build it once |
| 5 | [07](07-presentation.md) gap 2 — **click the deck to draw** | medium | low + item 4 | deletes the ugliest card on the Lost Cities board; rules already allow it |
| 6 | [05](05-assets-and-repo.md) gap 2 — **`asset` scheme prefixes** | medium | low | removes run-time guessing; wide but shallow edit |
| 7 | [06](06-schema-and-types.md) gap 1 — **zone qualities as tags** | medium | medium | `activate` already proved the shape. Cheaper now than after more games exist |
| 8 | [06](06-schema-and-types.md) gaps 2–3 — **lists everywhere, then guards at the door** | medium | medium | strictly in that order: deleting a guard before the normaliser exists turns a warning into a crash |
| 9 | [08](08-grid-movement-notation.md) — **check, as a stamped `threat` stat** | low | medium | chess and castling are shipped. Check is the last rule that changes how chess plays, and the same stat gives tactical games threat maps. Not a computed tag — see the doc for why |
| 10 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | low | small | free: answers "is turn-based CS fun" for the price of a game file |
| 11 | [07](07-presentation.md) gap 3 — **multi-ability chooser** | low | medium | no shipped game needs it. Build it with the first card that has two abilities |

Still true and still unowned: **`cards.lua`'s browser asset path is dead code.**
It calls `love.js.eval`, which does not exist in the runtime this repo serves,
and fails silently because every call is `pcall`-guarded. `netlink.lua` has a
bridge that works; pointing `cards.image` at it is small, but it would make an
engine module depend on the optional networking layer, so it wants a decision
about where that bridge should live. Fold it into item 6 — that is the pass that
touches asset resolution anyway.

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
- **`validate.lua`'s field tables and `tests/run.lua`'s `CASES`** — same rule.
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
