# 29 — A place to fight

**Shipped** (2026-09-01). Codex resolved an attack as one action list on the
attacker. Twenty-five cards want to speak *inside* the exchange and the list has
no inside. LoR already solved this; the question is what it costs to say the
same thing here.

## What the list cannot do

`codex.json` carries three strike abilities — squad leader, patroller, anything
— and each ends in the same nineteen lines, copied out:

```json
"stat_set:incoming@self:sum:atk@self",
"stat_damage:incoming@self:sum:armor@target",
"stat_damage:hp@target:sum:incoming@self",
...
"activate_zone:rules_death"
```

Three copies that must stay identical, and no point in them a card other than
the attacker can reach. Everything that blocks a card blocks it for that one
reason:

| clause | cards |
|---|---|
| overpower | 9 |
| `Attacks: …` | 5 |
| sparkshot | 3 |
| deathtouch · frenzy · long-range · obliterate | 2 each |
| "whenever this kills a patroller" | 2 |
| swift strike · armor piercing · healing · readiness | 1 each |

## What LoR does

Combat is not an action list. It is a zone walked four times:

```json
"activate_zone:battle:by_column:aim",
"activate_zone:battle:by_column:armor",
"activate_zone:battle:by_column:land",
"activate_zone:battle:by_column:spill"
```

Three parts, all of which Codex already has:

1. **A zone cards are moved into to fight.** `battle` is a `grid`, and its
   `applies: ["in_combat"]` hands the four step abilities to whatever lies in
   it. Nothing is written on a card to enrol it; lying there is the enrolment.
2. **Keywords are tags that join a step.** `tough` adds one ability keyed
   `armor` doing `stat_damage:incoming@self:1`. It does not know what else runs
   at that step, and nothing that runs there knows about it.
3. **Pairing is spatial.** The grid is 6×2 and `@across` names the card
   opposite, so no rule needs to be told who is fighting whom.

The steps *are* the ordering. Nothing declares one.

Codex can invoke the walks straight from the strike ability — it already calls
`activate_zone:rules_death` from inside one — so no phase restructuring is
needed and the attack stays a thing you do in the main phase.

## The shape for Codex

A `duel` zone, `grid: [1, 2]`, `applies: ["in_combat"]`, one pattern `across`
with vectors `[[0, 1], [0, -1]]`. Attacker into the near cell, defender into the
far one, then:

| step | who speaks | what it says |
|---|---|---|
| `obliterate` | attacker | destroy N of the defender's side before anyone aims |
| `aim` | both | `stat_gain:incoming@across:sum:atk@self`, plus `Attacks:` abilities, plus `frenzy`'s `stat_gain:incoming@across:sum:frenzy@self` |
| `armor` | defender | `stat_damage:incoming@self:sum:armor@self`, `when: ["count:armor_piercing@across == 0"]` |
| `land` | both | `stat_damage:hp@self:sum:incoming@self`, and deathtouch's `stat_set:hp@self:0` `when: ["incoming@self >= 1", "count:deathtouch@across >= 1"]` |
| `spill` | attacker | overpower's overkill to the base; sparkshot to the neighbours |
| — | | `activate_zone:rules_death` |
| `home` | survivors | back where they came from |

Two things worth noticing about that table. **Armor piercing belongs to the
attacker and is spent on the defender's line** — it is the defender who skips
its own reduction, asking `@across` whether to. That sentence has nowhere to
live in an action list, and it is the whole argument. And **frenzy adds to
`incoming` rather than to `atk`**, so no printed number is written and nothing
has to be put back — which is how every "+N while attacking" here dodges the
continuous-effects gap the rest of Codex is waiting on.

Swift strike costs two more steps (`aim`/`land` run twice with a death check
between) rather than a new word.

## The hard part: getting home

`activate_zone` builds its context as `{ card_id, targets = {} }`. Targets do
not survive the walk, so the defender cannot stay where it is and be reached as
`@target`. It has to be **in** the walked zone. LoR never meets this because
everything on both sides returns to one `bench`.

A Codex defender came from one of ten places — five patrol slots, the army, the
base, the tech buildings, the structures, the add-on — and nothing records which.
`return_to` takes a fixed destination and `move_to` with no argument means the
card's home zone, which for a patroller is the army: correct for the attacker,
wrong for everyone else. **A patroller that survives must go back to the slot it
was in**, or the patrol zone quietly empties itself every combat.

### Option A — a slot stat, and ten guarded abilities — *rejected*

Each patrol ability stamps `stat_set:slot@self:1..5`, and the `home` step is one
guarded ability per origin. Ships with no engine change, and costs an index of
the board written out by hand on a tag: every new zone must be added to it, and
forgetting a line is wrong in a way nothing can detect — the cards just fall
into the army.

### Option B — `origin`, a destination word — **shipped**

`zones.move_card` already knew where a card was leaving from; now it remembers,
as one field on the card entity, and four verbs take `origin` where they take a
zone:

```
move_to:origin                   the acting card, home
move_target_to:origin            the ones the player chose, each to its own
move:duel:origin                 empty a zone, sending everything back
return_to:duel:origin            the same, said the other way round
```

No new zone field and no new verb — one word, in the place `target` already
sits. It is engine bookkeeping rather than a game's rule: every card in every
game came from somewhere, and nothing but the engine can know it.

**A destination and never a source.** `return_to:origin:hand` is refused, and
that refusal is the definition: there is no one zone to drain, because the
answer is different for every card. That is also the whole reason the word
earns its place — one line sending a combat zone home sends each card
elsewhere, which no existing destination can express.

Three rules settled while building it:

- **Immediately before, not "where this lives".** A card played from a hand,
  sent to a duel and bounced remembers the duel. The home zone is a different
  question and already has an answer: a tag's `zone`, read by a bare `move_to`.
- **A card that never moved has no origin** and stays where it is, rather than
  being given its dealt zone as a default. Setup is not a move.
- **Going home from home is not a move.** A card already standing in its origin
  is left alone rather than removed and re-inserted, which would have fired
  `leaves` and `receive` on a card that went nowhere.

It round-trips through save and net sync for free: `entity.snapshot` deep-copies
whole entities, so a scalar on a card needed nothing added to either format.

Its reach was wider than this fight, as expected. A bounce, "return it to the
deck you drew it from", and every temporary reveal want the same word.

## What this does not fix

**Resist N** — Gemscout Owl, Calamandra, Final Showdown, and five more. It is a
cost that depends on the target, not a step in a fight, and it stays open.

## What it drags in behind it

**The five patrol zones want to be one grid.** Sparkshot hits the patrollers
*next to* what it killed, and Zane shoves a patroller to an empty slot — both are
adjacency questions, and adjacency across five separate zones cannot be asked.
As `patrol`, `grid: [5, 1]`, the slot bonuses become per-column, `@across`-style
patterns work, and Option A's ten abilities drop to six. This is not required for
the duel zone and should not be bundled with it, but it is the next thing that
asks.

## Decided

- **A zone cards move into**, not a marker stat on cards that stay put. The
  walk takes a zone; a scope will not do, and ten `activate_zone` lines per step
  to cover every zone a defender might sit in is the same rule written forty
  times.
- **Keywords join steps; steps do not know their keywords.** The step list is
  fixed by the game file and every tag that wants a voice adds an ability with
  that key.
- **`incoming` accumulates; printed numbers are not written.** Anything that
  would be a temporary buff becomes an addend on a per-combat stat instead.
- **The attack stays an ability in the main phase**, not a phase of its own.
  Codex has no blocking step to interleave, so the LoR declare/block round trip
  buys nothing here.

## What it came to

`duel` is a `grid: [1, 2]`, offscreen, `applies: ["in_combat"]`, walked nine
times from inside the strike ability — no phase of its own, because Codex has no
blocking step to interleave and a fight begins and ends inside one click:

```
clear · rage · attacks · aim · armor · land · venom · tally · spill · kills
```

Then `return_to:duel:origin` and the existing `rules_death`. **Sending everyone
home before sweeping the dead** is what kept the death rules untouched: a
scavenger dies standing in its own slot, exactly as it did before, so
`r_scav` and `r_techie` never learned that combat had moved.

**The cell question answered itself.** The zone is empty before every fight and
emptied after, so `move_to:duel` then `move_target_to:duel` fill cell 1 and cell
2 in that order, and `by_column` walks them in it. No slot targeting, no named
cells.

Three things the steps bought that no action list could hold:

- **Armor piercing belongs to the attacker and is spent on the defender's
  line** — the defender skips its own reduction, asking `@across` whether to.
- **"+4 ATK when attacking buildings"** — nothing could ask what a strike was
  aimed at until the target stood in the same zone as the attacker.
- **Deathtouch is a rule about the victim**, reading the card across it, and had
  nowhere to live on the attacker.

**Nothing writes a printed number.** Frenzy and the siege bonuses add to
`power`, a per-combat stat set from `atk` at `clear`, so no buff has to be put
back and Codex's continuous-effects gap never comes into it.

**One card may not carry two abilities under one name** — the chooser deals one
entry per ability, and the validator says so. That is why the killer's trigger
needed a single condition covering units, heroes and buildings alike, which is
the `tally` step: it adds `hp + life + integrity` into `left`, and `slain` is
one computed tag over it. Zane, who wants two different triggers at the same
step, keeps half of his flagged.

## Open

- **Resist N** — eight cards. A cost that depends on the target, not a step in a
  fight, and untouched by this.
- ~~Sparkshot and Zane's shove want adjacency~~ — **done** (2026-09-01). The
  five patrol zones are one `grid: [5, 1]`, and a `beside` pattern answers
  sparkshot: the row is asked *before* the defender leaves it, and each
  patroller reads whether the marked card is next to it. A gap breaks adjacency
  for free, which is the rulebook's own wording. What fell out with it: five
  `go_*` abilities became one `go_patrol` that targets a square, the five
  compute triples became one family, five `activate_zone` lines per walk became
  one, and `origin` was found to be losing the *square* on any grid wider than
  one cell — a tech building could come home from a fight in the wrong column.
  Zane's shove still needs a card and a square chosen together, and an ability
  takes one kind of target.
- **Keyword grants** — Wandering Mimic, Blooming Elm, Ferocity, Drakk. These are
  continuous effects, and they wait on that word rather than on this one.
