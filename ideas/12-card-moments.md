# 12 — A card is a list of moments

**Shipped.** `play` · `activate` · `challenge` · `receive` · `turn` · `start`,
and `pick` turned out not to be one.

## The design

**The `activate_` prefix disappeared entirely**, and with it a convention nobody
documented: `cost`/`activate_cost`, `target`/`activate_target`,
`on_play`/`on_activate` were three instances of "the same thing, but for the
board ability" spelled as a naming trick. Structure says it instead.

`requires` became `challenge.needs` and `accepts` became `receive.needs`, so
**`needs` is the only word for a condition that gates** and the block it sits in
says what it gates. `on_pass`/`on_fail` became `challenge.pass`/`challenge.fail`
— inside `challenge` the prefix is noise, and the three fields that only ever
work together now live in one block that cannot be half-written.

Two things were gained rather than moved. `phases` split per moment, so
"playable in main, activatable any time" became sayable. And `irreversible`
became the tag `no_undo`: a boolean quality is a tag, not a field, and it was
one field serving two moments.

**Blocks are uniform, including the boring ones.** `"turn": { "action": [...] }`
is three characters longer than `"on_turn": [...]`, and buys one rule to learn
instead of "subdocuments, except the short ones", plus room for `turn.needs`
("only while standing") to arrive as a field rather than as another top-level
name.

**It shipped one moment per commit**, through a single table in
`declaration.parse` mapping authored block fields to the flat names the engine
already read — so no read site changed and each moment moved on its own. The
flat name is *refused* once its moment has moved, driven by the same table, or
it keeps working by accident and the accidental alias is the thing being
removed.

## `challenge` is the odd one out, deliberately

Six blocks answer **when**. `challenge` answers **what test**, and is reached by
`resolve_challenge` from any action list. That reads as an inconsistency, and
the alternative is worse: kingdom's crisis cards resolve their challenge when
*played*, and on failure stay on the board to be *activated* and tried again.

```json
"challenge": { "needs": ["food >= 4"], "pass": [...], "fail": ["move_to:board", ...] },
"play":      { "action": ["resolve_challenge"] },
"activate":  { "action": ["resolve_challenge"] }
```

One test asked from two moments. Inside `play` it would be written twice and
kept in step by hand. A block groups things that belong together, and *when* is
only the commonest reason they do.

## `pick` was a duplicate of `play`

An overlay is a pending choice, and a choice is resolved by *playing* one of the
cards offered — so `flow.pick` was a second path doing what `play_card` does,
and the phase's `zone` already bounds what may be played. Deleting it also
removed the `page`/non-page split that decided whose actions ran, a phase-level
`on_pick`, and a footgun where a card's own actions were silently ignored in a
non-page overlay.

Three rules that had lived inside `flow.pick` became rules of their own, and all
three are better said out loud:

- **An overlay pops before the card's actions run**, so a chained reveal lands
  on top rather than burying the overlay it came from.
- **A card still lying in the offer afterwards is spent.** A read page vanishes;
  one whose actions moved it stays where it went.
- **A choice costs nothing.** Cost, needs and targeting are skipped, because
  they describe playing that card out of a hand later — castle deals *buildings*
  into its draft, and paying to choose one charged the build price twice. The
  golden trace caught exactly that.

What a phase's `on_pick` said is now the offer zone's, granted with `applies`.
That needed one honest change: two different offers sharing one zone had to
become two zones, because a zone grants to everything lying in it and an ending
card must not inherit a draft's rule.

## The consequence nobody would notice until it broke

**Granting works at the block level.** A zone hands its contents a whole
`activate`, not a stray cost. Field-level granting could mix a zone's action
with the card's own cost — possible before, wanted by nobody — and block
granting is both simpler and what DESIGN already described: *a creature lying in
a graveyard that grants "return to hand" offers that, not the tap ability it had
on the board.*

## Refused

- **A third level.** `play.cost.mana` is deep enough: a block holds fields, and
  a field holds a value or a flat map.
- **Blocks for things that are not moments.** `text`, `tooltip`, `asset`,
  `tags`, `card_stats` are what a card *is*, not something that happens to it.
- **`on_` anywhere.** The prefix says "this is an event handler", which is what
  being inside a moment already says.
