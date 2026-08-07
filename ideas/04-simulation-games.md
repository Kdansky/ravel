# Idea 04 — Cultist Simulator / Book of Hours, Turn-Based

> *Hard mode: Do the equivalent of Book of Hours or Cultist Simulator, but
> instead of real time, just have it be turn-based (1 second in CS = 1 turn, or
> whatever works for Book of Hours (maybe split a day into 10 turns, 6 day, 4
> night?))* — `IDEAS.md`

**Status:** not started · **Unblocked** — [00](00-foundation-scope.md) shipped, and it is smaller now than when this was written · **Size:** medium

Labelled "hard mode" in the ideas file. Having read the engine, I think it is
the *closest* of the four to already working, because ravel's core model —
cards, zones with slots, timers on a round wrap — is structurally the same model
Cultist Simulator uses. It needs roughly **one** new subsystem, not five.

---

## The mapping is almost one-to-one

| Cultist Simulator | Ravel today |
|---|---|
| Card with aspects (Lantern 2, Forge 3) | Card template with `card_stats` — **exists** |
| Verb (Work, Study, Dream) with slots | Grid zone with `grid: [n, 1]` slots — **exists** |
| Dragging a card into a verb slot | Slot targeting (`targeting.lua`, `place_in_slot`) — **exists** |
| A verb "running" for N seconds | A timer stat decremented on the round wrap — **expressible** |
| Timer completion producing cards | `on_turn` + a computed tag — **expressible** |
| Card decay / expiry | Same timer, ending in `destroy_self` — **expressible** |
| Drawing from a weighted deck | `contents` with counts gives weights by duplication — **exists** |
| Discovering a recipe you didn't know | The `reveal` overlay — **exists** |
| **Recipe matching** — which outcome fires for *this* set of cards | **missing** |

The last row is the whole project.

## Turns instead of seconds

Real time becomes a tick. Concretely:

- One **turn** = one `next_phase` through a two-phase loop: a `player_input`
  phase where you place and take cards, and an `automatic` phase that advances
  every running verb by one tick. That is the existing round machinery
  (`flow.settle`'s round boundary, `game/flow.lua:186`) doing exactly what it
  already does — `run_on_turn` fires each board card's `on_turn`, and a verb in
  progress *is* a board card.
- **Book of Hours' day/night** is a phase list: `dawn → day×6 → dusk → night×4`,
  with routing (`"next"` tables) picking which recipes are available. `round`
  is already a player stat, so "it is day 14" is free and displayable.
- **A "wait" button** is a card tagged `token` with
  `on_play: ["destroy_self", "next_phase"]`. No engine work — this is exactly
  the pass-card pattern already used by `draw_and_play` phases.

So the temporal model needs **no new engine code at all**. That is the pleasant
surprise here, and worth verifying with a throwaway game file before building
anything.

## The one new subsystem: zone recipes

A recipe is: *when the contents of this zone satisfy these requirements, after
N turns, consume some of them and produce some things.*

```json
{ "key": "work", "type": "grid", "grid": [3, 1], "label": "Work",
  "recipes": [
    { "requires": { "forge": 2, "count:tool@work": 1 },
      "turns": 4,
      "consumes": ["count:fuel@work:1"],
      "then": ["gain:wrought_iron", "gain_stat:insight:1"],
      "text": "You beat the metal until it yields." },

    { "requires": { "lantern": 1 },
      "turns": 3,
      "then": ["reveal:a_glimpse"] },

    { "requires": {},
      "turns": 6,
      "then": ["gain:a_little_money"],
      "text": "Menial labour. It pays." }
  ] }
```

Three design points, each of which is where this kind of system usually goes
wrong:

1. **Most specific wins.** Recipes are tried in file order and the first match
   fires — authors control priority by ordering, exactly like phase `next`
   routing already works (`game/phase.lua:57`). No scoring, no specificity
   algorithm. A catch-all recipe with empty `requires` goes last.
2. **`requires` is scoped to the zone.** `{"forge@work": 2}` means "the cards
   in *this zone* total forge ≥ 2" — the `@<zone>` scope, **which now exists**,
   along with `sum:`/`max:`, comparisons in either direction, and bounds that
   are themselves subjects. Reusing `predicate.meets_all` unchanged is the
   whole point: no second condition dialect (invariant 6).
3. **Running verbs are cards, not engine state.** When a recipe starts, create a
   card into the zone carrying `card_stats: {timer: 4}` and an `on_turn` of
   `["lose_stat:timer:1"]`, plus a computed tag `{"done": {"stat": "timer",
   "equals": 0}}`. The tick machinery, the snapshot, undo, and the renderer all
   already handle cards. **Do not add a "pending recipe" list to game state** —
   it would have to join the snapshot protocol (ARCHITECTURE invariant, "if you
   add stateful storage anywhere else") and it would be a second kind of thing
   the engine has to think about. Invariant 7, again: *when in doubt, decks and
   cards.*

### What genuinely must be added to the engine

- `zones.check_recipes(zone_id)` — called from `settle`, after any card enters
  or leaves a zone that declares recipes. Finds the first matching recipe,
  creates the in-progress card, and moves the consumed inputs out.
- ~~One action, `consume:<subject>:<n>`~~ — **already exists.** `destroy`
  generalised from "empty a zone" to a scope expression, so
  `destroy:each.mine.fuel` is the selective form this asked for, and
  `destroy:random.mine.fuel` takes exactly one. No new verb needed.
- Recipe fields in `validate.lua`'s known-field tables, plus checks that
  `then` ops exist and `requires` subjects are real.

That is maybe 120 lines. Everything else on this page is content.

## Why this is a good project to actually do

- It is the only idea here that produces a game with *no analogue* in the
  shipped set, so it stress-tests the engine in a direction the board games
  don't (many small zones, constant card churn, no win condition for a long
  while).
- It has an extremely cheap proof of concept: **write a game file with three
  verbs and a hand-rolled fake recipe** (a card the player plays manually to
  represent "start working") and see whether the loop is fun before writing
  `check_recipes`. If the turn-based translation of CS isn't fun — and it might
  not be; CS's tension partly *is* the real-time pressure — you find out for the
  cost of a JSON file.
- Its output is the strongest evidence for the `IDEAS.md` thesis that a
  JSON-driven engine can host genuinely different genres.

## Open questions worth deciding before building

- **Does turn-based CS lose the game?** In CS, timers running out while you
  scramble is the core loop. Turn-based, you always have time to think. Possible
  answer: a per-turn action budget (`plays` already exists and already resets
  per phase — `"ends_after": 2` on the phase gives you two actions per turn for
  free). Prototype this early.
- **Board size.** CS's table is a free 2D surface; ravel has grid slots. Slots
  are probably *better* for a turn-based version (legible, no lost cards), but
  it changes the feel from "workspace" to "board". Accept it.
- **Book of Hours vs Cultist Simulator.** BoH is much larger content-wise
  (hundreds of items, a mansion to map) and much gentler mechanically. CS is the
  smaller, sharper target. **Start with a CS-like**; BoH is the same engine with
  ten times the content, and content is the expensive part.
