# Idea 02 — More Than One Player

> *Start with hot-seating […] Ideally it would be networked […] a button that
> says "transfer to other player" which returns a (compressed) json, and a
> "receive move" button.* — `IDEAS.md`

**Status:** not started · **Stage A blocked on:** [00-foundation-scope](00-foundation-scope.md) · **Size:** A small, B small, C medium

Three stages. Each one is independently shippable and each one is genuinely
useful on its own, which is unusual and worth exploiting — do not treat this as
one project.

---

## Stage A — Hot-seat

**This is 90% the foundation doc.** Once stats and counts can be scoped to a
player, hot-seat is mostly content, not engine.

What remains after the foundation lands:

- **Turn ownership in phases.** A phase declares `"player": "active"` (default)
  or a specific player. `next_phase` at a round boundary rotates
  `active_player`. Two-player alternation is then just the phase list, exactly
  as `IDEAS.md` sketches it.
- **Whose turn is it** — a HUD element. `render.lua`'s stat bar
  (`draw_stats`, `game/render.lua:608`) grows a player nameplate; the inactive
  player's stats render dimmed.
- **Hidden hands.** The inactive player's hand renders as backs
  (`draw_card_back`, `game/render.lua:229` already exists). This is *presentation
  only* — the state still holds everything, which is correct for hot-seat and
  emphatically not sufficient for stage C.
- **A pass-the-device screen.** No engine work: it is an overlay phase with one
  card that says "Hand the laptop to Blue" and `on_pick: ["pop_phase"]`.
  Invariant 7 pays out again.
- **Undo becomes an information leak.** Today undo is capped at 50 steps
  (`game/flow.lua:23`). With two players, undoing past a reveal shows one player
  something they shouldn't have seen, and undoing past a turn boundary rewrites
  the other player's decisions. **Clear the history at every turn handover** —
  one line in the rotation, and it also makes stage B's replay model sound.

**Done when:** a two-player fixture game runs a full turn cycle in
`tests/run.lua`, with `gold@me` differing per player, and Lost Cities (see
[01-boardgames](01-boardgames.md)) is playable by two people on one keyboard.

---

## Stage B — Play-by-post (copy/paste)

This is the highest value-per-line feature in the whole ideas file. No server,
no accounts, no hosting bill, no latency assumptions, and it works over Discord,
email, SMS or a piece of paper. It should be built early.

The engine is unusually well set up for it: state is a flat serializable array
(DESIGN.md's first directive), the RNG is seedable with defined precedence, and
the debug server already dumps full state as JSON (`game/debugserver.lua`).

### Two transports, and you want both

**Ship the whole state.** Serialize the entity array + phase stack + fired flags
+ log, compress, base64. Robust — it cannot desync, because there is nothing to
re-derive. Downsides: the blob is large (a few KB compressed for a mid-size
game, which is fine for Discord), and it hands the receiving player the entire
hidden state. For hot-seat-by-mail between friends, that is acceptable; say so
out loud rather than pretending otherwise.

**Ship the moves.** A move is tiny: `{"t":"play","card":17,"targets":[4]}` — a
handful of bytes, human-inspectable, and it makes a game log that can be
replayed, forked and debugged. Requires determinism.

**Recommendation: ship moves, with a state hash appended.** The receiver applies
the move, hashes its own resulting state, compares to the sender's hash, and on
mismatch offers "request full state". Best of both, and the hash is ~15 lines.

### Determinism: one real problem to fix first

The engine is deterministic given a seed, with one exception I found while
reading it:

**`pairs()` iteration order is not portable.** Lua 5.4 randomizes string hash
seeds per process; LuaJIT and PUC-Lua differ from each other regardless. Any
`pairs()` loop whose *order* affects state will desync two machines running
identical inputs. The one that matters:

```lua
-- game/flow.lua:251
for _, def in pairs(G.card_defs) do
    if def.auto_play then ... cards.create(def.key, to.id) ... end
end
```

Entity IDs are assigned by creation order (`game/entity.lua:7`), so two machines
can build the same game with **different IDs for the same cards** — and moves
reference cards by ID. It also shifts RNG consumption if any `on_play` rolls.

Fix: iterate a sorted key list, or better, iterate the ordered card list in file
order. `declaration.parse` already keeps ordered lists for zones, stats and
phases (`G.zone_list`, `G.stat_defs_list`, `G.phase_list`) — `card_defs` just
never needed one. Add `G.card_list` and use it here. Audit the other `pairs()`
loops the same way (`pay` in `game/flow.lua:271` iterates a cost table — order
only matters when clamping interacts, but make it sorted anyway; `cards.reload`
and `can_afford` are read-only and fine).

This fix is worth doing **regardless of multiplayer** — it is a latent
reproducibility bug in a codebase that advertises reproducibility.

### Format

One line, pasteable anywhere, self-identifying:

```
RAVEL1:<game>:<turn>:<base64(deflate(payload))>
```

`love.data.compress`/`love.data.encode` provide deflate and base64 on desktop
and in love.js. Under the headless shim they don't exist — so the transfer
module must degrade to uncompressed JSON when `love.data` is absent, the same
way `cards.image` no-ops headless (invariant 4). That also keeps it testable in
`tests/run.lua`: encode → decode → assert identical state.

### Surface

- **GUI:** two buttons in the turn-handover overlay — "Copy move" (to clipboard,
  `love.system.setClipboardText`) and "Paste move". In love.js, clipboard access
  needs the `love.js.eval` bridge that `cards.lua` already established for
  asset fetching.
- **CLI:** `send` prints the blob, `recv <blob>` applies it. Free, and it makes
  the whole feature testable from a terminal before any UI exists.
- **Debug server:** same two commands, so a script can play both sides.

**Done when:** two `play.lua` processes complete a game of Lost Cities by
pasting strings between terminals, and a test round-trips a move.

---

## Stage C — Networked

Only after B. Once moves are a transportable string, the network is a dumb pipe
and nothing about the game logic changes.

- **Transport, desktop:** luasocket is already a dependency path in `cards.lua`.
- **Transport, browser:** love.js has no sockets, but `cards.lua`'s
  `fetch_browser` proves the `love.js.eval` bridge works for real network I/O.
  A WebSocket or a polling `fetch` against a relay goes through the same door.
- **Relay:** the smallest thing that works is a room-keyed blob store —
  `POST /room/<id>` and `GET /room/<id>?since=<n>`. Under 100 lines, and the
  repo already ships nginx + Docker (`nginx.conf`, `docker-compose.yml`), so it
  has somewhere to live. No accounts, no lobby, no matchmaking: the URL *is* the
  invite, exactly as `IDEAS.md` suggests.
- **What changes about hidden information:** nothing, until you want it to.
  Full-state or full-move sync means each client can see everything. Real hidden
  information requires an authoritative server that filters state per player —
  a different architecture and a much bigger project. **Decide explicitly that
  ravel's networked play is trust-based between friends**, or accept the server.
  Do not drift into the question by accident.

---

## Ordering

Stage A and Stage B are **independent after the foundation** — A is scoping and
UI, B is serialization and determinism, and they barely touch the same files.
That makes them the natural first pair of parallel worktrees (see
[README](README.md)).
