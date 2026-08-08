# Authoring Games for Ravel

A game is one JSON file in `game/games/`, plus optional images in
`game/games/assets/` (sources and licenses are recorded in
`assets/CREDITS.md` — keep it that way when adding art). No code.

This document is meant to be complete: two walkthroughs, a procedure for
**translating a published rulebook into a game file** (§3), the patterns worth
copying (§4), and a full reference for every field the engine reads (§5). If
something is not here, the engine does not read it. `DESIGN.md` explains *why*
things are shaped this way; `ARCHITECTURE.md` explains the engine internals.

The shipped games are the worked examples: `starter_cyoa.json` (a skeleton
built to copy), `castle.json` (turn cycle, challenges, a hero card),
`kingdom.json` (drafts, routing, long game), `lost_cities.json` (two players,
per-seat zones, placement legality, scoring).

Quick loop while authoring: `luajit play.lua mygame.json 42` (CLI, seeded), or run
the GUI and just save the JSON — templates hot-reload into the running game.
A validator checks the whole file on load (and on reload) and prints what's
broken in plain language — typo'd fields and sections, missing references,
conflicts — with "did you mean" suggestions; the game plays on regardless.
`luajit check.lua mygame.json` runs the same checks without starting a game.

---

## 1. Walkthrough: a minimal game

```json
{
  "title": "My Game",

  "stats": [
    { "key": "hp", "label": "Health", "min": 0, "max": 10 }
  ],

  "setup": { "player": { "hp": 5 } },

  "zones": [
    { "key": "deck", "type": "deck", "pos": [0.05, 0.10, 0.25, 0.60],
      "tags": ["shuffle"], "contents": ["sword:3", "trap:2"] },
    { "key": "hand", "type": "hand", "pos": [0.05, 0.65, 0.95, 0.98] }
  ],

  "templates": [
    { "key": "sword", "text": "Sword", "tooltip": "Gain 1 health.",
      "on_play": ["gain_stat:hp:1", "draw_from:deck:hand:1"] },
    { "key": "trap",  "text": "Trap",  "tooltip": "Lose 2 health.",
      "on_play": ["lose_stat:hp:2", "draw_from:deck:hand:1"] }
  ],

  "phases": [
    { "key": "setup",   "type": "automatic", "actions": ["draw_from:deck:hand:1"] },
    { "key": "playing", "type": "player_input", "label": "Playing" }
  ],

  "end_conditions": [
    { "stat": "hp", "equals": 0, "then": ["push_phase:defeat"] }
  ]
}
```

The recipe, in order:

1. **Stats** — the numbers of your game. Declared stats show in the HUD (add
   `"hidden": true` to keep one internal). Starting values go in `setup.player`.
2. **Zones** — where cards live. `pos` is window fractions `[x1, y1, x2, y2]`;
   positions off-screen (negative y) make cards fly in from outside. Decks own
   their starting cards via `contents`.
3. **Templates** — one entry per card *kind*. Instances are created from these;
   editing a template live changes every instance.
4. **Phases** — the turn structure. The first phase starts the game; `automatic`
   phases run and advance immediately.
5. **End conditions** — how the game ends. Endings are just overlay phases that
   deal a "fate card" whose `on_pick` loads the menu.

The menu itself is a game (`menu.json`); add a card with
`"on_play": ["load_game:mygame.json"]` to make yours reachable.

---

## 2. Walkthrough: a story game

Classical CYOA needs almost no machinery: one automatic intro that reveals
the first page, one `player_input` phase, and everything else is cards.
**Copy `starter_cyoa.json`** — a complete, playable, TODO-marked skeleton
with a keepsake, a gated branch, a shuffle-secret and endings — or build up
from this two-page story:

```json
{
  "title": "The Cellar",
  "phases": [
    { "key": "intro", "type": "automatic", "actions": ["reveal:p_door"] },
    { "key": "story", "type": "player_input", "label": "The Cellar" }
  ],
  "zones": [ { "key": "hand", "type": "hand" } ],
  "templates": [
    { "key": "p_door", "text": "The Cellar Door",
      "story": "It was locked all your childhood. Tonight it stands open.",
      "on_pick": ["fill:hand:c_down:1", "fill:hand:c_away:1"] },

    { "key": "c_down", "text": "Take the stairs",
      "tooltip": "You always wanted to know.",
      "on_play": ["reveal:p_dark"] },
    { "key": "c_away", "text": "Close the door",
      "tooltip": "Some doors are better shut.",
      "on_play": ["reveal:e_away"] },

    { "key": "p_dark", "text": "Down",
      "story": "The stairs go further than the house is tall.",
      "on_pick": ["destroy:hand", "fill:hand:c_away:1"] },
    { "key": "e_away", "text": "An Ordinary Life",
      "story": "You bolt it, and that is that.",
      "on_pick": ["load_game:menu.json"] }
  ]
}
```

Two rules carry every story:

- **Pages** are cards with `story` (the prose) and `on_pick` (what happens
  when the read page is clicked away). **Choices** are cards with `tooltip`
  (what the player is told) and `on_play` (what secretly happens — usually a
  `reveal:`). The tooltip reveals exactly as much as you write into it.
- **Every page that deals new choices starts its `on_pick` with
  `destroy:hand`**, or the old choices pile up next to the new ones. A page
  that keeps the hand (a locked door, a rebuff) uses `"on_pick": []`.

From there: keepsakes are cards with a home-zone tag (`gain:` them, test
them with `card:<key>`), shuffle secrets are `reveal_top:` over a hidden
deck, and endings are pages whose `on_pick` is `load_game:menu.json` plus
`end_conditions` that `reveal:` a death page. Zones may omit `pos` — every
type has a sensible default spot. Register your game with a card in
`menu.json`, or it is only reachable from the CLI.

## 3. From a rulebook to a game file

This section is the one to follow when translating a published game — it is
written to be worked through in order, by a person or an agent, with the
rulebook open alongside.

### The procedure

1. **Count the seats.** One player: skip ahead, everything else stays as
   written. Two or more: declare one card per seat, tagged `player`, each with
   the stats that rulebook calls "your" something (score, gold, life).
2. **Inventory the components** and turn each into a zone. A draw deck is a
   `deck` with `contents`; a hand is a `hand` zone (`per_seat` when there are
   seats); a personal tableau is a `grid` (`per_seat`); a shared board, market
   row or discard pile is the same without `per_seat`.
3. **Inventory the card types** and write one template each. Numbers printed on
   a card become `card_stats`; categories printed on it (suit, colour, faction)
   become `tags`. If the deck runs past ~20 distinct cards, write a generator
   script instead of the JSON — see *Big decks* below.
4. **Write the turn as phases**, one per step the rulebook describes ("play a
   card, then draw one" is two phases). Put `"seat": "next"` on the first phase
   of a turn so entering it hands over. Give each phase a `zone`, which is both
   where it deals and what may be played from it.
5. **Turn each choice into a card with a destination.** "Play a card to your
   tableau, or discard it" is one `target` spec listing both places plus
   `on_play: ["move_to:target"]`. A choice with no card attached ("pass",
   "draw from the deck") is a `pass_card` token whose `on_play` does the thing
   and calls `next_phase`.
6. **Turn placement restrictions into `accepts`** on the destination, never
   into `needs` on the card — `needs` would make the card unplayable entirely,
   including the ways it *is* still legal.
7. **Costs and prerequisites**: what is spent is `cost`; what merely has to be
   true is `needs`.
8. **End of game**: a condition on a stat goes in `end_conditions`; "when the
   deck runs out" is a route — `{ "zone_empty": ["deck"], "then": "scoring" }`
   on the last phase of the turn.
9. **Scoring** is a phase whose `pass_card` list is one card per scoring rule,
   each gated by `needs` so it only appears when it applies, each ending in
   `destroy_self`. Give the phase its own `zone` so leftover hand cards are not
   still playable while tallying.

### Rulebook phrase → engine construct

| The rulebook says | You write |
|---|---|
| "Shuffle the deck" | a `deck` zone tagged `shuffle` with `contents` |
| "Deal each player 8 cards" | an `automatic` setup phase: `draw_from:deck:mine.hand:8`, `draw_from:deck:enemy.hand:8` |
| "On your turn, do X then Y" | two phases, the first tagged `"seat": "next"` |
| "Play a card from your hand" | phase `"zone": "hand"`, `"ends_after": 1` |
| "…to your own area" | a `per_seat` grid zone; `move_to:<zone>` resolves to yours |
| "…or discard it instead" | a second destination in the same `target` spec |
| "Cards must be played in ascending order" | `accepts` on the destination |
| "Costs 2 gold" | `"cost": { "gold": 2 }` |
| "Only if you control a farm" | `"needs": { "count:farm": 1 }` |
| "Draw from the deck or a discard pile" | `on_click` on each pile: `draw_from:<pile>:hand:1`, `next_phase` |
| "Discard a card of your choice" | an `overlay` phase over the hand with `on_pick` |
| "Destroy all enemy creatures" | `destroy:each.enemy.creature` |
| "Choose an enemy creature" | `"target": { "tags": ["creature"], "owner": "enemy", "count": 1 }` |
| "Roll / draw randomly" | `shuffle` then `reveal_top:<zone>` |
| "The game ends when the deck is empty" | a route on `{ "zone_empty": ["deck"] }` |
| "Score 3 points per set" | a scoring card: `gain_stat:score:3:x:count:<tag>` |
| "(sum − 20) × multiplier" | two actions: `gain_stat:score:sum:…:x:…` then `lose_stat:score:20:x:…` |
| "Whoever has more points wins" | a route: `{ "stat": "score@north_side", "at_least": "score@south_side" }` |
| "Players each have a different power" | different `player`-tagged templates |

### Rules that do not fit — stop and say so

The engine is turn-based, one screen, no hidden information between seats and
no continuous effects. If the rulebook needs any of the following, it cannot be
expressed today and guessing will produce a game that looks right and plays
wrong:

- **Simultaneous or real-time action** — everything is strictly one action at a
  time, in phase order.
- **Negotiation, trading, bluffing between players** — there is no channel.
- **Hidden information between seats.** Hot-seat hides nothing: both hands are
  in the same state on the same screen. Fine at one keyboard, not a secret.
- **Triggered abilities** — "when a creature dies, …". `on_turn` (each round
  boundary) is the only automatic hook; anything else has to be a card the
  player is made to play.
- **Continuous effects / auras** — "all your beasts have +1 while this is in
  play". Model it as a stat change applied once, or leave it out.
- **Arithmetic beyond a product** — amounts multiply, but there is no division,
  no subtraction inside one amount, and no parentheses. Distribute it into
  separate actions, as the scoring row above does.

### Big decks

Past a couple of dozen templates, hand-written JSON stops being reviewable and
starts drifting. Write a generator, check it in, and treat the JSON as output —
`tools/make_lost_cities.py` builds all sixty Lost Cities cards from five
colours and a value range, and is the model for any deck-of-cards game.

### Art without assets

**No game needs an image file.** `asset` may name a shape instead, drawn
procedurally: `<shape>[:<n>]:<colour>[:<colour>]`.

```json
"asset": "circle:teal"           "asset": "polygon:5:green"
"asset": "star:6:gold:navy"      "asset": "stripes:7:crimson"
"asset": "checker:8:black:white" "asset": "auto"
```

| Shapes | |
|---|---|
| no count | `circle`, `square`, `triangle`, `diamond`, `cross` |
| counted | `polygon:3–12`, `star:3–12`, `stripes:2–16`, `checker:2–16`, `dots:1–8` |

Colours are `#rrggbb` or a palette name: `black white grey slate ash silver
red crimson maroon pink orange amber gold yellow sand tan brown olive green
forest teal cyan blue navy indigo violet purple magenta`. A second colour is
the background; with only one, the background is a dark wash of the first, so a
one-colour spec looks deliberate. Counts outside a shape's range are clamped.

**`"asset": "auto"`** derives a shape, a count and a hue from the card *key*.
Same card, same art, every run and every machine — no authoring at all, and no
RNG draw, so it cannot shift a seeded shuffle. Set `"placeholder_art": true` at
the top level to make `auto` the default for every card with no `asset`, which
is the one-line way to give a brand-new game visual differentiation.

`lost_cities.json` is the worked example: sixty cards, no image files. Its
number cards are `stripes:<value>:<colour>`, so a card's value is legible as a
stripe count, and its wagers are stars.

**Art is style, never a rule.** It is tempting, once a card is drawn
`crimson`, for a rule to ask "is this card red". It must not, and it cannot —
nothing below the presentation line can even see the asset field. Colour the
rules care about is a tag or a stat (`"tags": ["red"]`,
`"card_stats": { "rank": 7 }`); the picture merely agrees with it. Lost Cities'
red 7 is red because of its `red_dest` target and its `value`, and would play
identically drawn in grey.

### Before you call it done

- `luajit check.lua mygame.json` — must be silent. Every message is a real
  problem, and most name the fix.
- `luajit play.lua mygame.json 42` — play a few turns at a fixed seed.
- Add a card to `menu.json` (template plus an entry in the `menu` zone's
  `contents`) or the game is only reachable from the CLI.
- Write a scripted test in `tests/run.lua`: a fixed seed, a few forced moves,
  and assertions on the end state. Ten lines, and it is the only thing that
  will notice when an engine change breaks your game.

## 4. Common patterns

**Ending screens.** Give the ending card an `outcome` and the engine adds the
pizzazz: a Victory/Defeat banner, a summary of the run's visible stats, and
confetti or falling embers. A hidden deck holding one ending card + an
overlay phase:

```json
{ "key": "fate_win", "type": "deck", "pos": [0.42, -0.4, 0.58, -0.08],
  "tags": ["hidden"], "contents": ["victory_card"] }

{ "key": "victory", "type": "overlay", "label": "Victory",
  "deck": "fate_win", "zone": "offer", "draw": 1,
  "on_pick": ["load_game:menu.json"] }
```

**Turn cycle with forced plays** (Castle Lord): `draw_and_play` phases in list
order; playing one card discards the hand and advances; the list wraps to the
first non-automatic phase, which ends the round. Always give these a `pass_card`.

**Free-play draft hands** (Coronation): a `player_input` phase with `deck`,
`draw` and a `pass_card` deals a hand you play freely from; a Done/router token
with `"needs": { "plays": 1 }` and `["destroy_self", "next_phase"]` ends the hand.

**Sub-card choices**: options live in a hidden internal deck; the parent card
pushes an overlay over it; `on_pick` sends the pick to hand and returns the rest.
Option cards can carry their own `cost` (a priced transformation).

**Classical CYOA** (The Drowned Tower): pages are cards with a `story` field;
choice cards `reveal:` them. A revealed page fills the screen; clicking it runs
the page's own `on_pick` — typically `destroy:hand` then `fill:hand:...` with
the next choices, so the story chains without any phase plumbing. Secret
conditional branches are `resolve_challenge` choices whose `on_pass`/`on_fail`
reveal different pages; shuffle-decided secrets are `reveal_top:` over a hidden
deck; the inventory is just a board — keepsakes carry a tag whose home is that
board, so `gain:rusty_key` puts them there, and `card:<key>` tests for them;
endings are pages whose `on_pick` is `load_game:menu.json`.
Put `"irreversible": true` on the point of no return. Note that a choice card's
consequences are invisible until played — the tooltip tells the player exactly
as much as you write into it.

**Draft one of three from a real deck** (Architect):
`on_pick: ["add_to:hand", "return_to:offer:build_deck", "shuffle:build_deck", "pop_phase"]`.

**Challenges/trials**: `on_play: ["resolve_challenge"]` with `requires` /
`on_pass` / `on_fail` on the card. Make passes cost tribute (`on_pass` starts
with `move_to:graveyard` plus the toll) and make failures *persist*: `on_fail`
starts with `move_to:board`, the card carries `on_turn: ["lose_stat:…"]` so an
unanswered crisis drains you every round, and `on_activate:
["resolve_challenge"]` lets the player answer it later — failure becomes
escalating pressure instead of a slap.

**Stat-driven structure** (tiers, acts, loops): `next` routing on phases — see
the reference below. Progress trackers are just stats that cards raise in their
own `on_play`.

**Synergies**: `count:<tag>` amounts (`gain_stat:gold:count:economic`),
`needs`/`requires` on counts, computed tags for thresholds, `on_turn` engines,
and exhaust-limited `on_activate` bursts.

**Cards as currency**: a `"sacrifice:<tag>"` cost destroys one of your board
cards to pay for the play — upgrade chains (sacrifice a Militia to field a
Garrison), trials payable in blood instead of coin, and story dilemmas (give
up the lantern or the pearl). The oldest matching card is taken.

---

## 5. Reference

### Top-level fields

| Field | Meaning |
|---|---|
| `title` | Shown in the HUD |
| `seed` | Optional fixed RNG seed (reproducible shuffles) |
| `stats` | Ordered stat declarations (HUD order) |
| `computed_tags` | Derived per-card tags (see below) |
| `tags` | Tag behaviour — a tag can give its cards a home zone (see below) |
| `effects` | Named visual effects on the base vocabulary (see below) |
| `templates` | Card definitions (`cards` also accepted) |
| `zones` | Zone definitions, in declaration order |
| `phases` | Phase definitions; first entry starts the game |
| `end_conditions` | Outcome checks, first match wins, once per game |
| `setup.player` | Starting player stats — becomes the injected player card |
| `placeholder_art` | `true` gives every card without an `asset` generated art from its key |

### Stats

`{ "key", "label", "min", "max", "hidden", "subject" }`. Declared stats display with a
built-in icon (`gold` coin, `hp` heart, `defense` shield, `morale` banner,
`food` apple, others a diamond). Stat changes clamp to `min`/`max`; a card
stat with a `<key>_max` companion clamps to `[0, max]`. **Reserved:** `round`
(starts 1, +1 per round boundary) and `plays` (per-hand play counter) are
engine-managed — declare them only to display them.

`subject` overrides what the HUD row *reads* while the key still names what
cards spend: castle's defense lives on the buildings that provide it and shows
as their total, `{ "key": "defense", "subject": "sum:defense@standing" }`.

### Zones

| Field | Meaning |
|---|---|
| `key`, `label` | Identity and optional on-screen label |
| `type` | `deck` (face-down stack), `pile` (face-up stack), `hand` (row, shows card text), `grid` (board with slots) |
| `pos` | `[x1, y1, x2, y2]` window fractions — optional; each type has a default spot (hidden zones default off-screen, giving dealt cards their fly-in) |
| `grid` | `[cols, rows]` for grid zones |
| `fit` | Grid zones: `"card"` (default) keeps card proportions inside each cell, leaving breathing room; `"fill"` stretches cards to fill the cell, for board-game tiles |
| `contents` | Starting cards: `"key"` or `"key:count"` strings |
| `on_click` | Actions run when the zone is clicked |
| `per_seat` | `true` makes one copy of this zone per seat (see *Two or more players*). `pos` then takes one rect **per seat**: `[[…], […]]` |
| `tags` | See below |

Zone tags: `shuffle` (on contents creation and refill), `refill_when_empty`
(recreate `contents` when emptied), `face_up` / `face_down` (override facing),
`no_peek` (no tooltip/browse), `hidden` (not drawn; offer zones, fate decks).

Cards entering a grid without slot targeting auto-occupy the first free slot.
A full board refuses new arrivals: moves fail quietly and `fill`/`gain` stop
early (the validator warns when starting `contents` already exceed capacity).

### Card templates

| Field | Meaning |
|---|---|
| `key` | Unique identifier |
| `text`, `tooltip`, `asset`, `color` | Presentation. `asset` is optional and may be a filename, an `http(s)://` URL, a procedural shape spec, or `"auto"` (see *Art without assets*); `color` is `[r, g, b]` |

A local `asset` must be a bare filename (`sword.png`, not `../sword.png` or
a path) — this is enforced, not just a convention, since games can be
authored by people other than whoever is hosting the engine.

`asset` is normally a filename in `game/games/assets/`. It may instead be a
full `http://` or `https://` URL, e.g. `"asset": "https://i.imgur.com/0vnj0kx.jpeg"`.
A URL image is fetched at runtime and kept only in memory (never written to
disk) and is desktop/GUI only — the CLI and headless tests never load images,
and the browser build has no direct network access, so it instead asks the
page itself to `fetch()` the URL (using the player's own browser session —
cookies, cache, CORS) and hands the decoded bytes back; a host that doesn't
send permissive CORS headers will fail there exactly as a plain `<img>` tag
would. The fetch never blocks the game: on desktop it runs on a worker thread and on the browser it is an async `fetch()`, so an unreachable host costs nothing but a card without art. A URL asset shows blank for a frame or two while it loads (and
permanently, if the fetch fails) rather than being validated at load time —
there is nothing to check until the request actually runs.
| `story` | Long-form prose, shown on the reveal page panel and in the detail view |
| `tags` | Free vocabulary for targeting/counting; engine-known: `token` (vanishes instead of joining the discard; swept before new pass cards deal) |
| `card_stats` | Per-instance stats stamped at creation (`hp`/`hp_max` show a badge; 0 hp = ruined, skips `on_turn`) |
| `cost` | Spent on play; gates and dims when unaffordable. `"sacrifice:<tag>": n` pays by destroying n board cards with that tag |
| `activate_cost` | Spent on activation (sacrifices allowed here too) |
| `needs` | Non-consuming gate (shared condition subjects); escape hatch: playable anyway if nothing else in the zone is |
| `requires` | Checked by `resolve_challenge` → `on_pass` / `on_fail` |
| `target` | Click-to-target with the arrow. Fields: `type` (`"card"` or `"slot"`), `min`/`max` (or `count` for both), `tags` (all must match; computed tags count), `zones` (search only these — a per-seat key means *yours*), `owner` (`mine`/`enemy`/`anyone`) |
| `accepts` | Condition map deciding whether **this** card may be targeted by the card being played (see *Legality between two cards*) |
| `activate_target` | Same shape, for `on_activate`: clicking the board card opens targeting before the ability runs |
| `on_play` | Actions when played (ctx: this card + chosen targets) |
| `on_activate` | Actions when clicked on the board; **exhausts** the card until the round wraps. A board card shows three states: ready, greyed "exhausted" (spent this round), greyed "can't yet" (cost or targets unavailable) |
| `exhausts` | `false` keeps the card ready after activating — a permanently clickable button ("pass the time") |
| `on_turn` | Actions each round boundary while on a grid (and not ruined) |
| `on_pass`, `on_fail` | Challenge outcomes |
| `on_pick` | Actions when this card is picked from the built-in reveal overlay (pages) |
| `irreversible` | Playing or picking this card clears the undo stack — the choice is final |
| `outcome` | `"victory"` or `"defeat"` on an ending card: banner, run summary, and flourish when it is offered |
| `auto_play`, `to_zone`, `to_slot` | Start in play (e.g. the throne) |

### Phases

| Field | Meaning |
|---|---|
| `key`, `label` | Identity, HUD label |
| `type` | `automatic`, `player_input`, `draw_and_play`, `overlay` |
| `actions` | Run on entry (automatic phases) |
| `deck`, `draw`, `zone` | Deal `draw` cards from `deck` into `zone` (default `hand`) on fresh entry. **Naming `zone` also bounds what may be played**: only cards in it. A phase that names none lets any reachable card be played, which is what the menu relies on |
| `pass_card` | Card key or array, dealt with every hand — forced plays always have an out |
| `ends_after` | The phase advances itself after this many plays |
| `seat` | `"next"` hands over to the next seat on entry (see *Two or more players*) |
| `discard_hand` | Leaving the phase discards its unplayed hand (tokens vanish) |
| `on_pick` | Overlay only: actions run with the picked card |
| `page` | Overlay only: render its cards as full-screen story pages (title, `story` prose, click to continue) and run the *picked card's own* `on_pick` instead of the phase's. The built-in `reveal` overlay sets this |
| `next` | Routing table (below) |

Types: `automatic` runs its actions once and advances (if the actions opened
an overlay — a revealed page, say — it waits and advances when the overlay
closes); `player_input` lets you play freely; `draw_and_play` is shorthand
for `player_input` with `ends_after: 1` and `discard_hand: true`; `overlay`
dims the screen, deals into its zone, and resolves via `on_pick` — overlays
are push-only (never in the sequence) and lock all other actions.

Think of phases like Magic's turn structure: each phase declares what it
deals on entry (`deck`/`draw`/`pass_card`), how it ends (`ends_after` N
plays, a card whose actions say `next_phase`, or nothing — the player decides
via a pass card), and whether leaving it sweeps the hand (`discard_hand` —
the usual choice, so unpicked options don't pile up across turns).

The engine provides a built-in overlay phase `reveal` over a built-in hidden
zone `reveal`, used by the reveal actions. It renders cards as full-text story
pages (title, `story` prose, click to continue), runs the picked card's own
`on_pick`, and destroys the read page unless its actions moved it somewhere.

Routing: `"next": [ { <condition>, "then": "phase_key", "ends_round": true }, ... ]`.
First matching entry wins; a condition-less entry always matches; no `next`
means list order with an implicit round-ending wrap. `ends_round` is the only
thing that ticks the round: round counter +1, exhausted cards ready, `on_turn`
runs.

### Conditions (one vocabulary everywhere)

Used by `next`, `end_conditions`, `requires`, `needs`. Subjects: a stat key,
`count:<tag>` (cards on grid zones with that tag), or `card:<key>` (instances
of that specific template on grid zones — "does the player have the rusty key?").

- Object form: `{ "stat": "progress", "at_least": 12 }` (`equals` / `at_least` / `at_most`) or `{ "zone_empty": ["road", "hand"] }`.
- Map form (`requires`, `needs`, `accepts`): `{ "might": 8, "count:farm": 3 }` — a bare number means **at least** n, much the commonest thing to ask.
- To ask the other way, the value is a comparison instead:
  `{ "max:value@mine.red": { "at_most": 6 } }`.

**A comparison may be measured against another subject, not just a constant.**
The type decides at run time — a number is a number, a string is measured:

```json
{ "stat": "score@north_side", "at_least": "score@south_side" }
{ "value@target": { "at_least": "max:value@mine.red" } }
```

A subject used this way must *look* like one — it has to name a scope (`@…`)
or a measuring fn (`sum:`, `max:`, `count:`, `card:`). A bare word is treated
as a typo and fails the comparison closed, rather than quietly reading as an
unknown stat worth nothing.

`end_conditions` fire once per game (first match), wait for open overlays, and
run their `then` actions — usually `push_phase:` to an ending overlay.

**Scopes: which cards a subject is about.** The part after `@` is a *scope
expression*: `[<quant>.][<owner>.]<zone-or-tag>`, where the name is a zone key,
a tag, or one of `self` / `target` / `all`. Without any scope, a subject means
**your own cards** — see *The player is a card* below.

```
insight@player       the stat on cards carrying the "player" tag
hp@each.follower     every follower, individually
hp@random.follower   one follower, chosen by the seeded shuffle
hp@self              the acting card
hp@target            the cards the player chose for this card
sum:defense@board    a stat summed over one zone
max:rank@tableau     the largest value in one zone
count:farm@board     count, narrowed to a zone
```

A **tag** scope means cards *in play* — on grid zones — exactly like
`count:<tag>`. A card in hand is not on the board; name the zone (`@hand`) when
that is what you want. Zone and tag names may never collide, and the validator
refuses a file where they do.

**Owner words** say whose cards, and compose with everything else:

```
hp@each.enemy.creature   every creature an opponent owns
sum:value@mine.red       my red expedition's total
count:beast@anyone.board every seat's beasts, said out loud
```

| Word | Means |
|---|---|
| `mine` | owned by the seat whose turn it is |
| `enemy` | owned by any other seat |
| `anyone` | no filter — identical to writing no owner word, but says so deliberately |

A card's owner is **the seat of the zone it sits in**. A card in a shared zone
(a common deck, a market row) belongs to nobody, so `mine` and `enemy` both
pass it over and only `anyone` — or no word at all — reaches it. In a
one-player game every word names the same cards and `enemy` names none, so
none of this is visible until a second seat exists.

**Quantifiers** say which member, and they work identically in conditions,
costs and effects:

| | Condition holds when | As a cost | As an effect |
|---|---|---|---|
| `any` (default) | the pool reaches n | drains members until n is paid | lands on the first member |
| `each` | **every** member reaches n | every member pays n | applies to every member |
| `random` | as `any` | as `any` | lands on one member |
| `@target` | every chosen target reaches n | every target pays n | applies to every target |

`each` over an empty scope is **false**, never vacuously true — otherwise
`{ "hp@each.follower": 1 }` would be free exactly when you have no followers.

Costs may carry a scope but not a measuring function: `count:` and `sum:` count
things rather than spend them, so they belong in `needs`, not `cost`.

### The player is a card

There is no player object. `setup.player` becomes an invisible card tagged
`player`, and a subject with no scope means that card — so `"cost": { "gold": 2 }`
and `{ "stat": "gold", "at_least": 5 }` are guaranteed to be talking about the
same coins. Nothing else changes for a game that never thinks about it.

Tag a template `player` and it becomes the player instead, with no stat bag
injected. `castle.json` does this with its throne room: the hero is a real card
on the board, so it can be looked at, damaged, targeted and destroyed like any
other, and its stats are the player's stats.

```json
{ "key": "throne_room", "tags": ["building", "hero", "player"],
  "card_stats": { "hp": 20, "gold": 20, "morale": 5 },
  "auto_play": true, "to_zone": "board", "to_slot": 13 }
```

A **party** is the same idea repeated: N cards in a zone, each tagged `player`,
each with its own `card_stats`. Per-character stats, targeting, death and
revival are all ordinary card behaviour — `sum:might@party` asks what the party
has between them, `"activate_cost": { "mana@self": 1 }` makes a character pay
from her own pool. Note that with several player cards a *bare* subject means
all of them at once; name a scope when you mean one.

`round` lives on a second injected card, not on the player: it belongs to the
game, so a hero who dies does not take the calendar with them.

**Aggregates beat running totals.** If a number is produced by cards, store it
on those cards and read it with `sum:`. Castle's defense used to be a global
counter a watchtower added 2 to on play — and a watchtower reduced to rubble
went on defending the castle forever, because nothing ever subtracted it again.
As `card_stats` plus `sum:defense@standing` (with `standing` a computed tag for
`hp` at least 1), that bug is not expressible.

### Two or more players

A **seat is a card tagged `player`**, named by its own key. Declaring two is
all it takes; each carries its own stats, and neither can touch the other's.

```json
{ "key": "north", "text": "North", "tags": ["player", "north_side"],
  "card_stats": { "score": 0 } },
{ "key": "south", "text": "South", "tags": ["player", "south_side"],
  "card_stats": { "score": 0 } }
```

A seat with no `to_zone` is auto-played into the hidden `system` zone — an
invisible stat holder. Give it one (`"to_zone": "board"`) when the seat should
be a visible hero on the table.

**Zones that belong to a seat** declare `per_seat`, and are then created once
per seat with one rect each:

```json
{ "key": "hand",  "type": "hand", "per_seat": true,
  "pos": [[0.02, 0.75, 0.78, 0.87], [0.02, 0.88, 0.78, 0.99]] },
{ "key": "arena", "type": "grid", "grid": [5, 1], "per_seat": true,
  "pos": [[0.02, 0.05, 0.60, 0.30], [0.02, 0.32, 0.60, 0.57]] }
```

An unqualified zone key means **the active seat's** copy — `move_to:arena`
puts the card in your own arena, `draw_from:deck:hand:1` deals into your own
hand. Say `enemy.arena` for the other. A `per_seat` zone also receives its own
copy of every `auto_play` card, so a marker declared once appears in each
seat's copy.

**Turn order is the phase list.** A phase declaring `"seat": "next"` hands over
on entry, so alternation is just two phases:

```json
{ "key": "north_play", "type": "player_input", "zone": "hand",
  "seat": "next", "ends_after": 1 },
{ "key": "north_draw", "type": "player_input", "zone": "draw_choice",
  "pass_card": "draw_deck" }
```

Handing over **clears the undo history** — undoing across it would either show
a player something they never saw or rewrite a decision that was not theirs.

Three rules the engine enforces so no interface has to: a card in another
seat's zone cannot be played; a card outside the phase's declared `zone` cannot
be played; and a target the rules did not allow is refused even if a script
passes it directly.

Everything above is invisible in a one-player game: there is exactly one seat,
every owner word means the same cards, and no handover ever happens.

### Legality between two cards

Some rules are about **the card being played and the place it lands** — "a card
may go on a higher one", "onto a card of the opposite colour". Neither `needs`
(which asks about game-wide state) nor a computed tag (which asks about one
card alone) can express that, because it takes two cards at once.

`accepts` lives on the **destination** and is asked of each candidate, with
itself as `@self` and the arriving card as `@target`:

```json
{ "key": "red_route", "tags": ["marker", "red_dest"],
  "auto_play": true, "to_zone": "red",
  "accepts": { "value@target": { "at_least": "max:value@mine.red" } } }
```

That single line is the whole of Lost Cities' expedition rule: a card must be
worth at least what is already there. A destination with **no** `accepts` takes
anything — which is how the same game's discard pile stays always legal:

```json
{ "key": "red_tip", "tags": ["marker", "red_dest"],
  "auto_play": true, "to_zone": "red_discard" }
```

The card being played just names both destinations and goes where it is
pointed:

```json
{ "key": "red_7", "card_stats": { "value": 7 },
  "target": { "type": "card", "tags": ["red_dest"], "count": 1,
              "zones": ["red", "red_discard"] },
  "on_play": ["move_to:target"] }
```

Putting the rule on the destination rather than on the card is what lets it
name its own zone: the red route marker knows it lives in `red`, so it needs no
way to say "wherever I happen to be". A marker card in an otherwise empty zone
also gives the empty case something to target.

**Targeting takes the owner words too**, so "choose an enemy creature" needs no
syntax of its own: `{ "type": "card", "tags": ["creature"], "owner": "enemy",
"count": 1 }`. And a spec that lists `zones` means *yours* — it never offers
another seat's copy of a per-seat zone unless an owner word says so.

### Computed tags

Per-card derived tags from that card's own stats:

```json
"computed_tags": { "damaged":  { "stat": "hp", "less_than_stat": "hp_max" },
                   "standing": { "stat": "hp", "at_least": 1 } }
```

Comparators: `less_than`, `less_than_stat`, `at_least`, `equals`. Usable
anywhere card tags are (targeting, `count:`, and as a scope — castle reads
`sum:defense@standing` so rubble stops defending).

### Tags with behaviour

A game can give tags meaning of their own — types, essentially:

```json
"tags": { "item": { "zone": "inventory" }, "unit": { "zone": "battlefield" } }
```

**Zones and tags share one namespace.** A condition that points at a name
means either the zone or the cards carrying that tag, so the two may never
collide — the validator refuses a file where they do, rather than picking a
winner by a precedence rule you would have to remember. `self` and `all` are
reserved for the engine. (`player` is not reserved: it is an ordinary tag you
put on one card, which is exactly what makes that card easy to find.)

A tag's `zone` is the home of every card carrying it, and placement then
works by type instead of by naming zones in every action:

- `move_to` without a zone sends the played card home (`"on_play": ["move_to"]`).
- `gain:card:n` creates cards directly in their home zone (no home: the hand).
- `auto_play` cards without a `to_zone` start in their home zone.

A game with a single board stays simple: cards without a home fall back to
it. With two or more boards (an inventory *and* a battlefield, say), every
card that enters play must know where it goes — the validator flags cards
whose tags don't say, and reports the conflict when a card's tags disagree.

### Board buttons

A card that starts in play and never leaves is the engine's button. Combine
`auto_play` with `on_activate`, and `exhausts: false` when it should stay
clickable rather than tiring for the round:

```json
{ "key": "pass_time", "text": "Let time pass", "auto_play": true,
  "to_zone": "table", "to_slot": 1, "exhausts": false,
  "on_activate": ["next_phase"] }
```

Add `activate_target` when the button needs to be pointed at something —
clicking it opens the same targeting arrow a played card uses, and the chosen
cards arrive in `on_activate` as targets:

```json
{ "key": "workbench", "auto_play": true, "to_zone": "table",
  "activate_cost": { "focus": 1 },
  "activate_target": { "type": "card", "count": 1, "tags": ["material"], "zones": ["table"] },
  "on_activate": ["lose_stat:hp@target:1", "gain_stat:progress:2"] }
```

### Effects

A game names its own visual effects on a base vocabulary — the classics —
and triggers them from any action list with `effect:<name>`:

```json
"effects": {
  "sabre_hit":   { "base": "damage" },
  "wagon_blaze": { "base": "explosion", "size": 1.5, "color": [1.0, 0.6, 0.2] }
}
```

Bases: `damage` (slash burst), `bleed` (falling drops), `power_up` (rising
motes and a ring), `sparkle` (twinkling points), `stars` (orbiting stars),
`heal` (rising crosses), `smoke` (drifting puffs), `explosion` (debris and a
shockwave). Parameters `size`, `speed` and `count` are multipliers that
default to 1; `color` is `[r, g, b]` and defaults per base. The effect plays
on the acting card (mid-screen when there is none), is skipped headless, and
a card losing hp gets a small damage burst automatically.

### Actions

Colon-separated strings; unknown ops log and skip.

**Numeric slots** take a number, or a measuring fn over a subject —
`count:<tag>`, `card:<key>`, `sum:<subject>`, `max:<subject>` — optionally
multiplied by a second such term with `:x:`, left to right:

```
gain_stat:gold:count:economic                        one per economic card
gain_stat:score:sum:value@mine.red:x:count:wager@mine.red
lose_stat:score:20:x:count:wager@mine.red            the same product, distributed
```

**Zone slots** take a scope expression too, so `arena` is the active seat's and
`enemy.arena` the other's.

| Action | Effect |
|---|---|
| `fill:zone:card:n` | Create n instances of card in zone |
| `shuffle:zone` | Shuffle |
| `draw_from:from:to:n` | Move n cards off the top |
| `return_to:from:to` | Move all cards (bounded; safe with refilling zones) |
| `move_to:zone` | Move the acting card (uses a slot target when given); without a zone, its home tag decides |
| `move_to:target` | Move the acting card into the **chosen target's** zone — how one card offers two destinations ("advance the expedition, or discard it") |
| `gain:card:n` | Create n instances of a card in its home zone (or the hand) |
| `add_to:zone` | Move the acting card (overlay picks) |
| `move_target_to:zone` | Move each targeted card |
| `gain_stat:stat:n` / `lose_stat:stat:n` | Change the stat holder's total (clamped, logged, floats) |
| `spend_stat:stat:n` | Alias of lose (costs) |
| `set_stat:stat:n` | Set directly (dev/authoring tool; silent) |
| `gain_stat:<subject>:n` / `lose_stat:<subject>:n` | Change a stat. The subject may carry a scope: `hp@target`, `hp@each.follower`, `hp@random.beast` |
| `attach_to_target` | Attach the acting card under the first target |
| `resolve_challenge` | Check the card's `requires`, run `on_pass`/`on_fail` |
| `effect:name` | Play a named visual effect on the acting card (headless: skipped) |
| `reveal:card` | Conjure the card into the page overlay; its `on_pick` continues |
| `reveal_top:zone` | Turn over a zone's top card into the page overlay (shuffle secrets) |
| `next_phase` / `push_phase:key` / `pop_phase` | Phase control |
| `destroy:<scope>` / `destroy_self` | Remove cards from play entirely. A bare zone key is a scope, so `destroy:hand` is unchanged; `destroy:each.enemy.creature` is a board wipe that spares your own. A card cannot be partly destroyed, so only `random.` narrows — to one victim |
| `load_game:file` | Switch games (menu items, endings). `file` must be a bare `name.json` — no path, no `..` — and is refused otherwise |

### Engine behaviors you get for free

Undo (Z / button, 50 steps, includes the event log — cleared by `irreversible`
cards), the built-in story-page overlay, the corner event log (L
expands), tooltips and detail views (right-click / long-press), zone browsing
on face-up piles, cost/needs dimming, targeting arrow with eligibility
highlighting, exhaust greying, floating stat deltas, card flight/impact
effects, touch controls, window-scaled UI, seeded runs
(`luajit play.lua game.json 42`, `RAVEL_SEED`, or `"seed"` in the file), CLI
play, networked play over any of three transports (see below), the TCP debug
API (`RAVEL_DEBUG=1`), live template editing
(`edit`/`dump`/`reload` + GUI hot-reload), and whole-file validation on load,
reload and via `luajit check.lua mygame.json` — unknown fields and sections,
bad shapes, broken references and conflicts, with did-you-mean suggestions.

### Playing over a network

Any game with two seats is already playable between two people on different
machines, and no game file needs a single line changed for it. What the engine
transfers is the whole game state — so what a game has to do to be networkable
is exactly what it had to do to be hot-seatable: tag two cards `player`, and
give the turn-taking phases `"seat": "next"`.

Three ways to connect, all of them without a server:

- **Two tabs of the same browser.** Click *Link tabs (same browser)* in each.
  They find each other over the page's own broadcast channel — which is scoped
  to **one browser profile**. Two tabs or two windows of the same browser work;
  Firefox next to Chrome does not, and neither does a private window next to a
  normal one. Use the internet invite for those.
- **Two computers, over the internet.** Load a two-player game, click *Invite
  over the internet*, send your opponent the ~1300-character blob it puts in the
  box, paste their reply back, and the two browsers are talking directly — no
  server, no port forwarding, and nothing to paste for the rest of the game.
  **Your opponent does not need the game**: if they do not have the file, it is
  sent over the connection and they play a game they have never seen. What does
  not travel is anything the file only points at — a game naming local image
  files renders as text on their side, while `placeholder_art` looks identical
  because it is generated. It fails on some mobile and carrier-NAT connections,
  where copy/paste is the fallback. The blob contains your IP address, which is
  what it is for: send it in a DM, not to a public channel.
- **Copy and paste.** One player runs `n host mygame.json 4242` in the CLI (or
  the browser's *Copy state*) and sends the other the 34-character invite it
  prints. From then on each turn is a ~300-byte string that fits in a Discord
  message. Both sides start from the same seed, which is why the messages stay
  that small.
- **A shared folder.** `n folder <dir> <me> <them>` in the CLI writes one file
  per side. Point it at anything that syncs — Syncthing, a mounted share — and
  it is a cross-machine game with nothing else to install.

The browser accepts all four kinds of string in the one box, and works out
which it is: a state, an invite, a peer-to-peer offer or its answer.

### Offering it from your own game

Networking is something a **card** does, so a game decides whether to mention it
at all. Five actions, checked by the validator like any other:

| | |
|---|---|
| `net_invite` | build an invite to send someone |
| `net_join` | open the box to paste one into |
| `net_seat:<seat>` | sit in a particular chair (`net_seat:any` to give it up) |
| `net_panel` | just show the networking controls |
| `net_offline` | disconnect |

The menu's own entry is one card:

```json
{ "key": "play_lost_cities_net", "text": "Lost Cities · online",
  "on_play": ["load_game:lost_cities.json", "net_seat:north", "net_invite"] }
```

None of them changes game state — they ask the interface to show something — so
they are safe to play before anything is connected, which is when you need them.
A game that never names them never grows a networking widget.

Claim a seat (*play as: north* in the panel, `n seat north` in the CLI) and the
engine stops you moving on your opponent's turn: their cards read as unplayable
rather than accepting a click and refusing it.

**Both players can see everything**, hidden zones included, and either of them
could hand the other any position at all — nothing checks that an arriving state
was reached by a legal move. Both would need a referee the engine does not have
(`ideas/DONE.md` says what that would cost). So: play with people you
trust, and think twice before shipping a game whose whole tension is a secret
hand.

### Hardcoded conventions

`menu.json` boots the engine. Zone keys `hand` (default deal/pick target),
`graveyard` (draw_and_play discard), `board` (default `auto_play` target) are
load-bearing names; `reveal` names both the built-in page zone and overlay
phase, and `system` the hidden zone holding the engine's own two cards (a game
may declare any of them to override). The tag `player` marks a seat, and the
card key `system` the round counter. Clicking a face-up card plays it; clicking
a grid card activates it; decks aren't clickable (give them `on_click` if
needed).

Reserved words that a zone or tag may never be named: `self` and `all` (the
engine answers for them in scopes), plus the quantifiers `any` / `each` /
`random` and the owner words `mine` / `enemy` / `anyone`, which are read as
prefixes in a scope expression rather than as names. `player` is deliberately
*not* reserved — it is an ordinary tag you put on a card.
