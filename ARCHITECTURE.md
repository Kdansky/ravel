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
art ─ procedural placeholder shapes (its pure `parse` is shared with validate)
────────────────────────────────────────────────────────────── presentation
flow ─ THE game driver: init/settle/play/activate/pick/undo, costs, legality
validate ─ whole-file checks: schema, references, conflicts
actions ─ the op vocabulary (HANDLERS table)
phase ─ phase stack, routing, round/fresh flags
targeting ─ who may be targeted (candidates), plus the live selection
predicate ─ the one condition evaluator: subjects, scopes, comparisons
zones ─ zone membership, seats, slots, moving/destroying cards
cards ─ template helpers, live editing, image cache
declaration ─ JSON → G, plus the injected system zone, player/system cards, seats
entity ─ the flat array     log ─ event record     json ─ decode/encode
rng ─ the engine's own PRNG (never the host's, below this line)
```

Optional and additive, required by nothing: `net` (state transfer for
networked play), `netlink` (transports), `netpanel` (its browser controls).
They sit beside the engine rather than in it — see
[ideas/02](ideas/02-multiplayer.md).

Support: `headless.lua` (the love shim), `play.lua` (CLI frontend over flow),
`check.lua` (validate a file without running it), `tests/run.lua` (logic
suite), `tests/render_smoke.lua` (draw-path crash test), `tools/` (game-file
generators — output belongs in `game/games/`, the generator is the source).

## What lives where

**State** is exactly: the entity array inside `entity.lua` (zones, slots,
cards — there is no player entity; the player is a card), the phase stack (`phase`), end-condition fired flags (on `G`),
the event log, and the RNG position (`rng.state()`, one integer). All five are captured by flow's checkpoint and restored by undo —
**if you add stateful storage anywhere else, you must join the snapshot
protocol in `flow.checkpoint`/`flow.undo` or undo will silently break.**

**Templates** (`declaration.G`) are shared, editable-at-runtime data:
`card_defs`, `zone_defs`, `phase_by_key`/`phase_list`, `stat_defs`,
`computed_tags`, `end_conditions`. Instances hold only `def_key` plus
per-instance state (`stats`, `zone_id`, `slot_id`, `exhausted`, `place`).
Undo does not revert template edits — that's a feature (tune, then replay).

**The player is a card.** There are three entity kinds — `zone`, `slot`,
`card` — and the player is not one of them. `declaration.parse` injects two
cards into a hidden `system` grid zone, the same way it injects the built-in
`reveal` zone and phase, and a game may claim either key to override them:

- the **player card** (tag `player`), holding `setup.player`'s stats and
  `plays`. Injected only when no template already carries the `player` tag, so
  a game that wants a visible hero just tags it (castle's throne room) and gets
  stats, targeting, rendering, tooltips and undo for free.
- the **system card** (key `system`), holding `round` — which belongs to the
  game, not to a seat: two players must not get two calendars, and a hero who
  dies must not take one with them.

A subject with no scope resolves to exactly these — every card tagged `player`
plus the system zone — so a bare read and a bare write land on the same card.
That is the whole point: `entity.sum_stat` (read everything) and `stat_holder`
(write to the first holder) used to disagree, and only an unwritten
one-holder-per-stat invariant kept them in step.

**Seats are those cards.** Every card tagged `player` is a seat, in
`G.seat_list` order (file order), named by its own key. A zone def with
`per_seat` is built once per seat, each instance carrying `seat`; `zones.find`
resolves a bare key against the active seat, which it derives from the system
card's `turn` rather than caching — so undo restores whose turn it is along
with everything else. A card's owner is the seat of its zone, which is why
ownership costs no per-card state; a seat card is its own seat wherever it
sits. One seat is the ordinary case and pays for none of this: `active_seat`
returns on its first line and every owner word names the same cards.

**Presentation cache**: `card.place` (pixel rect) lives on entities for
hit-testing and as the animation target, but it is written by
`render.sync_places` every frame (plus a fly-from prestamp in `flow.deal`).
Treat it as disposable.

## Invariants (the rules that keep this codebase small)

1. **IDs, never pointers.** Entities reference each other by array index.
   Undo replaces every entity table with snapshot copies — a held Lua table
   reference across an undo is stale. Re-fetch via `entity.get(id)`.
2. **All mutation goes through flow, and so does all legality.** `play_card`,
   `activate`, `pick`, `zone_click`, `undo`, `init` — each checkpoints first,
   then acts, then `settle()`s. Never mutate game state from presentation code.
   Flow **re-derives** what is legal rather than trusting what it is handed:
   target counts, target identity (`targeting.candidates`, a pure function it
   calls itself), the phase's declared zone, and the acting seat. `targeting`
   holds what a player was *offered*; flow decides what the rules allow, so a
   script or the debug API is bound by exactly the same checks the GUI is.
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
   URLs, a `love.thread` worker over luasocket — its browser branch calls
   `love.js.eval`, which **does not exist** in the runtime this repo serves,
   so that path has never done anything; see Deployment) because it
   is itself presentation-only —
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
   `predicate.lua`. A subject is `[<fn>:]<arg>[@<scope expression>]`, where a
   scope expression is `[<quant>.][<owner>.]<zone-or-tag>` —
   `predicate.parse_subject` is the only place that grammar is decided, and
   `predicate.entities_in_scope` the only place a scope becomes entities, so
   conditions, costs and effects can never disagree about who `@player` is.
   Do not invent a new comparison dialect; extend the evaluator. Same for
   numeric arguments: the single `amount()` resolver in actions.
7. **When in doubt, decks and cards.** New mechanics should be expressible as
   zones, cards, actions and phases before they become engine special cases
   (sub-card choices, endings, pass cards and story pages are all just cards —
   the CYOA layer is one built-in overlay plus two actions over ordinary
   templates).
8. **Randomness is the engine's, never the host's.** `math.random` is a
   different generator in LuaJIT and in PUC Lua, so one seed used to mean a
   different deck on each — which made a replay, a golden trace and a
   networked opponent all interpreter-specific. Everything below the
   presentation line uses `rng.lua` (Lehmer/MINSTD, one integer of state,
   checked against `std::minstd_rand`'s published vector). `fx.lua` keeps
   `math.random` deliberately: particle jitter is presentation, must not be
   reproducible, and must not consume draws the rules depend on. A test greps
   for the line being crossed.

## Life of a click

```
love.mousepressed/released (main)          ── hit-test via card.place
  → flow.play_card(id, targets)
      checkpoint (entities+phases+fired+log mark)
      can_play? (cost via flow.can_afford, needs via predicate, escape hatch)
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
numbers, `zone_id()` for zone arguments so they accept a scope expression,
`log.add` for player-visible effects), declare its argument shape in `SPEC`
(the validator derives its checks from that table), document it in
AUTHORING.md. Nothing else to touch.

**A new kind of legality**: put it where flow can re-derive it, not only where
the GUI can show it — `targeting.candidates` is pure for exactly this reason.
Prefer expressing it in the condition vocabulary (`accepts` is a `predicate`
map, not a new dialect) over a bespoke check.

**A new card/phase/zone field**: parse nothing — defs are carried whole from
JSON. Read it where it matters, add it to the validator's known-field tables
(`CARD_FIELDS` etc. — otherwise every file using it gets an "unknown field"
warning), document it. If it affects playability, surface it in
`flow.can_play` so all interfaces agree.

**A new validator message**: add a case to the `CASES` table in
`tests/run.lua` ("every error message, once") — each message has exactly one
test that proves it still fires, so a check that silently dies turns the
suite red.

**New engine-managed state**: prefer a stat on one of the two injected cards
(`plays` on the player card, `round` on the system card) — snapshots, undo,
display, and predicates come free. Otherwise, join the snapshot protocol
(invariant 3 above).

**A new game**: one JSON file + a menu card. See AUTHORING.md — §3 is the
procedure for translating a published rulebook. Past ~20 templates, generate
the JSON from a checked-in script (`tools/make_lost_cities.py`) and treat the
file as output.

## Testing strategy

- `luajit tests/run.lua` — plays real games through flow headless. Patterns:
  seeded `flow.init(file, seed)` for determinism, `eval("action")` to arrange
  state, count-based assertions over exact-order ones, re-fetch entities by ID
  after undo. All shipped games must validate clean (asserted).
- `luajit tests/render_smoke.lua` — stubs `love.graphics` and drives every
  draw path (flight, arrow, overlays, log, detail views) for every shipped
  game. Catches crashes, not pixels. Two stubs are assertions rather than
  no-ops (`setScissor` rejects a negative size); a catch-all noop answers a
  malformed draw as happily as a good one, which is how a crash in the browser
  build survived a green suite. **Add a game here when you add a game** —
  layouts differ far more than draw code does.
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
Lua 5.1/5.4+ to keep the code portable, and since `rng.lua` it produces the
same golden traces there).

There *is* a way to reach JavaScript, and it is not the `love.js.eval` that
`cards.lua` assumes — that does not exist in the 2dengine runtime, so the
browser asset path silently does nothing. `player.js` overrides `window.open`
(so `love.system.openURL("javascript:…")` is eval'd) and `window.prompt`
(which is what emscripten's stdin calls, so `io.read` returns the result).
`netlink.lua` documents the two traps: inbound reads are quadratic unless
chunked, and a snippet returning `null` closes stdin permanently. Everything a
page can do is reachable this way — `netlink`'s peer-to-peer transport drives
`RTCPeerConnection` through the same door. Check
`love.system.getOS() == "Web"` before touching any of it — on desktop,
`openURL` opens a real browser and `io.read` blocks.
