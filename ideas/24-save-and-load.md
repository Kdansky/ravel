# 24 — Saving a game, and loading it back

**Shipped** — `game/save.lua`, `tests/integration/save.lua`.

| | |
|---|---|
| `save_game:<slot>` | write the position out |
| `load_save:<slot>` | put it back, whichever game it was of |
| `saved:<slot> >= 1` | a condition: is there anything in that slot |

## The decision

**A save is not "essentially" the network payload, it *is* it.** `M.write` is
`net.snapshot()` plus a game hash handed to `json.encode`; `M.read` is
`json.decode` handed to `net.apply_full`. There is no serialisation code in the
file at all — the other 120 lines are refusals. Anything that made the two
diverge would buy a second format to keep correct, and `state_hash`, the delta
protocol and undo would all have a second thing to stay right against.

The proof is two cards and no third place to look: chess deals a **Save**
button, `menu.json` deals **Continue**, and Continue names no game — the save
names its own file and that file is loaded first.

A loaded game keeps its log and cannot be undone past the load. That is what the
network already does and nobody has minded.

## What building it found

**The browser needed one line, not a caveat.** The write-up guessed the honest
first version might be desktop-only. love.js already mounts `$HOME` as IDBFS and
populates it before the game starts, so a save *is* read back after a reload;
what it only does at exit is the flush, and a tab is never exited. One
`javascript:` snippet after each write pushes it across, through the bridge
`netlink.lua` documents. Fire and forget — syncfs is asynchronous and there is
nothing useful to do about a failure a whole tab away.

**The condition had a spelling already in the grammar.** `saved:<slot>` is
`tagged:`'s shape — a yes/no as 1 or 0. The only new thing is *who answers*: it
is a fact about the machine rather than any card, so `predicate` asks through
`M.saved_slot`, and a build without `save.lua` answers 0, which is true there.

**"slot" was already taken.** The engine calls a square on a grid a slot, so an
argument type spelled `slot` would read as "this action takes a square". The
type is `save`; the word a player uses stays *slot*.

**Loading defers like `load_game`**, through `actions.pending_slot` and
`flow.settle` — it replaces every entity, so actions written after it in the
same list would run against a world nobody wrote them for.

**The game-hash refusal needed its own sentence.** net's reads *"different
versions of chess.json — theirs 3f2a…, yours 91bc…"*, which is a sentence about
two people. `save.read` says *"chess.json has changed since this was saved"*
first; net's stays underneath as the backstop.

## Refused

- **A second serialisation format**, for the reason above.
- **Saving during a networked game** — two peers writing independent saves of a
  shared state is a resync problem in a new hat.
- **Migrating an old save to a changed game file.** Same file, or no load.
- **Saving to a path the game file names.** A game file can arrive from a peer;
  a write primitive it controls is one handed to a stranger. Slots are words,
  and the engine decides where they land.
- **A timestamp, an index, or a delete action.** How many saves there are is not
  a question the engine has an answer for. `M.forget` is module API with no
  action word: a card that deletes your save is not a button anybody asked for.
