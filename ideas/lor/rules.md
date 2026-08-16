# The rules of Legends of Runeterra

Reference material for [18](../18-legends-of-runeterra.md) — somebody else's game,
written down so that ravel can be built against it. Not an idea about ravel;
what ravel makes of it is in the idea file.

**How this was written, and how far to trust it.** It was checked against
sources rather than recalled, which is what [18](../18-legends-of-runeterra.md)
stage 1 asked for. Riot's own rules pages render their text in JavaScript and
came back empty, so the spine is the League of Legends Wiki
(`wiki.leagueoflegends.com`, which is Riot-hosted), with `gamepressure.com` for
the turn structure. Every rule below is marked:

- **(v)** — read off a source during this pass.
- **(r)** — recalled, *not* verified. Build against these last, and check them
  first when something plays wrong.

The card data is a separate matter and did not survive the same standard — see
[decks.md](decks.md), which says exactly what is missing and where it is.

---

## The board

**(v)** Each player has a **Nexus** at 20 health — that is the life total, and
the game is won by taking an opponent's to zero. It can be raised past 20 by
card effects, to a maximum of 99.

**(v)** Three places hold cards, and their limits are hard:

| Place | Holds | Limit |
|---|---|---|
| Hand | cards you may play | 10 |
| Bench | your units, not in combat | 6 |
| Battlefield | units committed to this combat | 6 |
| Deck | what you draw from | 40 at the start |

**(v)** A deck is 40 cards, from at most **two regions**, with at most **3
copies** of any card and at most **6 champion cards**.

**(v)** You lose if your Nexus reaches zero, if a card's own win condition says
so, or if you must draw from an empty deck. The game is a **tie at round 40**,
or if both players would lose at once.

## The round

**(v)** A round is not a turn. Both players act inside one round, alternating,
and the round is the unit that mana and the attack token are measured in.

At the **start of every round**:

- **(v)** Both players draw one card.
- **(v)** Both players gain one more mana gem, to a maximum of ten, and all
  gems refill. The count rises by one per round from one, so round 4 is four
  mana.
- **(r)** Round-start triggers fire here.

**(v)** One player holds the **attack token**. It alternates every round, so
each player attacks every other round, and only its holder may declare an
attack. The holder also acts first in the round.

**(v)** **Scout** is the exception that must not be forgotten: a scout attack
returns the attack token to you, once per round.

## The action loop, and what ends a round

**(v)** Players alternate. On your turn you take **one action** — play a card,
declare an attack — and priority passes to the opponent, who may answer before
you act again. Doing nothing is passing.

**(v)** **The round ends when both players pass in succession**, with no action
between the two passes.

**(v)** Mana does not refill between turns inside a round. It refills at the
start of the next round, which is what makes holding mana a real decision.

## Mana, and spell mana

**(v)** Unspent mana at the end of a round becomes **spell mana**, up to a
maximum of **3**, and carries into the next round.

**(v)** Spell mana may only be spent on spells. When a spell is paid for,
**spell mana is spent first**, then ordinary mana.

**(r)** Spell mana is not refilled by the round start — it is only what the
last round left over, and it is capped at 3 however much was left.

## Spells, and their four speeds

**(v)** A spell's speed decides *when* it may be played and *whether the
opponent may answer it before it resolves*:

| Speed | May be played | The opponent |
|---|---|---|
| **Burst** | any time, including during combat | may only answer *after* it has resolved |
| **Focus** | outside combat, with nothing else waiting to resolve | as Burst: resolves immediately |
| **Fast** | any time, including during combat | may answer before it resolves |
| **Slow** | outside combat, with nothing else waiting to resolve | may answer before it resolves |

**(r)** Spells waiting to resolve form a stack, and it drains last-first: the
answer resolves before the spell it answered. This is the one rule in this file
whose *bounds* decide whether [18](../18-legends-of-runeterra.md) is a milestone
or a project, and it is recalled rather than verified. The bound that matters:
Burst and Focus never sit on that stack at all, because they resolve on the spot.

## Combat, in order

This is the part an implementation asks about most and every summary skips, so
it is written as steps.

1. **(v)** The attack-token holder declares an attack, moving units from the
   bench onto the battlefield. **(r)** The token is spent by declaring.
2. **(v)** The defender assigns blockers. **Blocking is one to one**: a blocker
   blocks exactly one attacker, an attacker is blocked by at most one blocker,
   and there is **no double-blocking** in either direction. All blocks are
   assigned at once, not one at a time.
3. **(v)** Both players may answer with Fast and Burst spells before damage.
4. **(v)** Units **strike**. Strikes resolve **left to right by board
   position**, not simultaneously — the leftmost pair first, then the next.
5. **(r)** Within a pair, attacker and blocker strike each other at the same
   time, so both can die. Quick Attack and Double Attack are the exceptions and
   are written below.
6. **(r)** An attacker nobody blocked strikes the defending **Nexus** for its
   power.
7. **(r)** Units that took lethal damage die together at the end of the step,
   and Last Breath triggers fire then. Surviving attackers return to the bench.

**(r)** Damage stays on a unit for the rest of the round — health is not
restored between two combats in one round — and clears at the start of the next.
Regeneration is a keyword precisely because this is not automatic.

## The keywords, as rules

**(v)** — all of the following are quoted or paraphrased from the wiki's keyword
pages during this pass.

**Combat, changing the arithmetic:**

| Keyword | Rule |
|---|---|
| **Quick Attack** | Strikes first *when attacking*. If the blocker dies before striking back, the attacker takes nothing. |
| **Double Attack** | Strikes both *before* and *at the same time as* its blocker. |
| **Overwhelm** | Damage beyond the blocker's remaining health hits the defending Nexus. |
| **Tough** | Takes 1 less damage from every source. |
| **Barrier** | Negates the next damage entirely. Lasts one round. |
| **Lifesteal** | When it strikes, your Nexus heals for the damage dealt. |
| **Fury** | Gains +1\|+1 whenever it kills a unit. |
| **Formidable** | Strikes with its health instead of its power. |
| **Impact** | Deals 1 to the enemy Nexus when it strikes. Stacks. |

**Combat, changing who may block whom:**

| Keyword | Rule |
|---|---|
| **Elusive** | Can only be blocked by another Elusive unit, or by one a card has granted the ability to. |
| **Fearsome** | Can only be blocked by a unit with 3 or more power. |
| **Challenger** | Chooses which enemy unit blocks it, dragging that unit into combat. |
| **Vulnerable** | Any enemy may challenge it, forcing it to block. |
| **Can't Block** | May not be declared a blocker. |
| **Immobile** | May neither attack nor block. |

**Outside combat:**

| Keyword | Rule |
|---|---|
| **Regeneration** | Heals to full at round start. |
| **Spellshield** | Negates the next enemy spell or skill that would affect it. |
| **Scout** | Attacking with only Scout units returns the attack token. Once per round. |
| **Attune** | Refills 1 spell mana when summoned. |
| **Ephemeral** | Dies after it strikes, or when the round ends. |
| **Fleeting** | Discarded from hand at the end of the round. |
| **Deep** | While your deck holds 15 or fewer cards, Deep units get +3\|+3. |

**Trigger words** — **(r)** for the wording, though the words themselves are
certain: **Play** (when summoned from hand), **Last Breath** (when it dies),
**Strike** (when it strikes), **Nexus Strike** (when it strikes a Nexus),
**Round Start** / **Round End**, **Support** (when it attacks beside the unit to
its right).

## Champions

**(v)** A champion is a card that **levels up** when the condition printed on it
is met. It transforms into an upgraded version of itself in place — keeping the
damage it has taken and the effects on it, and counting as the same unit.

**(v)** Most gain +1|+1 plus new text. The transformation is permanent: it
persists if the champion dies or returns to hand.

**(v)** A deck may hold at most 6 champion cards, which with the 3-copy limit
means at most two champions in the usual build.

## The opening

**(v)** Both players draw **4 cards** and may replace any of them. Replacements
come from the deck and the replaced cards go back into it. There is no penalty
and no card advantage either way.

---

## Sources

- [Legends of Runeterra (game) — League of Legends Wiki](https://wiki.leagueoflegends.com/en-us/Legends_of_Runeterra_(game)) — deck and board limits, win conditions, spell speeds, mana, the outline of combat.
- [Keywords (Legends of Runeterra) — League of Legends Wiki](https://wiki.leagueoflegends.com/en-us/Keywords_(Legends_of_Runeterra)) — the keyword table.
- [Turns and rounds system — gamepressure](https://www.gamepressure.com/legends-of-runeterra/turns-and-rounds-system/z0cf3d) — the action loop, passing, mana not refilling inside a round.
- [Blocking — gamepressure](https://www.gamepressure.com/legends-of-runeterra/blocking/z1cf3e) — one blocker per attacker, and strikes resolving left to right.
- [Round FAQ — Riot Games Support](https://support.riotgames.com/en-us/legends-of-runeterra/gameplay/round-faq) — **could not be read**: the page renders its text in JavaScript and returns an empty document to a fetch. It is the authority for everything marked **(r)** above and is the first place to check.
