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

**And: Abragail's journal spaces 2 and 4 may be buildable today.** Only Abragail
has a journal, so only one seat ever asks, and an offer is exactly the
mechanism. They were left out for a reason that turns out not to hold. **Try it
before designing anything** — like F2, this one may already be free.

**Size:** the queue is medium. Abragail is a generator change and possibly zero
engine work.

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

**What that cost.** A flat ability list cannot say which of its entries are part
of being *resolved*, so a copy would have fired the discard effect too.
Spellstorm's `disc` steps now carry a `when` — they are looking only while no
card stands in a battle spot, which is every moment except a resolution. Worth
noting as a shape rather than a fix: **the four-pass resolve exists only to keep
`disc` out**, and now that `disc` says for itself when it is looking, one
`activate_zone` with no step would do the same work.

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

### D1. Random discards are not random (Shockwave, Dust Cloud, Tidal Wave, Undertow, Face Punch, Data Breach)

**Proposal — let `move:` take the `random.` quantifier it already parses.**
`random.` narrows a scope for *reading* today. `move:random.enemy.hand:enemy.discard`
is the same word doing the obvious thing, and six cards become exact.

**Size:** small. Best value-for-effort item in section D.

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

## E. Things that are not gaps at all

Worth separating, because they read like engine limits in `09` and are not.
Each is a to-do in the generator.

- **Croh's DOOM Token conditions.** "Gains a token only when he has none" is an
  ability `when` — `count:doom@mine.board <= 0`. The engine reads it today.
  Same for *Sinking Strike* granting one for an empty CURSE pile.
- **Empty-pile actions.** "Giving from an empty pile does nothing" can be a
  `when` on `count:@ice_pile <= 0` firing the printed alternative. Expressible
  now; simply not written.
- **Rapid Fire does not return itself.** Nothing obviously prevents it: the
  round-end sweep is `each_seat:move:mine.battle:mine.discard`, and a card that
  moved itself to hand during its cast is no longer in `battle` to be swept.
  **Worth re-testing before anything is built** — this may already work.
- **Card counts are per design, not per print run.** Data, not engine. The print
  files do not record duplicate counts; nothing to fix here.
- **Oren's Chemistry Board.** Three 0–6 tracks are three stats, and the engine
  has stats. Only the Ultimate that *spends* them needs a word, and that word is
  a disjunctive cost — [31](../31-either-of-two.md), or `pays_for` again.

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

### F2. Oren's potion push-your-luck

"Draw, resolve, then choose to stop or draw again, until a third TOXIC" is an
unbounded player-driven loop inside one ability — which is a **phase**, not an
ability, and the engine has phases with `ends_when`. A `player_input` phase
pushed by the Ultimate, ending on `count:toxic@mine.potion_discard >= 3` or a
*stop* button, may be buildable today with no engine change at all.

**Worth trying before it is designed.** It is the one item here that might
already be free.

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

## What to do first

| | Item | Size | Why here |
|---|---|---|---|
| 1 | A2's tail + F2 — **try Abragail's two spaces, and the potion phase** | free, if they work | both were left out for reasons that do not survive a test; either may already be buildable |
| 2 | E — **the five things that are not gaps** | small | five entries leave `09` for the price of some generator lines |
| 3 | C1 — **`chosen.where` narrows what is shown** | small | fixes every `[GAIN]`, every Essence and Flame in one change |
| 4 | D1 — **`random.` in a `move:`** | small | six cards become exact |
| 5 | A1 — **Ultimates as a reaction to a resolve verb** | small–medium | restores the `[ULT]` icon, the largest single departure |
| — | A3 — **the nested offer, and the half-resolved copy** | ~~small–medium~~ | **done.** Both landed; a copied card now resolves the whole of itself |
| 6 | A2 — **one offer per seat, queued** | medium | Falling Star, and the same question as `seat: "all"` |
| 8 | B1 — **`adjusts.instead`** | small | Croh exact, Bunny exact |
| 9 | C2, C3, D2, D3 | small each | one card or three apiece |
| — | B1's Glittering Dust, C4, F1, F5 | large or niche | **not recommended**, and each says why above |
