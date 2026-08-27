# 18 — Legends of Runeterra

**Milestone 1 plays** — `game/games/lor.json`, tested by
`tests/integration/lor.lua`. Draw, mana, the pass, the attack token, attackers
and blockers as lane placement, the strike, the Nexus, and a winner. Tough and
Overwhelm came with it, because both turned out to be arithmetic.

Reference: [lor/rules.md](lor/rules.md), [lor/decks.md](lor/decks.md),
[lor/CREDITS.md](lor/CREDITS.md). Card text and names are Riot's.

LoR was chosen over Magic and Hearthstone because it is a real, current
two-player card game with a small closed rule set, and it is the first target on
the ladder that makes ravel a *card game* engine rather than a board game engine
that also holds cards.

## Left to build

1. **Burst spells** — the ones that resolve immediately, so there is still no
   stack. This is where a spell targets, and targeting already exists.
2. **The response stack**, for Fast and Slow. [27](27-reactions-and-the-stack.md)
   shipped the window; what LoR adds is **speeds**.
3. **The rest of the keywords**, one at a time, each as a tag with behaviour.
   The ones that only change combat arithmetic — Quick Attack, Lifesteal — are
   the cheap half; the ones that change *who may block* — Elusive, Fearsome,
   Challenger — are rules about the pairing and want the pairing solid first.
4. **Champions**, which are `transform` plus a trigger watching the level-up
   condition, so they land after [01](01-boardgames.md) gap 5.

Also missing and small: spell mana (unspent mana carrying over, capped at three,
spendable only on spells — it needs the spells it pays for), the mulligan (the
offer overlay picks exactly one; a mulligan picks a subset), a hand cap of ten,
decking out, and the round-40 tie.

**Stated rather than implied, because a prototype that quietly differs from the
game is worse than one that says where:** the deck is 30 rather than 40, and
**the token holder does not act first** though LoR is explicit that they do —
that is [22](22-the-crew.md)'s `set_active_seat`, now shipped, and not yet wired
in here. A blocker may meet any attacker rather than only the one across from
it, which *is* the real rule since the defender chooses the pairing; what it may
not do is enter an empty lane or the attacker's row, and `where` says so.

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
keeps it out, and it is free because `activate_zone` does not read `phases` at
all. That asymmetry was already load-bearing and undocumented.

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

## What is still owed, and it is spells

`land` lives on `in_combat`, which the *battle* zone grants, so a unit on the
bench has no way to take damage written onto it. Combat is the only thing that
deals damage today, so nothing is broken; the first spell that hits a benched
unit pays for it, and `land` moves onto the `unit` tag at that point.

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
