# 34 — An opponent

**Status:** step 1 shipped — `game/opponent.lua` holds `M.legal()`, every move
available right now as closures, and the test harness is its second caller
rather than its owner. **Size:** every version after it is a design question
about where the thinking lives.

> *We could also put some AI logic in there for single player gameplay.*
> — the board-game opponent kind, not the LLM kind.

## The substrate is `game/opponent.lua`

`M.legal()` returns every move available right now as closures: the cards in
hand `flow.can_play` allows (targets filled from `targeting.eligible`), every
offer card while an overlay is up, and every `flow.usable_abilities` on every
card standing on a grid. **A random opponent is that list and one
`math.random`** — the terminator has been playing whole games with it all along.

Everything harder is choosing *which* move rather than finding the moves.

The move itself was verbatim, and the suite passing unchanged is the check that
nothing was lost. It reads `flow`, `zones`, `targeting` and `cards` — the same
four modules the interfaces use — so an opponent is another interface, not a new
layer. **[Assumption: still unchecked, because nothing yet drives it from a
seat — whether an opponent calling `flow` directly fights `net.lua`'s wrappers,
which intercept `play_card`, `activate`, `react` and `undo` to decide whether
this seat may act. A local opponent taking a seat is exactly the case those
wrappers were written to refuse, so this is step 2's first surprise.]**

## The three versions, and the honest gap between them

| | What it does | What it costs |
|---|---|---|
| **Random** | picks uniformly from `legal_moves()` | the function, moved |
| **Greedy** | picks the move that most improves a number the game names | a way for a game file to say which number, and to score a move without committing to it |
| **Searching** | looks ahead | undo already exists, and a search is undo used in anger |

The gap between random and greedy is the whole track. Random needs nothing from
the format; greedy needs the game file to say **what winning looks like as a
number**, and that is a word the format has not got.

Two things it might already be, and neither quite fits:

- **`end_conditions`** say when the game is over and who won, but they are
  yes/no. "Am I closer to eight shards" is not a condition, and turning one into
  a gradient is inventing a second meaning for it.
- **`computes`** name a number with a formula, which is exactly the right shape
  — Spellstorm could already write `computes: { my_shards: ... }`. What is
  missing is nothing about computing it; it is *saying which compute the
  opponent should climb*, which is one field and therefore a decision to take
  with the user rather than in passing.

**[Assumption: that a single number is enough to play any of the shipped games
badly-but-legally is untested. Splendor and Lost Cities have an obvious one
(score); Puzzle Strike and Codex plainly do not, and The Crew is cooperative and
wants a different shape entirely.]**

## Where it does not go

**Not in the game file as a script.** DESIGN.md's whole schema section exists to
keep the format from becoming a programming language, and "how to play well" is
the most programming-shaped thing there is. The format's job is to say what
winning is; picking moves is the engine's.

**Not per game.** An opponent that has to be written once per game is a second
copy of every game's rules, and it will disagree with the first copy. Whatever
lands has to be one algorithm reading what the game file already says.

## Why it is worth having beyond single-player

- **It is a test.** The random terminator already catches softlocks nothing else
  will; an opponent that plays a game *badly but legally* for a thousand games
  is the same instrument pointed at balance and at rules that cannot be
  satisfied.
- **It is how a game gets tried.** Every game in `game/games/` is currently
  played by one person moving both seats, which is a poor way to find out
  whether a rule is any good.

## Order

1. ~~`legal_moves` out of the test harness~~ — **done**, as `game/opponent.lua`.
2. A random opponent taking a seat, and whatever `net.lua`'s wrappers turn out
   to say about that.
3. Only then the question of what a game file says about winning, which is where
   this track stops being small.
