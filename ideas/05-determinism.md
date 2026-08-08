# Idea 05 — The Engine Should Own Its Randomness

**Status:** **shipped** (`5d4091d`) · **Was blocking:** [02 stage B and C](02-multiplayer.md) ·
**Size:** small (~80 LOC, one module, three call sites) — which is what it cost

## What was built

`game/rng.lua`: Lehmer / MINSTD, `x = 48271 * x mod (2^31 - 1)`. The choice
turned on the "published test vector" requirement below — this is exactly what
C++ standardised as `std::minstd_rand`, so the test asserts the standard's own
number (seed 1, 10000 draws, 399268537) rather than asserting that the
generator agrees with itself. Integer-only; the widest intermediate is
`48271 * (2^31 - 2) ≈ 2^46.6`, exact both in a double and in a 64-bit integer,
so 5.1, LuaJIT and 5.4 produce one sequence with no bit operations.

All three call sites moved (`zones.shuffle`, `designated`'s `random`
quantifier, `destroy`'s `random.`), `flow.init` seeds it, and `fx.lua` kept
`math.random` on purpose. The generator's state is one integer, so it joined
`flow.checkpoint` in two lines and rides in net.lua's state transfer for free.

**Both "done when" conditions hold.** `luajit tests/run.lua` and
`lua5.4 tests/run.lua` produce identical golden transcripts and the skip is
deleted; no `math.random` call remains below the presentation line (a test
greps for it); undo across a shuffle replays that shuffle.

One thing the plan did not say: with no seed anywhere, `flow.init` now falls
back to `os.time()`. It used to inherit whatever `math.randomseed(os.time())`
had been called at startup, and dropping that would have made every unseeded
game identical.

---

*The original write-up follows.*

Not from `IDEAS.md`. It was a footnote inside [02](02-multiplayer.md) — noticed
while writing the transfer format, then again while recording the golden
traces — and it is not really a multiplayer feature at all. It is a correctness
bug in a codebase whose first design directive is reproducibility, and it is
already costing something today.

---

## The problem

`math.randomseed` / `math.random` are the host's, and the host is not one
thing:

- **LuaJIT** (what LÖVE ships, and what the game actually runs on) uses a
  Tausworthe generator.
- **PUC Lua 5.4** uses xoshiro256\*\*.

Same seed, different sequence. Not subtly different — the very first card drawn
diverges. Two machines running the identical file with the identical seed do
not produce the same game.

## What it already costs

**The golden traces are LuaJIT-only.** `tests/run.lua` skips both transcripts
outside LuaJIT and says so out loud, because a seed does not reproduce across
interpreters. That is a real hole in the regression net: the suite's strongest
test — "does this file still play exactly as recorded" — silently does not run
for anyone using `lua5.4`.

**Nothing else guarantees a shuffle is stable.** `zones.shuffle`,
`hp@random.<tag>`, `destroy:random.…` and `reveal_top` all consume host RNG.
A seeded replay is only reproducible on the machine that recorded it.

## What it blocks

[02 stage B](02-multiplayer.md#stage-b--play-by-post-copypaste) — move-based
play — cannot work at all. A move is `{"t":"play","card":17}`; applying it on
the other machine requires that machine to have built the same game, drawn the
same cards, and assigned the same entity IDs. The ID half of that was fixed
(`G.card_list`, in `23267e3`); the shuffle half is this.

Stage C inherits the same requirement, and the user note already in that
section says exactly this.

## The fix

Carry a small PRNG in the engine and stop borrowing the host's.

- One module, `game/rng.lua`, below the presentation line: `rng.seed(n)`,
  `rng.int(n)` (1..n), maybe `rng.shuffle(list)`.
- Any small, well-specified, integer-only generator with a published test
  vector. **Pick one with a reference implementation to check against** —
  reproducibility is the entire point, so "it looks random" is not the bar.
  Avoid anything relying on floating point, which reintroduces the portability
  question one layer down.
- Replace every `math.random` **below the presentation line**. There are
  exactly three: `zones.shuffle`, `actions.designated`'s `random` quantifier,
  and `destroy`'s `random.` — plus `math.randomseed` in `flow.init`, which
  becomes `rng.seed`.
- **Leave `fx.lua` alone.** Its several dozen `math.random` calls are particle
  jitter: presentation, per-frame, and deliberately *not* reproducible. Seeding
  them would make every explosion identical and would consume draws that game
  logic must not depend on. The line between the two is exactly the
  presentation line the module map already draws.
- The generator's state is one integer, so it must **join the snapshot
  protocol** or undo will replay a different shuffle than the one it is
  undoing. Cleanest: keep it as a stat on the injected `system` card, which is
  already snapshotted, already restored by undo, and already the home for
  engine bookkeeping (invariant: prefer a stat on the injected cards).

## Done when

- `luajit tests/run.lua` and `lua5.4 tests/run.lua` produce **the same golden
  transcripts**, and the skip in `tests/run.lua` is deleted.
- No `math.random` remains below the presentation line.
- Undo across a shuffle replays that shuffle identically.

## Why do it before 02 stage B rather than as part of it

It is small, it is isolated, it has an exact pass/fail test (the two
interpreters agree), and it removes a caveat from the test suite that is there
right now. Stage B is a serialization project; bundling a PRNG rewrite into it
means debugging two unrelated things through one symptom — "the other machine
disagrees" — which is the worst possible signal to debug against.
