# 21 — Lost Ruins of Arnak

**Built and playing**, hand-written, no generator:
[game/games/arnak.json](../game/games/arnak.json), with
[ideas/arnak/rules.md](arnak/rules.md) as the rulebook it was read out of and
[ideas/arnak/design.md](arnak/design.md) as the record of what was built —
rule-by-rule mapping, every divergence with its reason, and the two words the
engine turned out not to have.

The research called it right: **zero new engine primitives, and the largest
content bill of the three deckbuilders.** Nothing in `game/` was touched.

## What the research found, kept because it corrected the framing

Three things the stub asserted that the rulebook does not say. They are kept
here because each one changed what kind of problem this was:

1. **The resources are Coin, Compass, Tablet, Arrowhead and Jewel** — not
   gold/wood/stone/obsidian (rules.md §3).
2. **There is no "gate" component.** The word does not appear in the rulebook.
   What opens new worker-placement spaces is **Discover a New Site**: pay a
   region cost plus a position cost to flip one of a fixed number of
   pre-printed, mostly-hidden board positions face up (§7).
3. **There is no personal exploration board and no terrain-crossing movement
   cost.** One shared island, fixed in size from setup, with a bounded number of
   printed-but-undiscovered positions that are *revealed*, never created (§8).
   That is a fixed-size `grid` with hidden cells, which is a different shape
   from Mage Knight's map growing without bound — and it is why
   [19](19-mage-knight.md) has a real gap here and Arnak does not.

## The decision that carried the build

**Worker placement is two shipped idioms, not a missing one.** Exhaust the
*space*, not the worker: a site is a card whose dig ability costs
`{ "exhaust": 1, … }`, and the round boundary readies every one of them at
once. The other gate — *have I an archaeologist to send* — is an ordinary
capped counter stat on the player. The two are independent, which is exactly
what the printed rule needs, and modelling it the other way round (exhaust the
worker token) answers only one of them: `predicate` has no subject that reads a
card's own exhaustion back as a condition, so "is this space free" would have
had nowhere to be asked.

Its cost is authoring weight rather than engine work. A `cost` is declared
statically, so *Dig at a Site* cannot be one parametrised action across nineteen
sites — it is one small card per site space, each with its own printed price.
That is the 1:1 mapping the physical game already uses, not a workaround.

## Still open

- **Three and four players.** The file is written for two, where the blocking
  tiles put exactly one space at each starting site. More seats means the second
  spaces exist, which is one extra card per site and no new shape.
- **The Travel Hierarchy** (rules.md §13.1) is collapsed to a single `travel`
  number. `pays_for` on the stats section expresses the real ordering exactly,
  one line per icon, the day the ordering is known.
- **The research track branches** in the printed game and is a straight line of
  six rows here. Branching is content — one card per position, one ability per
  edge — and was left out for size, not because anything refuses it.
- **Two words the engine does not have**, both recorded in
  [arnak/design.md](arnak/design.md) rather than acted on:
  *dealing into a named cell*, which is why the card row is two zones sized by
  arithmetic instead of one with a staff crossing it; and *who spent a card's
  exhaust*, which is why the Fear-from-a-guarded-site rule is a counter on the
  player rather than a fact about a figure.
