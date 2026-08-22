# 26 — An ability with an if in it, and a number with a name

**Status:** **shipped** — `when` and `computes` both, with Runeterra migrated ·
**Size:** small engine change, one large decision refused on the way

> *"stat_damage:spill@self:sum:health@across:x:count:overkilled@across:x:sum:attacking@self"
> is a bit crazy. Is this multiple actions, or is this just one massively long
> parsed sequence of things? Because so far we only had a single @ per line, not
> three, and a dozen ":" everywhere.*

It is one action. And the measurement says it is not an arithmetic problem.

---

## What the line was

```
stat_damage:spill@self : sum:health@across : x : count:overkilled@across : x : sum:attacking@self
                         ────────────────       ──────────────────────       ─────────────────
                         the value              a yes/no                     a yes/no
```

Two of the three terms are **booleans multiplied in to fake an `if`**.
`count:overkilled@across` is 0 or 1; `attacking@self` is 0 or 1. Multiplying by
them is how the file said *only when* — because an ability had `key`, `text`,
`cost`, `target`, `phases`, `action`, `moves`, and nowhere to put a condition.

Measured across the thirteen shipped games before this pass:

| | |
|---|---|
| action strings | 845 |
| median length | 19 characters |
| use `:x:` at all | 15 |
| have three or more `@` | 9 |
| of the 15, a disguised `if` | 5 |
| of the 15, real multiplication | 10 — and all ten are *one* Lost Cities scoring formula written five times |

So the blast radius of an arithmetic grammar was two formulas in the whole
corpus, and the thing actually missing was one field.

The second measurement is what paid for `computes`. Hidden stats that are
written by actions, declared on no card, and only ever read `@self` — pure
scratch registers:

| | |
|---|---|
| self-only scratch registers | 13 |
| actions existing only to feed them | 70 |
| worst: Splendor's `short` | written by 20 actions, read by 35 |

And `short` is not one value. It is a *shared* register, recycled by ten
different formulas in sequence across two tags — "how much white I cannot pay",
then blue, then in the noble tag something else again. [25](25-derived-stats.md)
already called that a hazard.

## `when` — the missing if

A list of ordinary conditions on an ability. The condition vocabulary was
already shipped whole by [17](17-conditions-as-expressions.md); it simply was
not reachable from an ability, though LoR's own block target had been using it
for a while.

```json
{ "key": "spill", "text": "Overwhelm", "phases": ["strike"],
  "compute": ["overkill"],
  "when":    ["attacking@self >= 1", "overkill >= 1"],
  "action":  ["stat_gain:spill@self:overkill"] }
```

**Why `when` and not `needs`, which is the word the format already has.** They
are different questions and the format already keeps them apart. `needs` is
*permission* — may this player do this — and `activate_zone` refuses permission
checks on purpose (`actions.lua`: "a rules card that refused itself here would be
a rule that silently did not happen"). `when` is the word routing and
`end_conditions` use for *does this fire*. Overwhelm's condition is part of the
rule, not a gate on a player, so the doctrine survives intact and the comment in
`activate_zone` gained a paragraph saying which is which.

It is honoured in both paths: `activate_zone`'s walk, and
`flow.usable_abilities`, so an ability whose condition fails is not offered in
the chooser either.

## `computes` — a number with a name

The first draft put the name inside the string (`"overkill = 0 - health@across"`)
and was rejected: *"I would really rather not have to parse assignments within
strings."* The second draft was positional — `compute.1`, `compute.2`, with
`compute` meaning the first — and lost to `DESIGN.md`'s own rule from two days
earlier: **a number is never positional**. `compute.2` is `[min, start, max]`
again, a number a reader must count to that renumbers every reference when a
line is inserted above it.

What landed is the user's third suggestion, and it is not a new concept at all —
it is the format's fifth instance of an idiom it already uses four times.
`patterns`, `styles`, `tags` and `effects` are global name→definition maps that
cards reference by name. `computed_tags` is that shape producing a boolean. This
is that shape producing a number, declared like a `stats` entry because that is
what it is minus the storing:

```json
"computes": [
  { "key": "overkill", "from": "0 - health@across",
    "tooltip": "How far past death the unit across this one was struck." }
]
```

Three things fell out of the global node that the inline form did not have:

- **No assignment to parse.** The key is a JSON key; `from` is a pure expression.
- **Order is recovered at the use site.** `json.lua`'s `parse_object` builds a
  plain Lua table and key order is lost, so a *map* of computes could never have
  been evaluated top to bottom. The ability's `compute` is an ordered array of
  strings, so a compute reading an earlier one is just "the line above ran
  first" — no dependency graph, no cycle check, no evaluation order to explain.
- **Documentation has a home**, and one declaration serves every card.

**The name is the point.** `sum:health@across` does not say why it is being read;
`overkill` does. That is most of the readability win, and it arrives without any
arithmetic at all.

## How much arithmetic, and the cap

`from` is `"<term>"` or `"<term> <op> <term>"` with one of `+ - *`, spaces
required around the operator. One operator, no parentheses, no precedence.

[25](25-derived-stats.md) proposed exactly this cap and then doubted it: Splendor
needs a five-term sum, so "allow n-ary `+`" would move the cap before anything
was written. **The doubt does not survive contact with the corpus**: n-ary
addition already has a spelling — successive `stat_gain` lines onto one stat,
which is readable and staying. What had no spelling was subtraction into a value
slot, and that is exactly one operator.

## What was refused

- **Arithmetic in the action value slot** — [17](17-conditions-as-expressions.md)
  step 5, which would have deleted `:x:`. Refused by the user directly ("C does
  not work, I agree"). Without parentheses `sum:value@mine.red - 20 * count:wager`
  reads left to right, which is a rule a reader must be *taught* and cannot check
  — the same defect the positional array was retired for. With parentheses and
  precedence the format is a programming language and `DESIGN.md`'s refusal is
  dead. **Step 5 of 17 is now closed rather than pending**: what it wanted from
  arithmetic, `computes` provides in a place where the formula sits alone with a
  name on it.
- **Parameterised computes.** Splendor's five colours differ only by the word
  "white". The moment `computes` takes an argument it is a function.
- **`armor` as an engine word.** Asked directly: should `stat_damage` know that
  a thing called armor reduces it. That is the right-hand column of the first
  directive's own table with a different noun in it, and the left-hand column was
  already built — the `incoming` channel plus an ordered step gives exactly that
  behaviour in one line on the tag, source-agnostic, so a spell that deals a
  strike meets armour without knowing anything about combat.
- **Overkill as an engine concept.** The good half of the same question, and it
  needed nothing: `bounds()` already documents that "a stat with no floor may go
  negative, which is what lets a blocker carry its own overkill", which is
  precisely why LoR declares `health` unfloored. What was missing was a *name*,
  and that is what a compute is.

## What Runeterra looks like now

```json
"overwhelm": { "tooltip": "Overwhelm — damage past the blocker hits the Nexus.",
  "abilities": [
    { "key": "spill", "text": "Overwhelm", "phases": ["strike"],
      "compute": ["overkill"],
      "when": ["attacking@self >= 1", "overkill >= 1"],
      "action": ["stat_gain:spill@self:overkill"] } ] },

"in_combat": { "abilities": [
  { "key": "aim",  "text": "Strike", "action": ["stat_gain:incoming@across:sum:power@self"] },
  { "key": "land", "action": ["stat_damage:health@self:sum:incoming@self"] },
  { "key": "spill",
    "when": ["attacking@self >= 1", "count:unit@across == 0"],
    "action": ["stat_set:spill@self:sum:power@self"] } ] }
```

All three `:x:` uses are gone; every remaining string has one `@`. The `spill`
step lost an action outright — "if blocked, zero it again" was a second line
undoing the first, and a `when` says it once before either happens. And the
`overkilled` computed tag went with them: it existed only to be that gate, and
the gate now reads `overkill >= 1`, which says the thing directly.

`:x:` survives in one generated file (`tools/make_lost_cities.py`) and one Crew
line. Everywhere it is left, it means *multiply* — never a disguised `if`.

## The bug it turned up

**A bare word in a value slot read as zero, silently.** `term()`
(`actions.lua`) does `tonumber(p[i]) or default`, so `stat_gain:gold:teh_count`
gained nothing and said nothing — a line that ran and did no work. It had no
validator branch at all, because the `n` argument type was the one type
`check_action` never checked. It does now, on the first term and on every factor
after an `x`, and a compute key is the one bare word that is legitimate there.

## What is left over

- **A compute has no floor, and Splendor's pricing is built on one.**
  `due_white` is `cost − bonus` clamped at 0 by the stat's own `min: 0`; an
  unclamped `due` goes negative when the buyer holds more bonuses than the cost,
  and `stat_damage:t_white:due` would then *hand out tokens*. So Splendor's
  `due_*` / `short` stay hidden stats. Shipped unclamped deliberately rather than
  inventing a spelling for it up front — the two games that migrated can say
  whether a floor is still wanted.
- **A compute cannot be an operand on the right of a comparison.**
  `predicate.compile` is pure and memoised across game loads, and letting it ask
  `G.compute_defs` whether a bare word is legitimate would end that. `overkill >= 1`
  is the shape that was wanted; `x >= overkill` is not writable.
- **[25](25-derived-stats.md) should be re-read, not built.** `compute` answers
  two of its three blocking questions by construction — *when is it evaluated*
  (when the ability fires) and *what does `@owner` mean on an unowned card* (it
  runs inside an action with a ctx). The open question is whether a stat that
  keeps itself is worth anything once a formula can sit at its use site with a
  name on it. Answer it with the Crew's `weigh` migrated, which this pass did not
  do.
- **The Crew's `weigh` is the next migration** — 16 actions on one ability, run
  twice per trick, three formulas fighting over `live` / `gap` / `over`.
