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

---

## Where things stand

The engine can express a two-player Knizia game, play it between two computers
over the internet with no server, and hand the game file itself to somebody who
has never seen it. What it cannot yet express is a piece that moves across a
board, and what it cannot yet promise is that your opponent is honest.

## What to do next

Ordered by "cheap and unblocks things" first:

1. **Hidden hands, a nameplate, and a pass-the-device overlay.** The last of
   multiplayer stage A, and all presentation — the rules are done. It matters
   more now that two people watch the same state from different machines.
2. **[01](01-boardgames.md) — checkers**, the next rung on the board-game
   ladder. Two thirds of its gap already arrived for other reasons; what is left
   is letting `place_in_slot` capture an occupant.
3. **[04](04-simulation-games.md) — a Cultist Simulator prototype in JSON
   only.** Still free: everything the temporal model needs exists, and it
   answers "is turn-based CS fun" for the price of a game file, before anyone
   writes `check_recipes`.
4. **`cards.lua`'s browser asset path is dead code.** It calls `love.js.eval`,
   which does not exist in the runtime this repo serves, and fails silently
   because every call is `pcall`-guarded. `netlink.lua` has a bridge that works;
   pointing `cards.image` at it is small, but it would make an engine module
   depend on the optional networking layer, so it wants a decision about where
   that bridge should live.

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
