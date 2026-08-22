# 12 — A card is a list of moments

**Status:** shipped — all seven moments, and `pick` turned out not to be one · **Size:** large, and
almost all of it is migration · **Depends on:** [11](11-styles-as-tags.md) for
`color`

**One moment per commit.** The mechanism is a single table in
`declaration.parse` mapping authored block fields to the flat names the engine
already reads, so no read site downstream changes and each moment moves on its
own. An entry joins that table only when its moment migrates: a block the parser
accepts while the validator rejects it is worse than no block.

**No migration aids, and no old syntax.** Every game is in this repository, so
there is nothing to be compatible with. The flat name is *refused* once its
moment has moved — otherwise it keeps working by accident, the engine reading
`def.requires` whichever way it arrived, and an accidental alias is the thing
being removed. That check is driven by the same table, so there is no second
list to keep in step.

> *cost, activate_cost, target, activate_target, and so on. I think cards should
> have two subdocuments: activation / play, and then have duplicate structures in
> there (cost, target, etc). This also gives a spot for "on_play", it's just the
> "action" of the play section, and activation is the action of the activation
> section. Similar for on_fail, on_pass, etc. Either duplicated for both
> activation and play, or only available in one (and then obviously so)*

---

## The shape

```json
{
  "key": "fireball",
  "text": "Fireball",
  "tooltip": "Three damage.",
  "tags": ["spell", "fire"],
  "card_stats": { "uses": 3 },

  "play": {
    "cost":   { "mana": 3 },
    "needs":  { "count:altar": 1 },
    "target": { "type": "card", "count": 1, "owner": "enemy" },
    "phases": ["main"],
    "action": ["lose_stat:hp@target:3"],
    "irreversible": true
  },

  "activate": {
    "cost":    { "focus": 1 },
    "needs":   { "uses@self": 1 },
    "target":  { "type": "slot", "count": 1 },
    "phases":  ["main"],
    "action":  ["move_to:target:taken", "next_phase"],
    "exhausts": false,
    "moves":   ["line_ortho"]
  },

  "challenge": { "needs": { "might": 8 }, "pass": [...], "fail": [...] },
  "receive":   { "needs": ["value@target >= value@self"] },
  "turn":      { "action": [...] },
  "pick":      { "action": [...], "irreversible": true },
  "start":     { "zone": "table", "slot": 1 },
  "outcome":   "victory"
}
```

**The `activate_` prefix disappears entirely**, and with it the convention
nobody documents: `cost`/`activate_cost`, `target`/`activate_target`,
`on_play`/`on_activate` were three instances of "the same thing, but for the
board ability" spelled as a naming trick. Structure says it instead.

## What this settles, field by field

| Today | Becomes | Why |
|---|---|---|
| `on_play` | `play.action` | the moment's action, as proposed |
| `on_activate` | `activate.action` | same |
| `cost` / `activate_cost` | `play.cost` / `activate.cost` | one word, position disambiguates |
| `target` / `activate_target` | `play.target` / `activate.target` | same |
| `needs` | `play.needs` | a gate on playing, which is what it always was |
| **`requires`** | **`challenge.needs`** | see below |
| **`accepts`** | **`receive.needs`** | see below |
| `on_pass` / `on_fail` | `challenge.pass` / `challenge.fail` | inside `challenge` the `on_` prefix is noise |
| `on_turn` | `turn.action` | |
| `exhausts`, `moves` | `activate.*` only | they mean nothing about playing a card, and now cannot be written there |
| `irreversible` | the tag `no_undo` | a boolean quality is a tag, not a field — and it was one field serving two moments |
| `phases` | `play.phases`, `activate.phases` | **a gain**: today one field gates both, so "playable in main, activatable any time" cannot be said |
| `auto_play`, `to_zone`, `to_slot` | `start.zone`, `start.slot` | the same prefix disease, one letter shorter. Presence of `start` replaces the `auto_play` flag |
| `color` | a style | [11](11-styles-as-tags.md) |

## `needs` vs `requires` — one word, and position says which

This was called out as *exceptionally* unclear, and the reason is that the two
names describe the same thing at different moments:

- `needs` gates playing the card.
- `requires` is read by the `resolve_challenge` action, which branches to
  `on_pass` or `on_fail`.

Nothing in either *word* says that. So: **`needs` is the only word for "a
condition that gates", everywhere**, and the block it sits in says what it
gates. `play.needs` gates the play; `challenge.needs` decides pass from fail.
The three fields that only ever work together — `requires`, `on_pass`,
`on_fail` — now live in one block that cannot be half-written, which the
validator currently has to check by hand.

## `pick` was not a moment either, and it went away

The last block turned out to be a duplicate of `play`. An overlay is a pending
choice, and a choice is resolved by *playing* one of the cards offered — so
`flow.pick` was a second path doing what `play_card` does, and the phase's
`zone` already bounds what may be played.

Deleting it removed more than a block: `flow.pick`, the `page`/non-page split
that decided *whose* actions ran, a phase-level `on_pick`, and a footgun where a
card's own actions were silently ignored in a non-page overlay.

Three rules that lived inside `flow.pick` had to become rules of their own, and
all three are better said out loud:

- **An overlay pops before the card's actions run**, so a chained reveal lands on
  top rather than burying the overlay it came from.
- **A card still lying in the offer afterwards is spent.** A read page vanishes;
  one whose actions moved it stays where it went.
- **A choice costs nothing.** Cost, needs and targeting are skipped, because they
  describe playing that card out of a hand later — castle deals *buildings* into
  its draft, and paying to choose one charged the build price twice. The golden
  trace caught exactly that.

What a phase's `on_pick` used to say is now the offer zone's, granted with
`applies` — behaviour belonging to the place, which is the rule
[DONE](DONE.md) already records for piles. That needed one honest change: two
different offers sharing one zone had to become two zones, because a zone grants
to everything lying in it and an ending card must not inherit a draft's rule.

## `challenge` is not a moment, and that is deliberate

Six of the seven blocks answer **when**: play, activate, receive, turn, pick,
start. `challenge` answers **what test**, and is reached by the
`resolve_challenge` action from any action list at all.

That reads as an inconsistency and is worth stating out loud in the docs — but
the alternative is worse. Kingdom's eleven crisis cards resolve their challenge
when **played**, and if it fails the card stays on the board to be **activated**
later and tried again:

```json
"challenge": { "needs": { "food": 4 }, "pass": [...], "fail": ["move_to:board", ...] },
"play":     { "action": ["resolve_challenge"] },
"activate": { "action": ["resolve_challenge"] }
```

One test, asked from two moments. Inside `play` it would have to be written
twice and kept in step by hand. So the odd one out earns its place: a block
groups things that belong together, and *when* is only the commonest reason
they do.

## `accepts` — the question is *whose* condition it is

`accepts` sits on a **destination** and is asked about an **arriving** card,
with `@self` bound to the destination and `@target` to the arrival. That
inversion is the whole confusion, and no rename of a bare field fixes it,
because the field name has nowhere to say *when*.

`receive.needs` does: **"to receive a card, this needs…"** reads in the right
direction and puts the arriving card where `@target` already points. Zones take
the same block, exactly as they take `accepts` today.

## Uniform blocks, including the boring ones

`turn` and `pick` carry only an action, so `"turn": { "action": [...] }` is
three characters longer than `"on_turn": [...]`. Take the cost:

- One rule to learn instead of "subdocuments, except the short ones".
- Room to grow. `turn.needs` ("only while standing") and `pick.needs` are both
  plausible, and today they would each arrive as another top-level field.

## The consequence nobody would notice until it broke

**Tag definitions must move with cards.** A tag def is a mixin carrying
`on_activate`, `activate_target`, `activate_cost`, `exhausts`, `phases` — and a
zone hands those to its contents with `applies`. `cards.behaviour(entity,
field)` resolves them field by field.

Under blocks, granting works at the **block** level: a zone grants a whole
`activate`, not a stray cost. That is a semantic change, and it is the one
`DESIGN.md` already describes:

> *a creature lying in a graveyard that grants "return to hand" offers that, not
> the tap ability it had on the board.*

Field-level granting could mix a zone's action with the card's own cost, which
is not a thing anyone wants and is currently possible. Block granting is both
simpler and closer to the documented intent.

## Refuse

- **A third level.** `play.cost.mana` is deep enough. A block holds fields, and
  a field holds a value or a flat map.
- **Blocks for things that are not moments.** `text`, `tooltip`, `asset`,
  `tags`, `card_stats` are what a card *is*, not something that happens to it.
- **`on_` anywhere.** The prefix exists to say "this is an event handler", which
  is what being inside a moment already says.
