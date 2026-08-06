# Ravel — Idea Workstreams

`IDEAS.md` is the raw list. These files are the worked-through versions: what
each idea actually requires, where it lands in the code, what order to build it
in, and what to refuse to build.

| # | Idea | Blocked on | Size | Notes |
|---|---|---|---|---|
| [00](00-foundation-scope.md) | **Stats live on cards** | — | small–medium | Not in `IDEAS.md`. The shared prerequisite. |
| [01](01-boardgames.md) | Any board game as JSON | 00 | large, staged | Chess/checkers/solitaire/Knizia/Hearthstone |
| [02](02-multiplayer.md) | More than one player | 00 (stage A only) | small ×3 | Hot-seat → copy/paste → networked |
| [03](03-placeholder-art.md) | Procedural placeholder art | — | small | Startable today, fully isolated |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | 00 | medium | Closer to working than it looks |

---

## The one finding that shapes everything

Three of the four ideas hit the **same wall**: stats are global, and worse, they
are global in two different ways that disagree. Reads sum a stat across every
entity in the game (`entity.sum_stat`, `game/entity.lua:30`); writes give it all
to whichever entity holds the stat first (`actions.stat_holder`,
`game/actions.lua:57`). Those only agree under an invariant nothing writes down
or enforces: **one entity per player-facing stat.**

That is correct and minimal for one player on one board, and it is why the
engine is 8k lines. It also makes hot-seat, chess and Cultist Simulator each
*impossible* rather than merely hard — not one of them can ask "how much gold do
**I** have" or "what is in **this** zone".

The fix is to **delete the player entity and make the player a card**
([00](00-foundation-scope.md)). `castle.json` already does this — its stats live
in `card_stats` on the `throne_room` template and it has no `setup.player` at
all — so the design is validated by the best-developed shipped game. Entity
kinds drop from four to three, reads and writes finally resolve to the same
entity, and a party of characters with individual stats needs no new engine
concept at all. Build it first, alone, on `main`.

Two smaller findings worth acting on regardless of which idea you pursue:

- **`pairs()` over `card_defs` in `flow.init` (`game/flow.lua:251`) breaks
  reproducibility.** Entity IDs are assigned in creation order, and `pairs()`
  order is not portable across Lua builds or (in 5.4) across processes. Two
  machines can load the same file and give the same card different IDs. That's a
  latent bug in a codebase that advertises seeded reproducibility, and it is a
  hard blocker for [move-based multiplayer](02-multiplayer.md#stage-b--play-by-post-copypaste).
  Fix: add an ordered `G.card_list`, as already exists for zones, stats and phases.
- **A ruined watchtower defends Castle Lord forever.** `on_play` adds +2 to a
  global `defense` total and nothing removes it when the building is reduced to
  0 hp (`game/games/castle.json:45`, and the unused `ruined` computed tag at
  line 18). A symptom of the same root cause — it stops being *writable* once
  defense is a property of the card that provides it.
- **Placeholder art is the one thing with no dependencies at all.** If you want
  something to make progress on immediately, it is that.

---

## The easiest path through all of this

The governing principle: **prove before you build.** Two of these four ideas can
be *answered* — not implemented, answered — with a JSON file and no engine code
at all. Do those first, because they might change what you build.

### Tier 0 — free, today, no engine changes

- **A Cultist Simulator prototype, in JSON only.** Everything idea 04 needs for
  the *temporal* model already exists: a verb is a grid zone, aspects are
  `card_stats`, a running verb is a card with a `timer` stat and
  `on_turn: ["lose_stat:timer:1"]`, and "finished" is a `computed_tag` of
  `{"stat": "timer", "equals": 0}`. The one thing actions can't do is branch —
  but **phase routing is the conditional**: an automatic tick phase routes to a
  payout phase when `count:done` is at least 1, else back to input.
  (`resolve_challenge` is a second way in, via `requires`/`on_pass`/`on_fail`.)
  Conditions are global, so this only stays clean for one verb at a time —
  which is exactly enough to find out whether turn-based CS is *fun* before
  committing to the recipes subsystem. Cost: an afternoon and no code.
- **The `card_list` determinism fix.** `pairs()` over `card_defs` in
  `flow.init` (`game/flow.lua:251`) makes entity IDs non-portable. Add an
  ordered `G.card_list` in `declaration.parse` — the file already builds exactly
  this for zones, stats and phases — and iterate that. Roughly five lines,
  removes a latent reproducibility bug, and unblocks move-based multiplayer.

### Tier 1 — additive, isolated, parallelisable

- **Placeholder art** (03). A new module plus one branch inside `cards.image`.
  Touches nothing else, blocked by nothing, needed by everything eventually.
  This is the worktree track that runs from day one.

### Tier 2 — the one real refactor

**Stats live on cards** (00). This is the only scary item on the list, and the
way to make it not scary is to land it as a sequence of individually-green
commits, each provable against a golden file.

**Build the golden file first.** The event log is already an exact, textual
record of observable behaviour — `change_stat` logs every stat change *with the
entity it hit* (`game/actions.lua:78-83`), plus plays, picks, draws, challenge
results and round markers. So:

1. **Golden trace.** A test that plays a fixed seeded sequence through
   `castle.json` and `kingdom.json` and asserts the full log matches a committed
   fixture. Cheap (`flow.init(file, seed)` + scripted calls + `log.tail`), and it
   catches precisely the thing this refactor could get wrong: a stat landing on
   the wrong entity. Everything below is then "did the golden change?"
2. **Resolver, with no callers.** `predicate.parse_subject` and
   `entities_in_scope` as pure functions with their own unit tests. Trivially
   green.
3. **Reads route through it, scope defaults to `all`.** Behaviour identical by
   construction. Golden unchanged.
4. **Player entity becomes a player card** in a hidden `system` zone, still
   created at the same point in `flow.init` — so it is still the first holder of
   every stat and `stat_holder` still picks it. Golden unchanged. This is the
   commit that deletes `kind = "player"`, and it is small.
5. **`round`/`turn` move to a `system` card, `plays` stays on the player card.**
6. **Bare subjects switch from `all` to `@me`.** The actual semantic change —
   and a no-op for every shipped game by the one-holder invariant, which the
   golden now proves rather than assumes.
7. **Delete `stat_holder`**; writes resolve exactly like reads.
8. **`castle.json` adds `"player"` to `throne_room`'s tags.** Then, separately,
   convert its defense to `sum:defense@board` — that commit *should* change the
   golden, and the diff is the ruined-watchtower bug being fixed.

Eight commits, each one green, each one revertable on its own.

### Tier 3 — after the foundation

- **Lost Cities** (01, Knizia) — a real published two-player game with near-zero
  new engine code. The cheapest possible load test of the new stat model.
- **Hot-seat** (02 stage A) — mostly falls out of the above.
- Then fan out into the wave-1 worktrees below: board geometry, zone recipes,
  copy/paste transfer.

### What to deliberately not start yet

Networked play, triggers/Hearthstone, checkmate, Book of Hours. Each is large,
each is better specified after the tier-2 and tier-3 work has taught you
something, and none of them is blocked by waiting.

---

## Worktrees: my recommendation

**Yes — but for two waves of two or three, not five at once, and not for docs.**

Worktrees pay off exactly when branches touch **disjoint files**. Measured
against this repo, they mostly don't: `predicate.lua`, `actions.lua`,
`validate.lua` and `tests/run.lua` are the hot files, and four of the five ideas
want to edit all four. Parallelising before the foundation lands buys you three
sets of merge conflicts in the engine's most delicate module.

### Before anything: commit

`git status` currently shows **89 modified/untracked paths on a single commit**.
A worktree branches from a *commit*, so every one of those changes would be
missing from it. Commit (or at least stash-and-branch) the current work first —
this is the actual prerequisite, not the worktree mechanics.

### Wave 0 — two tracks

```fish
# main: the foundation, sequential, alone
#   game/predicate.lua, game/entity.lua, game/actions.lua, game/validate.lua

# worktree: procedural art, fully isolated
git worktree add ../ravel-art -b art/placeholders
cd ../ravel-art; luajit tests/run.lua      # everything is repo-root-relative; just works
```

`art/placeholders` touches `game/cards.lua`'s image path, a new `game/art.lua`,
and `tests/render_smoke.lua`. Zero overlap with the foundation. This is the
textbook case for a worktree.

### Wave 1 — after the foundation merges, three tracks

```fish
git worktree add ../ravel-board -b board/geometry     # geometry.lua, movement, capture
git worktree add ../ravel-sim   -b sim/recipes        # zone recipes, consume action
git worktree add ../ravel-post  -b mp/transfer        # serialization, determinism, CLI send/recv
```

These are genuinely parallel: each adds a **new module** plus its own game JSON
under `game/games/`, and their engine edits are mostly additive. `mp/transfer`
in particular barely touches the engine at all.

They still collide in four places. The conventions that keep it cheap:

- **`actions.lua`'s `SPEC` table (`game/actions.lua:338`) and `HANDLERS`** —
  append new entries at the **end**, never insert alphabetically. Git merges
  append-only hunks cleanly; sorted insertion conflicts every time.
- **`validate.lua` and `tests/run.lua`'s `CASES` (`tests/run.lua:791`)** — same
  rule: append.
- **Game files** — one new `.json` per track, plus one line each in
  `menu.json`. Trivial conflicts, resolve by taking both.
- **`AUTHORING.md` / `DESIGN.md` / `ARCHITECTURE.md`** — the real conflict
  magnet, because everyone wants to edit the same reference tables. **Rule: no
  track edits the shared docs.** Each writes its user-facing documentation into
  a "Shipped" section at the bottom of its own `ideas/NN-*.md`, and one pass on
  `main` folds all three into `AUTHORING.md` after they merge. Docs are the
  cheapest thing to merge manually and the most expensive thing to merge with
  git.

### Wave 2

Networked play (02 stage C), triggers and a Hearthstone-like (01 gap 5), legal
chess with checkmate. All large; all want the previous wave landed first.

### When *not* to use a worktree here

- The foundation. It is short, it is central, and a second branch touching
  `predicate.lua` while it is in flight is pure cost.
- Anything you'd finish in an afternoon on `main`.
- These docs. They are additive files with no conflicts — they went straight
  onto `main`.

### Housekeeping

```fish
git worktree list                    # what's out there
git worktree remove ../ravel-art     # when merged
git worktree prune                   # after deleting a directory by hand
```

Each worktree is a full checkout, so `luajit tests/run.lua`, `luajit play.lua`
and `docker compose up` all work inside it unchanged — everything in this repo
resolves relative to the repo root (`headless.lua:4` sets `package.path` to
`game/?.lua`). One caveat: `docker-compose.yml` binds a fixed port, so don't run
two stacks at once without changing it.
