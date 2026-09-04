# 03 — A move out of a stock

*From animating Puzzle Strike, where a crash — the most important thing that
happens in the game — turned out not to be a move at all.*

**Not started. One word to agree, and it is a rules change, so it waits on
consent.**

A crash is written like this:

```json
"stat_set:crashed@mine.player:sum:value@target",
"fill:enemy.gem_pile:gem_1:sum:crashed@mine.player",
"stat_damage:stock@bank.gem_1:sum:crashed@mine.player",
```

Gems appear in the other player's pile out of nowhere and, on a separate line
with nothing tying it to the first, the bank's count goes down. Two statements
for one event.

## Why it is written that way, and why that part is right

**A supply keeps one entity per kind.** `contents: ["gem_1:64"]` yields *one*
card stamped with a `stock` of 64; the other sixty-three gems are a number
written on it. So there is no card in the bank to move — taking one would move
the card that *is* the stock.

That is deliberate and load-bearing, and [ARCHITECTURE](../ARCHITECTURE.md)'s
"Supply zones" section already says so. The promise that makes it safe is that a
supply's cards are *interchangeable*, enforced by nothing being able to point at
one: `targeting.candidates` drops them (`targeting.lua:233`), `reactions.placed`
refuses them (`reactions.lua:56`). A rule that could aim at a particular gem
would be able to find out there is only one. The validator refuses `draw_from`
out of a supply for the same reason (`validate.lua:982`), along with `reach` and
`refill_from`: a stock has no order, so it has no top and no way to run out in
one.

So `fill` plus a `stock` cost is not a workaround anybody invented in a hurry. It
is the spelling the format has, and buying uses it too:

```json
"cost":   { "buys@mine.player": 1, "stock@self": 1, "money@mine.player": "price@self" },
"action": ["fill:mine.discard:@self:1"]
```

## What is actually wrong

**The two halves are two statements, and nothing holds them together.**

- **The engine cannot know they are one event.** That is what left a crash with
  no animation: the gems had never been anywhere, so there was nothing to travel
  from. [02](02-between-two-states.md) now guesses the origin by looking up the
  supply that stocks the kind, which works and is a guess — the right layer to
  guess in, but a guess.
- **A game file can put them out of step and only find out by counting.** There
  is no check that a `fill` of a stocked kind is matched by a decrement, because
  there is nothing saying they belong to each other.
- **It reads as creation when it is a transfer.** An author reading
  `fill:enemy.gem_pile:gem_1:3` is told a gem appeared. Where it came from is on
  the next line, if it is anywhere.

Counted in the corpus: **96 `fill` sites in `puzzle_strike.json` sit beside a
bank decrement**, and every one of them is a component coming out of the box.

## The word: `take`

```
take:<supply scope>:<zone>:<n>[:top|bottom]
```

**It is `move`, for a source that counts instead of keeps.** That is the whole of
it, and the documentation has to lead with that sentence: a card comes out of the
box and goes somewhere, the box has one fewer, and it is a different verb *only*
because `move` and `draw_from` aimed at a supply would pick up the one card
standing for the whole stack.

```json
"take:bank.gem_1:enemy.gem_pile:2"
```

Buying becomes:

```json
"cost":   { "buys@mine.player": 1, "money@mine.player": "price@self" },
"when":   ["stock@self >= 1"],
"action": ["take:@self:mine.discard:1", "stat_gain:bought@mine.player:1"]
```

**What the first argument names is the exception worth stating twice.** In
`move:<scope>:<zone>` the scope names *what moves*. In `take` it names *what it
comes out of* — the shelf, not the goods. `bank.gem_1` is the `<zone>.<tag>`
scope that `stock@bank.gem_1` already uses, and `@self` is a shelf acting on
itself. That inversion is the argument for a separate verb rather than a flag on
`move`: two spellings that read alike and mean different things would be worse
than two words.

**Behaviour**, so there is nothing left to decide at the keyboard:

| | |
|---|---|
| stock is enough | take `n`, stock down by `n`, `n` real cards created in the destination |
| stock is short | take what is there and stop. An empty box is a legal state — Puzzle Strike counts it, as `count:spent@bank` over a computed `spent` tag |
| stock is zero | nothing happens, and nothing is said. Not an error |
| source is not a supply | content error, and a validator warning that names `move` |
| destination is a supply | it collapses back to stock, exactly as `move_card` already does — so `take:bank.gem_1:other_bank:2` is legal and moves a number |
| what the presentation sees | `move`, once per card, with the shelf as its origin. The animation stops being a guess |

**`fill` stays.** It means "put a copy of this card here", and 63 of Puzzle
Strike's uses and all 157 of Codex's are exactly that — building a starting deck
out of nothing, where nothing is the honest answer. `take` means "move one out of
that box". Two questions, two words, which is [13](13-one-name-one-thing.md)'s
rule working rather than being bent.

## The price, stated plainly

**Buying loses a line and gains a line.** `stock@self: 1` as a cost is doing
three jobs at once: it checks the stack is not empty, it pays, and it is the only
record that the chip came from there. Splitting it into a `when` and a `take` is
one line longer and says three separate true things instead of one convenient
one. An author who liked the old form is entitled to think this is worse; the
answer is that the old form cannot animate and cannot be checked.

`take` does *not* gate the ability it sits in — an action list is not a legality
test, which is what `when` is for. It fails cleanly rather than half-doing
anything, so a missing `when` costs a silent no-op and not a corrupt board.

## The neighbour it should be built with

[28](28-a-zone-by-its-parts.md) item 2 is the other half of this and is already
ranked: **where a destroyed card goes**. `zones.add` reclaims a card *into* a
supply and nothing reclaims the other way, so a finite box has to name the bank
at every site that removes a component. Together the pair is symmetric and the
box is closed:

- **in** — `move` into a supply, which already collapses to stock;
- **out** — `take`;
- **gone** — `destroy`, which should return to the box rather than the void.

One pass over supplies rather than three, and the decision 28 is waiting on —
what happens when two supplies stock the same kind — is the same decision `take`
needs for a scope that resolves to more than one shelf.

## A smaller thing found on the way: `move` has no count

`destroy` takes one (`scope n?`) and `move` does not (`scope zone pos?`), which
is why one Puzzle Strike card spells "send two of my gems over there" as

```json
"destroy:mine.gem_1:2", "fill:enemy.gem_pile:gem_1:2"
```

Both piles are real cards. Nothing here needs a supply, a stock, or `take` — it
is a plain move of two cards, written as a death and a birth because the verb
that moves cards cannot be told how many. It loses the animation for the same
reason a crash did, and it loses the cards' identity as well.

**`move = "scope zone n? pos?"` is a one-word change to `SPEC` and one `amount()`
call in the handler**, it needs no new vocabulary, and it should probably go in
first — it is cheaper than `take`, it fixes a real site today, and it makes the
`take` proposal smaller by taking a case off it.
