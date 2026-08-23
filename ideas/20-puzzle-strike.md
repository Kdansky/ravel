# 20 — Puzzle Strike

**Status:** **built and playing** (milestone 1, 2026-08-23) · **Size:** medium ·
**Depends on:** nothing that was missing — the two things stage 2 called gaps
were both real, and only one of them mattered

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

---

## Stage 3 — built (milestone 1, 2026-08-23)

`game/games/puzzle_strike.json`, generated by `tools/make_puzzle_strike.py`,
tested in `tests/integration/puzzle_strike.lua`, on the menu. Two seats pick a
character, ante, act, buy, clean up, and race each other to ten. A bot playing
badly finishes a game in 13–17 turns, which is the right side of the
rulebook's own floor of ten.

What is in it: the bank (four gems, the three purples, Wounds, and ten of the
twenty-four Puzzle chips), **all ten base characters** with three chips each, the ante,
the action and buy phases, the must-buy-something rule with the Wound as the
free fallback, the mid-draw reshuffle, the height bonus, Panic Time, crashing,
combining, and a loss condition asked at the end of your own turn and nowhere
else.

### The verdict held, and the one real gap is still cut

Counter-crashing is still the only thing the engine refuses: `flow.lua`'s
`reachable()` wants a card's owner to be the active seat, and a reaction is by
definition played by the other one. Cut exactly as predicted, and the game is
still the game — every chip whose *reaction* half is missing has its main half
built, and says so in its own tooltip. It remains the same gap
[18](18-legends-of-runeterra.md)'s response stack names, and whichever is built
second gets it free.

### `refill_when_empty` was the wrong tool, confirmed by building the right one

The phase pair stage 2 sketched is what shipped, at three phases rather than
two: `draw_step` routes, `draw_one` draws one and counts down, `reshuffle`
tips the discard back in and shakes it. `reshuffle` routes to the handover when
the discard was empty too, or the loop spins forever on a player who has
nothing left. The soak runs it dozens of times a game and the decks grow from
ten chips to fifteen or twenty-four, which is the proof the *actual* discard
comes back rather than a recreated starting deck.

### Four findings that were not in the gap table

**A scope cannot see a hand, and that decided two zone types.**
`sum:value@mine.gem_pile` is the loss condition, the height bonus, the combine
gate and half of crashing — and a tag scope searches **grid zones only**, so
the gem pile is a `grid [10, 2]` rather than the `pile` the table predicted.
The card holding the global Panic number went the same way: a hidden
`grid [1, 1]`, because `panic@clock` is a scope too. That is
[06](06-schema-and-types.md)'s unsearchable gap in a third dress, and the
workaround is now three-for-three across three games: **make it a grid**. The
gap is row 1 of the plan and this is the third game to pay for it.

> **Corrected when 06 shipped `@everywhere` (2026-08-23).** Half of this was a
> misdiagnosis: `sum:value@mine.gem_pile` reads a **pile** perfectly well —
> naming a zone by key never went through the grid-only path — so the gem pile
> did not have to be a grid *for the scope*. It stays a grid for **display**,
> which is a real and separate reason: gems laid out in a row so a player can see
> the pile's height. Only a *bare* tag or a tag scope was ever board-only, and
> that is what `@everywhere` opens up. The panic card at `@clock` is the same:
> named, so it was always readable.

**Only a phase a player acts in can hand the turn over.** `rotate_seat` sits on
the fresh-entry path for non-automatic phases; an automatic phase never
reaches it. So the ante could not be an automatic phase in front of the action
phase — it is the action phase's own `actions`. Worth stating generally: **a
turn's opening bookkeeping belongs on the first phase the player acts in**, not
on an automatic phase in front of it, because that phase is where the seat
changes.

**The first handover is what selects seat one.** The system card's `turn` starts
at 0 and `rotate_seat` computes `turn % n + 1`, so the first phase carrying
`seat: "next"` lands on seat *one*, not seat two. A draft therefore needs
`seat: "next"` on its **first** pick phase as well as its second. It reads
wrong and is right, and it cost a debugging pass: without it both picks
resolved to the same seat and one player got twenty chips.

**`needs` is asked before there are targets.** "Combine two gems if the total is
4 or less" is a fact about the *pair*, and `needs` is evaluated with no pair in
hand — so an illegal pair sailed through. `challenge` is the one condition that
**sees the targets** (`@target` is what the card was aimed at), so Combine is
`action: ["resolve_challenge"]` with the whole merge in `pass` and an action
refund in `fail`. That is a second honest customer for `challenge` outside
chess's promotion, and it is worth writing down as the rule: **a condition
about the targets is a `challenge`; a condition about the card is a `needs`.**

### Ten characters, and what the last five cost

The roster is all ten base characters, which took a second source: the physical
chips answer for five of them and an older printed sheet (**version 4.7, 2010**)
fills the rest. The two disagree in sixteen places, and
[puzzle_strike/chips.md](puzzle_strike/chips.md) tabulates every one — the
photographed third-edition text wins wherever a photograph exists, and the five
chips the sheet is the only source for are marked as such in the catalogue.
Worth knowing before the next game with a component photograph behind it:
**a printed reference sheet is a different edition until proved otherwise**, and
the cheapest proof is one photo with two editions of the same chip in it, which
this set happened to have.

Three of the fifteen new chips needed something new, and all three were cheap:

- **"Choose one" is an offer**, `options:<a>,<b>,<c>` with a card per branch —
  the same mechanism chess promotes a pawn with, used here for the first time
  by an ordinary played card rather than by a challenge. *Any different two of
  four* is six cards, which is the exhaustive set and reads better than asking
  twice would.
- **An extra turn is one flag read at the handover.** `stat_gain:extra`, and a
  route `{ "when": "extra@mine.player >= 1", "then": "again" }` ahead of the
  unconditional one; `again` decrements it and routes back with `seat: "same"`.
  The route overruling the phase about the seat is what makes it two lines.
- **The upgrade rule got two more destinations.** "A gem one bigger than the one
  you gave up" is asked by Risky Move (into the discard), Big Rocks (into the
  hand) and Strength of Earth (into the pile) — same question, three answers,
  three hidden zones. Which is the case-table-is-a-zone idiom paying off a
  second time rather than a new problem.

### A case table is a zone

Four rules here turn a number the action list just wrote into a *card*: which
gem the ante puts down, what two combined gems become, what a gem upgrades to,
how much a full pile draws. No amount grammar turns 3 into `gem_3`, and none
should. The shape that works is one card per answer in a hidden zone, each with
its own `when`, walked by `activate_zone` — which is ungated for permission and
still honours the if. Four families, four hidden zones (`rules_ante`,
`rules_combine`, `rules_upgrade`, `rules_height`), and the alternative was
either four copies of the chip or a branch in the action grammar.

One thing learned the hard way: `activate_zone:<zone>::<step>` does not parse —
the empty segment collapses and the step is read as the order. A step wants an
order beside it, and a deck has no columns to order by, so **one zone per
question** is the cheaper spelling anyway.

### The bank is one grid of counted plates

Eighteen stacks would have been eighteen rects to keep in step. One `grid [9, 2]`
of plate cards, each carrying `stock` and an `activate` that spends money, a buy
and one of the stock, lays itself out — and Panic Time then costs one computed
tag (`spent` = `stock < 1`) and one condition (`count:spent@bank`). Splendor's
token piles are the same idiom; this is its second use and the first where the
count is load-bearing for a rule rather than for a cost.

## Stage 4 — made readable (2026-08-23)

Playing it found what a validator cannot: the board was correct and unreadable.
Six things came out of that, five of them engine.

**A chip says what it gives in symbols.** A printed chip reads at arm's length
because it says `+1 action, +2 chips` in four shapes; a paragraph of English in
a forty-pixel band does not. So the things a chip gives are **stats**, badged —
`plus_act`, `plus_buy`, `plus_draw`, `plus_pow` — and the printed words stay in
the tooltip where the exact wording belongs. Three engine pieces made that
possible: four more icon shapes (`arrow`, `card`, `fist`, `orb`), a stat saying
`number: false` for a badge that is a shape alone (a shield meaning *this has a
reaction half* has no quantity), and **badges drawing on cards in a hand at
all** — `draw_card_stats_overlay` ran from the grid branch and the browse view
only, so a chip in hand wore a hole where its numbers belong. The face had
already reserved the space.

**The printed text, verbatim, and ours after a blank line.** The tooltips were
paraphrases with parenthetical asides in the middle of them, which is the
fastest way to make a rule unreadable and leaves nobody able to tell a typo
from a rules change. They are now word for word from
[puzzle_strike/chips.md](puzzle_strike/chips.md), and anything the build
leaves out is a trailing `DEV:` line. A test asserts the shape.

**Reading somebody else's hand** — `show:<scope>[:optional]`, which puts the
**real** cards into the offer rather than the copies `options:` deals. A copy of
a chip is a different chip and cannot be taken, which is the whole difference
between a menu and a hand. Each borrowed card remembers where it came from and
goes home when the offer closes; choosing one runs the *asker's* new `chosen`
block with the pick as its target, because the pick is somebody else's property
and carries none of our rules. Pilebunker is built on it.

**A question that may go unanswered** — the word `optional` on an offer, which
puts a **No choice** button under it. `dismissable` existed and was
right-click-only, which is not discoverable and does not exist on a touch
screen.

**A card with nothing to run is not a move.** The Wound has no `play` block —
that is what *this chip does nothing* means — and it was playable, cost nothing
and changed nothing. Worse, it is exactly the card the soft-lock escape hatch
would offer forever, since a card with no cost and no needs never reaches that
gate. A bot ran 4000 moves in six rounds clicking one.

**`refill_from` on a zone**, which deleted the three-phase draw loop and fixed a
real bug at the same time. The loop reshuffled *between* phases, so the cleanup
draw was right and **Draw Three on a short bag silently came up short** — a
card's action list cannot branch, and no phase runs between two draws. A zone
that knows its own discard closes the loop wherever it runs out, and the cleanup
phase is one `draw_from` again. Fired on being *drawn from* and found empty
rather than on emptying, so a rule that clears a pile on purpose is left alone.

**Two labels read off the engine** — a zone whose `label` is `current_phase` or
`current_player` prints what the engine says rather than a fixed word. A board
shows what is where and cannot say whose turn it is.

The layout was rebuilt around all of it: the bank a two-wide column down the
left (a chip is taller than it is wide, so nine pairs beat one long strip), the
two seats mirrored with nothing between them, the buttons on the middle line
between the gem piles, and the character card beside its owner's bag instead of
taking the middle of the table. **South is seat one and south is the near
edge** — a per-seat zone takes its rects in seat order, and written the other
way round the opening pick is made for the player across the table.

The roster stopped being a zone. Ten characters want half the screen for one
click and nothing at all afterwards; the offer is drawn over a dimmed board and
is not there when it is closed, so the pick is `options:` and the phase ends on
a flag rather than on `ends_after` — choosing out of an overlay is deliberately
not a play.

## Stage 5 — two rules read wrong (2026-08-23)

The owner caught both, and both were transcription rather than build.

**The piggy bank is not "+1 buy".** There is no second buy in Puzzle Strike —
you buy one chip a turn and nothing raises it — and the icon read here as a buy
is the **Piggy Bank option**, which [rules.md](puzzle_strike/rules.md) §4 had
quoted from the rulebook all along: *"During the cleanup phase, you may keep a
chip in your hand that you didn't play rather than discard it. If you do, draw
one less chip at the end of the turn."* Six chips in the catalogue said the
wrong thing, and the game gave the wrong benefit.

It builds out of what already exists and needed no engine work: a per-seat
`stash` deck, a rule card gated on `piggy@mine.player >= 1` that runs
`show:mine.hand:optional`, a `chosen` block that moves the pick to the stash and
docks `to_draw`, and one `move:mine.stash:mine.hand` at the top of the next
turn. **Cleanup had to become two phases** — an offer opens over the phase that
ran it and the rest of that phase's list has already gone by, so discarding the
hand the chip was kept out of belongs to the phase after.

**Arrows have colours, and the restricted one must be spent first.** A black
arrow pays for any chip; brown, red, blue and purple each pay only for a chip
whose own banner matches (§2).

The first build of this made a `cost` a list of *alternatives*, which the owner
refused, and rightly: it put the same list on forty cards, made the order the
author's problem, and said on the card a thing that is true of the resource.
What replaced it is **`pays_for` on the stat** — `acts` declares that it may be
spent as any of the four colours, once, and a chip's cost is flatly one arrow of
its own colour. Which pool actually drains is a matching the engine solves: most
constrained demand first, own stat before any substitute. Magic's *four generic
and three red* is the case that proves the rule needs both halves, and
[`tests/integration/substitution.lua`](../tests/integration/substitution.lua)
is that case. The greedy is exact while the substitution sets are nested or
disjoint, and the validator refuses any other shape, so what loads is paid
correctly.

Two consequences. The action phase lost its `ends_when`: "no actions left" is
one comparison and there are now five pools, and it was the wrong question
anyway — the rulebook says play *up to* one chip, so declining to spend an arrow
is a move. Done acting is the answer. And "yellow" throughout the catalogue was
a misread of the tan arrow; the rulebook's colours are brown, red, blue, purple.

### Left

- **Counter-crashing**, and with it Bubble Shield, Unstable Power's reaction
  half, Rigorous Training, Gems to Lemonade, Stone Wall, Thinking Ahead — every
  blue banner in the game. Shared with [18](18-legends-of-runeterra.md).
- **The other fourteen Puzzle chips**, and the whole Shadows expansion — ten
  more characters and twenty-four more Puzzle chips. **The catalogue is now
  complete**: every base chip, every Shadows chip and every one of the sixty
  character chips is transcribed in
  [puzzle_strike/chips.md](puzzle_strike/chips.md), from the owner's own
  photographs and inventory. Three things are still open there and none of them
  blocks a build: which Shadows character owns which trio (the grouping is
  certain, the ten names are matched to it by guesswork), The Hammer's banner,
  and Custom Combo's wordless arrow burst.
- **Ongoing chips that change somebody else's rules** — Protective Ward's
  combine tax, Flagstone Tax, Panda's Bargain's condition. An ongoing that
  changes *your own* ante works (Dragon Form), because the number it moves is
  recomputed at the start of every ante.
- **3–4 players.** Wants the lowest-pile winner (`min:` shipped with
  [22](22-the-crew.md)), a crash that names *which* opponent, and floating gems.
- **Bank exchanges** — Training Day, Purge Bad Habits' full text, Chips for
  Free: "trash a chip, take one costing up to 2 more" needs a cost comparison
  between two cards, which nothing says yet.
