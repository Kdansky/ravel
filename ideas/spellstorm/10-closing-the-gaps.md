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

### A1. ~~Ultimates are cast on play, not on resolve~~ — done, and the answer was yes

**The open question was whether `reactions.responders` may open a window from
inside an *automatic* phase's action list.** It may. Nothing in the scheduler
had to learn anything: `settle` puts the response window ahead of every phase
decision, so an `emit:` from a phase's own actions leaves the stack waiting and
the phases behind it unrun. That made A1 a game-file change and no engine change
at all.

**What it is.** A card carrying the `[ULT]` icon carries one more ability,

```json
{ "key": "ult_call", "text": "Ultimate", "action": ["emit:resolving"] }
```

and the wizard carries the answer:

```json
{ "to": "resolving", "whose": "mine", "from": "wizard",
  "cost": { "mana@mine.player": 6 }, "action": [ … ] }
```

`"whose": "mine"` is the whole of *your own* card: the announcement is made by
whichever seat is resolving, and only that seat's wizard may answer it. The
subject is the card rather than a rule about the round, which is what lets the
window name the card that opened it — the engine already draws that line across
the top of the screen, with the Pass beside it.

**And the one thing it needed was a phase.** An action list has no cursor, so an
ask in the middle of one is answered after the rest of the list has run. A phase
that *ends* on the ask leaves the next phase waiting, so each side's resolution
became two: `ult_1` then `resolve_1`, `ult_2` then `resolve_2`. The seat is named
once per side, in the announce phase, since the resolve that follows is the same
seat's.

**Two latent engine bugs surfaced doing it**, neither reachable from any game
shipped at the time, both now fixed with tests:

- **`each_seat:` inside a deferred list looped one seat N times.** Priority
  outranks the turn wherever "mine" is worked out, and `each_seat` moved only the
  turn — so an emit's tail or a reaction's action ran the same seat's action once
  per seat. It moves whichever is being read now.
- **A pushed phase froze `settle` in any game with a stack.** `react_step` said
  "waiting" for `depth > 1` before checking whether the stack held anything, so an
  empty stack under an open page stopped end conditions and automatic phases
  both. The interjection rule is right; it just has to be asked second.

**What is still not the printed rule**: *Obsidian* and *Energy Wave* waive the
requirement rather than meet it (D4, and 09's weather note), and neither is a
thing a card can say about the round.

### A2. ~~A question inside an automatic step~~ — done (09 §2, Abragail, Falling Star, May)

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

**The queue is done, and the middle bullet above was wrong about how it failed.**
The second `show:` did not return silently: both offers opened, stacked, and the
two hands *merged* into the one `options` zone, so one seat was asked to pick out
of the other's cards. And the first offer was already going to the wrong seat —
`each_seat:` had put the turn back by the time the overlay was drawn, so it was
answered by whoever happened to be up.

**What it is.** `show:` writes the question down when the offer is busy, and
settle asks the next one when the last is answered — the same place a response
window is settled, and for the same reason: it is after an action. No new word;
`each_seat:show:mine.hand:optional` was always the sentence and now it works.

Three things make it small:

- **The request waits, not the cards.** The scope is read again when the question
  opens, against the board the previous answer left — so a question asked of a
  player whose hand somebody else has just emptied opens nothing, which is the
  rule an empty offer already had.
- **The asking seat is written down, not acted on.** An ask that moved the seat
  where it stood would move it out from under the list still running, and every
  remaining question would go to whoever asked first. Flow hands priority over
  once the game has come to rest — priority being the word that already means
  "who is acting, when it is not the turn player".
- **It is plain data on a zone**, so `entity.snapshot()` carries it into saves,
  net messages and undo checkpoints with nothing taught to any of them. Tested by
  encode/decode/apply mid-queue.

**Two things it dragged into the light.** Priority was released on the stack's
way past, so a game with offers and no stack zone would have kept it — that rule
is its own line in settle now. And closing an offer never settled, which nothing
had noticed because there was never anything waiting behind one.

**Falling Star is exact**, order included. `each_seat:` goes round the table from
whoever is up rather than always from the first seat — which is what "each
player" means wherever a rulebook bothers to say, and Spellstorm says it twice
("starting with the player with Initiative, then clockwise") — so naming the seat
before the loop is how a game chooses the order, with a word it already had.

For targeting, an ability run by a zone could open it the way a play does — but
nothing in this box needs that.

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

**Size:** the queue came in at about seventy lines across two files. Abragail was
a generator change and no engine work at all.

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

**Size:** medium — and cheaper than it was. A1 shipped the half they shared: a
window *does* open from inside an automatic step and holds it. What is left is
the verb itself, emitted from the damage path rather than from a card.

---

## C. Offers that cannot be narrowed or repeated

### C1. ~~`[GAIN]` ignores the Tier limit and the element~~ — done, and the proposal above was wrong

**What it was.** Any of the five Storm Cloud cards could be taken from a card
effect, whatever its Tier; the Essences offered the whole shelf rather than their
own element; nine cards said "not narrowed" in their tooltips.

**Why the proposal above was the wrong shape.** It asked `chosen.where` to narrow
what is *shown* as well as what may be taken. But `where` is documented to leave
the whole scope up on purpose — reading somebody's hand is usually half the rule
— and one field cannot mean both "show me less" and "show me everything, and grey
out the rest" without the author saying which.

**They are two questions, and the engine already had a word for each.**

- **Which cards come up** is a property of the *scope*, and a scope is narrowed
  by `<zone>.<tag>` — one place and one kind, the word that already writes
  `destroy:mine.discard.wound`. So `show:mine.hand.fire:optional` is the whole of
  "a Fire card from your hand", and the Water and Earth cards never leave the
  hand. Nothing has to be greyed out, because a card that never comes up is one
  nobody has to be told they may not click.
- **Which of them may be taken** stays `chosen.where`, and it has to be separate
  because it can ask about the *player*. "Tier I or II" is a number on the card
  (`tier_req@target <= 2`); "at or below **your** Tier" is not a property of the
  card being looked at at all, and no tag could ever say it.

Both were already there. Nine cards became exact — the three Essences, Flame,
Mana Font, Ice Flume, Ultimate, Spirit Crystal, Deep Gems and Beetle Buster — for
a lambda in the generator and no engine change.

**What is left is only where a card names two of something.** One scope names one
kind and one place: *Doom Bauble* ("a CURSE or ICE") gets the junk in the
discard, so an ASH comes up too, and *Ice Flume* ("from your hand or discard")
gets the hand. Both are recorded in `09`.

**The lesson, again.** Twice on this page now, the fix has been a word the engine
already had, used where it belongs. It is worth asking, before proposing a field,
which *question* the rule is asking — "which cards" and "which of these" look
alike on a card and are answered in different places.

### C1b. ~~A `[GAIN]` from a card effect ignored your Tier~~ — done

Noticed while wiring Falling Star, and worth its own entry because it is C1's
lesson going unapplied for a while. The Regroup gain was gated on the shelf card
itself and the three Essences on the number they print, but every plain `[GAIN]`
— Power Gem, Amber, Opal, Quake, Two Power, Three Power, Earth Dragon, Coffee
Run, New Curriculum, journal space 6 — offered the whole shelf.

The icon table says it outright: *"May gain a card from the Storm Cloud of your
Tier or lower, to hand"*, and the rulebook says both halves again for the Regroup
step. So two things were wrong, and the second was mine from the day before:

```json
"chosen": { "action": ["move_target_to:mine.hand", "draw_from:spellstorm_deck:storm_cloud:1"],
            "where":  ["tier@mine.player >= tier_req@target"] }
```

**A `chosen.where` and not a narrower scope**, for the reason C1 gives: your Tier
is not a property of the card being looked at, so no tag could say it. The whole
shelf comes up — seeing what is there is half the decision — and only what you
may take can be clicked. An offer where nothing qualifies does not open at all,
which is what *may* means.

And **Falling Star's gain went to the discard**, because I copied Power Gem. Power
Gem is the one card that says otherwise in its own text ("if you gained a card,
discard it"); everything else goes to hand.

Three keep their own rule and are untouched: the Essences say "any Tier I or II",
Meteorite says "regardless of tier", and Mana Font and Deep Gems VOID rather than
gain.

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

### G1. ~~Riot fires the discard effects it says it does not~~ — done, without a new word

**What it was.** Eve's *Riot* reads "discard your hand without triggering any
discard effects". That was accidentally true while On Discard was an ability
nothing ran outside Regroup, and went false the moment the trigger was made
right: a `leaves` fires on a card going from a hand to a discard, and
`move:mine.hand:mine.discard` is exactly that.

**What it did not get.** A keyword. A verb argument meaning "and this one does
not count" is a whole new idea in the format bought for one card in one box, and
the format is the product — every game file afterwards would have to know it.

**What it got instead: a detour.** The cards go by way of `quiet`, an offscreen
zone with `status: "exile"`, and neither hop is the trigger — leaving a hand for
the quiet is not a discard, and leaving the quiet for a discard is not leaving a
hand. Two lines on one card, using words that were already there:

```json
"action": ["move:mine.hand:quiet", "move:quiet:mine.discard"]
```

**And the thing that makes a detour honest is a comment.** A reader of the game
file would otherwise find two moves where the card says one thing, so the card
carries a `comment` saying why — a field the engine reads nowhere and that may
sit on anything with named fields. That is the general lesson, and it is worth
more than the trick: **the format did not need a word for this; it needed
somewhere to write down why.**

The zone is empty between any two steps, and Riot is the only card that uses it.

### G2. ~~"A CURSE or an ICE" cannot be said~~ — done, and it is a tag now

**What it was.** A condition list is an `and`; a scope names one tag and one
place. So *a CURSE or an ICE* had nowhere to be written — the two cards have
nothing in common to point at — and *from your hand or discard* had nowhere
either, since no zone key covers two zones. Between them they cost Doom Bauble,
Ice Flume, Bloodstone and all three empty-pile VOIDs.

**What it got: a name.** `computed_tags` already meant "a tag a card wears
because something is true of it"; it learned two more ways to work one out.

```json
"computed_tags": {
  "held":              { "any_of": ["in_hand", "in_discard"] },
  "curse_or_ice":      { "any_of": ["curse", "ice"] },
  "curse_or_ice_held": { "all_of": ["curse_or_ice", "held"] }
}
```

Three things make it small rather than a boolean language.

- **Tag names, never conditions.** Every tag question in the engine comes through
  one lookup, run on every card of every scope resolution. A condition there is
  the recomputation problem auras are. What a card *is* is a tag; what is *true*
  of it is a condition, and they meet in a `where`.
- **One entry, one combinator.** An `and` of `or`s is written by naming the
  middle of it, which reads as a sentence. Nesting would not.
- **A place is a kind**, because a zone hands out tags (`applies`). That is what
  makes "hand or discard" expressible without teaching scopes about zone lists.

**And one thing had to be added to reach it**: `everywhere.<tag>` as a scope. A
*subject* could always say "this tag wherever it sits" (`count:gem@mine.everywhere`)
and a scope could not, so a rule could count such a set and not show or move it —
one question with two spellings, in the one place `<zone>.<tag>` had missed.

**What this corrected.** Two things written on this page and in `09` were wrong,
and finding them was the useful part: `tags.owner_of` falls back to the zone's
seat, so an unowned ICE in your discard does answer "mine" — ownership was never
the blocker the empty-pile note claimed. And `mine.discard.ash` names a zone
**and** a kind, so half of that VOID was buildable all along.

## What to do first

| | Item | Size | Why here |
|---|---|---|---|
| 1 | B1 — **`adjusts.instead`** | small | Croh exact, Bunny exact |
| 2 | C2, C3, D2, D3 | small each | one card or three apiece |
| 3 | B2 — **Omar's Traps** | medium | now cheaper: A1 proved the window, and a trap is a reaction to a verb the damage path would emit |
| — | A1, A2, A3, F2, E, D1, G1, G2, C1 | ~~various~~ | **done.** The Ultimates, the offer queue, the copy, the journal, the potion loop, the five that were not gaps, the random discards, Riot's silence, the tag unions, and the narrowed offers |
| — | B1's Glittering Dust, C4, F1, F5 | large or niche | **not recommended**, and each says why above |
