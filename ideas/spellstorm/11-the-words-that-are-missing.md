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

## 1. ~~A stat change that runs an action instead~~ — `adjusts.instead` — **done**

**Croh Vosh, PASSIVE — Accursed.** *"Whenever you would normally heal damage,
ignore all healing and give 1 CURSE instead."*

**What was built before.** A battle-start sweep on a rules card: he gave one
CURSE at the top of each battle whether or not anybody had tried to heal him, and
he could still heal. Two departures from one sentence.

**What it is now.** An aura printed on his own card:

```json
"accursed": { "adjusts": [
  { "key": "curse", "verb": "heal", "stat": "health", "covers": "mine.player",
    "instead": ["activate_zone:rules:by_column:dry_give_curse",
                "draw_from:curse_pile:enemy.discard:1"] } ] }
```

`by` says what a verb lands for; `instead` says it does not land at all and this
happens in its place. The printed rule was never "heal less", so no shift reached
it.

**What the word needed from the game.** Healing had to *be* a moment. The engine's
own `stat_gain` is unwatchable on purpose — that rule is the whole of what makes
interference something a game opts into — so Spellstorm now declares one verb,
`heal`, and every heal in the box goes through it, including the one Bunny hands
his opponent. The `wizard` zone also gained `"status": "board"`, because an aura is
only read while its card is in play and the game had no board zone at all.

**Two things the note did not say, and the build found.**

The list runs as **the aura's own side**, with the aura as `@self` and the card
that would have changed as `@target`. Anything else gets the seat wrong the moment
somebody *else* heals Croh — Bunny's Ultimate heals both players — and the CURSE
would come from the healer rather than from the cursed.

And a chain that leads back to itself has to terminate. Two auras each replacing
the other's verb would hand one change back and forth for ever, so the chain is
cut after 200 substitutions and the change the last aura would have refused is
allowed to land. A file that does it is a bug rather than a game; running out of
stack is the one outcome worth ruling out.

**The same hook, a second customer — also done, and not as written here.**
Bunny Wizard's **Triple Stitch!** — *"If you heal when already at 10 health,
`[DRAW]` for each point of wasted healing."*

This page said the number wanted was the clamp `adjusts` computes and throws away,
to be exposed as a scope. It was not. His rule is conditioned on being **already at
10**, and there every point of a heal is wasted — so the number is simply how big
the change was, and there is no clamp to report. That is `amount`, bound in the
hook's `needs` and in its `instead` alike, always as a player reads it: "3 damage"
is 3, never the negative the engine carries.

```json
"overhealing": { "adjusts": [
  { "key": "spare", "verb": "heal", "stat": "health", "covers": "mine.player",
    "needs": ["health@mine.player >= 10"],
    "instead": ["draw_from:mine.deck:mine.hand:amount"] } ] }
```

And this page said his other passive, **Double Stitch** — *"You can heal beyond
your starting health, to a maximum of 10"* — needed nothing, because his ceiling
was 10 from the start. **It was 8.** Every wizard's ceiling was worked out from
printed health and nothing made him the exception, so neither passive existed. A
ceiling of his own is one number in the roster; the claim that it was already
there is the third time a note on this page has asserted something the engine had
not done.

---

## 2. A budget an aura can spend — Omar's *Dodge!*

**Omar Evans, Trap — Dodge!** *"You may reveal this when an opponent is dealing
damage to you. The first 2 points of damage you take this round are negated."*

**Two of the three traps are done, and neither needed a word.** *Mud Trap* and
*Ice Bomb* trigger on **countering**, which was already a rules card firing in the
showdown. One `emit:countered` on it and each trap is an ordinary reaction with
`in: "traps"` — the same shape as the Ultimate answering `resolving`. The counter's
own draw is the emit's *held* action, because an action list runs to completion and
a draw written beside the announcement would land before anyone had answered it.
The face-down half was shipped too: a per-seat zone with `visibility: "owner"` **is**
a card placed and unreadable, which is what `commit` already was. *Ice Bomb* even
announces `resolving` of its own, and the Ultimate answers it from inside the
window the counter opened.

**This page was wrong about which half was hard.** It said the trigger had nowhere
to live, because nothing in the damage path speaks. That is true of the engine and
beside the point — a game makes its own moments, and `emit` takes a held action, so
`emit:damaging:stat_damage:health@opponent:2` announces the hit and lets it land
afterwards. Every damage in the box comes out of two lambdas in the generator, so
that trigger is two lines and no engine word at all.

**What is actually missing is the effect.** "The first 2 points of damage you take
this round are negated" is a budget that is *spent as it is used*, and three words
come close and fail the same way:

- **`adjusts.by`** can reduce by a measure — `"by": "-min:dodge@mine.player"` — but
  cannot spend the counter it read, and `by` is read more than once per change, so
  a read with a side effect would be a disaster.
- **`adjusts.instead`** can cancel and re-deal, but the remainder is
  `amount - dodge`, and the amount grammar has multiplication and nothing else. No
  subtraction; `min:` is a minimum over a subject's bearers, not of two numbers.
  Dealing `amount` and healing `dodge` back is wrong twice over — it overheals when
  the hit is smaller than the budget, and healing is a declared moment now, so it
  would hand Croh a CURSE.
- **`counterspell`** in the reaction negates the *whole* hit, which is right only
  when it is two points or fewer.

So the word is either arithmetic in the amount grammar, or a way for an `adjusts` to
spend what it read. The second is smaller, and it is what every *prevent the next N
damage* shield in any game wants — which is the decision this entry always meant,
mislabelled as being about the trigger.

**Size:** small once the shape is chosen; the choice is the work.

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

## 4. ~~What the last step touched~~ — a zone is the name — **done**

**Ruby.** *"Discard the top 3 cards of your deck. Deal 1 damage per `[FIRE]` card
discarded OR you may VOID one of the discarded cards."*

**What this page claimed.** That nothing names the set a previous step moved, and
that three cards wanted a word — `@moved` — for it.

**Two of the three were never about that.** *Lapis* ("you may discard up to 2
cards, heal 1 for each `[WATER]` discarded") asks, and the count rides on the
answer: a pick leaves the offer holding exactly the card taken, so a rule asked
from `chosen`, before the discard, counts what was just chosen. That is Coffee
Run, shipped. *Lava Bat* ("move a non-Wizard `[FIRE]` card from any discard to any
other") was never counting anything — the direction is two entries and the filter
is a scope plus a `where`.

**And Ruby wanted a zone, not a word.** A set that moves without anybody picking
it has no name, so give it one: the three go to `sifting` instead of straight to
the discard, and `count:fire@sifting` is the damage.

**The interesting half is the question.** "Deal damage OR VOID one of them" wants
the player to *read the three* before deciding, which an offer of two entries does
not show. So the other half of the "or" is minted **into the same zone**:

```python
cast=["draw_from:mine.deck:sifting:3",
      "create:sifting:ruby_burn:1",
      "stat_set:counted@sifting.burn:count:fire@sifting",
      "show:sifting"]
```

One question, four cards — three real and one standing for the alternative — and
the branch is which came back. Two things make it work, and neither is new:

- **`@options` inside `chosen` is the answer, not the question.** `flow.lua:1453`
  sends the rest of the offer home before the chosen actions run, keeping only the
  picked card. So `count:burn@options` says which branch was taken.
- **A card's text is filled like any label.** `"Deal {stats.counted} damage"` on
  the minted card reads the number written onto it a step earlier, so the choice
  says what it is worth instead of making the player count Fire icons.

**One small gap this turned up, and one that is now closed.** `set_owner` had a
vocabulary of its own — `mine`, `none`, or a seat's key — while `set_active_seat`
and `set_priority` had been naming a seat with an ordinary scope the whole time.
One question, two spellings, and the smaller one could not say "the other player"
at all. It takes a scope now, so Lava Bat's give direction is
`set_owner:target:opponent` and `none` is the only literal left, because nobody is
not a seat and an empty scope means *skip* rather than *clear*.

What is still open: **the prompt above an offer cannot be written per question**: `render.lua:1890` prints the overlay phase's `label`
through `label.fill`, and `draw_zone` prints the offer zone's — but both are one
string for every question in the game, and no action can write either. So what a
choice means has to live on the cards in it, which is where this game has always
put it.

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

**Six notes came off the cards when this section was checked**, and every one was
content work: the words had arrived while the cards stood still, which is the
failure this whole document exists to catch. They are listed here because the
shapes are reusable, not because anything is left to do.

- **Coffee Run** ("if you gained an `[EARTH]` card") and **Star Shot** ("if it
  was Tier II") read the card just picked, which is the only one still lying in
  the offer while a `chosen` list runs — `count:earth@options` and
  `sum:tier_req@options`, the reading Potion Gun took its Element from. Counted
  *before* the move, since a card in hand is no longer in the offer.
- **Croh's Ultimate** ("for each DOOM Token, redraw a card of your choice **OR**
  `[DRAW]`") is not one or but *N* of them, and a number of questions worked out
  from a stat has no spelling at all — an action list is written once and a stat
  is read as it runs. One rules card per token he might hold, each gated on
  holding that many, and the Ultimate walks the column.
- **Rapid Fire** ("you **may** redraw this") is a one-entry offer with a No
  button, the shape Puzzle Strike's *Boost 3* has used all along. A cost is one
  map settled in full, so a part you may decline is always an offer.
- **Wind Dragon** and **Shatter** ("up to two") are two `show:` lines on one
  card, which is how *Amber* gains twice. The per-card rider rides on the
  answer, so it counts itself.
- **The empty-pile VOIDs** were the interesting one. *Which* ICE looks
  immaterial — every ICE is the same card — and is not: one in your hand costs a
  Blast Score and one in your discard costs a draw. The holder is asked, and
  when the junk was being *given* the holder is the other player, which is the
  whole of `set_priority`: from inside that window, `mine` is theirs.

**Deep Gems is done, and did not want a new field.** "You may lose 1 Power Token"
is a price on the answer, and `chosen` carries only `where` and `action` — so the
gate is the `where` and the payment is the first thing the answer does. Declining
owes nothing, which the optional offer already said. Better than the note hoped,
too: an offer where nothing may be taken does not open, so with no token he is not
asked at all.

**Buddy System is done as well.** "You may resolve a *different* revealed
`[EARTH]` card" is `show:others.battle.earth:optional` — `battle` names the
revealed cards across both seats and `others.` is the pool with the asking card
taken out of it, so the card cannot offer itself and nothing has to name which
card is meant.

One that really does need something, and is cheap to state: **Omar's Shuriken**
("this card ALWAYS goes first") wants a card-level override read by
`set_active_seat:has_init`.

**And one thing the checking turned up**: a second question asked from inside a
`copy:` is swept, exactly as entry 8 describes — Wind Dragon loses its second
offer when another card resolves it, the same way *Data Breach* loses its second
half. Two customers for one ordering rule now.
