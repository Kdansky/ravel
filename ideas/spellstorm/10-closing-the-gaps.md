# Spellstorm — closing the gaps

`09-engine-gaps.md` is the honest record: everywhere the playable version
departs from the printed game. This is the other half — what each departure
would cost to close, and what it would be called.

Written after building the game rather than before, which is the only order that
produces an honest list: every entry below is a shape the engine actually
refused, not one somebody imagined it might.

**The one thing worth reading if you read nothing else.** Most of what is
missing here is one moment: the rules want the player's answer and the engine is
midway through an action list. But the shape of that limit is narrower than it
looks from the outside, and getting it right changes which entries are cheap —
see A2, which was written wrong the first time and is corrected below.

---

## A. The one big word: an automatic step that can ask

### A1. Ultimates are cast on play, not on resolve (09 §2)

**What it costs.** The `[ULT]` icon means nothing mechanically, and an Ultimate
that wants to answer what the opponent revealed cannot — it is spent before the
showdown turns the cards over.

**Proposal — reactions, which already exist for exactly this.** A reaction is a
window opened on a named verb, and it already carries a `cost`, a `when` and a
`from`. Give the resolve step an `emit:` — say `spell_resolving` — and the
wizard card carries:

```json
{ "to": "spell_resolving", "whose": "mine", "from": "board",
  "cost": { "mana@mine.player": 6 }, "action": [ … ] }
```

The machinery is all there (`game/reactions.lua`, `emit:` in `actions.lua`).
The open question is whether `reactions.responders` may open a window from
inside an *automatic* phase's action list, which is where resolution runs.
If it can, this is a game-file change and no engine change at all — worth
finding out before anything else on this page.

**Size:** small if the window opens; medium if the scheduler has to learn to.

### A2. A question inside an automatic step (09 §2, Abragail, Falling Star, May)

**What is actually true, tested rather than assumed.** An automatic step *can*
ask. `show:` opens an offer from inside an ability that an automatic phase
activated, and Spellstorm already depends on it: every `cast_ask` runs that way.
Verified on a three-card game — an `automatic` phase running
`each_seat:activate_zone:rules:by_column:bstart` over an ability whose whole
body is `show:shelf:optional` leaves a live, dismissable offer on the table.

So the earlier framing here, and the comment in `make_spellstorm.py` that says a
battle-start step "cannot open a question", are both wrong. Three narrower
things are true instead:

- **It cannot open targeting.** `activate_zone` runs every ability with
  `targets = {}`, hardcoded (`actions.lua`), so an ability's `target` spec is
  never asked about and no targeting opens. An offer is the only way to ask.
- **It cannot ask each seat in turn.** `each_seat:` runs both seats inside one
  step and there is one `options` zone. The first seat's offer holds it; the
  second seat's `show:` finds the source zone already lent out and returns
  silently, so the question is asked once and nobody is told. **This is the real
  blocker**, and it is Falling Star exactly.
- **It cannot resume.** An action list has no cursor, so whatever follows the
  ask runs before the answer arrives.

**Proposal.** For the each-seat case, a queue: `show:` from inside `each_seat:`
enqueues rather than opening, and the offers are presented one after another as
each is answered. That is the same question [32](../32-a-third-player.md)'s
`seat: "all"` asks, and the two should be settled together. For targeting, an
ability run by a zone could open it the way a play does — but nothing in this
box needs that once offers work.

**And: Abragail's journal — done, all three asking spaces, and there were
three.** Space 6 (`[GAIN]`) was missing too and nobody had noticed. Two things
turned out to be true that the paragraph above did not say. One seat asking is
not one ask: a fully-researched journal asks *three* times in one battle-start
list, and an action list has no cursor, so all three overlays would land on one
table. And "only Abragail has a journal" is false in a mirror, where both seats
do. So each asking space gets **a phase**, and each phase **one seat** — six
short automatic phases, empty for every other wizard. An ask is the last thing a
phase does, and the next phase waits for the answer, which is the cursor an
action list has not got.

Worth keeping as the shape: **a phase is the engine's word for "and then".**

**Size:** the queue is still medium. Abragail was a generator change and no
engine work at all.

### A3. ~~An offer opened inside an offer deadlocks~~ — done

Two faults, not one, and the second only showed once the first was out of the
way.

**The lock.** Picking from an offer popped the overlay, ran the `chosen` block,
then swept the `options` zone. There is one such zone and it knows its contents
by what is lying in it, so an offer the chosen block opened was eaten by the
cleanup meant for the offer that had just closed — cards and `dismissable` flag
together, which is why `can_dismiss` refused: it reads the flag that had just
been cleared. **Fixed by the ordering**: the leftovers go home before the chosen
actions run, and only the picked card waits for them.

**The half-resolved copy.** `copy:<scope>:activate` ran a card's *first* ability
and stopped. That dropped every rider with an if in it, and every question the
card asks — a card that asks keeps the asking in a later ability so the offer
opens after the rest has run, which is exactly the ability a copy never reached.
**Fixed**: `copy` now runs every ability whose `when` holds, in order, the same
thing `activate_zone` does.

**What that cost, and what it bought.** A flat ability list cannot say which of
its entries are part of being *resolved*, so a copy fired the discard effect
too. The first patch was a `when` on every `disc` step — looking only while no
card stands in a battle spot — which is a card carrying a condition about the
world to answer a question about itself, and reads as nothing at all.

**Fixed properly**: On Discard is not an ability. An ability is something the
card does; this is something that happens *to* it. It is a `leaves` trigger now,
`{ "from": "hand", "into": "discard" }`, which is the rulebook sentence — and
"does not trigger when you VOID" comes free, since a VOID lands somewhere else.
The engine gained one word for it, `leaves.from`, naming which departure a
`leaves` answers. Nineteen conditions went, two `activate_zone` lines went, and
*Flame* and *Spirit Crystal* began firing the On Discard they had been eating.

Worth noting as a shape rather than a fix: **the four-pass resolve had a second
job, keeping `disc` out of a stepless pass**, and no longer has it. Each battle
spot holds one card, so `activate_zone:mine.battle:by_column` with no step would
now run the same four abilities in the same order, in one line instead of four.

The `cast`/`cast_ask` split stays, and should: it is what keeps the offer last
within one card, so a rider does not read a hand that has been lent out to a
question. Merging them would be safe today by luck — only one card has both a
rider and an ask, and its rider reads the battle spots — which is not a reason.

---

## B. Passives, auras and replacement

### B1. No continuous effects (09 §4: Croh, Bunny; Glittering Dust)

**What it costs.** Croh's *Accursed* ("whenever you would heal, give a CURSE
instead") is approximated as a battle-start sweep. Bunny's overheal draw never
fires. The weather card *Glittering Dust* ("Earth cards do nothing but heal 2")
is not implemented.

**Proposal — `adjusts` already is this word, one field short.** A tag may carry
`adjusts` with `verb`, `stat`, `covers`, `when` and `by` — a live hook that
changes a stat change as it happens. What it cannot do is run an action
*instead* of the change. Add `instead: [ … ]`:

```json
"accursed": { "adjusts": [
  { "verb": "heal", "stat": "health@mine.player",
    "instead": ["move:curse_pile:enemy.discard"] } ] }
```

Croh becomes exact. Bunny needs one thing more — *how much* healing was wasted —
which is the clamp `adjusts` already computes and does not report; expose it as
a scope (`@adjusted`) and *Double Stitch* is exact too.

*Glittering Dust* is the harder half: rewriting what another card's whole action
list does is not a stat hook, and nothing short of a real replacement layer
covers it. **Left alone deliberately** — one weather card is not worth an
effects engine.

**Size:** `instead` is small. The wasted-heal scope is small. Glittering Dust is
large and not recommended.

### B2. Omar's Traps (09, components table)

**What it costs.** Three cards not implemented: played face down, revealed at a
trigger of the player's choosing.

**Proposal — half of it already shipped.** The face-down half is the `commit`
zone: a per-seat zone with `visibility: "owner"` is exactly a trap that is
placed and unreadable. The missing half is a reaction to something that is not a
card being played — "when an opponent is dealing damage to you". Since
`adjusts` already watches `stat_damage`, the cheapest route is to let the damage
path `emit:` a verb, and a trap is then an ordinary reaction with
`from: "traps"`.

**Size:** medium, and it shares its whole cost with A1 (both want a verb emitted
from inside the engine's own steps rather than from a card).

---

## C. Offers that cannot be narrowed or repeated

### C1. `[GAIN]` ignores the Tier limit and the element (09, rules simplified)

**What it costs.** Any of the five Storm Cloud cards may be taken from a card
effect, whatever its Tier; the Essences offer the whole shelf rather than their
own element.

**Proposal — let `chosen.where` narrow what is *shown*, not only what may be
taken.** The field exists and the condition is already written down: the Regroup
gain step proves it (`tier@mine.player >= tier_req@self`). Today it gates the
take and the cards all still show, which is the worst of both — the player sees
five and may click two.

**Size:** small. This is the highest ratio of "cards fixed" to "lines changed"
on the page: it fixes every `[GAIN]`, every Essence, and Flame's Fire-only
offer in one go.

### C2. "Gain twice" gains once (Amber, Earth Dragon, Abragail)

**Proposal — a list of `chosen` blocks rather than one**, run in order, or a
`times` on the block. The second reads better and stays one block.

**Size:** small.

### C3. Diamond discards the first three rather than three of your choosing

**Proposal — a count on the offer.** `chosen.count: 3`, and the overlay closes
when three are taken rather than one. The offer already knows how to stay open
(`ends_when` on the `options` phase does it); what it lacks is a number.

**Size:** small–medium. Wants C1's `where` beside it or it will offer cards it
should not.

### C4. Sift looks at 2 and puts them back in order

**Proposal — none recommended.** An ordering interface is a new input surface
for one card in the box. Sift stays as it is: draw 2, discard 1.

---

## D. Counting and arithmetic

### D1. ~~Random discards are not random~~ — done, and it was already there

`move:` has honoured `random.` since the quantifier existed — the same three
lines `destroy` and `show` carry. Nobody had written it down: the reference said
`show` and `destroy` took it and the `move` row did not, so six cards discarded
the top of a hand for want of a sentence in `AUTHORING.md`. Now said in both, and
in `SCHEMA.json`.

**The lesson is about the docs, not the engine.** A word the engine knows and the
reference does not is a word the game cannot use.

Shockwave, Dust Cloud, Tidal Wave, Undertow, Face Punch and Data Breach are
exact. Two cards is the line twice; there is no count on a move, and doubling it
is what "discard two random cards" says.

### D2. Ruby counts what was just discarded

**What it costs.** "1 damage per Fire card discarded" is a flat 1.

**Proposal — a scope naming what the previous step moved.** Reactions already
have `@event` for "the thing this is about"; an action list wants the same for
"what the step before me touched" — `@moved`, say. Lapis and Diamond want it
too, which is three cards for one word.

**Size:** medium.

### D3. No parity, modulo or division (Derby's Ultimate)

**Proposal — one comparison, not an expression language.** `odd` and `even` as
condition operators (`health@mine.player is odd`) covers the only case in this
box and does not open the door that [17](../17-conditions-as-expressions.md)
closed on purpose. Division has no customer here at all.

**Size:** small. Do not generalise it.

### D4. Obsidian does not grant a free Ultimate

**What it costs.** "there is no way to waive a cost."

**Proposal — a stat that pays.** [20](../20-puzzle-strike.md)'s `pays_for`
already proposes a stat that stands in for another when a cost is checked; a
one-shot `ult_free` stat that `pays_for` mana is Obsidian exactly. Ties to
[25](../25-derived-stats.md).

**Size:** small once `pays_for` lands; nothing to do before then.

### D5. Omar's Shuriken "ALWAYS goes first"

**Proposal — a card-level initiative override read by `set_active_seat:has_init`.**
Or leave it: taking Initiative is close, and the difference shows in maybe one
game in twenty.

**Size:** small, low value.

---

## E. ~~Things that are not gaps at all~~ — done, all five

They read like engine limits in `09` and were not one of them. Each was a to-do
in the generator, and all five are written.

- **Croh's DOOM Token conditions.** An ability `when`, twice: `doom@mine.player
  <= 0` for the Ultimate, `count:junk@curse_pile <= 0` for *Sinking Strike*. The
  Ultimate calls a rules card rather than saying it inline, because an action
  list has no room for an if and a rules card is where this game keeps them.
- **Empty-pile actions.** `count:junk@<kind>_pile <= 0` on a rules card, checked
  *before* the draw — a draw that takes the last card is not a draw from an empty
  pile. Both directions, since the penalty follows whoever would have received
  the card. **Half of each junk rule is still missing**: "VOID an ASH in your
  hand or discard" wants a card of one kind in one seat's zone, and a scope names
  a zone or a kind, never both. The Dragon pile has no VOID in it and is exact.
- **Rapid Fire does not return itself.** It does now, and nothing prevented it:
  the round-end sweep moves what is still standing in a battle spot, and a card
  that left is not there to be swept. One `move_to:mine.hand` on the rider.
- **Card counts are per design, not per print run.** Data, not engine. The print
  files do not record duplicate counts; nothing to fix here.
- **Oren's Chemistry Board.** Three stats, and each potion's Element cost is a
  `when` on the step that spends it — no disjunctive cost anywhere in it. What
  wants [31](../31-either-of-two.md) is *Unstable Formula*, which is a different
  card and a different question.

---

## F. Structural, and left alone on purpose

### F1. Hot-seat still shows the click (09 §1)

The `commit` zone closed the network case outright: the second player chooses
against a card back. Hot-seat cannot be fixed by any arrangement of phases,
because the other player is sitting there.

**Proposal — a handoff.** An overlay phase that blanks the board and waits
("pass the machine to Eve"). It is small, it is honest, and it belongs with
[16](../16-the-player-at-this-screen.md), which is where a seat learns to have a
name worth printing in that sentence.

**Size:** small. Not scheduled — hot-seat simultaneity is a niche of a niche.

### F2. ~~Oren's potion push-your-luck~~ — done

It was free, and it needed no `ends_when` at all: the phase is pushed by the
Ultimate and popped by whatever ends it, which is an action either way — the
*Stop drinking* button, or the rule that watches for a third TOXIC. A phase that
is ended by a condition and a phase that is ended by a button are different
shapes, and this is the second one.

The Chemistry Board came with it and was never the hard part: three stats, and a
potion's Element cost is a `when` on the step that spends it. A beaker too low is
a potion that does nothing, which is the printed rule.

One thing had to change beside it. An Ultimate is now `phases: ["play_1",
"play_2"]` — **an Ultimate that may be used inside anything can be used inside
itself**, and Oren's opens a phase to be used inside. That is where §2 already
said Ultimates live; it just had never been written down as a restriction.

### F3. The Tier check runs between rounds

Overflow is kept, so nothing is lost — it just arrives a moment late. A stat
that fires a rule on crossing a threshold is the general fix, and
`actions.on_stat_change` is already the hook a renderer uses for exactly this
signal. **Small, if it is ever worth the moment.**

### F4. The Unplayable Hand rule is a button

The engine has no way to notice a state and act on it — except that it does, once
per game: `end_conditions` is a list of `when`/`then` pairs evaluated as the game
runs. Generalise it into a top-level rule list evaluated at the same points, and
the button becomes automatic.

**Size:** small, and it is the same machinery, not new machinery. The button is
also arguably better interface, so this is a taste question as much as a
capability one.

### F5. More than two players, and Robot Boy

Both parked. Player count is [32](../32-a-third-player.md). Robot Boy is a
scripted opponent — a deck that plays itself, Blast Tokens standing in for a
hand, Tier-scaled riders on every card — which is a second game's worth of
machinery. His cards are all transcribed in `04-robot-boy.md` if it is ever
wanted.

---

---

## G. Found while closing the others

### G1. Riot fires the discard effects it says it does not

**What it costs.** Eve's *Riot* reads "discard your hand without triggering any
discard effects". That was accidentally true while On Discard was an ability
nothing ran outside Regroup. It is a `leaves` now — the card going from a hand to
a discard — and Riot's `move:mine.hand:mine.discard` is exactly that, so it sets
off every one of them. The card is wrong today, and it went wrong the moment the
trigger was made right.

**What will not do.** Routing the cards through a spare zone on the way —
hand → commit → discard, neither hop matching both ends of the trigger — works
and is a lie printed on a card. The format is the product; a card that says
"discard your hand" must say that.

**Proposal — a word for a move that is not a departure**, and it wants the
author's ear before it is written, because it is a new word in the file. `destroy`
already has the idea ("nothing is triggered by it") and the wrong shape, since
these cards must land in the discard and be counted there. Two spellings worth
weighing:

- on the action, beside `top`/`bottom`: `move:mine.hand:mine.discard:quietly` —
  short, and reads on the card as the printed text reads;
- on the trigger, as a scope the `leaves` declines: harder to write and no better
  to read.

The first is one argument on one verb, and the only card in the box that needs it
says why on its face.

**Size:** small, and blocked on a word rather than on work.

## What to do first

| | Item | Size | Why here |
|---|---|---|---|
| 1 | G1 — **a move that is not a departure**, for Riot | small | the one card the engine is currently *wrong* about, rather than merely short of; needs a word agreed first |
| 2 | C1 — **`chosen.where` narrows what is shown** | small | fixes every `[GAIN]`, every Essence and Flame in one change |
| 3 | A1 — **Ultimates as a reaction to a resolve verb** | small–medium | restores the `[ULT]` icon, the largest single departure |
| 4 | A2 — **one offer per seat, queued** | medium | Falling Star, and the last thing an automatic step cannot ask |
| 5 | B1 — **`adjusts.instead`** | small | Croh exact, Bunny exact |
| 6 | C2, C3, D2, D3 | small each | one card or three apiece |
| — | A3, A2's tail, F2, E, D1 | ~~various~~ | **done.** The copy, the journal, the potion loop, the five that were not gaps, and the random discards |
| — | B1's Glittering Dust, C4, F1, F5 | large or niche | **not recommended**, and each says why above |
