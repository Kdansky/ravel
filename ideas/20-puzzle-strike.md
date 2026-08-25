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

## Stage 6 — what reactions unblocked, and what is still left (2026-08-25)

[27](27-reactions-and-the-stack.md) shipped the response window, so the "Left"
list above is out of date in one direction and more precise in the other. Every
chip carrying a `DEV:` note in `puzzle_strike.json` was re-read against the
engine as it now stands.

### Now buildable — content work, not engine work

- **Unstable Power's reaction half.** "The engine refuses a chip played out of
  turn" was the reason, and it is exactly the thing that was built. The chip
  wants a second entry under `reactions` answering `crash`, running what its
  `play` already runs.
- **Hex of Murkwood** — *each opponent gains a wound or discards two wounds*.
  Verified with a throwaway game: a **mandatory reaction on a card in the
  opponent's own board zone**, whose action is `options:…`, opens the offer for
  *them* — priority is theirs while it is up, so both the choice and its
  consequences read as the opponent, and the turn never moves. The chip emits a
  verb; the answer lives on a card each seat has on the board. The seat cards
  (`south`/`north`) sit in the injected `sys` grid and are the natural home;
  each character card in `fighter` is the alternative.
- **Troublesome Rhetoric** — *chosen opponent chooses your benefit* — is the same
  pattern, and its DEV note ("nothing makes the opponent press the button") is
  the same stale reason.

The awkwardness in both is that **a reaction cannot be granted by a tag**, the
way an ability can. The rule for one chip has to be written on whatever card
each seat keeps on the board, rather than on the chip that has it.

### Still blocked, by feature

**A card cannot answer its own controller's action.** The window skips the
announcing seat, which is what makes "everybody passed" a state that arrives.
Verified: the opponent's copy of a mandatory reaction fires and yours does not.
This is Magic's *whenever you cast a spell* and it is not sayable.
→ **Panda's Bargain** (*at the end of any turn you bought a Puzzle chip, +1
chip*), and every ongoing that watches its own owner.

**No way to make an announcement unanswerable.**
→ **Dragon Form**, *your purples can't be reacted to*.

**No gate on which piles may be bought from.** An `activate` block has no
`needs`, and money gates *at most*, never *exactly* or *not that one*.
→ **Dragon Form**, *you can't buy purples*; **Martial Mastery**, *costing exactly
2 more*; the bank exchanges from Stage 5 (Training Day, Chips for Free).

**Nothing runs after an interjected phase closes.** A reaction can hand a phase
to a player (Rigorous Training does), but the action list that pushed it has
already run to completion, so it cannot branch on what they did in there.
→ **Protective Ward**, *players can't combine unless they discard a Puzzle chip
first* — the tax has to be offered to somebody else and then checked.

**No "play this card's action" primitive.**
→ **Double-take**, *play it twice*.

**A pile and a bag are reached from the top.**
→ **Burning Vigor** (a wound from hand *or discard pile*), **It's Time for the
Past** (a chosen chip out of the discard), **Research & Development** (a purple
found in a shaken bag).

**`show:` cannot narrow what may be picked.** It opens a real hand and takes any
card back; there is no `where` on it the way a `target` has one.
→ **Pilebunker**, *trash their largest gem* — nothing enforces largest, or gem.

**No random reveal, and no branch on what was revealed.**
→ **Jackpot**, *reveal two at random; if both are purples…*.

**The order cards go back in is not the player's to say.**
→ **Future Sight**, *put two chips on top of your bag in any order*.

## Stage 7 — copy, the ends of a pile, and one card of a hand (2026-08-25)

Four small primitives, and a re-read of Stage 6's blocked list that found two
entries were never true.

### What was built

- **`copy:<scope>[:play|activate[:<n>]]`** — a card's action list runs without
  the card being played: nothing created, nothing spent, no cost paid, the card
  does not move. Bounded against a card that copies itself.
- **`:top` / `:bottom`** on `move`, `move_target_to`, `add_to`, `draw_from` and
  `return_to`. The top of a pile was always the end of its list and always where
  an arrival landed; `bottom` is the end that could not be reached at all.
- **`show:random.<scope>`** — the quantifier `move` and `destroy` already take,
  meaning here what it means there: one of them, by the seeded generator.
- The validator learned that **an amount is one slot or five**, so a word written
  after `sum:value@spare` is no longer checked against whatever the measure left
  standing. That is what made a trailing argument possible at all.

### Unblocked

- **Double-take** — *play it twice, trash it*. `copy:target:play:2` then
  `destroy:target`. The Stage 6 entry ("no play-this-card's-action primitive")
  is closed.
- **Future Sight** — *put two chips on top of your bag in any order*. Verified:
  targets arrive in the order they were picked, and `move_target_to:mine.bag:top`
  puts them back in that order. The Stage 6 entry was **wrong**, not blocked —
  the order was the player's all along and nothing said so.
- **Burning Vigor**, **It's Time for the Past** — *from your discard pile*. Also
  wrong rather than blocked: `show:` opens the **real** cards of any zone, a
  deck and a pile included, and `chosen` takes the pick. Verified with a
  throwaway game reaching into a face-down bag. "A pile is reached from the top"
  was true of `draw_from` and of nothing else.
- **Jackpot's first clause** — *reveal at random from their hand* —
  `show:random.enemy.hand`. Two at once, and branching on what came up, are still
  missing, so the chip is not finished.

### Still blocked, and one that never was

The Stage 6 list stands otherwise. One correction to its framing: **making the
opponent choose does not need a reaction at all.** Verified —
`set_priority:enemy.player` followed by `show:mine.hand` opens *their* hand to
*them*, because every scope is relative to whoever is up; the pick runs `chosen`
and `clear_priority` sends priority home, with the turn never moving. The
mandatory-reaction route from Stage 6 works too, but it is the long way round
and it needs a card on their board to hang the rule on.

That leaves, unchanged: no way to make an announcement unanswerable (Dragon
Form); no gate on which piles may be bought (Dragon Form, Martial Mastery, the
bank exchanges); nothing running after an interjected phase closes (Protective
Ward); a card cannot answer its own controller's action (Panda's Bargain); and
`show:` cannot narrow what may be picked (Pilebunker, Research & Development) —
which, now that reaching into a pile turns out to be free, is the one missing
piece doing the most damage.

### Not a bug: the bank is the same every game

The bank does not shuffle because **nothing asks it to**. `setup.place` names all
eighteen chip stacks explicitly and the bank grid holds exactly eighteen, so
there is no draw to randomise — the RNG is seeded from the clock and is working.
Puzzle Strike proper deals ten piles out of a much larger set; that needs more
chip stacks written than the bank has room for, and then a hidden pool zone,
`shuffle`, and `draw_from:pool:bank:n`. Content work, and it cannot start until
there are more chips than slots.

## Stage 8 — the whole box, and a bank you build (2026-08-25)

### First, a landmine that had already been armed

`tools/make_puzzle_strike.py` had drifted **seventy-six cards** behind
`game/games/puzzle_strike.json`. Running it would have silently deleted the
entire reaction feature — the `react_buy` phase, the `pending` stack zone, the
`spent` migration, every `reactions` block, the `price` on every chip — and
nothing would have failed, because a generated file that has been hand-edited
looks exactly like one that has not.

The generator now reproduces the shipped game exactly, and
`tests/integration/generators.lua` holds all four generated games to their
scripts so this cannot happen again. The other three (Lost Cities, Splendor, The
Crew) were already in sync.

**The rule this establishes: hand-edit the generator, never the game file.**

### The box

All fifty-one Puzzle chips are now defined — twenty-four base, twenty-four
Shadows, three promotional — transcribed from `ideas/puzzle_strike/chips.md`
with printed text, cost, banner and stock. Ten of them make a bank, so the other
forty-one live in a hidden `chip_box` zone.

- **18 are built whole**, with no note: Axe Kick, Button Mashing, Dashing Strike,
  Degenerate Trasher, Draw Three, Ebb or Flow, Gem Essence, It's Combo Time,
  One of Each, One-Two Punch, Punch Punch Kick, Really Annoying, Recklessness,
  Risky Move, Roundhouse, Safe Keeping, Sneak Attack, The Hammer.
- **31 are built in part**, each carrying a DEV note saying exactly what is
  missing. Three of those notes now say *built whole* for a clause that used to
  be impossible — Training Day, Chips for Free and Pick Your Poison.
- **2 are not playable at all**: Option Select and Custom Combo.

### The bank is drafted

The old complaint — *"I get the exact same bank every game"* — was never an RNG
bug. The generator named the ten and the RNG was never asked for anything. It
is a draft now, and it needed no new engine anything:

- **Choose a chip** opens the box face up in the offer, all fifty-one plates, and
  the pick goes into the bank. Press it as often as you like.
- **Randomise the rest** shuffles what is left and deals the shortfall — ten less
  however many Puzzle chips are already standing there, floored at nothing,
  which is one subtraction rather than a branch.

The phase ends when the bank holds ten of them. The eight that are always there
(four gems, Combine, Crash Gem, Double Crash, Wound) never enter the count.

### What each unfinished chip is still missing

| Chip | What is built, and what is not |
|---|---|
| **Bang then Fizzle** | the gem-pile gate is built. Once-per-turn is not: nothing marks a chip as already used this turn. |
| **Blues Are Good** | the search and the immunity are built — the bag really opens, face up, and you take one. Nothing narrows the pick to a blue chip. |
| **Chip Damage** | the action and the chip off the discard pile are built. "A purple or two chips" is their choice narrowed to one banner colour, and show: cannot narrow what may be picked. |
| **Chips for Free** | built whole, the same way Training Day is: the allowance is money and the piles price themselves. |
| **Color Panic** | the action is built. The discard is narrowed by a colour the player picks as the chip runs, and neither the narrowing nor a branch on whether they could is sayable. |
| **Combinatorics** | the action is built and laying it out says you have it. Both ongoing clauses watch your own play, and a card cannot answer its own controller. |
| **Combos Are Hard** | it ends your action phase and trashes itself. "The only action you play this turn" cannot be asked — nothing counts the actions a player has played — so the two chips are not given. |
| **Custom Combo** | not playable, and not transcribed: chips.md reports the arrow rows are legible as shapes and not as amounts, so what this chip gives is unknown. Guessing it would be the one invented chip in the box. |
| **Gems to Gemonade** | both halves fire; the +$1 per gem is owed in a later phase, and nothing defers a payment. |
| **Hundred-Fist Frenzy** | laying it out says you have it. Both clauses watch your own actions, and a card cannot answer its own controller. |
| **Improvisation** | the two chips are drawn. "The other drawn chips" needs the set a draw just produced, which nothing keeps. |
| **Iron Defense** | the Crash Gem arrives in your gem pile. Playing a card out of a gem pile is not built — a zone can grant what lying in it lets a card do, and this one does not. |
| **It's a Trap** | the action is built and the chip trashes itself. A token that sits on a bank stack and changes what buying from it does is a rule on somebody else's card, which nothing writes. |
| **Just a Scratch** | built, with the trash reaching your hand rather than the discard pile. |
| **Knockdown** | the action and their discard are built, and the discard really is their pick: priority goes to them while the offer is up. Barring an announcement from being answered has no spelling. |
| **Master Puzzler** | it ends your action phase and trashes itself. "Play them" would be copy:, but the bank holds plates rather than chips and there is no instance to copy. |
| **Mix-Master** | the combine is built. "The largest gem" needs a pick chosen by a number rather than by a player, which no scope says. |
| **Money for Nothing** | both halves are built; the chip is not offered the choice of trashing itself. |
| **Now or Later** | built, with the trash reaching your hand rather than the discard pile. |
| **One True Style** | the three actions are built; the combine is not, since it would want its own pair of targets alongside them. |
| **Option Select** | not playable. copy: runs a card's action list, and the bank holds plates rather than chips — there is no instance of the thing being copied. |
| **Ouch!** | the ante and the wound are built. Trashing a named chip out of their discard needs a pick narrowed to one card, and once-per-turn is not marked. |
| **Pick Your Poison** | built whole, and the choice really is theirs: priority goes across while the offer is up and comes home when it closes. |
| **Repeated Jabs** | it always goes back on top of your bag rather than to the table. "You may" would be an offer of two landings, and where a chip lands is one word. |
| **Risk to Riskonade** | the ante and the draw are built; the chip is not offered the choice of trashing itself. |
| **Sale Prices** | the gem power is built. A cost is a fixed number in this engine — no measure may stand in one — so nothing can make the bank cheaper for a turn. |
| **Secret Move** | the action and the piggy bank every turn are built. Discarding it when *you* buy a purple would be a reaction to your own controller's action, which the response window skips on purpose. |
| **Self-Improvement** | both halves are built; the trash reaches your hand only, and reaching the discard pile as well is content work — show:mine.discard opens its real cards. |
| **Signature Move** | the bag opens face up and you take one. Nothing narrows the pick to a character chip, and the free play afterwards is not built. |
| **Stolen Purples** | their hand opens and you take one card to your discard. Nothing enforces that it is a purple, and the rest of their purples are not discarded. |
| **Thinking Ahead** | the gem power and the immunity are built. Redirecting what you buy onto your bag would mean answering your own purchase, which the window skips. |
| **Training Day** | built whole. The allowance is handed over as money and the ordinary price of every pile does the gating, so "up to 2 more" needed nothing new. |
| **X-Copy** | built with copy:, which runs the chosen chip's play twice without playing the chip. Nothing narrows the pick to those three kinds. |

### The same list, grouped by the missing feature

Thirty-three unfinished chips, and only eight things are missing:

1. **`show:` cannot narrow what may be picked.** It opens a zone's real cards and
   takes any of them; a `target` has a `where`, an offer does not. **Nine chips**
   — Blues Are Good, Chip Damage, Color Panic, Mix-Master, Ouch!, Pilebunker,
   Research & Development, Signature Move, Stolen Purples. By a distance the
   most expensive gap in the game, and it got worse rather than better when
   reaching into a bag and a discard pile turned out to be free.
2. **A card cannot answer its own controller's action.** The window skips the
   announcing seat, which is what makes "everybody passed" a state that arrives.
   **Five chips** — Combinatorics, Hundred-Fist Frenzy, Panda's Bargain, Secret
   Move, Thinking Ahead.
3. **No gate on which piles may be bought, and no exact price.** Money gates *at
   most*, never *exactly* or *not that one*, and a cost is a fixed number so
   nothing can discount the bank. **Three chips** — Dragon Form, Martial Mastery,
   Sale Prices.
4. **No instance of a bank chip to copy.** `copy:` runs a card's action list and
   the bank holds *plates*; the chip itself is still in the box. **Two chips** —
   Master Puzzler, Option Select. X-Copy works because it copies a chip in a
   *hand*.
5. **Nothing marks a chip as used this turn.** **Two chips** — Bang then Fizzle,
   Ouch!.
6. **Nothing offers a choice of where a card lands, or defers a payment, or
   remembers what a draw just produced, or counts the actions a player has
   played.** One chip each — Repeated Jabs, Gems to Gemonade, Improvisation,
   Combos Are Hard. Also Money for Nothing and Risk to Riskonade, which only
   want "you may trash this".
7. **No way to make an announcement unanswerable** (Dragon Form), **nothing runs
   after an interjected phase closes** (Protective Ward), **a zone cannot grant
   play to what lies in it here** (Iron Defense), **and nothing writes a token
   onto a bank stack** (It's a Trap).
8. **One chip cannot be transcribed at all.** Custom Combo is five rows of arrows
   that `chips.md` reports are legible as shapes and not as amounts. Guessing it
   would be the one invented chip in the box, so it is present, priced, and
   unplayable.

**If one thing gets built next, it is (1).** A `where` on `show:` — the same
condition list a target already takes, asked of each borrowed card — closes nine
chips on its own and finishes Pilebunker, which has been the standing example of
the gap since Stage 4.

## Stage 9 — `chosen.where`, and the gap it closed (2026-08-25)

Stage 8 ended by saying that if one thing got built next it should be a `where`
on `show:`, because it was the only missing feature costing more than two chips.
It is built, and it needed no new grammar: the asking card's `chosen` block
takes the same `where` a target already takes, asked the same way — candidate as
`@target`, asker as `@self`.

**The whole scope still comes up.** Revealing a hand is half of what Pilebunker
and Stolen Purples say, so what is narrowed is the *pick*, not what is shown: the
cards that do not qualify are revealed and dimmed. Two things fall out of that —
an offer where nothing qualifies is a mandatory question with no answer, so it is
not asked at all; and an entry `options:` *dealt* is never narrowed, since it came
off the asker's own list and writing a shorter list is how you narrow one of
those.

"The largest" turned out to be the interesting case and needed nothing special:
`sum:value@target >= max:value@options` compares the candidate with the offer it
is lying in.

### What it closed

| Chip | Now |
|---|---|
| **Pilebunker** | built whole — their hand is revealed, and only the largest gem may be taken |
| **Blues Are Good** | built whole — the bag opens, and only a blue chip comes out |
| **Burning Vigor** | built whole — the discard pile opens, and only a wound |
| **It's Time for the Past** | built whole — a *chosen* chip out of the discard, not the top one |
| **Research & Development** | the bag opens and a purple comes out; the chip given back in exchange is still not asked for |
| **Signature Move** | narrowed to a character chip; playing one free afterwards is still not built |
| **Stolen Purples** | you take a purple rather than any card; the rest are still not discarded |

Nineteen chips built whole, up from eighteen, and four of the seven above went
from a caveat to none.

### Still open

Three of the nine are not about narrowing after all:

- **Mix-Master** wants *the largest gem in each opposing gem pile* with no offer
  involved — a scope that picks by a number rather than a player, which is a
  different feature.
- **Color Panic** narrows by a colour the player picks *as the chip runs*, and a
  `where` is written before the game starts.
- **Ouch!** and **Chip Damage** want the opponent to pick out of their own zone
  narrowed — both are now sayable (priority crosses, and their offer takes its
  own `where`) and neither is written yet.

The next most expensive gap is the one under it: **a card cannot answer its own
controller's action**, which is five chips.

## Stage 10 — a reaction says whose announcement it answers (2026-08-25)

Stage 9 ended by naming the next most expensive gap: **a card cannot answer its
own controller's action**, five chips. That was never a rule anybody wanted — it
was what the window did in order to make "everybody has passed" a state that
arrives, and it is half of what a stack is for. You put a spell up and then
answer it yourself; no opponent is involved.

`whose` says which, in a scope's own words: **`enemy`** (the default, and what
every reaction meant before), **`mine`**, **`anyone`**. A word rather than a
flag, the same shape `forced` and `from` already have, and the same closed set
the scope grammar already reads.

Termination was never the seat check's job. **One card answers one record once**,
and an answer is a *new* record with its own memory — so a chain gets longer
rather than going round. The one shape that could still run away, a mandatory
reaction on a card that never leaves the board answering the verb its own
answers go up as, hits a stack depth it will not pass, is marked as having had
its go, and unwinds on the next pass.

### What it closed

| Chip | Now |
|---|---|
| **Secret Move** | built whole — it discards itself when *you* buy a purple |
| **Hundred-Fist Frenzy** | you may crash a gem after your own red attack. "Discard if an opponent skips his action phase" is still not built |
| **Panda's Bargain** | the chip comes as you buy the Puzzle chip rather than at the end of the turn |

### And what it did not

Two of the five turned out to be waiting on something else:

- **Combinatorics** wants *whenever you play a Combine*, and nothing announces a
  Combine being played — there is no verb for it to answer. Its other clause,
  *discard when your gem pile totals 5 or less*, is a **state** rather than an
  event, and a reaction subscribes to events.
- **Thinking Ahead** wants what you buy to land on your bag. The buy is
  answerable now, but the event names the *plate* and not the chip it dealt into
  your discard, so there is nothing to move.

Two things fall out of that pair, and they are the same thing said twice: **a
turn ending, a phase going by, and a number crossing a line announce nothing**,
so nothing can answer them; and **an event carries its cause, not its effect**,
so a reaction cannot reach what the thing it answered created. Panda's Bargain
and Hundred-Fist Frenzy are both approximations for the first reason.

## Stage 11 — a phase announces itself (2026-08-25)

Stage 10 ended on a pair of sentences that were the same sentence twice: **a turn
ending, a phase going by and a number crossing a line announce nothing**, so
nothing can answer them. The first of those is now false.

A phase carries `emits` the way a card does, keyed by the two hooks it already
had — `begin` beside the actions it runs on entry, `end` beside the hand it
discards on the way out. The subject is the player card of whoever the phase
belongs to, so `whose: "mine"` reads there exactly as it does everywhere else,
and *"at the end of your turn"* has somewhere to be said at last. Nothing is
deferred: a phase has no action list waiting on the answer, so the announcement
goes up, the phase carries on, and whatever answers it resolves beside it —
which is how the sentence reads at a table.

`cleanup_draw` emits `turn_end`, since it is the last thing a turn does.

### Two bugs the ongoing row had been hiding

Writing an ongoing chip that reacts turned up two things that had been broken
since the `spent` migration and that nothing had caught:

- **`"from": "board"` meant "on a grid".** Puzzle Strike lays ongoing chips in a
  per-seat face-up zone, which is a *hand* as far as zone types go, so every
  reaction on a laid-out chip was unreachable. `from` takes a zone by name now.
  Guessing which face-up zones count as in play was the alternative, and it gets
  a discard pile wrong.
- **A card whose whole play was going somewhere could not be played.** Once
  `spent` took over the going, its action list was empty, and *"a card with
  nothing to run is not a move"* refused it outright. **Dragon Form has been
  unplayable since reactions shipped.** A card that says where it lands does
  exactly one thing when clicked, and that one thing is the move.

### What it closed

| Chip | Now |
|---|---|
| **Panda's Bargain** | built whole — the buy sets a flag, the turn ending pays the chip, exactly as printed |
| **Dragon Form**, **Hundred-Fist Frenzy**, **Secret Move**, **Combinatorics** | playable again, which they had not been |

### Still open

The other half of Stage 10's pair stands: **an event carries its cause, not its
effect**, so Thinking Ahead's buy names the plate and not the chip it dealt.
Combinatorics still wants a verb for *a Combine was played* that nothing emits —
a tag on the purple chips would give it one, which is content work now rather
than engine work. And Hundred-Fist Frenzy's *"discard if an opponent skips his
action phase"* is not a phase beginning or ending but a phase passing
**unused**, which is a different fact and still announces nothing.

