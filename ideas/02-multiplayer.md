# Idea 02 — More Than One Player

> *Start with hot-seating […] Ideally it would be networked […] a button that
> says "transfer to other player" which returns a (compressed) json, and a
> "receive move" button.* — `IDEAS.md`

**Status:** not started · **Stage A unblocked** ([00](00-foundation-scope.md) shipped) · **Size:** A small–medium, B small, C medium

Three stages. Each one is independently shippable and each one is genuinely
useful on its own, which is unusual and worth exploiting — do not treat this as
one project.

---

## Stage A — Hot-seat

**This was written as "90% the foundation doc". It isn't.** That assumed
[00](00-foundation-scope.md)'s first draft, where a scope was a seat (`@me`,
`@opponent`). The shipped design made a scope a plain zone key or tag and
dropped seats entirely — a better decision, but it leaves the whole of seats
here rather than 10% of it.

What the foundation *did* give: several cards can be tagged `player`, each with
its own stats, individually addressable by tag (`gold@north`), and a `system`
card that already exists to hold a `turn` counter. What it did not give: any
notion of which seat is active, or of a zone belonging to one.

What remains:

- **Seats, and zones that belong to one.** The design is below — it is the bulk
  of this stage.
- **Turn rotation in phases.** A phase declares `"seat": "next"`; entering it
  rotates the active seat. Two-player alternation is then just the phase list,
  exactly as `IDEAS.md` sketches it.
- **A play gate.** `flow.play_card` has no zone check at all today, so nothing
  stops a player playing out of the other player's hand. It must refuse a card
  whose zone belongs to an inactive seat.
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
`tests/run.lua`, with each seat's stats differing and neither able to play from
the other's hand, and Lost Cities (see [01-boardgames](01-boardgames.md)) is
playable by two people on one keyboard.

### Seats, and whose zone a name means

The question this stage exists to answer: if a card says `move_to:arena` and
there is an arena per player, whose arena? And how do you say "kill all
creatures", "kill all *enemy* creatures" and "kill *one* enemy creature"
without any of it becoming engine special cases?

**Ownership is one more word, in the vocabulary that already exists.** The
foundation gave subjects a scope (a zone key or a tag) and a quantifier
(`each` / `any` / `random`). Ownership is a third, orthogonal axis, and every
combination of the three is meaningful — which is the test that it belongs
alongside them rather than inside them.

#### A seat is a card, and a zone can belong to one

A seat is a player card with a name tag — `"tags": ["player", "north"]` — so
`gold@north` already works today. Seat order is `card_list` order, and the
active seat is a `turn` stat on the injected system card, which
[00](00-foundation-scope.md) reserved for exactly this.

A zone declares that it exists once per seat:

```json
{ "key": "arena", "type": "grid", "grid": [5, 1], "per_seat": true }
```

The engine instances it at load — one `arena` entity per seat, each carrying
its seat — and `zones.find` resolves the key against the active seat. That is
the whole per-seat mechanism, and it lands in the one function every zone
reference in the engine already goes through. **A card's owner is the seat of
the zone it is in.** No per-card controller field, no new state to snapshot; a
card in a shared zone (a common deck, a market row) simply has no owner.

#### Scope expressions

The thing after `@` becomes a small expression instead of a single name:

```
[<quant>.][<owner>.]<zone-or-tag>
```

with owner one of `mine` / `enemy` / `anyone`. The same expression stands alone
as an action's zone argument, so there is one grammar in two positions:

```
hp@each.enemy.creature       every creature an opponent owns
hp@random.mine.follower      one of my followers, seeded
sum:value@mine.red           my red expedition's score
move_to:arena                a destination must be one zone, so: the active seat's
move_to:enemy.arena          put it in the opponent's arena
destroy:each.enemy.creature  a board wipe that spares your own
```

`destroy:<zone>` generalises to `destroy:<scope expression>` for free —
`destroy:hand` keeps meaning exactly what it means today, because a bare zone
key is a scope expression that names one zone.

Targeting takes the same word, so the player-chooses case needs no new syntax
either:

```json
"target": { "tags": ["creature"], "owner": "enemy", "count": 1 }
```

#### The four cases, composed

| English | Written as |
|---|---|
| Kill all creatures | `destroy:each.anyone.creature` |
| Kill all enemy creatures | `destroy:each.enemy.creature` |
| Kill one enemy creature (chosen) | `target: {tags, owner: "enemy", count: 1}` + `destroy:target` |
| Kill any one creature (random) | `destroy:random.anyone.creature` |

Nothing above is a new verb. That is the point.

#### Bare means "anyone", and it is deliberate

An unqualified scope filters by *nothing* — exactly today's meaning, so every
shipped game changes by zero bytes and castle's shared board keeps working.

The tempting alternative is bare = `mine`. Rejected for two reasons. First,
cards in shared zones have no owner, so `mine` would have to be defined as
"mine *or* unowned" — a special case, in the one place the engine cannot afford
one. Second, real card games already read this way: "destroy all creatures"
destroys yours too, and it is the *narrowing* that gets a word in the text.

In a one-player game the distinction never surfaces: with one seat, `anyone`,
`mine` and unqualified name the same cards, and `enemy` names none — so
`each.enemy.x` is simply false, by the empty-scope rule the foundation already
established. That is the sense in which this "defaults to P1".

The one asymmetry, stated out loud: a **destination** must resolve to exactly
one zone, so an unqualified per-seat zone used as a destination means the active
seat's. A set can be wide; a place to put a card cannot.

#### What this costs

- `zones.lua`: `key_map` becomes key → seat → id; `zones.find` resolves against
  the active seat. Every existing caller is unchanged.
- `predicate.lua`: `parse_scope` (the expression above) beside `parse_subject`,
  and an owner filter inside `entities_in_scope`.
- `flow.lua`: seat rotation on a phase's `"seat": "next"`, a play gate refusing
  cards in an inactive seat's zones, and clearing undo history at handover
  (below).
- `targeting.lua`: honour `spec.owner`.
- `validate.lua`: unknown owner word, `per_seat` on a zone a one-seat game
  declares, a `"seat"` phase in a game with one seat.

`actions.lua` needs one generalisation (`destroy`) and no new verbs, which is
the signal the shape is right.

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

**`pairs()` iteration order is not portable** — *fixed in `23267e3`; kept here
because the reasoning still applies to any new `pairs()` loop.* Lua 5.4
randomizes string hash seeds per process; LuaJIT and PUC-Lua differ from each
other regardless. Any `pairs()` loop whose *order* affects state will desync two
machines running identical inputs. The one that mattered:

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

This fix was worth doing **regardless of multiplayer** — it was a latent
reproducibility bug in a codebase that advertises reproducibility. `G.card_list`
now exists and `flow.init` walks it; `pay` sorts its cost keys.

The RNG note under stage C is the remaining half of this problem, and it is
larger: LuaJIT and PUC-Lua ship *different generators*, so a seed does not even
reproduce across interpreters, let alone across `pairs()`. `tests/run.lua` skips
the golden traces outside LuaJIT for exactly this reason. Move-based play needs
the engine to carry its own PRNG rather than borrow the host's.

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

Requirement: Currently jit vs lua5.4 uses different RNG implementations, which might need consideration for doing network stuff, since clients easily go out of sync.

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
