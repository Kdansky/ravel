# Spellstorm — closing the gaps

`09-engine-gaps.md` is the honest record: everywhere the playable version
departs from the printed game. This is the other half — what each departure
would cost to close, and what it would be called.

Written after building the game rather than before, which is the only order that
produces an honest list: every entry below is a shape the engine actually
refused, not one somebody imagined it might.

**The one thing worth reading if you read nothing else.** Eleven of the entries
below are the same missing word wearing different hats: *an automatic step
cannot stop and ask a question.* Ultimates on resolve, Abragail's spaces 2 and
4, Falling Star, May's Dangerous Download, Oren's potions, Diamond, Omar's
traps — all of them are a moment where the rules want the player's answer and
the engine is midway through an action list with nobody to ask. Everything else
here is small by comparison.

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

**What it costs.** Abragail's Research Journal spaces 2 and 4 are not
implemented, because a battle-start step is automatic. Falling Star gives mana
instead of offering the Storm Cloud to each player in turn. May's *Dangerous
Download* is missing entirely.

**Proposal — `push_phase`, which is already an action.** `push_phase` and
`pop_phase` exist and are already refused while an offer is open (`frozen()`).
An automatic step that wants an answer pushes a one-question `player_input`
phase and pops back when its `ends_when` is met. Two things to settle:

- **Where the loop resumes.** The pushed phase has to return to the *middle* of
  an action list, and an action list has no cursor today. Cheapest honest answer
  is that it does not resume: the step ends at the push, and what follows is the
  pushed phase's own `next`. That is enough for all four cards above.
- **`each_seat:` around a push.** Falling Star wants one offer *per seat*, which
  is a pushed phase with `seat: "next"` and a counter — see
  [32](../32-a-third-player.md), whose `seat: "all"` is the same question.

**Size:** medium. It is the single highest-value item in this file.

### A3. An offer opened inside an offer deadlocks (09, engine words §2)

**What it costs.** Seven cards resolve another card, and every one of them is
split into `cast` (deterministic, always runs) and `cast_ask` (the offer, never
reached by a copy). A copied *Lapis* draws but does not offer its discard.

**Proposal — stack the overlays.** `show:` from inside a `chosen` block currently
pushes an overlay that the outer `close_offer` then empties, leaving an
unresolvable `options` phase. The engine already has a phase *stack*
(`push_phase`/`pop_phase`); the offer overlay is the one thing not using it.
Make `close_offer` pop one rather than empty, and the `cast`/`cast_ask` split
disappears from all seven cards.

**Size:** small–medium, and it deletes code rather than adding it.

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
| 1 | F2 — **try the pushed potion phase** | free, if it works | costs an afternoon to find out and may close a component outright |
| 2 | E — **the five things that are not gaps** | small | five entries leave `09` for the price of some generator lines |
| 3 | C1 — **`chosen.where` narrows what is shown** | small | fixes every `[GAIN]`, every Essence and Flame in one change |
| 4 | D1 — **`random.` in a `move:`** | small | six cards become exact |
| 5 | A1 — **Ultimates as a reaction to a resolve verb** | small–medium | restores the `[ULT]` icon, the largest single departure |
| 6 | A3 — **stack the offer overlays** | small–medium | deletes the `cast`/`cast_ask` split from seven cards |
| 7 | A2 — **an automatic step that can ask** | medium | Abragail, Falling Star, May — and it is the word behind half this page |
| 8 | B1 — **`adjusts.instead`** | small | Croh exact, Bunny exact |
| 9 | C2, C3, D2, D3 | small each | one card or three apiece |
| — | B1's Glittering Dust, C4, F1, F5 | large or niche | **not recommended**, and each says why above |
