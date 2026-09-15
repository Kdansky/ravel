# Spellstorm — the words that are missing

Everything left in the box that the format cannot say, one entry per word rather
than one per card. `09-engine-gaps.md` is the running record of what departs from
the printed game and `10-closing-the-gaps.md` is what each departure would cost;
this is the short list those two now point at, written out in full so that a
reader deciding whether a word is worth adding has the printed rule, the closest
thing the engine can express, and the exact place the two part company.

**Read it against the engine before acting on it.** Three entries came off this
list in one session without anybody closing them — the word had shipped for
another game and the note went on asserting the old limit. A list of what the
engine cannot say is a claim about the engine, and claims go stale.

---

## 1. A stat change that runs an action instead — `adjusts.instead`

**Croh Vosh, PASSIVE — Accursed.** *"Whenever you would normally heal damage,
ignore all healing and give 1 CURSE instead."*

**What is built.** A battle-start sweep on a rules card:

```python
rules_card("r_accursed", "Accursed", …,
    [ability("bstart", GIVE("curse"), when=["count:croh@mine.wizard >= 1"])])
```

He gives one CURSE at the top of each battle, and he *can* still heal.

**What is missing.** `adjusts` is already a live hook on a stat change — it
carries `verb`, `stat`, `covers`, `needs` and `by`, and `by` shifts the number
that lands. What it cannot do is run an action *in place of* the change. The
printed rule is not "heal less"; it is "do this other thing rather than that
one", and no amount of `by` reaches it.

```json
"accursed": { "adjusts": [
  { "verb": "heal", "stat": "health@mine.player",
    "instead": ["move:curse_pile:enemy.discard"] } ] }
```

**Size:** small. It is one field on a hook that already fires at the right
moment, against the right stat, for the right seat.

**The same word, a second customer.** Bunny Wizard's **Triple Stitch!** —
*"If you heal when already at 10 health, `[DRAW]` for each point of wasted
healing."* His ceiling is 10 from the start, so the overheal never exists to be
counted. `adjusts` already computes that clamp and throws it away; exposing it as
a scope (`@adjusted`, say) and Bunny is exact. His other passive, **Double
Stitch** — *"You can heal beyond your starting health, to a maximum of 10"* —
needs nothing, and is the reason his seat gets `stat_boost:health@mine.player`
before its `stat_set`.

---

## 2. A verb the damage path announces — Omar's *Dodge!*

**Omar Evans, Trap — Dodge!** *"You may reveal this when an opponent is dealing
damage to you. The first 2 points of damage you take this round are negated."*

**What is built.** Nothing. The three Traps are the one wizard component with no
implementation, and Omar carries a `[Simplified: …]` note saying so.

**What is missing, and it is less than the note claims.** A reaction answers a
verb, and a verb is announced by a card being played or by an `emit:` in an
action list. "An opponent is dealing damage to you" is neither — nothing in the
damage path says anything out loud, so there is no announcement for a trap to
answer.

**Two of the three traps need no word at all.** *Mud Trap* and *Ice Bomb* trigger
on **countering**, and countering is already a rules card whose ability fires in
the showdown:

```python
ability("check", [DRAW], when=["count:%s@mine.battle >= 1" % a,
                               "count:%s@enemy.battle >= 1" % b])
```

An `emit:countered` on that ability is one line, and both traps become ordinary
reactions with `in: "traps"`. The face-down half already shipped for another
reason: a per-seat zone with `visibility: "owner"` **is** a trap that is placed
and unreadable, which is what the `commit` zone is.

And *Dodge!*'s **effect** is expressible today — "the first 2 points of damage
are negated" is `adjusts` with a `by`, which is the word a shield already uses.
It is only the trigger that has nowhere to live.

**Size:** small for two traps, medium for the third, and the third is the one
that wants a decision — whether the damage path announces itself is a question
about every game in the corpus, not about Omar.

---

## 3. Parity — Derby's Ultimate

**Derby Pocket, ULTIMATE (6) — Flaming Yardstick.** *"Deal 2 damage. If you have
an odd number of health, `[MANA]` `[MANA]`."*

**What is built.** `[DMG(2), MANA]` — two damage and one mana, always.

**What is missing.** There is no parity, modulo or division anywhere in the
condition grammar, so "an odd number of health" has no expression at all. Not a
narrow miss: there is no arithmetic to get close with.

**The shape.** One comparison, not an expression language — `odd` and `even` as
condition operators, so `health@mine.player is odd` reads as the card does. That
covers the only case in this box and does not reopen what
[17](../17-conditions-as-expressions.md) closed on purpose. Division has no
customer here at all.

**Size:** small. Do not generalise it.

---

## 4. What the last step touched — `@moved`

**Ruby.** *"Discard the top 3 cards of your deck. Deal 1 damage per `[FIRE]` card
discarded OR you may VOID one of the discarded cards."*

**What is built.** `["draw_from:mine.deck:mine.discard:3", DMG(1)]` — the three
cards go, and the damage is a flat 1.

**Lapis.** *"`[DRAW]`. You may discard up to 2 cards. Heal 1 for each `[WATER]`
discarded."* Built as `[DRAW, OFFER_HAND]` with `["destroy:target", HEAL(1)]` —
one card, and a flat 1.

**What is missing.** Nothing names the set a previous step moved. A reaction has
`@event` for "the thing this is about" and an action list has no equivalent for
"what the step before me touched", so a rider that counts what was just discarded
has nothing to count.

**Where the line is.** This is *not* the same as reading what the player picked.
Potion Gun already does that — `count:fire@options` counts the pick while it is
still lying in the offer, which is what makes its Element reading exact. The gap
is only the steps that move cards without asking.

**Size:** medium, and three cards want it.

---

## 5. A number on an offer — `chosen.count`

**Diamond.** *"Discard exactly 3 cards. If you did, `[POWER]` `[POWER]`
`[POWER]`."*

**What is built.**

```python
cast2=("count:spell@mine.hand >= 3",
       ["draw_from:mine.hand:mine.discard:3", POWER, POWER, POWER])
```

The count is right and the choice is not: the three that go are the first three
in hand.

**What is missing.** An offer closes on one pick. `chosen` has `where` for which
cards may be taken and no word for how many — the machinery to stay open exists
(`ends_when` on the `options` phase does it), but nothing says a number.

**Size:** small–medium. It wants `where` beside it or it will offer cards it
should not.

---

## 6. Routing the pick by what it is — `target.<tag>`

**Soothing Rain.** *"`[DRAW]`. Each player may VOID an ASH, CURSE or ICE in their
hand or discard pile."* — and a VOIDed junk card goes back on its own supply
pile rather than into the VOID, so which pile depends on what was picked.

**What is built.** Three moves, of which two always find nothing:

```python
chosen=["move:options.ice:ice_pile", "move:options.ash:ash_pile",
        "move:options.curse:curse_pile"]
```

It works because the pick is the only card left in the offer while `chosen` runs.
It reads as a bug.

**What is missing.** `move_target_to:` names one destination. A rule whose
destination depends on what the pick *is* has to name the offer zone and move by
tag instead, which is the same question with a second spelling — the fault
`<zone>.<tag>` was written to end, left in the one place it missed. The word is
`target.<tag>` as a scope.

**Size:** small, and it removes an idiom that every reader has to be told about.

---

## 7. A gate a zone hands out — `play.needs` through `behaviour`

**No card in this game.** Both of Spellstorm's zone-granted gates moved to
abilities, whose `when` is read. It is here because the next game will meet it.

**What is missing.** `flow.can_play` asks `def.needs` — the card's own — while
the action list it is about to run comes from `cards.behaviour`:

```lua
-- flow.lua:1269
if predicate.meets_all(def.needs, ctx) then return true end
```

So a zone can say *what* playing a card there does and not *whether* you may. The
two halves of one sentence are read from different places.

**Size:** one line, and it is a consistency fix rather than a feature.

---

## 8. An offer opened inside a `copy:` is swept

**May Danaris, *Data Breach*.** *"Lose 1 or 2 Energy Tokens. If you did,
`[POWER]` that many times. If you still have 2 Energy Tokens, chosen opponent
reveals their hand and they discard a card of your choice."*

**What is built.** The whole card, and it is right when the round resolves it.
The branches are an offer of two; the entry that is picked spends the Energy and
calls a rules card whose `when` is the second if.

**What is missing.** When the *whole resolution* is driven by `copy:` — Spirit
Crystal can resolve Data Breach, since it is Earth — the offer the entry opens is
swept, and May powers up without ever seeing the opponent's hand.

A3 fixed the same nesting through the other door: an offer opened from inside a
`chosen` block deadlocked until the leftovers were sent home *before* the chosen
actions ran. An entry's **play** action is that shape again, and the cleanup
still runs after it.

**Size:** one ordering rule, in the place A3 already touched.

---

## 9. `copy:<scope>:activate` has no cursor

**May Danaris, ULTIMATE (6) — Void Traveler.** *"Gain 3 Energy Tokens. You may
resolve a non-Wizard card from your hand or any card in the VOID. Then place that
card on the bottom of the Spellstorm Deck."*

**What is built.** The move is said *before* the resolve:

```python
chosen=["move:target:spellstorm_deck:bottom", "copy:target:activate"]
```

**What is missing.** Written in the printed order it breaks, and had been broken
since the card was written: `copy:target:activate` on a card that asks a question
opens an offer, and an action list has no cursor, so the move ran while the
question was still open and lost its target. Any `[GAIN]` card resolved out of
the VOID stayed where it was.

Reordering is a real fix and not a workaround — nothing here reads the
resolution's own place — but it only works because nothing *had* to come
afterwards. A card whose follow-on genuinely must follow has nowhere to put it,
and the two `cast`/`cast_ask` splits in the generator exist to dodge the same
edge from the other side.

**Size:** this is the general "an ask has no continuation" limit, and it is the
one thing on this page that is architecture rather than a word.

---

## 10. Replacing what another card does — *Glittering Dust*

**Glittering Dust (Weather).** *"`[DRAW]` `[DRAW]`. `[EARTH]` cards do nothing
when resolved but Heal 2."*

**What is built.** The two draws. The card carries a `[Simplified: …]` note
saying the rest is not there.

**What is missing.** Rewriting what another card's whole action list *does* is
not a stat hook, and nothing short of a real replacement layer covers it —
`adjusts.instead` is about one stat change, and this is about every effect on a
whole element of card, for one round.

**Recommendation: leave it.** One weather card is not worth an effects engine,
and the note on the card is honest. Listed so that nobody proposes
`adjusts.instead` as the fix for it.

---

## What is *not* on this page

Several `[Simplified: …]` notes still in the game look like engine gaps and are
probably content work — the words arrived while the cards stood still, which is
the failure this whole document exists to catch. Worth re-reading against the
engine before anybody writes a word for them:

- **Coffee Run** ("if you gained an `[EARTH]` card") and **Star Shot** ("if it
  was Tier II") both want to read what was just picked, which Potion Gun already
  does with `count:<tag>@options`.
- **Croh's Ultimate** ("redraw a card of your choice from your discard **OR**
  `[DRAW]`") is an or, and an or is an offer of two.
- **Rapid Fire** ("you **may** redraw this") is a one-entry optional offer, the
  shape Puzzle Strike's *Boost 3* has used all along.
- **Wind Dragon** ("resolve up to two cards") is two `show:` lines on one card,
  which is how *Amber* gains twice.
- **The empty-pile VOIDs** ("which ICE is VOIDed is not offered") were written
  before the offer queue landed, and the reason given — that a battle-start sweep
  runs for both seats and an offer is one at a time — is exactly what A2 fixed.

Two that really do need something, and are cheap to state: **Omar's Shuriken**
("this card ALWAYS goes first") wants a card-level override read by
`set_active_seat:has_init`, and **Deep Gems** ("you may lose 1 Power Token" as
the price of the rest) wants a cost on a chosen action.
