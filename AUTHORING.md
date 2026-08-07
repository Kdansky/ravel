# Authoring Games for Ravel

A game is one JSON file in `game/games/`, plus optional images in
`game/games/assets/` (sources and licenses are recorded in
`assets/CREDITS.md` — keep it that way when adding art). No code. This document walks through building a game, then lists everything the
engine understands. `DESIGN.md` explains *why* things are shaped this way;
`ARCHITECTURE.md` explains the engine internals.

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

## 3. Common patterns

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

## 4. Reference

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

### Stats

`{ "key", "label", "min", "max", "hidden", "subject" }`. Declared stats display with a
built-in icon (`gold` coin, `hp` heart, `defense` shield, `morale` banner,
`food` apple, others a diamond). Stat changes clamp to `min`/`max`; a card
stat with a `<key>_max` companion clamps to `[0, max]`. **Reserved:** `round`
(starts 1, +1 per round boundary) and `plays` (per-hand play counter) are
engine-managed — declare them only to display them.

`subject` overrides what the HUD row *reads* while the key still names what
cards spend: a stat produced by cards can display as their total,
`{ "key": "might", "subject": "sum:might@party" }`.

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
| `text`, `tooltip`, `asset`, `color` | Presentation (asset optional; color `[r,g,b]`) |

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
| `target` | `{ "type": "card"\|"slot", "min", "max" (or "count"), "tags": [...], "zones": [...] }` — click-to-target with the arrow |
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
| `deck`, `draw`, `zone` | Deal `draw` cards from `deck` into `zone` (default `hand`) on fresh entry |
| `pass_card` | Card key or array, dealt with every hand — forced plays always have an out |
| `ends_after` | The phase advances itself after this many plays |
| `discard_hand` | Leaving the phase discards its unplayed hand (tokens vanish) |
| `on_pick` | Overlay only: actions run with the picked card |
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

- Object form: `{ "stat": "progress", "at_least": 12 }` (`equals` / `at_least` / `at_most`, numbers only) or `{ "zone_empty": ["road", "hand"] }`.
- Map form (`requires`, `needs`): `{ "might": 8, "count:farm": 3, "card:pearl": 1 }` — each subject must total at least n.

`end_conditions` fire once per game (first match), wait for open overlays, and
run their `then` actions — usually `push_phase:` to an ending overlay.

**Scopes: which cards a subject is about.** Add `@<name>`, where the name is a
zone key, a tag, or one of `self` / `target` / `all`. Without one, a subject
means **your own cards** — see *The player is a card* below.

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


### Computed tags

Per-card derived tags from that card's own stats:

```json
"computed_tags": { "damaged": { "stat": "hp", "less_than_stat": "hp_max" },
                   "ruined":  { "stat": "hp", "equals": "0" } }
```

Comparators: `less_than`, `less_than_stat`, `at_least`, `equals`. Usable
anywhere card tags are (targeting, `count:`).

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

Colon-separated strings; unknown ops log and skip. Every numeric slot accepts
a number, `count:<tag>` **or** `card:<key>`.

| Action | Effect |
|---|---|
| `fill:zone:card:n` | Create n instances of card in zone |
| `shuffle:zone` | Shuffle |
| `draw_from:from:to:n` | Move n cards off the top |
| `return_to:from:to` | Move all cards (bounded; safe with refilling zones) |
| `move_to:zone` | Move the acting card (uses a slot target when given); without a zone, its home tag decides |
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
| `destroy:zone` / `destroy_self` | Remove cards from play entirely |
| `load_game:file` | Switch games (menu items, endings). `file` must be a bare `name.json` — no path, no `..` — and is refused otherwise |

### Engine behaviors you get for free

Undo (Z / button, 50 steps, includes the event log — cleared by `irreversible`
cards), the built-in story-page overlay, the corner event log (L
expands), tooltips and detail views (right-click / long-press), zone browsing
on face-up piles, cost/needs dimming, targeting arrow with eligibility
highlighting, exhaust greying, floating stat deltas, card flight/impact
effects, touch controls, window-scaled UI, seeded runs
(`luajit play.lua game.json 42`, `RAVEL_SEED`, or `"seed"` in the file), CLI
play, the TCP debug API (`RAVEL_DEBUG=1`), live template editing
(`edit`/`dump`/`reload` + GUI hot-reload), and whole-file validation on load,
reload and via `luajit check.lua mygame.json` — unknown fields and sections,
bad shapes, broken references and conflicts, with did-you-mean suggestions.

### Hardcoded conventions

`menu.json` boots the engine. Zone keys `hand` (default deal/pick target),
`graveyard` (draw_and_play discard), `board` (default `auto_play` target) are
load-bearing names, and `reveal` names both the built-in page zone and overlay
phase (a game may declare its own to override them). Clicking a face-up card
plays it; clicking a grid card activates it; decks aren't clickable (give them
`on_click` if needed).
