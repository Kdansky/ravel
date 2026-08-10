# 12 — A card is a list of moments

**Status:** in progress — `challenge` shipped (`251b48f`) · **Size:** large, and
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
  "receive":   { "needs": { "value@target": { "at_least": "value@self" } } },
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
| `on_pick` | `pick.action` | |
| `exhausts`, `moves` | `activate.*` only | they mean nothing about playing a card, and now cannot be written there |
| `irreversible` | `play.*` and `pick.*` | the two moments it applies to, duplicated because both genuinely have it |
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

## Migration

~650 field occurrences across ten games. Two of the files are generated, so
they regenerate; the other eight are rewritten by a script.

**The golden traces are the proof.** A faithful migration changes no behaviour,
so every recorded transcript must come out byte-identical — and `castle.log` and
`kingdom.log` cover the two densest games, which is why this can be done a moment
at a time and still be checked.

Order, one commit each:

1. ~~`declaration.parse` reads the new shape and nothing else~~ — **done**, and
   the clean break held: the flat name is an error, not a fallback.
2. ~~`challenge`~~ — **done.** 22 cards across five games.
3. `receive` (`accepts`, on cards *and* zones), then `play`, then `activate`,
   then `turn` / `pick` / `start`. Each adds one line to `MOMENTS`, one entry to
   `validate.FIELDS` and one block to `SCHEMA.json` — which the schema test then
   holds to the engine in both directions, and which is what makes a rename this
   wide safe to do piecemeal.
4. `cards.behaviour` resolves blocks; tag defs already flatten through the same
   table, so their vocabulary cannot drift from a card's.
5. Golden traces must be unchanged. If they are not, the migration is wrong —
   not the traces.

## Refuse

- **A third level.** `play.cost.mana` is deep enough. A block holds fields, and
  a field holds a value or a flat map.
- **Blocks for things that are not moments.** `text`, `tooltip`, `asset`,
  `tags`, `card_stats` are what a card *is*, not something that happens to it.
- **`on_` anywhere.** The prefix exists to say "this is an event handler", which
  is what being inside a moment already says.
