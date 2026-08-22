# 21 — Lost Ruins of Arnak

**Status:** not started · **Size:** large · **Depends on:** worker placement
has no equivalent anywhere in the engine today — this file's real job is
finding out what that gap costs

> *Third of three deckbuilder candidates — a deckbuilder fused with worker
> placement and a personal exploration board, from the current generation of
> hybrid euros.*

**Objective.** Arnak layers a deckbuilding resource engine on top of worker
placement (limited action spaces that unlock over the game as you spend
workers to open "gates") and a personal expedition board that each player
uncovers tile by tile, revealing terrain, idols and guardian encounters as
they go. Fame and resources both matter, the game runs five rounds, and
endgame scoring pulls from cards, idols and research tracks. This is the
deckbuilder candidate most likely to expose something structural: worker
placement — an action space a limited number of players may occupy per round
— has no equivalent anywhere in ravel today, and a personal fog-of-war board
is a variant on the "board that grows as you play" question Hive and
Carcassonne already raised in the earlier board-game survey.

---

## Stage 1 — the rules document

**Deliverable:** [ideas/arnak/rules.md](arnak/rules.md), sourced and marked
the same way as [19](19-mage-knight.md)'s.

**Done.** Built from the official CGE rulebook PDF (October 2020, fetched in
full from `filemanager.czechgames.com` and read end to end via `pdftotext`
after the publisher's own `czechgames.com/files/rules/...` URL turned out to
redirect to a marketing page rather than the PDF), plus two secondary
sources for a handful of numbers whose icons didn't survive text extraction
(Board Game Arena's rules-help page, BGG forum threads). Three corrections
to the objective's own framing turned up and are worth flagging up front,
the way Puzzle Strike's Wound/Crash corrections were:

1. **The resource types are Coin, Compass, Tablet, Arrowhead and Jewel** —
   not gold/wood/stone/obsidian. The objective's guess was simply wrong;
   the real five map cleanly onto the same vocabulary regardless (rules.md
   §3).
2. **There is no "gate" component anywhere in the rules** — the word
   doesn't appear once in the rulebook. The mechanic that actually unlocks
   new worker-placement spaces is **Discover a New Site**: pay a region
   cost plus a per-position cost to flip one of a fixed number of
   pre-printed, mostly-hidden board positions face up. See rules.md §7.
3. **There is no personal exploration board, no tile-by-tile private
   reveal, and no terrain-crossing movement cost.** The objective's
   framing ("a personal expedition board that each player uncovers...
   revealing terrain") describes a game Arnak isn't. There is exactly one
   shared island board, fixed in size from the start, with a bounded number
   of printed-but-undiscovered positions that get revealed (not created) as
   the game goes — see rules.md §8, and Stage 2 below for why this matters.

Every number that couldn't be cross-confirmed is flagged inline and
collected in rules.md §13.

## Stage 2 — what it names that the engine lacks

| Arnak rule | Ravel today |
|---|---|
| 5 fixed rounds; strictly sequential clockwise turn order, one main action + free actions per turn, pass-and-skip | the reserved `round` stat, ordinary phase cycling with `seat: "next"`, a `pass_card` — **exists** |
| Personal deck: 2 Funding + 2 Exploration + 2 Fear starting cards, drawn to a hand of 5 at round start | `per_seat` deck/hand zones, `draw_from` — **exists** |
| A card played either for its printed effect *or* its travel value, never both | the same "two distinct things a card can do" shape `abilities` already covers for Mage Knight's basic/powered split — **expressible** |
| Round-end reshuffle: play area + unkept hand cards shuffled *together*, then appended to the *bottom* of the deck, below any cards bought mid-round, **above** whatever the deck hadn't drawn yet | not `refill_when_empty` (Puzzle Strike's finding applies again — a personal pile that changes over the game, not a fixed recipe) — **expressible**, but needs `shuffle` applied to the *returning batch alone* before `return_to` appends it, and depends on `return_to` inserting at the deck's bottom rather than its top; see below |
| Five resource types (Coin, Compass, Tablet, Arrowhead, Jewel), banked on a player's own board, spent as flat token costs on cards/guardians/research | ordinary stats on the player card plus `cost`/`needs` maps — **exists**, confirmed and moving on |
| A second currency: a card's printed travel value, spent by discarding the card face-up (ignoring its effect) rather than by paying a stat | the `"sacrifice:<tag>"` cost family (consume a card as payment, not a stat) — **expressible** |
| Card row split by the moon staff (artifacts vs. items), each round shifting to reveal one more artifact slot and one fewer item slot, refilled from the matching deck, two cards exiled every round regardless of purchases | a shared (non-`per_seat`) zone plus `card_stats.cost`, ordinary `play.action` — **exists/expressible** |
| **Worker placement**: 2 archaeologists per player (fixed, never grows), a site's space is occupied by at most one figure across all players for the rest of the round, freed when figures return home at round wrap | **resolves almost entirely in ravel's favor** — see below |
| Some sites print **two** archaeologist spaces at different costs; either can be filled by either player, even both by the same one | authored as two separate site-space entities, each with its own fixed cost — **expressible** (content, same texture as Mage Knight's sideways-play repetition) |
| **Discover a New Site**, the actual "gate": pay a region cost plus a position's own cost to reveal one of a fixed number of pre-marked, mostly-hidden board positions | a fixed-size shared `grid`, most slots pre-filled, remainder hidden until a `fill:zone:card:n`-style reveal into a player-chosen open slot — **expressible**, see below |
| A guardian appears automatically, immediately, whenever a site is discovered; it does not block digging; only consequence is a Fear card if an archaeologist returns home from its site still guarded | an ordinary `turn.action`/round-boundary check plus a Fear-card gain — **expressible** |
| **Overcoming a guardian**: pay the flat resource cost printed on its tile — there is no strength stat, no roll, no comparison of any kind | an ordinary `cost` gate, identical in shape to buying a card — **exists**, and simpler than the objective assumed |
| Idol: found on site discovery, kept face down, 4 player-board slots, each fillable once as a free action choosing 1 of 5 printed effects, scores 3 points always plus a per-slot bonus if left empty | the sub-card-choice / offer pattern already documented (choosing is playing) — **expressible** |
| **The island board**: one shared board, fixed size from the start, no per-player copies, no terrain-crossing movement cost | **resolves entirely in ravel's favor, and differently from Mage Knight's map** — see below |
| Research track: two tokens (notebook may never sit ahead of the magnifying glass), a **branching graph** of positions and cost-bearing edges, per-row effects, first-arrival-only bonus tiles | a small authored graph of position cards/edge-cards, not a spatial grid — **expressible**, see below |
| Assistants: a separate per-player ability pool, exhausted (turned sideways) on use, refreshed for everyone automatically at round wrap | `activate.cost: {"exhaust": 1}` plus the engine's own round-wrap ready-sweep — **exists**, an exact match |
| Fear cards: no effect, only travel value, -1 point each at game end, gained automatically at round cleanup | an ordinary token-tagged card plus a round-boundary gain and an end-scoring tally — **expressible** |
| Endgame scoring: research-row position, temple tiles, idols + empty-slot bonus, guardians flat 5 each, printed card points, Fear penalty; **no leftover-resource or hand-size penalty at all** | a scoring phase chaining `stat_gain`/`stat_damage` per category, the Puzzle Strike/Lost Cities pattern — **exists/expressible** |

### Worker placement: the whole reason this file exists, worked through concretely

**The exact shape, confirmed from the rules, not assumed:** a *space* — not
a site — is occupied by at most one archaeologist figure, from any player,
for the rest of the round; freed for everyone at the next round's wrap.
Most sites print exactly one space. A handful (confirmed: the 5 starting
sites, scaled down by blocking tiles at low player counts; unconfirmed
whether any discovered site ever does) print **two**, at two different
costs, and either space may go to either player — even both to the same
one. This is ordinary worker placement with a well-known wrinkle (multi-slot
spaces exist in Agricola and plenty of others), not a different shape.

Two ways to map "claimed until round end, free again next round" onto
ravel's existing vocabulary, and it's worth ruling one out explicitly rather
than picking the first that fits:

**Model A — exhaust the worker.** The stub's own hint: give each player two
archaeologist-token cards, `activate.cost: {"exhaust": 1}` each, refreshed
by the engine's own round-wrap sweep. This turns out to be the *wrong* half
of the mechanism to exhaust. A Dig action needs to ask "is this specific
site-space still open" — a question about the **space**, not about which
particular worker last used it — and `predicate.lua`'s subject vocabulary
has no way to read a card's own exhaustion state back as a condition
(subjects are stat/tag/`count:`/`card:`-based; "is this exhausted" isn't
one of them). Exhausting the worker token answers "have I got a spare
archaeologist," not "is this space free" — the two are genuinely different
gates in the real rules (both must hold independently: an archaeologist
figure available *and* an unoccupied space), and Model A only naturally
gives you one of them.

**Model B — exhaust the space.** Model each site-space as its own small
card sitting in the shared board's zone, with `activate.cost` equal to its
own printed resource price and `"exhaust": 1` layered on top. Activating it
is "Dig at a Site": pay the price, get the effect, and the card goes
greyed-out for the rest of the round — DESIGN.md's Costs section already
describes this outcome word for word ("exhausts it — greyed out, unusable —
until the round wraps and readies every card again. One activation per card
per round, as is proper"). No archaeologist entity is even required for
this half: *who* dug there is simply *whichever seat's turn it was when the
card got activated*, exactly like any other shared-board ability card
(a market row, a shared building) — the engine already tracks that for
free. The other gate — "have I got a spare archaeologist" — is an ordinary
round-scoped counter stat on the player card (`archaeologists_placed`,
incremented by each Dig/Discover action, gated `at_most: 1` before
incrementing to 2, reset to 0 by an ordinary action on the round's first
automatic phase) — the same shape the engine's own `plays` stat already
uses for "at least one card played," just capped instead of floored. Both
halves compose independently and correctly, matching the real rule's two
orthogonal constraints exactly.

**What this costs, and what it doesn't.** Zero new engine primitives:
`exhaust`, round-wrap readying, an author-declared capped counter stat, and
ordinary `cost` are all already shipped and proven (chess, castle, kingdom).
What it does cost is authoring weight: a fixed `cost`, declared statically
per card or ability the way ravel's `cost` always is, cannot itself express
"whichever of several destinations gets chosen" — so "Dig at a Site" can't
be one generic parametrized action across ~21 site positions (5 starting +
10 Level I + 6 Level II, plus a handful of second spaces). It has to be one
small card per site-space, each with its own fixed printed cost. That is
not a workaround bought at a discount — it is the natural translation, since
Arnak already represents each site as one physical tile; "one card per
site" is the obvious 1:1 mapping, not an inflated one, and it's the same
"repetitive, not a missing primitive" texture Mage Knight's sideways play
and Puzzle Strike's Combine table already established. **Net finding:**
worker placement, worked through concretely rather than assumed, is not a
genuine engine gap at all. It is a combination of two already-shipped
idioms nobody has combined this way yet, plus a content-authoring bill —
smaller in kind than either of the other two candidates' worst gap.

### The island board resolves in ravel's favor, and not the way Hive/Carcassonne/Mage Knight did

The objective's own framing — "a personal fog-of-war board... a variant on
the 'board that grows' question" — turns out not to describe this game.
Rereading the rules directly (rules.md §8) settles three things Mage
Knight's writeup couldn't take for granted: the board is **shared**, not
personal; its **set of possible positions is fixed and printed from
setup**, not unbounded; and "discovery" **flips a hidden position to a
face-up tile**, it does not create a new position or extend the map's
edge. There is no hex adjacency, no per-hex terrain cost, and no path a
figure crosses to get anywhere — "Dig at a Site" and "Discover a New Site"
are both direct placements onto a named target, gated only by that
target's own flat printed cost. That is structurally a fixed-size `grid`
zone, most cells pre-filled at setup, the rest hidden until a `fill:`-style
reveal (from a shuffled per-region stack, into a slot the discovering
player chooses among the still-hidden ones) puts a face-up card there —
**expressible** with the exact `target: {"type": "slot"}` / grid-fill
machinery chess and every other grid game already exercise, just not yet
combined with a *hidden-until-revealed* cell in any shipped game. Compare
directly to [19](19-mage-knight.md)'s hex map: that gap is real because the
map's *extent itself* grows without bound, which no `[cols, rows]` grid can
represent without changing size at runtime. Arnak's board never changes
size — only which of its fixed cells are face up. Same surface vocabulary
("exploring," "revealing"), a different shape underneath, exactly the
caution the stub asked to check for.

### The research track is a small graph, not a spatial board — also not a gap

Two tokens, a branching path of positions connected by cost-bearing edges,
per-row effects, first-arrival bonus tiles. This has no `[cols, rows]`
rectangle under it at all — it is closer to a tech tree than to a board —
so it never touches `geometry.lua`'s grid math, hex or otherwise. It maps
cleanly onto discrete positions (small marker cards or zone slots) and one
small authored card per edge: `needs` that a token currently sits at the
edge's start, `cost` equal to the bridge's printed price, `action` moving
the token to the edge's end and resolving that row's effect. Roughly 20–30
edges across two branching paths, the same repetitive-but-mechanical
authoring bill as the site-spaces above, and the same "castling: a card
with fixed destinations, not a move pattern" idiom AUTHORING already
documents for exactly this shape (named destinations, not a direction).
**Expressible**, no new vocabulary.

### Guardian strength checks are simpler than the stub assumed

Confirmed directly from the rules (rules.md §7): overcoming a guardian is a
flat resource-token payment printed on its own tile — there is no attack
total, no comparison of any kind, nothing for `predicate.lua` to evaluate
at all. It is the *same* `cost` gate as buying a card, not even a `needs`
comparison. **Exists**, and more trivially than the stub's "strength/attack
total vs. a fixed guardian number" framing expected.

### The deck-reshuffle order is a small, confirm-before-building nuance, not a gap

Round cleanup shuffles the returning play-area-plus-kept-hand batch
*by itself*, then appends it below whatever the deck hadn't drawn yet this
round (a deck doesn't always fully drain, since a kept hand card reduces
how much gets redrawn) — a plain `shuffle:` on the whole deck would wrongly
re-randomize the untouched remainder too. The fix is ordinary
(`shuffle:play_area` in place, then `return_to:play_area:deck` to append the
already-shuffled batch), contingent only on `return_to` inserting at the
deck's bottom rather than its top — a detail worth confirming in code
before building, in the same spirit as Puzzle Strike's
`refill_when_empty`-is-the-wrong-tool finding, and no larger than it.

### Verdict

**Arnak needs zero new engine primitives — a smaller ask, at the engine
level, than either of the other two candidates — but the largest
content-authoring bill of the three.** Every row in the table above lands
on *exists* or *expressible*; even worker placement, the row this whole
file was written to interrogate, resolves into a composition of two
already-shipped idioms (per-card `exhaust` for space occupancy, an
author-declared capped counter stat for the worker-count cap) rather than
into anything new, once worked through against what a space actually is
and what actually needs asking. That is a materially different outcome
than the stub predicted ("no equivalent anywhere in the engine today") and
worth stating plainly: the stub was right that no *shipped game* combines
these idioms this way yet, and wrong that the combination needs new engine
code. Weighed against the other two: [20](20-puzzle-strike.md) is still the
fastest path to a table-ready build — the smallest total scope, and its one
real gap (acting out of turn) is a `flow.lua` legality-check change, the
only one of the three candidates that needs *any* engine code touched at
all. [19](19-mage-knight.md) trails both by a wide margin even after
amputating its hardest pieces — hex geometry and an unbounded growing map
are gaps content authoring cannot route around, and nothing here changes
that. Arnak sits in an unusual spot relative to both: cheaper than Mage
Knight by every measure, and cheaper than Puzzle Strike specifically at the
engine layer (nothing to touch in `flow.lua` or anywhere else below the
presentation line) — but its content surface is the largest of the three,
comparable to LoR's "no generator, hand-author every template" scale and
arguably past it once every site-space, guardian tile, idol-slot effect,
research-track edge, and the 75 item/artifact cards are counted
individually. **Rank it first on engine risk, last on authoring volume** —
and since this ladder has consistently measured "does the engine need new
code" rather than "how many JSON entries does it take," that puts Arnak
ahead of Puzzle Strike on the axis this whole research series actually
cares about, with the caveat that "buildable" and "quick to build" are not
the same claim, and Arnak is the first of the three where they clearly
diverge.
