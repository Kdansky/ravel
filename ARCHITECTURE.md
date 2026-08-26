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
inspect ─ ctrl+hover: the JSON behind whatever is under the cursor
anim ─ flight tweens    fx ─ particles/shake/floats
art ─ procedural placeholder shapes (its pure `parse` is shared with validate)
────────────────────────────────────────────────────────────── presentation
flow ─ THE game driver: init/settle/play/activate/undo, costs, legality, the stack
reactions ─ who may answer an event, and whether a window opens at all
validate ─ whole-file checks: schema, references, conflicts
actions ─ the op vocabulary (HANDLERS table)
phase ─ phase stack, routing, round/fresh flags
targeting ─ who may be targeted (candidates), plus the live selection
predicate ─ the one condition evaluator: subjects, scopes, comparisons
zones ─ zone membership, seats, slots, moving/destroying cards
geometry ─ grid arithmetic: which squares a pattern reaches from a square
cards ─ template helpers, live editing, image cache
tags ─ what a card is (declared, granted by its zone, computed) and whose it is
declaration ─ JSON → G, plus the injected system zone, player/system cards, seats
entity ─ the flat array     log ─ event record     json ─ decode/encode
rng ─ the engine's own PRNG (never the host's, below this line)
```

Optional and additive, required by nothing: `net` (state transfer for
networked play), `netpack` (its base64 and LZSS), `netlink` (transports),
`netpanel` (its browser controls), and `save` (a game written to a file and read
back, which is `net`'s own snapshot with somewhere to live).
They sit beside the engine rather than in it — see
[ideas/DONE](ideas/DONE.md).

Support: `headless.lua` (the love shim), `play.lua` (CLI frontend over flow),
`check.lua` (validate a file without running it), `packet.lua` (turn a network
packet back into readable text — `luajit packet.lua '<blob>'`), `tests/run.lua`
(logic suite), `tests/render_smoke.lua` (draw-path crash test), `tools/`
(game-file generators — output belongs in `game/games/`, the generator is the
source).

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

- the **player card** (tagged `player` by the engine), holding its seat's `stats` and
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
with everything else. One seat is the ordinary case and pays for none of this:
`active_seat` returns on its first line and every owner word names the same
cards.

**Ownership** (`tags.owner_of`) is a card's seat *tag* first, and the seat of
its zone second. The tag wins because a zone's seat is where a thing is and a
tag is whose it is, and those come apart on a shared board: a chessboard is one
zone with pieces belonging to two players, and a four-player game can have a
planet held by player three sitting inside player two's system. Ownership still
costs no per-card state — a seat is already a card key, so claiming one is a
tag. Two questions, deliberately separate: `tags.owner_of` is *whose piece is
this* (a seat card is nobody's piece, so a party game tagging four characters
`player` keeps all four clickable on one turn), and `predicate.seat_of` is *who
does this card answer for* (a seat card answers with its own key, which is what
makes `score@mine` find the active seat's stat bag).

**Presentation cache**: `card.place` (pixel rect) lives on entities for
hit-testing and as the animation target, but it is written by
`render.sync_places` every frame (plus a fly-from prestamp in `flow.deal`).
Treat it as disposable.

## Invariants (the rules that keep this codebase small)

1. **IDs, never pointers.** Entities reference each other by array index.
   Undo replaces every entity table with snapshot copies — a held Lua table
   reference across an undo is stale. Re-fetch via `entity.get(id)`.
2. **All mutation goes through flow, and so does all legality.** `play_card`,
   `activate`, `zone_click`, `undo`, `init` — each checkpoints first,
   then acts, then `settle()`s. Never mutate game state from presentation code.
   Flow **re-derives** what is legal rather than trusting what it is handed:
   target counts, target identity (`targeting.candidates`, a pure function it
   calls itself), the phase's declared zone, and the acting seat. `targeting`
   holds what a player was *offered*; flow decides what the rules allow, so a
   script or the debug API is bound by exactly the same checks the GUI is.
3. **`settle` is the only driver.** It loops: pending `load_game` → the response
   window (`flow.react_step`: a seat must answer → stop; a record resolved →
   loop) → end
   conditions (deferred while an overlay is open) → round boundaries
   (counter, ready, every card's `turn.action` — always before the new round's phases act) →
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
   values (`card_stats`, a seat's `stats`) are coerced with `tonumber(v) or 0`
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
      choosing from an overlay? skip cost/needs/targets, pop the phase first
      log "Played X", plays+1, pay cost
      actions.run(play action, ctx)         ── mutates entities, maybe phases
      spent? a card still in the offer it was chosen from is destroyed
      draw_and_play? discard hand (tokens vanish), phase.next
      settle()                              ── routing, rounds, deals, endings
  → next frames: render.sync_places diffs card.place → anim tweens
      anim.on_land → fx.impact; actions.on_stat_change → fx.float
```

The CLI and debug server call the same flow functions; only main.lua's
hit-testing and hooks are GUI-specific. That is why one test suite covers all
three interfaces.

**The seam that claim hides**, and the one place a bug can live where no test
looks: hit-testing returns the topmost *card*, while a spec may be asking for a
*place*. `targeting.aim` closes it — pointing at a piece means pointing at its
square when the spec wants a square — and it lives in `targeting` rather than in
`main` precisely so the tests can ask about it. Capture shipped unclickable for
exactly as long as that rule was written inline in the input layer: every test
reached `targeting.candidates` directly and passed. When a rule about *what a
click means* has to be added, it belongs below the presentation line.

## The response window

A game with a zone tagged `stack` can let one player answer another's action.
Three ideas carry the whole of it, and a game without that zone pays for none of
them.

**Priority is not the turn.** `zones.turn_seat()` is whose turn it is;
`zones.active_seat()` is who may act *right now*, and they differ only inside a
window. Priority lives in one stat (`priority` on the system card), 0 meaning
"nobody but the turn" — so every game that has never heard of reactions reads
exactly the turn, as it always did. Everything downstream — `mine`, costs, the
plays counter, reachability — already reads `active_seat`, which is why moving
priority is the entire out-of-turn unlock.

**Nothing on the stack is a game card.** Each entry is an `event` record
standing for something announced; the card that announced it stays in the hand or
on the table it was played from. A counter therefore removes a record and has
nothing to put back, and where the announcing card lands was already said by its
own `spent`. The record carries what it needs to resolve later (`re_action`,
`re_event`, `re_subject`, `re_actor`, `re_targets`, `re_spent`) as ordinary
entity fields, so undo and the network snapshot carry it for free.

> Which is also the trap: entity state is JSON on its way to a save file and to
> the other client, and a table keyed by a **number** comes back keyed by a
> string. Card ids are numbers. `re_answered` is a *list* of ids for that reason,
> and anything else remembering cards on an entity must be too.

**Two filters, so an unanswerable action never prompts.** `reactions.lua` owns
both. Filter A is `G.react_index`, built once at parse — verb → card → the
reactions on it — so a verb no card in the game answers short-circuits before a
single card is looked at. Filter B walks the board and asks each candidate
whether it matches: `where` against the event, `when` against the reactor (asked
as their seat), and *where the card is*. That last one is asked two ways —
strictly when the answer is acted on, loosely when it merely decides whether to
open a window, because a hand and the bag behind it are the same place from
across the table. Opening on what is publicly possible costs a pass now and then
and keeps the prompt from being evidence about a hidden hand.

`flow.react_step` is the scheduler and runs inside `settle`: it returns
`waiting` (a seat must answer), `resolved` (a record ran) or `idle` (no stack —
every existing game). An interjected phase counts as `waiting`, because a phase
pushed for the answering seat is part of resolving the record that opened it.

**It walks the responders twice, forced first and all of them.** A trigger is
not the seat's to decline, so a pass does not silence it and a card standing
ahead of it in the list cannot spend its turn: one fires per step and `settle`
comes straight back for the next, which is how a record with three answers owed
runs all three. Only then are the questions asked, and only the optional ones —
a forced reaction that cannot fire is not a question, and offering it as one is
how a trigger got lost. That is what `forced_verdict` is for: `fire` on its own,
`ask` when it has to be aimed after all, `no` when the loose reading found a
card that is not really where it could answer from.

**What may answer whom** is one word on the reaction, `whose`, in the scope
grammar's own vocabulary: `enemy` (the default), `mine`, `anyone`. It is not
what makes the protocol terminate — that is `re_answered`, which lets one card
answer one record once. An answer is a *new* record with its own memory, so a
chain gets longer rather than going round, and the only shape that can still run
away — a mandatory board reaction answering the verb answers themselves go up as
— hits `STACK_LIMIT`, is marked as having had its go, and unwinds.

**A phase announces itself** through the same `emits` a card carries, keyed by
the two hooks a phase already had: `begin` beside the actions it runs on entry,
`end` beside the hand it discards on the way out. Nothing is deferred, because a
phase has no action list waiting on the answer. This is the only announcement in
the engine that nobody caused, and it is what "at the end of your turn" is made
of: the subject is the player card of whoever the phase belongs to, so `whose`
and `@event` read there exactly as they do anywhere else.

## Extending the engine

**An optional layer with its own vocabulary**: declare the words in actions.lua
(`SPEC` + a `HANDLERS` entry that calls a hook) and let the layer assign the
hook on require — that is how the `net_*` ops work. The validator then checks
them like anything else, and the words survive as silent no-ops if the layer is
deleted.

**A new action**: add a `HANDLERS["op"]` in actions.lua (use `amount()` for
numbers, `zone_id()` for zone arguments so they accept a scope expression,
`log.add` for player-visible effects), declare its argument shape in `SPEC`
(the validator derives its checks from that table), document it in
AUTHORING.md. Nothing else to touch.

**A new kind of legality**: put it where flow can re-derive it, not only where
the GUI can show it — `targeting.candidates` is pure for exactly this reason.
Prefer expressing it in the condition vocabulary (`receive.needs` is a `predicate`
map, not a new dialect) over a bespoke check.

**A new card/phase/zone field**: parse nothing — defs are carried whole from
JSON. Read it where it matters, add it to the validator's known-field tables
(`CARD_FIELDS` etc. — otherwise every file using it gets an "unknown field"
warning), document it. If it affects playability, surface it in
`flow.can_play` so all interfaces agree.

**A new validator message**: add a case to the `CASES` table in
`tests/integration/validator.lua` ("every error message, once") — each message has exactly one
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
- `tests/integration/*.lua` — **where new tests go.** A module returning a
  table; every exported `test*` function is a test, handed `check` and nothing
  else. `tests/harness.lua` loads the folder, sorts by name and runs each one
  under `xpcall`, so a test that raises is one failure with a traceback rather
  than the end of the suite. `luajit tests/run.lua <pattern>` runs just the
  matching ones and skips everything else. Each test starts from its own
  `flow.init` and must leave no state behind — the price of being able to run
  it alone. The body of `run.lua` is the older half: one script whose sections
  inherit each other's state, cheaper to write and much harder to read a
  failure out of. Move a section over when you touch it.
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
