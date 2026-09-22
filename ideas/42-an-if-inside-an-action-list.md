# 42 — An if inside an action list

**Open, and blocked on one decision about the grammar rather than on effort.**

An ability carries a condition — `needs` asks *may this happen* and `when` asks
*does this happen*. Both gate the **whole** ability. So a card that does one
thing and then conditionally does a second has to be written as two abilities,
and a card whose resolution is walked by a phase pass has to make the *phase*
know that the second one exists.

Counted as *an ability carrying a gate while a sibling on the same card carries
none* — the shape that is an `if` and not a choice:

| | abilities | gated siblings |
|---|---|---|
| Spellstorm | 233 | **44** |
| Codex | 260 | 9 |
| Puzzle Strike | 30 | 0 |

It is concentrated, and that is worth saying plainly: this is a Spellstorm
problem that Codex has a little of and Puzzle Strike does not have at all.

## What it looks like

`magicdart` prints *"Gain 1 mana. If you have Initiative, deal 1 damage."* One
sentence. The file:

```json
"abilities": [
  { "key": "cast",  "text": "Resolve", "action": ["stat_gain:mana@mine.player:1"] },
  { "key": "cast2", "text": "Resolve", "needs": ["initiative@mine.player >= 1"],
    "action": ["hit:health@opponent:1"] }
]
```

Two abilities, both captioned "Resolve", and the order they run in is the
alphabetical accident of their keys. **All 22 of Spellstorm's `cast2`/`cast3`
abilities carry a `needs`. Not one of them is a genuine second step.**

And the cost does not stop at the card. The `resolve` phase reads:

```json
"actions": ["activate_zone:rules:by_column:dust",
            "activate_zone:mine.battle:by_column:cast",
            "activate_zone:mine.battle:by_column:cast2",
            "activate_zone:mine.battle:by_column:cast3",
            "activate_zone:mine.battle:by_column:cast_ask"]
```

**A card wanting a third conditional clause needs a `cast4` and an edit to the
phase**, and every other card in the zone pays for the extra pass.
[38](38-repeated-shapes.md) §7 says the same thing about the `cast_ask` half:
naming a step is the right word for *"every unit works out its damage, then
every keyword reduces it"*, and the wrong word for *"this one card does a thing
and then asks a question"*.

## The obvious spelling, and why it is not obvious

A wrapper op, the shape `each_seat:<action>` and `emit:<verb>:<action>` already
have:

```
"when:initiative@mine.player >= 1:hit:health@opponent:1"
```

**It does not parse.** A condition may contain a colon —
`count:farm@mine.board >= 3`, `sum:value@target >= 4`, `tagged:witch@source` —
so `when:count:farm >= 3:hit:…` has no reading the parser can find. `each_seat`
and `emit` dodge this only because their first argument is a bare word that
cannot contain one.

Three ways out, and this is the decision the track is waiting on:

1. **The condition names a `computes` key.** `"when:has_init:hit:health@opponent:1"`,
   with `has_init` declared once at the top level. A compute key cannot contain a
   colon, so the grammar is clean with no new rule; the word already exists; and
   the card reads as English. The cost is a declaration per gate, and a decision
   about what a compute means as a *truth* — presumably `>= 1`, which is how
   `ready@`, `tagged:` and `saved:` already read when written bare.
2. **A separator the grammar reserves**, so the condition is bounded. Cheapest
   to implement, and it puts a second punctuation rule into a format whose whole
   claim is that `:` separates everything.
3. **Split on the first token that is a known op name.** Works today, needs no
   new word, and is the kind of rule that is invisible until a game names a
   compute `hit` and the line changes meaning silently. Refuse.

**The recommendation is 1**, and it is a recommendation rather than a decision
because it adds a declaration to the file for something a reader would expect to
write inline.

## What it would delete

Spellstorm: 22 abilities, two of the four passes in `resolve`, and the reason
two abilities on one card are both called "Resolve". Codex: 9. It does **not**
touch `cast_ask`, which is [38](38-repeated-shapes.md) §7's half and a different
question — acting and then asking is about the offer queue, not about a gate.

## What to refuse

- **`else`.** Two conditions that exclude each other are two lines, and the
  second one says its own condition. `r_tier`'s `tier_up`/`tier_gem` pair is
  written that way today and reads correctly.
- **Nesting.** A `when:` whose action is another `when:` is a parser with a
  stack and a format with an expression language. One level, and the validator
  refuses the second.
- **`or`.** Already refused, on [31](31-either-of-two.md), for its own reasons.
  A gate here is a condition in the one vocabulary, with whatever that
  vocabulary can say and nothing more.
