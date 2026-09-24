# 18 — Legends of Runeterra

**Milestone 2 plays** — `game/games/lor.json`, tested by
`tests/integration/lor.lua`. Milestone 1 was draw, mana, the pass, the attack
token, attackers and blockers as lane placement, the strike, the Nexus, and a
winner; Tough and Overwhelm came with it, because both turned out to be
arithmetic. Milestone 2 is **spells** — eighteen of them, all three speeds, a
graveyard, a combat response window, Give and Grant, and Rally.

Reference: [lor/rules.md](lor/rules.md), [lor/decks.md](lor/decks.md),
[lor/CREDITS.md](lor/CREDITS.md). Card text and names are Riot's.

LoR was chosen over Magic and Hearthstone because it is a real, current
two-player card game with a small closed rule set, and it is the first target on
the ladder that makes ravel a *card game* engine rather than a board game engine
that also holds cards.

## Spells, and what a speed turned out to be

Eighteen spells, text and cost taken from [lor/data](lor/data) rather than from
memory — which is the finding, and it cost a whole set: written from recall,
Blade's Edge was Burst rather than Fast, Vengeance was 7 rather than 6, Elixir
of Iron gave +0|+3 rather than +0|+2, and Noxian Fervor's second half was aimed
at the Nexus rather than at anything. The data is in the repository. Read it.

**A speed is a list of phases, and nothing else.** `burst`, `fast` and `slow`
are tags the cards wear so a rule may one day ask, but what enforces the speed
is the `phases` each card carries and whether its action ends the phase:

| | may be cast in | ends the phase |
|---|---|---|
| Burst | play, declare_attack, declare_block, combat_response | no — the caster keeps the initiative |
| Fast | play, combat_response | yes |
| Slow | play | yes |

**Fast meant nothing until blocks had a window after them.** With only `play`,
`declare_attack` and `declare_block` to name, Fast and Slow were two words for
one behaviour — and a Fast spell cast during blocking would have ended the
*blocking* rather than handed the initiative over, because `end_phase` in a
declaration phase is the Done button. So `combat_response` sits between
`declare_block` and `strike`: a `player_input` phase that both seats pass out of,
counted by the same `passed` stat and the same two-in-succession rule the round
already used, with `combat_hand_over` clearing the other seat's flag exactly as
`hand_over` does. That is the whole of it — no new engine word, and the pass
button gained one phase key.

**A spell is spent, not moved.** `play.spent: "mine.discard"` files it however
the play ends. Units die into the same per-seat `status: "grave"` zone through
`destroy:dead`, which replaced `purge:dead` in `after_combat` — a unit killed by
a spell and a unit killed by a strike have to take the same road or only one of
them sets off what watches.

**Give and Grant are two stats, because Riot prints two words.** `given_power`
and `given_health` are cleared at round start; `granted_power` and
`granted_health` are not. All four are buffs, so nothing is written to the
number they lift and taking one off has no undo path to forget.

**The round heals, and it has to.** A unit kept alive by a borrowed +0|+2 would
fall over the moment the round called the loan in. LoR clears damage between
rounds anyway, so `reset:each.anyone.unit:health` sits in `round_start` right
after the two `given_` stats are zeroed — in that order, so nothing is briefly
dead in between.

**Rally needed no new word.** The attack button's cost *is* "once a round", so
Relentless Pursuit is `stat_set:token@mine.player:1` and nothing else learned
the word.

**What milestone 1 thought spells would cost, they did not.** This file expected
`land` to move off the battle zone onto the `unit` tag, because combat was the
only thing that could write damage onto a unit. A spell writes through the
`damage` verb directly instead, and Tough is a fact about *that verb* rather than
about the step combat uses — so a keyword written for the lanes answers a spell
on the bench with no change at all.

## Left to build

1. **Deny**, and with it the rest of Fast. `combat_response` is a window, not a
   stack: a spell resolves as it is cast, so there is no pending spell for
   *"Stop a Fast spell, Slow spell, or Skill"* to stop. That is
   [27](27-reactions-and-the-stack.md)'s question, not this one's.
2. **The rest of the keywords**, one at a time, each as a tag with behaviour.
   The ones that only change combat arithmetic — Quick Attack, Lifesteal — are
   the cheap half; the ones that change *who may block* — Elusive, Fearsome,
   Challenger — are rules about the pairing and want the pairing solid first.
   Note that the spells which *grant* a keyword for a round (Ranger's Resolve,
   Might, Prismatic Barrier) need a way to hand out a tag temporarily, which a
   computed tag cannot be: it may carry a buff and nothing else.
3. **Champions**, which are `transform` plus a trigger watching the level-up
   condition, so they land after [01](01-boardgames.md) gap 5.

Also missing and small: spell mana (unspent mana carrying over, capped at three,
spendable only on spells — now that there are spells to pay for), the mulligan
(the offer overlay picks exactly one; a mulligan picks a subset), a hand cap of
ten, decking out, and the round-40 tie.

**Stated rather than implied, because a prototype that quietly differs from the
game is worse than one that says where:** the deck is 40 now, but **the token
holder does not act first** though LoR is explicit that they do — that is
[22](22-the-crew.md)'s `set_active_seat`, now shipped, and not yet wired in here.
A blocker may meet any attacker rather than only the one across from it, which
*is* the real rule since the defender chooses the pairing; what it may not do is
enter an empty lane or the attacker's row, and `where` says so. There is one
response window, after blocks, where LoR gives the attacker one before them too.

## Two things the spells found, and both are closed

**"Deal 2 to anything" was not a gap after all.** It looked like one — a Nexus is
a seat card carrying `nexus`, a unit carries `health`, so one aim writes two
stats and an action list had no if (it has gates now: [46](46-one-list-of-conditions.md)).
The answer is that it needs no if: `any_of` says the aim once as a union of the
two kinds, and a subject names only the cards **carrying** its stat, so the two
damage lines each land on exactly the half they are about and pass over the
other. Mystic Shot and Blade's Edge are in the deck, and the shape is in the
COOKBOOK as *"Deal 2 to anything — a unit **or** a Nexus"*. It also says *"heal
an ally or your Nexus"*, which is Health Potion and Ritual of Renewal.

**A `where` could not see a buff, and now can.** `predicate.holds` had an `each`
branch reading `e.stats[arg]` straight where every other read goes through
`tags.stat`, and a bare `@target` parses as `quant = "each"` — so *"Kill a unit
with 3 or less Power"* offered a unit Elixir of Wrath had lifted to 4, while
`sum:power@target <= 3` answered correctly about the same card. Fixed, with the
buffed case in the Culling Strike test.

**The same mistake was in four other places**, found by grepping for a read of
`e.stats` outside `tags.lua`: a seat's ordering number in `phase.lua`, the hp
gate on `run_on_round` and the winner check in `flow.lua`, and the per-card
ceiling the inspector panel prints. The reads that stay raw are the ones that
should: the writer in `actions.lua`, the system card's own bookkeeping, a slot's
row and column, a supply shelf's `stock` (an engine ledger whose write is raw
too, so a buffed read would let a take through the decrement cannot account
for), and the counter inside `tags.buff` itself, which would otherwise be a
bonus deciding its own size.

## Blocking is placement, and that is the whole of it

**Six lanes per side, and a unit fights whatever is across from it.** There is no
relation to store, because the board already holds it.

The rules document is what makes this a reading of the rule rather than a
convenience: blocking is strictly one to one with no double-blocking in either
direction, and strikes resolve **left to right by board position** — so LoR's own
resolution order is a walk along the lanes, and the game lines blockers up
opposite attackers on screen for exactly that reason. A lane index is not a
stand-in for the pairing; it *is* the pairing, in the game as well as the model.

Everything it needed was built. An attacker whose opposite lane is empty is the
unblocked case, and it is an empty-square test rather than an absence of
relation. **So `attach_to_target` is not this track's customer after all** — it
stays [15](15-many-on-one-square.md)'s open question until the **Attach**
keyword turns up, where a card genuinely rides another and moves with it.

## What milestone 1 cost

**Four engine words, and the whole of combat is content.** Nothing in `flow`,
`predicate` or `render` knows what a lane, a blocker, Tough or Overwhelm is.

| Added | Why LoR asked |
|---|---|
| `where` on a **slot target spec** | a blocker's lane is *my row, opposite something already attacking*. `where` existed but only inside a `moves` rule, and a bench unit walks no pattern to reach the battlefield |
| `move:<scope>:<zone>` | "send the survivors home". Only the acting card and the ones a player chose could be moved; a set nobody picked had no verb |
| `set_owner:<scope>:<who>` and `receive.action` | something has to be able to *change* an owner, and a pile anybody may take from has to say so itself |
| **A card is born owned** | a unit played out of a seat's hand arrived on the shared battlefield belonging to nobody, so `mine`/`enemy` stopped seeing it |

**Ownership is a property of the card, not of where it is lying.** The last row
started in the wrong place and the wrong version *worked*: stamping the owner in
`zones.move_card` meant a card leaving a seat's zone for a shared board took the
seat with it, which is right for this game and wrong in general.

## The three things the build settled

**Combat is a rule on the zone, not on the cards.** The battlefield carries
`"applies": ["in_combat"]` and the tag holds one ability; `activate_zone` runs it
for every unit standing there, in slot order. All ten templates stay text-free —
they are stats, a picture and a price.

**Two stats, not one, for the attack token.** `attacker` says whose round it is
and survives the round; `token` is what the attack button *spends*, so "once a
round" is the cost and needs no counter. Combat then names the Nexus
**absolutely**, because the active seat during the strike is the *defender* —
blocking is the last thing anybody did — and `enemy` would point the wrong way.
That is [17](17-conditions-as-expressions.md)'s finding again: a condition cannot
name a seat, and tagging the seat card is the workaround.

**A keyword runs after the rule it modifies, and that is already the order.**
`cards.abilities` returns the card's own, then what the *zone* grants, then what
its own tags do. Steps did not have to fight it.

## Tough, and two wrong turns before it landed

Milestone 1 shipped it as *the striker deals full power and hands a point back*,
which is **a reaction, not a replacement**, and *heals* against a zero-power
source. This file then diagnosed the fix as needing a replacement effect, because
"the clamp needs `min(1, damage)` and the amount grammar has products only" —
which sent the track at a subsystem for a rule that needs three ordinary lines.

**[22](22-the-crew.md) corrected it.** *Reduce incoming damage by 1, never below
0* is `max(0, power - tough)`, which is `stat_damage` against a floor of zero,
computed on a scratch number *before* the damage lands. What was missing was
never an operator but the habit of working a number out on the way in.

That put the scratch number on the **striker**, which is the second wrong turn.
It works, and it is still Tough written into whatever is hitting you — every
source of damage would carry the term, and LoR has sources that are not strikers
at all. **So the number lives on the card being hit**: `incoming`, one stat,
`min: 0`, `on: ["unit"]`. Damage is written there, reduced there, and only then
taken. **A keyword that changes a number is one line on its own tag**, naming
neither the fight nor whatever dealt it, and `min: 0` is the whole of *never
below zero* — there is no clamp to write and no way to write it wrong.

## What it cost: a step

`activate_zone:<zone>:<order>:<step>` runs only the abilities keyed to that word,
so a phase can walk the same zone several times — every unit works out what it is
dealt, then every keyword that reduces a number reduces it, then every unit takes
it.

**The reason it needed a word at all** is that the only order there was ran down
one card's abilities before the next card started, and a rule that has to happen
after *all* of one thing and before *all* of another had nowhere to live. Steps
give a phase that ordering without the engine learning what a strike is.

Naming no step runs every ability, so nothing else in the corpus changed. The
validator refuses a step no ability answers to — a mis-typed step is a pass that
silently does nothing, which is the shape of bug a pipeline is best at hiding.

**A tag ability rides on the card everywhere**, so `tough`'s `armor` would have
appeared in the bench chooser beside *Attack* and *Block*. `phases: ["strike"]`
kept it out, free because `activate_zone` does not read `phases` at all — an
asymmetry that was load-bearing and undocumented.

**Superseded 2026-09-01.** Tough is not an ability now and never was one in
spirit: it says that damage arriving at this card arrives for one less.
[30](30-things-that-are-true.md) gave it the word, and the whole apparatus went
with it — the `armor` ability, the `phases` fence that kept it off the bench,
and a fourth pass over the board in the strike phase. What the pass finding
above is *actually* about survives intact, since `aim` still has to run for
every card before `land` runs for any.

## Overwhelm stopped being arithmetic

It shipped as one line with three terms, two of which were 0/1 stats multiplied
in to fake an `if` — because an ability had nowhere to put a condition.
[26](26-an-if-and-a-name.md) gave it one, plus a name for the value, and the
diagnosis was *not* "the arithmetic grammar is too weak".

The `in_combat` spill step lost an action — "if blocked, zero it again" was a
second line undoing the first, and a `when` says it once before either runs. The
`overkilled` computed tag is deleted: it existed only to be that gate. And the
wart this file left standing — that the excess is read as a *negative* health —
is now named rather than clever: `overkill` is `0 - health@across`, declared once
with a sentence saying why.

## What is still owed

**Settled 2026-09-20.** `land` lives on `in_combat`, which the *battle* zone
grants, so a unit on the bench had no way to take damage written onto it — and
this file expected the first spell to hit a benched unit to pay for moving
`land` onto the `unit` tag. It did not. A spell writes `damage:health@target:n`
through the game's own verb, which is where Tough is hung, so `incoming` and
`land` stayed a detail of how the lanes resolve.

**What Overwhelm says is still deduced**, and the gap is the shape of every
keyword after these two:

> *When it deals damage to a target, and the target dies, and this is combat —
> strike the enemy Nexus with the excess.*

Three conditions, and the engine observes none of them. It infers all three from
state after the fact: `attacking@self` stands in for "this is combat", health
below zero stands in for "the target died *of this damage*", and the negative
health is the excess. Each stands in faithfully today and each is a coincidence
rather than a reading — **a second source of damage in the same combat would make
the second inference wrong.**

**Ability moments are the next question this raises.** `play`, `activate`,
`challenge`, `receive` and `turn` are moments a card has, and none is *"when
something else happens"*. `activate` is the click moment — and yet
`activate_zone` runs those same lists with no click, no cost and no phase. That
is a word doing two jobs, and a `trigger` moment beside the others is what would
separate them. It wants designing with [01](01-boardgames.md) gap 5.

## Refused

- **A rules-complete LoR.** The target is a playable subset that is honestly the
  game, not every card ever printed.
- **Building anything before the rules document is satisfying.** The cost of
  discovering a misremembered combat order after the combat code exists is the
  entire combat code.
- **Engine knowledge of a keyword.** A keyword is a tag with behaviour declared
  in the game file. The moment `render` or `flow` knows what Overwhelm means,
  ravel is a LoR engine rather than a card game engine.
- **The client, the collection, the levelling, the art.**
- **A generator.** ~40 hand-written templates is a readable size, and the
  generator is what [14](14-kinds-and-placements.md) deleted.
