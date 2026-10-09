# 34 — An opponent

**Status:** steps 1–3 shipped. `game/opponent.lua` is the move list, a seat that
plays from it, and a search scored by the game's `bot` section; the title screen,
`bot <seat>` in the CLI and `o` in the GUI turn it on.
**Size:** every version after this is a design question about where the thinking
lives.

> *We could also put some AI logic in there for single player gameplay.*
> — the board-game opponent kind, not the LLM kind.

## What step 2 cost, which was not the opponent

A random opponent really is `M.legal()` and one `math.random`. The work was all
in the two things around it.

**The move list was a test's, and an interface's list has to be complete.** The
terminator only ever played six games that happen to be one seat and no stack,
so the list was the hand plus the abilities of cards on a grid. Pointed at the
other eleven it stalled in three of them within twenty steps, each for a
different missing kind of move: a response window (`window_locked` refuses
everything else, so the only moves are `usable_reactions` and a pass), a place
with an ability (`usable_zone_abilities` — how a deck is drawn from, which is
half the corpus), and a card whose zone the phase does not name (Lost Cities
plays out of `choice`, not `hand`). It asks `flow.can_play` of every card now
rather than walking one zone, which is also what made the offscreen question go
away: an offer zone is offscreen and is exactly what an overlay phase is about,
so the engine's own gates are the authority and the list adds none of its own.
The one exception is the system column — Save, Menu, the event log — which
`flow.is_system_card` already names.

**A claimed seat is what hides the opponent's hand, and it was also what stopped
the opponent moving.** `net.unattended(fn)` is the answer: a scoped latch saying
this machine is moving for a seat nobody is sitting at, restored even when the
body raises for `zones.as_seat`'s reason. It is why `opponent` requires `net`,
which no engine module may — an opponent is an interface, and that is the line
it sits on.

## Three bugs it found, all in the same shape

Each is a rule the engine states somewhere and enforces somewhere else, so only
something that does not come through a mouse could reach it.

- **A seat claim outlived its game.** Sitting as North and loading another game
  left every move refused with nothing on screen saying why. `zones.watching`
  had already been taught this for the eye; `may_act` had not, and a name check
  would not have been enough — the second game may have a North of its own. A
  claim belongs to the game it was made in, so `claim_seat` records which.
- **`flow.can_play` never asked what a zone is `use`d for.** The rule lived in
  hit-testing (`zones.card_at`) and in the renderer, so the top card of a
  face-down deck was playable to a script, the debug API, the network and an
  engine seat. Flow is the single legality gate, which has to mean this one too.
- **`play.lua` stopped reading zones when [28](28-a-zone-by-its-parts.md)
  landed.** Five `zone_type` reads left over from the split, all silently false:
  no board for chess, no pile counts, no `a <slot>`, and a hand found by a
  fallthrough. It had never had a way to use a place's ability either, so from
  that prompt half the corpus could not finish a turn.

## Step 3: a bot the game file values

Asked for 2026-10-04 for Spellstorm ("a valuation logic and a brute force
approach ... okay if it's mediocre"), and settled with the user: **one bot, one
algorithm, and the game file says only what a position is worth** — no named
bots, no per-bot logic. Documented in AUTHORING.md, *An opponent the engine
plays*. What it cost that the docs do not say:

- **Scoring right after the move scores nothing in Spellstorm.** A card goes face
  down and nothing moves until both have played. So a try plays on, random moves
  for everybody, until the round turns. The guess test found the other edge: in a
  game whose round never turns, the rollout plays the whole hand and every first
  move scores alike.
- **Undo is not a rehearsal.** A tried move checkpoints, and two hundred of them
  push the player's own undo off MAX_HISTORY. `flow.rehearse` keeps the stack it
  found and fires no hook.
- **The hooks a try fires are the screen's.** `zones.on_change`, `on_stat_change`
  and `on_effect` record a run to play back, and undo's `on_reset` clears it.
  `opponent` mutes the four for the search, and `net.unheard` keeps tries off
  the wire.
- **Not cheating needed no word.** Zone `visibility` already says what a seat
  cannot see; the bot deals it again before every try.

Against random play over six Spellstorm games it won five; random against random
splits about evenly. A decision was 0.5–2 s of CPU at four tries a move. Halving
the field each round instead (every move once, the better half twice, up to 16)
took Spellstorm to 0.15 s mean, 0.9 s slowest, and won 3 of 4 against random;
`M.BUDGET` stops any decision at 5 s. `tools/bot_match.lua` measures a game.

## Left

1. **The search runs on a second engine**, linked like a remote player
   (`botlink`, `botpeer`): a love.thread on desktop, wasmoon in a Web Worker in
   the browser. Measured: desktop, Spellstorm via the menu, 60 s under xvfb —
   engine turns 0.48 s mean, 1.57 s max, no frame over 33 ms; headless Firefox
   against the built image — the worker answers in 2.0 s cold and moves 1.6 s
   later. Not yet clicked through in a real browser tab. Two costs of being a
   peer: undo stops at the engine's last move (an applied state clears it), and
   a game against the engine cannot also be online. Tried first and dropped: the
   search in slices of a frame (~2x slower to decide), and a thread answering an
   index into a seeded move list (desktop only).
2. **`per_phase` is unmeasured.** Spellstorm's gain override reads sensible and
   nobody has watched it gain.
3. **Puzzle Strike, Codex and Ghost Stories have a `bot` section** (2026-10-09).
   Against random play: Puzzle Strike 17 of 18 (gem piles cubed, the bag's
   average price), Codex 10 of 10 (bases, board, hero levels, a worker curve).
   Ghost Stories loses every night still — 6 to 14 ghosts exorcised where random
   play gets none, then the village falls; the rollouts are random, and an
   exorcism is a walk, a roll and a choice of dice that random play rarely
   finishes. Splendor and Lost Cities have an obvious score and no section yet;
   The Crew is cooperative like Ghost Stories. Measured with
   `tools/bot_match.lua`. What the matches found besides: a phase pushed inside
   `each_seat` went to the wrong seat (Oren's potions), a game's button in the
   system column was not a move (Spellstorm's "Unplayable hand"), rules only a
   phase walks were clickable (Spellstorm's Resolve, Ghost Stories' haunting),
   and three ways for a bot to stall a turn it feared to end. Open: Codex's
   Overpower opens `spill` with nothing left to hit and no way out.
4. **The rollout opponent is random**, so the bot plans against a fool. Playing
   the rollout with the bot itself is the next step up and costs TRIES² time.
5. **Only the minimum targets are chosen**, so an optional target is never
   taken, and a target is picked at random once per move rather than tried.
