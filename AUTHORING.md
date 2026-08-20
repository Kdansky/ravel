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

**Hold ctrl and point at anything** in the running game — a card, the square
under it, the zone it lies in — to read the JSON behind it: the template (your
JSON, plus whatever the parser derived from it — a card with `moves` grew the
the `activate.target` that makes those moves clickable), the live entity the engine
made of it, and the things the engine works out rather than stores anywhere
(whose piece it is, and *every* tag that is true of it
right now, including the ones its zone grants and the computed ones that are
true only while a stat holds). The mouse wheel scrolls the panel and ctrl+C
copies it, so a dump can go straight back into the game file.

---

## 1. Walkthrough: a minimal game

```json
{
  "title": "My Game",
  "stats": [{ "key": "hp", "label": "Health", "min": 0, "max": 10 }],
  "zones": [
    {
      "key": "deck",
      "type": "deck",
      "pos": [0.05, 0.1, 0.25, 0.6],
      "tags": ["shuffle"],
      "contents": ["sword:3", "trap:2"]
    },
    { "key": "hand", "type": "hand", "pos": [0.19, 0.65, 0.95, 0.98] }
  ],
  "players": [{ "stats": { "hp": 5 } }],
  "cards": [
    {
      "key": "sword",
      "text": "Sword",
      "tooltip": "Gain 1 health.",
      "play": { "action": ["stat_gain:hp:1", "draw_from:deck:hand:1"] }
    },
    {
      "key": "trap",
      "text": "Trap",
      "tooltip": "Lose 2 health.",
      "play": { "action": ["stat_damage:hp:2", "draw_from:deck:hand:1"] }
    }
  ],
  "phases": [
    { "key": "setup", "type": "automatic", "actions": ["draw_from:deck:hand:1"] },
    { "key": "playing", "type": "player_input", "label": "Playing" }
  ],
  "end_conditions": [{ "when": "hp == 0", "then": ["load_game:menu.json"] }]
}```

The recipe, in order:

1. **Stats** — the numbers of your game. Declared stats show in the HUD (add
   `"tags": ["hidden"]` to keep one internal). Starting values go in the seat's
   `stats` under `players`.
2. **Zones** — where cards live. `pos` is window fractions `[x1, y1, x2, y2]`;
   positions off-screen (negative y) make cards fly in from outside. Decks own
   their starting cards via `contents`.
3. **Cards** — one entry per card *kind*. Instances are created from these;
   editing one live changes every instance, which is why the engine calls them
   templates internally even though the section is `cards`.
4. **Phases** — the turn structure. The first phase starts the game; `automatic`
   phases run and advance immediately.
5. **End conditions** — how the game ends. Endings are just overlay phases that
   deal a "fate card" whose `play.action` loads the menu.

The menu itself is a game (`menu.json`); add a card with
`"play": { "action": ["load_game:mygame.json"] }` to make yours reachable.

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
  "zones": [{ "key": "hand", "type": "hand" }],
  "cards": [
    {
      "key": "p_door",
      "text": "The Cellar Door",
      "story": "It was locked all your childhood. Tonight it stands open.",
      "play": { "action": ["fill:hand:c_down:1", "fill:hand:c_away:1"] }
    },
    {
      "key": "c_down",
      "text": "Take the stairs",
      "tooltip": "You always wanted to know.",
      "play": { "action": ["reveal:p_dark"] }
    },
    {
      "key": "c_away",
      "text": "Close the door",
      "tooltip": "Some doors are better shut.",
      "play": { "action": ["reveal:e_away"] }
    },
    {
      "key": "p_dark",
      "text": "Down",
      "story": "The stairs go further than the house is tall.",
      "play": { "action": ["destroy:hand", "fill:hand:c_away:1"] }
    },
    {
      "key": "e_away",
      "text": "An Ordinary Life",
      "story": "You bolt it, and that is that.",
      "play": { "action": ["load_game:menu.json"] }
    }
  ]
}
```

Two rules carry every story:

- **Pages** are cards with `story` (the prose) and `play.action` (what happens
  when the read page is clicked away). **Choices** are cards with `tooltip`
  (what the player is told) and `play.action` (what secretly happens — usually a
  `reveal:`). The tooltip reveals exactly as much as you write into it.
- **Every page that deals new choices starts its `play.action` with
  `destroy:hand`**, or the old choices pile up next to the new ones. A page
  that keeps the hand (a locked door, a rebuff) uses `"play": { "action": [] }`.

From there: keepsakes are cards with a home-zone tag (`gain:` them, test
them with `card:<key>`), shuffle secrets are `reveal_top:` over a hidden
deck, and endings are pages whose `play.action` is `load_game:menu.json` plus
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
   `play.action: ["move_to:target"]`. A choice with no card attached ("pass",
   "draw from the deck") is a `pass_card` token whose `play.action` does the thing
   and calls `next_phase`.
6. **Turn placement restrictions into `receive.needs`** on the destination, never
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
| "Cards must be played in ascending order" | `receive.needs` on the destination |
| "Costs 2 gold" | `"play": { "cost": { "gold": 2 } }` |
| "Only if you control a farm" | `"play": { "needs": ["count:farm >= 1"] }` |
| "Draw from the deck or a discard pile" | a token in the draw phase's `zone` for the deck; for the piles, `"applies": ["takeable"]` on each and one tag def carrying an `activate` block |
| "Only during your main phase" | `"play": { "phases": ["main"] }`, or `activate.phases` for the ability |
| "Put it on the discard pile" | `"target": { "type": "zone", "zones": ["discard"] }` — point at the place, not at a card lying in it |
| "Discard a card of your choice" | an `overlay` phase over the hand; the zone `applies` a tag whose `play.action` discards |
| "Destroy all enemy creatures" | `destroy:each.enemy.creature` |
| "Choose an enemy creature" | `"target": { "tags": ["creature"], "owner": "enemy", "count": 1 }` |
| "Roll / draw randomly" | `shuffle` then `reveal_top:<zone>` |
| "The game ends when the deck is empty" | a route on `{ "zone_empty": ["deck"] }` |
| "Score 3 points per set" | a scoring card: `stat_gain:score:3:x:count:<tag>` |
| "(sum − 20) × multiplier" | two actions: `stat_gain:score:sum:…:x:…` then `stat_damage:score:20:x:…` |
| "Whoever has more points wins" | a route: `{ "when": "score@north_side >= score@south_side" }` |
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
- **Triggered abilities** — "when a creature dies, …". `turn.action` (each round
  boundary) is the only automatic hook; anything else has to be a card the
  player is made to play.
- **Continuous effects / auras** — "all your beasts have +1 while this is in
  play". Model it as a stat change applied once, or leave it out.
- **Arithmetic beyond a product** — amounts multiply, but there is no division,
  no subtraction inside one amount, and no parentheses. Distribute it into
  separate actions, as the scoring row above does. Subtraction *between*
  actions is free and clamps at the stat's floor, which is `max(0, a - b)` and
  further than it looks (see *Actions*); a clamp anywhere but at the floor —
  "never below one" — is genuinely missing.

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
"asset": "chequer:8:black:white" "asset": "auto"
```

| Shapes | |
|---|---|
| no count | `circle`, `square`, `triangle`, `diamond`, `cross` |
| counted | `polygon:3–12`, `star:3–12`, `stripes:2–16`, `chequer:2–16`, `dots:1–8` |

Colours are `#rrggbb` or a palette name: `black white grey slate ash silver
red crimson maroon pink orange amber gold yellow sand tan brown olive green
forest teal cyan blue navy indigo violet purple magenta`. A second colour is
the background; with only one, the background is a dark wash of the first, so a
one-colour spec looks deliberate. Counts outside a shape's range are clamped.

**`"asset": "auto"`** derives a shape, a count and a hue from the card *key*.
Same card, same art, every run and every machine — no authoring at all, and no
RNG draw, so it cannot shift a seeded shuffle. **Tag a card `generate_art`** and
it gets the same thing without naming an asset at all — which is how a handful of
cards can carry generated shapes among a deck of photographs, and how a brand-new
game gets visual differentiation before it has any art.

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
- Write a scripted test in `tests/integration/`: a module returning a table,
  and a `test_my_game(check)` function in it with a fixed seed, a few forced
  moves and assertions on the end state. Ten lines, and it is the only thing
  that will notice when an engine change breaks your game.
  `luajit tests/run.lua my_game` runs just that one.

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
  "play": { "action": ["load_game:menu.json"] } }
```

**Turn cycle with forced plays** (Castle Lord): `draw_and_play` phases in list
order; playing one card discards the hand and advances; the list wraps to the
first non-automatic phase, which ends the round. Always give these a `pass_card`.

**Free-play draft hands** (Coronation): a `player_input` phase with `deck`,
`draw` and a `pass_card` deals a hand you play freely from; a Done/router token
with `"play": { "needs": ["plays >= 1"], "action": ["destroy_self", "next_phase"] }` ends the hand.

**Sub-card choices**: options live in a hidden internal deck; the parent card
pushes an overlay over it, and the offer zone `applies` a tag whose `play.action`
sends the chosen card to hand and returns the rest — behaviour that belongs to
the offer, not to the buildings it deals.
Option cards can carry their own `cost` (a priced transformation).

**Classical CYOA** (The Drowned Tower): pages are cards with a `story` field;
choice cards `reveal:` them. A revealed page fills the screen; clicking it runs
the page's own `play.action` — typically `destroy:hand` then `fill:hand:...` with
the next choices, so the story chains without any phase plumbing. Secret
conditional branches are `resolve_challenge` choices whose `challenge.pass`/`challenge.fail`
reveal different pages; shuffle-decided secrets are `reveal_top:` over a hidden
deck; the inventory is just a board — keepsakes carry a tag whose home is that
board, so `gain:rusty_key` puts them there, and `card:<key>` tests for them;
endings are pages whose `play.action` is `load_game:menu.json`.
Tag the point of no return `no_undo`. Note that a choice card's
consequences are invisible until played — the tooltip tells the player exactly
as much as you write into it.

**Draft one of three from a real deck** (Architect):
`pick.action: ["add_to:hand", "return_to:offer:build_deck", "shuffle:build_deck", "pop_phase"]`.

**Challenges/trials**: `play.action: ["resolve_challenge"]` with a `challenge` block —
`challenge.pass` / `challenge.fail` on the card. Make passes cost tribute (`pass` starts
with `move_to:graveyard` plus the toll) and make failures *persist*: `on_fail`
starts with `move_to:board`, the card carries `turn.action: ["stat_damage:…"]` so an
unanswered crisis drains you every round, and `activate.action:
["resolve_challenge"]` lets the player answer it later — failure becomes
escalating pressure instead of a slap.

**Stat-driven structure** (tiers, acts, loops): `next` routing on phases — see
the reference below. Progress trackers are just stats that cards raise in their
own `play.action`.

**Synergies**: `count:<tag>` amounts (`stat_gain:gold:count:economic`),
`needs` on counts (a card's own, or a challenge's), computed tags for thresholds, `turn.action` engines,
and exhaust-limited `activate.action` bursts.

**A card as its own currency**: `"exhaust": 1` in an `activate.cost` is MTG's
tap symbol — the ability spends the card *being ready*, and a card already spent
cannot pay it, which is the whole of "once a round". An ability that does not
charge it stays available all round. Only an activate cost may ask for it: a
card leaving a hand has nothing to stay spent.

**Cards as currency**: a `"sacrifice:<tag>"` cost destroys one of your board
cards to pay for the play — upgrade chains (sacrifice a Militia to field a
Garrison), trials payable in blood instead of coin, and story dilemmas (give
up the lantern or the pearl). The oldest matching card is taken.

---

## 5. Reference

The two walkthroughs below are checked by the test suite — they are parsed out
of this file and run through the validator, so an example that stops working
fails a test rather than wasting your afternoon.

`SCHEMA.json` at the repository root lists **every field a game file may
contain**, laid out as a game file with a sentence where each value would be. A
test holds it and the engine to the same field set in both directions, so it
cannot quietly go out of date. Read this section to learn the format; read that
file to check what may appear where.

### Top-level fields

| Field | Meaning |
|---|---|
| `title` | Shown in the HUD |
| `seed` | Optional fixed RNG seed (reproducible shuffles) |
| `stats` | Ordered stat declarations (HUD order) |
| `computed_tags` | Derived per-card tags (see below) |
| `styles` | Named looks, claimed by tagging one (see *Styles*) |
| `tags` | Tag behaviour — a tag is a mixin: it can give its cards a home `zone`, a `tooltip`, and an `activate` block (the same one a card has), which a zone may then hand to its contents with `applies` (see below) |
| `effects` | Named visual effects on the base vocabulary (see below) |
| `patterns` | Named direction sets for grid movement (see *Pieces that move*) |
| `assets` | Named pictures, and the only place a picture carries options (see *Named assets*) |
| `cards` | Card definitions — one entry per card *kind* |
| `zones` | Zone definitions, in declaration order |
| `phases` | Phase definitions; first entry starts the game |
| `end_conditions` | Outcome checks, first match wins, once per game |
| `players` | Who is playing, in seat order (see *Players*) |
| `setup` | How the game begins: `place` lays out whatever starts on the table (see *Setup*) |

### Stats

`{ "key", "label", "min", "max", "subject", "icon", "color", "tags" }`.

`icon` is the shape drawn beside the number, on a card face and in the HUD:
`coin`, `heart`, `shield`, `banner`, `leaf`, `blade`, or `diamond`. **Named by
shape, not by meaning** — what your game calls its currency is your business,
and the engine has no opinion about which word means money. A closed set: a
shape nobody draws is refused rather than silently becoming a diamond. Left
out, it *is* the diamond.

`color` is what colour that shape is drawn in — a palette name or `#rrggbb`,
the same vocabulary a zone paints its squares with. Left out, the shape's own
colour is used, which is what makes an undeclared stat readable at a glance.
Say it when the six shapes run out before your numbers do: Splendor has five
gems, borrows five silhouettes, and its onyx came out an orange sword.

`min` and `max` are the bounds every bearer of the stat is held between, and a
card may narrow them for itself by writing `card_stats` as a list
(`"hp": [0, 4, 4]` — see *Cards*). A card that declares neither takes the
global rule, and where there is no global rule there is no bound at all.

**Reserved:** `round` (starts 1, +1 per round boundary) and `plays` (per-hand
play counter) are engine-managed — declare them only to display them.

A stat a game keeps on its *cards* rather than its players still wants an entry
here, tagged `hidden`: that is where its bounds and its icon are said, without
it becoming a row in the HUD.

`subject` overrides what the HUD row *reads* while the key still names what
cards spend: castle's defense lives on the buildings that provide it and shows
as their total, `{ "key": "defense", "subject": "sum:defense@standing" }`.

### Zones

| Field | Meaning |
|---|---|
| `key`, `label` | Identity and optional on-screen label |
| `type` | `deck` (face-down stack), `pile` (face-up stack), `hand` (row, shows card text), `grid` (board with slots), `options` (an offer: empty and unreachable until something asks — see *Asking a question*). **Stacks are reached from the top**: only the top card of a deck or pile can be played, activated or targeted |
| `pos` | `[x1, y1, x2, y2]` window fractions — optional; each type has a default spot (hidden zones default off-screen, giving dealt cards their fly-in) |
| `grid` | `[cols, rows]` for grid zones |
| `contents` | Starting cards: `"key"` or `"key:count"` strings |
| `tooltip` | Prose shown when the zone is hovered. A deck answers for itself — there are no cards in it to ask, only a deck |
| `activate` | The zone's **own** ability, in a card's words: `cost`, `phases`, `action`, `target`. This is how a deck is drawn from — the box answers, rather than the card on top of it becoming clickable. Gated like a card's: the phase it works in, what it costs, and whose zone it is. Not to be confused with `applies`, which hands an ability to the cards *lying* there |
| `applies` | Tags this zone hands to whatever sits in it, behaviour included (see *Tags as mixins*) |
| `receive` | What this zone does about an arrival. `needs`: whether a card being played may be sent **here** — the zone answers for itself, as a card does. `action`: what happens when one lands, with the zone as `@self` and the newcomer as `@target` (a discard pile anybody may take from says `set_owner:target:none` here, once, rather than every card that might be thrown into it saying it) |
| `asset` | A picture behind the whole zone — the painted board most games have. Same asset rules as a card's: a filename in `games/assets/`, an `http(s)` URL, or a shape spec. Stretched to the zone's rect, since that rect is what the cells are computed from |
| `tags` | See below |

The words the engine reads on a zone are in *Every tag the engine reads*,
with every other reserved tag.

Cards entering a grid without slot targeting auto-occupy the first free slot.
A full board refuses new arrivals: moves fail quietly and `fill`/`gain` stop
early (the validator warns when starting `contents` already exceed capacity).

### Players

**Who is playing is declared, not inferred.** One entry per seat, in seat order:

```json
"players": [
  { "card": "player_white" },
  { "card": "player_black" }
]
```

| Field | Meaning |
|---|---|
| `card` | the key of the card that **is** this seat. Leave it out and the engine injects an invisible stat bag, which is what a solitaire game has always had |
| `stats` | starting numbers for an injected seat. A seat that names a card takes its numbers from that card's `card_stats` instead |
| `text` | an injected seat's name. Defaults to "You" |

**Whose a piece is** is not declared here. It is written on the piece when
`setup.place` puts it down (`"owner": "player_white"`), because that is where
the question is actually decided — see *Setup*.

**A seat is still a card**, which is the point: it has stats, it can be looked
at, targeted, damaged and destroyed, and castle's throne room is a building on
the board that happens to be the player. Saying nothing at all gives you one
injected seat, so a game that never thinks about players never writes the
section.

The engine stamps the `player` tag onto each seat, so `@mine.player` and every
other scope keeps working. Writing that tag by hand no longer makes a seat, and
the validator says so — it would be a card every `@player` condition reached
that the engine did not consider a player.

**Whether a game can be played with somebody else is now a fact you can read**:
two entries means two seats. It does not, by itself, offer an invite — that is
still a card's decision (see *Playing over a network*), because whether a game
*wants* to be shared is content's business and not the engine's.

### Setup

**A card never says where it starts.** The `cards` list is what comes out of the
box; `setup` is the page of the manual that arranges it:

```json
"setup": {
  "player": { "hp": 5 },
  "place": [
    { "card": "throne_room", "zone": "board", "at": "c3" },
    { "card": "pawn", "owner": "player_white", "zone": "board",
      "at": ["a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2"] }
  ]
}
```

| Field | Meaning |
|---|---|
| `card` | the key of a card that starts already in play |
| `owner` | which player this one belongs to. Without it a card belongs to the seat of the zone it sits in, which is enough for per-seat tableaus; a shared board has no such seat, so pieces on one say whose they are here |
| `zone` | where it goes. Leave it out and its home tag decides, then the only board. A `per_seat` zone gets one copy in **each** seat's — a marker declared once appears on every player's board |
| `at` | the square, named the way a player would say it: a column letter and a rank counted from the near edge, so `"e1"` is the white king's. Grid zones only; without it the card takes the first free cell |

**`at` may be a list, and then it is that many cards.** Eight pawns are one
entry naming eight squares. That is what makes the placement list read like the
diagram in a rulebook instead of a table of cell numbers, and it is why chess
needs six cards rather than thirty-two.

**The order is the order things are placed**, and it is worth caring about:
entity IDs are handed out as cards are created, so a seeded game only replays
identically if setup builds the board the same way every time.

The engine places its own before any of this: the system card, the injected
player, and any seat that named no place. A seat has to exist before it can act,
so that is plumbing rather than setup, and a game never writes it down.

### Card templates

| Field | Meaning |
|---|---|
| `key` | Unique identifier |
| `text`, `tooltip`, `asset` | Presentation. `asset` is optional and may be a filename, an `http(s)://` URL, a procedural shape spec, or `"auto"` (see *Art without assets*). A card's **colour is a style it tags** — see *Styles* |

A local `asset` must be a bare filename (`sword.png`, not `../sword.png` or
a path) — this is enforced, not just a convention, since games can be
authored by people other than whoever is hosting the engine.

### Named assets

A card or zone's `asset` may spell its picture out — a filename, an `http(s)`
URL, a shape spec — or **name an entry in the top-level `assets` table**, which
is the only place a picture carries options:

```json
"assets": {
  "banner":         "banners_procession.jpg",
  "archmage_tower": { "src": "https://i.imgur.com/0vnj0kx.jpeg", "max": 4092 }
}
```

The bare form is a source on its own; the object form adds options. Today there
is one, `max` — the longest edge in pixels, 1 to 4092, which caps how large the
browser hands the picture over (see the size note below). Anything spelled out
inline instead gets 1024.

**A `src` may be a list, and then it is one picture per player**, chosen by whose
card wears it:

```json
"assets": { "rook": { "src": ["Chess_rlt60.png", "Chess_rdt60.png"] } }
```

That is what lets one card be a piece in either colour, and it is why chess
declares six pieces rather than six times however many players. A card's owner
is placement state (`setup.place`'s `owner`), so the same template placed for
white and for black draws differently without knowing anything about either.
A card with no owner takes the first picture.

Three reasons to name one rather than inline it:

- **Options.** A photograph that must stay sharp in the detail view asks for a
  bigger `max`; everything else should not pay for it.
- **One picture per player**, as above — there is nowhere else to say it.
- **Sharing.** The name is the cache key, so twenty cards drawn from one
  picture are one download and one texture. Inline sources are cached per card.

A name is anything without a source in it — no extension, no `:`, no scheme —
so the two forms can never be confused, and a name that matches no entry is a
validation error with a suggestion rather than a card that silently draws blank.

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

In the browser the picture is decoded by the page before the engine sees it,
and is handed over untouched if it is a JPEG or PNG no larger than **4092
pixels on its long edge**. Anything bigger is scaled to that, and anything in
another format is re-encoded — which means **the format stops mattering**:
LÖVE reads what stb_image reads, the browser reads far more, so a remote WebP,
AVIF or progressive JPEG works. Point a remote asset at whatever your host
serves.

The ceiling is about memory, not looks. Pixels are what the browser build's
heap pays for — 4092 square is 67 MB of RGBA — and that heap does not grow.
`index.html` puts a floor under it (256 MB); raise that before raising this.

Repeat visits are free: the fetch is an ordinary browser request, so a host
sending `Cache-Control` (imgur sends a year) is answered from the browser's own
disk cache with no network at all.
| `story` | Long-form prose, shown on the reveal page panel and in the detail view |
| `tags` | Free vocabulary for targeting and counting, plus any style the card claims. The words the engine itself reads are in *Every tag the engine reads* |
| `card_stats` | Per-instance stats stamped at creation. A number is a bare current value; a list is the bounds beside it — `[current, max]`, or `[min, current, max]`. `hp` shows a badge; 0 hp = ruined, skips `turn.action` |
| `play` | Playing the card. `cost` is spent (gates the card and dims it when unaffordable; `"sacrifice:<tag>": n` pays by destroying n board cards with that tag). `needs` is a non-consuming gate — escape hatch: playable anyway if nothing else in the zone is. `target` is click-to-target (below). `phases` is a phase key or list, and naming none means any — this is "cast only during your main phase". `action` is what happens |
| `activate` | The board ability, in the same words: `cost`, `target`, `phases`, `action` (no `needs` — an ability is gated by its cost and its phase). **Being spent is a cost**: `"cost": { "exhaust": 1 }` makes it once-a-round, and an ability that does not charge it stays available, which is how a permanent button works ("pass the time"). A board card shows three states — ready, greyed "exhausted" (spent this round), greyed "can't yet" (cost or targets unavailable). `moves` says how a piece moves on a grid and writes the `target` for you (see *Pieces that move*) |
| `challenge` | **Not a moment — a named test.** `needs` is the condition, `pass` and `fail` the action lists it chooses between, and any action list reaches it by running `resolve_challenge`. That is why it sits beside the moments rather than inside one: kingdom's crises are resolved when *played*, and if they fail they stay on the board to be *activated* later — one challenge, asked from two moments. Written inside `play` it would have to be written twice. One block because the three fields only ever work together. **Its condition sees the card asking it** — `@self` is that card and `@target` whatever it was aimed at — which is how chess's pawn asks "did this move end on my eighth rank" |
| `receive` | `needs`: whether **this** card may be the destination of the card being played, with itself as `@self` and the arriving card as `@target` (see *Legality between two cards*). `action`: what happens when one lands, read the same way. Zones take the same block |
| `turn` | `action`: run at each round boundary while the card is on a grid and not ruined |
| `play.target` / `activate.target` | Click-to-target with the arrow. Fields: `type` (`"card"`, `"slot"` or `"zone"` — a zone target names places in `zones` and ignores `tags`), `min`/`max` (or `count` for both), `tags` (all must match; computed tags count), `zones` (search only these — a per-seat key means *yours*), `owner` (`mine`/`enemy`/`anyone`), `fill` (slots only — see below) |
| `fill` | What may already be standing on a targeted square: `empty` (default), `enemy`, `open` (empty or enemy — "not blocked by my own"), `any`. Anything but `empty` is how a square you are about to capture becomes clickable |
| `where` | A condition asked of **each candidate**, with the candidate as `@target` and as the anchor for any pattern inside — so a target spec can say things about the destination that `fill` cannot. `"row@target == 1"` is the near row of a grid; `"count:unit@across >= 1"` is a cell with something standing opposite it. The same word a move rule carries, asked one level up so a destination nothing *walks* to can be narrowed too |

### Every seat, once

`each_seat:<action>` runs one action for each seat in turn, with that seat up:

```json
"actions": [
  "each_seat:draw_from:deck:mine.hand:10",
  "each_seat:stat_set:has_r4@mine.player:card:rocket_4@mine.hand"
]
```

`mine` is what makes it work — every scope you write is already relative to
whoever is up — so any action at all can be wrapped and no new words are needed.
The Crew's deal was four `set_active_seat` lines and four draws before this, and
a five-player variant meant editing the phase rather than the `players` list.

Whoever was up is up again when it returns, and **nothing hands over**: no line
in the log and no undo history cleared, because dealing to everybody is not
anybody's turn. It runs the same action for each seat, so an *uneven* deal is
the one thing it cannot say.

### Phases

| Field | Meaning |
|---|---|
| `key`, `label` | Identity, HUD label |
| `type` | `automatic`, `player_input`, `draw_and_play`, `overlay` |
| `actions` | Run on every entry — including a loop back into the same phase |
| `on_enter` | Run when the **turn** begins here, and not on a loop that keeps the same player. See *A phase that leads back to itself* |
| `deck`, `draw`, `zone` | Deal `draw` cards from `deck` into `zone` (default `hand`) on fresh entry. **Naming `zone` also bounds what may be played**: only cards in it. `zone` may be **a list**, which is a player holding two hands — an open one beside a closed one; the *first* is where cards are dealt and what an overlay offers, because those are singular questions. A phase that names none lets any reachable card be played, which is what the menu relies on |
| `pass_card` | Card key or array, dealt with every hand — forced plays always have an out |
| `ends_after` | The phase advances itself after this many **plays** |
| `ends_when` | A condition, asked every time the game comes to rest — **after every action, not only after a play**. See below |
| `seat` | `"next"` hands over to the next seat on entry (see *Two or more players*). A route may overrule it |
| `tags` | `discard_hand` and `keep_hand` — see *Every tag the engine reads* |
| `next` | Routing table (below) |

Types: `automatic` runs its actions once and advances (if the actions opened
an overlay — a revealed page, say — it waits and advances when the overlay
closes); `player_input` lets you play freely; `draw_and_play` is shorthand
for `player_input` with `ends_after: 1` and `discard_hand: true`; `overlay`
dims the screen, deals into its zone, and is resolved by **playing** one of the
cards in it — choosing is playing. Overlays are push-only (never in the
sequence), and the phase's `zone` is what bounds the choice to the offered
cards. Picking pops the overlay before the card's actions run, so a chained
reveal lands on top rather than burying it, and a card still lying in the offer
afterwards is spent. **A choice costs nothing**: cost, needs and targeting are
skipped, because they describe playing that card out of a hand later.

Think of phases like Magic's turn structure: each phase declares what it
deals on entry (`deck`/`draw`/`pass_card`), how it ends, and whether leaving it
sweeps the hand (`discard_hand` — the usual choice, so unpicked options don't
pile up across turns).

**How a phase ends is the phase's to say, and there are four ways.** A card
whose actions say `next_phase`; nothing at all, so the player decides via a pass
card; `ends_after` N plays; or `ends_when`, a condition.

`ends_after` counts **plays** and cannot tell one from another. That is true of
a game where a turn is one card and false of most others — in a trick-taking
game, putting a card into the middle ends your turn and everything else you may
do does not:

```json
{ "key": "lead", "type": "player_input", "zone": ["hand", "open"],
  "ends_when": "count:play_card@trick >= 1" }
```

`ends_when` is an ordinary condition in the ordinary vocabulary, and it is asked
every time the game comes to rest — after an activation, after a zone's
`receive` moved something, after a play. A phase says one or the other, never
both, and only a phase a player acts in: automatic and overlay phases end
themselves.

The engine provides a built-in overlay phase `reveal` over a built-in hidden
zone `reveal`, used by the reveal actions. It renders cards as full-text story
pages (title, `story` prose, click to continue), runs the picked card's own
its `play.action`, and destroys the read page unless its actions moved it somewhere.

Routing: `"next": [ { <condition>, "then": "phase_key", "ends_round": true }, ... ]`.
First matching entry wins; a condition-less entry always matches; no `next`
means list order with an implicit round-ending wrap. `ends_round` is the only
thing that ticks the round: round counter +1, exhausted cards ready, `turn.action`
runs.

#### A phase that leads back to itself

A turn is often "do a thing, then decide again", which is one phase looping. Two
games loop for opposite reasons, so the seat is a property of the **route**:

```json
"next": [
  { "when": "done@mine.player >= 1", "then": "noble_check" },
  { "then": "act", "seat": "same" }
]
```

`"same"` keeps the player who is up — Splendor's turn carries on until they are
done with it. `"next"` passes it along — The Crew's draft goes round the table.
A route saying nothing leaves the phase's own `seat` to answer, which is what
every arrival from elsewhere uses.

Alongside it, `on_enter` against `actions`:

```json
{ "key": "act", "type": "player_input", "seat": "next",
  "on_enter": ["stat_set:takes@each.anyone.player:0"],
  "actions":  ["activate_zone:t1_row"],
  "next": [ …, { "then": "act", "seat": "same" } ] }
```

`actions` run every time round; `on_enter` runs when the **turn** begins — an
arrival from another phase, or a loop that hands the turn on. A counter reset
belongs in `on_enter`, because running it again on the way round would undo the
turn it was counting. A number recomputed from the board belongs in `actions`,
because the board changed. Splendor needs exactly that split: what you have
taken this turn resets once, and what you can afford is worked out after every
token.

Both of these used to cost a second phase key — `act` and `act_on`, `play` and
`play_on` — where the second was a copy of the first with one word missing, and
every edit to one had to be remembered for the other. A phase nothing leads back
to has only one kind of entry, so `on_enter` on one is refused: it is what
`actions` already means.

### Conditions (one vocabulary everywhere)

Used by `next`, `end_conditions`, and every `needs` — a card's, a challenge's, a
zone's. Subjects: a stat key,
`count:<tag>` (cards on grid zones with that tag), or `card:<key>` (instances
of that specific template on grid zones — "does the player have the rusty key?").

`saved:<slot>` is the same yes/no shape asked of the machine rather than of any
card: 1 when that save slot holds a game and 0 when it does not, which is how a
menu offers *Continue* only when there is something to continue.

**A square on a grid carries `col` and `row` as ordinary stats**, 1-based and
row-major, so where something is on the board is asked with the vocabulary
already here: `"row@target == 8"` is "the far rank".

**A condition is one string**: `<subject> <op> <number-or-subject>`, where the
operators are `>=`, `<=`, `>`, `<`, `==` and `!=`. One comparison per string —
there are no boolean operators, because a list already means *and*, and *or* is
two abilities.

- Any `needs`, an `accepts` and a target's `where` take a **list** of them, all
  of which must hold: `["might >= 8", "count:farm >= 3"]`. A list rather than a
  map keyed by its subject, because such a map cannot name one subject twice,
  and `["gold >= 3", "gold <= 8"]` is a range.
- A routing entry and an `end_condition` take exactly one, under `when`:
  `{ "when": "progress >= 12", "then": "trial" }`. `{ "zone_empty": ["road", "hand"] }`
  is the one question the comparison grammar cannot ask, and it stays.
- A **cost** is not a condition and keeps its map: `{ "gold": 2 }` is what gets
  *spent*, where `"gold >= 2"` would only say what to check.

**The right-hand side may be another subject, not just a constant.** The type
decides at run time — a number is a number, anything else is measured:

```json
{ "when": "score@north_side >= score@south_side" }
"value@target >= max:value@mine.red"
```

It has to *look* like a subject — name a scope or a measuring fn — or it is
refused as a bare word, which would otherwise read as a stat worth nothing and
quietly pass.

**A stat nobody carries is absent, not zero**, and every comparison against it
fails — including `== 0` and `<= n`. Without that rule "this rook has
never moved" would be true of a rook captured twenty moves ago, since a sum over
nobody is zero: a gate that opens exactly when the thing it guards stops
existing. `nil` and `0` are different, here as in Lua.

The measuring forms are exempt and mean what they say: `count:` and `card:` over
nothing really is zero (which is how "these squares are empty" is written), and
`sum:`/`max:` are asked *of a pool*, whose empty measure is honestly zero —
nothing adds to nothing, and nothing is at most nothing.

**`min:` is the exception to the exception.** Nothing is not *at least* nothing:
a zero answer would sit below every real value, so `min:value@mine.hand` over an
empty hand would beat everything exactly when the hand is empty. An empty pool
has no smallest member, so `min:` reads as absent and fails every comparison.

**`min:` and `max:` only see the cards that carry the stat**, which is what
makes "the lowest pink card in my hand" sayable without a scope that can name a
tag inside a hand: give a pink card a `v_pink` stat and give no other card one,
and `min:v_pink@mine.hand` is exactly that.

A subject used this way must *look* like one — it has to name a scope (`@…`)
or a measuring fn (`sum:`, `max:`, `count:`, `card:`). A bare word is treated
as a typo and fails the comparison closed, rather than quietly reading as an
unknown stat worth nothing.

`end_conditions` fire once per game (first match), wait for open overlays, and
run their `then` actions — usually `push_phase:` to an ending overlay.

**Scopes: which cards a subject is about.** The part after `@` is a *scope
expression*: `[<quant>.][<owner>.]<zone-or-tag>`, where the name is a zone key,
a tag, a movement pattern, or one of `self` / `target` / `all` / `reach` /
`owner_of.<scope>`.
Without any scope, a subject means **your own cards** — see *The player is a
card* below.

```
insight@player       the stat on cards carrying the "player" tag
hp@each.follower     every follower, individually
hp@random.follower   one follower, chosen by the seeded shuffle
hp@self              the acting card
hp@target            the cards the player chose for this card
sum:defense@board    a stat summed over one zone
max:rank@tableau     the largest value in one zone
min:rank@tableau     the smallest — over the cards that carry the stat
count:farm@board     count, narrowed to a zone
count:king@enemy.reach  a king standing where an opponent could move — check
score@owner_of.target   the score of whoever owns the card the player chose
```

### `@reach` — wherever a set of pieces could move

`reach` is the squares a set of pieces could move onto **right now**, answered as
the things standing on them. The owner word picks *whose* pieces are asked, not
what comes back, so `@enemy.reach` is every square an opponent could move to —
and asking what stands there is how a game asks about threats:

```json
{ "when": "count:king@enemy.reach == 0" }
```

*No king of mine stands where an enemy could move* — which is "not in check",
written by the game rather than known by the engine.

**The engine has no idea what an attack is**, and does not need one. A piece may
only land on an occupied square if its own move says so: a pawn's step is
`"fill": "empty"` and cannot reach an occupied square, its take is
`"fill": "enemy"` and can. The line between moving and threatening is already
drawn in the game file, and `reach` only adds it up. That also means a piece is
never offered its own side's squares, so `count:king@enemy.reach` can only ever
have found *your* king.

It is computed on demand from the `moves` each piece declares — nothing is
stored, so there is no "when is it recomputed" to get wrong. **A move rule's own
`needs` may not usefully ask for it**: that would be reach asking itself, and the
circle names nothing rather than hanging.

Chess uses it to route into a phase whose label says so, which is the whole of
the feature on the game's side:

```json
{ "key": "white_move", "label": "White to move", "seat": "next",
  "next": [{ "when": "count:king@mine.reach >= 1", "then": "black_check" },
           { "then": "black_move" }] }
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

### `@owner_of` — the seat a card belongs to

`owner_of.<scope>` is **the seats owning what the rest of it names**, as their
own cards — so a rule can pay, ask about or score *whoever* owns something
without naming a chair:

```json
{ "action": ["stat_gain:score@owner_of.target:1"] }
```

*The owner of the card you chose scores a point.* Every other way of naming a
seat is decided in advance: `mine` and `enemy` are relative to whoever is up,
and a seat key reaches its own card only because the game file tagged that card
with its own name. Neither can say *whoever owns this particular card*, which is
what a trick winner, a captured piece and a card played out of somebody's hand
all need.

What follows the prefix is an ordinary scope expression, so quantifiers and
owner words work inside it. On its own, `@owner_of` is **the acting card's own
seat** — which a card cannot otherwise name, since `mine` is whoever is up
rather than whose the card is.

```
score@owner_of              the seat this card belongs to
score@owner_of.target       the seat owning what the player chose
count:player@owner_of.piece the seats with a piece on the board — each counted once
score@mine.owner_of.target  ...and only if that owner is me
```

**An owner word means whichever side of the prefix it stands on.** Inside, it
picks the cards (`@owner_of.enemy.creature` — the seats an opponent's creatures
answer for); before it, it filters the seats that come back
(`@mine.owner_of.target` — the target's owner, when that is me). Each seat
answers once however many cards it owns, and a card nobody owns names nobody.

That is the reading half. `set_active_seat:<scope>` is the writing one — it
**makes that seat the one whose turn it is**, which is how the trick winner
leads the next trick:

```json
{ "key": "score_trick", "type": "automatic",
  "actions": ["stat_gain:tricks@owner_of.highest:1", "set_active_seat:owner_of.highest"] }
```

Cards, zones and phases all run ordinary action lists, so any of them may say
it. The scope names cards and the seat is whose they are, through the same
answer `mine` asks — so `set_active_seat:target` and
`set_active_seat:owner_of.target` mean the same thing about an ordinary card,
and naming a seat card outright picks that seat. A scope naming **two** seats is
refused rather than resolved (picking the first would make turn order depend on
the order cards sit in the file); one naming **none** does nothing, because the
trick is not won until somebody has won it. Handing over ends the undo history,
exactly as the end of a turn does.

### The player is a card

There is no player object. A seat that names no card becomes an invisible one tagged
`player`, and a subject with no scope means that card — so `"cost": { "gold": 2 }`
and `{ "when": "gold >= 5" }` are guaranteed to be talking about the
same coins. Nothing else changes for a game that never thinks about it.

Tag a template `player` and it becomes the player instead, with no stat bag
injected. `castle.json` does this with its throne room: the hero is a real card
on the board, so it can be looked at, damaged, targeted and destroyed like any
other, and its stats are the player's stats.

```json
{
  "key": "throne_room",
  "tags": ["building", "hero", "player"],
  "card_stats": { "hp": 20, "gold": 20, "morale": 5 }
}

"setup": { "place": [{ "card": "throne_room", "zone": "board", "at": "c3" }] }
```

A **party** is the same idea repeated: N cards in a zone, each tagged `player`,
each with its own `card_stats`. Per-character stats, targeting, death and
revival are all ordinary card behaviour — `sum:might@party` asks what the party
has between them, `"activate": { "cost": { "mana@self": 1 } }` makes a character pay
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

A seat with no `start.zone` goes into the hidden `system` zone — an
invisible stat holder. Place it (a `setup.place` entry) when the seat should
be a visible hero on the table.

**Zones that belong to a seat** declare `per_seat`, and are then created once
per seat with one rect each:

```json
{ "key": "hand",  "type": "hand", "tags": ["per_seat"],
  "pos": [[0.02, 0.75, 0.78, 0.87], [0.02, 0.88, 0.78, 0.99]] },
{ "key": "arena", "type": "grid", "grid": [5, 1], "tags": ["per_seat"],
  "pos": [[0.02, 0.05, 0.60, 0.30], [0.02, 0.32, 0.60, 0.57]] }
```

An unqualified zone key means **the active seat's** copy — `move_to:arena`
puts the card in your own arena, `draw_from:deck:hand:1` deals into your own
hand. Say `enemy.arena` for the other. A `per_seat` zone also receives its own
copy of every card `setup.place` puts there, so a marker placed once appears in each
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

**Pieces on a shared board** belong to a seat without the board doing so. Tag a
card with a seat's key and it is that seat's:

```json
{ "key": "w_rook", "text": "White Rook", "tags": ["white", "piece"] }
```

A chessboard is one zone, not two, so ownership cannot come from the zone; this
is how `mine` and `enemy` still tell the pieces apart, and how the engine knows
white may not move black's rook. A seat card itself is nobody's piece, so a
party game that tags four characters `player` keeps all four usable on one turn.

Three rules the engine enforces so no interface has to: a card another seat owns
cannot be played or activated; a card outside the phase's declared `zone` cannot
be played; and a target the rules did not allow is refused even if a script
passes it directly.

Everything above is invisible in a one-player game: there is exactly one seat,
every owner word means the same cards, and no handover ever happens.

### Pieces that move

A grid game says how its pieces move in one top-level `patterns` block, and each
piece names the patterns it uses. **A pair is a direction, not a destination** —
it is applied up to `range` times, and each repetition has to pass through the
one before it. That single idea is all of blocking, leaping and range:

```json
"patterns": {
  "line_ortho":  { "vectors": [[1,0],[-1,0],[0,1],[0,-1]], "class": ["ray"] },
  "line_diag":   { "vectors": [[1,1],[1,-1],[-1,1],[-1,-1]], "class": ["ray"] },
  "knight_leap": { "vectors": [[1,2],[1,-2],[-1,2],[-1,-2],[2,1],[2,-1],[-2,1],[-2,-1]] },
  "adjacent":    { "vectors": [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]] }
}
```

| `class` | Means |
|---|---|
| `step` | the vector applies exactly once — **the default** |
| `ray` | it repeats until something stops it |
| `ray:n` | …up to n times |
| `phasing` | nothing on the way stops it |
| `absolute` | the entries are **squares, not directions** — see below |

A bare list of pairs is shorthand for `"class": ["step"]`. **Every direction is
written out.** There used to be a `mirrored` word that negated each axis so one
pair stood for its family; it saved four lines in one game and cost a reader
working out which eight directions `[1,2]` meant — and it hid a bug, since
mirroring a zero produced `-0`, which dodged the duplicate check and had rooks
walking eight rays down four lines.

**`y` is a rank: `[0,1]` is one square forward, up the board**, and the engine
flips it for whoever is sitting at the other side. So one pawn template serves
both colours.

**Absolute patterns** name squares rather than directions, and name them the way
a player says them. A square belongs to a board rather than to whoever is
moving, so an absolute pattern names its `zone` (or takes the only board):

```json
"home_base":     { "vectors": ["a1"],       "class": ["absolute"], "zone": "board" },
"castle_k_path": { "vectors": ["f1", "g1"], "class": ["absolute"], "zone": "board" }
```

`absolute` is a *kind*, not a modifier: there is no path to block and nothing to
repeat, so `ray` and `phasing` mean nothing beside it and the validator says so.
Mixing both kinds in one piece is just two rules — `"moves": ["forward",
"home_base"]` is "step ahead, or teleport to base".

**Every coordinate an author writes starts at the bottom left.** `a1` is the
near-left corner, `row@target` is a rank counted from the bottom, and
`place:<who>:<square>` takes a name. The cells are laid out top-down on screen,
which is `geometry.slot_at`'s business and appears nowhere else.

### Asking about the square you are considering

A move rule's `needs` is asked **once for the rule**, so it cannot tell one
candidate square from another. `fill` is asked per square but knows only what is
standing there. `where` is the third: asked per candidate, with that square as
`@target` **and as the anchor for any pattern inside it**.

```json
{ "patterns": ["pawn_take"], "fill": "empty",
  "where": ["tagged:last_acted@behind >= 1",
            "tagged:pawn@behind >= 1",
            "rank@behind == 4"] }
```

That is en passant: *an empty square I could take onto, with a pawn just behind
it that a player touched last and that stands on its own fourth rank* — which
between them mean it has just run two squares past me. `behind` is anchored on
the square being considered, and its facing still comes from the mover, so the
same clause serves both colours.

**`tagged:` and `not_tagged:`** answer yes or no about a scope, as 1 or 0:
`"tagged:pawn@behind": 1` is *there is a pawn there*. Use them rather than
counting to one — `count:` is for when the number is the point.

**Castling is what this is for.** It is two abilities on the king, and every
question it asks is relative — the king goes two columns toward the rook, and
columns do not flip with facing, so the same rules serve both colours:

```json
{ "key": "castle_k", "text": "Castle kingside",
  "moves": [{ "patterns": ["two_right"], "fill": "empty",
              "needs": ["moves_made@self == 0"],
              "where": ["tagged:rook@one_right >= 1",
                        "moves_made@one_right == 0",
                        "not_tagged:piece@one_left >= 1"] }],
  "action": ["move_to:target", "place:one_right:one_left", "next_phase"] }
```

`needs` asks about the king (it has not moved), `where` asks about the square it
is considering (a rook still sits beyond it, unmoved, with nothing in between),
and the action moves the rook to the far side by pointing rather than by naming
a square. Clicking the king offers "Move" and "Castle kingside" only when both
are really available.

### Looking inside a deck

Right-click or long-press a zone to browse it: every card, full size, laid out
to fill the panel. **A deck may be browsed too** — what is *in* one is public in
most games, and a deck whose contents are secret is already `hidden`, which
nothing can click.

**The order is the secret, not the contents.** A face-down stack is shown sorted
by name, so reading it tells you what is left and nothing about what comes next
— shuffling changes the draw and changes the browser not at all. A face-up pile
has no secret to keep and is shown as it lies, top card last.

Browsing never changes anything, so it is safe to offer everywhere it is
allowed at all. Drawing is a separate gesture and stays one.

**An opponent's hand is not browsable, and neither are its cards.** Drawing them
as backs is only half of hiding a hand: right-clicking a card, right-clicking
the hand itself, and ctrl+hovering for the inspector all read a card, and all
three ask the same question now. The rule is one function — a hand with a seat
is its owner's alone — and the board, the decks and a seatless hand stay open to
everybody.

### `last_acted` — the card a player touched last

The engine marks whichever card was most recently **played or activated**, one
at a time, and the mark lingers until the next thing a player does. A zone
activation clears it: the last thing that happened was not to a card.

That is how a rule asks whether something happened *just now*. En passant's
window closes the instant the opponent does anything at all, which is the real
rule — not "at the end of the turn", which is only nearly it.

It rides undo with everything else, being an ordinary stat on the entity.

### A pattern is also a scope

The same name answers *what is standing there* as readily as *where may I go*,
so no separate "is this square empty" condition exists or is needed:

```json
"play": { "needs": ["count:piece@castle_k_path == 0"] }
```

An absolute pattern names its squares outright. A relative one is anchored on
the acting card — `count:ally@adjacent` is a support bonus — and names nothing
when that card is not standing on a square.

**A knight needs no "leaps" flag and a rook needs no "blocked" flag.** `[1,2]`
applied once has no square before it, so nothing can obstruct it; `[1,0]`
applied seven times walks through six. It falls out of the geometry.

Pieces then name patterns, and only a piece whose rules differ in *what may be
standing on the far square* needs more than a list of names:

```json
{ "key": "queen", "activate": { "moves": ["line_ortho", "line_diag"],
    "action": ["move_to:target:taken", "next_phase"] } },
{ "key": "knight", "activate": { "moves": ["knight_leap"], "action": [...] } },
{ "key": "pawn", "activate": { "action": [...], "moves": [
    { "patterns": ["pawn_step"], "fill": "empty" },
    { "patterns": ["pawn_run"],  "fill": "empty",
      "needs": ["rank@self == 2"] },
    { "patterns": ["pawn_take"], "fill": "enemy" } ] } }
```

Declaring `activate.moves` writes the `activate.target` for you (one square, `fill` per
rule), so clicking the piece opens targeting and clicking a square moves it.
Write the `activate.action` yourself — that is where captures go, and where the turn
ends.

**`y` is forward for whoever is moving**, so one pawn definition serves both
colours: the first seat advances toward row 1 and the rest advance away from it.
A piece on a square also carries `col`, `row` and `rank` as stats (declare them
in `card_stats` to opt in) — `rank` counts from the piece's *owner's* side, which
is why "home rank" is 2 for both colours above, and why promotion is one
computed tag: `{ "promoting": { "stat": "rank", "at_least": 8 } }`.

### Moves with fixed destinations (castling)

Some moves are not a direction so much as one exception. Castling is the king's
second ability: a two-square pattern with everything it needs written beside it,
which is how chess declares it.

```json
{
  "key": "castle_k",
  "text": "Castle kingside",
  "moves": [
    {
      "patterns": ["two_right"],
      "fill": "empty",
      "needs": ["moves_made@self == 0"],
      "where": [
        "tagged:rook@one_right >= 1",
        "moves_made@one_right == 0",
        "not_tagged:piece@one_left >= 1"
      ]
    }
  ],
  "action": ["move_to:target", "place:one_right:one_left", "stat_gain:moves_made@self:1", "next_phase"]
}
```

Three things make that work, none of them specific to chess:

- **"Has it moved" is a stat.** A `moves_made` stat plus
  `stat_gain:moves_made@self:1` in the ability's action, and `{"unmoved":
  {"stat": "moves_made", "equals": 0}}` if you want it as a computed tag.
- **`needs` asks about the piece, `where` asks about the square.** A move rule's
  `needs` is a condition on the mover; its `where` is asked of each square the
  rule offers, with the *patterns anchored on that square* — which is how "the
  rook beside it has not moved either" is a condition and not a special case. A
  captured rook carries no stat at all, and an absent stat is not zero (see
  below), so this refuses a rook that was taken as well as one that has moved.
- **`place:<who>:<square>`** moves a named card onto a named square, and a
  pattern naming one square is a "who" as much as a card key is: `place:one_right:one_left`
  is *the piece one square to my right goes one square to my left*. It refuses an
  occupied square, which is why the rule above has to be complete.

Two spellings this section used to teach are gone: `place:<who>:<col>:<row>`
takes a square name now, and a board of individually named pieces
(`w_king_e`, `w_rook_h`, one card per piece) became six templates placed with
an `owner`, which is the section on `setup.place` above.

**If you do write a move as a card** — a button in a zone rather than an ability
on the piece — put that zone in **`optional`**. Ordinarily a `needs`-gated card
becomes playable when nothing else in its zone is, so a mandatory play can never
soft-lock a hand; but a zone of buttons is not a hand, and "everything here is
currently illegal" is its normal state rather than a trap.

`game/games/chess.json` is the worked example, and it is written by hand —
thirteen cards, six of which are the pieces. Movement is six pattern entries
shared by both colours, and castling is two more abilities on the king.

### Legality between two cards

Some rules are about **the card being played and the place it lands** — "a card
may go on a higher one", "onto a card of the opposite colour". Neither `needs`
(which asks about game-wide state) nor a computed tag (which asks about one
card alone) can express that, because it takes two cards at once.

`receive.needs` lives on the **destination** and is asked of each candidate, with
itself as `@self` and the arriving card as `@target`:

```json
{
  "key": "red_route",
  "tags": ["marker", "red_dest"],
  "receive": { "needs": ["value@target >= max:value@mine.red"] }
}

"setup": { "place": [{ "card": "red_route", "zone": "red" }] }
```

That single line is the whole of Lost Cities' expedition rule: a card must be
worth at least what is already there. A destination with **no** `receive` takes
anything — which is how the same game's discard pile stays always legal:

```json
{ "key": "red_tip", "tags": ["marker", "red_dest"] }

"setup": { "place": [{ "card": "red_tip", "zone": "red_discard" }] }
```

The card being played just names both destinations and goes where it is
pointed:

```json
{
  "key": "red_7",
  "card_stats": { "value": 7 },
  "play": {
    "target": { "type": "card", "tags": ["red_dest"], "count": 1, "zones": ["red", "red_discard"] },
    "action": ["move_to:target"]
  }
}
```

Putting the rule on the destination rather than on the card is what lets it
name its own zone: the red route marker knows it lives in `red`, so it needs no
way to say "wherever I happen to be". A marker card in an otherwise empty zone
also gives the empty case something to target.

**Targeting takes the owner words too**, so "choose an enemy creature" needs no
syntax of its own: `{ "type": "card", "tags": ["creature"], "owner": "enemy",
"count": 1 }`. And a spec that lists `zones` means *yours* — it never offers
another seat's copy of a per-seat zone unless an owner word says so.

### Styles

A **style is a named look**, and a card claims one by tagging it:

```json
"styles": {
  "crimson": { "color": [0.85, 0.25, 0.25] },
  "jade":    { "color": [0.30, 0.70, 0.35] }
},
"cards": [
  { "key": "red_2", "text": "Red 2", "tags": ["expedition", "crimson"] }
]
```

Lost Cities has seventy coloured cards and five colours, so this is five style
entries and one word per card rather than three numbers repeated fourteen times.
Change the red and every red card changes.

A style carries everything about how a thing *looks*, for cards and zones alike:

| Property | On | Means |
|---|---|---|
| `color` | cards | `[r, g, b]` for the plate behind the art, or **`false`** for no plate at all, so a transparent PNG shows the board through it |
| `title` | cards | `false` draws none, giving the whole card to the picture |
| `border` | cards | `false` draws no frame. A chess piece is not a card and should not be drawn inside one — selection and eligibility outlines still draw, because those are the affordance rather than the frame |
| `fit` | grid zones | `card` (default) keeps card proportions in a cell; `fill` stretches to the whole cell, for board tiles |
| `fan` | stack zones | show the whole stack, not just its top card — `"up"`, `"down"`, `"left"` or `"right"`, the way the next card is laid. See below |
| `ratio` | zones | the shape it keeps whatever the window is — width over height, or `"grid"` to read it from the cell count |
| `chequer` | grid zones | two colours alternated across the squares. **The first is a1's** — the bottom-left square — and a board wanting the other way round swaps the two strings. There is no flag for it |
| `badges` | cards | the stat keys drawn as numbers along the bottom of the face, left to right: `["power", "health"]` is a creature card. Without it a card shows `hp` and nothing else — **a card that carries numbers and names none of them here shows none of them**. Read off the **card**, so a style only a zone claims draws nothing; the validator says so |
| `badge_run` | cards | which way that list runs: `"right"` (default) along the bottom, or `"down"` the left edge from the top corner, for more numbers than go across a card. A column leaves the title its full width; a row makes way for it |
| `badge_zeros` | cards | `false` leaves out a badge whose number is zero. A separate word from `badge_run` on purpose — a market card's cost of no rubies is not a line of the price, while a creature's zero power is a fact and must still draw |
| `paint` | grid zones | `{ "<absolute pattern>": colour-or-filename }` — terrain, goal rows, home rows |
| `cell_outline` | grid zones | `false` draws no outline on empty cells. Eligible squares still light up during a move |

Every one of these was its own field or its own tag. Chess's whole board is now
one word:

```json
"styles": {
  "chessboard": { "fit": "fill", "ratio": "grid",
                  "chequer": ["#b58863", "#f0d9b5"], "cell_outline": false },
  "piece":      { "title": false, "color": false }
},
"zones": [{ "key": "board", "type": "grid", "grid": [8, 8], "tags": ["activate", "chessboard"] }]
```

**`color: false` is where two ideas became one.** A card's colour and "draw no
plate behind it" were a field and a tag deciding the same thing; now the plate
has a colour, or it has none.

### A card that can do several things

One `activate` is a card with one thing to do. A list of `abilities` is a card
the player has to be asked about:

```json
"abilities": [
  { "key": "levy",  "text": "Raise a levy",
    "cost": { "exhaust": 1 }, "action": ["stat_gain:gold:3", "stat_damage:stability:1"] },
  { "key": "drill", "text": "Drill the levies",
    "cost": { "exhaust": 1, "gold": 3 }, "action": ["stat_gain:might:2"] },
  { "key": "rest",  "text": "A day of rest", "action": ["stat_gain:stability:1"] }
]
```

Each ability has its own `cost`, `target`, `phases` and `action` — they are
gated separately, and **only the ones usable right now are offered**. The third
above has no cost, so it stays available after the first two are spent, which is
what `exhaust` being a *cost* rather than a consequence buys.

`text` is the label in the chooser, so a card with more than one ability needs
it. The engine generates the menu entry itself, with a shape derived from the
ability's name — you do not write a card per option.

**Clicking is unchanged for everything else.** One usable ability acts at once;
a chooser only appears when the answer stopped being obvious. `@self` is the
card that asked either way, so an ability is written the same whether it is the
card's only one or one of five.

**An ability that targets asks after it is chosen.** The offer closes, the board
comes back, and the targeting arrow starts from the card — and **cancelling
reopens the chooser**, because a player who changed their mind about *which*
ability has not changed their mind about the card.

**A tag's abilities are added to the card's, not substituted.** A zone that
grants an ability used to hide whatever the card could already do; now a card
that can move and is handed "take me" can do both, and is asked which.

### Asking a question

Some moves end in a choice: a pawn reaching the far rank, a builder picking what
to build. That is one action:

```json
"challenge": { "needs": ["rank@self == 8"],
               "pass":  ["options:to_queen,to_rook,to_bishop,to_knight"],
               "fail":  ["next_phase"] }
```

`options` deals a card per choice into the **offer** — a zone of type `options`
— and opens it over the board. Clicking one plays it, and everything left is
cleared: an offer outlives its question by nothing.

**The offer remembers who asked**, which is the part that saves the game file
work. The chosen card is played with the asking card as its `target`, so a
promotion choice is one line and needs no marker stat to find the pawn again:

```json
{ "key": "to_queen", "text": "Queen", "asset": "queen",
  "play": { "action": ["transform:target:queen", "next_phase"] } }
```

The choices also take the asker's **owner**, so a named asset with one picture
per player draws them in the right colours without the game saying anything.

**The source may be a zone instead of a list** — `"options:upgrades"` offers a
card per card in that zone, which is how a variable set of choices is written.

**An offer you asked for can be declined.** Right-click or Escape closes a
chooser opened by clicking a card — nothing has happened yet, so taking the
click back costs nothing. An offer the *rules* opened stays: promotion appears
after the pawn has already moved, and there is no state to return it to. The
engine draws that line itself, by which side opened the offer.

**You get the zone and the phase for free.** Both are injected under the key
`options`, exactly as `reveal` is, and a game that wants the offer drawn
somewhere else declares its own zone with that key. An `options` zone is hidden
by its type rather than by a tag it has to remember — an offer that is not open
is not on the board, and *that* is a rule worth having in the type, because a
hidden zone holding cards is how clicks go missing.

### `fan` — a stack you can read

A `pile` draws its top card, because that is what a stack of cards looks like.
Some stacks are meant to be read down their whole length — a solitaire tableau,
a Lost Cities expedition, a row of tricks won — and for those the pile says
which way it spreads:

```json
"styles": { "expedition": { "fit": "fill", "fan": "down" } },
"zones":  [{ "key": "red", "type": "pile", "label": "Red", "tags": ["expedition"] }]
```

Every card is drawn, each over the one before, leaving a **strip** of it showing.
The card's name moves to the bottom of that strip rather than the bottom of the
card, so a covered card still says what it is — which is the whole point, and the
reason the arithmetic protects the strip first: as cards pile up the fan closes
to a minimum readable strip, then the *cards* shrink, and only a stack too long
for even that shares the room out evenly.

The direction is where the **next** card goes. `"down"` is a tableau read
top-to-bottom. `"up"` grows away from whoever owns the zone. `"left"` and
`"right"` lay a horizontal run, and there the strip is a narrow column, so keep
those for short stacks or wide zones.

**Give a fanned zone room along its axis.** A dozen cards fanned down a zone a
finger tall is the fault this replaced, not the fix for it — the layout will
divide what it is given, and eight cards want roughly the height of two.

**Not on a `grid`.** A grid puts each card in an addressed slot and a fan lays
them in a run; both answer *where does this card go*, so a grid wearing a fanning
style is a validation error rather than a coin toss.

**A style name lives in the same namespace as zones, tags and cards** — one name
means one thing, and the validator refuses a style called `red` in a game that
already has a `red` zone. That is why these are named for the look (`crimson`,
`jade`) rather than for the thing wearing it.

**Two styles on one card claiming the same property is an error**, not a
precedence rule you would have to remember — the same stance the engine takes
when a card and its zone both define one behaviour.

**A style may be a computed tag, and then the look follows the numbers:**

```json
"computed_tags": { "wounded": { "stat": "hp", "less_than": 3 } },
"styles":        { "wounded": { "color": [0.8, 0.1, 0.1] } }
```

A card carrying that tag turns red the moment its `hp` drops, with no condition
anywhere in the drawing code. Only style words that are *also* computed tags are
re-checked while the game runs, so a game without any pays nothing for this.

**A style may not change a rule.** It decides how a thing looks, never whether it
can be played, targeted or afforded — the moment it could, every rules bug would
become a drawing bug too.

### Every tag the engine reads

Tags are your own vocabulary and an unknown one is never an error. These
eighteen are the exceptions — the words the engine itself looks for:

| Tag | On | What it does |
|---|---|---|
| `generate_art` | card | with no asset, draws a shape derived from its key rather than a bare colour |
| `immutable` | card | scenery: nothing may target it and its template can never be edited |
| `no_undo` | card | playing or picking it clears the undo stack — the choice is final |
| `player` | card | this card is a seat. Stamped by the engine from the players section, not written by hand |
| `token` | card | vanishes when a hand is swept, instead of joining the discard |
| `activate` | zone | cards here may use their abilities — without it an ability is unreachable |
| `face_down` | zone | cards here are hidden, whatever the type would do |
| `face_up` | zone | cards here are shown, whatever the type would do |
| `hidden` | zone | not drawn and not clickable — offer zones, fate decks. **This is what keeps a deck's contents secret**: any other deck can be browsed |
| `no_peek` | zone | no tooltip and no browsing the pile |
| `optional` | zone | nothing here ever has to be played, so a gated card stays gated |
| `page` | zone | its cards are drawn as full-screen story pages |
| `per_seat` | zone | one copy per seat; pos then takes one rect each |
| `refill_when_empty` | zone | recreates its contents when the last card leaves |
| `shuffle` | zone | shuffled when its contents are created, and on every refill |
| `discard_hand` | phase | leaving it discards the unplayed hand; tokens vanish |
| `keep_hand` | phase | a draw_and_play phase opting out of the discard it would otherwise get |
| `hidden` | stat | kept out of the HUD, while cards may still read and change it |

**They are reserved.** A style, a tag with behaviour, or a computed tag may not
be named after one: the engine reads the word off the entity, so two meanings
would both apply with nothing to say which wins. The cost is real and accepted —
you cannot name a style `hidden` to colour everything that is — and it buys the
guarantee that a word already meaning something cannot be quietly given a second
job.

**A near miss is reported.** A tag six letters or longer that is one edit from a
reserved word is almost certainly that word misspelled, and every one of them
fails *silently*: a board tagged `activaet` holds cards whose abilities can never
be used, and nothing else would ever say so. Short words are left alone, because
`mage` is one edit from `page` and is nobody's mistake.

### A stat says whose number it is

**A card carrying a stat is how it says it takes part in that number.** An action
skips a card that has none, and an absent stat fails every comparison rather than
reading as zero — both rules are load-bearing, and both used to mean a card that
is one of forty in a deck declared the same zero forty times. The stat says it
once instead, beside its own floor and ceiling:

```json
"stats": [
  { "key": "contend", "min": 0, "max": 999, "tags": ["hidden"],
    "on": ["play_card"], "start": 0 },
  { "key": "hp", "min": 0, "on": ["creature"] }
]
```

| Field | Meaning |
|---|---|
| `on` | tag names — whose number this is. A card carrying any of them takes part |
| `start` | what those cards start at. **The card's own `card_stats` still wins**, so one card may start somewhere else |

**Left out, `start` means each of them says its own** — *a creature has hp, and
every creature says how much* — and the validator names the card that forgot.
That turns a whole class of silent bug into an authoring error: a card missing
from an arithmetic that is about it used to be invisible, because a stat nobody
carries fails closed.

Saying `start` without `on` is refused: it would not know whose number it is.

**`on: ["player"]` is the one every game wants.** `player` is stamped by the
engine onto the cards your `players` list names, so it is the one tag you never
type and every seat wears:

```json
{ "key": "reserve_slots", "min": 0, "max": 99, "on": ["player"], "start": 3 }
```

```json
{ "key": "north", "text": "North", "tags": ["north_side"], "card_stats": { "opens": 1 } },
{ "key": "south", "text": "South", "tags": ["south_side"] }
```

Splendor's two seats used to carry twenty numbers each, nineteen of them the
same on both, and a third player would have meant a third copy. What is left on
a seat card is what makes it *that* seat.

`suit` and `value` in The Crew are the required form (every playing card says its
own), and the eight scratch registers of the trick arithmetic are the granted
one. Splendor went from 1,256 zeros in 1,662 `card_stats` entries to 301, and The
Crew from 282 in 407 to 10. What is left in both is real: a development card that
costs no white, a noble that needs no green.

### Computed tags

Per-card derived tags from that card's own stats:

```json
"computed_tags": { "damaged":  { "stat": "hp", "less_than_max": true },
                   "standing": { "stat": "hp", "at_least": 1 } }
```

Comparators: `less_than`, `less_than_stat`, `less_than_max`, `at_least`, `equals`. Usable
anywhere card tags are (targeting, `count:`, and as a scope — castle reads
`sum:defense@standing` so rubble stops defending).

**This is the one place the struct spelling survives, and it is a different
question.** A condition asks about a *scope*; a computed tag is asked of one
card, per frame, and reaches things no subject can name — `less_than_max` reads
that card's own ceiling. Until a subject can say "this card's ceiling", folding
the two together would cost more than the second vocabulary does.

### Tags with behaviour

A game can give tags meaning of their own — types, essentially:

```json
"tags": { "item": { "zone": "inventory" }, "unit": { "zone": "battlefield" } }
```

### One `play`, however many cards have it

A tag may carry a whole `play` block, and every card wearing the tag is played
that way:

```json
"tags": {
  "development": {
    "play": { "phases": ["act"], "needs": ["buyable@self >= 1"], "action": [ … ] }
  }
}
```

```json
{ "key": "t1_white_01", "text": "2R 1K", "tags": ["development"],
  "card_stats": { "cost_red": 2, "cost_black": 1 } }
```

Splendor's ninety development cards differ in what they cost and in nothing
else, and buying one is one sentence. Written on the cards it was ninety copies
of twenty-seven actions — three thousand lines whose only job was to stay
identical. Written on the tag it is said once, and the card is down to what is
printed on it.

**A card's own `play` wins, and wins whole.** The tag fills in for cards that
say nothing; a card that writes its own block takes none of the tag's. Half a
moment — the tag's action under the card's own cost — is the sort of thing that
reads as cleverness and debugs as neither.

**Two tags granting `play` is refused, and the card does neither.** Whichever
won would be the order somebody typed the tags. The validator names both, the
same way an ambiguous home is no home.

Only `play`. A tag's `activate` already reaches its cards through their
abilities, and one word with two roads into the engine is how a format grows
synonyms.

The zone route is a different question with the same spelling: a zone's
`applies` hands a tag to whatever *lies there*, and that is looked up as a card
moves. What a card's own tags say about it never changes, so it is settled once
at load — which is also why `dump` shows you a card with the moment already on
it.

### Keywords: a tag that means something to the player

A tag with a `tooltip` is a **keyword**. The game says once what it does, and
every card carrying the tag inherits the sentence — in the hover panel and in
the detail overlay a player opens to find out:

```json
"tags": {
  "tough":     { "tooltip": "Tough — takes 1 less damage from every source." },
  "overwhelm": { "tooltip": "Overwhelm — damage past the blocker hits the Nexus." }
}
```

```json
{ "key": "plucky_poro", "text": "Plucky Poro", "tags": ["unit", "tough"], … }
```

The card says which keywords it has and nothing about what they mean. Write the
name into the sentence — the engine adds no punctuation and makes no decision
about how it reads.

**The tag is still what the rules read.** `count:tough@across` is what makes
Tough happen; the tooltip is only what a player is told. A keyword whose text
nobody wrote is a tag like any other, and a keyword whose *behaviour* nobody
wrote is a sentence that lies — the two halves are independent and the engine
checks neither against the other.

The same field does a second job: on a tag a **zone** hands out through
`applies` it describes what lying there lets a card do ("Take this card into
your hand"). One field, because both answers are the same shape — what does
this tag mean for the card wearing it.

**A keyword can carry behaviour too**, not only text. A tag def's `abilities`
are given to every card wearing the tag, so the thing the keyword *does* is
written once beside the sentence that describes it:

```json
"overwhelm": {
  "tooltip": "Overwhelm — damage past the blocker hits the Nexus.",
  "abilities": [
    { "key": "spill_over", "text": "Overwhelm", "phases": ["strike"],
      "action": ["stat_damage:spill@self:…"] }
  ]
}
```

A card's abilities are asked in a fixed order: **its own, then what its zone
grants, then what its tags give it.** Keywords come last because one that
changes an *outcome* has to run after the outcome — there is nothing to send
past a dead blocker until the blocker has been struck.

Gate a keyword that is not meant to be clicked with `phases`. An ability run by
`activate_zone` is ungated and fires regardless; the phase list is what keeps it
out of a player's hands the rest of the time.

### What a name may repeat

**A key names one thing inside its own kind.** Two cards may not share a key,
and nor may two zones, two stats or two phases — the validator says so by name.

**Across kinds, a repeat is usually fine and sometimes the point.** A chess
piece is a card keyed `w_rook_h` *and* a tag of the same name, which is how one
piece is named by another's condition. A style sharing its name with a computed
tag is what makes a look follow the numbers. Neither is a mistake.

**One namespace is real, and it is what a *scope* resolves.** `@board` is asked
of patterns first, then zones, then tags, so two of those kinds sharing a name
means a condition silently picks one. The validator refuses that rather than
inventing a precedence rule you would have to remember:

```
'board' is the name of both a zone and a pattern — a condition pointing at it
could mean either, so rename one of them
```

Styles count as tag words here, since that is where they are named — so a style
may not be called after a zone, and *may* be called after a computed tag.

`self` and `all` are reserved for the engine. (`player` is not reserved: it is
an ordinary tag you put on one card, which is exactly what makes that card easy
to find.)

A tag's `zone` is the home of every card carrying it, and placement then
works by type instead of by naming zones in every action:

- `move_to` without a zone sends the played card home (`"play": { "action": ["move_to"] }`).
- `gain:card:n` creates cards directly in their home zone (no home: the hand).
- A `setup.place` entry with no `zone` puts the card in its home zone.

A game with a single board stays simple: cards without a home fall back to
it. With two or more boards (an inventory *and* a battlefield, say), every
card that enters play must know where it goes — the validator flags cards
whose tags don't say, and reports the conflict when a card's tags disagree.

### Board buttons

A card that starts in play and never leaves is the engine's button. Combine a
`setup.place` entry with an `activate.action`. A button stays clickable by
saying nothing: an ability spends its card only if its cost says so, and one
that charges no `exhaust` is available every turn.

```json
{
  "key": "pass_time",
  "text": "Let time pass",
  "activate": { "action": ["next_phase"] }
}

"setup": { "place": [{ "card": "pass_time", "zone": "table", "at": ["a1"] }] }
```

Add `activate.target` when the button needs to be pointed at something —
clicking it opens the same targeting arrow a played card uses, and the chosen
cards arrive in `activate.action` as targets:

```json
{
  "key": "workbench",
  "activate": {
    "cost": { "focus": 1 },
    "target": { "type": "card", "count": 1, "tags": ["material"], "zones": ["table"] },
    "action": ["stat_damage:hp@target:1", "stat_gain:progress:2"]
  }
}

"setup": { "place": [{ "card": "workbench", "zone": "table" }] }
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
stat_gain:gold:count:economic                        one per economic card
stat_gain:score:sum:value@mine.red:x:count:wager@mine.red
stat_damage:score:20:x:count:wager@mine.red            the same product, distributed
```

**A stat with a floor of zero subtracts down to it and no further, and that is
`max(0, a - b)`** — the one piece of arithmetic the grammar has beyond the
product, and it is worth knowing you have it. Splendor's whole pricing is this
and nothing else: a cost less a discount, then what is left over after the
tokens, then what the gold has to make up.

```
stat_set:due@self:sum:cost_red@self             what it says on the card
stat_damage:due@self:sum:red_bonus@mine.player  ...less the discount, never below nothing
stat_set:short@self:sum:due@self
stat_damage:short@self:sum:t_red@mine.player    what the tokens cannot cover
```

A yes/no comes out the same way: `max(0, 1 + have - need)` is 1 exactly when
`have >= need`, so **a condition can read one number** where an `and` across
five would be needed. Declare the working numbers as `hidden` stats with
`"min": 0` — the floor is what makes it work, and hiding them keeps the HUD to
what a player reads.

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
| `move_to:target:<what>` | …and say what becomes of a piece already standing there: `destroy`, or the zone it goes to (a captured-pieces tray). Left out, an occupied square refuses the move. This is capture; with it, aiming at a *piece* means taking its square rather than joining its zone |
| `gain:card:n` | Create n instances of a card in its home zone (or the hand) |
| `add_to:zone` | Move the acting card (overlay picks) |
| `move_target_to:zone` | Move each targeted card |
| `place:<who>:<where>` | Put every card the scope names on a square of the only board. `<where>` is a square by name (`"g1"`) or a **pattern pointing at one from the acting card** (`"one_left"`) — the second is how a rule works for both sides of a board, since a named square is only ever one player's. Refuses an occupied square |
| `stat_gain:<subject>:n` / `stat_damage:<subject>:n` | Change the current value, held between its floor and its ceiling, logged, and floated on the card. Two words for one arithmetic, because "damage 2" and "gain −2" read differently to everybody but the engine. The subject may carry a scope: `hp@target`, `hp@each.follower`, `hp@random.beast` |
| `stat_boost:<subject>:n` | Move the **ceiling** of a stat that has one (`card_stats` written `[current, max]`). Lowering it under the number standing there brings the current down with it; nothing else does |
| `stat_set:<subject>:n` | Set directly, past every bound, silently. A dev and authoring tool — how a phase resets a counter, not how a rule changes a number |
| `move:<scope>:<zone>` | Move every card the scope names into that zone. The scope-first sibling of the two above, for a set nobody picked: written twice with opposite owner words (`move:mine.battle:mine.bench`, then `enemy`) it covers both seats whoever is up |
| `set_active_seat:<scope>` | Whoever the scope names becomes the seat whose turn it is — the trick winner leading, the attack token holder acting first. Every other way of naming a seat is settled before the game starts, so this is the only one that reads off what just happened. Two seats is refused, none does nothing, and the handover ends the undo history |
| `set_owner:<scope>:<who>` | Hand those cards to a seat, to the one that is up (`mine`), or to nobody (`none`). Whose a card is is settled when it is dealt and stays settled, so this is the only thing that changes it: mind control, and a pile that disowns whatever lands in it |
| `activate_zone:<zone>[:<order>]` | Every card lying there does what it does — how a *phase* makes cards act instead of waiting for a click. Put the rule on a card, the card in a hidden zone, and have the phase say so. **Ungated**: the phase has already decided it is time. The order is the game's to state — naming none acts in the order the cards are in, `by_column` reads a board left to right; any other word is refused |
| `ready:<scope>` | Un-spend those cards, the counterpart to the `exhaust` cost. A phase's own actions run when it begins, so this is how a game says *when* being spent wears off rather than taking the engine's round boundary for it |
| `attach_to_target` | Attach the acting card under the first target |
| `options:<source>` | Offer a choice and open it. `<source>` is a zone, whose cards name the choices, or a comma-separated list of card keys. The chosen card is played with **the asking card as its target** |
| `transform:<scope>:<card>` | Replace each card in scope with a new one of that key, standing on the same square, in the same zone, belonging to the same player. Everything else is the new card's own |
| `resolve_challenge` | Ask the card's `challenge`: run its `pass` or its `fail`. The condition is asked with the acting card and its targets in hand, so it may say `@self` and `@target` |
| `effect:name` | Play a named visual effect on the acting card (headless: skipped) |
| `reveal:card` | Conjure the card into the page overlay; playing it there continues the story |
| `reveal_top:zone` | Turn over a zone's top card into the page overlay (shuffle secrets) |
| `next_phase` / `push_phase:key` / `pop_phase` | Phase control |
| `destroy:<scope>` / `destroy_self` | Remove cards from play entirely. A bare zone key is a scope, so `destroy:hand` is unchanged; `destroy:each.enemy.creature` is a board wipe that spares your own. A card cannot be partly destroyed, so only `random.` narrows — to one victim |
| `load_game:file` | Switch games (menu items, endings). `file` must be a bare `name.json` — no path, no `..` — and is refused otherwise |
| `save_game:<slot>` / `load_save:<slot>` | Write the position out, and put it back. The slot is a plain word your game picks; where it lands is the engine's business. See *Saving a game* below |

### Engine behaviors you get for free

Undo (Z / button, 50 steps, includes the event log — cleared by `no_undo`
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
is exactly what it had to do to be hot-seatable: **list two seats under
`players`**, and give the turn-taking phases `"seat": "next"`.

**Whether an invite is *offered* is still a card's decision, deliberately.** The
engine never counts seats and decides for you: a game that wants to be shared
deals a card whose action is `net_invite`, and a solitaire game deals none. That
keeps a question about content — *should this game be played with somebody?* —
out of the interface, where it was once a branch in a panel. What `players`
changes is that the *fact* is now readable: two entries means two seats, so a
menu can say so and the validator can warn when a game offers an invite it has
no second chair for.

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
  files renders as text on their side, while a `generate_art` card looks identical
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
{
  "key": "play_lost_cities_net",
  "text": "Lost Cities · online",
  "play": { "action": ["load_game:lost_cities.json", "net_seat:north", "net_invite"] }
}
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

### Saving a game, and picking it up

Two actions and one condition, and no format to learn:

| | |
|---|---|
| `save_game:<slot>` | write the position out |
| `load_save:<slot>` | put it back — whichever game it was of |
| `saved:<slot> >= 1` | a condition: is there anything in that slot |

**A slot is a word, not a path.** Your game says `quick` or `autosave` or
`slot_3`; the engine decides where that lands, for the same reason `load_game`
refuses a path — a game file can arrive from a stranger over the network and
parses through the same door. One word is one save, so a game that wants a
single autosave writes one and a game that wants three writes three; nothing in
the engine has an opinion about how many that should be.

**What a save contains is exactly what a networked opponent would be sent** —
the same state, the same encoding, checked the same way. That is why there is
nothing to say about the format here: anything that made a save different from a
message would be a second thing to keep correct.

The whole loop is two cards. Chess deals a button:

```json
{
  "key": "save_button",
  "text": "Save",
  "tags": ["immutable"],
  "play": { "action": ["save_game:quick"] }
}
```

and the menu deals the card that picks it up, dimmed until there is something to
pick up:

```json
{
  "key": "m_continue",
  "text": "Continue",
  "tags": ["token", "immutable"],
  "play": { "needs": ["saved:quick >= 1"], "action": ["load_save:quick"] }
}
```

Note what *Continue* does not say: which game. A save names its own file and
that file is loaded first, so one card on the menu resumes whatever was saved.

Two refusals, both of which say so in the event log rather than failing quietly:

- **The game file has changed since.** A position means something else against
  different rules, and no amount of loading it fixes that — so a save carries a
  hash of the file it was taken from and is refused when they disagree. Edit a
  game you have saves of and those saves are gone; that is the honest answer
  rather than a game that plays strangely.
- **A network game is connected.** Two people saving one shared game write two
  files that each claim to be it.

**A loaded game keeps its log and loses its undo history.** Both are what the
network already does with every state that arrives, and for the same reason: the
moves before the save were made in a game this process never ran, so undoing
into one of them would fork it.

Where the file lands is the platform's business — LÖVE's save directory on a
desktop, and in the browser a folder inside IndexedDB, which the engine pushes
across after every write because the browser only flushes it on quit and a tab
is never quit.

### Hardcoded conventions

**The engine injects two cards**, into a hidden zone it also owns. A `system`
card carries `round` and `turn` — the round belongs to the game, so two seats
cannot get two calendars. A `player` card carries its seat's `stats`, and is
injected only when a game declares no card tagged `player` of its own. The
`system` card sitting in the `system` zone and the `player` card carrying the
`player` tag are both fine: neither name is one a scope resolves, and a game
that wants a visible hero just tags a board card `player` and gets no injection.

`menu.json` boots the engine. Zone keys `hand` (default deal/pick target),
`graveyard` (draw_and_play discard), `board` (where a placement with no zone lands) are
load-bearing names; `reveal` names both the built-in page zone and overlay
phase, and `system` the hidden zone holding the engine's own two cards (a game
may declare any of them to override). The tag `player` marks a seat, and the
card key `system` the round counter. The tag `immutable` means scenery: nothing
may target such a card and its template can never be edited — put it on menu
entries and anything else that is interface rather than game. Clicking a face-up
card plays it; clicking a grid card, or the top of a pile, activates it; decks
aren't clickable unless they carry an `activate` block, which is how a deck is drawn from.

Reserved words that a zone or tag may never be named: `self` and `all` (the
engine answers for them in scopes), plus the quantifiers `any` / `each` /
`random` and the owner words `mine` / `enemy` / `anyone`, which are read as
prefixes in a scope expression rather than as names. `player` is deliberately
*not* reserved — it is an ordinary tag you put on a card.
