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

### A1. Ultimates are cast on play, not on resolve — done, and the answer was yes (09 §2)

**The open question was whether `reactions.responders` may open a window from
inside an *automatic* phase's action list.** It may — `settle` puts the response
window ahead of every phase decision, so nothing in the scheduler had to learn
anything. The fix and shape are in 09 §2; not repeated here.

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

### A2. A question inside an automatic step — done (Abragail, Falling Star, May)

An automatic step *can* ask — `show:` already opens an offer from inside an
ability an automatic phase activated. Three narrower things are true instead of
"it cannot ask":

- **It cannot open targeting.** `activate_zone` runs every ability with
  `targets = {}`, hardcoded — an offer is the only way to ask.
- **It cannot ask each seat in turn.** `each_seat:` runs both seats inside one
  step and there is one `options` zone — the real blocker, and it is Falling
  Star exactly.
- **It cannot resume.** An action list has no cursor, so whatever follows the
  ask runs before the answer arrives.

**The fault, once found, was not the middle bullet as guessed.** Both offers
opened and the two hands *merged* into the one `options` zone, so one seat
picked out of the other's cards — and the first offer was already going to the
wrong seat, since `each_seat:` had moved the turn on by the time the overlay
drew.

**What it is.** `show:` writes the question down when the offer is busy, and
settle asks the next one when the last is answered — the same place a response
window is settled, and for the same reason. No new word;
`each_seat:show:mine.hand:optional` was always the sentence.

- **The request waits, not the cards** — the scope is read again when the
  question opens, against whatever board the previous answer left.
- **The asking seat is written down, not acted on** — moving it would pull it
  out from under the list still running. Flow hands priority over once the game
  has come to rest.
- **It is plain data on a zone**, so saves, net messages and undo cross it for
  free.

**Two things it dragged into the light.** Priority was released on the stack's
way past, so a game with offers and no stack zone would have kept it — its own
line in settle now. And closing an offer never settled, unnoticed because
nothing had ever waited behind one.

**Falling Star is exact**, order included: `each_seat:` goes round the table
from whoever is up, which is what "each player" means wherever a rulebook
bothers to say it.

**Abragail's journal — all three asking spaces**, and space 6 (`[GAIN]`) was a
fourth nobody had noticed. One seat asking is not one ask: a fully-researched
journal asks three times in one battle-start list, and a mirror match means
both seats have a journal. Each asking space got its own phase, one seat per
phase — six short automatic phases, empty for every other wizard.

Worth keeping as the shape: **a phase is the engine's word for "and then".**

### A3. An offer opened inside an offer deadlocks — done (09 §3)

Two faults, fixed as described in 09 §3: the offer-cleanup ordering, and
`copy:<scope>:activate` running only a card's first ability. `leaves.from` is
the engine word that came out of it.

**Worth keeping as a shape, not in 09:** the four-pass resolve had a second job
— keeping `disc` out of a stepless pass — and no longer has it, since `leaves`
now carries that rule instead of a condition on the step.

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

### C1. `[GAIN]` ignores the Tier limit and the element — done

**The proposal in an earlier draft here was the wrong shape**: it asked
`chosen.where` to narrow what is *shown* as well as what may be taken, but
`where` is documented to leave the whole scope up on purpose, and one field
cannot mean both "show less" and "show everything, greyed out" without saying
which.

**They are two questions, and the engine already had a word for each.**

- **Which cards come up** is a property of the *scope* — `<zone>.<tag>` narrows
  it, the same word `destroy:mine.discard.wound` already uses. So
  `show:mine.hand.fire:optional` is the whole of "a Fire card from your hand".
- **Which of them may be taken** stays `chosen.where`, because it can ask about
  the *player* — "at or below your Tier" is not a property of the card at all,
  and no tag could ever say it.

Both words were already there; nine cards became exact for a lambda in the
generator.

**The lesson, again**, and it is the one worth keeping: ask which *question* a
rule is asking before proposing a field — "which cards" and "which of these"
look alike on a card and are answered in different places.

**Left:** where a card names two of something in one scope (one place, one
kind) — Doom Bauble's "a CURSE or ICE", Ice Flume's "hand or discard" — see 09.

### C1b. A `[GAIN]` from a card effect ignored your Tier — done

C1's lesson, unapplied for a while: every plain `[GAIN]` but the Essences and
Regroup offered the whole shelf regardless of Tier, fixed the same way as C1 —
`chosen.where`, not a narrower scope, since your Tier is not a property of the
card being looked at.

**Trap:** Falling Star's gain went to the discard because it was copied from
Power Gem, which is the one card that sends a gain to the discard by its own
text; everything else goes to hand.

### C2. "Gain twice" gains once — done (Amber, Earth Dragon)

No new word needed: two `show:` lines on one card are already two questions,
held one at a time, both answered by the same `chosen`.

**The rejected alternative is the trap worth keeping.** A counter in one
`chosen` block, telling the questions apart by how many had been answered,
reads well until the first "up to" is declined — nothing runs on a decline, so
the count never advances and every question after it means the wrong thing.

Abragail's *New Curriculum* looked like a double gain and was not: one
`[GAIN]` and a separate VOID are two different fates for a chosen card, and a
card has one `chosen` block — so **a second asker is a second answer**, each
owning what happens to its own pick, the same idiom the journal's asking
spaces use.

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

### D1. Random discards are not random — done, and it was already there

`move:` had honoured `random.` since the quantifier existed; nobody had written
it down, so six cards discarded the top of a hand for want of a sentence in
`AUTHORING.md`. Now said there and in `SCHEMA.json`.

**The lesson is about the docs, not the engine.** A word the engine knows and
the reference does not is a word the game cannot use.

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

## E. Things that are not gaps at all — done, all five

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

### F2. Oren's potion push-your-luck — done

Needed no `ends_when` at all: the phase is pushed by the Ultimate and popped by
whatever ends it, an action either way — the *Stop drinking* button, or the
rule watching for a third TOXIC. A phase ended by a condition and a phase ended
by a button are different shapes; this is the second one.

**Trap worth keeping:** an Ultimate is now `phases: ["play_1", "play_2"]`,
because an Ultimate that may be used inside anything can be used inside
itself — Oren's opens a phase to be used inside it, a restriction A1's rule
had never had to state until this card needed it.

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

### G1. Riot fires the discard effects it says it does not — done, without a new word

Eve's *Riot* ("discard your hand without triggering any discard effects") broke
once On Discard became a real `leaves` trigger on hand→discard. **Rejected:** a
verb argument meaning "and this one does not count" — a new idea in the format
bought for one card, and the format is the product.

**What it got instead: a detour**, through `quiet`, an offscreen exile zone —
leaving a hand for `quiet` is not a discard, and leaving `quiet` for a discard
is not leaving a hand. Two moves, words already there.

**The lesson worth keeping:** a detour needs a `comment` on the card explaining
why, since a reader would otherwise find two moves where the card says one —
**the format did not need a word for this; it needed somewhere to write down
why.**

### G2. "A CURSE or an ICE" cannot be said — done, and it is a tag now

A condition list is an `and`; a scope names one tag and one place — so *a
CURSE or an ICE* and *from your hand or discard* both had nowhere to be
written. Cost Doom Bauble, Ice Flume, Bloodstone and the empty-pile VOIDs.

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
| 2 | C3, D2, D3 | small each | one card or three apiece |
| 3 | **An offered card's own `needs`** | one line | `pickable` answers for every card in an offer and only asks the asker's `chosen.where`; a dealt entry should fall through to its `needs`. Oren's pours want it, and it is the same fault as F-the-zone-granted-play in the other half of the offer |
| 4 | B2 — **Omar's Traps** | medium | now cheaper: A1 proved the window, and a trap is a reaction to a verb the damage path would emit |
| — | A1, A2, A3, C2, F2, E, D1, G1, G2, C1 | ~~various~~ | **done.** The Ultimates, the offer queue, the copy, the journal, the potion loop, the doubled gains, May's download, Oren's four, the weather, the five that were not gaps, the random discards, Riot's silence, the tag unions, and the narrowed offers |
| — | B1's Glittering Dust, C4, F1, F5 | large or niche | **not recommended**, and each says why above |
