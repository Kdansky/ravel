# 18 — Legends of Runeterra

**Status:** **stage 1 done** — [lor/rules.md](lor/rules.md) and
[lor/decks.md](lor/decks.md) — and **milestone 1 plays**: draw, mana, the pass,
the attack token, attackers and blockers as lane placement, the strike, the
Nexus, and a winner · **Size:** large, and the first deliverable was a
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
- **The card texts arrived after the first draft, and corrected it.** Riot's
  Data Dragon is 584 KB for set1, not the "few megabytes" the first pass guessed
  from a truncated fetch; both sets are now checked in under `lor/data/` and
  every card list is read out of them by a printed query. What that turned up is
  worth the trip: **four collectible units in the whole of set1 have no keyword
  at all.** Vanilla bodies are not "most of a real deck's bottom half" — that was
  recollection, and it was wrong. Milestone 1's deck is ten *text-free* units
  carrying two keywords between them, Tough and Overwhelm, both pure combat
  arithmetic and neither touching who may block.

## Stage 2 — what LoR names that the engine lacks

The ladder's discipline is *each target game names one missing capability*. LoR
names three, and the honest reading is that it names them because it is a
different genre, not because it is unusually complex.

| LoR rule | Ravel today |
|---|---|
| Nexus health, mana, deck of 40, hand of 10 | seat stats and per-seat zones — **exists** |
| Bench and battlefield | two grid zones per seat — **exists** |
| Drawing at round start, mana refilling | `turn.action` on a round wrap — **exists** |
| The attack token alternating | a seat stat plus phase routing — **built**, and it wanted *two* stats: `attacker` (whose round it is, persistent) and `token` (what the attack spends). What is still missing is that its holder should **act first**, which no routing can say — see [22](22-the-crew.md) |
| Champions levelling up | `become` — **shipped**, and it was chess promotion that paid for it |
| Ephemeral, Fleeting | a tag plus a round-boundary action — **expressible** |
| Play / Last Breath / Round Start abilities | **[01](01-boardgames.md) gap 5, triggers** — not started |
| ~~**Blocking: which unit blocks which**~~ | **not missing — it is placement.** Six lanes a side, and a unit fights what is across. Strictly one to one, which is what a lane is. See below |
| ~~**Combat damage, ~~simultaneous~~ left to right, then deaths**~~ | **built** — `activate_zone:battle` walks the lanes in slot order and every unit strikes what is `@across`; deaths are deferred to a `destroy:dead` after the walk, which is what makes a pair's strikes simultaneous while the pairs stay ordered |
| ~~Tough, Overwhelm~~ | **built, and as arithmetic** — Overwhelm is one term in the zone's own formula; Tough is one line on its own tag, over a damage channel (`incoming`) and a step. See *What milestone 1 cost* and *Tough is content* below |
| ~~**The pass**~~, and responding to a spell | the pass **shipped** (`6e29b75`) as a card on the table with a flag on it. The response **stack** is still missing, and stage 1 narrows it: Burst and Focus never enter one |
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

1. ~~**Vanilla combat.**~~ **Done** — `game/games/lor.json`, with
   `tests/integration/lor.lua` scripting it. Draw, play to bench, take the
   attack token, declare attackers, declare blockers, strike, Nexus, and a
   winner. The lane model holds and needed no triggers, and **Tough and
   Overwhelm came with it** rather than waiting for milestone 4, because both
   turned out to be arithmetic. What it cost is below.
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

**One line about provenance:** card text and names are Riot's. *Corrected by
stage 1: there is no `CREDITS.md` at the root — the one that exists is
`game/games/assets/CREDITS.md`, credits living beside the material they cover.
So the LoR data has its own, [lor/CREDITS.md](lor/CREDITS.md), in the same
spirit.*

## What milestone 1 cost, and what it taught

**Four engine words, and the whole of combat is content.** Nothing in
`flow.lua`, `predicate.lua` or `render.lua` knows what a lane, a blocker, Tough
or Overwhelm is — which was the refusal below, held.

| Added | Why LoR asked | Where |
|---|---|---|
| `where` on a **slot target spec** | a blocker's lane is *my row, opposite something already attacking*. `where` existed but only inside a `moves` rule, and a bench unit walks no pattern to reach the battlefield | `targeting.candidates` |
| `move:<scope>:<zone>` | "send the survivors home". Only the acting card (`move_to`) and the ones a player chose (`move_target_to`) could be moved; a set nobody picked had no verb. [23](23-splendor.md) named this same gap independently | `actions.lua` |
| `set_owner:<scope>:<who>` and **`receive.action`** | the pair the rule below needs to be honest: something has to be able to *change* an owner, and a pile anybody may take from has to say so itself | `actions.lua`, `zones.move_card` |
| **A card is born owned** | a unit played out of a seat's hand arrived on the shared battlefield belonging to nobody, so `mine`/`enemy` stopped seeing it | `cards.create` |

### Ownership is a property of the card, not of where it is lying

The last row started out in the wrong place and is worth recording as a
correction, because the wrong version *worked*. It first stamped the owner in
`zones.move_card` — a card leaving a seat's zone for a shared board took the
seat with it — bounded to grid destinations so that a Lost Cities discard, which
either player may take from, stayed unowned.

That is ownership as a **consequence of moving**, and it is wrong for a plain
reason: *whose a card is does not change when it moves.* It changes when
somebody takes it, and that is a rule a game says out loud.

So the stamp moved to `cards.create`: **a card dealt out of a seat's own zone is
that seat's from the moment it exists**, through the hand, the board and the
discard, and one born in a shared zone is nobody's and never gains an owner by
moving. Lost Cities needs no exclusion at all under that rule — its cards come
from one shared deck, so nothing it deals was ever anybody's — and the pile-vs-grid
carve-out disappeared with the version that needed it.

What the change *does* need is a way to say the exception, which is the third
row above: `set_owner:<scope>:<who>` (a seat, `mine`, or `none`), and a zone
moment to run it from. `receive` already said what a zone will take; it now also
says what it does about an arrival, with the zone as `@self` and the newcomer as
`@target`, exactly as `receive.needs` reads. Lost Cities' four discards carry
`"receive": { "action": ["set_owner:target:none"] }` — which changes nothing
today and states the rule rather than leaning on the accident.

Seats are numbered from 1 and **nobody is 0**, which is why "none" needed no new
storage: `tags.owner_of` reads the number, finds no seat at 0, and — the part
that matters — does *not* then fall back to the zone the card is lying in. Unset
is a third state meaning "never had one", and it stays distinct: a card nobody
ever owned is not the same as one taken away from somebody.

The golden traces are byte-identical across all of it.

### Three things the build settled that the design had not

- **Combat is a rule on the zone, not on the cards.** The battlefield carries
  `"applies": ["in_combat"]` and the tag def holds one ability with five
  actions; `activate_zone:battle` runs it for every unit standing there, in slot
  order. All ten templates stay text-free — they are stats, a picture and a
  price — and the two keywords are one term each in a formula nobody has to
  repeat. That is [01](01-boardgames.md)'s *when in doubt, decks and cards*
  arriving at rules rather than at objects.
- **A product stands in for a condition, and that is why no keyword needed a
  gate.** An activated ability has no `needs` — `activate_zone` is deliberately
  ungated, and `ACTIVATE_FIELDS` has never carried one — so every branch had to
  be arithmetic. `count:<tag>@<scope>` is 1 or 0, so multiplying by it *is* an
  if:

  ```
  gain_stat:health@across:count:tough@across                  Tough: hand one back, if it is tough
  lose_stat:spill@self:sum:spill@self:x:count:unit@across      a blocked attacker spills nothing
  lose_stat:spill@self:sum:health@across:x:count:overkilled@across:x:count:overwhelm@self:x:sum:attacking@self
  ```

  The last line is Overwhelm, and it works because **the excess is already on
  the board**: health is unclamped, so a blocker struck past zero carries the
  overflow as a negative number, and `overkilled` is a computed tag reading
  `health < 0`. Losing a negative is gaining. Whether that is elegant or a trick
  is a fair question — it is certainly *dense* — and it is the strongest
  argument this repository has produced for [17](17-conditions-as-expressions.md).
- **Two stats, not one, for the attack token.** `attacker` says whose round it
  is to attack and survives the whole round; `token` is what the attack button
  *spends*, so "once a round" is the cost and needs no counter. Combat then names
  the Nexus **absolutely** — routing on `attacker@north_side` picks one of two
  one-line phases — because the active seat during the strike is the *defender*
  (blocking is the last thing anybody did), and `enemy` would have pointed the
  wrong way. That is [07](07-presentation.md) gap 6's finding again: a condition
  cannot name a seat, and tagging the seat card is the workaround.

### Tough, and two wrong turns before it landed

Kept short because the route matters and the wrong versions do not.

Milestone 1 shipped Tough as `stat_gain:health@across:count:tough@across` — the
striker deals full power and hands a point back. That is **a reaction, not a
replacement**, and it *heals* against a zero-power source. This file then
diagnosed the fix as needing a replacement effect ([01](01-boardgames.md) gap 5's
harder half) because "the clamp needs `min(1, damage)` and the amount grammar has
products only" — which sent the track at a subsystem for a rule that needs three
ordinary lines.

**[22](22-the-crew.md) corrected it (2026-08-20):** *reduce incoming damage by 1,
never below 0* is `max(0, power - tough)`, which is `stat_damage` against a floor
of zero — [23](23-splendor.md)'s finding — computed on a scratch number *before*
the damage lands. What was missing was never an operator but the habit of working
a number out on the way in.

That correction put the scratch number on the **striker**, which is the second
wrong turn and the one the section below fixes.

### Shipped (2026-08-21), and the scratch number moved to the other card

The correction above was right about the arithmetic and wrong about where it
goes. It put `hurt` on the **striker** — `max(0, power@self - tough@across)` —
which works and is still Tough written into whatever is hitting you. Every
source of damage would have to carry the term, and LoR has sources that are not
strikers at all: a spell deals damage without anything standing across the lane.

So the number lives on the **card being hit**. `incoming` is one stat, declared
once, `min: 0` and `on: ["unit"]`:

```json
{ "key": "incoming", "min": 0, "on": ["unit"], "start": 0, "tags": ["hidden"] }
```

Damage is written there, reduced there, and only then taken. **A keyword that
changes a number is one line on its own tag**, and it names neither the fight
nor whatever dealt it:

```json
"tough": { "abilities": [{ "key": "armor", "phases": ["strike"],
  "action": ["stat_damage:incoming@self:1"] }] }
```

`min: 0` is the whole of *never below zero*, so there is no clamp to write and
no way to write it wrong.

### What it cost: a step

One engine word. `activate_zone:<zone>:<order>:<step>` runs only the abilities
keyed to that word, so a phase can walk the same zone several times:

```json
"stat_set:incoming@each.battle:0",
"activate_zone:battle:by_column:aim",
"activate_zone:battle:by_column:armor",
"activate_zone:battle:by_column:land",
"activate_zone:battle:by_column:spill"
```

`aim`, `land` and `spill` are the battlefield's (`in_combat`); `armor` is the
keyword's — *reduce damage by x* is an ability half of gaming has, so the step is
named for what it does rather than for the one keyword that uses it here; Overwhelm's line is unchanged and simply joins the `spill` step. The
reason this needed a word at all is that **the only order there was ran down one
card's abilities before the next card started**, and a rule that has to happen
after *all* of one thing and before *all* of another had nowhere to live. Steps
give a phase that ordering without the engine learning what a strike is.

Naming no step runs every ability, which is what Splendor's and The Crew's
`activate_zone` calls have always meant, so nothing else in the corpus changed.
The validator refuses a step no ability answers to — a mis-typed step is a pass
that silently does nothing, which is the shape of bug a pipeline is best at
hiding.

### Three things found on the way

- **A tag ability rides on the card everywhere**, so `tough`'s `armor` would
  have appeared in the bench chooser beside *Attack* and *Block*. `phases:
  ["strike"]` is what keeps it out — and it is free, because `activate_zone`
  does not read `phases` at all. That asymmetry was already load-bearing:
  Overwhelm's ability has carried `phases: ["strike"]` since it was written, for
  exactly this reason and without saying so.
- **A keyword runs after the rule it modifies, and that is already the order.**
  `cards.abilities` returns the card's own, then what the *zone* grants, then
  what its own tags do — "keywords come last on purpose". Steps did not have to
  fight it.
- **`on_act` now says which step it is announcing.** The presentation spaces
  bursts out by the beat, and four passes over one zone is four beats a card;
  the one a player actually sees is the landing. `tests/integration/lor.lua`
  reads that argument rather than counting to four.

### What is still owed, and it is spells

`land` lives on `in_combat`, which the *battle* zone grants — so a unit on the
bench has no way to take the damage written onto it. Combat is the only thing
that deals damage today, so nothing is broken; the first spell that hits a
benched unit is what pays for it. [Assumption: `land` moves onto the `unit` tag
at that point, since taking damage is something a unit does wherever it stands,
and the two passes a spell needs are then two ordinary lines in its own action
list — which `test_lor_anything_that_writes_the_damage_meets_tough` already
runs, outside the strike phase, with no striker anywhere in it.]

**Overwhelm went the other way and is now on the keyword itself.** A card's own
tags grant abilities — the same thing a zone's `applies` has always done, and
the same asymmetry the tooltip had — so the `overwhelm` tag def carries both the
sentence and the action, and a unit says only that it has the keyword. The
`count:overwhelm@self` factor is gone: the tag decides whether the ability
exists rather than multiplying its result by zero.

That is *where* the rule lives fixed. **What it says is still deduced**, and the
gap is worth naming precisely, because it is the shape of every keyword after
these two:

> *When it deals damage to a target, and the target dies, and this is combat —
> strike the enemy Nexus with the excess.*

Three conditions, and the engine can observe none of them. It infers all three
from state after the fact: `attacking@self` stands in for "this is combat",
`overkilled@across` (health below zero) stands in for "the target died *of this
damage*", and the negative health itself is the excess. Each stands in
faithfully today and each is a coincidence rather than a reading — a second
source of damage in the same combat would make the second inference wrong.

**Ability moments are the next question this raises**, and it is the right one:
`play`, `activate`, `challenge`, `receive` and `turn` are moments a card
already has, and none of them is *"when something else happens"*. `activate` is
the click moment — and yet `activate_zone` runs those same action lists with no
click, no cost and no phase, which is how all of the above works. That is a word
doing two jobs, and a `trigger` moment beside the others is what would separate
them. It wants designing with [01](01-boardgames.md) gap 5 rather than bolting
onto this file.

### Two drifts the game file found in the validator

Both were the validator disagreeing with the engine rather than with the game,
and both are fixed here:

- **`actions` on a non-automatic phase were rejected**, three commits after
  `c68c0c8` made phase entry actions universal. `SCHEMA.json` said the same. The
  warning, its case in `tests/integration/validator.lua` and the schema line are
  gone.
- **A slot's `col` and `row` were unknown stats.** They are stamped on every
  square by `zones.lua` and can only be read through a scope, so they are
  legitimate exactly where `where` uses them (`row@target`). Allowed in the
  scoped branch only, beside `card_stats`. A stat declared on a **seat card** is
  now allowed unscoped too, which is what the next section makes true.

### And one real bug, in the engine rather than in the file

`"cost": { "mana": 3 }` was the **pool of both seats' mana**. A bare subject has
no scope, and the default scope was every `player`-tagged card — so `can_afford`
added north's gems to south's, and `pay` took the amount off whichever seat came
first in the file. Measured: with north on 5 and south on 0, south played a
three-drop and north paid for it.

It was first patched in the game file, by writing every cost `mana@mine.player`,
and that was treating the symptom. **An unscoped subject means the seat that is
up** — `predicate.entities_in_scope`'s own comment has said "no scope means mine"
since it was written; it simply never filtered. It does now, and `lor.json`'s
costs are back to `{ "mana": 3 }`.

**No solo game could ever have seen this** — one seat, and the pool is that seat
— which is the argument for two-seat games as a test of the vocabulary and not
only of the engine. The one thing it changed elsewhere is a four-seat party
fixture in `tests/run.lua` whose comment already named the gap it was
documenting: *"several cards tagged player means a bare subject is the whole
company"*. It is one character now, not four.

### What milestone 1 deliberately does not do

Stated rather than implied, because a prototype that quietly differs from the
game is worse than one that says where:

- **The token holder does not act first.** LoR is explicit that they do; `play`
  alternates with `seat: "next"` and nothing can point the turn at a named seat.
  This is [22](22-the-crew.md)'s `set_active_seat:<scope>` primitive, and this
  game is its **second independent customer** — which is the ladder's own bar
  for building it.
- **The deck is 30, not 40**, and there is no mulligan (the offer overlay picks
  exactly one; a mulligan picks a subset), no hand cap of ten, no spell mana, no
  decking out and no round-40 tie. All of those are named in the stage-2 table
  and none of them is combat.
- **A blocker may meet any attacker, not only the one it is "in front of"** —
  which is the real rule, since the defender chooses the pairing. What it may
  *not* do is enter an empty lane or the attacker's row, and `where` is what says
  so.

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

---

## What `todo.md` sent back after milestone 1

Three notes, two of them this file's stage-2 table wearing different words.

**"A zone for the spellstack."** Already the response stack above, and
[20](20-puzzle-strike.md) names the same engine gap from the other side
(`flow.reachable` refuses a card played out of turn, which is what casting in
response *is*). The zone is the last part of that, not the first: nothing goes in
it until a spell exists, and a spell cannot exist until a card can be played out
of turn.

**"Player cards for the nexus, with mana and spell mana on them."** and **"the
left side is wasted space"** — one edit, not two, and **shipped**. Two
`grid [1, 1]` zones down the empty band from `x` 0.00 to 0.16, each holding its
seat's card with a style badging `nexus` and `mana`. It had to be a *grid*:
`draw_card_stats_overlay` runs from the grid branch of `draw_zone` and from the
browse overlay **and nowhere else**, so a card lying in a hand or on a pile wears
no badges at all — a nameplate without its numbers. The test says so, because a
plate that stopped being a grid would go blank without failing anything else.

Spell mana is the half that is still stage 2: unspent mana carrying over, capped
at three, spendable only on spells, is a rule that needs the spells it pays for.
The card gains a third badge then.

## Overwhelm stopped being arithmetic (2026-08-23)

The line this file shipped Overwhelm as —

```
stat_damage:spill@self:sum:health@across:x:count:overkilled@across:x:sum:attacking@self
```

— is gone, and the diagnosis was not "the arithmetic grammar is too weak". Two
of its three terms were 0/1 stats multiplied in to fake an `if`, because an
ability had nowhere to put a condition. [26](26-an-if-and-a-name.md) gave it
one, plus a name for the value:

```json
{ "key": "spill", "text": "Overwhelm", "phases": ["strike"],
  "compute": ["overkill"],
  "when": ["attacking@self >= 1", "overkill >= 1"],
  "action": ["stat_gain:spill@self:overkill"] }
```

Three things went with it. The `in_combat` spill step lost an action — "if
blocked, zero it again" was a second line undoing the first, and a `when` says it
once before either runs. The `overkilled` computed tag is deleted: it existed
only to be that gate, and `overkill >= 1` says the thing directly. And the wart
this file left standing — that the excess is read as a *negative* health and so
had to be subtracted — is now named rather than clever: `overkill` is
`0 - health@across`, declared once with a sentence saying why.
