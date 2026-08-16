# Splendor — Card Data

The base game (Space Cowboys / Asmodee, 2014). 90 development cards, 10
noble tiles, gem tokens in 5 colors plus gold. Development cards carry no
printed name — only art, a cost, a bonus color, and (sometimes) a point
value — so this document identifies them by tier + bonus color + cost
rather than inventing names. Noble tiles do carry printed names on the
physical component, but see the unverified section: name-to-cost
attribution across fan sources conflicts, so this document gives cost and
points only.

Gem colors and their real-world names (the box uses both interchangeably):
**white** = diamond, **blue** = sapphire, **green** = emerald, **red** =
ruby, **black** = onyx, plus **gold**, a wild token gained only by
reserving.

**Sources.** No single authoritative text online reproduces the full 90-card
table, so this document triangulates three independently-authored fan
transcriptions of the physical deck, found as data files (not prose) in
three unrelated GitHub repos:

- [bouk/splendimax — `Splendor Cards.csv`](https://github.com/bouk/splendimax/blob/master/Splendor%20Cards.csv)
- [dychen/splendor — `gamedata.tsv`](https://github.com/dychen/splendor/blob/master/gamedata.tsv) + [`nobledata.tsv`](https://github.com/dychen/splendor/blob/master/nobledata.tsv) (column order and gem-letter mapping confirmed from `game.py`'s own comments and load code)
- [seal256/splendor — `assets/cards.csv`](https://github.com/seal256/splendor/blob/master/assets/cards.csv) + the `NOBLES` constant hardcoded in [`pysplendor/splendor.py`](https://github.com/seal256/splendor/blob/master/pysplendor/splendor.py)

All three were downloaded and diffed programmatically, not eyeballed. Once
each source's own letter/column convention was resolved (worked out
mechanically by testing both possible mappings and keeping the one that
produces an exact match — done for `u`/`b` in source 2 and `b`/`k` in
source 3), **all three agree on tier, bonus color, full cost, and points
for every one of the 90 cards, with zero discrepancies.** The two noble
sources (dychen, seal256) likewise agree exactly on all 10 cost/point
combinations. Turn-structure and token-count rules below are
cross-confirmed across three independent rules summaries — see their own
sourcing note.

This is about as solid as unofficial secondary data gets: three people who
never worked together, transcribing from (presumably) three different
physical copies or references, produced byte-identical tables.

---

## Development cards — 90 total

**40 level 1, 30 level 2, 20 level 3** (8/6/4 cards per tier per color,
confirmed by the row counts in all three sources, not merely assumed from
the objective's framing). Each row is one card: **Bonus** is the gem color
it produces once bought (permanent discount of that color, forever); **VP**
is its printed point value (`-` means 0, the common case at level 1); the
five cost columns are gem tokens spent to buy it, **before discounts**
(`-` means 0). A card's cost occasionally includes its own bonus color —
this looked like a transcription error until it was confirmed identically
in all three sources, so it's real.

### Tier 1 (40 cards, 0–1 VP)

| Bonus | VP | White | Blue | Green | Red | Black |
|---|---|---|---|---|---|---|
| White | - | - | - | - | 2 | 1 |
| White | - | - | 3 | - | - | - |
| White | - | - | 1 | 1 | 1 | 1 |
| White | - | - | 2 | - | - | 2 |
| White | - | - | 1 | 2 | 1 | 1 |
| White | - | - | 2 | 2 | - | 1 |
| White | - | 3 | 1 | - | - | 1 |
| White | 1 | - | - | 4 | - | - |
| Blue | - | 1 | - | - | - | 2 |
| Blue | - | - | - | - | - | 3 |
| Blue | - | 1 | - | 1 | 1 | 1 |
| Blue | - | - | - | 2 | - | 2 |
| Blue | - | 1 | - | 1 | 2 | 1 |
| Blue | - | 1 | - | 2 | 2 | - |
| Blue | - | - | 1 | 3 | 1 | - |
| Blue | 1 | - | - | - | 4 | - |
| Green | - | 2 | 1 | - | - | - |
| Green | - | - | - | - | 3 | - |
| Green | - | 1 | 1 | - | 1 | 1 |
| Green | - | - | 2 | - | 2 | - |
| Green | - | 1 | 1 | - | 1 | 2 |
| Green | - | - | 1 | - | 2 | 2 |
| Green | - | 1 | 3 | 1 | - | - |
| Green | 1 | - | - | - | - | 4 |
| Red | - | - | 2 | 1 | - | - |
| Red | - | 3 | - | - | - | - |
| Red | - | 1 | 1 | 1 | - | 1 |
| Red | - | 2 | - | - | 2 | - |
| Red | - | 2 | 1 | 1 | - | 1 |
| Red | - | 2 | - | 1 | - | 2 |
| Red | - | 1 | - | - | 1 | 3 |
| Red | 1 | 4 | - | - | - | - |
| Black | - | - | - | 2 | 1 | - |
| Black | - | - | - | 3 | - | - |
| Black | - | 1 | 1 | 1 | 1 | - |
| Black | - | 2 | - | 2 | - | - |
| Black | - | 1 | 2 | 1 | 1 | - |
| Black | - | 2 | 2 | - | 1 | - |
| Black | - | - | - | 1 | 3 | 1 |
| Black | 1 | - | 4 | - | - | - |

### Tier 2 (30 cards, 1–3 VP)

| Bonus | VP | White | Blue | Green | Red | Black |
|---|---|---|---|---|---|---|
| White | 1 | - | - | 3 | 2 | 2 |
| White | 1 | 2 | 3 | - | 3 | - |
| White | 2 | - | - | - | 5 | - |
| White | 2 | - | - | 1 | 4 | 2 |
| White | 2 | - | - | - | 5 | 3 |
| White | 3 | 6 | - | - | - | - |
| Blue | 1 | - | 2 | 2 | 3 | - |
| Blue | 1 | - | 2 | 3 | - | 3 |
| Blue | 2 | - | 5 | - | - | - |
| Blue | 2 | 2 | - | - | 1 | 4 |
| Blue | 2 | 5 | 3 | - | - | - |
| Blue | 3 | - | 6 | - | - | - |
| Green | 1 | 2 | 3 | - | - | 2 |
| Green | 1 | 3 | - | 2 | 3 | - |
| Green | 2 | - | - | 5 | - | - |
| Green | 2 | 4 | 2 | - | - | 1 |
| Green | 2 | - | 5 | 3 | - | - |
| Green | 3 | - | - | 6 | - | - |
| Red | 1 | 2 | - | - | 2 | 3 |
| Red | 1 | - | 3 | - | 2 | 3 |
| Red | 2 | - | - | - | - | 5 |
| Red | 2 | 1 | 4 | 2 | - | - |
| Red | 2 | 3 | - | - | - | 5 |
| Red | 3 | - | - | - | 6 | - |
| Black | 1 | 3 | 2 | 2 | - | - |
| Black | 1 | 3 | - | 3 | - | 2 |
| Black | 2 | 5 | - | - | - | - |
| Black | 2 | - | 1 | 4 | 2 | - |
| Black | 2 | - | - | 5 | 3 | - |
| Black | 3 | - | - | - | - | 6 |

### Tier 3 (20 cards, 3–5 VP)

| Bonus | VP | White | Blue | Green | Red | Black |
|---|---|---|---|---|---|---|
| White | 3 | - | 3 | 3 | 5 | 3 |
| White | 4 | - | - | - | - | 7 |
| White | 4 | 3 | - | - | 3 | 6 |
| White | 5 | 3 | - | - | - | 7 |
| Blue | 3 | 3 | - | 3 | 3 | 5 |
| Blue | 4 | 7 | - | - | - | - |
| Blue | 4 | 6 | 3 | - | - | 3 |
| Blue | 5 | 7 | 3 | - | - | - |
| Green | 3 | 5 | 3 | - | 3 | 3 |
| Green | 4 | - | 7 | - | - | - |
| Green | 4 | 3 | 6 | 3 | - | - |
| Green | 5 | - | 7 | 3 | - | - |
| Red | 3 | 3 | 5 | 3 | - | 3 |
| Red | 4 | - | - | 7 | - | - |
| Red | 4 | - | 3 | 6 | 3 | - |
| Red | 5 | - | - | 7 | 3 | - |
| Black | 3 | 3 | 3 | 5 | 3 | - |
| Black | 4 | - | - | - | 7 | - |
| Black | 4 | - | - | 3 | 6 | 3 |
| Black | 5 | - | - | - | 7 | 3 |

---

## Noble tiles — 10 total

Every noble is worth **3 VP** (confirmed identically by every source
consulted, primary and secondary — no exceptions in the base game). Cost
is discounts, never tokens: it's read against how many bought cards of
each bonus color a player owns, not against tokens in hand. Two shapes
only: **5 nobles cost 4+4** (two colors), **5 nobles cost 3+3+3** (three
colors) — confirmed by an explicit source quote ("five nobles require two
gem colors at four each, the remaining five require three gem colors at
three each") and independently reproduced by cross-checking dychen's and
seal256's cost tables against each other.

The 4+4 pairs form one 5-cycle over the colors (white–blue–green–red–
black–white), each adjacent pair used exactly once; the 3+3+3 triples are
the complementary picks, each color appearing in exactly 3 of the 5.

| # | Cost | VP |
|---|---|---|
| 1 | 4 white + 4 blue | 3 |
| 2 | 4 blue + 4 green | 3 |
| 3 | 4 green + 4 red | 3 |
| 4 | 4 red + 4 black | 3 |
| 5 | 4 black + 4 white | 3 |
| 6 | 3 white + 3 blue + 3 black | 3 |
| 7 | 3 blue + 3 green + 3 red | 3 |
| 8 | 3 white + 3 red + 3 black | 3 |
| 9 | 3 white + 3 blue + 3 green | 3 |
| 10 | 3 green + 3 red + 3 black | 3 |

Nobles used per game: **n + 1**, drawn at random from these 10 and
revealed face up at setup (2p: 3 nobles, 3p: 4, 4p: 5) — confirmed by
three independent rules sources.

---

## Gem token supply

| Players | Tokens per color (white/blue/green/red/black) | Gold |
|---|---|---|
| 2 | 4 | 5 |
| 3 | 5 | 5 |
| 4 | 7 | 5 |

Gold (the wild joker) stays at 5 regardless of player count. The box
contains 7 of each color + 5 gold = 40 gem tokens total, matching the
4-player count exactly (lower player counts remove tokens from the full
set, they don't use a separately-sized pool). Confirmed identically by
three independent rules sources.

---

## Turn structure

A turn is exactly **one** of:

1. **Take 3 tokens of 3 different colors** from the bank (gold excluded —
   gold is never taken this way).
2. **Take 2 tokens of the same color**, only if that color's bank stack
   has **at least 4** remaining *before* the take.
3. **Buy a development card**, either face-up from the tableau or from
   among the player's own reserved cards — paying its printed cost, with
   each of the player's permanent bonuses (owned cards) reducing that
   color's cost by 1, and gold substituting for any shortfall of any
   color. A face-up card bought is immediately replaced from that tier's
   deck.
4. **Reserve a development card** — face-up from the tableau, or blind
   from the top of any tier's deck — taking it into a private hand of at
   most 3 reserved cards, and gaining 1 gold token if any remain in the
   bank (no gold if the bank is out; the reservation still happens).

**Hand limit.** A player holding more than 10 tokens (any mix of the 5
colors + gold) at the end of their turn must discard down to exactly 10,
their choice of which.

**Noble visits.** After a purchase, any noble whose full cost is met by
the buyer's current bonuses (permanent discounts, not tokens in hand) is
claimed automatically, for free — no cost, no action spent. At most one
per turn: if multiple qualify simultaneously, the player picks which one.
A claimed noble is removed from the shared pool for the rest of the game.

**Turn order.** Strictly sequential, one seat at a time, going around the
table. No simultaneous or hidden-information mechanics anywhere in the
base game — the whole board (bank, tableau, reserved-card *counts* if not
contents, everyone's bonuses) is open information; only the contents of
reserved cards are private to their owner.

---

## Win condition

The instant a player's total VP (development cards + claimed nobles)
reaches **15** at the end of their turn, the game does not stop —
play continues to finish the current round, so every player gets the
same number of turns. Then: highest total VP wins; ties are broken by
**fewest development cards purchased** (efficiency over raw points).

---

## Not independently verified

1. **Noble tile flavor names.** The physical tiles depict named historical
   figures (Isabella of Castile, Catherine de' Medici, and similar), but
   fan sources disagree on which name maps to which cost combination —
   one compiled list's claim for "Henry VIII" (4 onyx + 4 emerald) does
   not match any of the 5 confirmed 4+4 pairs, which only ever combine
   *adjacent* colors on the white–blue–green–red–black cycle (onyx/black
   and emerald/green are not adjacent). Rather than propagate a
   contradicted attribution, this document gives nobles by cost only.
   Names are cosmetic and don't affect any engine data.
2. **Secondary tiebreak beyond "fewest development cards."** One secondary
   source (a Wikipedia summary) adds "then fewest reserved cards, then
   shared victory" as further tiebreak steps; the two other rules sources
   consulted state only the fewest-development-cards rule and don't
   mention a next step. Included nowhere above as fact; flagged here in
   case a real game file needs a full tiebreak chain.
3. **Whether a card's cost may include its own bonus color is by design
   or a shared transcription artifact.** It appears in all three
   independent sources identically (e.g. a white-bonus tier-1 card
   costing 3 white among its price), which is strong evidence it's simply
   correct, but no primary-source rulebook text was read directly to
   confirm the designers intended it rather than three fan sites
   inheriting the same original error.
4. **Exact reserve-from-deck wording** ("without showing it to the other
   players") — confirmed by one rules-summary source; not cross-checked
   against a second for the precise phrase, though the mechanic itself
   (reserve blind from any tier's deck top) is confirmed by all three
   rules sources used.
