# 18 — Legends of Runeterra

**Status:** **stage 1 done** — [lor/rules.md](lor/rules.md) and
[lor/decks.md](lor/decks.md) · **Size:** large, and the first deliverable was a
document rather than code · **Depends on:** [01](01-boardgames.md) gap 5
(triggers) for anything past the vanilla prototype

> *So, let's try a big one: Write an .md file that writes down the rules of
> Legends of Runeterra. Then read it, and see if it's correct. If necessary,
> repeat this until it's satisfying. Copy down two relatively simple decks with
> all their card's texts. I want to implement LoR instead of MTG, purely because
> it's more streamlined and MTG is full of annoying edge cases.*

[01](01-boardgames.md) already refuses full Magic in as many words — *the
comprehensive rules are a programming language with a priority stack and
replacement effects* — and names Hearthstone as the creature-combat target
instead. LoR is a better choice than either: it is a real, current, two-player
card game with a small closed rule set, and it is the first target on the ladder
that would make ravel a *card game* engine rather than a board game engine that
also holds cards.

---

## Stage 1 — the rules document, and why it comes first

**Deliverable:** [Assumption: `ideas/lor/rules.md`, with the decks beside it in
`ideas/lor/decks.md` — a subfolder rather than a numbered file, because the
rules of somebody else's game are reference material and not an idea about
ravel.]

The instruction *write it, read it, see if it's correct, repeat until it's
satisfying* is the important part of this stage and not a formality.
[Assumption: writing it means writing it from recollection, which is exactly the
thing that produces a confident, subtly wrong document — the wrong mana curve,
a keyword's interaction misremembered, a phase boundary in the wrong place. The
re-read loop is the check that exists in place of a source. If a rulebook or a
wiki is reachable at the time, use it and say so in the file; if not, the
document must say which parts are recalled rather than verified, because
building against a wrong rule costs far more than writing "unsure" costs.]

**What the document must contain**, because these are the parts an
implementation will ask about and a summary always omits:

- The round structure: who gets the attack token, when it passes, what refills.
- Mana: the gem count, how it grows, and how banked spell mana differs.
- The action loop: what a "pass" is, what ends a round, and when a player may
  respond to what.
- Combat in exact order: declaring attackers, declaring blockers, what happens
  to unblocked units, when damage lands and whether it is simultaneous.
- Every keyword in the two decks, written as a rule rather than as flavour.
- The board limits: hand size, bench size, deck size, how the game ends.

**Acceptance criterion, borrowed from [10](10-schema-document.md):** the
document plus a short list of what writing it exposed — every rule that turned
out to need a paragraph, and every one that ravel cannot express. That second
list *is* stage 2.

### What writing it exposed

**It was written from sources, not from recollection, and that changed an
answer.** Riot's own rules pages render in JavaScript and fetch as blank, so the
spine is the Riot-hosted wiki with gamepressure for the turn structure. Every
rule in the document is marked **(v)** verified or **(r)** recalled, and the
Round FAQ — unreadable, and the authority for most of the **(r)** lines — is
named as the first place to check. That distinction is the deliverable as much
as the rules are.

- **"Simultaneous combat" was wrong, and it is the correction that matters
  most.** Strikes resolve **left to right by board position**, one pair at a
  time. Building simultaneous resolution first would have been the misremembered
  rule this whole stage exists to catch — and the truth is *better* news, since
  an ordered run of cards in a zone is a thing ravel already has.
- **Blocking is one to one, and cannot be anything else.** No double-blocking in
  either direction — which, with strikes resolving by position, is what makes it
  *placement* rather than a stored relation. See "Blocking is placement" below;
  it is the finding that took a missing capability off the list.
- **The stack is bounded more sharply than expected**, though the bound is
  recalled rather than verified: **Burst and Focus never enter it at all**, since
  they resolve on the spot. A response stack is therefore only Fast and Slow, and
  the four speeds are really *two* questions — may this be played during combat,
  and may the opponent answer before it resolves. Two booleans, not four cases.
- **Damage persists across combats within a round** and clears at round start,
  which is why Regeneration is a keyword. A game that healed at end of combat
  would be a different game.
- **Three rules turned out to be free**, and none was on the capability table:
  round 40 is a tie (an end condition on the round counter), decking out is a
  loss (`zone_empty` already), and the attack token returning through Scout is a
  seat stat.
- **Two were not free and are new to the list.** The **mulligan** is *draw four,
  replace any subset* — ravel's offer overlay picks exactly one, and choosing a
  subset is a different interaction. And the **hand cap of 10** is a bound on a
  zone that has none: a grid is bounded by its cells, a hand is not bounded at
  all.
- **A question for whoever builds champions**: level-up transforms in place
  *keeping the damage already taken*. `become` shipped for chess promotion, where
  the pawn had no damage to keep — so whether it preserves stats is worth
  checking before it is relied on.
- **The card texts did not survive the same standard**, and
  [lor/decks.md](lor/decks.md) says so rather than approximating them. The deck
  list is real and second-hand; the text is in Riot's Data Dragon
  (`dd.b.pvp.net/latest/set1/en_us/data/set1-en_us.json`, confirmed reachable and
  machine-readable), which is a few megabytes and wants downloading rather than
  fetching. **Milestone 1 needs none of it** — its decks are vanilla bodies —
  so this blocks nothing yet.

## Stage 2 — what LoR names that the engine lacks

The ladder's discipline is *each target game names one missing capability*. LoR
names three, and the honest reading is that it names them because it is a
different genre, not because it is unusually complex.

| LoR rule | Ravel today |
|---|---|
| Nexus health, mana, deck of 40, hand of 10 | seat stats and per-seat zones — **exists** |
| Bench and battlefield | two grid zones per seat — **exists** |
| Drawing at round start, mana refilling | `turn.action` on a round wrap — **exists** |
| The attack token alternating | a seat stat plus phase routing — **expressible**, no engine work |
| Champions levelling up | `become` — **shipped**, and it was chess promotion that paid for it |
| Ephemeral, Fleeting | a tag plus a round-boundary action — **expressible** |
| Play / Last Breath / Round Start abilities | **[01](01-boardgames.md) gap 5, triggers** — not started |
| ~~**Blocking: which unit blocks which**~~ | **not missing — it is placement.** Six lanes a side, and a unit fights what is across. Strictly one to one, which is what a lane is. See below |
| **Combat damage, ~~simultaneous~~ left to right, then deaths** | **missing** — a walk along the lanes. *Corrected by stage 1: strikes resolve by board position, one pair at a time, not all at once* |
| **The pass, and responding to a spell** | **missing** — a bounded stack, and stage 1 narrows it: Burst and Focus never enter one |
| Spell mana, spendable only on spells | **missing, and small** — a cost paid from either of two pools by a rule |
| Mulligan: draw 4, replace any subset | **missing** — the offer overlay picks exactly one |
| A hand that holds at most 10 | **missing** — a grid is bounded by its cells, a hand by nothing |
| Round 40 is a tie · decking out loses · Scout returns the token | **expressible** — an end condition on the round counter, `zone_empty`, and a seat stat |

### Blocking is placement, and that is the whole of it

*Decided 2026-08-16, and it replaces the design this section used to carry.*

**Six lanes per side, and a unit fights whatever is across from it.** The
battlefield is a grid of six addressed cells, an attacker is placed in a lane, a
blocker is placed in the lane opposite, and combat walks the lanes. There is no
relation to store, because the board already holds it.

**Stage 1 is what makes this a reading of the rule rather than a convenience.**
Blocking is strictly one to one with no double-blocking in either direction, and
strikes resolve **left to right by board position** — so LoR's own resolution
order is a walk along the lanes, and the game lines blockers up opposite
attackers on screen for exactly that reason. A lane index is not a stand-in for
the pairing; it *is* the pairing, in the game as well as in the model.

Everything it needs is built: a `grid` zone with addressed cells, `per_seat` so
each side has its own, `place_in_slot` with its `on_occupied` rule, ownership as
placement state, and `col`/`row` stamped on every slot so a condition can ask
what is across ([14](14-kinds-and-placements.md), [08](08-grid-movement-notation.md)).
An attacker whose opposite lane is empty is the unblocked case, and it is an
empty-square test rather than an absence of relation.

**So `attach_to_target` is not this track's customer after all.** It stays
[15](15-many-on-one-square.md)'s open question until the thing it was made for
turns up — the **Attach** keyword, where a card genuinely rides another and
moves with it. That is a later milestone and it will ask 15's four thin
questions properly (detaching, what happens when the parent dies, whether a
child can be targeted alone) instead of a blocker asking them for one turn and
then dissolving.

### The pass is a stack, and it is a small one

This is where "more streamlined than MTG" has to be tested rather than
believed. [Assumption: from recollection, LoR keeps a stack — a spell can be
responded to and the responses resolve last-first — but bounds it in ways MTG
does not: no permanents entering as a response, a small closed set of spell
speeds, and a round that ends when both players pass in succession. If that is
right, it is a *bounded* version of the exact thing `01` refused, and the
refusal was about the unbounded one. The rules document is what settles this,
and it should be settled before any code, because the answer decides whether
this is a milestone or a project.]

**Stage 1 got halfway there and says so.** The round *does* end on two
consecutive passes (verified), the speeds *are* a closed set of four (verified),
and **Burst and Focus never enter a stack at all** — so what can wait to resolve
is Fast and Slow alone. Last-first draining is still recalled, not verified,
because the one page that would settle it is the one that would not render. The
four speeds collapse into two questions — *playable during combat?* and *may the
opponent answer first?* — which is a much smaller thing to build than four cases.

The engine has one relevant guarantee already: `flow.settle`'s 64-step budget
(ARCHITECTURE invariant 3), which is the same discipline `01` gap 5 requires of
triggers — *they queue, they never recurse*. A response stack drained by
`settle` under that budget is the shape to aim at.

## Stage 3 — the milestones, smallest first

Each ships a playable game file in `game/games/` and its own scripted test, per
`01`'s rule that every board game gets one.

1. **Vanilla combat.** Two decks of units with no text at all, no spells, no
   keywords: draw, play to bench, take the attack token, declare attackers,
   declare blockers, damage, nexus health, somebody wins. This is the milestone
   that proves the lane model and the combat resolution, and it needs no
   triggers. Four zones a seat — hand, bench, battlefield, deck — and the
   battlefield is the six-cell grid the lanes are cut from.
2. **Burst spells only** — the ones that resolve immediately, so there is still
   no stack. This is where a spell targets, and targeting already exists.
3. **The pass and the response stack.** Fast and Slow spells, and the round
   ending on two passes.
4. **Keywords**, one at a time, each as a tag with behaviour. [Assumption: the
   ones that only change combat arithmetic — Quick Attack, Overwhelm, Tough,
   Lifesteal — are the cheap half, and the ones that change *who may block* —
   Elusive, Fearsome, Challenger — are rules about the pairing and want the
   pairing to be solid first.]
5. **Champions**, which are `become` plus a trigger that watches the level-up
   condition — so they land after 01 gap 5 and not before.

**Two decks, not the card pool.** ~40 templates hand-written, which
[14](14-kinds-and-placements.md) shows is a readable size (chess is 13 cards and
279 lines) and does **not** want a generator — the generator is what 14 deleted.

**One line about provenance:** card text and names are Riot's. `CREDITS.md`
already exists as the place this repository records where content came from, and
`DESIGN.md` requires it stays accurate — a fan implementation of two decks
belongs in it beside the art.

## Refuse

- **A rules-complete LoR.** The same refusal `01` makes for Magic, for the same
  reason: the target is *a playable subset that is honestly the game*, not every
  card ever printed.
- **Building anything before the rules document is satisfying.** The whole
  request is shaped as document-first, and it is right: the cost of discovering
  a misremembered combat order after the combat code exists is the entire combat
  code.
- **Engine knowledge of a keyword.** A keyword is a tag with behaviour declared
  in the game file, exactly as `takeable` is. The moment `render.lua` or
  `flow.lua` knows what Overwhelm means, ravel is a LoR engine rather than a card
  game engine, and invariant 7 is gone.
- **The client, the collection, the levelling, the art.** This is a rules
  implementation played from a fixed deck list.
