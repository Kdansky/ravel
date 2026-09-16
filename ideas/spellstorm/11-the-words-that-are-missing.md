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

## 2. ~~A budget an aura can spend~~ — **not needed**

**Omar Evans, Trap — Dodge!** *"You may reveal this when an opponent is dealing
damage to you. The first 2 points of damage you take this round are negated."*

**This page was wrong about both halves.** It said first that the trigger had
nowhere to live, then corrected itself to say the trigger was easy and the budget
was the word. The budget was not a word either.

**The trigger.** Nothing in the engine's damage path speaks, which is true and
beside the point: a game makes its own moments. Damage is a declared verb, and
declaring one is now the whole of announcing it —

```python
DMG = lambda n: "hit:health@opponent:%d" % n
SELF_DMG = lambda n: "hurt:health@mine.player:%d" % n
```

```json
"reactions": [{"to": "hit", "whose": "enemy", "in": "traps", ...}]
```

— and the change waits behind the window, which is what puts the shield up
*before* the blow arrives. `whose: "enemy"` is "an **opponent** is dealing damage
to you"; damage a card does to its own side is a cost rather than an attack, so it
has a verb of its own that nothing answers and Dodge! cannot be revealed because
the other player poked themselves.

**This was built the wrong way round first, and the first way is worth recording.**
The announcement rode on each caller — `emit:damaging:hit:health@opponent:1` on
every attacking card. It worked, and it was wrong: a new kind of defence would
reopen every card that could ever be defended against, and the next raw
`stat_damage` written by hand would be silently unanswerable. Three such lines
already existed and had to be found and rewritten. The announcement belongs to the
verb.

**The budget.** Three words were said to come close and fail, and two of the three
readings were right about the word and wrong about the sentence.

`by` really cannot spend what it reads — it is read more than once per change, so
a read with a side effect would be a disaster — and it takes a number rather than
a measure. But "the first 2 points" does not need a measure. It is **two points**,
and a point is a shift of one:

```json
{"key": "soak_one", "verb": "wound", "stat": "health", "covers": "mine.player",
 "needs": ["guard@mine.traps >= 1"], "by": -1},
{"key": "soak_two", "verb": "wound", "stat": "health", "covers": "mine.player",
 "needs": ["guard@mine.traps >= 2"], "by": -1},
{"key": "soak", "verb": "hit", "stat": "health", "covers": "mine.player",
 "needs": ["guard@mine.traps >= 1"],
 "instead": ["wound:health@mine.player:amount",
             "stat_damage:guard@mine.traps:amount"]}
```

Each shift asks whether that much of the budget is still there. Three would be
three lines, and nothing in the box says three.

And the spending is the `instead`, which this page had looked at and dismissed for
wanting `amount - guard`. It wants no subtraction. The hit does not land; a
**wound** of the same size lands in its place, which is what the two shifts are
about, and the budget goes down by the size of the *blow* — `stat_damage` stops at
the floor, so a blow bigger than what is left uses up the rest and no more. That is
"the first 2 points", across as many blows as the round holds, with no arithmetic
anywhere.

**Two verbs, and that is the load-bearing part.** `hit` is what a card deals;
`wound` is what arrives once anything standing in front of it has taken its bite.
One verb would not do: a hit that re-dealt itself as a hit would find this same
rule on the way down and never arrive.

The budget lives on the Trap, as a card stat, because that is where a player can
see it and because it goes when the Trap does — the Ultimate zeroes it on the way
back to the pile, and the round takes what is left, the way an unspent free
Ultimate goes out with the round.

**What the engine gained, and it is one sentence rather than a field.** A verb a
game declares now announces itself wherever it is performed, and the change waits
behind the window an answer opens. `emit` keeps its job for moments that are not
stat changes — `countered`, `resolving`, `round_over` — and the held half of a
declared verb is written by the engine as `land:<action>`, which no game file says.

Two smaller corrections came with it. `validate` asked "is this declared verb
performed anywhere?" before it had read the tags, so `wound` — performed only
inside an `instead` — read as a verb nothing used; an aura is somewhere a verb is
performed, and the check moved below the tag loop. And a reaction may now answer a
declared verb without anybody writing an `emit` for it, so every declared verb
counts as emitted.

**What it still cannot say.** The announcement carries the acting card, not the
card being changed — so a reaction can ask *whose blow this is* and not *who it
lands on*. Spellstorm needs only the first, and says the second with a second verb.
A game wanting "whenever a creature is damaged" would need the change's subject on
the record, and would have to decide whether a verb aimed at four cards is one
moment or four.

---

## 3. ~~Parity~~ — one operator, and it needed no condition — **done**

**Derby Pocket, ULTIMATE (6) — Flaming Yardstick.** *"Deal 2 damage. If you have
an odd number of health, `[MANA]` `[MANA]`."*

**What this page proposed.** `odd` and `even` as condition operators, so
`health@mine.player is odd` would read as the card does.

**What it is.** A remainder in the compute grammar, which is smaller and says
more:

```json
"computes": [{"key": "yardstick_mana", "value": "health@mine.player % 2 * 2"}]
```

```python
ult_action=[DMG(2), "stat_gain:mana@mine.player:yardstick_mana"]
```

**There is no condition on the card, and that is the point.** A gain of nothing is
a gain of nothing, so the even case needs no second rule — where an `odd` operator
would have needed a branch beside it, and the format has no branch. `%` binds as
`*` does, so this is `(health % 2) * 2` by the precedence every reader has.

**And it is not a parity word, so it is not one case.** Every other round, every
third gem, a cost that repeats — none of which anyone had to argue for, because
they come with the operator rather than beside it. `/` was left out on the claim
that nothing in the box asks how many times a number went in — and the Power Track
does, one Tier per six Power. It is there now, rounding down, so a quotient is a
whole number like everything else.

**What it cost the engine.** One entry in `ARITH`, one word in the product loop,
and a guard making a remainder of nothing nothing rather than a number that is not
one — the operands are read off the board, and no author can promise the right one
is never zero.

**A second thing was wrong, and this is what found it.** A reaction's `compute`
was bound when the reaction was *offered* and not when it fired: `flow.M.react`
built a bare ctx and pushed the record without the bindings, so a name a reaction
computed read as nothing in its own action list. AUTHORING had promised
otherwise — "worked out just before it is judged **and again before it runs**" —
and no card had asked until this one. Fixed by binding once in `M.react` and
sending `let` up with the record, which is the road `emit` already used.

**And it printed a rule nobody wrote.** Obsidian costs 1 health for a free
Ultimate; Derby starts at 13. Taking the free cast flips him to even and his
Ultimate earns nothing — the pass costs the two mana it would have paid. That
falls out of two cards that never mention each other, which is the argument for
saying the rule once in the number rather than in a condition on the card.

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

## 5. ~~A number on an offer~~ — `chosen.count` — **not needed**

**Diamond.** *"If you hold 3 or more other cards, discard 3 of them and
`[POWER]` `[POWER]` `[POWER]`."* — and **Sift**, *"`[POWER]`. Look at the top 2
cards of your deck and put them back in any order."*

Both were filed here as wanting a count on an offer. Neither did.

**Diamond.** An offer with no `:optional` cannot be walked away from, so three of
them in a row *are* "exactly three":

```python
cast2=("count:spell@mine.hand >= 3",
       [POWER, POWER, POWER, HAND_PICK, HAND_PICK, HAND_PICK]),
chosen=["move:target:mine.discard"]
```

The one thing that looked like it would break does not. The gate reads the hand
and the hand empties under the very questions it gated — but an ability's `when`
is read once, before its action list runs, so all three questions are queued
while the hand is still whole and the third cannot close behind the second.

What a count would have bought is a *maximum* — "discard **up to** 3" — which no
card in this box says. `chosen` is one block per card, so it would also have had
to say which of several offers the number was about. Left unwritten.

**Sift.** The missing thing here was never a number either; it was a name for
cards you are *looking at*. `sifting` is that name, built for Ruby:

```python
cast=[POWER, "draw_from:mine.deck:sifting:2", "show:sifting"],
chosen=["move:sifting:mine.deck", "move:target:mine.deck"]
```

The pick goes back **last** and a deck takes a card on top, so the card named is
the one drawn next and the other lands under it. Leaving the order alone is
naming the card that was already on top, so "you may" and "you must" are the same
question and it needs no way out. The printed rule is on the card now, and the
`[Simplified]` note is gone.

That is a fourth entry off this list with nothing added to the engine, and the
second closed by a zone built for a different card.

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

## 10. ~~Replacing what another card does~~ — *Glittering Dust* — **done**

**Glittering Dust (Weather).** *"`[DRAW]` `[DRAW]`. `[EARTH]` cards do nothing
when resolved but Heal 2."*

**What this page said.** That rewriting what another card's whole action list does
needs a real replacement layer, that one weather card is not worth an effects
engine, and that it was listed so nobody proposed `adjusts.instead` as the fix.

**The first sentence was the mistake.** Nothing has to rewrite the action list.
A card does nothing when resolved by **not being in the spot the resolution
walks**:

```json
{ "key": "dust", "needs": ["card:glitteringdust@weather_now >= 1",
                           "count:earth@mine.battle >= 1"],
  "action": ["heal:health@mine.player:2", "destroy:mine.battle.earth"] }
```

on a rules card, at the top of every resolution and ahead of the four cast
columns. Nothing on any Earth card, which is the test: a weather card that rewrote
every Earth card would want rewriting every time one was printed.

**What made it small is the board, not the engine.** A battle spot holds one card
and the game resolves by walking a zone, so "skip this card's effect" is a question
about what is *in* the zone — which the format has always been able to ask. The
card goes where the round's own sweep would have sent it, by the same verb, one
step early, and nothing between here and there reads a battle spot.

**What is still true.** There is no way to gate an ability from outside the card
carrying it. A tag can shift a number (`buffs`) and interfere with a change
(`adjusts`), but nothing says "an ability on a card wearing this tag does not
run". A game resolving from a stack, or one where the silenced card had to keep
standing where it was, would still want that word. This one did not, and the
right reading of that is that the shape of the board decides it — not the card
text, which looks identical either way.

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

**Omar's Shuriken is done too, and this page was wrong about it.** "This card
ALWAYS goes first" was said to want a card-level override read by
`set_active_seat:has_init`. It wanted no word: the duel is a turn group, a turn
group orders itself by `highest:<stat>`, and the stat is the game's to choose. It
is `highest:lead` now, written at the reveal — after what was played is known, and
before the group that reads it is entered.

**And one thing the checking turned up**: a second question asked from inside a
`copy:` is swept, exactly as entry 8 describes — Wind Dragon loses its second
offer when another card resolves it, the same way *Data Breach* loses its second
half. Two customers for one ordering rule now.
