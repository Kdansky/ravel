# 30 — Things that are true

**Built, first cut** (2026-09-01). The stat half of `adjusts` ships with the
declared-verb rule; the cost half (`"verb": "target"`, and resist with it) is
still a draft, because it carries the preview question below. A fourth card
moment was asked for, beside `play`,
`activate` and a reaction: an **aura** that modifies behaviour rather than
causing it. "Cannot be targeted by spells." "Blue spells cannot target this."
"This takes 1 less damage."

The reframe this draft argues for: those three are not one moment. The first two
are a question the engine already asks and one game file has never answered.
The third is the only new word, and it is smaller than it looks.

## The axis is not a fourth moment

`play`, `activate` and `reactions` are **things that happen**. They have a
moment, an actor, and an action list that runs to completion.

What was asked for is **things that are true**. They have no moment. Nothing
runs. They are consulted, by whatever is happening, at the instant it happens —
and the same question asked twice gets the same answer.

Sorted that way there are three of them, and they were never one word:

| what it settles | word | state |
|---|---|---|
| whether a thing may happen at all | `receive.needs` | **ships today, unused** |
| what a number on a card *is* | `buffs` | shipped 2026-09-01 |
| how much a verb *does* | `adjusts` | this draft |

## The first one already works

`receive.needs` is asked of every candidate in `targeting.candidates`, with the
candidate as `@self` and **the card doing the aiming as `@target`**. That is
hexproof, exactly, with no engine change:

```json
{ "key": "warded", "tags": ["unit"],
  "receive": { "needs": ["not_tagged:spell@target >= 1"] } }
```

And the subset case is the same line with a different word in it:

```json
{ "key": "blueward", "tags": ["unit"],
  "receive": { "needs": ["not_tagged:blue@target >= 1"] } }
```

Verified: a bolt tagged `spell` and `blue` offers neither of them and the plain
unit only; a punch tagged neither offers all three.

**Nothing in eight game files uses it.** It has no reference section in
AUTHORING — one passing mention that it takes a list of conditions — and it is
documented in SCHEMA under `receive`, which reads as being about *arrival*
("may be sent to THIS card"). A reader looking for "cannot be targeted" has no
way to find it. That is the whole bug, and it is a documentation bug.

It also has exactly the right blind spot. `receive.needs` is asked when a
**player points at something** and never when a scope names it, so hexproof
stops a bolt and does not stop a board wipe. That is the real rule in every game
that has the keyword, and it falls out rather than being written.

**Proposed, in place of a new word: rename the question.** `accepts` is what the
engine's own comments call it, it reads as legality rather than as delivery, and
it would sit under its own AUTHORING heading with the wards as its examples.
`receive.needs` stays as the spelling that already parses.

## The second one shipped last week

`buffs` covers every *"this is bigger than it says"* effect, because it is a
read: a tag shifts a stat for as long as it is worn, nothing is written, and
nothing has to be undone. It came out of exactly this conversation and is
already carrying Codex's elite post.

What it cannot do is the reason there is a third word. A buff changes a number
**on a card**. It cannot change a number in a **sentence** — how much this
particular damage is, what this particular spell costs.

## The third: `adjusts`

A tag may say that a verb, aimed at cards it covers, lands for a different
number.

```json
"tags": {
  "tough": {
    "tooltip": "Tough — takes 1 less damage from every source.",
    "adjusts": [
      { "key": "tough", "verb": "stat_damage", "stat": "hp", "covers": "self", "by": -1 }
    ]
  }
}
```

Six fields, four of them familiar:

- **`verb`** — which action it watches, and it is a verb **the game declared**,
  never an engine one. See below: this is what stops an aura reaching into
  plumbing that was never meant to be interfered with.
- **`stat`** — which number. `stat_damage` to `hp` is not `stat_damage` to
  `gold`, and a shield that stopped both would be a bug in every game.
- **`covers`** — a scope, read with the aura's own card as `@self`, naming who
  it is about. `"self"` is the common case and the fast path; `"each.mine.unit"`
  is the anthem that protects your whole side.
- **`when`** — the one condition grammar, as everywhere. `@self` is the card
  holding the aura, `@target` is the card being acted on, and **`@source`** is
  the card doing it. That last is a new scope word and the only one this needs.
- **`by`** — the shift, in the ordinary amount grammar: a plain number, a
  subject, or a compute the entry names.
- **`key`** — a name, as an ability has, so two adjustments on one card can be
  told apart and a tooltip can say which fired.

Worked examples:

```json
"barrier":    { "verb": "stat_damage", "stat": "hp", "covers": "self", "by": -1,
                "when": ["tagged:spell@source >= 1"] }
"anthem":     { "verb": "stat_damage", "stat": "hp", "covers": "each.mine.unit", "by": -1 }
"cornered":   { "verb": "stat_damage", "stat": "hp", "covers": "self", "by": -2,
                "when": ["count:mine.unit <= 1"] }
```

### The verb is the game's word, not the engine's

**`stat_damage` is a mechanism and not a meaning**, and an aura keyed to it
would be a rule with a reach nobody can predict. Two ways that goes wrong, and
they are not the same problem:

*The stat already settles one of them.* A simulation lowering a plane's altitude
with `stat_damage` is safe, because an aura names its stat and a shield written
for `hp` never sees `altitude`. Nothing is needed for that case.

*The stat cannot settle the other.* **Poison and a sword both take `hp`, and
armour stops one of them.** Same verb, same stat, different meaning — and there
is nowhere in an action string for the difference to live, because an action is
a verb and its arguments and Ravel has no per-action metadata anywhere.

So a game declares its own:

```json
"verbs": [
  { "key": "damage", "does": "stat_damage", "tooltip": "Damage — armour stops it." },
  { "key": "poison", "does": "stat_damage", "tooltip": "Poison — armour does not." },
  { "key": "heal",   "does": "stat_gain" }
]
```

and writes them where it means them:

```json
"action": ["damage:hp@target:3"]
"action": ["poison:hp@target:1"]
```

with the aura keying on the word the card says:

```json
{ "key": "armour", "verb": "damage", "stat": "hp", "covers": "self", "by": -1 }
```

**An aura may name a declared verb and never an engine verb.** That rule is the
whole point and it does more than tidy the vocabulary: it makes being
interferable **opt-in**. Codex's combat steps move `incoming`, `raw`, `back` and
`spill` around with raw `stat_damage`, and none of it can ever be intercepted,
because nothing is able to name it. A game says which of its moments are moments
by giving them words; everything else stays plumbing.

It pays twice over. The log stops saying `Grunt −1 hp` and says `Poisoned Grunt
−1 hp`, and a declared verb takes a `tooltip` like every other keyword, so
"armour does not stop poison" is written once in the place the rule lives.

**Why a declaration and not inference.** Without the list, `posion:hp@target:1`
is a typo the validator cannot tell from a word the game just invented. The
declaration is what makes the typo catchable — and the check has a model
already: a reaction answering a verb nothing emits is reported today, and this
is the same cross-reference. An aura naming a verb no action performs, and a
verb declared and never used, are both worth the same warning.

**Its relationship to `emit` wants deciding.** A game can already name its own
verb there, and reactions key off it. The difference is that an emit *waits* —
it opens a response window and defers what follows — while a declared verb just
*is* what is happening. A game using the same word for both would be saying
something coherent, and whether `emits` may name a declared verb is an open
question rather than an obvious yes.

### The rules that keep it predictable

**They sum, in sorted key order.** Two `tough` are two less. Order is fixed at
load so a replay adds them the same way twice — the same reason the buff index
is sorted.

**An adjustment may not change the sign.** `stat_damage:hp:1` reduced by 3 is 0,
never a heal of 2. A word that could turn damage into healing by accident is a
word nobody can reason about; a game that wants that writes a reaction.

**It adjusts the number the action names**, always as a player reads it. The
action says "3 damage", the aura says "1 less", the answer is 2 — the author
never has to know the delta is carried negative inside the engine.

**It is asked before the change and sees the board as it was.** "Takes 1 less
while damaged" reads the hp this damage has not yet taken off, which is the
reading every card that says it means.

**Only cards in play hold auras**, the same status a tag scope already means. A
shield in a deck shields nothing.

**`stat_set` is not adjustable, on purpose.** It is the authoring tool that
resets a counter past every bound — and it could not be declared as a verb's
`does` even if a game tried.

### Why it returns a number and not an action list

This is the one place the draft says no to what was asked. "Return something
similar to an action list which modifies whatever is about to happen" is the
natural way to describe it, and it is the version that cannot be built well.

An action list running *inside* another action is re-entrant: the aura could
destroy the card being damaged, move it, or start a fight, half way through a
verb that is holding a reference to it. It would be order-dependent between
auras. And it could not be asked twice with the same answer — which breaks the
invariant `activate_zone` rests on, that the rules resolve a zone in one instant
so a snapshot can never be taken mid-combat.

A number has none of those problems. It is a read, like `buffs` and like
`accepts`, and that is what puts all three in the same family.

The genuinely-replacement case — *"if it would die, exile it instead"* — is a
different word and is not this one. `leaves` is already where a card says what
happens on its way out.

## Implementation

Two hook points, plus an index built at load.

**`change_stat` in `actions.lua`** is the single per-entity funnel for every
stat change in the game: `apply_stat` resolves the subject, then loops
`designated` and calls it once per card. The adjustment goes inside that loop,
which is what makes "this creature takes 1 less" possible at all — `amount()`
runs once for the whole action and does not know who is being hit. The verb
comes from `p[1]` and is one extra argument to pass.

**`flow.plan`** for the cost case, below.

**The verb table** costs nothing at runtime. `p[1]` already carries the word the
action was written with, so the handler lookup resolves `damage` to
`stat_damage` once at load and the original word rides along to `change_stat` as
the thing the aura keys on.

**The index** mirrors `buff_index`: keyed by `verb .. ":" .. stat`, built in
`declaration.lua`, so a game with no auras pays one nil lookup per stat change
and every shipped game but Codex is that game. On a hit, walk the entries; for
each, find the cards in play wearing the tag and test `covers` and `when`.
`covers: "self"` short-circuits to an identity check and will be the great
majority.

Cost is defs × bearers per adjusted change. Codex would have perhaps eight.

Nothing crosses the wire: an aura is derived from a tag on a card, and both
already travel.

## What it reaches, including the one it was not expected to

**Resist N, at last — with one decision to make.**

```json
"resist_2": {
  "adjusts": [
    { "key": "resist", "verb": "target", "stat": "gold", "covers": "self", "by": 2,
      "when": ["tagged:spell@source >= 1"] }
  ]
}
```

`"verb": "target"` is the second verb the word needs: *anything that aims at a
card I cover pays this much more*. It hooks `flow.plan`, which already receives
the chosen targets — `flow.lua:903` judges the cost after targeting and the
comment there already says why: *"A cost the targets pay could not be judged
before they were chosen."*

The decision is the **preview**. Playability and dimming are settled at
`flow.lua:803` with no targets, so the card in hand would show its printed price
and only quote the resist once a target is picked. Three ways out, and this is
the user's call:

1. **Accept it.** The resisting unit is face up on the board; the player can
   read it. The play is refused after the pick, as it is now for any unaffordable
   cost.
2. **Dim on the worst case** — quote the price plus the largest resist any legal
   target carries. Honest about affordability, wrong about the number.
3. **Show a range** in the cost row: `2–4 gold`. Truthful, and the only one that
   needs the renderer to learn anything.

Also reached, from Codex's own gap list: the four keyword-grant cards, if their
grants are `buffs`; and LoR's `tough`, which is currently an ability inside the
combat zone walk and would become one line.

**Not reached, and not trying to be:** replacement effects, anything needing a
choice made mid-verb, and source-side arithmetic. That last is worth saying
plainly — *"my spells deal 1 more damage"* is expressible (`covers` the enemy
side, `when` reads `@source`) but reads badly, and almost every source-side
effect is really a `buffs` on the attacker's own number. If a game turns up
where it isn't, that is evidence for a fourth entry in the table, not for
widening this one.

## What shipped, and what did not

**Shipped**: `verbs` as a top-level list, `adjusts` on a tag, `@source`, and the
rule that an aura may watch only a declared verb. Two engine verbs may be stood
for, `stat_damage` and `stat_gain`. The hook is in `change_stat`, per card, and
the index is keyed `"<verb>:<stat>"` so a game with no auras pays one nil lookup
per stat change. Ten validator refusals, seven integration tests, and a section
in AUTHORING.

**Not shipped**: `"verb": "target"` and the cost hook in `flow.plan` — which is
resist. Everything about it is settled except the preview, and that is a
question about what a player is shown rather than about the word. It is one
handler and one index lookup once that is answered.

## Open questions

1. ~~**The name.**~~ Settled as `adjusts`, because it says what it does and pairs
   with `buffs` — one shifts a number *on* a card, one shifts a number *done to*
   one. Against `aura`: Ravel already has `attached`, and MTG's Aura is an
   attachment, so the word would arrive meaning something else.
2. ~~**`@source`.**~~ Shipped. `@event` was taken and means a reaction's record.
3. **Which engine verbs a game verb may stand for.** `stat_damage` and
   `stat_gain` shipped. Counts — draw two fewer, destroy one less — are a later
   widening and want their own evidence.
4. **Whether `emits` may name a declared verb**, or the two vocabularies stay
   apart. See above.
5. **The preview**, above.
