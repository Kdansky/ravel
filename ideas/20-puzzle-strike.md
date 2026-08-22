# 20 — Puzzle Strike

**Status:** not started · **Size:** medium · **Depends on:** likely little —
this is the deckbuilder candidate closest in shape to what's already
plausible; stage 2 exists to confirm that rather than assume it

> *Second of three deckbuilder candidates — a chip-based, character-driven
> deckbuilder from Sirlin Games, closer in shape to Dominion than Mage Knight
> is.*

**Objective.** Puzzle Strike replaces cards with poker chips: a shared bank
of numbered "gem" chips players buy into their own pile, each of roughly a
dozen characters brings one unique starting chip with its own text, damage is
chips that clog your economy rather than a separate life total, and a
"Crash" chip lets you cash in a stack of same-value chips for a burst effect.
It reads as the closest of the three deckbuilder candidates to something
already argued plausible for this engine (a Dominion-shaped buy → discard →
reshuffle loop over `draw_and_play` and `refill_when_empty`) — this file
exists to check that instinct against the real rules rather than assume it.

---

## Stage 1 — the rules document

**Deliverable:** `ideas/puzzle_strike/rules.md`, sourced and marked the same
way as [19](19-mage-knight.md)'s. Must cover:

- The buy phase: what money buys, what the shared bank looks like, turn
  order.
- The bank/discard/reshuffle cycle for a player's own chip pile.
- How damage chips work: how they enter your pile, what they cost you while
  they're there, how a player is eliminated.
- The Crash mechanic, exactly — what triggers it, what a stack "crashing"
  produces, what happens to the chips afterward.
- Full text for at least two starting characters, to test the
  asymmetric-starting-power question [Santorini's suggestion](../ideas)
  already raised for a different genre.
- Win condition and game length.

**Done** — [ideas/puzzle_strike/rules.md](puzzle_strike/rules.md). Built from
the official Sirlin Games rulebook PDF (Third Edition, v7.3), fetched and read
in full, plus David Sirlin's own design writing and three character
strategy-guide threads on the Sirlin Games forum. Two corrections to the
objective's own framing turned up in the process, both worth flagging up
front rather than burying: the wound chip is called **Wound**, not "Crashing
Moles" (that name appears nowhere in the source material); and the Crash
mechanic is **not** "N chips of a matching value trigger automatically" — it
is a deliberate action-chip play that breaks one gem from *your own* gem pile
and sends it to a chosen opponent's. The value-matching-trigger mechanic
turns out to belong to *Puzzle Strike 2*, an unrelated 2022 redesign the
designer himself calls "really just two different games" — see rules.md §11.
Every number not cross-confirmed across two sources is flagged inline and
collected in rules.md §12.

## Stage 2 — what it names that the engine lacks

**Deliverable:** the gap table, in the shape of
[19](19-mage-knight.md)'s — one row per Puzzle Strike rule, mapped to what
ravel already has, what's expressible, and what's a genuine gap, followed by
a verdict.

| Puzzle Strike rule | Ravel today |
|---|---|
| Shared bank: fixed quantities of 1/2/3/4-gems, Combine, Crash Gem, Double Crash Gem, Wound, plus 10 of 24 Puzzle Chip designs chosen per game | shared (non-`per_seat`) zones with `contents` — **exists** |
| Buy phase: money computed fresh each turn from Gem chips played out of hand, spent same turn, unspent lost | a per-turn `money` stat, reset on fresh phase entry exactly as the engine's own `plays` stat already is, gained by each Gem chip's own `play.action`, spent as an ordinary `cost` — **expressible** |
| Wound: the mandatory 0-cost buy when nothing else is affordable, capped at one per turn | a `needs`-gated purchase card plus the documented escape hatch ("a needs-gated card becomes playable when nothing else in its zone is") — **exists**, and is precisely the case that escape hatch was written for |
| Personal chip cycle: bag/hand/discard, draw 5 (+height bonus for a fuller gem pile) at Cleanup, discard the played table plus the unplayed hand | `per_seat` deck/hand/pile zones, a `discard_hand`-tagged phase, `draw_from` — **exists**, and matches Dominion's shape closely enough that `draw_and_play` almost fits verbatim |
| Reshuffle discard into the bag mid-draw when the bag empties, preserving whatever chips were actually bought and discarded | **not** `refill_when_empty` — see below | **expressible, but the obvious first reach is wrong** |
| The "ongoing" zone: a fourth personal zone for chips that stay in play providing a passive benefit until something discards them | an ordinary `per_seat` zone plus `activate`/`turn.action` — **exists/expressible**, no new zone type needed |
| Piggy Bank: keep one unplayed hand chip past Cleanup instead of discarding it, at the cost of drawing one fewer next turn | a chip's own `activate.action` moving itself to a small holding zone before the phase's automatic discard sweep, then folding back into the next Cleanup's draw at `n - 1` — **expressible**, but an authored pattern rather than the built-in `discard_hand`/`keep_hand` toggle, which opts a whole hand in or out rather than one chosen card |
| Gem pile: a second personal zone, gems only, never shuffled or drawn from, holding the game's entire loss-condition total | a second `per_seat` zone (`pile` type) with `card_stats.value` on each gem card — **exists** |
| Loss condition: pile value ≥10, checked **only at the end of your own turn**, not continuously (you may legally sit above 10 mid-turn) | `sum:value@gem_pile` is a direct subject read, but the *timing* wants phase routing on the Cleanup→next-turn transition, not `end_conditions` — see below | **expressible, but the obvious first reach is wrong again, the same way** |
| 3–4p free-for-all: the whole game ends the instant anyone crosses 10, winner is whoever holds the **lowest** total, not a last-survivor format | needs a `min:` measuring function; `predicate.lua`'s `FNS` table has `count`/`card`/`sum`/`max` only, no `min` | **small genuine gap** — irrelevant to the 2-player game, which the rulebook itself calls the tournament default |
| Crash Gem: break one gem from your own pile, send that many 1-gems to a chosen opponent's pile | an ordinary `activate.target` into your own `gem_pile`, `destroy:target` plus `fill:enemy.gem_pile:gem_1:<value>` — **expressible**, and unambiguous with exactly one opponent |
| Double Crash Gem: as above, up to two gems in one play | the same target spec with `count: 2` — **expressible** |
| Combine: merge two gems in your own pile (sum ≤4) into one new gem of that value | `"needs": ["sum:value@target <= 4"]` on a two-card target, then destroy both and create one — **expressible**, but which template to create is a small closed set (1+1→2, 1+2→3, 1+3→4, 2+2→4) authored per case, the same repetition-not-a-gap texture Mage Knight's sideways play already established |
| 4-gems are immune to counter-crash entirely | a tag or `computed_tags` check gating whether the reaction is even offered — **expressible**, once reactions exist at all (next row) |
| Counter-crash: the *non-active* seat plays a reaction chip from their own hand during the active seat's turn, without becoming the active seat | **genuine gap** — see below |
| Choosing *which* opponent to crash, in 3–4p | no idiom routes a created card into a zone owned by a *player-chosen* target rather than a scope word (`mine`/`enemy`/`anyone`) | **small genuine gap**, 3–4p only — 2-player sidesteps it entirely, since `enemy` already names the only opponent |
| Character asymmetry: one identical shared starting deck, differentiated by exactly three named character chips | the same asymmetric-starting-power pattern already used for Onitama/Santorini — **exists/expressible**, cheaply |
| Panic Time: forced Ante escalates permanently as shared bank stacks empty | `count:<tag>@bank` per stack compared against zero, driving which gem value the Ante action grants — **expressible** |

### `refill_when_empty` is the wrong tool, and it matters generally

`zones.lua:174` (`M.refill`) iterates the zone *definition's* declared
`contents` list — the fixed set of `"key:count"` strings written in the game
file — and `zones.lua:313` fires it automatically inside `move_card` whenever
a `refill_when_empty`-tagged zone hits zero. That is exactly right for a
shared market that restocks itself from a fixed recipe. It is exactly wrong
for a personal draw pile whose contents change over the game: tagging a
Puzzle Strike bag `refill_when_empty` would, the first time it emptied,
silently recreate the *starting* ten chips and discard every gem, Wound and
Puzzle Chip actually bought since — the bug DESIGN.md's own aggregates-beat-
running-totals principle warns about, wearing a different hat.

The rule the game actually states — *"put the chips from your discard pile...
into your bag, shake your bag to shuffle them, then continue drawing"* — is
`return_to:discard:bag` + `shuffle:bag`, run exactly when the bag is empty and
a draw is still owed. No shipped game has needed this yet, so there is no
one-line idiom for it: the fixed-size `draw_from:from:to:n` op stops the
moment the source empties (`zones.move_top` returns false at zero cards) and
does not itself branch on "reshuffle, then keep going" — an ordinary action
list has no per-step conditional. The construct that *does* express it is
already in the engine, just not combined this way before: a small automatic
phase pair, one drawing a single chip and self-looping on a routing condition,
the other reshuffling and looping back:

```json
{ "key": "draw_step", "type": "automatic", "actions": ["draw_from:bag:hand:1"],
  "next": [
    { "when": "count:chip@hand >= 5", "then": "buy" },
    { "zone_empty": ["bag"], "then": "reshuffle_step" },
    { "then": "draw_step" }
  ] },
{ "key": "reshuffle_step", "type": "automatic",
  "actions": ["return_to:discard:bag", "shuffle:bag"],
  "next": [{ "then": "draw_step" }] }
```

(`chip` is an ordinary author-declared tag every gem/Wound/Puzzle/Character
chip carries, standing in for "how many cards are in this zone regardless of
which" — the raw-count-of-a-zone question [17](17-conditions-as-expressions.md)
already notes has no dedicated subject.) This is a genuine, if small,
authoring cost past a one-line `draw_and_play` phase — worth generalizing:
**any Dominion-shaped deckbuilder whose personal pile grows through play**
(this game, and very likely [21](21-lost-ruins-of-arnak.md)'s Arnak too, since
Arnak explicitly apes the same loop) needs this same pair of phases, not
`refill_when_empty`, and the stub's own framing of this idiom as "unconfirmed"
was right to flag it — it is now confirmed, in the wrong direction from the
optimistic reading.

### The loss condition needs a routing check, not an `end_condition`

`end_conditions` are checked continuously — DESIGN.md is explicit that they
"run after every action" — which is exactly wrong for a rule that is checked
"only at the end of your own turn." Authoring `{ "when": "sum:value@gem_pile >= 10", "then": [...] }` as an ordinary
`end_conditions` entry would end
the game the instant an opponent's crash pushes your pile over 10, mid-turn,
denying you the real rule's whole tactical layer — bringing your own pile back
under 10 with your own Crash Gem or Combine before your turn formally ends.
The fix costs nothing new: a `"next"` routing entry on the Cleanup phase's own
transition already only evaluates at that one moment, which is precisely the
tool DESIGN.md's phase-routing section describes and precisely what this rule
needs. `{ "when": "sum:value@gem_pile >= 10", "then": "defeat" }` on
Cleanup's `next` table, ahead of the unconditional entry that starts the next
player's turn, is the whole of it.

### The crash-by-value fear doesn't apply — but a real reaction gap replaces it

The stub worried specifically about whether "N chips sharing a numeric value
stat" is nameable in `predicate.lua`'s condition vocabulary — and it genuinely
isn't (`count:` takes a tag argument, never a stat-value match; grouping by an
*arbitrary shared value* rather than a *pre-declared tag* has no primitive).
But the worry turns out not to apply to Puzzle Strike at all: the base game's
Crash is a single deliberate action-chip play against your own gem pile, not
an automatic same-value trigger — that mechanic belongs to the unrelated 2022
sequel (rules.md §11). Nothing in the base game asks the engine to group
cards by a shared numeric stat.

A different, real gap sits exactly where the fear was aimed, though: **counter-
crashing.** `flow.lua`'s `reachable()` (line 47) requires a card's owner seat
to equal the active seat before it may be played or activated — a Crash Gem
sitting in the defending player's own hand is unreachable to them while it is
not their turn, full stop. This is the same shape as
[18](18-legends-of-runeterra.md)'s stage-2 finding about LoR's response stack
— a card played by the *non-active* seat, mid-turn, without a turn handover —
and just as real here. It is, if anything, a smaller instance than LoR's: one
reaction chip type, one negation rule (matching 1-gems cancel), one immunity
carve-out (4-gems), no permanents entering as a response and nothing resolving
last-first. Still a genuine gap rather than an authoring inconvenience, because
the block sits in `flow.lua`'s legality check, not in content.

### Character asymmetry resolves in ravel's favor

Every one of the ten base characters shares one identical starting deck —
three Character chips, one Crash Gem, six 1-gems — differing only in what
those three named chips do. That is precisely the shape already proven out
for Onitama and Santorini: different `player`-tagged templates with different
starting `card_stats`/abilities, sharing everything else. Argagarg (Hex of
Murkwood forcing Wounds, an *ongoing* Bubble Shield, a Combine-tax Protective
Ward) and Jaina (bank-anted burn chips, an uncounterable finishing Double
Crash) are mechanically opposite — one plays entirely on attrition and
disruption, one entirely on tempo and a single big finish — and both are
ordinary card templates with ordinary `abilities`/`activate` blocks; nothing
about either asks for new engine vocabulary. Midori is the one wrinkle worth
naming: Dragon Form doesn't act on gems already in play, it *changes what the
Ante phase itself grants* for as long as it's active — a mode switch rather
than an effect, expressible as a tag flipping which of two Ante actions a
`turn.action`/phase-entry step runs, but a step up in authoring weight from
the other two.

### Verdict

**Buildable now, as a 2-player game, mostly content — the stub's prediction
holds, though not for the reason it guessed.** The core loop — shared bank,
per-turn money from played gems, the buy-a-Wound fallback, the personal
bag/hand/discard cycle including a *correct* reshuffle (not
`refill_when_empty`), the gem pile as a second per-seat zone, the loss
condition as a Cleanup-phase routing check, Crash/Combine as ordinary
targeted actions against your own pile, and asymmetric characters — asks for
nothing past today's vocabulary. The one real structural gap, counter-
crashing, is cleanly cuttable for a first build exactly the way Mage Knight's
writeup amputated Conquest mode: without it, crashes simply land, the
defending player's own future turns are where they claw back under 10, and
the core identity of the game — manage your own pile, race the bank's
depletion, buy your way out of a bad hand — survives completely intact. That
makes Puzzle Strike's honest gap list shorter and shallower than Mage
Knight's two compounding, engine-level gaps (hex geometry, a map that grows
without bound) and puts it in the same rough weight class as
[21](21-lost-ruins-of-arnak.md)'s one named-but-unresearched gap (worker
placement) — except Arnak's gap is a *new primitive* nothing in the engine
expresses today, while Puzzle Strike's is a *missing capability inside an
existing mechanism* (`flow.lua`'s legality check refuses acting out of turn),
smaller in kind as well as in scope. Rank Puzzle Strike first of the three:
the least new engine work, the shortest list of authored-but-not-novel
patterns, and — via the `refill_when_empty` correction above — a finding that
pays for itself on Arnak too before Arnak's own research has even started.
