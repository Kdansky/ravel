# 26 — An ability with an if in it, and a number with a name

**Shipped** — `when` and `computes` both, with Runeterra migrated.

The question was whether this was one action or a parsed sequence:

```
stat_damage:spill@self : sum:health@across : x : count:overkilled@across : x : sum:attacking@self
                         ────────────────       ──────────────────────       ─────────────────
                         the value              a yes/no                     a yes/no
```

It is one action, and **two of the three terms are booleans multiplied in to
fake an `if`** — because an ability had `key`, `text`, `cost`, `target`,
`phases`, `action`, `moves`, and nowhere to put a condition.

## The measurement that decided it

Across the thirteen shipped games: 845 action strings, median 19 characters, and
only **15 using `:x:` at all — five of them a disguised `if`**. The other ten are
one Lost Cities scoring formula written five times. So the blast radius of an
arithmetic grammar was two formulas in the whole corpus, and the thing actually
missing was one field.

A second measurement paid for `computes`: **13 hidden stats that are pure
scratch registers**, written by 70 actions that exist only to feed them.
Splendor's `short` is written by 20 and read by 35 — and it is not one value but
a *shared* register recycled by ten formulas in sequence.

## `when` — the missing if

A list of ordinary conditions on an ability. The vocabulary was already shipped
by [17](17-conditions-as-expressions.md); it simply was not reachable from an
ability.

**Why `when` and not `needs`.** They are different questions and the format
already keeps them apart. `needs` is *permission* — may this player do this —
and `activate_zone` refuses permission checks on purpose, because a rules card
that refused itself there would be a rule that silently did not happen. `when`
is what routing and `end_conditions` already use for *does this fire*. So the
doctrine survives intact. It is honoured in both paths, `activate_zone`'s walk
and `flow.usable_abilities`, so a failing ability is not offered in the chooser.

## `computes` — a number with a name

Two drafts lost first. `"overkill = 0 - health@across"` was rejected outright —
*"I would really rather not have to parse assignments within strings."* The
positional `compute.1`/`compute.2` lost to DESIGN's own rule from two days
earlier: **a number is never positional.**

What landed is not a new concept at all but the format's fifth use of an idiom
it already had four times — `patterns`, `styles`, `tags` and `effects` are
global name→definition maps referenced by name; `computed_tags` is that shape
producing a boolean, and this is it producing a number.

```json
"computes": [
  { "key": "overkill", "from": "0 - health@across",
    "tooltip": "How far past death the unit across this one was struck." }
]
```

Three things fell out of the global node that the inline form did not have:

- **No assignment to parse.** The key is a JSON key; `from` is a pure expression.
- **Order is recovered at the use site.** JSON object key order is lost at parse,
  so a *map* of computes could never be evaluated top to bottom. The ability's
  `compute` is an ordered array, so a compute reading an earlier one is just
  "the line above ran first" — no dependency graph, no cycle check.
- **Documentation has a home**, and one declaration serves every card.

**The name is the point.** `sum:health@across` does not say why it is being
read; `overkill` does. That is most of the readability win, and it arrives with
no arithmetic at all.

**The cap is one operator** (`+ - *`, spaces required, no parentheses).
[25](25-derived-stats.md) proposed exactly this and then doubted it, since
Splendor needs a five-term sum. The doubt does not survive the corpus: n-ary
addition already has a spelling — successive `stat_gain` lines onto one stat.
What had no spelling was subtraction into a value slot, and that is one operator.

## Refused

- **Arithmetic in the action value slot** — [17](17-conditions-as-expressions.md)
  step 5, which would have deleted `:x:`. Without parentheses
  `sum:value@mine.red - 20 * count:wager` reads left to right, a rule a reader
  must be *taught* and cannot check; with them the format is a programming
  language. What step 5 wanted, `computes` provides in a place where the formula
  sits alone with a name on it.
- **Parameterised computes.** Splendor's five colours differ only by the word
  "white". The moment `computes` takes an argument it is a function.
- **`armor` as an engine word.** The left-hand column was already built: the
  `incoming` channel plus an ordered step gives that behaviour in one line on
  the tag, source-agnostic, so a spell that deals a strike meets armour without
  knowing anything about combat.
- **Overkill as an engine concept.** It needed nothing — a stat with no floor
  may go negative, which is why LoR declares `health` unfloored. What was
  missing was a *name*.

## What it did to the corpus

The Crew's `weigh` was the case this was built for and collapsed from sixteen
actions to three abilities of one action each — because what those sixteen lines
computed was an **or**, and an or is two abilities with a `when`. The corpus went
845 action strings to 776, `:x:` 15 to 10, and nothing is left with four `@`.
Runeterra's `overkilled` computed tag went too: it existed only to be a gate,
and the gate now reads `overkill >= 1`, which says the thing directly.

Where `:x:` survives it means *multiply* — never a disguised `if`.

## The bug it turned up

**A bare word in a value slot read as zero, silently.** `term()` does
`tonumber(p[i]) or default`, so `stat_gain:gold:teh_count` gained nothing and
said nothing. It had no validator branch at all, because `n` was the one
argument type `check_action` never checked. It does now, on the first term and
on every factor after an `x`, and a compute key is the one bare word that is
legitimate there.

## What is left over

- **A compute has no floor, and Splendor's pricing is built on one.** An
  unclamped `due` goes negative when the buyer holds more bonuses than the cost,
  and `stat_damage:t_white:due` would then *hand out tokens*. Shipped unclamped
  deliberately rather than inventing a spelling up front.
- **A compute cannot be an operand on the right of a comparison.**
  `predicate.compile` is pure and memoised across game loads, and letting it ask
  `G.compute_defs` whether a bare word is legitimate would end that.
  `overkill >= 1` works; `x >= overkill` is not writable.
- **[25](25-derived-stats.md) should be re-read, not built.** `compute` answers
  two of its three blocking questions by construction. The open one is whether a
  stat that keeps itself is worth anything once a formula can sit at its use site
  with a name on it.
- **`compute` and `when` live on an ability, and a card has six moments.** Lost
  Cities' scoring is in a `play`, so it can use neither, and its five
  `(sum - 20) x wagers` pairs are the last real `:x:` in the corpus. Same shape
  one level up: a tag grants `play` and `activate` and nothing else, which is why
  kingdom's trials share two blocks through the tag and still each carry their
  own `turn`. Both are "one question, one spelling" gaps rather than missing
  capability.
- **Splendor still cannot use a compute, and the reason is measured.** Every pair
  of lines in its pricing is `stat_set` to seed and `stat_damage` to subtract,
  and the clamp is the point. A compute is only ever *unclamped* arithmetic,
  which is why it fits The Crew and not Splendor.
