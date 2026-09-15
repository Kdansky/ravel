# Cookbook — an effect, and the JSON that says it

**How to use this file.** Every `###` heading is one effect, written the way a card or a
rulebook writes it. The headings *are* the index:

```
grep '^### ' COOKBOOK.md
```

Read those. When one matches the card in front of you, read the JSON under it and nothing
else. Skimming this file end to end is a human's way through it and a waste of an agent's
context.

Each block carries **only the fields the effect needs** — no `key`, no `text`, no surrounding
card, unless the effect is about them. `<angled>` is yours to fill in. A line beginning
**Trap** is the mistake the effect usually causes; a line beginning **Also** is the nearby
spelling you may have wanted instead.

These are the common cases. A card whose context differs is the author's problem — the point
of the file is that the wheel was already turned once. `AUTHORING.md` §5 says what every field
*means*; `SCHEMA.json` lists them alphabetically; this file is the index by *what you want to
happen*.

---

## Numbers

### Gain 2 gold.

```json
"action": ["stat_gain:gold@mine.player:2"]
```

Also: `"stat_gain:gold:2"` — a bare subject is the seat whose turn it is, which is the same
thing said shorter.

### Lose 2 gold.

```json
"action": ["stat_damage:gold@mine.player:2"]
```

Trap: this takes what is there and floors at the stat's `min`. A price the player must be able
to *afford* is a `cost`, not this.

### Set a number to exactly 0.

```json
"action": ["stat_set:guard@self:0"]
```

### This card's maximum health goes up by 5.

```json
"action": ["stat_boost:health@mine.player:5"]
```

Only the ceiling moves; the current value stays where it is (and is re-clamped under the new
bound).

### Gain 1 gold for each Farm you control.

```json
"action": ["stat_gain:gold@mine.player:count@mine.farm"]
```

Trap: `count:farm` with no `@` is **every** farm in play, both sides. `count@mine.farm` counts
the pool "my farms"; `count:farm@board` counts farms lying in the zone `board`.

### Gain gold equal to the target's printed price.

```json
"action": ["stat_gain:gold@mine.player:sum:price@target"]
```

### Deal damage equal to the biggest attack on your side.

```json
"action": ["damage:hp@target:max:atk@mine.army"]
```

`max:` and `sum:` of an empty pool are 0. `min:` of an empty pool is **absent** and fails every
comparison — nothing is not *at least* nothing.

### A number only creatures have.

```json
"stats": [{ "key": "hp", "min": 0, "on": ["creature"], "start": 3 }]
```

A card carrying none of the `on` tags does not take part: an action skips it, and a comparison
against its missing stat **fails rather than reading zero**. Leave `start` out and every bearer
must say its own in `card_stats`.

### Every seat has 20 life.

```json
"stats": [{ "key": "life", "min": 0, "max": 20, "on": ["player"], "start": 20 }]
```

`player` is stamped on the cards your `players` list names. It is the one tag you never type.

### A marker with no number printed on it.

```json
"stats": [{ "key": "hits", "min": 0, "max": 1, "icon": "fist", "number": false }]
```

### A number kept on cards, not on a seat, that still wants bounds and an icon.

```json
"stats": [{ "key": "hp", "min": 0, "max": 9, "on": ["unit"], "display": "offscreen" }]
```

`offscreen` keeps it out of the HUD; everything else about a stat still applies.

### The HUD row shows a total worked out from the board.

```json
"stats": [{ "key": "defense", "subject": "sum:defense@standing" }]
```

The key still names what cards spend; `subject` only changes what the row *reads*.

### A number with a name, worked out where it is used and stored nowhere.

```json
"computes": [{ "key": "overkill", "value": "0 - health@across" }],
"abilities": [{ "compute": ["overkill"], "needs": ["overkill >= 1"],
                "action": ["stat_gain:spill@self:overkill"] }]
```

`from` is one term, or two with one of `+ - *` and spaces around it. No parentheses. A compute
may name an earlier compute if the ability lists that one first. A **computed tag** and a
**phase's actions** may not name one at all — nobody is acting, so nobody listed it.

---

## Damage, healing, and being answered

### Deal 3 damage to a unit.

```json
"verbs": [{ "key": "damage", "does": "stat_damage" }],
"play": { "target": { "type": "card", "tags": ["unit"], "count": 1 },
          "action": ["damage:hp@target:3"] }
```

Trap: write `stat_damage:` directly and **nothing can answer it** — no armour, no resist, no
ward. The engine's own verb is deliberately unwatchable. Name your own moment first.

### Armour: this takes 1 less damage.

```json
"tags": { "armoured": { "adjusts": [
  { "key": "armour", "verb": "damage", "stat": "hp", "covers": "self", "by": -1 }] } }
```

`covers` is who it protects — `self`, or a scope like `each.mine.unit` for an anthem. Two auras
on one card sum. An adjust may not flip the sign: 3 damage reduced by 5 is none, never a heal.

### Armour that stops swords and not poison.

```json
"verbs": [{ "key": "damage", "does": "stat_damage" },
          { "key": "poison", "does": "stat_damage" }]
```

Both run `stat_damage`; the aura names one of them. That is the whole mechanism — a verb is a
*meaning* laid over a mechanism, and interference is opted into.

### Takes 2 less, but only from a witch.

```json
"adjusts": [{ "key": "ward", "verb": "damage", "stat": "hp", "covers": "self", "by": -2,
              "needs": ["tagged:witch@source"] }]
```

`@source` is who is doing it — the one thing no other scope names. `@self` is the card holding
the aura, `@target` the card being hit.

### This spell costs 1 more for each of their heroes in play.

```json
"tags": { "taxed": { "adjusts": [
  { "key": "resist", "verb": "cast", "stat": "gold", "covers": "self", "by": 1,
    "needs": ["count@enemy.self >= 1"] }] } }
```

Resist is the same word as armour, pointed at a cost rather than at damage.

### Heal 2.

```json
"verbs": [{ "key": "mend", "does": "stat_gain" }],
"action": ["mend:hp@target:2"]
```

### Deal 3 damage divided as you choose.

```json
"play": { "target": { "verb": "cast", "type": "card", "spread": 3,
                      "owner": "enemy", "zones": ["patrol", "army"] },
          "action": ["damage:hp@target:1"] }
```

Three *points*, not three cards. `@target` is every pick in order, so a card named twice takes
it twice. `spread` beside `count` is refused — they answer the same question.

### Deal 1 damage to every enemy unit.

```json
"action": ["damage:hp@each.enemy.unit:1"]
```

### Deal 1 damage to a random enemy unit.

```json
"action": ["damage:hp@random.enemy.unit:1"]
```

### Deal 1 damage to the player who owns the target.

```json
"action": ["damage:life@owner_of.target:1"]
```

### Damage the other player.

```json
"action": ["damage:life@opponent:1"]
```

`@opponent` is *the* other seat and only exists in a two-seat game. `enemy` means "not mine"
and is a pool of any size.

---

## Counters on a card

### Put a +1/+1 rune on it. Runes stack.

```json
"stats": [{ "key": "runes", "min": 0, "max": 99, "on": ["unit"], "start": 0,
            "buffs": { "atk": 1, "hp": 1 } }],
"action": ["stat_gain:runes@target:1"]
```

A counter is a stat that carries a buff: the buff is applied **once per point held**, so three
runes is +3/+3. Nothing is written to `atk` — it is worked out on every read, so removing the
counter removes the bonus with no undo path to forget.

### Take the runes off at end of turn.

```json
"action": ["stat_set:runes@each.anyone.unit:0"]
```

Put it in the phase whose route carries `"ends_round": true`, or in a rules column that phase
walks.

### −1/−1 until end of turn.

```json
"stats": [{ "key": "minus", "on": ["unit"], "start": 0, "buffs": { "atk": -1, "hp": -1 } },
          { "key": "sank",  "on": ["unit"], "start": 0 }],
"action": ["stat_gain:minus@target:1", "stat_gain:sank@target:1"]
```

Then in the end-of-turn column: `["stat_damage:minus@self:sum:sank@self", "stat_set:sank@self:0"]`.
The second stat records **what this turn lent**, so a permanent rune given earlier survives the
handback.

---

## What a card is

### This card is a Soldier.

```json
"tags": ["soldier"]
```

### While it has no health left it counts as dead.

```json
"computed_tags": { "dead": { "needs": ["hp@self < 1"] } }
```

Worn like any other tag, worked out on every read, and usable anywhere a tag is.

### A Fire card or an Ice card.

```json
"computed_tags": { "elemental": { "any_of": ["fire", "ice"] } }
```

`all_of` is the other one. A union with a name is usable as a scope, in `applies`, in a target
spec — anywhere a tag goes.

### Elite units have +1 attack.

```json
"tags": { "elite": { "buffs": { "atk": 1 } } }
```

Trap: `"action": ["stat_gain:atk@target:1"]` looks equivalent and is not — something then has
to take it away again on every path the card can leave by, and missing one is a silent
permanent bonus.

### Units in the arena get +3 attack while they stand there.

```json
"tags": { "raging": { "buffs": { "atk": 3 } } },
"zones": [{ "key": "arena", "applies": ["raging"] }]
```

### While it is wounded it hits harder.

```json
"computed_tags": { "hurt": { "needs": ["hp@self < 3"] } },
"tags": { "hurt": { "buffs": { "atk": 2 } } }
```

The computed tag says when; the tag of the same name says what.

### A keyword with rules text the player can read.

```json
"tags": { "flying": { "tooltip": "Flying — only a flier may block it." } }
```

### Every Soldier can do this.

```json
"tags": { "soldier": { "abilities": [
  { "key": "rally", "text": "Rally", "cost": { "exhaust": 1 },
    "action": ["mend:hp@each.mine.soldier:1"] }] } }
```

A tag may carry `abilities`, `play`, `receive`, `leaves`, `buffs`, `adjusts`, `emits` and
`tooltip` — everything a card can carry about behaviour. A card writing its own `play` takes
none of the tag's.

### A tier that can be compared, not just checked.

```json
"tags": { "tech_2": { "buffs": { "tech_level": 2 } } },
"stats": [{ "key": "tech_level", "min": 0, "max": 3, "on": ["unit"], "start": 0 }]
```

A tag carrying a number is how "rank" becomes something `>=`, `lowest:` and `highest:` can
read. Without it every comparison is a chain of `tagged:` questions.

---

## Drawing and decks

### Draw a card.

```json
"action": ["draw_from:mine.deck:mine.hand:1"]
```

### Draw as many cards as you have Doom.

```json
"action": ["draw_from:mine.deck:mine.hand:sum:doom@mine.player"]
```

### When the draw pile runs out, shuffle the discard back in.

```json
"zones": [{ "key": "deck", "layout": "stack", "visibility": "secret", "refill_from": "discard" }]
```

Asked for on demand — mid-draw, mid-card, wherever it actually runs out — not fired when the
pile empties. A rule that clears the pile on purpose is left alone.

### Shuffle your deck.

```json
"action": ["shuffle:mine.deck"]
```

### Reveal the top card of the fate deck.

```json
"action": ["reveal_top:fate"]
```

Renders as a full-text page over the board and then runs that card's own `play.action`.

### Only the top card of this pile exists to the rules.

```json
"zones": [{ "key": "deck", "reach": "top" }]
```

A `stack` is `top` unless it says otherwise; `all` is the other value. This is what a deck being
a deck consists of — everything under the top card is out of reach of every scope.

### Put it on the bottom of your deck.

```json
"action": ["move:target:mine.deck:1:bottom"]
```

The count comes before the end. `top` is the default.

### Deal four cards to each player at the start of the game.

```json
"phases": [{ "key": "setup", "type": "automatic",
             "actions": ["each_seat:draw_from:mine.deck:mine.hand:4"],
             "next": [{ "then": "play" }] }]
```

### Search your deck for a card and take it.

```json
"play": { "action": ["show:mine.deck:optional"] },
"chosen": { "action": ["move:target:mine.hand"] }
```

`show:` borrows the **real** cards, which is what lets one be taken. `options:` deals copies,
which is right for a menu and wrong for a hand. Everything not taken goes back where it came
from.

Trap: **one offer at a time.** A second ask while the first is still open is written down and
run when the first is answered — and its scope is read again *then*, against the board the first
answer left.

---

## Cards moving

### Put this back to its printed numbers.

```json
"action": ["reset:self", "move_to:mine.army"]
```

A hero coming back out of the command zone comes back at what it is printed with. Every
stat the template declares, or `reset:self:hp` for one of them. A stat's own `start` folds
into `card_stats` at load, so "every fighter begins at nought" restores through here without
the card saying it again. The ceiling comes back too, so a card whose maximum was raised
comes back down to its printed one — and a buff is untouched, because that belongs to a tag
and leaves when the tag does.

### Put this into play.

```json
"action": ["move_to:board"]
```

Bare `move_to` sends the card to whatever its own tag names as its `zone` — "where this lives".

### Return their unit to their hand.

```json
"target": { "type": "card", "count": 1, "owner": "enemy", "zones": ["army", "patrol"] },
"action": ["move:target:enemy.hand"]
```

Trap: **there is no owner-relative destination.** `mine.hand` is the *acting seat's* hand, not
the target's owner's, so a bounce names the side it works on and the target spec pins the same
`owner`. A card that may bounce either side is two rules.

### Discard the target.

```json
"action": ["move:target:mine.discard"]
```

Same ownership rule as the bounce: `enemy.discard` when the card is theirs.

### Destroy the target.

```json
"zones": [{ "key": "discard", "status": "grave", "copies": "per_seat" }],
"action": ["destroy:target"]
```

The card **dies**: it moves into its grave, its `leaves` fires, whatever watches for the
announcement answers, and it is still lying there to be counted or raised. The seat is the
*dying card's*, so one line kills either side's unit and files it correctly.

### Destroy this.

```json
"action": ["destroy:self"]
```

### A dead hero goes somewhere other than the discard.

```json
"tags": { "hero": { "grave": "command" } }
```

Which grave is asked of five places, narrowest first: the card's own `grave`, the tags it
wears, the zone it is standing in, its seat's `status: "grave"` zone, and a shared one. Two
tags naming different graves settle nothing, and the question passes to the wider ones.

### Everything that dies in the arena is swept into the pit.

```json
"zones": [{ "key": "arena", "status": "board", "grave": "pit" }]
```

### Remove a token from the game entirely.

```json
"action": ["purge:each.anyone.token"]
```

`purge` is the other verb: the card lands in no zone, **`leaves` does not fire**, and its stats
go with it. A component whose kind a `status: "supply"` zone stocks goes back in that box and
the stock ticks up. Reach for it only when nobody may ask — a token, a swept husk. A unit
killed by an effect and a unit killed by damage must take the same road, or only one of them
sets off the death triggers.

### This card can never be trashed, by anything.

```json
"target": { "type": "card", "zones": ["hand"], "tags": ["trashable"] }
```

```json
"chosen": { "where": ["not_tagged:puzzle@target"], "action": ["purge:target"] }
```

**The rule lives on the asker, not on the card**, because the two ways of asking are gated in
different places: a `target` spec narrows its pool by `tags`, and an offer gates its pick with
`chosen.where`. A tag nothing reads protects nothing — write the word on the cards, then say it
at every site that removes one.

Say it positively where you can (`trashable` on the few kinds that may go) and negatively where
the exceptions are fewer (`not_tagged:` on the one kind that may not); Puzzle Strike does both,
for chips and for Puzzle chips. If the offer should not even show the card, narrow the **scope**
instead — `show:mine.hand.trashable` — and keep `where` for what it alone can ask: a fact about
the *player* rather than about the card.

### Destroy the four lowest-tech patrollers.

```json
"action": ["purge:lowest:tech_level.enemy.patrol:4"]
```

`lowest:`/`highest:` say what **order** a pool is in and never how many of it is taken; the
count is the consumer's own. Ties keep entity order, so a seeded replay is a replay. A card
carrying no such number reads nought and sorts to the front of `lowest`.

### Send everything in the duel back where it came from.

```json
"action": ["move:duel:origin"]
```

`origin` is a different place per card — where each was immediately before its last move. It is
a destination and never a source. On a grid it is the square, not the zone.

### Move three cards from the bank into your bag.

```json
"action": ["take:bank.gem_1:mine.bag:3"]
```

`take` is `move` for a source that **counts** rather than keeps — a supply pile with a number
on it. The card arrives remembering the box it came from.

### A discard pile anyone may take from.

```json
"zones": [{ "key": "discard", "receive": { "action": ["set_owner:target:none"] } }]
```

Said once by the zone rather than by every card that might land in it.

### Close the gap when a card leaves the row.

```json
"action": ["compact:row.artifact:leftward"]
```

The furthest card moves first, so nothing behind overtakes something in front.

### Deal cards until the row is full.

```json
"action": ["draw_from:market_deck:row:99"]
```

A count is a **maximum, not a promise**: the deal stops when the count runs out, the source
empties, or the destination has no room, and none of the three is an error. There is no "until
full" word because the overshooting number reads the same. Free cells are taken by index, so a
hole in the middle is filled before the end.

### Refill the one cell that was just emptied.

```json
"action": ["compact:row.artifact:rightward", "draw_from:artifact_deck:row:1:a1"]
```

A cell holds one card, so a deal aimed at an occupied cell does nothing at all — which is how a
market row refills without any condition asking what was bought.

### Put two skeletons into your army.

```json
"action": ["create:mine.army:skeleton:2"]
```

`create` **makes** cards out of nothing, which is what a token is: two more, never up to two.

### Take control of the target.

```json
"action": ["set_owner:target:mine"]
```

### Turn this pawn into a queen.

```json
"action": ["transform:target:queen"]
```

### Stand this card on top of the one it was played at.

```json
"play": { "target": { "type": "card", "count": 1, "zones": ["sites"] },
          "action": ["attach_to_target"] }
```

Then read across it: `count:digger@attached_to.self` is what is standing on me,
`count:guardian@attached_to.host_of.self` is what else is standing on my host. A rider keeps no
square of its own and draws on its host.

---

## Playing a card, and what it costs

### This costs 3 gold to play.

```json
"play": { "cost": { "gold@mine.player": 3 }, "action": ["move_to:board"] }
```

### This costs whatever is printed on it.

```json
"play": { "cost": { "gold@mine.player": "price@self" } }
```

A cost value may be any subject, so a price on the card is read off the card.

### Exhaust this to use it.

```json
"abilities": [{ "key": "tap", "text": "Tap", "cost": { "exhaust": 1 },
                "action": ["stat_gain:gold@mine.player:1"] }]
```

Readiness is the engine's own state with its own two words — never a tag and never a stat. Cards
ready at the round boundary.

### Sacrifice a unit to play this.

```json
"play": { "cost": { "sacrifice:unit": 1 } }
```

The player picks which unit — a sacrifice is always theirs to choose, and needs no word to say so. A
tag names a kind and never a side, so the pool refuses anything with a foreign owner: you may spend
your own and whatever stands on a board nobody owns, never theirs.

### Sacrifice this to use its ability.

```json
"abilities": [{ "cost": { "sacrifice:self": 1 }, "action": ["stat_damage:hp@target:2"] }]
```

`self` is the asking card, the one thing a tag cannot name. Written as a private tag the card wears
alone, a second copy on the board kills the wrong one.

### Boost 3: pay 3 more and trash one of their workers.

```json
"play":  { "cost": { "gold@mine.player": "price@self" },
           "action": ["move_to", "options:mr_boost:optional"] },
"cards": [{ "key": "mr_boost", "text": "Boost 3", "tags": ["immutable"],
            "tooltip": "Pay 3 more and trash one of their workers.",
            "play": { "cost": { "gold@mine.player": 3 },
                      "action": ["stat_damage:workers@opponent:1", "purge:enemy.workers:1"] } }]
```

**The extra is a card.** A cost is one map settled in full, so it cannot hold a part you may decline
— but an offer can, and the offered card carries a cost of its own. `options:` deals it, choosing it
plays it, and `flow.can_play` gates it like anything else: unaffordable, it is dimmed and cannot be
taken. `optional` is what puts the No button there. Nothing new is needed for a choice between
several boosts either — Murkwood Allies offers three, of which one costs four more.

### Sacrifice a unit. If you do, draw a card.

```json
"play":  { "cost": { "gold@mine.player": 2 }, "action": ["options:rite_give:optional"],
           "spent": "mine.discard" },
"cards": [{ "key": "rite_give", "text": "Sacrifice a unit", "tags": ["immutable"],
            "play": { "cost": { "sacrifice:unit": 1 },
                      "action": ["draw_from:mine.deck:mine.hand:1"] } }]
```

The same shape, and the reason to reach for it: **"if you do" is not a cost.** Written as one the
card stops being playable when the board has nothing to give, where the rules cast the spell and
fizzle only the consequence. As an offer the spell always casts, and the giving is a question asked
afterwards that may have no answer. `optional` is not decoration here — a lone unpayable entry with
no way out is an offer that never closes.

A rules card opening an offer of its own is fine: `show:` runs the **asker's** `chosen`, and the
asker is the card standing in the offer, not the spell that dealt it.

### Pay 5 gold out of whichever lands you choose.

```json
"play": { "cost": { "gold@select.mine.land": 5 } }
```

Without `select` the five comes off the lands in a fixed order and nobody is asked. With it they
light up and you point at them, one click per coin. A pool with one way to settle the price asks
nothing either way.

### Pay this with red or with a wild, as you like.

```json
"stats": [{ "key": "wild", "pays_for": ["red"] }],
"play":  { "cost": { "red@select.mine.player": 1 } }
```

`select` also picks between the pools a `pays_for` offers, and is what lets two substitution pools
overlap without nesting: the greedy that would settle such a price is what the checker refuses, and
a price the player settles has no greedy to get wrong.

### It costs an action and two gold.

```json
"play": { "cost": { "main@mine.player": 1, "gold@mine.player": 2 } }
```

A cost is one map of what is owed. Every entry must be payable or the card is not playable.

### Gold may be spent as any colour of action.

```json
"stats": [{ "key": "gold", "pays_for": ["act_red", "act_blue"] }]
```

The fact lives on the **pool that settles the debt**, not on the card that owes it — so a card's
cost never has to know which currencies exist.

### You may only play this if you control a Farm.

```json
"play": { "needs": ["count@mine.farm >= 1"] }
```

### You may only play this during your main phase.

```json
"play": { "phases": ["main"] }
```

### Every Spell does this when played.

```json
"tags": { "spell": { "play": { "action": ["stat_gain:power@mine.player:1"] } } }
```

One `play` however many cards carry the tag. A card writing its own takes none of the tag's.

---

## Abilities

### This card has a clickable ability.

```json
"abilities": [{ "key": "poke", "text": "Poke", "action": ["damage:hp@target:1"],
                "target": { "type": "card", "count": 1, "owner": "enemy" } }]
```

### This card can do two different things.

```json
"abilities": [{ "key": "a", "text": "Draw", "action": ["draw_from:mine.deck:mine.hand:1"] },
              { "key": "b", "text": "Gold", "action": ["stat_gain:gold:1"] }]
```

Two abilities open a chooser. So does a card with one ability and a `play`.

### While this is in the shop, its own ability is all it offers.

```json
"abilities": [{ "key": "buy", "text": "Buy it", "merge": "this",
                "cost": { "gold@mine.player": 3 }, "action": ["move:self:mine.hand"] }]
```

`merge`: `both` (default, added to whatever else the card does), `this` (mine alone), `other`
(mine only when the card offers nothing else). The word goes on the **ability**, never on the
zone that granted it.

### The ability only happens if something is true.

```json
"abilities": [{ "key": "spill", "needs": ["overkill >= 1"], "compute": ["overkill"] }]
```

`needs` is whether it **happens**; `cost` and `phases` are whether a player **may**.

### A deck you draw from by clicking the deck.

```json
"zones": [{ "key": "deck", "abilities": [
  { "key": "draw", "text": "Draw", "phases": ["main"], "cost": { "main@mine.player": 1 },
    "action": ["draw_from:mine.deck:mine.hand:1"] }] }]
```

The box answers, rather than the card on top of it becoming clickable. No `target` and no
`moves` — there is no arrow to draw from a deck.

### Do what that card does, without playing it.

```json
"action": ["copy:target:play"]
```

`copy:<scope>:activate` runs its ability list instead.

### Exhaust every enemy unit.

```json
"action": ["exhaust:each.enemy.unit"]
```

### Ready this.

```json
"action": ["ready:self"]
```

### Only while this is ready. / Only while it is spent.

```json
"needs": ["ready@self"]
```

Written bare, with no comparison and no argument — a card is spent or it is not, never spent
twice. `exhausted@<scope>` is its exact complement. A game that wants spending to *mean*
something says so itself:

```json
"computed_tags": { "spent": { "needs": ["exhausted@self"] } },
"tags": { "spent": { "buffs": { "atk": -1 } } }
```

---

## Targeting

### Target a unit.

```json
"target": { "type": "card", "tags": ["unit"], "count": 1 }
```

### Target up to two units.

```json
"target": { "type": "card", "tags": ["unit"], "min": 0, "max": 2 }
```

`count` fixes both bounds; `min`/`max` is a range; `spread` is points rather than cards.

### Target one of *their* units.

```json
"target": { "type": "card", "tags": ["unit"], "count": 1, "owner": "enemy" }
```

`owner` is `mine`, `enemy` or `anyone`.

### Target a card lying in one of these zones.

```json
"target": { "type": "card", "count": 1, "zones": ["patrol", "army"] }
```

### Target a card lying anywhere on the board.

```json
"zones": [{ "key": "patrol", "tags": ["in_play"] }, { "key": "army", "tags": ["in_play"] }],
"target": { "type": "card", "count": 1, "zones": ["in_play"] }
```

A `zones` entry names a zone key or a word the zones themselves wear, so the set a
spell may land on is stated once instead of in every block that casts one — and a
new board zone joins it by wearing the word rather than by being found in all of them.

### My ICEs, wherever I am keeping them.

```json
"zones": [{ "key": "hand", "tags": ["held"] }, { "key": "discard", "tags": ["held"] }],
"action": ["move:random.mine.held.ice:ice_pile"]
```

The left half of a scope is a zone key or a word several zones wear. "Hand or discard
and not the deck" is a property of the places, so it is said on them — the alternative
is a tag handed out by each zone, a union to or them, and an `and` to put the real
question back.

### Target an empty square.

```json
"target": { "type": "slot", "count": 1, "zones": ["battle"], "fill": "empty" }
```

### Target a unit whose cost is 3 or less.

```json
"target": { "type": "card", "count": 1, "where": ["price@target <= 3"] }
```

`where` is asked **of each candidate** with that candidate as `@target`. `needs` is asked once,
before anything is offered.

### Target something other than this card.

```json
"target": { "type": "card", "count": 1, "where": ["not_self"] }
```

### This is an attack; that is a spell.

```json
"verbs": [{ "key": "attack", "does": "target" }, { "key": "cast", "does": "target" }],
"target": { "verb": "cast", "type": "card", "count": 1, "owner": "enemy" }
```

Nothing performs an aiming verb. Declaring it is what lets a *target* answer it.

### May I attack anything, or must I go through a patroller first?

```json
"abilities": [
  { "key": "strike_lead", "target": { "verb": "attack", "type": "card", "count": 1,
      "owner": "enemy", "zones": ["patrol"], "where": ["slot@target == 1"] } },
  { "key": "strike_free", "needs": ["aims:strike_lead == 0"],
    "target": { "verb": "attack", "type": "card", "count": 1, "owner": "enemy" } }]
```

`aims:<ability>` is how many cards one of **this card's own** abilities could point at right
now. It takes no `@`. It counts candidates — zones, owner, `where`, and every ward they wear —
and never the ability's own `needs`. It exists so a rule is not written twice: a new `where`
clause or a new ward feeds the permission rule the moment it is written.

---

## Being targeted

### This cannot be targeted by spells.

```json
"receive": { "needs": ["not_verb:cast"] }
```

`verb:`/`not_verb:` ask what kind of aim this is, which is not a question about the aimer — the
hero that casts is the hero that attacks. An aim a game never named answers no to `verb:` and
yes to `not_verb:`.

### This cannot be attacked while you control a bigger unit.

```json
"receive": { "needs": ["max:atk@mine.army <= atk@self"] }
```

`receive.needs` is a ward: asked of the candidate as `@self`, with the aiming card as `@target`.
Several conditions are ANDed; several wards are several gates.

### Tech-0 units cannot attack this.

```json
"stats": [{ "key": "bars_t0", "on": ["unit"], "start": 0 }],
"receive": { "needs": ["bars_t0@target <= tech_level@self"] }
```

Trap: splitting a comparison into two conditions makes it an **and**, which is a different rule.
`["bars_t0@target >= 1", "tech_level@self >= 1"]` stops a tech-0 unit attacking *anything*.

### This is disabled when a spell or ability aims at it.

```json
"receive": { "action": ["stat_set:ready@self:0"] }
```

`receive`'s other half. `needs` is whether the aim may be made; `action` is what this card does
about the aim that was — asked the same way round, `@self` the card aimed at and `@target` the
card aiming. It runs once per chosen target, after the cost is settled and **before** the aiming
card acts, so what it changes is what the aim then lands on. Add `when` to answer only some aims;
with none, every aim is answered.

Only where a player *pointed*. A scope that names the card is not an aim, so `destroy:each.unit`
answers nothing — which is why a ward stops a bolt and not a board wipe, and why the same blind
spot is the right one here.

### Opponents without a detector cannot aim at this; your own spells can.

```json
"tags": { "hidden": { "receive": {
  "whose": "enemy", "needs": ["count:detector@mine.addon >= 1"] } } }
```

`whose` is the side the block is addressed to, in the word a reaction already uses: `"enemy"`
answers an opponent's aim and nobody else's, `"mine"` its own side's, `"anyone"` is the default.
Only write it for a ward that is one-sided in print — Codex's Invisible and Mindparry Monk are,
its Untargetable and Illusion are not.

It gates the whole block, `when` and `action` with `needs`, so a ward that refuses only an
opponent also fires only on one.

Trap: this cannot be a condition. `needs` is an **and**, and the rule is a detector *or* the
aimer being its owner — so written inside `needs` it comes out as "your own spells need a
detector too", which is a different card.

### Illusions die when a spell or an ability aims at them.

```json
"tags": { "illusion": { "receive": { "when": ["verb:cast"], "action": ["destroy:self"] } } }
```

A keyword rather than a card, so the eight cards that have it carry the word and not the rule.

`when` is the gate, and it is **not** `needs`: `needs` settles whether the aim may be made and
`when` whether the card answers the aim that was. An Illusion wants opposite answers from them —
targetable by everything, killed only by a spell — so one list could not have said both. The
aim's own verb is in scope, which is why being attacked is not being aimed at.

The aiming spell then lands on nothing: a target whose zone **status** changed since it was
pointed at drops out of `@target`, so a bounce does not haul the corpse out of the discard.
Status and not zone, deliberately — a unit walking army → duel and home again is still what the
bolt was thrown at, because both are the board.

### This card may only be played onto a matching pile.

```json
"zones": [{ "key": "red_pile",
            "receive": { "needs": ["value@target >= max:value@mine.red"] } }]
```

The zone answers for itself, exactly as a card does.

---

## Triggers

### When this dies, deal 1 to their hero.

```json
"leaves": { "into": "discard", "action": ["damage:hp@enemy.hero:1"] }
```

`into` names where it landed, and that is what tells one kind of leaving from another. Leave
`from` out and it means leaving **play**; a card walking between two board zones fires nothing.

### When you discard this from your hand, gain 1 power.

```json
"leaves": { "from": "hand", "into": "discard", "action": ["stat_gain:power@mine.player:1"] }
```

### When this dies on somebody else's turn.

```json
"leaves": { "into": "discard", "needs": ["count:player@enemy.owner_of >= 1"],
            "action": ["damage:integrity@mine.base:1"] }
```

`needs` is for what `from` and `into` cannot say — they are both places. Asked after the move,
so it reads the world the action will run in.

### Every unit's death is announceable.

```json
"tags": { "unit": { "leaves": { "into": "discard", "action": ["emit:died"] } } },
"reactions": [{ "to": "died", "whose": "anyone", "forced": "mandatory", "in": "board",
                "action": ["damage:hp@enemy.hero:1"] }]
```

One line makes the whole class announce itself, and no unit knows it is being watched.

### At the start of every round, gain 1 gold.

```json
"round": { "action": ["stat_gain:gold:1"] }
```

### When a card lands here, do this.

```json
"zones": [{ "key": "shrine", "receive": { "action": ["stat_gain:faith@mine.player:1"] } }]
```

The zone is `@self`, the newcomer is `@target`. Fires on **every** landing, which is what a
discard stamping its owner wants — and not on a `create`, which conjures a card rather than
sending one.

### When a *unit* lands here, do this.

```json
"zones": [{ "key": "shrine", "receive": { "when": ["tagged:unit@target"],
                                          "action": ["stat_gain:faith@mine.player:1"] } }]
```

`when` gates the action; `needs` beside it gates the landing itself. Say it in `needs` and the
card cannot be sent here at all, which is a different rule.

### When a card comes into play here.

```json
"zones": [{ "key": "army", "arrives": { "action": ["emit:arrived"] } }]
```

The arrival counterpart to a card's `leaves`, keeping the same rule at the other end: `leaves`
fires on the way *out of play* and a unit walking between two board zones fires nothing, so
this fires on the way *in* and a unit walking back fires nothing either. Codex's combat is a
move out to the duel zone and home again — an arrival trigger that answered that would fire on
every attack. A card lent to a question comes home having arrived nowhere, because the zone it
counts as coming from is the one it was **borrowed from**. A created token arrives too.

The **arriving card** is `@self`, where `receive` is asked with the zone: `receive` is the
place doing something about what landed in it, and this is a card's arrival being announced.
Which is what lets `emit` name the newcomer and `others` leave it out of a pool.

### When another unit arrives, put a rune on this.

```json
"zones": [{ "key": "army", "arrives": { "action": ["emit:arrived"] } }],
"cards": [{ "key": "blooming_ancient", "tags": ["unit", "ancient"],
  "reactions": [{ "to": "arrived", "whose": "mine", "forced": "mandatory", "in": "board",
                  "needs": ["not_self@event", "tagged:unit@event"],
                  "action": ["stat_gain:plus@self:1"] }] }]
```

The rule lives on the card that prints it. `@self` is the watcher, `@event` is the card that
just arrived, and *"another"* is `not_self@event`. A `mandatory` reaction is a triggered
ability and not a question, so nobody is asked — and it fires once per watcher, which is what
*"every Blooming Ancient you have"* means.

### Do this to every card in a column, in order.

```json
"action": ["activate_zone:rules:by_column:upkeep"]
```

A column of immutable rules cards, each with an ability of that key, walked one at a time. The
idiom for upkeep, arrival and death rules that belong to the *game* rather than to a card.

---

## Reactions

### When they attack, you may pay 2 to answer.

```json
"reactions": [{ "to": "attack", "whose": "enemy", "in": "hand",
                "cost": { "mana@mine.player": 2 },
                "action": ["damage:hp@event:2"] }]
```

`to` is the announcement, `whose` says whose action it answers (`mine`, `enemy`, `anyone`),
`from` is where the answering card must be lying, and `@event` is the card it is about.

### A card that lets you use your Ultimate without paying for it.

```json
"reactions": [{ "to": "resolving", "whose": "mine", "in": "wizard",
                "needs": ["free_use@mine.player <= 0"],
                "cost": { "mana@mine.player": 6 }, "action": ["damage:hp@enemy.player:2"] },
              { "to": "resolving", "whose": "mine", "in": "wizard",
                "cost": { "free_use@mine.player": 1 }, "action": ["damage:hp@enemy.player:2"] }]
```

Nothing waives a cost, and nothing needs to: a cost is a map of what is owed, and owing it
differently is answering the same announcement twice. The card that grants the free use hands
out one point of a stat and the second reaction spends it.

**Keep one of the two payable at a time.** A bare click means the single answer a card offers,
so the paid one steps aside with a `needs` rather than standing beside the free one — a card
offering two answers is a card no click can reach.

### Announce that this card was played.

```json
"emits": { "play": "attack" }
```

`{ "activate": "<name>" }` is the same for an ability. `emit:<name>` in an action list announces
something that is not a card being played at all.

### They must answer this — it is not optional.

```json
"reactions": [{ "to": "crash", "whose": "enemy", "forced": "mandatory", "in": "mine.bag" }]
```

A mandatory reaction is how you ask somebody *else* a question.

### Wherever this card ends up, it lands there.

```json
"reactions": [{ "to": "buy", "spent": "mine.discard" }]
```

---

## Asking a question

### Choose one: gain 2 gold, or draw a card.

```json
"play": { "action": ["options:opt_gold,opt_draw"] }
```

Each named card is dealt into the offer with **the asking card as its `target`** and the asker's
owner, so the chosen card can act back on whoever asked:

```json
{ "key": "opt_gold", "text": "Gain 2", "play": { "action": ["stat_gain:gold:2"] } }
```

### One of the choices is only there if you own a Farm.

```json
{ "key": "opt_raid", "text": "Raid", "tags": ["immutable"],
  "play": { "needs": ["count:farm@mine.army >= 1"],
            "action": ["stat_gain:gold@mine.player:3"] } }
```

A dealt entry's `needs` is read as it is offered, the same way its `cost` is (*Boost 3*, above): an
entry you may not take comes up and refuses the click. Put the gate here rather than in an ability
the entry runs — an ability that declines to fire has already spent the player's choice. It is not
`chosen.where`, which answers the other question: what may be taken out of a `show:`, where the
cards are somebody else's and carry nothing of yours.

### Return a card from your discard, **or** draw a card.

```json
"action": ["options:opt_recall,opt_draw:optional"]
```

```json
{ "key": "opt_recall", "text": "Take a card back", "tags": ["immutable"],
  "play": { "needs": ["count:card@mine.discard >= 1"],
            "action": ["show:mine.discard:optional"] },
  "chosen": { "action": ["move:target:mine.hand"] } },
{ "key": "opt_draw", "text": "Draw instead", "tags": ["immutable"],
  "play": { "action": ["draw_from:mine.deck:mine.hand:1"] } }
```

**An "or" is an offer of two, and the two are cards.** Each entry carries what its branch does,
and its `needs` says whether that branch is on the table at all — *return a card* is simply
refused when the discard is empty, so the player is never offered a branch with nothing behind it.

**A branch may ask a question of its own.** The second offer belongs to the *entry*, so the
entry's `chosen` answers it — the asker is the card standing in the offer, not the card that
dealt it. One caveat: nothing may follow that question inside the same branch, because an action
list has no cursor. Write *"resolve it, then bury it"* as the move and then the resolve.

### Put a marker on one of these eight spaces, and it stays there.

```json
"action": ["show:rules.jspace:optional"],
"chosen": { "where": ["researched@target <= 0", "tokens@mine.player <= 5"],
            "action": ["stat_set:researched@target:1", "stat_gain:tokens@mine.player:1"] }
```

**The board is already cards**, so lend the real ones rather than dealing copies of them: the
player picks the space itself and the mark stays on it. A 0-or-1 stat declared on the card is the
marker, and `where` asks both halves of *"an empty space, while you have markers left"* — one
about the card, one about the player, which is the pair only `where` can ask together.

**Do not spell this as one counter.** `marks >= n` per space reads as the same rule and is not:
one number then answers both "how many" and "which of them", so the spaces can never disagree
with their own order, and any space past the counter's ceiling can never light at all.

### Choose one of the cards in that row.

```json
"action": ["options:upgrades"]
```

A zone instead of a list is how a variable set of choices is written.

### You may decline.

```json
"action": ["options:tr_tempo,tr_money:optional"]
```

Puts a **No choice** button under the offer. An offer the *rules* opened cannot otherwise be
walked away from; one the player opened by clicking a card always can.

### Look at their hand and take one card.

```json
"play": { "action": ["show:enemy.hand:optional"] },
"chosen": { "action": ["move:target:mine.discard"] }
```

### Only some of the revealed cards may be taken.

```json
"chosen": { "where": ["tier_req@target <= 2"], "action": ["move:target:mine.hand"] }
```

### Ask every player, going round from whoever is up.

```json
"action": ["each_seat:activate_zone:rules:by_column:topup"]
```

### Ask a question before the game starts.

```json
"phases": [{ "key": "pick_1", "type": "player_input", "seat": "next",
             "label": "Choose your character",
             "actions": ["options:char_grave,char_jaina"],
             "ends_when": "picked@mine.player >= 1", "next": [{ "then": "pick_2" }] }]
```

Trap: choosing out of an offer is deliberately **not a play**, so `plays >= 1` will not end this
phase. Have the chosen card set a flag.

---

## Turns and phases

### A phase where the player may act freely.

```json
{ "key": "main", "type": "player_input", "zone": "hand", "next": [{ "then": "end" }] }
```

Naming `zone` also bounds what may be played: only cards lying there.

### One card a turn.

```json
{ "key": "main", "type": "player_input", "ends_when": "plays >= 1" }
```

`plays` is engine-kept and reset when the turn begins. It cannot tell one play from another —
if some of what a player does should not end the turn, count the thing that should:
`"ends_when": "count:play_card@trick >= 1"`.

### The turn keeps going until the player is done.

```json
"next": [{ "when": "done@mine.player >= 1", "then": "check" },
         { "then": "act", "seat": "same" }]
```

`same` keeps the player who is up; `next` passes it along. The seat is a property of the
**route**, because two games loop for opposite reasons.

### Reset a counter when the turn begins, not on every loop round.

```json
{ "key": "act", "type": "player_input", "seat": "next",
  "on_enter": ["stat_set:takes@each.anyone.player:0"],
  "actions": ["activate_zone:t1_row"] }
```

`actions` run on every entry including a loop; `on_enter` runs only when the **turn** begins
here.

### Each player takes the same three steps, highest initiative first.

```json
{ "key": "turn", "type": "turn", "seat": "each", "order": "highest:initiative",
  "phases": ["upkeep", "main", "cleanup"] }
```

### Go somewhere else if a condition holds.

```json
"next": [{ "when": "count:king@enemy.reach >= 1", "then": "check" },
         { "then": "black_move" }]
```

First matching entry wins; an entry with no condition always matches.

### This is where the round ends.

```json
"next": [{ "then": "upkeep", "ends_round": true }]
```

The only thing that ticks the round: counter +1, exhausted cards ready, `round.action` runs.

### Deal a fresh hand each time this phase starts.

```json
{ "key": "draft", "type": "player_input", "deck": "market", "draw": 3, "zone": "offer" }
```

### Give every player a way out of a forced choice.

```json
{ "key": "draft", "pass_card": "pass" }
```

### Sweep the unplayed cards when the phase ends.

```json
{ "key": "draft", "tags": ["discard_hand"] }
```

### Dim the screen and make them pick one of these.

```json
{ "key": "promote", "type": "overlay", "zone": "options" }
```

An overlay is resolved by **playing** one of the cards in it; cost, needs and targeting are all
skipped, because a choice is not a purchase.

### End the game when someone's life hits zero.

```json
"end_conditions": [{ "when": "life@anyone.player <= 0", "then": "game_over" }]
```

---

## Boards and pieces

### A rook moves any distance orthogonally.

```json
"patterns": { "line_ortho": { "vectors": [[1,0],[-1,0],[0,1],[0,-1]], "class": ["ray"] } },
"cards": [{ "key": "rook", "moves": ["line_ortho"] }]
```

`class` is `step` (one cell), `ray` (until blocked), or `ray:<n>` (at most n).

### A pawn steps forward onto an empty square and takes diagonally.

```json
"moves": [{ "patterns": ["pawn_step"], "fill": "empty" },
          { "patterns": ["pawn_run"], "fill": "empty", "needs": ["rank@self == 2"] },
          { "patterns": ["pawn_take"], "fill": "enemy" }]
```

`fill` is what may be standing on the destination: `empty`, `enemy`, `any`. **The engine has no
idea what an attack is** — the line between moving and threatening is drawn here.

### En passant.

```json
"moves": [{ "patterns": ["pawn_take"], "fill": "empty",
            "where": ["tagged:last_acted@behind", "tagged:pawn@behind", "rank@behind == 4"] }]
```

`@behind`, `@across` and `@beside` point at the other cards from the square being considered.
`last_acted` is the card a player most recently played or activated.

### Is my king standing where they could move?

```json
"next": [{ "when": "count:king@enemy.reach >= 1", "then": "check" }]
```

`@<owner>.reach` is every square that side could move onto right now, answered as what stands
there. Computed on demand from the `moves` each piece declares. A move rule's own `needs` may
not usefully ask for it.

### Put this on a particular square.

```json
"action": ["place:self:one_right"]
```

### A grid of six cells.

```json
{ "key": "battle", "layout": "grid", "grid": [6, 1] }
```

A grid is `status: "board"` without saying so. Cards entering without slot targeting take the
first free cell; a full board refuses arrivals quietly.

---

## Seats and sides

### Two players.

```json
"players": [{ "card": "north" }, { "card": "south" }]
```

The player *is* a card, so everything that works on a card works on a seat.

### One hand each.

```json
{ "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner" }
```

`pos` then takes one rect per seat.

### Whose is it?

```json
"needs": ["count:player@enemy.owner_of.target >= 1"]
```

### The seat names itself.

```json
"cards": [{ "key": "north", "text": "{name}" }],
"action": ["set_name:mine.player:text@self"]
```

### Hand the turn to a particular player.

```json
"action": ["set_active_seat:has_init"]
```

---

## Supplies and stock

### A bank of gems the engine counts.

```json
{ "key": "bank", "status": "supply", "contents": ["gem_1:20"] }
```

A supply keeps a number rather than a pile of cards. `take:` draws from it, a destroyed
component goes home to the box that stocks its kind, and `stock@supply.pile_white` reads it.

---

## Look and feel

### Card art.

```json
{ "key": "knight", "asset": "knight.png" }
```

A filename in `games/assets/`, an `http(s)` URL, or a shape spec.

### Card text that reads the board.

```json
{ "key": "tally", "text": "Gold: {gold}" }
```

### A zone whose label says whose turn it is.

```json
{ "key": "banner", "layout": "grid", "grid": [1,1], "label": "{active}" }
```

### Nobody may read this pile.

```json
{ "key": "deck", "visibility": "secret" }
```

`visibility` is about reading and nothing else. A card in play may be unreadable and a card
nobody can touch may be plain to see — what may be *done* with it is `use`.

### A box you use rather than reach into.

```json
{ "key": "trash", "use": "none" }
```

### Two zones that are never both open, on one rect.

```json
{ "key": "battle", "layout": "grid", "grid": [1,1], "pos": [0.4, 0.5, 0.6, 0.8] },
{ "key": "commit", "layout": "grid", "grid": [1,1], "visibility": "owner", "pos": "battle" }
```

The one drawn is the first holding a card, host first. Every overlap nobody declared is still an
error.

### Rules pages and fate decks nobody sees.

```json
{ "key": "rules", "layout": "stack", "display": "offscreen" }
```

Not the same as `secret`, which is a zone you can see and cannot read.

---

## Known gaps

Effects with **no spelling yet**, so nobody re-derives one. Each has live customers in
`game/games/codex.json`, and each is written up in `todo.md`:

- **Swift strike** — a blow struck before the exchange. 6 cards.
- **A death replaced by something else** — a card that returns, or leaves a token, instead of
  dying. 5 cards. Hand-written three times as a `rules_death` column.
- **Transform and back** — becoming another card and returning. 5 cards.
- **A buff measured by a number the card carries** — `"atk": "time@self"`. 3 cards; a counter's
  fixed multiplier is the near miss.
- **An aim narrowed after it is made** — a flagbearer that redirects what was already pointed
  somewhere else. 3 cards.
- **"This costs nothing"** — a cost of zero is not the same as no cost. 4 cards.
