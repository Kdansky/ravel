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

### 2. `target.zones` matches a zone key, and Codex spells out six — engine half shipped

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

**What is left is Codex's own vocabulary.** The classes the 97 blocks actually
name, counted:

| zones listed | blocks | what it is |
|---|---|---|
| `army`, `patrol` | 36 | where a fighter stands |
| `patrol` | 14 | the patrol alone |
| `army`, `patrol`, `command` | 13 | a fighter, a fallen hero included |
| all six board zones | 8 | anything a spell may hit |
| `base`, `tech`, `structures`, `addon` (+`patrol`) | 8 | buildings |

Three or four words cover 79 of the 97, and naming them is Codex's decision
rather than the engine's.

### 3. No word for "in play, at its printed numbers"

Codex's 18 `summon` abilities are the same nine steps each, six of which are
`stat_set` restoring a number `card_stats` already prints:

```
stat_set:level@self:1   stat_set:ripe@self:0    stat_set:atk@self:2
stat_set:life@self:3    stat_set:armor@self:0   stat_set:guard@self:0
```

108 lines saying what the card says above them, because a hero can come back and
its numbers have to be put back. `transform:<scope>:<card>` is the only verb
that resets numbers today and it swaps identity to do it. A `reset:<scope>`
restoring `card_stats` removes all 108, and stops "give heroes a new stat" from
meaning eighteen edits.

### 4. Every moment is run by hand

`activate_zone:rules_death` appears 54 times in Codex and `rules_arrive` 49.
Each one is the author remembering that damage can kill and that an arrival is
watched. I checked all 104 action lists in the file that damage or destroy
something: the discipline holds, there is no card that hurts and forgets. It
holds by hand 103 times.

The rules zone itself is right — a column of immutable cards is a good place for
rules that belong to the game rather than to a card, and COOKBOOK says so. What
is missing is the game being able to say *when* it is walked. A top-level
`moments` block naming a zone per moment keeps the idiom and drops the call
sites.

This is **not** the merge that declaration.lua:1015 refuses. That refusal is
about handing a card half a moment — "the tag's action under the card's own
cost, which reads as cleverness and debugs as neither" — and it is right. A
game-level moment is a new moment with an owner of its own, not a card's block
with something spliced into it.

### 5. `computes` has one operator, and Codex chains eight deep

**15 of Codex's 25 computes exist only as parentheses.** The names admit it:
`lead_ig1` and `rest_ig1` are *part one of a sum*, and the attack chain runs
`det → unspent → watching → no_det → sneak_ok → lead_pass → lead_ig1 → lead_ig
→ lead_hold`. AUTHORING's own rule is that "two chained is the intended answer;
four means the rule wants a word of its own". This is eight, and the word it
wants is parentheses in `from` — or n-ary `+` and `*`, which is most of the same
relief for less of the grammar.

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
