# Lost Ruins of Arnak — Rules

Czech Games Edition, 2020. Designed by Mín (Květoslav Bílek) & Elwen (Filip
Neduk); the box credits "A game by Mín & Elwen." 1–4 players, ~30 min/player.

**Sources.** Primary source is the official CGE rulebook PDF, fetched in full
from `https://filemanager.czechgames.com/storage/files/lost-ruins-of-arnak/rules/lost-ruins-of-arnak-rules-en.pdf`
(© Czech Games Edition, October 2020, "Rulebook Writer: Jason Holt") and read
end to end via `pdftotext`. Every mechanic and every quoted rule below comes
from that document unless flagged otherwise. Two secondary sources fill a
handful of numeric gaps the PDF's icon glyphs didn't survive text extraction
(they render as images, not characters, so `pdftotext` silently drops them):
Board Game Arena's `Gamehelparnak` rules-help page (starting resources by
seat order), and BGG forum threads on the idol-slot point values. Anything
sourced that way, or not sourced at all, is flagged inline and collected in
§13.

---

## 1. Overview

Each player leads an archaeological expedition to a newly discovered island.
Over **5 rounds**, players place a small, fixed number of worker figures on
a *shared* action board to gather resources and explore, buy item/artifact
cards into a personal deck (deckbuilding, Dominion-shaped: buy → play →
reshuffle), and advance two tokens up a branching research track. The game
ends after round 5; highest total score wins.

**Turn order is fixed and strictly sequential, never simultaneous.** "The
player with the starting player marker starts. Players take turns clockwise
around the table." One player takes an entire turn (one main action, plus
any number of free actions), then the next player does, and so on; a player
who has nothing left to do **passes**, and is skipped for the remainder of
the round while everyone else keeps cycling until all have passed. There is
no hidden simultaneous commitment step anywhere in the base game (contrast
Mage Knight's simultaneous private Tactic-card pick each round) — this is
the property that makes the game reachable by a turn-based-only engine at
all, and the rulebook states it in as many words.

---

## 2. Round structure

Each of the 5 rounds runs identically:

1. **Draw.** Every player draws from their own deck until their hand holds
   5 cards. (Cards deliberately kept from the previous round's hand count
   toward this 5 — see §5.)
2. **Turns.** Starting with whoever holds the starting-player marker,
   players take turns clockwise. A turn is exactly one **main action**
   (choose one of: Dig at a Site, Discover a New Site, Overcome a Guardian,
   Buy a Card, Play a Card, Research, or Pass — §4–§9) plus any number of
   **free actions** (marked with their own icon; can be played before,
   during, or after the main action, without ending the turn).
3. **Pass.** A player who passes takes no more turns this round; the turn
   order continues clockwise but skips passed players. "If you are the only
   player left who has not yet passed, you can take multiple turns in a
   row." The round ends when everyone has passed.
4. **Round cleanup**, all players simultaneously: return both archaeologist
   figures to your own board (gaining a Fear card for each one that was
   sitting on a site still guarded — §7); gather your play area plus any
   hand cards you choose not to keep, shuffle *that batch*, and put it on
   the bottom of your deck (cards you bought during the round are already
   below it, so they are drawn *before* the freshly shuffled batch); refresh
   (un-exhaust) all assistants. The card row shifts (§6) and the starting
   player marker passes one seat to the left.
5. **Advance the moon staff** one space, marking the round number.

Round 5's cleanup is truncated: archaeologists return and Fear is gained as
normal, but steps 2–5 above are skipped entirely — the game goes straight to
final scoring (§12).

---

## 3. Resources — five types, exactly

There is no gold/wood/stone/obsidian economy; Arnak's five physical resource
tokens are:

| Resource | Represents | Primarily used to |
|---|---|---|
| **Coin** | funding | buy Items |
| **Compass** | time/energy spent exploring | buy Artifacts, pay the Discover-a-New-Site region cost |
| **Tablet** | deciphered ancient texts | (mixed into guardian/research costs) |
| **Arrowhead** | weapon remnants | overcome Guardians |
| **Jewel** | talismans of the bird god Ara-Anu | research costs, especially deep ones |

These are **held resources** (banked tokens on a player's own board,
unlimited in principle — "reserve tiles" with a ×3 multiplier exist purely
as a physical-component safety valve for extremely long games, not a cap).
They are spent as flat token costs on: buying cards (§6), overcoming
guardians (§7), and research (§10).

**A second, separate currency exists layered on top: a card's printed
"travel value."** Every hand card shows one of these same five icons (often
just one, sometimes two) as its travel value. Playing a card *for travel*
means moving it face-up into your play area **while ignoring its printed
effect entirely**, and using its icon(s) to pay a **travel cost** — the cost
printed on a site space, or a region's Discover cost. A card can be played
for its effect *or* its travel value, never both. Travel costs cannot be
paid directly from banked resource tokens, with one flat exception: "Hiring
a Pilot" always lets a player spend 2 coins to generate one universal travel
icon ("a plane") that pays any single travel cost. A **Travel Hierarchy**
lets a higher-tier icon pay a lower-tier cost (never the reverse); the exact
tier ranking is on the quick-reference sheet and wasn't reproduced in the
extracted text — flagged in §13.

Fear cards (§9) carry no effect at all, only a travel value.

---

## 4. Your turn, in detail

**Main actions** (exactly one per turn, chosen from): Dig at a Site,
Discover a New Site, Overcome a Guardian, Buy a Card, Play a Card, Research,
Pass. "You always perform exactly one main action per turn" — a turn with
*only* free actions and no main action is not legal; a player with nothing
they want to do must Pass.

**Free actions** carry their own icon and never count as the turn's main
action. Confirmed free actions: playing a Funding or Exploration basic card
for its effect, some item effects, slotting an idol (§8), using a guardian's
boon (§7), using most assistant effects (§11 — the assistant that grants a
buy discount is the one documented exception, itself a main action).

**Buying an artifact from the card row can itself trigger a further
action** (its effect resolves immediately on purchase) — the rulebook is
explicit this whole chain is still one main action, not two.

---

## 5. The personal deck and card play

Each player's deck starts identical: **2 Funding cards, 2 Exploration
cards, 2 Fear cards** (their own basic-card color). Funding cards give a
Coin (effect) or a travel value; Exploration cards give a Compass (effect)
or a travel value; both effects are free actions. Shuffled at game start,
placed face down on the player board, and never reshuffled mid-round — only
at round cleanup (§2 step 4). Deck-out is handled gracefully: "if your deck
does not have enough cards to make a full hand, just draw them all" — there
is no penalty for an empty deck, a hand can legally be under 5.

**A card in hand is played either for its effect or for its travel value,
never both**, and once played it sits face-up in the player's own **play
area** — "basically a spread-out discard pile" — for the rest of the round,
not recycled into the deck until cleanup.

**Exile** removes a card from the game (or from its usual cycle)
permanently: item/artifact cards have dedicated exile piles by their decks;
Fear cards return to the Fear deck instead of leaving play entirely; Funding
and Exploration cards go near the Fear deck. Most exile is one-way.

---

## 6. Buying cards: the item/artifact row

The **card row** is one row of face-up cards split by the **moon staff**
marker: artifacts to its left, items to its right. At setup: 1 artifact face
up left of the staff, 5 items face up right of it (staff itself marks
"round I"). **Each round the staff moves one space right**, so across the
game the visible artifact slots grow and the item slots shrink — deeper
into the game, expeditions find more artifacts and get less support from
the mainland, thematically.

- **Buy an Item**: pay its printed Coin cost; it goes face down onto the
  *bottom* of your deck (so it shows up in a later round's hand, not this
  one, unless a draw effect reaches it).
- **Buy an Artifact**: pay its printed Compass cost; move it to your play
  area; you *may* immediately resolve its effect, ignoring the separate
  "exile-cost" icon printed in its corner (that icon only matters later,
  when the same effect is replayed from hand — see below).
- **Refill**: at the end of a turn that bought a card, slide the row toward
  the staff to open a slot on the outer end and deal a new card of the same
  type into it. If a deck (item or artifact) runs out entirely, that side
  of the row simply stops refilling.
- **Round cleanup** additionally exiles the two cards immediately flanking
  the staff (one artifact, one item) before the staff moves and the row
  refills — a steady, guaranteed one-artifact/one-item churn every round
  regardless of whether anyone bought them.

**Playing an artifact's effect later, from hand, costs an extra Tablet**
(the small corner-icon cost) on top of whatever else the effect asks —
buying it and immediately using it for free is the one-time exception. Item
costs have no such surcharge.

---

## 7. Worker placement: Dig at a Site, Discover a New Site, Guardians

**Each player has exactly two archaeologist figures, fixed for the whole
game.** This count never grows — there is no track, upgrade or card effect
in the base game that adds a third. (Two archaeologist *figures per color*
are provided; the number in active use per player never exceeds two.)

### Dig at a Site

Send one archaeologist from your board onto **any unoccupied space** at any
already-discovered site (the 5 starting sites, plus any Level I/II site
discovered since). "Unoccupied" means literally no archaeologist figure —
and, at 2–3 players, no face-down **blocking tile** (see below) — currently
sitting there.

1. Pay the space's printed **travel cost** (by spending a hand card's
   travel value, per §3).
2. Move your archaeologist figure onto that space.
3. Resolve the space's printed effect (almost always: gain the depicted
   resource token(s)).

**A single site can print one or two archaeologist spaces**, each with its
*own* travel cost — the worked example in the rulebook shows a site with
two spaces where the second costs more than the first; a player may
occupy both spaces of the same site with their own two archaeologists if
nobody else has taken the other one first. If both of a site's spaces are
occupied, nobody else may dig there for the rest of the round. **A space is
occupied by at most one archaeologist figure, from any player**, for the
remainder of the round; occupancy clears for everyone at the next round's
cleanup (step 4, §2) when figures return home — there is no way to reclaim
a space mid-round short of an item effect that explicitly relocates a
figure.

**Blocking tiles scale total board capacity to player count.** They exist
only for the 5 starting sites' *second* space: at 4 players none are used
(all second spaces open); at 3 players, 3 of the 5 are randomly blocked for
the whole game; at 2 players, all 5 are blocked, so every starting site has
room for exactly one archaeologist all game. [Whether any Level I/II site
tile ever prints a second space at all — as opposed to this scaling
applying only to the 5 starting sites — is not confirmed; see §13.]

If both of a player's own archaeologists are already placed on the board,
that player simply cannot choose Dig at a Site (or Discover a New Site) as
their main action until one comes home.

### Discover a New Site — the game's actual "gate" mechanic

**There is no component or rule literally called a "gate" anywhere in this
rulebook** — the word does not appear. The mechanic that opens new
worker-placement spaces over the course of the game is **Discover a New
Site**, and it works like this:

1. Choose to discover a Level I or Level II site (their region costs, paid
   in Compass-flavored travel value, are printed on the shared board — the
   exact numbers weren't recovered from the extracted text, §13). Pay that
   region cost.
2. Choose *which* still-undiscovered site position (in that region) to
   reveal — the shared board prints a fixed number of blank/marked
   positions per region from the start of the game, most undiscovered at
   setup. Pay *that specific position's own* travel cost to move your
   archaeologist there (a second, per-position payment on top of step 1's
   flat region cost).
3. Take the idol sitting at that position (§8) and resolve its effect.
4. Flip the top tile from that region's face-down site-tile stack (Level I
   stack: 10 tiles; Level II stack: 6 tiles — see §13 for which numeral maps
   to which icon) face up onto the board position, and immediately resolve
   the newly revealed site's own effect.
5. Draw the top tile from the guardian stack and place it face up on the
   new site, awakening a guardian there (see below).

Once discovered, a site behaves exactly like one of the 5 starting sites
for all future Dig-at-a-Site purposes — permanently, for every player, for
the rest of the game. **The board's set of possible site positions is fixed
at setup, printed on the shared board itself; "discovery" flips one from
hidden to a face-up, playable tile — it does not add new positions to the
board.** See §8 for why this matters for how big the underlying data
structure actually is.

### Guardians

A guardian tile appears, face down flipped face up, automatically and
immediately every time a site is discovered — never as a separate action,
never skippable. It has **no immediate effect**. It sits on the site
indefinitely; it does not block Dig-at-a-Site at all ("Guardians... do not
prevent archaeologists from digging at their sites").

**Its only consequence: any archaeologist that returns home (at round
cleanup) from a site still holding a guardian earns its owner one Fear
card**, regardless of who woke that guardian originally.

**Overcoming a guardian is a flat resource-token payment, not a strength
comparison of any kind.** As a main action, with an archaeologist already
standing on the guardian's site: "1. Pay the cost depicted at the bottom of
the guardian tile. 2. Remove the guardian from the board and keep it by
your player board." There is no attack stat, no roll, no threshold to beat
— it is exactly the same shape as paying to buy a card. (Some card/idol
effects let a player overcome a guardian on their own occupied site
*without* paying that cost — but the underlying cost itself is never
anything other than a flat token price.) An overcome guardian is worth 5
points at game end regardless of whether its **boon** (a one-time bonus
ability, printed in its corner, usable once ever on any future turn) is
ever used.

---

## 8. Idols and the shared island board's actual shape

**Idols** are found only when discovering a new site (never from Dig at a
Site on an already-discovered one). They're kept face down on the player's
own board ("supply crates"). Each is worth 3 points at game end, whether or
not it was ever used. A player board has **4 idol slots**; on any turn, as a
**free action**, a player may move one held idol into the leftmost open
slot and immediately choose one of five printed idol-slot effects. A slot,
once filled, can never be emptied or reused (short of a specific artifact
effect that bends this). **Each of the four slots also scores points if it
is still empty at game end** — the exact per-slot values weren't
independently confirmed; secondary sources suggest the first two slots
score 1 and 2 points respectively for staying empty, but this is not
cross-verified against the official numbers (§13).

**The island board is one single shared board, not a private board per
player, and it does not grow.** This directly contradicts the loose framing
("a personal expedition board that each player uncovers tile by tile")
this research project's own objective started from — worth stating
precisely, because it changes what kind of engine gap this is (see
[21](../21-lost-ruins-of-arnak.md)'s Stage 2):

- There is exactly one island board, visible to and shared by every player.
  Every discovered site, every guardian, every idol slot's fill state is
  public information the instant it happens — there is no private,
  per-player fog of war anywhere in the base game.
- The board's *set of possible site positions* is fixed and printed from
  the start of the game — the 5 starting sites already have tiles; the
  remaining Level I/II positions are marked (with their region, and
  whether that position gets one or two idols) but empty until discovered.
  "Discovery" replaces a hidden marker with a face-up tile at a position
  that already physically existed on the printed board; it never adds a
  new position to the map, and no tile physically overlaps or connects
  with another in a way that creates a movement-cost topology.
- **There is no terrain to cross and no movement cost that accumulates
  over distance.** Sending a figure "to" a site is a direct placement
  (pay that site's own flat printed cost, put the figure down) — not a
  step-by-step traversal of intervening spaces the way a hex or grid move
  would be. "Terrain cost" in the sense Mage Knight, Hive or Carcassonne
  raise it (a board that grows without bound, crossed hex by hex, cost
  varying by what's underfoot at each step) simply does not exist in
  Arnak's rules.

---

## 9. Fear

Fear cards have no effect and only a travel value; there are 19 in the
shared Fear deck (all identical, kept face up as a public pile). A player
gains one for every archaeologist that returns home from a still-guarded
site at round cleanup, and may also be forced to gain one by a small
number of card/effect texts. **Fear scores -1 point each at game end** (or
-2 for a **fear tile**, a physical stand-in used only if the 19-card Fear
deck itself runs out — a component-supply safety valve, not a separate
rule). There is no other "leftover resource" or hand-size penalty
anywhere in final scoring — banked Coin/Compass/Tablet/Arrowhead/Jewel
tokens left unspent at game end score nothing and cost nothing.

---

## 10. Research

Each player has two tokens on the research track: a **magnifying glass**
(discovery) and a **notebook** (documentation). **The notebook may never
sit on a row above the magnifying glass** — "first you discover something,
then you write it down" — though both can share the same space, and both
can advance together in the same action if the player is moving the
notebook up to meet the magnifying glass.

**The track is a branching path, not a single line**: each space connects
to one or two spaces in the row above, each connection ("bridge") carrying
its own resource-token cost, so a token's available moves depend on exactly
where it currently sits. A research action is: choose which token to move
(if it would still respect the never-ahead-of rule); choose one connected
space above; pay that bridge's cost; then resolve two things (in either
order) — take the row's face-up bonus tile if one is there and unclaimed
(first token to arrive gets it, tile removed from the game after; and the
bonus tile is skipped in future scoring since it's gone), and always
resolve the row's own effect (differs by whether it was the magnifying
glass or the notebook that arrived — resource gain, drawing a card, or
recruiting/upgrading an assistant, per row).

**Recruiting an assistant**: some rows, reached by the *notebook*, let the
player take one of (usually) 3 face-up-topmost assistant tiles from a
shared supply of pre-shuffled stacks (assistants further down each stack
stay secret until the ones above are taken). **Upgrading an assistant**:
other notebook rows instead let the player flip one of their own held
assistants to its stronger gold side, refreshing it in the process even if
already used that round.

**Reaching the Lost Temple** (top of the track, magnifying glass only —
the notebook can never get there) is scored by *arrival order*: the
magnifying glass is placed on whichever remaining Lost Temple space is
worth the most points, so the first player there gets the best value.
Reaching it also grants a temple-bonus tile pick from a stack sized exactly
to the player count.

**After reaching the Lost Temple**, further magnifying-glass research
actions no longer advance the track — instead they buy a **temple tile**
from any one of several stacks (worth 2, 6, or 11 points), each requiring
its own fixed *combination* of the three non-Coin, non-Compass resource
costs (e.g., the 6-point stacks each need two of the three; the 11-point
stack needs all three). Stacks are limited (roughly player-count-sized;
exact counts not confirmed, §13) and can run out.

---

## 11. Assistants

A distinct pool from archaeologists — assistants live entirely on the
player's own board, are never placed on the shared island board, and are
recruited/upgraded only via the research track (§10). Each has a silver
(base) and gold (upgraded) side with different effects; some effects are
free actions usable at will, a few count as the main action.

**Using an assistant turns it sideways ("exhausted"), unusable again until
refresh.** In the ordinary case, refresh happens for every assistant,
automatically, at round cleanup (§2 step 4) — this is a once-per-round
resource exactly like the shared island board's dig spaces, just scoped to
one player instead of shared. A few specific card/upgrade effects can
refresh an assistant mid-round, allowing a second use in the same round.

---

## 12. End of game and final scoring

The game always runs exactly 5 rounds; round 5's cleanup is truncated
(archaeologists return, Fear from guardians is gained, then final scoring
runs immediately — no card-row shift, no reshuffle, no round 6).

Points, per the rulebook's own summary list:

- Each research token scores points **based on its row** on the track
  (magnifying glasses that reached the Lost Temple score by arrival order
  instead, per §10).
- Each temple tile scores the amount printed on it.
- Each idol scores 3 points, whether it was ever slotted or not, **plus**
  points for each idol slot still empty (values not fully confirmed, §13).
- Each guardian overcome scores 5 points flat, whether its boon was used
  or not.
- Each item and artifact card in the player's collection scores the amount
  printed in its lower-right corner.
- Each Fear card scores -1 point (fear tiles, the supply-overflow stand-in,
  score -2 each).
- **No other category exists** — there is no leftover-resource penalty and
  no hand-size penalty.

Highest total wins. Ties break first in favor of whoever reached the Lost
Temple first; if nobody did, in favor of the higher research score; any
tie surviving both checks stays a tie.

---

## Solo variant (context only, not load-bearing for Stage 2)

A deterministic rival, not an AI: it plays from a shuffled, pre-built
10-tile stack of fixed action tiles (5 archaeologist actions plus 5
red/green "aggression level" action pairs, mixed by a chosen difficulty),
each resolved by fixed, unconditional priority rules and a "decision arrow"
tiebreak — never a choice, never adaptive. It always starts each round,
gains no resources of its own, gains no Fear, and simply scores by the same
categories a real player would. Included here only because it's further
evidence the whole ruleset is designed to be executed by a fixed, ordered
procedure — nothing in it needs real judgment or hidden state beyond what a
shuffled deck already provides.

---

## 13. What was not independently verified

Collected here, flagged inline above:

1. The exact Travel Hierarchy ranking between the five travel icons (which
   icon outranks which) — described as existing and printed on the quick
   reference sheet, but the specific ordering wasn't recovered from the
   extracted rulebook text (icons are images, lost in text extraction).
2. The exact region costs (Compass amounts) to Discover a Level I vs. Level
   II site, and the exact per-space travel costs at each of the 5 starting
   sites — printed directly on the board/tiles as icons, not as text
   anywhere in the rulebook body.
3. Which numeral (10 or 6) maps to Level I vs. Level II site tiles — inferred
   from typical difficulty/quantity pairing (more, easier tiles at the
   lower tier) but not textually confirmed, since the level icons
   themselves didn't extract as text.
4. Whether any Level I/II (discovered) site tile ever prints a second
   archaeologist space — confirmed only for the 5 starting sites, which the
   blocking-tile rules explicitly scale by player count.
5. Starting resources by seat order (Player 1: 2 Coin; Player 2: 1 Coin + 1
   Compass; Player 3: 2 Coin + 1 Compass; Player 4: 1 Coin + 2 Compass) —
   sourced from Board Game Arena's `Gamehelparnak` rules-help page, not
   cross-verified against the official PDF's icon-only table.
6. The exact per-slot point values for the four idol slots when left empty
   at game end — the rulebook confirms this scoring category exists but the
   printed numbers weren't recovered from the extracted text; secondary
   sources suggest the first two slots (of four) are worth 1 and 2 points
   respectively, not cross-verified for all four.
7. Fear cards' printed travel-value icon — a secondary source (Board Game
   Arena's rules images) suggests a single icon, but which of the five
   resource types it corresponds to wasn't confirmed from the official text.
8. Exact temple-tile stack sizes (how many 2-/6-/11-point tiles exist per
   player count beyond "as many as there are players" for some stacks) and
   the exact three-way cost combinations printed at the bottom of the
   temple for each stack.
9. Full guardian-tile cost/boon table (36 distinct guardian tiles's worth
   of "cost to overcome" and "boon effect" text) — the rulebook describes
   the mechanism, not each tile's printed values.
10. Card row's total visible slot count and exact refill-when-a-deck-
    empties edge-case behavior beyond "that side stops refilling."
