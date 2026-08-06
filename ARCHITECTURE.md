# Ravel Engine Architecture

For future code authors. `DESIGN.md` records the directives; `AUTHORING.md` is
the content-side manual; this explains how the engine is built and how to
extend it without breaking its guarantees.

---

## The one-paragraph version

All game state is a **flat array of entities** referencing each other by
integer ID. Game **templates** (parsed JSON) are read-only-ish data that
instances point into by key. Every mutation goes through **flow**, which
checkpoints state for undo, runs data-driven **actions**, and then drives a
**settle** fixpoint (loads, end conditions, phase routing, dealing) until the
game is stable. The presentation layer re-derives everything it draws from
state every frame and is never required by game logic — which is why the whole
engine runs headless under a 20-line `love` shim.

---

## Module map

Dependencies point downward only. Nothing below the line may require anything
above it.

```
main ─ input routing, love callbacks, hot-reload watch
render ─ drawing, layout, UI scale, buttons     tooltip   debugserver
anim ─ flight tweens    fx ─ particles/shake/floats
────────────────────────────────────────────────────────────── presentation
flow ─ THE game driver: init/settle/play/activate/pick/undo
validate ─ whole-file checks: schema, references, conflicts
actions ─ the op vocabulary (HANDLERS table)
phase ─ phase stack, routing, round/fresh flags
zones ─ zone membership, slots, moving/destroying cards
cards ─ template helpers, affordability, live editing, image cache
predicate ─ the one condition evaluator      targeting ─ eligibility state
declaration ─ JSON → game definition (G) + built-in reveal zone/phase
entity ─ the flat array     log ─ event record     json ─ decode/encode
```

Support: `headless.lua` (the love shim), `play.lua` (CLI frontend over flow),
`tests/run.lua` (logic suite), `tests/render_smoke.lua` (draw-path crash test).

## What lives where

**State** is exactly: the entity array inside `entity.lua` (player, zones,
slots, cards), the phase stack (`phase`), end-condition fired flags (on `G`),
and the event log. All four are captured by flow's checkpoint and restored by undo —
**if you add stateful storage anywhere else, you must join the snapshot
protocol in `flow.checkpoint`/`flow.undo` or undo will silently break.**

**Templates** (`declaration.G`) are shared, editable-at-runtime data:
`card_defs`, `zone_defs`, `phase_by_key`/`phase_list`, `stat_defs`,
`computed_tags`, `end_conditions`. Instances hold only `def_key` plus
per-instance state (`stats`, `zone_id`, `slot_id`, `exhausted`, `place`).
Undo does not revert template edits — that's a feature (tune, then replay).

**Presentation cache**: `card.place` (pixel rect) lives on entities for
hit-testing and as the animation target, but it is written by
`render.sync_places` every frame (plus a fly-from prestamp in `flow.deal`).
Treat it as disposable.

## Invariants (the rules that keep this codebase small)

1. **IDs, never pointers.** Entities reference each other by array index.
   Undo replaces every entity table with snapshot copies — a held Lua table
   reference across an undo is stale. Re-fetch via `entity.get(id)`.
2. **All mutation goes through flow.** `play_card`, `activate`, `pick`,
   `zone_click`, `undo`, `init` — each checkpoints first, then acts, then
   `settle()`s. Never mutate game state from presentation code.
3. **`settle` is the only driver.** It loops: pending `load_game` → end
   conditions (deferred while an overlay is open) → round boundaries
   (counter, ready, `on_turn` — always before the new round's phases act) →
   automatic phases → dealing fresh phases. It carries a
   64-transition budget; on breach it warns and halts. Anything that needs to
   happen "after an action" belongs here, not sprinkled at call sites.
4. **Logic is headless.** Modules below the presentation line may touch
   `love.filesystem.read` and `love.graphics.getDimensions` only (the shim
   surface). If a logic module needs anything visual, it exposes a hook
   (`flow.on_reset`, `actions.on_stat_change`, `anim.on_land`) that the
   presentation layer assigns. `cards.image` is the one deliberate exception:
   it touches `love.graphics.newImage` directly (and, for `http(s)://` asset
   URLs, `love.js.eval`/luasocket) because it is itself presentation-only —
   nothing in flow's state graph depends on whether an image loaded — and
   every call is behind checks that no-op cleanly under the headless shim.
5. **Content errors warn, never crash — and content is untrusted.** Games are
   meant to be authored by people other than whoever is running the engine,
   so every JSON field a game can set is adversarial input, not just
   typo-prone input. Unknown ops log and skip; the validator reports
   problems at load (but never blocks them — warnings don't stop content
   from running, so the *runtime* must be safe on its own); loops are
   budgeted. Concretely: `json.lua` is a hand-rolled recursive-descent
   parser, never `load`/`loadstring` over untrusted text; stat-bearing
   values (`card_stats`, `setup.player`) are coerced with `tonumber(v) or 0`
   at the point they're written, so a malformed value can never reach
   arithmetic as a string and throw; `predicate.met`/`meets_all` coerce and
   type-check before every comparison and fail closed (false) rather than
   erroring on a malformed condition; `load_game:` and local `asset` paths
   are restricted to a bare filename (no `..`, no path separators — see
   `safe_game_filename` in actions.lua and the matching check in
   `cards.image`); and the one content-triggered call into `declaration.load`
   (in `flow.settle`, servicing the `load_game` action) is `pcall`-wrapped
   with a fallback to `menu.json`, so a file that's missing, isn't valid
   JSON, or blows the parser's recursion depth recovers instead of crashing
   the process. A typo — or a deliberately hostile file — must never kill a
   running game.
6. **One condition vocabulary.** Anything conditional goes through
   `predicate.lua` (subjects: stats, `count:<tag>`, `card:<key>`). Do not
   invent a new comparison dialect; extend the evaluator. Same for numeric
   arguments: the single `amount()` resolver in actions.
7. **When in doubt, decks and cards.** New mechanics should be expressible as
   zones, cards, actions and phases before they become engine special cases
   (sub-card choices, endings, pass cards and story pages are all just cards —
   the CYOA layer is one built-in overlay plus two actions over ordinary
   templates).

## Life of a click

```
love.mousepressed/released (main)          ── hit-test via card.place
  → flow.play_card(id, targets)
      checkpoint (entities+phases+fired+log mark)
      can_play? (cost via cards.can_afford, needs via predicate, escape hatch)
      log "Played X", plays+1, pay cost
      actions.run(def.on_play, ctx)         ── mutates entities, maybe phases
      draw_and_play? discard hand (tokens vanish), phase.next
      settle()                              ── routing, rounds, deals, endings
  → next frames: render.sync_places diffs card.place → anim tweens
      anim.on_land → fx.impact; actions.on_stat_change → fx.float
```

The CLI and debug server call the same flow functions; only main.lua's
hit-testing and hooks are GUI-specific. That is why one test suite covers all
three interfaces.

## Extending the engine

**A new action**: add a `HANDLERS["op"]` in actions.lua (use `amount()` for
numbers, `log.add` for player-visible effects), add any reference checks to
`validate.lua`, document it in AUTHORING.md. Nothing else to touch.

**A new card/phase/zone field**: parse nothing — defs are carried whole from
JSON. Read it where it matters, add it to the validator's known-field tables
(`CARD_FIELDS` etc. — otherwise every file using it gets an "unknown field"
warning), document it. If it affects playability, surface it in
`flow.can_play` so all interfaces agree.

**A new validator message**: add a case to the `CASES` table in
`tests/run.lua` ("every error message, once") — each message has exactly one
test that proves it still fires, so a check that silently dies turns the
suite red.

**New engine-managed state**: prefer a stat on the player entity (`round`,
`plays` precedent) — snapshots, undo, display, and predicates come free.
Otherwise, join the snapshot protocol (invariant 3 above).

**A new game**: one JSON file + a menu card. See AUTHORING.md.

## Testing strategy

- `luajit tests/run.lua` — plays real games through flow headless. Patterns:
  seeded `flow.init(file, seed)` for determinism, `eval("action")` to arrange
  state, count-based assertions over exact-order ones, re-fetch entities by ID
  after undo. All shipped games must validate clean (asserted).
- `luajit tests/render_smoke.lua` — stubs `love.graphics` and drives every
  draw path (flight, arrow, overlays, log, detail views). Catches crashes,
  not pixels.
- `RAVEL_DEBUG=1` + `nc` — poke a live GUI process; `echo state | nc` dumps
  full entity state as JSON.
- Balance questions: write a scratch script over `headless.lua` + `flow` and
  simulate a few hundred runs (this is how Castle Lord's 100% softlock was
  found). `cards.edit` lets a simulation hot-patch numbers mid-experiment.

## Deployment

`game/` is zipped to `game.love` by the Docker entrypoint and served through
love.js (browser, SharedArrayBuffer headers via nginx). Browser constraints:
no sockets (debug server no-ops), no file watching (hot-reload no-ops), LuaJIT
semantics (`luajit` is the reference interpreter; the suite also runs under
Lua 5.1/5.4+ to keep the code portable).
