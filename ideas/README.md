# Ravel — Idea Workstreams

`IDEAS.md` is the raw list. These files are the worked-through versions: what
each idea actually requires, where it lands in the code, what order to build it
in, and what to refuse to build.

| # | Idea | Blocked on | Size | State |
|---|---|---|---|---|
| [00](00-foundation-scope.md) | **Stats live on cards** | — | small–medium | **shipped** |
| [01](01-boardgames.md) | Any board game as JSON | — | large, staged | **Lost Cities shipped.** Next: checkers, chess, Klondike, triggers |
| [02](02-multiplayer.md) | More than one player | 05 for stage B | small ×3 | **Stage A (hot-seat) shipped**, bar its HUD polish. B and C not started |
| [03](03-placeholder-art.md) | Procedural placeholder art | — | small | **shipped** |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | — | medium | not started — unblocked, and smaller than written |
| [05](05-determinism.md) | The engine owns its randomness | — | small | not started — blocks 02B, and already costs the test suite |

---

## Where things stand

**The wall all of this was built around is gone.** Stats used to be global in
two ways that disagreed — reads summed every entity, writes went to whichever
entity held the stat first — and that made hot-seat, chess and Cultist
Simulator each *impossible* rather than merely hard. [00](00-foundation-scope.md)
deleted the player entity, and everything since has been vocabulary rather than
special cases.

What the engine can express now that it could not four commits ago:

- **Seats.** A card tagged `player` is a seat; a zone declaring `per_seat`
  exists once per seat; a card's owner is the seat of its zone. Turn order is
  the phase list.
- **Ownership as a third axis**, composing with scope and quantifier:
  `destroy:each.enemy.creature`, `sum:value@mine.red`, `"owner": "enemy"` in a
  target spec.
- **Relational legality** — `accepts` on a destination, asked of each candidate
  with the arriving card bound as `@target`. "A card may go on a higher one" is
  one line.
- **Comparisons in either direction, measured against another subject**, not
  just a constant. This bent DESIGN.md's no-expressions rule on purpose; the
  bend is recorded there.
- **Products** in numeric slots, because `(sum − 20) × wagers` cannot be
  reached by repeated addition.

And two legality holes that had been open the whole time are closed: flow now
re-derives target *identity* and the zone a card is played from, rather than
trusting whatever an interface hands it.

## What to do next

Ordered by "cheap and unblocks things" first:

1. **[05](05-determinism.md) — the engine owns its randomness.** Small,
   isolated, exact pass/fail test, and it is already costing the suite: both
   golden traces are skipped outside LuaJIT because a seed does not reproduce
   across interpreters. Blocks [02](02-multiplayer.md) stage B entirely.
2. **[02](02-multiplayer.md) stage A's remaining polish** — a nameplate, hidden
   hands, a pass-the-device overlay. Presentation only; the rules are done.
3. **[01](01-boardgames.md) — checkers**, the next rung. Two thirds of its gap
   already arrived for other reasons; what is left is letting `place_in_slot`
   capture an occupant.
4. **[04](04-simulation-games.md) — a Cultist Simulator prototype in JSON
   only.** Still free: everything the temporal model needs exists, and it
   answers "is turn-based CS fun" for the price of a game file, before anyone
   writes `check_recipes`.

A syntax pass over the JSON is worth doing at some point but **not yet** —
`needs`/`requires`/`accepts` are three names for one shape, `{"subject":
{"at_most": n}}` is a map pretending to be an expression, and `pos` means
either a rect or a list of rects. Write more games first; the warts that
actually hurt will be the ones that keep needing explanation.

## Worktrees: my recommendation

**Yes — but for two waves of two or three, not five at once, and not for docs.**

Worktrees pay off exactly when branches touch **disjoint files**. Measured
against this repo, they mostly don't: `predicate.lua`, `actions.lua`,
`validate.lua` and `tests/run.lua` are the hot files, and four of the five ideas
want to edit all four. Parallelising before the foundation lands buys you three
sets of merge conflicts in the engine's most delicate module.

### The tracks that are actually parallel now

```fish
git worktree add ../ravel-art  -b art/placeholders   # game/art.lua, cards.image, render_smoke
git worktree add ../ravel-rng  -b eng/rng            # game/rng.lua, zones, actions, flow.init
git worktree add ../ravel-board -b board/geometry    # geometry.lua, movement, capture
```

`art/placeholders` is the textbook case: a new module plus one branch inside
`cards.image`, touching nothing else. `eng/rng` is small but touches
`zones.lua` and `actions.lua`, so land it before anything else that does.
`board/geometry` adds a module and a game file and is mostly additive.

They still collide in four places. The conventions that keep it cheap:

- **`actions.lua`'s `SPEC` table and `HANDLERS`** — append new entries at the
  **end**, never insert alphabetically. Git merges append-only hunks cleanly;
  sorted insertion conflicts every time.
- **`validate.lua`'s field tables and `tests/run.lua`'s `CASES`** — same rule:
  append. `CASES` is "every error message, once", so a new message is a new
  line at the bottom.
- **Game files** — one new `.json` per track, plus one line each in
  `menu.json`. Trivial conflicts, resolve by taking both. A generated game
  (`tools/`) conflicts in the generator, not the JSON — regenerate after
  merging rather than merging the output.
- **`AUTHORING.md` / `DESIGN.md` / `ARCHITECTURE.md`** — the real conflict
  magnet, because every track wants to edit the same reference tables.
  **Rule: no track edits the shared docs.** Each writes its user-facing
  documentation into a "Shipped" section at the bottom of its own
  `ideas/NN-*.md`, and one pass on `main` folds them in afterwards. Docs are
  the cheapest thing to merge by hand and the most expensive to merge with git.

### When *not* to use a worktree here

- Anything central. A second branch touching `predicate.lua`, `flow.lua` or
  `zones.lua` while another is in flight is pure cost — that is what the
  foundation, the seats work and `accepts` each needed, and each was done alone
  on `main` for that reason.
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
