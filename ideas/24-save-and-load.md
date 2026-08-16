# 24 — Saving a game, and loading it back

**Status:** not started · **Size:** small engine change sitting on top of a
store that does not exist · **Depends on:** [16](16-the-player-at-this-screen.md)
gap 2, which is the same missing store

> *Add a safe/load functionality to the engine which produces what is
> essentially an encoded json (just like what we send over the network for
> multiplayer), and give games the ability to save/load. We might want to check
> that a game's json hasn't changed between saves, though I'm not sure how.*

**The format the note asks for already exists and is shipped.** `net.snapshot()`
(`net.lua:96`) is *everything ARCHITECTURE.md lists as state*, plus the RNG
position and the file it belongs to, in a table `json.encode` writes with sorted
keys. `net.apply_full(snap)` (`net.lua:475`) puts it back. A save file is that
table; loading one is that call. So this track is not "design a save format" —
it is **give the bytes somewhere to live, and give a game a word for it**.

---

## What is already answered, and it is more than the note expects

| The note asks | What answers it today |
|---|---|
| an encoded json, like the network's | `net.snapshot()` / `net.apply_full()` — the same table, already round-tripped by every message a peer sends |
| stable bytes | `json.encode` sorts map keys, and `net.fingerprint` already depends on that holding on two machines |
| *has the game's json changed?* | **`net.game_hash(filename)`** (`net.lua:145`) and `same_game(body)` (`net.lua:431`), which already refuses a state whose `gh` does not match and says *"different versions of lost_cities.json — theirs 3f2a…, yours 91bc…"* |

The third row is the part the note was unsure about, and it is not only solved
but solved with the error message already written. A save carries `gh` the way a
network message does, `apply_full` checks it on the way in, and a game file
edited since the save is refused at the door rather than three moves later.

**One correction to the premise:** the save is not "essentially" the network
payload, it *is* it. Anything that makes the two diverge — a field saved but not
sent, a version tag on one and not the other — buys a second format to keep
correct. [Assumption: the right shape is one function pair used by both, with
the file layer being the only new code: `save.write(slot)` encoding
`net.snapshot()` and `save.read(slot)` handing the decoded table straight to
`net.apply_full`.]

## What is genuinely missing

### 1. There is nowhere to write

`grep -rn "love.filesystem.write" game/` returns nothing, and `conf.lua` sets no
`t.identity` — so LÖVE has no save directory at all. This is the same finding
[16](16-the-player-at-this-screen.md) gap 2 made from the other side, and it is
the *whole* dependency between the two: a name and a saved game want one store,
and building two would be the mistake.

[Assumption: this is one line in `conf.lua` and a small `save.lua` beside
`net.lua` — outside the engine, in the same spirit as `net.lua`'s first line, so
no engine module requires it and deleting it leaves the game as it was.]

**The browser is the part to check first rather than last.** love.js keeps the
save directory in IndexedDB and needs an explicit sync for a write to survive a
reload. 16 gap 2 already flags this and it bites harder here: a name that does
not persist is an annoyance, a saved game that silently evaporates is a lie.
[Assumption: if the sync turns out not to be wired up in this repo's love.js
build, the honest first version is desktop-only and says so, rather than
offering a browser button that does nothing.]

### 2. A game has no word for it

The note asks to *give games the ability to save/load*, which means an action,
not just a menu item. `load_game:<file>` already exists as an action, so the
shape is established.

[Assumption: `save_game:<slot>` and `load_save:<slot>` as two ordinary actions,
with the slot a plain word from the game file — so a game that wants a single
autosave writes one and a game that wants three writes three, and no engine
concept of "how many saves" is needed. `menu.json` is a game file, so *continue*
is a card in the menu with a `needs` that the slot exists — which wants a
condition that can ask, and that is the one thing in this track with no obvious
existing spelling.]

### 3. The log, and how much of the past a save keeps

`net.snapshot()` carries `log.tail(1e9)` — the whole scrollback — and no undo
history at all, because `flow.forget_history` is what the network calls when a
state arrives. A save is the same trade and should make it deliberately:
**a loaded game has its log and cannot be undone past the load.** That is the
behaviour the network already has and nobody has minded.

## What to refuse

- **A second serialisation format.** The moment a save is not exactly a network
  snapshot, `state_hash`, the delta protocol and undo all have a second thing to
  stay correct against.
- **Saving during a networked game.** Two peers writing independent saves of a
  shared state is a resync problem wearing a new hat. [Assumption: the honest
  version refuses while `net` is linked, and says why.]
- **Migrating an old save to a changed game file.** The `gh` check is the whole
  policy: same file, or no load. A save that *adapts* to an edited game file is
  a schema-migration project, and the note's own instinct — check that it has
  not changed — is the cheaper and more honest answer.
- **Saving to a path the game file names.** The same rule the asset path and
  [09](09-composition.md)'s `include` already enforce: a game file arriving from
  a peer is parsed through the very same door, and a save path it controls is a
  write primitive handed to a stranger. Slots are words; the engine decides
  where they land.

## Build order

1. **The store** — `t.identity`, `save.lua`, and the browser sync question
   answered out loud. Shared with [16](16-the-player-at-this-screen.md) gap 2,
   and whichever track gets there first builds it.
2. **`save.write` / `save.read`** over `net.snapshot` / `net.apply_full`, with
   `gh` carried and checked. A test that a save taken mid-game, loaded back,
   produces the identical `net.fingerprint` — which is the strongest statement
   available that nothing was lost, and it costs one assertion.
3. **A test that an edited game file is refused**, since that is the half of
   the note that was uncertain and the half a silent failure would hurt most.
4. **The two actions**, and a *continue* card in `menu.json` as the proof.
