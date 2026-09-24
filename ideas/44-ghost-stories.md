# 44 — Ghost Stories

**Built and playing**, four seats at Initiation level: `game/games/ghost_stories.json`
out of `tools/make_ghost_stories.py`, all 55 ghosts and all 10 incarnations,
tested in `tests/integration/ghost_stories.lua`. The rules are transcribed in
[ghost_stories/rules.md](ghost_stories/rules.md) — card by card, off the scans
in `ideas/Ghost Stories/` — and nothing in the generator invents one.

## What the game asked for and did not need

**One grid for the village and the four boards.** The nine tiles sit in the
middle of a 5×5, the twelve ghost spaces run along its edges, and the four
corners hold a plaque apiece. Every "where" in the rulebook then falls out of
two patterns: a Taoist walks to a tile `adjacent` to the one it stands on, and
exorcises a ghost `orthogonal` to it — one space from an edge tile, two from a
corner, none from the middle, and not one of those three said anywhere. Four
separate board zones would have bought "my board is full" cheaply and cost the
whole of that, in four copies of every reach rule.

**The Taoists ride their tiles.** Four figures on one tile is what the rules
want and what a square cannot hold, so a Taoist is a rider
(`attach_to_target`) and `mine.attached_to.orthogonal` read from a ghost *is*
"is one of my Taoists facing me".

**The plaques answer what a pattern cannot.** A corner card with a `row3` or
`col3` pattern names the three spaces beside it, so "this board is full" is
`count:ghost@row3 >= 3` asked by the board itself. It also stops a ghost being
laid in a corner, which is the other half of why the corners are not empty.

**`to_haunt` is the whole interface to haunting.** A haunting figure reaching
the board, a Curse die, and a ghost's own arrival all set it; six rules read it
— three distances on each axis, each asking that the tiles nearer than it are
already dark — and a ghost still holding it when they are done is the village
falling. Three sources, one resolution, and the "first *active* tile in front"
is the ordering of the six rather than a search.

**One action tray for the table.** The buttons a turn is made of — pass, roll,
give up, spend the Yin-Yang, take the reward — are every one of them about
whoever is *up*, and say so: `mine.player`. A `copies: "per_seat"` tray would
be four copies of eight cards where eight will do, and the three copies nobody
is looking at are not merely waste, they are three more places for a rule to
drift. **A per-seat zone is for what a player keeps** — their tokens, their
figure, their Buddha — and a shared one for what the game asks of whoever is
playing.

## Two things the engine taught this game

**A pattern read off an unowned card is flipped for whoever is up.** Only the
first seat faces forward, so `[[0,1]]` is "up the board" on south's turn and
"down" on west's. Every pattern in the file names both directions and lets the
far one fall off the board. Folded into `AUTHORING.md`.

**An automatic phase does not hand the turn over.** `seat: "next"` is read
where a hand is dealt, and a Yin phase deals nothing, so the turn is passed by
each seat card naming the one that follows it and `set_active_seat`. Folded
into `COOKBOOK.md`.

## Left, in the order they are worth doing

1. **The two-ghost exorcism from a corner tile.** One roll, the dice split as
   the player likes, both ghosts gone. The engine has no trouble with two
   targets; what it has no way to say is that a die spent on one is not
   available to the other, since what an exorcism is worth is a `compute` read
   fresh each time. Wants the dice to be *consumed* — a face moved out of the
   tray — which is a third zone and an ordering question.
2. **Tao tokens lent by Taoists on the same tile.** `count:<colour>@mine.spent`
   is the only term that would change: it would have to reach every seat whose
   Taoist shares a tile with the one acting, which is `attached_to.host_of.
   mine.taoist` and an owner word the scope grammar does not have.
3. **The eight Taoist powers**, and with them the four ghosts that switch a
   board's power off. Two of the eight (Bottomless Pockets, Dance of the
   Spires) are a line each; Second Wind and Heavenly Gust are a second pass
   through the Yang phase, which is routing; Strength of a Mountain is a fourth
   die, which is a fourth bag and a fourth term in five computes.
4. **The captive Tao die.** "Exorcisms roll one die fewer" is one die not
   dealt, and the roll is a fixed list of actions with no if in it — which a
   gate in its `needs` now says ([46](46-one-list-of-conditions.md)), not a new word.
5. **The Uncatchable.** It may only be exorcised standing on a Buddha, and a
   Buddha here occupies the square and eats whatever is laid on it. Faithfully
   it wants a Buddha that is a *rider* on a space, which is the same want as
   [15](15-many-on-one-square.md)'s "a number on a square". Shipped exorcisable
   like any other incarnation rather than unwinnable, and the card says so.
6. **The Nameless's white faces.** "The white sides no longer count as wild" is
   a term dropped from five computes while one card is in play, and a compute
   is bound before it is read. Every other global state in this file is a
   condition on a tag, and this is the one that is arithmetic.
7. **A resistance printed in several colours** spends the same white face on
   each of them, because the four conditions are read independently. Wrong for
   Hope Killer and the Nameless and nobody else; the same fix as item 1.
8. **Neutral boards**, for one to three players. The rulebook's own appendix:
   a board with nobody behind it plays the first two steps of its Yin phase and
   no Yang phase, and the players carry Power tokens to borrow its power. It is
   [09](09-composition.md)'s seat-count module in its natural habitat, and the
   reason this file ships at four seats.
9. **The village laid out at random.** Nine tiles into nine squares in a
  shuffled order; `setup.place` says which card goes where and has no way to
  say "these nine, in any order". Cheap, and it changes how a game opens.
