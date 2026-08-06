# Foundation: Stats Live on Cards

**Status:** not started · **Blocks:** 01, 02, 04 · **Size:** small–medium (~300 LOC, three files)

Not one of the ideas in `IDEAS.md`. It is the prerequisite all four of them
turned out to share, and the shape it should take is: **delete the player
entity. The player is a card.**

---

## The current model is incoherent, and one shipped game already routes around it

Today there are two different rules for the same stat, and they disagree:

| | Rule | Where |
|---|---|---|
| **Read** | Sum the stat across **every entity in the game** | `entity.sum_stat` (`game/entity.lua:30`) |
| **Write** | Give it all to the **first** entity that happens to hold the stat | `actions.stat_holder` (`game/actions.lua:57`) |

`gain_stat:gold:1` writes to one entity; `{"stat": "gold", "at_least": 5}` reads
the total of all of them. Those only agree under an invariant nobody wrote down
and nothing enforces: **exactly one entity may hold each player-facing stat.**

Two consequences worth seeing before designing anything:

**1. `castle.json` already implements player-as-card.** It has no `setup.player`
at all. Its stats — `hp 20, gold 20, morale 5, defense 0, food 0` — sit in
`card_stats` on the `throne_room` template (`game/games/castle.json:27`), which
is `auto_play`ed onto the board at slot 13 and tagged `hero`. The player entity
in that game holds nothing but `round` and `plays`. The best-developed shipped
game invented this design on its own and the engine's global-sum semantics let
it work by accident. That is about as strong a signal as this kind of question
ever gives you.

**2. The undocumented invariant is already producing a real bug.** In
`castle.json`, a watchtower's `on_play` is
`["move_to:board", "gain_stat:defense:2"]` — the +2 lands on the throne room as
a running total. Buildings can be reduced to 0 hp (there is a `ruined` computed
tag for exactly this, `game/games/castle.json:18`) and nothing ever removes
their contribution. **A ruined watchtower defends your castle forever.** That is
not a stats-plumbing nit; it is a live gameplay bug, and it exists because
"defense" is a global number rather than a property of the cards that produce it.

---

## The design

### Entity kinds go from four to three

`{ player, zone, slot, card }` → `{ zone, slot, card }`. There is no player
entity, no `kind = "player"`, no `flow.player()` helper, no `setup.player`
special-parsing branch, and no `stat_holder` scan. A player is a card with
stats, which means it snapshots, undoes, renders, gets a detail view, gets a
tooltip, can be hot-edited with `edit`/`dump`, and can be targeted — all for
free, because every one of those already works for cards.

This is invariant 7 (*when in doubt, decks and cards*) applied to the one thing
in the engine that wasn't.

### Finding the player card

A reserved tag:

```json
{ "key": "throne_room", "tags": ["building", "hero", "player"],
  "card_stats": { "hp": 20, "gold": 20, "morale": 5 },
  "auto_play": true, "to_zone": "board", "to_slot": 13 }
```

If a game declares no template tagged `player`, **the engine injects one** from
`setup.player` into a hidden `system` zone. That is not a new mechanism — it is
exactly what `declaration.parse` already does for the built-in `reveal` zone and
`reveal` phase (`game/declaration.lua:159-168`), including the "a game may claim
the key to override the presentation" escape hatch.

So the same mechanism spans the whole range: an invisible stat bag for
`kingdom.json`, a visible hero card on the board for `castle.json`, a
Hearthstone hero portrait, or four party members.

### Engine bookkeeping

`round` is a property of the *game*, not of a player — with two players you must
not get two round counters. So one more injected card, tagged `system`, in the
same hidden zone, holding `round` and `turn` (which seat is active). `plays` is
per-player and moves onto the player card, where it always belonged.

Be honest about the trade: this is two injected cards where there was one player
entity. The win is not fewer objects, it is **fewer kinds and one coherent rule**
— both injected cards are ordinary cards obeying every existing invariant,
whereas `kind = "player"` was a thing with its own rules everywhere it appeared.

### Subjects resolve to an entity set

One vocabulary (invariant 6), extended with an optional scope suffix in the
colon-and-`@` style actions already use. **The scope is a plain name — a zone
key or a tag** — which is simpler than the seat-based `@me`/`@opponent` this
document originally proposed, and it makes the common case trivial: a tag
carried by exactly one card *is* a unique reference to that card.

```
insight@player        -- the one card tagged "player"
hp@self               -- the acting card itself
sum:defense@board     -- sum a stat over every card in a zone
max:rank@tableau_3    -- highest value in a zone
count:lore@holdings   -- unchanged in meaning, now explicit about where
gold                  -- no scope: unchanged global total, so old files still work
```

`predicate.parse_subject` is one pure function; `predicate.entities_in_scope` is
the single place that turns a name into a set of entities. `predicate.total`,
`actions.amount` (`game/actions.lua:49`) and cost payment all route through
them, so reads and writes finally resolve to the *same entity*.

Two rules keep the name space honest, **both already enforced by the validator**
(shipped ahead of the resolver, so every game is conflict-free before it lands):

- A tag and a zone may never share a name — a scope that could mean either is
  refused at load, not resolved by a precedence rule nobody would remember.
- `self` and `all` are reserved; neither can be expressed as a tag. `player` is
  deliberately *not* reserved — it is ordinary content, which is the whole point.

### Quantifiers: which member of the set, and how many

A scope naming a tag usually matches *several* cards, and "three followers have
hp" does not say what happens to them. Three genuinely different intents, needed
for **both costs and effects**:

```
hp@each.follower      -- every follower, individually
hp@any.follower       -- the set as a pool; the engine satisfies it however it can
hp@random.follower    -- one member, chosen by the seeded RNG
hp@target             -- the cards the player already chose for this card
hp@follower           -- bare: same as any (and the same as today's global total)
```

`.` separates the quantifier because **`:` cannot** — `actions.parse`
(`game/actions.lua:30`) splits action strings on colons, so `hp@each:follower`
would arrive as two arguments. Neither `.` nor `@` appears in any of the 63
zone and tag names across the shipped games, so both are free.

| Quantifier | Affordable when | Paying a cost | Applying an effect |
|---|---|---|---|
| `any` (default) | total over the set ≥ n | drain members in id order until n is paid | lands on the first member |
| `each` | set non-empty **and** every member ≥ n | every member pays n (total n × count) | applies to every member |
| `random` | as `any` | as `any` | lands on one member, seeded |
| `target` | every chosen target ≥ n | every target pays n | applies to every target |

**`each` over an empty set fails — it is not vacuously true.** Otherwise
`"cost": { "hp@each.follower": 1 }` would be *free* when you have no followers,
which is exactly backwards. `sacrifice:` already works this way.

**`target` needs no new interaction.** The card's existing `target` /
`activate_target` spec already asks the player to choose; the cost and the
effect just refer to what they chose. "Choose which follower takes the hit" is
`activate_target: { tags: ["follower"], count: 1 }` plus
`lose_stat:hp@target:1` — no cost-time prompt to invent.

**Determinism holds.** `any` drains in entity-id order (oldest first, matching
`sacrifice:`); `random` uses the seeded RNG. Both reproduce from a seed.

### This deletes three actions

Once scopes carry quantifiers, three bespoke verbs are just special cases:

```
damage_random:beast:hp:2   →  lose_stat:hp@random.beast:2
gain_target_stat:hp:2      →  gain_stat:hp@target:2
lose_target_stat:hp:2      →  lose_stat:hp@target:2
```

Worth doing as a follow-up commit, not the same one — keep the old verbs as
aliases until the shipped games migrate, then delete them. The net effect is a
*smaller* action vocabulary than before the feature, which is the sign the
abstraction is the right one.

`sacrifice:<tag>` stays as it is for now: it spends whole cards rather than a
stat, which is a different axis, and it already means "any n, oldest first".

### The party case falls out

A party of characters is N cards in a `party` grid zone, each tagged `player`:

- Per-character stats — ordinary `card_stats`.
- Targeting a character — ordinary card targeting, already works.
- A character dying — `zones.destroy_card`, already works; the `ruined`/`damaged`
  computed-tag pattern already works.
- "Does the party have 8 might between them" — `sum:might@party`.
- "This character pays from her own mana" — `"cost": { "mana@self": 2 }`.

No new engine concept is required for any of it. That is the test of whether the
model is right, and it passes.

### Aggregates get better, not worse

Castle's defense becomes a property of the buildings that provide it:

```json
{ "key": "watchtower", "card_stats": { "hp": 4, "hp_max": 4, "defense": 2 },
  "on_play": ["move_to:board"] }

{ "requires": { "sum:defense@board": 3 } }
```

Destroy the watchtower and the defense goes with it. The bug above stops being
possible to write, rather than being fixed once.

---

## Migration

- `setup.player` stays as sugar and desugars into the injected player card, so
  `demo`, `road`, `tower`, `kingdom` and `starter_cyoa` change by zero bytes.
- `castle.json` adds `"player"` to `throne_room`'s tag list. One word.
- Converting castle's defense to `sum:defense@board` is a separate, optional
  commit — and it is the regression test that proves the model works.

## Work plan

1. `predicate.parse_subject` / `entities_in_scope` — pure, unit-testable with no
   game loaded. Tests first.
2. `predicate.total` rewritten over them; add `sum:` and `max:`.
3. Injected `player` + `system` cards and the hidden `system` zone in
   `declaration.parse`, mirroring the `reveal` injection.
4. Delete `kind = "player"`: `flow.init`'s player construction (`game/flow.lua:244`),
   `flow.player()`, `actions.stat_holder`.
5. Route `actions.amount`, `change_stat`, `cards.can_afford` and `flow.pay`
   through the resolver.
6. `render.draw_stats` (`game/render.lua:608`) reads the active player card
   instead of `entity.sum_stat`.
7. `validate.lua`: unknown scope, `@me` in a game with no player card, a stat
   written by an action that no entity can hold. One `CASES` entry per message
   (`tests/run.lua:791`).

## Risks

- **A stray action can now destroy the player.** `destroy:hand` sweeping a
  player card would be bad. The injected default lives in a hidden `system` zone
  nothing targets; a game that puts its hero on the board is choosing that, and
  "your hero dies and you lose" is a feature. Do not add a `protected` flag until
  something actually needs one.
- **Silent behaviour change.** The bare-subject meaning shifts from "global sum"
  to "the player's card". For every shipped game those are identical, *because*
  of the one-holder invariant — but prove it: script a fixed sequence through
  `castle.json` and `kingdom.json` and diff the full state dump before and after.
- **Grammar creep.** `@` is the only new punctuation, and a new kind of scope is
  a new *word* after it, never new syntax.

## Done when

- No `kind = "player"` remains in the codebase.
- `luajit tests/run.lua` green, including a two-seat fixture where `gold` and
  `gold@opponent` differ, and a four-character party fixture using `sum:@party`.
- A ruined watchtower stops defending the castle.
