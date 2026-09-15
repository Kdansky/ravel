# 34 — An opponent

**Status:** steps 1 and 2 shipped. `game/opponent.lua` is the move list *and* a
seat that plays from it; `bot <seat>` in the CLI and `o` in the GUI turn it on.
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

## The three versions, and the honest gap between them

| | What it does | What it costs |
|---|---|---|
| **Random** | picks uniformly from `legal()` | shipped |
| **Greedy** | picks the move that most improves a number the game names | a way for a game file to say which number, and to score a move without committing to it |
| **Searching** | looks ahead | undo already exists, and a search is undo used in anger |

The gap between random and greedy is the whole track. Random needs nothing from
the format; greedy needs the game file to say **what winning looks like as a
number**, and that is a word the format has not got.

Two things it might already be, and neither quite fits:

- **`end_conditions`** say when the game is over and who won, but they are
  yes/no. "Am I closer to eight shards" is not a condition, and turning one into
  a gradient is inventing a second meaning for it.
- **`computes`** name a number with a formula, which is exactly the right shape.
  What is missing is nothing about computing it; it is *saying which compute the
  opponent should climb*, which is one field and therefore a decision to take
  with the user rather than in passing.

**[Assumption: that a single number is enough to play any of the shipped games
badly-but-legally is untested. Splendor and Lost Cities have an obvious one
(score); Puzzle Strike and Codex plainly do not, and The Crew is cooperative and
wants a different shape entirely.]**

A second thing the same word would fix, found by watching it play: a random seat
will happily choose **"With a friend, online"** out of a game's own opening menu,
claim a seat and hand the game to nobody. The card is content and looks like
every other move from here. Nothing in the file says a move is about the session
rather than the game — the same gap as not knowing what a move is *for*.

## Where it does not go

**Not in the game file as a script.** DESIGN.md's whole schema section exists to
keep the format from becoming a programming language, and "how to play well" is
the most programming-shaped thing there is. The format's job is to say what
winning is; picking moves is the engine's.

**Not per game.** An opponent that has to be written once per game is a second
copy of every game's rules, and it will disagree with the first copy. Whatever
lands has to be one algorithm reading what the game file already says.

## Left

1. **Where the switch belongs.** `o` and `bot <seat>` are an interface's
   affordances, and the invariant says *when in doubt, decks and cards* — which
   is how networking is offered ("a two-player game deals a card that says play
   this with a friend"). An engine opponent wants the same, and that needs an
   action word nobody has agreed yet.
2. **A better-than-random pick**, which is where the number above comes in.
3. **Only the minimum targets are chosen**, so an optional target is never
   taken. Nothing in the corpus turns on it.
