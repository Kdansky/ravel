# Ravel — Design Directives

This file captures all architectural and design decisions for the ravel project, as given. Reference this before adding features or changing core systems.

Companion documents: **`AUTHORING.md`** — how to build a game, with the full reference of fields, actions, tags and conditions. **`ARCHITECTURE.md`** — how the engine is built, its invariants, and how to extend it.

---

## Data Model

**Flat arrays with foreign keys only.** All runtime entity state lives in a single flat array. Entities reference each other by integer index (ID), never by Lua table pointer. This makes the full game state trivially serializable and copyable.

```lua
-- correct
card.zone_id = 3

-- never
card.zone = some_zone_table
```

Snapshotting state = copying the array. Undo = push snapshot before each action, pop to revert. No graph traversal, no pointer invalidation. Cross-references in JSON are resolved to IDs at load time by `declaration.lua`.

**Who is playing is declared, in a `players` section, one entry per seat in seat order.** It used to be inferred — any card carrying the `player` tag was a seat — which meant "is this a two-player game" was a scan, and a game that wanted an invite card had to know its own seat count without ever stating it. The engine now stamps that tag onto the cards `players` names, so every `@mine.player` scope is unchanged and the word still means what it did.

**A seat is a card too.** Several cards tagged `player` are several seats, named by their own keys; a zone declaring `per_seat` is instanced once per seat, and a card's owner is the seat of the zone it sits in — so ownership needs no per-card controller field and no new state to snapshot. An unqualified zone key means the active seat's copy, because a destination must resolve to exactly one zone even though a *set* may be wide. Whose turn it is is a `turn` stat on the system card, advanced by phases declaring `"seat": "next"`.

**There are three entity kinds — `zone`, `slot`, `card` — and the player is a card.** A player has stats, can be looked at, targeted, damaged and destroyed; every one of those already works for cards, and a fourth kind meant re-implementing all of it. When a game names no card for a seat, the engine injects one from that seat's `stats` into a hidden `system` zone, alongside a second injected card holding `round` (which belongs to the game, not to a seat). A game that wants a visible hero simply lists that board card under `players`. This is *when in doubt, decks and cards* applied to the one thing in the engine that wasn't.

---

## Templates and Instances, Live Editing

Card definitions are **templates** (`G.card_defs`, one per card key); entities are **instances** that hold only a `def_key` plus per-instance state (stats, zone, slot). Everything — rendering, costs, actions — reads through the template at use time, so editing a template changes every instance at once.

Templates are editable in place from every interface, for development:

- **CLI play and debug server**: `edit <card> <field> <json>` (invalid JSON is taken as a plain string; `null` clears the field), `dump <card>` prints the template as pretty JSON for pasting back into the game file, `reload` re-reads all templates from the game file without resetting the running game.
- **GUI**: the running game watches its game file and hot-reloads templates when it changes on disk — edit the JSON in your editor, save, and the live game updates within half a second. The debug server's `edit` also works against the running GUI.

Editing `card_stats` (directly or via a reload that changes them) re-stamps the stats of existing instances — immediate feedback beats preserving damage. Zones and phases are structural and need a full game load. Undo does not revert template edits.

---

## Module Split: flow vs main

`flow.lua` owns every state change that follows from player intent: loading, dealing, playing, activating, undo, end conditions, round-boundary `turn` actions. It has no rendering or input dependency, so the whole game logic runs headless (tests, debug server).

`main.lua` is only LÖVE wiring: hit-testing, click routing, tooltip hover, per-frame place syncing. Rendering lives in `render.lua`; it re-derives card rectangles every frame — no module ever needs to remember to "refresh" positions after a mutation.

Game feel is its own layer, never touched by logic: `anim.lua` gives card movement a physical arc — lift, mid-air growth, tilt into the direction of travel, overshoot slam onto the board plus a landing squash (`slam`/`drop`/`glide` profiles by destination zone) — and `fx.lua` draws the payoff: impact rings, debris sparks, screen shake, hit bursts on targeted cards, and floating stat deltas ("+2 gold") wherever a stat changed. The targeting arrow is a Hearthstone-style bezier arc with chevrons marching toward the cursor, turning hot over a valid target.

Presentation rules:

- **Everything scales.** 960×540 is the design size; `render.rescale` derives a UI scale from the window and rebuilds fonts, line widths, badges and effects from it. No fixed pixel text in a proportional layout. Card titles truncate with "..." rather than wrap.
- **Stats get icons, not just words.** `gold`, `hp`, `defense`, `morale` and `food` map to built-in vector glyphs (anything else gets a diamond) used in the HUD, cost badges and HP badges.
- **States never ride on hue alone.** Targeting eligibility is border color plus a pulsing fill plus a corner marker.
- **Touch works.** The primary action fires on release; a long press inspects (the touch stand-in for right-click); targeting shows on-screen Confirm/Cancel buttons and an Undo button appears whenever undo is available.
- Card art prompts live in `games/assets/card_art.md` — one neutral-style prompt per card key, designed for the live template reload loop.

---

## JSON Schema Rules

The JSON format must be writable by non-programmers. Three allowed value forms:

1. **Key/value objects** — `{ "key": "value", "min": 0 }`
2. **Arrays of strings** — `["shuffle", "instanced"]`
3. **A comparison object as a map value** — `{ "max:value@mine.red": { "at_most": 6 } }`

No s-expressions, no command trees, no arbitrary expressions. Nested arrays are allowed where they are **a list of coordinates rather than structure**: a `per_seat` zone's `pos` (one rect per seat) and a movement pattern's `vectors` (one `[x, y]` direction per entry). Both carry no keys, no depth past two, and no evaluation order — which is what the rule is actually protecting against. Anywhere else a nested array is structure, and structure is what this list refuses.

**Form 3 is a deliberate bend, recorded rather than assumed.** The rule started as "no code-like expressions", to stop a complexity explosion before anything needed one. Two things eventually did: asking a condition the *other* way (`at_most`), and measuring against another subject rather than a constant. Both are ordinary requirements for real card games, and neither is expressible in a flat `key: number` map. The bend is bounded — a comparison has exactly three possible keys and no nesting — and the reason it stays honest is that a bound must still look like a subject, so nothing silently becomes an expression by accident.

---

## Actions Are Strings

Game actions (a card's `play.action` / `activate.action` / `turn.action`, a phase's `actions`) are arrays of plain strings. Each string is an operation with optional colon-separated parameters:

```
"draw_from:stock"
"stat_gain:hp:2"
"push_phase:choose_upgrade"
"load_game:demo.json"
```

The engine parses `op:param1:param2:…` at runtime. Unknown ops are ignored (logged). Stat changes clamp to the stat's declared `min`/`max`, and to `[0, <stat>_max]` when the entity carries a companion `<stat>_max` value.

Every numeric slot accepts a number or `count:<tag>` — the number of cards on grid zones carrying that tag: `stat_gain:gold:count:economic`. One amount rule, everywhere.

---

## Conditions Are One Vocabulary

`predicate.lua` evaluates every condition in the engine — phase routing, `end_conditions`, and every `needs` — a card's, a challenge's, a destination's — all share it, and so do costs and the stat arguments of actions. A subject is `[<fn>:]<arg>[@<scope expression>]`: `gold`, `count:farm`, `sum:defense@board`, `hp@each.follower`, `hp@each.enemy.creature`, `hp@self`, `hp@target`. Comparisons are `equals` / `at_least` / `at_most` — against a number or another subject — or `zone_empty`. Map forms like `"requires": { "might": 8, "count:farm": 3 }` mean "each subject totals at least n".

The part after `@` is a **scope expression**: `[<quant>.][<owner>.]<zone-or-tag>`. The name is always a zone or a tag, never a seat — whose cards is a separate word (`mine` / `enemy` / `anyone`), so ownership composes with everything instead of doubling the vocabulary. A subject with no scope means the player's own cards. `predicate.parse_subject` is the only place the grammar is decided and `predicate.entities_in_scope` the only place a scope becomes entities, so a read, a cost and an effect can never disagree about who they mean.

**A stat nobody carries is absent, not zero.** Every comparison against it fails, `equals: 0` and `at_most: n` included — because reading a missing value as zero makes "this rook has never moved" true of a rook captured twenty moves ago, a gate that opens precisely when the thing it guards stops existing. Nil and zero are different values and this vocabulary keeps them so. The measuring forms are the exception, and mean what they say: `count:`/`card:` over nothing is a count of zero, and `sum:`/`max:` are asked of a *pool*, whose empty measure is honestly zero.

**A comparison may be measured against another subject, not only a constant.** This deliberately bends the no-expressions rule below: putting your own stat inside a condition is a genuine requirement (`{"value@target": {"at_least": "max:value@mine.red"}}`), and JSON and Lua both carry either type happily, so the type decides at run time. The rule the bend keeps: a subject used as a bound must *look* like one — name a scope or a measuring fn — so a bare word still fails closed instead of quietly reading as zero.

**Legality between two cards lives on the destination.** `receive.needs` is a condition map asked of each candidate target, with itself as `@self` and the arriving card as `@target`. The block is what says *when* it is asked, which a bare field could not. Putting it there rather than on the acting card is what lets it name its own zone; a destination with no `receive` takes anything, which is what every game before it assumed.

---

## One Name, One Thing — Where It Matters

**A key is unique inside its own kind**: no two cards, zones, stats or phases share one. **Across kinds a repeat is legal**, and two are load-bearing — a chess piece is a card key *and* a tag so another piece's condition can name it, and a style sharing a computed tag's name is what makes a look follow the numbers.

**The one namespace that must stay unambiguous is what a scope resolves**: patterns, then zones, then tags (`predicate.lua` asks in that order). Two of those kinds sharing a name means a condition silently picks one, so the validator refuses it rather than inventing a precedence rule. Styles are tag words for this purpose, being named in the same list.

---

## Setup Is the Manual, Not the Cards

**A card never says where it starts.** The `cards` section is the list of things that come out of the box; `setup.place` is the page that arranges them — which card, which zone, which cell. This is why a template can be a *kind* rather than a piece on a square: eight pawns are eight placements naming one card, not eight cards that each know their square.

The order of `setup.place` is load-bearing rather than incidental: entity IDs are handed out as cards are created, so a seeded game replays identically only if setup builds the board the same way every time.

The engine places its own first — the system card, an injected player, and any seat that named no place. A seat has to exist before it can act, so that is plumbing rather than setup and a game never writes it down. **The `system` card living in the `system` zone, and an injected `player` card carrying the `player` tag, are both deliberate**: neither name is in the scope namespace, and both are engine furniture a game may replace by declaring its own.

---

## Zone Contents

A zone declares its starting cards in its own definition, as `"card_key"` or `"card_key:count"` strings:

```json
{ "key": "build_deck", "type": "deck", "tags": ["shuffle", "refill_when_empty"],
  "contents": ["watchtower:3", "farm:3", "market:2"] }
```

Contents are created (and shuffled, if tagged) when the zone is created, and recreated by `refill_when_empty`. The `fill:` action still exists for dynamic cases.

---

## No Boolean Fields

**A thing an entity either is or isn't is a tag, not a field.** A boolean field is a name that has to be read twice — once for the word, once for the value — and it can only ever be set on the thing that owns the field. `placeholder_art` was the clearest case: a game-level `true`/`false` that could not give six cards generated art among thirty-five photographs. It is the tag `generate_art`, and a card asks for itself.

This is what the tag system is for, and the rule the styles pass already followed from the other side: a *quality* is a tag, a *value* is a field. `ratio` is a number and there are infinitely many, so it is a field; `no_undo`, `generate_art`, `stays_ready`, `per_seat`, `discard_hand` and `hidden` are words a thing carries or does not. Phases and stats grew a `tags` list so they could say so too — everything the format declares now has one.

**A tag is carried or it is not, so there is no "false" to write**, and an opt-out needs its own word: a `draw_and_play` phase discards its hand by default and says `keep_hand` when it should not.

**One exception, and it is a real one.** A routing entry's `ends_round` stays a boolean, because a routing entry is not a *thing* — it has no key, no identity and nothing to tag. It is a property of a transition, and the rule above needs an entity to attach to. Moving it up to the phase would narrow what a game can say: a phase that self-loops for a repeated draft must be able to end the round on the way out and not on the way round, which is exactly why `ends_round` is declared per route rather than inferred.

---

## Reserved Tags

**Eighteen words are the engine's, and a game may not redefine them.** `validate.lua`'s `ENGINE_TAGS` is the single list — what each word attaches to and what it does — and `SCHEMA.json`, AUTHORING's table and the validator all read it rather than restating it. Four half-lists is how this started, and a word two of them disagreed about was reported as a typo or silently ignored, both of which look like the game being wrong.

A style, a tag with behaviour or a computed tag under a reserved name is **an error**: the engine reads the word off the entity, so two meanings would both apply with nothing to say which wins. The cost is accepted rather than argued away — a game cannot name a style `hidden` to colour everything that is — and it buys the guarantee that a word already meaning something cannot quietly be given a second job.

**A near miss is reported, an unknown word never is.** Free vocabulary is the point. But a tag of six letters or more that is one edit from a reserved word is almost certainly that word misspelled, and those fail *silently*: a board tagged `activaet` holds cards whose abilities can never be used. Short words are exempt, because `mage` is one edit from `page` and is nobody's mistake.

---

## Zone / Deck Behaviour: Tags

Zones declare behaviour through an open-ended string tag set. The engine checks for known tags; unknown tags are ignored (forward-compatible).

| Tag | Effect |
|---|---|
| `shuffle` | Shuffled when contents are created (setup and refill) |
| `refill_when_empty` | Recreates `contents` when the zone empties |
| `face_up` | Deck shows its top card's face (decks default to backs) |
| `face_down` | Pile shows card backs (piles/hands default to faces) |
| `no_peek` | No tooltip and no browsing, even when face-up |
| `hidden` | Not drawn; used for overlay offer zones and fate decks |
| `activate` | Cards here may use their abilities. Not inferred from the zone's shape: a board and a Lost Cities discard both allow it, a hand and an MTG graveyard both do not, and neither pair shares a type |

Decks are finite by default; drawing removes the card.

---

## Phase Stack

Phases are a stack, not a flat list. Current phase = top of stack.

- `next_phase` — replace top with the next phase in the JSON sequence; at the end of the sequence, wrap to the first non-automatic phase. A wrap marks a completed **round**: every board card then runs its `turn.action` (cards at 0 hp are ruined and don't act).
- `push_phase:key` — push a phase (opens overlay, modal, menu).
- `pop_phase` — pop current phase (closes overlay, returns to previous).

Phase types: `automatic` (runs `actions`, advances immediately), `player_input`, `draw_and_play` (deals `draw` cards from `deck`; playing one card discards the rest and advances), `overlay`.

**Routing.** A phase may declare a `"next"` table instead of relying on list order: the first entry whose condition holds wins, an entry without a condition always matches, and no match means the phase stays put (the validator flags that shape). Round boundaries are *declared* with `"ends_round": true` on the entry — never inferred from list positions — so self-loops for repeated draft hands don't fire income or ready cards unless asked to. `settle` carries a 64-transition budget: a routing cycle warns and halts instead of hanging.

```json
"next": [
  { "stat": "progress", "at_least": 20, "then": "trials_hard" },
  { "stat": "round",    "at_least": 7,  "then": "trials_easy", "ends_round": true },
  { "then": "creation", "ends_round": true }
]
```

**Free-play drafts** need no phase type: a `player_input` phase with `deck`, `draw` and a `pass_card` deals a hand you may play freely from; a Done/router token advances via `next_phase`. `pass_card` accepts a single key or an array (e.g. three "travel" routers that each set a destination stat the routing reads). Stale tokens are swept from the hand before each deal, so they never accumulate across phases.

A `draw_and_play` phase must declare a `"pass_card"`: that card is created into the hand with every deal, so a forced play always has an out — no hand can deadlock the game. The pass card is an ordinary card tagged `token` (tokens are destroyed instead of discarded when the hand is swept) whose play action is `["destroy_self"]`.

The engine keeps a **round counter** as a `round` stat on the injected system card: it starts at 1 and increments every time the phase list wraps. Because it is a stat, games can display it (declare a `round` stat), gate a challenge on it (`challenge.needs`), or end on it (`end_conditions`) — and undo restores it like everything else. The wrap also **readies** all exhausted cards.

Overlay phases grey out the background and deal `draw` cards from `deck` into `zone`. **Choosing is playing**: there is no separate pick path, the phase's `zone` bounds what may be played, and the card's own `play.action` runs — or one its zone grants with `applies`, which is how an offer says what choosing from it means when the cards it deals already do something else in a hand. Picking pops the overlay before the actions run, so a chained reveal lands on top rather than burying it, and a card still lying in the offer afterwards is spent. **A choice costs nothing**: cost, needs and targeting are skipped, because they describe playing that card out of a hand later. Overlays are push-only: they never appear in the phase sequence, only via `push_phase`. Resuming a phase after a pop does not re-deal it.

---

## Sub-card Choices

A card can fork into specific sub-cards: play it, choose one option, the chosen card lands in your hand, and playing it is a deliberate second step. That second step means option cards can carry their own `cost` — a priced transformation. There is no special engine verb: the options live in an **internal deck** and the choice is an ordinary overlay. When in doubt, everything is decks and cards.

```json
{ "key": "edicts", "type": "deck", "tags": ["hidden"],
  "contents": ["festival", "conscription", "tax_levy"] }

{ "key": "decree", "type": "overlay", "label": "Choose an edict",
  "deck": "edicts", "zone": "offer", "draw": 3,
  "zone": "decree_offer" }   // whose zone applies a tag: "play": { "action": ["add_to:hand", "return_to:decree_offer:edicts"] }
```

The parent card is just `"play": { "action": ["move_to:graveyard", "push_phase:decree"] }`, and the offer zone grants what choosing from it means — behaviour belonging to the place, so the option cards need say nothing about being offered. While an overlay is open, all other actions (plays, activations, end conditions) are locked until the choice resolves. `destroy:zone` and `destroy_self` remove cards from play entirely — the flat array keeps the husks (IDs stay valid) but they hold no zone and no stats, so nothing renders, targets or counts them; undo restores them.

---

## Costs

`"play": { "cost": { "gold": 2 } }` gates playing a card: unaffordable cards render dimmed and don't respond to clicks; the cost is deducted on play. `activate.cost` does the same for the board ability. **Choosing from an overlay costs nothing** — cost, needs and targeting describe playing that card out of a hand later. Affordability reads the same subject the payment spends, so it checks whatever the subject's scope names — the player's own cards by default.

`"needs": { "plays": 1 }` is the non-consuming gate: nothing is spent, the card is simply unplayable (dimmed) until the condition holds. Subjects follow the shared vocabulary, so `"needs": { "count:soldier": 2 }` gates on the board. The engine maintains a `plays` stat on the player card — reset to 0 whenever a phase is freshly entered (not when resumed after an overlay), +1 per card played — which is how "play at least one card per hand" is expressed. Escape hatch: a needs-gated card becomes playable when nothing else in its zone is, so a mandatory play can never soft-lock a hand. `round` and `plays` are reserved engine stats; declare them only to display them.

Activating a board card **exhausts** it — greyed out, unusable — until the round wraps and readies every card again. One activation per card per round, as is proper. A card that should stay clickable declares `"exhausts": false`.

Exhaustion is a **card behaviour, not a stat**. It is tempting to make readiness an ordinary numeric stat so it falls out of the cost machinery for free, but stats are numbers with magnitudes that can be gained, spent and compared; readiness is binary and belongs to the engine's standard card vocabulary, as it does in most card games. Binary card states stay engine behaviours; do not encode them as 0/1 stats.

Cards entering a grid zone without slot targeting take the first free slot automatically — friction-free placement for drafts, precise placement when a `target` spec says so.

---

## End Conditions

Games declare win/lose checks that run after every action:

```json
"end_conditions": [
  { "stat": "hp", "equals": 0,      "then": ["push_phase:defeat"] },
  { "zone_empty": ["road", "hand"], "then": ["push_phase:victory"] }
]
```

Comparisons: `equals`, `at_least`, `at_most` on a stat total, or `zone_empty` (all listed zones empty). The first matching condition fires; a game has exactly one outcome. Outcomes wait until any open overlay closes, so a pending choice always resolves first. Victory/defeat screens are just overlay phases dealing a fate card whose `play.action` loads the menu — no special engine mode.

---

## Load-time Validation

`validate.lua` checks every game file as it loads: action ops exist, referenced zones/cards/phases/stats exist, routing targets are real non-overlay phases with reachable entries, comparands are numbers, `count:` tags exist somewhere, reserved stats aren't redefined, `draw_and_play` phases carry a pass card, automatic phases can't cycle unconditionally, and `return_to` never drains a `refill_when_empty` zone (it would refill mid-drain). Problems are printed and written to the event log — content errors warn, they never kill the game. The test suite asserts all shipped games validate clean.

---

## Undo

`flow` snapshots entities, phase stack, and end-condition state before every player action (play, activate, pick, zone click). `Z` (or the on-screen Undo button) reverts one step. History is capped at 50 and cleared on game load.

---

## Event Log

`log.lua` records the play-by-play at the logic level: plays, picks, activations, stat changes, challenge results, draws, discards and round markers. Undo checkpoints mark positions in the log, so undoing removes exactly the lines the undone action wrote. The GUI shows the tail bottom-left (`L` toggles the expanded view), the CLI echoes new lines after every command, and the debug server serves `log [n]`.

---

## Reproducibility

The RNG can be seeded per game load, with precedence: explicit seed > CLI/env default > game doc, and the clock when a game asks for none. A game file may declare `"seed": 12345`; the CLI takes `luajit play.lua castle.json 42`; the GUI honors a `RAVEL_SEED` env var; the debug server takes `load castle.json 42`. Seeding happens before deck contents are created, so shuffles reproduce exactly.

The generator is the engine's own (`rng.lua`), not the host's. This is the difference between "reproduces" and "reproduces *here*": `math.random` is a Tausworthe generator in LuaJIT and xoshiro256\*\* in PUC Lua 5.4, so a seed used to name a different deck on each, and the golden traces could only ever run under one of them. A seed now means one sequence on every interpreter — which is also the whole reason two networked players can be handed the same game by exchanging a filename and a number.

---

## Trust

Networked play is **trust-based, by design and not by omission**. Both players hold the entire state, hidden zones included — a hand is hidden by the renderer, not by the protocol — and a client applies whatever state arrives, checking only that it follows the state both sides agreed on, never that it is reachable from it by a legal move. The hashes in every message exist to catch accidents: a stale paste, two different versions of a game file, an engine that serialises differently.

Changing that is not a patch. It needs an authoritative referee that takes moves rather than states, validates each one, owns the result, and shows each player only their part — a different architecture, and a much larger project than the transport it would replace. `ideas/DONE.md` sets out what it would cost. Until it exists, play with people you trust.

---

## Menu as a Game

The startup screen is `menu.json`, a valid game loaded like any other. Menu items are cards with `"play": { "action": ["load_game:filename.json"] }`. The engine has no special menu code. Loading a game resets state and reinitialises from the new JSON.

---

## Card Selection

Clicking any face-up card always selects it. This is hardcoded engine behaviour, not a JSON-configurable action. No game definition needs to declare a "select" action. Right-click opens a detail view of a card, or browses a face-up zone's contents (e.g. the discard pile).

**A zone has abilities of its own, and they are gated like a card's.** `activate` on a zone carries the same words a card's does — cost, phases, action — and answers the same questions: the phase it works in, what it costs, and whose zone it is. It replaced `on_click`, which fired in *any* phase and answered to nothing, and therefore had to carry a warning that it was not a move and must not be used as one. It is a move now. Do not confuse it with `applies`, which grants an ability to the cards *lying* in the zone: a discard pile has both, and they are different sentences — "you may take the top of this pile" is the pile speaking about its cards, "draw from this deck" is the deck speaking about itself.

**A deck is a box, not a stack of clickable cards**, and that is what makes drawing simple. "Click the deck to draw" was going to need the top card to become clickable, and therefore hoverable, and therefore guarded so that hovering a face-down deck did not read out the card you were about to draw. The zone answers instead, and the problem is deleted rather than defended against.

---

## Stacks Are Reached From the Top

A `deck` or a `pile` draws one card and hit-tests one card, so the rules say the same: the top card of a stack is playable, activatable and targetable, and nothing under it is. Anything else is a disagreement between what the player is shown and what the engine allows, and it can point either way. Lost Cities had it pointing both ways at once — a destination marker at the bottom of each discard pile stayed *eligible* for the whole game while the first card discarded on top of it made the marker *unreachable*, so a colour could be discarded to exactly once and never again; meanwhile a script or a network peer could name any card buried in the pile.

**A place to put a card is a zone, not a marker card standing in one.** `"target": { "type": "zone", "zones": ["red", "red_discard"] }` offers the expedition and the discard, and the player points at a place. `receive` therefore belongs on the zone as naturally as on a card — the expedition's ascending rule is one line on the expedition — and destinations stop needing a stand-in card that anything can cover up.

---

## Tags Are Mixins, and a Zone May Grant Them

A tag definition may carry card behaviour — a home `zone`, a `tooltip`, and the `play` and `activate` blocks a card itself has — and a zone may hand tags to whatever sits in it:

```json
"tags":  { "takeable": { "activate": { "action": ["move_to:hand", "next_phase"], "phases": ["draw"] } } }
"zones": [ { "key": "red_discard", "type": "pile", "applies": ["takeable"] } ]
```

That is the whole of "you may take the top card of a discard pile": the pile says what lying on it means, and no card in the game knows piles exist. Graveyard recursion, a deckbuilder's market row and Klondike's movable runs are the same sentence.

**Where a card is decides what it can do.** The zone answers first and the card's own definition answers where the zone is silent — a creature lying in a graveyard that grants "return to hand" offers that, not the tap ability it had on the board. There is deliberately **no card-wins precedence rule**: an earlier draft had one so a marker card could opt out of an ability its pile handed everybody, and that was a workaround for content the engine no longer needs. A card and its zone defining the same behaviour is an authoring conflict now, reported by the validator rather than silently resolved. Prose is the exception and not a conflict: a card's own tooltip and its zone's describe different acts, so the tooltip shows both.

This is aura-shaped, and gap 5 of `ideas/01-boardgames.md` defers auras for good reason; what keeps this the cheap corner is that the grant is *static*: a fixed list declared on the zone, resolved by one lookup, never recomputed as state moves.

---

## When a Card May Be Used

`"phases": ["draw"]` on a card — or on a tag granting it — limits it to those phases. Naming none means any phase, which is what every card written before it assumed. This is MTG's sorcery speed, and it is the rule that makes a grantable ability safe: an ability is used *where the card lies*, so `in_play_zone` cannot bound it (the pile is not the phase's zone and never will be), and without a phase restriction "take the top of that pile" would fire during your play step for a free card and a skipped turn.

**Phase keys must not name a seat.** Both players share one `play` and one `draw`; `"seat": "next"` on entry is what makes the turn theirs. A phase list that says `north_play`/`south_play` doubles every rule that ever mentions a phase, and triples it at three seats.

---

## Immutable

`immutable` is a hardcoded tag meaning *scenery*: it cannot be targeted and its template cannot be edited, ever. The menu is a game like any other, so the live-edit tools and every targeting spec point straight at it; this is how the interface says it is furniture rather than a game object.

---

## Assets and Tooltips

Every card definition may include:
- `"asset": "filename.png"` — image file under `games/assets/`. **A picture that cannot be produced draws a generated one, never nothing**: the reasons are mostly not the author's (a host refusing the fetch, or a game file that arrived over the network carrying the JSON and none of the sender's art), and a card with no image reads as a bug where a shape derived from its key reads as a card. The key is hashed rather than the text, because the key is identity and the text is presentation. It may instead be an `http(s)` URL, a procedural shape spec, or `"auto"`; zones take the same field for the picture behind the board.
- `"tooltip": "string"` — shown in a hover panel after a short delay (plus cost, per-card stats and attachments).

**A look is a named style a card or zone claims by tagging it**, not a field it carries. It covers the lot — a card's plate colour and whether it has a title, a zone's shape, how a card sits in its cells, what those cells are painted with and whether empty ones are outlined. Chess's entire board appearance is one word on the zone. Seventy Lost Cities cards in five colours are five `styles` entries and one word each, and changing the red changes every red card. `color: false` is where two ideas became one: a card's colour and "draw no plate" were a field and a tag deciding the same thing, so now the plate has a colour or it has none. The name shares the one namespace zones and tags live in — so a style is named for the look (`crimson`) rather than the thing wearing it (`red`, which is already a zone) — and two styles on one card claiming the same property is an authoring conflict the validator reports rather than a precedence rule to memorise. A style that is *also* a computed tag makes the look follow the numbers, which is conditional rendering with nothing in the drawing code that knows what `wounded` means. **A style may never change a rule**: the moment it could, every rules bug would become a drawing bug.

**A picture with options is named once, in the top-level `assets` table, and referenced by key.** A name is anything with no source *in* it — no extension, no scheme, no shape colon — so the two forms cannot be confused, and there is exactly one place a picture carries options (today `max`, the longest edge). Naming also makes the name the cache key, so twenty cards drawn from one picture are one download and one texture.

**A remote picture is not a convenience, it is what makes a game file shareable.** A file that names only local binaries cannot be handed to somebody without also handing them the binaries, which is the thing networked play exists to avoid. The browser build therefore fetches URLs through the page itself, which also decodes them — so the format stops mattering, and the size cap is about the wasm heap rather than about looks (`index.html` explains the floor under it; raise that before raising the cap).

---

## Testing

State is flat and serializable, so the engine runs headless (`headless.lua` is the tiny `love` shim making that possible):

- **Test suite** — `luajit tests/run.lua` (or `lua tests/run.lua`) from the repo root; everything under `flow` is exercised for real.
- **Render smoke test** — `luajit tests/render_smoke.lua` drives render/anim/fx/tooltip through their states with a stubbed `love.graphics` to catch crashes; it does not check pixels.
- **CLI play** — `luajit play.lua [castle.json]` plays any game interactively in the terminal: numbered hand, ASCII board, target prompts, `a <slot>` to activate, `u` to undo, `e <action>` to run raw actions. Same `flow` code paths as the GUI.
- **Debug server** — start LÖVE with `RAVEL_DEBUG=1` and drive the live game over TCP:

  ```sh
  echo "stats"                 | nc 127.0.0.1 5757
  echo "play farm slot:8"      | nc 127.0.0.1 5757
  echo "eval stat_set:gold:9"  | nc 127.0.0.1 5757
  echo "state"                 | nc 127.0.0.1 5757   # full entity dump as JSON
  ```

  Commands: `state`, `stats`, `play`, `activate`, `pick`, `click`, `eval`, `load`, `undo`, `help`. Cards are addressed by def key, entity ID, or `slot:N`. No-op under love.js (no sockets).

---

## Coding Style

- Keep code small and elegant — no Java-style verbosity.
- Follow the official Lua style guide.
- Only extract helper functions that are clearly generic with an obvious use-case. Don't extract one-off logic.
- Comments explain the WHY, not the HOW.
- Don't overengineer.

---

## Infrastructure

- LÖVE game code in `game/`, zipped to `game.love` by Docker.
- love.js 11.5 (2dengine fork) runs the `.love` in the browser.
- nginx serves with COOP/COEP headers (required by love.js SharedArrayBuffer).
- Dev: `docker compose up --build` — watches `game/` and repacks on change.
- Prod: `docker build` + `docker run -p 8080:8080`.
- Tests: `luajit tests/run.lua` (headless, no LÖVE needed).
