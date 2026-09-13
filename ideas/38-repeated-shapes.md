# 38 — The shapes that repeat

A survey of the three biggest games in the box — Codex (425 cards, 279
abilities), Puzzle Strike (195 / 30) and Spellstorm (150 / 234) — for structure
that appears often enough to be a spelling rather than a card. Counted
mechanically: action n-grams, ability shapes with the numbers blanked, target
blocks compared whole, and `mine`/`enemy` mirror pairs.

Two kinds of finding, kept apart because they cost different things. The first
kind is a sentence the format already holds and the file does not use — content
work, no engine change, and the only real question is whether the validator
should have said so. The second kind is a word that is missing.

## Already sayable

- ~~**`count:<tag>@self >= 1` — 79 times in Codex**~~ — **done.** All 79
  rewritten to `tagged:`/`not_tagged:`, and `count:` always reads a tag where
  `card:` reads a key, so the two words that are both a tag and a card key in
  Codex (`skeleton`, `ninja`) mean exactly what they meant. The validator says
  so now, which is the half that stops it recurring — and it reports the shapes
  above nought separately, since a pool of one can never reach two and
  `count:unit@self >= 2` is a condition that cannot hold rather than one that
  reads oddly. No rewrite is offered for that one: the wrong number and the
  wrong scope look identical from here.

- **17 mirrored `mine`/`theirs` ability pairs in Codex** — 34 of its 279
  abilities, all on the rules cards: `r_scav`, `r_techie`, `r_heroes`,
  `r_lives`, `r_insured`, `r_gang`, `r_drakk`, `r_tech_rubble`,
  `r_addon_rubble`. AUTHORING already names this shape as the format fighting
  back, and the answer it names is `each_seat:`, which Spellstorm uses on
  exactly this kind of walk (`each_seat:activate_zone:weather_now:by_column:wx`).
  `each_seat:activate_zone:rules_death` deletes the `theirs` half of all 17.
  What changes is the order — one seat's whole rules, then the other's, rather
  than interleaved — and for these rules that is not a difference.

- **95 `lvlN` abilities in Codex**, 34% of its abilities and 4.2% of the file.
  59 of them are identical modulo the number: pay 1 XP, `stat_gain:level@self:1`,
  gated on `level@self == N-1`. A single `lvl` ability gated on
  `level@self < level_cap@self` replaces all 59, with `level_cap` an ordinary
  `card_stats` number — stat-against-stat comparison already works
  (`tier@mine.player >= tier_req@target` in Spellstorm, `price@target <=
  budget@mine.player` in Puzzle Strike). The other 36 also move `atk` and
  `life`, and those want a word (below).

- ~~**27 `ult_call` abilities in Spellstorm**~~ — **done.** One entry under
  `tags.ult.abilities` reaches all 27: `cards.abilities` gathers tag abilities
  (cards.lua:212) and `activate_zone` walks whatever that returns. 234 abilities
  on cards became 207.

- **Codex's combat macro, written out three times.** `strike_lead`,
  `strike_patrol` and `strike_army` each carry the same 25 steps, 11 of which
  are `activate_zone:duel:by_column:<pass>`. One immutable card in a rules zone
  holds it once.

## Missing words, in the order worth building

### 1. ~~A scope names one place, and the place must be a zone key~~ — shipped

Answering *why Spellstorm has `ice_held`* was the whole argument, and it is
below as written. What shipped is the fix it argues for, plus one thing the
survey had not seen; both halves of the word landed together, since §2 turned
out to be the same word in the other place rather than a second one.

Spellstorm asks "an ICE of mine, wherever I keep it" — hand or discard, not
deck, not battle, not void. A scope is `[quant.][owner.]<zone>.<tag>`
(predicate.lua:467) and the place half is matched by key alone
(`zones.all_with_key`, predicate.lua:476), so there is no way to name two
zones. What the game does instead is four layers deep:

```
zones:          hand    applies ["in_hand"]
                discard applies ["in_discard"]
computed_tags:  held      any_of  ["in_hand", "in_discard"]
                ice_held  needs   ["tagged:ice@self", "tagged:held@self"]
use:            move:random.mine.everywhere.ice_held:ice_pile
```

Two zone tags whose only purpose is to be gathered, a union to OR them, an AND
to put the real question back, and then `everywhere` — every card entity in the
game — walked and filtered. Five of Spellstorm's eight computed tags are that
last step: `ice_held`, `ash_held`, `curse_held`, `junk_held`,
`curse_or_ice_held`. Puzzle Strike's `character_stowed` is the same shape over
`stowed = in_bag | in_discard`. The validator already carries a paragraph
rationalising the first layer — "a zone that hands out `in_hand` for a union to
gather is the whole of *your hand or your discard*, and it has no other reader
by design" (validate.lua:485).

**The fix is to let the place half match a zone tag as well as a zone key.**
Zones already carry free-form `tags` (zones.lua:131, `tags = def.tags_set`), and
the engine reserves only `bare`, `optional`, `refill_when_empty` and `shuffle`.
Then the whole chain above is:

```
zones:  hand    tags ["held"]
        discard tags ["held"]
use:    move:random.mine.held.ice:ice_pile
```

Five computed tags, two `applies` and one `everywhere` walk go. Resolution order
is already decided and already written down: key first, then the new reading,
then a card tag — "the zone comes first because a place is the wider of the two,
and a tag that happened to name a zone would otherwise decide which reading a
line got" (predicate.lua:465). The validator should refuse a zone tag that
collides with a zone key, which is the only way that order can surprise anyone.

**Not multi-tag scopes.** The first draft of this finding proposed letting a
scope AND two *card* tags — `mine.everywhere.ice.held` — because a target spec
already does (`tags.lua:237` ANDs a whole list) and a scope cannot, which is one
question with two spellings. That would work and it is the wrong fix: the
question here is which *places* count, and answering it with card tags is what
built the four layers in the first place. Zone tags answer it where it lives.

**And `status` is deliberately not part of this.** `status: board` already
exists, and `tags.IN_PLAY` already means it internally, so matching it would
make `mine.board.unit` work with no authoring at all. It is still refused: a
game that can say `board` two ways has a synonym, and the reason a tag may carry
`play` and nothing else is that "a second road to one word is how a format grows
synonyms" (declaration.lua:1019). A game that wants the board as one place tags
its board zones.

**What the survey had not seen: two kinds of word are never places.** A style is
one — a zone and the cards lying in it are routinely given the style they share,
which is how a game says they draw alike, and `lor.json` had exactly that
(`nexus_plate` on the seat box and on both seat cards) on the first run. The
other is a word the engine reads off a zone, and finding the list of those cost
the real time: `stack` is how `flow` finds the response window (flow.lua:1531)
and nothing had ever declared it, so removing it from Spellstorm as dead weight
broke ten reaction tests. It is registered now and held to
`zones.ENGINE_ZONE_TAGS` by a test, so the two lists cannot drift again.

**And `place_word` takes the definitions rather than reading the live game.**
The validator parses a file and checks what came out — that is the whole of being
able to check a game without running it — so `declaration.G` is empty while it
works. Reading it there answered for whatever happened to be running, which is
why the `lor.json` case passed the first time and failed the second.

### 2. ~~`target.zones` matches a zone key, and Codex spells out six~~ — shipped

Codex has **97 target blocks, 58 of them distinct**, and most of the difference
between them is which of six board zones they list. "Any card in play" is
`["army", "base", "tech", "structures", "addon", "patrol"]`, written out six
separate times; "their unit" is `["army", "patrol"]`, eleven times. Adding a
board zone to Codex means editing 97 blocks, and the file gives no way to tell a
block that means *the board* from one that happens to list those zones.

The matching was `zone_set[z.layout] or zone_set[z.key]` (tags.lua:234, and
targeting.lua:80 for slots). This turned out to be the same word as §1 rather
than a second one, so it arrived with it: an entry in `zones` reads a zone tag,
through the same `place_word` rule, and the two halves cannot drift.

**Codex now names four classes**, and 72 of its 97 blocks say one word where
they listed keys — 278 lines out of the file:

| word | zones wearing it | blocks |
|---|---|---|
| `fielded` | `army`, `patrol` | 36 |
| `fighters` | `army`, `patrol`, `command` | 14 |
| `in_play` | the six board zones | 8 |
| `built` | `base`, `tech`, `structures`, `addon` | 8 (+4 as `built`, `patrol`) |

The 25 blocks left name one zone, or a set with no word worth having
(`fielded`, `ongoing`; `built`, `army` — their buildings or their army, which is
`strike_army` having already passed the patrol).

**Checked three ways, because 72 mechanical edits to a 470KB file is not
something to eyeball.** Every block's zone list was resolved back through the
tags actually written into the file and compared with the list it replaced: 97
blocks, 97 identical, 72 of them rewritten. Then the same comparison through the
engine's own matching (`zone_set[z.key] or zone_set[z.layout] or zone_tagged`)
over every zone entity Codex builds, which is the predicate `find_targets`
applies. Then the game played.

**And the word was half-landed until this.** `check_target` validates
`target.zones` against zone keys in a second place (validate.lua:1666) that the
first pass missed, so the runtime accepted a zone word there while the validator
refused it — which is how converting Codex found it. Both halves read
`zone_words` now.

### 3. ~~No word for "in play, at its printed numbers"~~ — shipped

Codex's 18 `summon` abilities are the same nine steps each, six of which are
`stat_set` restoring a number `card_stats` already prints:

```
stat_set:level@self:1   stat_set:ripe@self:0    stat_set:atk@self:2
stat_set:life@self:3    stat_set:armor@self:0   stat_set:guard@self:0
```

108 lines saying what the card says above them, because a hero can come back and
its numbers have to be put back.

**`reset:<scope>[:<stat>]` shipped**, and the template needed no help: a stat's
own `start` already folds into `card_stats` at load, so `armor` and `guard` and
`ripe` restore without being written on every card that has them — three of the
six lines. Each summon is now `reset:self` and the two or three lines that
genuinely are the summon.

The ceiling and the floor come back with the value, which is a real change of
behaviour next to the `stat_set`s it replaces: those only ever moved the value,
so a hero whose life maximum had been boosted used to come back carrying the
boost. It is what "printed numbers" means, and the alternative is a word that
puts most of them back.

Checked by summoning all 29 heroes through the engine with every number they
carry scrambled first: 882 numbers, 881 back at what the card prints. The one
that is not is Prynn, whose summon sets `time:4` *after* the reset because she
arrives with four fading runes and is printed with none — the line doing its
job.

### 4. Every arrival and death is run by hand

`activate_zone:rules_death` appears 54 times in Codex and `rules_arrive` 45 on
cards, each one the author remembering that damage can kill and that an arrival
is watched. `rules_arrive` holds **two** rule cards between them — a +1/+1 rune
on every Blooming Ancient, and a card drawn per Flagstone Garrison — so it is
two rules and forty-five reminders.

**And unlike the death rules, this one is already wrong.** 72 action lists put
something into `army` or `patrol`; 28 do not run the arrive rules. Codex tries
to say it once, on the four `techN` tags, whose `play` opens with the call — but
a tag hands over `play` whole or not at all and a card's own wins outright
(declaration.lua:1015), so any unit needing its own play action silently loses
it. Confirmed at load: `bloodrage_ogre` gets the call, `spore_shambler` and
`young_treant` do not, because both wanted a line of their own. Add every
`create:mine.army:…` token — skeletons, ninjas, blue soldiers, wisps, squirrels
— and Blooming Ancient sits there not runing. A handful of the 28 are correct:
`final_showdown` creates into `enemy.army`, and the rule cards read `mine`.

**The answer is the zone, not a global moments block** — which is what the first
draft of this section proposed, and it was the wrong shape. A zone already has
`receive`, and `receive` already sees every arrival: `fire_receive` is called
from the move path (zones.lua:845) *and* the create path (zones.lua:909). Two
declarations, on `army` and `patrol`, in place of forty-five reminders, and the
28 misses close by construction because the zone cannot be forgotten.

**What blocks it is one word, and it is not a big one.** `receive` runs its
block with the *zone* as the acting card and the newcomer as `@target`
(zones.lua:621). Blooming Ancient's rule is *"whenever **another** unit of yours
arrives"*, and a rule about the other cards on the board has no way to leave the
newcomer out: `each.mine.ancient` includes it, and `others` drops the asker,
which here is the zone. That is exactly what Codex's ordering is a workaround
for — all 45 call sites fire the rules *before* the move, so the arriving card
is not yet in scope to catch its own trigger. So the word wanted is "every one
of these except the one that just arrived", said inside a receive.

**Routing it through `emit` and a mandatory reaction does not work**, and this
is worth recording because it looks like it should. On a fixture: a zone whose
`receive` is `emit:arrived`, and a watcher carrying `{ to: "arrived", forced:
"mandatory", needs: ["not_self@event"] }`. Two things go wrong. The watcher runes
itself, because the emit's subject is the zone rather than the arriving card, so
`not_self@event` compares it to the zone and always answers yes. And the count
is wrong: one play that arrives and then creates three tokens raises the watcher
by **1, not 4**, because a reaction answers a record once (`top.re_answered`).
Reactions are a response window, not a trigger that fires per arrival — which is
the right design for reactions and the wrong tool for this.

### 5. ~~`computes` has one operator, and Codex chains eight deep~~ — shipped

**15 of Codex's 25 computes existed only as parentheses.** The names admitted
it: `lead_ig1` and `rest_ig1` were *part one of a sum*, and the attack chain ran
`det → unspent → watching → no_det → sneak_ok → lead_pass → lead_ig1 → lead_ig
→ lead_hold`. AUTHORING's own rule is that "two chained is the intended answer;
four means the rule wants a word of its own". At eight, the word it wanted was
brackets.

`from` is now an arithmetic expression: `+ - *`, parentheses, `*` binding
tighter, both associating left. The school precedence precisely so there is no
second rule to teach — and arithmetic only, no comparison, no boolean, no
branch. Spaces around a binary operator stay, since they are what tell one from
a hyphen in a name and a minus on a literal.

Codex is 25 computes down to 18 and the chain three deep instead of eight. Seven
went: the four whose tooltips said they were fragments of a sum, and `det`,
`unspent` and `no_det`, each of which fed one parent that was the idea they were
half of. `lead_hold` is now `lead_pass + lead_t0 + lead_un + lead_wk` and reads
as the sentence it always was. What stayed are the names a reader would ask
about — `t0_rest` really is *their tech 0 patrollers other than the squad
leader*.

Proved algebraically rather than eyeballed: the old chain and the new one
evaluated over 4,000 random assignments of the fourteen leaf subjects, comparing
`watching`, `sneak_ok`, `lead_pass`, `rest_pass`, `lead_hold` and `rest_hold` —
24,000 comparisons, no disagreement.

Division is still absent, and deliberately so for now: it is a new operator and
a decision about rounding, not more of the same arithmetic.

### 6. A printed stat that steps

Codex heroes read *"Levels 1-3 2/3, levels 4-6 3/3, level 7 4/3"*. The file says
it as the 36 `lvlN` abilities that §"Already sayable" could not collapse, each
`stat_set`ting `atk` and `life` on the way past — which is also why levelling
heals, as an accident of `stat_set` rather than because anything says so.

`card_stats` already takes an object where a plain number will not do
(`"life": { "value": 3, "max": 3 }`). A stepped form would let the card say its
own sentence and would take the accident out. `buffs` cannot do this: the amount
"is a plain number, never a subject" by design, so it cannot vary per card.

### 7. An ability cannot act and then ask

29 Spellstorm cards split their resolution into `cast` and `cast_ask`, with the
answer landing in `chosen`. The resolve phase then walks the zone four times —
`cast`, `cast2`, `cast3`, `cast_ask` — and the ordering of a card's own
resolution lives in the spelling of its ability keys. Codex does the same thing
harder, walking the duel zone eleven times.

Naming a step is the right word for *"every unit works out its damage, then
every keyword reduces it, then every unit takes it"* — that is a genuine
resolution in passes, and actions.lua says so at length. It is the wrong word
for "this one card does a thing and then asks a question", which is one card's
business and is being paid for by every card in the zone.

## Smaller, and already noted in the generators

- `move:` takes no count, so "discard two at random" is the line twice
  (make_spellstorm.py:64).
- A one-tracker toggle like initiative is two writes and cannot be said as one
  (make_spellstorm.py:45).
- `needs` has no `or`, which is deliberate and on `todo.md`. Worth recording
  that the `any_of` workaround is now load-bearing in all three games: `hidden`,
  `buildable`, `finished`, `hasty`, `ranged`, `exhaustable` in Codex, `held` and
  `curse_or_ice` in Spellstorm, `stowed` in Puzzle Strike.
- "Is this card mine?" has no word. Codex says `count@mine.self >= 1` 15 times
  and `count@enemy.self >= 1` nine; COOKBOOK's other spelling for it is
  `count:player@enemy.owner_of >= 1`. Two clumsy spellings and no clean one.
