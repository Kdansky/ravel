# Authoring Games for Ravel

A game is one JSON file in `game/games/`, plus optional images in
`game/games/assets/` (sources and licenses are recorded in
`assets/CREDITS.md` — keep it that way when adding art). No code.

This document is meant to be complete: two walkthroughs, a procedure for
**translating a published rulebook into a game file** (§3), a recipe for every
common case (§4), and a full reference for every field the engine reads (§5). If
something is not here, the engine does not read it. Every whole-file example is
run through the validator by the test suite, and the index below is held to the
headings it indexes, so this document fails a build rather than your afternoon. `DESIGN.md` explains *why*
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

## Where to look

| If you want | Go to |
|---|---|
| the shortest file that runs | §1, and copy it |
| a story with no board | §2, or copy `starter_cyoa.json` |
| to turn a rulebook into a file | §3, which is a procedure rather than a feature list |
| a working two-player game | §4, first recipe — it is a whole file, and the suite runs it |
| "how do I say *X*" | §4, which is a list of those questions |
| what a field means | §5, indexed below |
| every field there is, alphabetically | `SCHEMA.json` |

**The reference index.** §5 is long because the format is large, not because it
says anything twice. These are its headings, grouped by the question each one
answers; a test holds this list to them, so a section that exists is listed here
and a line here names a section that exists:

- **What a file holds** — Top-level fields · Stats · Zones · Players · Setup · Card templates · Two marks in card text · Named assets · Styles · Effects · What a name may repeat · Hardcoded conventions
- **Whose turn it is** — Phases · A phase that leads back to itself · A turn's opening bookkeeping · A choice before the game · Every seat, once · Two or more players · The player is a card · A stat says whose number it is
- **Asking the board a question** — Conditions (one vocabulary everywhere) · `needs` and `where` — asked once, or asked of each · `@everywhere` — every card, hands and decks included · `@owner_of` — the seat a card belongs to · `@reach` — wherever a set of pieces could move · `<zone>.<tag>` — one place, one kind · A pattern is also a scope · `across` and `beside` — pointing at the other cards · What counts as in play · `supply` — a stock the engine counts for you · Looking inside a deck · `last_acted` — the card a player touched last · `computes` — a number with a name · Computed tags
- **What a card does** — Actions · A card that can do several things · `merge` — what an ability says to the others on its card · `when` — an ability with an if in it · One `play`, however many cards have it · Tags with behaviour · `buffs` — a tag that changes a number · `verbs` and `adjusts` — a moment with a name, and something that answers it · Keywords: a tag that means something to the player · Every tag the engine reads · Board buttons · A card with nothing to run is not a move · `pays_for` — one thing spent as another · Doing what another card does · `leaves` — a card on its way out
- **Making somebody choose** — Asking a question · A question that may go unanswered · Reading somebody else's hand · `chosen.where` — which of the revealed cards may be taken · Only one of them: `random.` · Making *them* choose · Nothing moves while an offer is open
- **Answering what somebody did** — Reactions — answering another player's action · What the player sees · `whose` — whose announcement it answers · `spent` — where a card lands however it ends · A phase announces itself · `emit:` — announcing something that is not a card being played · A mandatory reaction is how you ask somebody else a question · What it will not do yet
- **Boards and pieces** — Pieces that move · Asking about the square you are considering · Moves with fixed destinations (castling) · Legality between two cards · Which end of a deck a card lands on · `origin` — back where it came from · `fan` — a stack you can read
- **Outside the game itself** — Engine behaviors you get for free · Playing over a network · Offering it from your own game · Saving a game, and picking it up

---

## 1. Walkthrough: a minimal game

```json
{
  "title": "My Game",
  "stats": [{ "key": "hp", "label": "Health", "min": 0, "max": 10 }],
  "zones": [
    {
      "key": "deck",
      "layout": "stack",
      "visibility": "secret",
      "pos": [0.05, 0.1, 0.25, 0.6],
      "tags": ["shuffle"],
      "contents": ["sword:3", "trap:2"]
    },
    { "key": "hand", "layout": "row", "pos": [0.19, 0.65, 0.95, 0.98] }
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
  "zones": [{ "key": "hand", "layout": "row" }],
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
   `layout: "stack"` with `visibility: "secret"` and `contents`; a hand is a
   `row` that is `visibility: "owner"` and `copies: "per_seat"`; a personal
   tableau is a `grid` with `copies: "per_seat"`; a shared board, market row or
   discard pile is the same without the copies.
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
| "…to your own area" | a grid zone with `copies: "per_seat"`; `move_to:<zone>` resolves to yours |
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

## 4. Common cases

Every entry below is a question authors actually ask and the shortest true
answer. The first is a whole file; the rest are the few lines that carry the
rule, with the reference section that holds the detail.

### A two-player game, whole

Nothing here is scenery. Two seats, a shared deck, a hand each, one card a turn,
first to ten:

```json
{
  "title": "Two-Player Skeleton",
  "stats": [{ "key": "score", "label": "Score", "min": 0 }],
  "players": [{ "card": "north" }, { "card": "south" }],
  "zones": [
    { "key": "deck", "layout": "stack", "visibility": "secret", "tags": ["shuffle"],
      "pos": [0.05, 0.35, 0.2, 0.65], "refill_from": "discard",
      "contents": ["coin:12", "gem:8"] },
    { "key": "discard", "layout": "stack", "pos": [0.8, 0.35, 0.95, 0.65] },
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.25, 0.7, 0.75, 0.95], [0.25, 0.05, 0.75, 0.3]] }
  ],
  "cards": [
    { "key": "north", "text": "North", "card_stats": { "score": 0 } },
    { "key": "south", "text": "South", "card_stats": { "score": 0 } },
    { "key": "coin", "text": "Coin", "tooltip": "Score 1.",
      "play": { "action": ["stat_gain:score:1"], "spent": "discard" } },
    { "key": "gem", "text": "Gem", "tooltip": "Score 2.",
      "play": { "action": ["stat_gain:score:2"], "spent": "discard" } }
  ],
  "phases": [
    { "key": "deal", "type": "automatic", "actions": ["each_seat:draw_from:deck:mine.hand:3"] },
    { "key": "turn", "type": "player_input", "label": "Play one", "zone": "hand",
      "seat": "next", "ends_after": 1,
      "actions": ["draw_from:deck:mine.hand:1"],
      "next": [{ "then": "turn", "ends_round": true }] }
  ],
  "end_conditions": [{ "when": "max:score@anyone.player >= 10", "then": ["load_game:menu.json"] }]
}
```

Five decisions, and everything else follows from them:

- **`players` declares the seats**, and each names a card. That is what makes a
  score a number *on* something — `card_stats` on `north` — rather than a global
  the engine would have to keep a table of.
- **`copies: "per_seat"` gives one hand each**, and `pos` then takes one rect per
  seat. `mine.hand` reaches whoever is up, so no rule is written twice.
- **`seat: "next"` hands over and `ends_after: 1` says when.** The route back to
  `turn` says nothing about the seat, so the phase's own word answers. Saying
  `"seat": "same"` on that route is the other game entirely: a turn that carries
  on until the player is done with it.
- **`refill_from` closes the loop.** The deck rebuilds from the discard when
  somebody draws and finds it empty — not when it empties, which is a different
  moment and the wrong one.
- **`max:` in the end condition is load-bearing.** Drop it and the game ends at
  five points each. See *Somebody has reached ten* below.

### Dealing and drawing

**Deal a hand to everybody.**

```json
{ "key": "deal", "type": "automatic", "actions": ["each_seat:draw_from:deck:mine.hand:5"] }
```

`each_seat` runs the action once per seat with that seat up, so `mine.hand` is a
different hand each time and four players cost the same line as two.
→ *Every seat, once*

**Draw one at the start of every turn.** Phase `actions` run on every entry,
including the loop back into the same phase:

```json
{ "key": "turn", "type": "player_input", "seat": "next", "ends_after": 1,
  "actions": ["draw_from:deck:mine.hand:1"] }
```

A counter that must reset *once a turn* and not on the way round goes in
`on_enter` instead. → *A phase that leads back to itself*

**A deck that never runs out.** The draw pile names the pile it is rebuilt from:

```json
{ "key": "deck", "layout": "stack", "visibility": "secret", "refill_from": "discard" }
```

**Where a played card ends up.** Once, on the play block, rather than a
`move_to` at the end of every action list it has:

```json
"play": { "action": ["stat_gain:score:1"], "spent": "discard" }
```

→ *`spent` — where a card lands however it ends*

### Permission and cost

**"Costs 2 gold."**

```json
"play": { "cost": { "gold": 2 }, "action": ["stat_gain:might:1"] }
```

A `cost` is **spent**; a `needs` is only **checked**. Two words because they do
two things, and `"gold >= 2"` in a cost would say the wrong one.

**"Only if you have three farms."**

```json
"play": { "needs": ["count:farm >= 3"], "action": ["stat_gain:gold:2"] }
```

**"Once a turn."** Being spent is itself the cost:

```json
"activate": { "cost": { "exhaust": 1 }, "action": ["stat_gain:gold:3"] }
```

An ability that charges no `exhaust` stays available all round, which is how a
permanent button works. Only an *activate* cost may ask for it — a card leaving
a hand has nothing left to stay spent.

**"Sacrifice a militia."** A cost paid in cards rather than numbers. The word
after the colon is a **tag**, not a card key, so one line prices a whole class:

```json
"play": { "cost": { "sacrifice:unit": 1 }, "action": ["gain:garrison:1"] }
```

It destroys that many of your board cards carrying the tag, oldest first.
Upgrade chains, trials payable in blood and story dilemmas are all this one
line.

**"Costs what it says on the card."** A cost amount may be measured rather than
typed, which is the whole of a shop:

```json
"activate": { "cost": { "coin@mine.player": "price@self", "stock@self": 1 },
              "action": ["fill:mine.discard:@self:1"] }
```

One ability, on the tag the shelf hands out, reading each shelf's own price. A
*quoted* number is refused rather than read, since it measures nothing.
→ *`supply` — a stock the engine counts for you*

### Whose turn it is

**Alternate.** `"seat": "next"` on the phase, and let the route say nothing.

**Carry on until they are done.** The route overrules the phase:

```json
"next": [{ "when": "done@mine.player >= 1", "then": "score" },
         { "then": "act", "seat": "same" }]
```

**Whoever won the trick leads next.** The only seat named by what just happened
rather than settled before the game began:

```json
{ "key": "collect", "type": "automatic",
  "actions": ["stat_gain:tricks@owner_of.taker:1", "set_active_seat:taker"] }
```

`taker` is a tag the game put on the winning card a moment earlier. Naming the
*card* is enough for `set_active_seat`, which reads a card as its owner;
`owner_of` is only needed where the seat is what carries the number.
→ *`@owner_of` — the seat a card belongs to*

### Numbers

**A score each seat carries.** A seat is a card, so it is `card_stats` on that
card, and a bare `score` in a condition means the seat that is up.
→ *A stat says whose number it is*

**Somebody has reached ten.** ⚠ **`score@anyone.player >= 10` is the wrong
spelling and passes the validator.** A bare stat over several cards is their
**sum**, so that fires when two seats hold five each. Three readings, all legal,
all different:

| Written | Holds when |
|---|---|
| `score@anyone.player >= 10` | the **total** across every seat reaches 10 |
| `max:score@anyone.player >= 10` | **some** seat has reached 10 |
| `score@each.anyone.player >= 10` | **every** seat has reached 10 |

The middle one is nearly always what an end condition means. The rule behind it
is under *`@everywhere`*, in the **Quantifiers** table: `any` — the default —
asks of the pool, and a pool of stats is a total.

**A number worked out from other numbers.** `computes` binds a name before the
action list runs, and holds the one arithmetic operator a cost has no room for.
→ *`computes` — a number with a name*

**A working number the player should not see.** Declare it `"tags": ["hidden"]`
with `"min": 0`. The floor is what gives you `max(0, a - b)`, and that single
piece of arithmetic is how a five-way check collapses into one comparison.
→ *Actions*, under **Numeric slots**

### Making somebody choose

**One of three named cards.**

```json
"play": { "action": ["options:tempo,money,tricks"] }
```

The chosen card is played with the asking card as its target. `:optional` adds a
No button. → *Asking a question*

**One card out of a real zone.** `options:<zone>` deals *fresh* entry cards from
it; `show:<scope>` lends the **real** cards and sends them home when the offer
closes. Reading an opponent's hand is the second one:

```json
"play":   { "action": ["show:enemy.hand:optional"] },
"chosen": { "action": ["move_target_to:enemy.discard"] }
```

**Anything that moves the phase, the seat or priority belongs in `chosen`,
never beside the `show:`.** All three are frozen while an offer stands, and the
change is refused where it is written. → *Nothing moves while an offer is open*

### Boards and pieces

**A board with squares.**

```json
{ "key": "board", "layout": "grid", "grid": [8, 8], "pos": [0.2, 0.05, 0.8, 0.95] }
```

A `grid` is `status: "board"` — in play — without saying so, and a card arriving
without slot targeting takes the first free cell.

**Pieces laid out like the diagram in the rulebook.**

```json
"setup": { "place": [
  { "card": "pawn", "owner": "player_white", "zone": "board",
    "at": ["a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2"] }] }
```

`at` taking a list is what makes chess six cards rather than thirty-two.

**A piece that moves, and takes what it lands on.**

```json
{ "key": "rook", "activate": { "moves": ["line_ortho"],
                               "action": ["move_to:target:destroy"] } }
```

`moves` writes the targeting for you. The `:destroy` is what makes aiming at a
*piece* mean taking its square; without it an occupied square refuses the move.
→ *Pieces that move*

### Ending

**When a pile runs out.** The one question the comparison grammar cannot ask
keeps a word of its own:

```json
"end_conditions": [{ "zone_empty": ["deck", "hand"], "then": ["push_phase:victory"] }]
```

**With a screen rather than a jump to the menu.** An ending is an overlay
dealing one card, and the card carries an `outcome`:

```json
{ "key": "fate_win", "layout": "stack", "visibility": "secret",
  "display": "offscreen", "contents": ["journeys_end"] }

{ "key": "victory", "type": "overlay", "label": "Journey's End",
  "deck": "fate_win", "zone": "victory_offer", "draw": 1 }

{ "key": "journeys_end", "outcome": "victory", "text": "Journey's End",
  "play": { "action": ["load_game:menu.json"] } }
```

`outcome` buys the banner, the summary of the run's visible stats, and the
confetti or the falling embers. End conditions fire once per game, wait for an
open overlay, and then run their `then`.

**Reachable at all.** A game the menu does not offer is a game only the CLI has:
add a card to `menu.json` with `"play": { "action": ["load_game:mygame.json"] }`.

Or don't: the menu's **Open a file** card asks for one wherever you keep it, and
dropping a `.json` onto the window does the same thing without the card. Either
way the file is read where it lies — nothing is copied into the engine and
nothing is uploaded anywhere — so a game you are still writing is one drop away
from being played, and a game somebody sends you needs no installing.

### Arrangements worth copying whole

Longer shapes, each named with the game that already does it.

**Forced plays, one card a turn** (`castle.json`). `draw_and_play` phases in
list order: playing one card discards the hand and advances, and the list wraps
to the first non-automatic phase, which ends the round. Always give these a
`pass_card` — a forced play needs an out.

**A free hand with a Done button** (`kingdom.json`). A `player_input` phase with
`deck`, `draw` and a `pass_card`, ended by a router token:

```json
"play": { "needs": ["plays >= 1"], "action": ["destroy_self", "next_phase"] }
```

**A shop** (`splendor.json`). A `supply` zone whose `applies` tag carries the
buy, priced off the shelf being bought. Nothing may point at a supply's cards,
and it is exactly that which lets one card stand for sixty-four.

**A story with no board** (`starter_cyoa.json`). Pages are cards with `story`,
choices are cards with `tooltip`, and there is no phase plumbing at all — §2.

**A trick-taking round** (`the_crew.json`). `ends_when` rather than
`ends_after`, because putting a card in the middle ends your turn and everything
else you may do does not:

```json
{ "key": "lead", "type": "player_input", "zone": ["hand", "open"],
  "ends_when": "count:play_card@trick >= 1" }
```

**A crisis that persists** (`castle.json`). `resolve_challenge` with a
`challenge` block, where `fail` starts with `move_to:board`, the card carries a
`turn.action` that drains you every round, and `activate.action:
["resolve_challenge"]` lets the player answer it later. Failure becomes
escalating pressure instead of a slap.

**Tiers, acts and loops** (`kingdom.json`). Structure driven by a number is
`next` routing plus a stat that cards raise in their own `play.action` — there is
no separate progression machinery, and there does not need to be.

**An engine that ticks** (`kingdom.json`). `turn.action` on a board card runs
once a round. Synergy is `count:<tag>` in an amount
(`stat_gain:gold:count:economic`), a threshold is a computed tag, and a burst is
an `exhaust`-limited `activate`.

**Sub-card choices** (`demo.json`). The options live in a hidden deck, the
parent card pushes an overlay over it, and the *offer zone* `applies` a tag
whose `play.action` sends the pick to hand and returns the rest. That behaviour
belongs to the offer, not to the cards being offered — which is why every game
that deals a choice writes it once. Taking one and putting the rest back is the
whole of that tag:

```json
"play": { "action": ["add_to:hand", "return_to:offer:build_deck",
                     "shuffle:build_deck", "pop_phase"] }
```

### When the JSON starts to fight you

The format is meant to hold the whole rule, and a few shapes are the file
telling you it does not hold this one. Say so rather than building a tower:

- **The same list written twice with `mine` and `enemy` swapped.** That is one
  rule about both seats, spelled as two. `move:<scope>:<zone>` and `each_seat:`
  cover most of it; where they do not, the missing thing is a word in the
  format.
- **A condition wanting *or*.** There is none, deliberately — a list means
  *and*, and *or* is usually two abilities. Where it genuinely is not (one card,
  one click, two ways to qualify) it is an open question on `todo.md` rather
  than something to encode.
- **A number you can only reach by adding three things.** `computes` takes one
  operator and no parentheses on purpose. Two chained is the intended answer;
  four means the rule wants a word of its own.
- **A phase that exists only to run one action.** Check `on_enter` against
  `actions` first: that split already removed a whole class of near-duplicate
  phases, and the second one is usually the first with a word missing.

An engine change is cheap next to a game file nobody can read. The validator,
`SCHEMA.json` and this document are all held to the engine by tests, so a word
that gets added arrives in all three or not at all.

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
`coin`, `heart`, `shield`, `banner`, `leaf`, `blade`, `diamond`, or `none`.
**Named by shape, not by meaning** — what your game calls its currency is your
business, and the engine has no opinion about which word means money. A closed
set: a shape nobody draws is refused rather than silently becoming a diamond.
Left out, it *is* the diamond.

`none` draws no shape, and the number closes the gap where one would have been.
Write it when the number needs no picture to be read — a pile that says how many
are left, on a plate whose colour and label already say what it is a pile of.

`color` is what colour that shape is drawn in — a palette name or `#rrggbb`,
the same vocabulary a zone paints its squares with. Left out, the shape's own
colour is used, which is what makes an undeclared stat readable at a glance.
Say it when the six shapes run out before your numbers do: Splendor has five
gems, borrows five silhouettes, and its onyx came out an orange sword.

`min` and `max` are the bounds every bearer of the stat is held between, and a
card may narrow them for itself by writing the same two words beside its value
(`"hp": { "value": 4, "min": 0, "max": 4 }` — see *Cards*). A card that declares
neither takes the global rule, and where there is no global rule there is no
bound at all.

**Reserved:** `round` (starts 1, +1 per round boundary) and `plays` (per-hand
play counter) are engine-managed — declare them only to display them.

A stat a game keeps on its *cards* rather than its players still wants an entry
here, `display: "offscreen"`: that is where its bounds and its icon are said, without
it becoming a row in the HUD.

`subject` overrides what the HUD row *reads* while the key still names what
cards spend: castle's defense lives on the buildings that provide it and shows
as their total, `{ "key": "defense", "subject": "sum:defense@standing" }`.

### Zones

| Field | Meaning |
|---|---|
| `key`, `label` | Identity and optional on-screen label. A label is written across the top of the zone and the cards keep clear of it, so a named zone is still named once something is in it — which costs a line of height, and a zone whose cards are sized by their height wants a little more room than an unnamed one. **Two labels are read off the engine instead of printed**: `current_phase` and `current_player`. A board shows what is where and says nothing about whose turn it is or which part of it this is, so an empty `grid [1, 1]` with one of those labels is a readout |
| `layout` | Where the cards are drawn. `stack` (one on top of another — only the top shows), `row` (side by side, each showing its text — wrapping onto more lines rather than shrinking when one line would be too tight), `grid` (addressed cells), `page` (each card fills the zone, for a story panel) |
| `visibility` | Who may read them, and **nothing else** — a card in play may be unreadable and a card nobody can touch may be plain to see. `public` (default), `owner` (the seat whose zone it is; a zone with no seat is nobody's secret and stays public), `secret` (nobody — backs out, and a stack's order is scrambled in the browser, because the order is the secret and the contents usually are not) |
| `reach` | Which of the cards here exist as far as the rules go: `all`, or `top` — only the last one. A `stack` is `top` unless it says otherwise |
| `use` | What may be done with a card lying here **at all** — the ceiling, which a phase's `zone` then narrows: playing needs both to agree. `play` (default), `abilities` (its own `activate` blocks work here — what a board means), `none` (a box you use rather than reach into, which is how a trash or an exile is made untouchable). A `secret` zone is `none` unless it says otherwise, which is what makes a deck a deck |
| `status` | What standing a card lying here has **in the rules** — a different question from what the zone looks like. `board` is in play, `offer` is a card lent to a question, `exile` is everything else and is the default. A `grid` is `board` and an `options` zone is `offer` without saying so. See *What counts as in play* |
| `display` | `onscreen` (default) or `offscreen` — not drawn, and nothing in it clickable. For offers, fate decks and rules pages. Not the same as `secret`, which is a zone you can see and cannot read |
| `copies` | `one` (default) or `per_seat` — one zone each, and `pos` then takes one rect per seat |
| `pos` | `[x1, y1, x2, y2]` window fractions — optional; each layout has a default spot (an `offscreen` zone defaults off the edge, giving dealt cards their fly-in) |
| `grid` | `[cols, rows]`. Legal only where `layout` is `grid` — **a value names its own parameter field**, and every word on every one of the seven is reserved against being a field name for anything else |
| `row` | Which way a row fans, so every card in it can be read at once: `down` or `right`. Legal only where `layout` is `row`; left out, the cards sit side by side and do not overlap |
| `contents` | Starting cards: `"key"` or `"key:count"` strings |
| `tooltip` | Prose shown when the zone is hovered. A deck answers for itself — there are no cards in it to ask, only a deck |
| `activate` | The zone's **own** ability, in a card's words: `cost`, `phases`, `action`, `target`. This is how a deck is drawn from — the box answers, rather than the card on top of it becoming clickable. Gated like a card's: the phase it works in, what it costs, and whose zone it is. Not to be confused with `applies`, which hands an ability to the cards *lying* there |
| `refill_from` | The zone this one is rebuilt from when something tries to draw from it and finds it empty — a deckbuilder's draw pile naming its discard. Everything there moves in and the pile is shuffled; a per-seat zone takes the same seat's copy, so one line serves every player. **Asked for, not fired on emptying**: a rule that clears the pile on purpose is left alone, and the loop closes wherever it actually runs out — mid-draw, mid-action, inside a card that draws four, which is exactly where a phase loop cannot reach |
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
| `zone` | where it goes. Leave it out and its home tag decides, then the only board. A zone with `copies: "per_seat"` gets one copy in **each** seat's — a marker declared once appears on every player's board |
| `at` | the square, named the way a player would say it: a column letter and a rank counted from the near edge, so `"e1"` is the white king's. Grid zones only; without it the card takes the first free cell |

`place` is the only thing `setup` holds. **Starting numbers are the seat's, not
setup's** — `players[].stats` for an injected seat, `card_stats` on the card for
one a game named. `setup` used to take a `player` map beside `place`, and read
it nowhere; the field set is asked for now rather than written out at the call
site, so the manual and `SCHEMA.json` are held to it like any other.

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

### A choice before the game

Some games ask a question before there is a board: which mission, which
character, which variant. There is no setup-time question — `setup.place` lays
out what comes out of the box and nothing else — so the answer is an ordinary
**leading phase**, and what it decides is written by the picked card's own
`play.action`.

**One question for the table** is an overlay pushed from the first phase. The
Crew asks how many tasks this way: five cards in a hidden zone, one of them
played, and its action writes a number the deal then reads.

```json
{ "key": "setup", "type": "automatic", "actions": ["push_phase:mission"],
  "next": [{ "then": "deal" }] },
{ "key": "mission", "type": "overlay", "zone": "mission" }
```

**One question per seat** is a draft: one phase per seat, each opening the same
offer, and each pick configuring the seat that made it.

```json
{ "key": "pick_1", "type": "player_input", "seat": "next",
  "label": "Choose your character",
  "actions": ["options:char_grave,char_jaina,char_midori,…"],
  "ends_when": "picked@mine.player >= 1", "next": [{ "then": "pick_2" }] },
{ "key": "pick_2", "type": "player_input", "seat": "next",
  "label": "Choose your character",
  "actions": ["options:char_grave,char_jaina,char_midori,…"],
  "ends_when": "picked@mine.player >= 1", "next": [{ "then": "deal" }] }
```

```json
{ "key": "char_jaina", "text": "Jaina", "tags": ["immutable"],
  "play": { "action": ["fill:mine.bag:playing_with_fire:1",
                       "fill:mine.bag:burning_vigor:1",
                       "fill:mine.bag:unstable_power:1",
                       "fill:mine.bag:crash_gem:1", "fill:mine.bag:gem_1:6",
                       "stat_gain:picked@mine.player:1",
                       "set_owner:self:mine", "move_to:mine.fighter"] } }
```

Four things about it are worth knowing before you write one:

- **The roster is the offer, not a zone of its own.** A band of screen wide
  enough for ten characters is a band kept empty for the rest of the game, and
  an empty zone still paints over what is under it. The offer is drawn over a
  dimmed board and is not there when it is not open; claim the `options` key
  and give it the middle of the screen.
- **`ends_when`, not `ends_after`.** Choosing out of an offer is deliberately
  not a play — the play counter belongs to the phase *under* the overlay — so
  the phase watches a flag the chosen card sets instead.
- **`seat: "next"` goes on the first pick as well.** The turn counter starts at
  *nobody*, so the first handover in a game is what selects seat one. Leave it
  off and both picks resolve to the same player.
- **The deal comes after, not in `setup`.** Nothing about a character exists
  until it is chosen, so shuffling and dealing belong in the automatic phase the
  last pick routes to — `each_seat:shuffle:mine.bag`, then
  `each_seat:draw_from:mine.bag:mine.hand:5`.

Sweeping is free: an offer clears itself when the choice is made.

### A turn's opening bookkeeping

**Only a phase a player acts in hands the turn over.** The seat changes on a
fresh entry into a `player_input` phase, and an `automatic` phase never rotates
— so a "start of turn" phase in front of the one the player acts in runs for
the *previous* player.

Put the resets, the upkeep and whatever the turn deals on the first phase the
player acts in, using its own `actions`:

```json
{ "key": "action", "type": "player_input", "seat": "next", "zone": "hand",
  "actions": ["stat_set:money@mine.player:0", "stat_set:acts@mine.player:1",
              "activate_zone:mine.ongoing", "activate_zone:rules_ante"],
  "ends_when": "acts@mine.player == 0", "next": [{ "then": "buy" }] }
```

### Card templates

| Field | Meaning |
|---|---|
| `key` | Unique identifier |
| `text`, `tooltip`, `asset` | Presentation. `asset` is optional and may be a filename, an `http(s)://` URL, a procedural shape spec, or `"auto"` (see *Art without assets*). A card's **colour is a style it tags** — see *Styles* |

A local `asset` must be a bare filename (`sword.png`, not `../sword.png` or
a path) — this is enforced, not just a convention, since games can be
authored by people other than whoever is hosting the engine.

### Two marks in card text

Prose a player reads — a card's `tooltip` and `story`, a zone's `tooltip` — may
carry exactly two marks:

```json
{ "key": "magicdart", "text": "Magic Dart",
  "tooltip": "Deal *1 damage*. _The first spell anyone learns, and the last one anyone respects._" }
```

`*bold*` is the mechanics: a stat, a keyword, a number the player has to act on.
`_italic_` is flavour, and is set one size smaller than the body — the point is
that the eye can skip it while it is still deciding what to play.

There is no more markdown than that — no headings, no links, no code spans —
because a card is one paragraph and the alternative is a language with
precedence living inside a game file. The two marks are independent, so one may
sit inside the other (`_a *magic* word_` is a bold word in a flavour line);
what there is no such thing as is bold inside bold.

**A mark that does not close is not a mark.** `weather_now` stays one word,
`2 * 3` stays arithmetic, and `un*even` keeps its star, because a mark only
opens where a word begins and only closes where one ends. A style never reaches
across a line break either. The one case nobody can mean — a mark that opens a
style and never shuts it — is a validator warning, since in the file it looks
exactly like text that is fine.

The marks are drawn, not set: LÖVE ships one face, so bold is the glyphs struck
twice and italic is the glyphs sheared. Everywhere text is read rather than
drawn — the CLI player, a log line — the marks come off.

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
| `card_stats` | Per-instance stats stamped at creation. A number is a bare current value; a card that carries its own bounds writes them by name — `{ "value": 4, "max": 4 }`, and `min` beside them — which are the same three words the `stats` entry uses. `hp` shows a badge; 0 hp = ruined, skips `turn.action` |
| `play` | Playing the card. `cost` is spent (gates the card and dims it when unaffordable; `"sacrifice:<tag>": n` pays by destroying n board cards with that tag). `needs` is a non-consuming gate, asked once before targeting opens and so blind to targets — see *`needs` and `where`*, which also carries the escape hatch. `target` is click-to-target (below). `phases` is a phase key or list, and naming none means any — this is "cast only during your main phase". `action` is what happens |
| `activate` | The board ability, in the same words: `cost`, `target`, `phases`, `action` (no `needs` — an ability is gated by its cost and its phase). **Being spent is a cost**: `"cost": { "exhaust": 1 }` makes it once-a-round, and an ability that does not charge it stays available, which is how a permanent button works ("pass the time"). A board card shows three states — ready, greyed "exhausted" (spent this round), greyed "can't yet" (cost or targets unavailable). `moves` says how a piece moves on a grid and writes the `target` for you (see *Pieces that move*) |
| `reactions` | A list of subscriptions to another player's action — each with the verb it answers (`to`), a condition about the event (`where`), a condition about the reactor (`when`), and the `cost`, `target` and `action` an ability has. `spent` says where the card lands once its answer is over. See *Reactions* |
| `emits` | What playing or activating this card **announces**, so a reaction may answer it: `{ "play": "cast" }`. Beside the moments rather than inside them, because a tag granting a `play` block grants it whole — written on a tag, one line makes every spell in the game answerable |
| `play.spent` | Where the card goes once its play is over, **however it ends** — resolved, or countered before it ever ran. Opt-in; without it the action list is answerable for its own card |
| `challenge` | **Not a moment — a named test.** `needs` is the condition, `pass` and `fail` the action lists it chooses between, and any action list reaches it by running `resolve_challenge`. That is why it sits beside the moments rather than inside one: kingdom's crises are resolved when *played*, and if they fail they stay on the board to be *activated* later — one challenge, asked from two moments. Written inside `play` it would have to be written twice. One block because the three fields only ever work together. **Its condition sees the card asking it** — `@self` is that card and `@target` whatever it was aimed at — which is how chess's pawn asks "did this move end on my eighth rank" |
| `receive` | `needs`: whether **this** card may be the destination of the card being played, with itself as `@self` and the arriving card as `@target` (see *Legality between two cards*). `action`: what happens when one lands, read the same way. Zones take the same block |
| `turn` | `action`: run at each round boundary while the card is on a grid and not ruined |
| `leaves` | `action`: run when this card **leaves play** — out of a `status: board` zone into one that is not. `into` names the zone it landed in, and is what tells death from exile from bounce (see *`leaves` — a card on its way out*) |
| `chosen` | `action`: run when somebody picks a card out of the offer **this** card opened with `show:`, with the pick as `@target` and this card as `@self`. The reverse of an `options:` offer, where the entry carries the rule and the asker is what it is about — here the entry is somebody else's property and carries nothing of ours |
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
`play.action`, and destroys the read page unless its actions moved it somewhere.

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
`count:<tag>` (cards **in play** with that tag), or `card:<key>` (instances of
that specific template in play — "does the player have the rusty key?").

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

It has to *look* like a subject — name a scope or a measuring fn — **or be a
compute the ability listed**, which is a number with a name and belongs on either
side. Anything else is a bare word: it fails the comparison closed rather than
quietly reading as a stat worth nothing, and the validator names it, since the
grammar alone cannot tell a bound name from a misspelling.

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
or a measuring fn (`sum:`, `max:`, `count:`, `card:`) — or name a compute the
ability listed. A bare word that is neither fails the comparison closed and is
reported as a typo, rather than quietly reading as an unknown stat worth
nothing.

`end_conditions` fire once per game (first match), wait for open overlays, and
run their `then` actions — usually `push_phase:` to an ending overlay.

**Scopes: which cards a subject is about.** The part after `@` is a *scope
expression*: `[<quant>.][<owner>.]<zone-or-tag>`, where the name is a zone key,
a tag, a movement pattern, or one of `self` / `target` / `event` / `all` /
`reach` / `owner_of.<scope>`.
Without any scope, a subject means **your own cards** — see *The player is a
card* below.

```
insight@player       the stat on cards carrying the "player" tag
hp@each.follower     every follower, individually
hp@random.follower   one follower, chosen by the seeded shuffle
hp@self              the acting card
hp@target            the cards the player chose for this card
hp@event             what an announcement is about, for a reaction to read
sum:defense@board    a stat summed over one zone
max:rank@tableau     the largest value in one zone
min:rank@tableau     the smallest — over the cards that carry the stat
count:farm@board     count, narrowed to a zone
count:king@enemy.reach  a king standing where an opponent could move — check
score@owner_of.target   the score of whoever owns the card the player chose
```

### `needs` and `where` — asked once, or asked of each

One vocabulary, two moments. **`needs` is asked once, before there is anything
to choose. `where` is asked once per candidate, and is the only one that can
tell them apart.**

| Written on | Asked | About |
|---|---|---|
| `play.needs` | once, before targeting opens | the card. It **cannot see targets** — none have been chosen yet |
| `challenge.needs` | once, when `resolve_challenge` runs | the card and the targets it already has |
| `receive.needs` | once per candidate destination | that destination as `@self`, the arriving card as `@target` |
| `target.where` | once per candidate | the candidate, as `@target` |
| `chosen.where` | once per revealed card | that card |
| a move rule's `needs` | once for the rule | the piece |
| a move rule's `where` | once per candidate square | that square, as `@target` **and** as the anchor for any pattern inside it |

The rule underneath: **`needs` asks about the thing it is written on; `where`
asks about each option that thing is offering.** `receive.needs` looks like the
exception and is not — it is written on the destination, the destination is what
it asks about, and it runs again for each one because each one is a different
destination answering for itself.

**Why both words exist.** They are two moments, and neither can do the other's
work. A card has to be judged playable before the player commits to anything —
that is what dims it in the hand — and at that moment there are no candidates,
so `needs` is asked with nothing chosen. Once targeting opens the question
changes from *may this card be played* to *may it be played at that*, which has
a different answer for every square on the board and cannot be asked once. One
word covering both would have to be re-asked per candidate, which makes the
first question unanswerable, or asked once, which makes the second one a lie.

**A move rule is the only block carrying both**, because it is the only one that
does both jobs: decide whether the rule applies at all, then filter the squares
it produced.

```json
{ "patterns": ["two_right"], "fill": "empty",
  "needs": ["moves_made@self == 0"],
  "where": ["tagged:rook@one_right >= 1", "moves_made@one_right == 0"] }
```

*Has this king moved?* is one answer for the whole rule, and asking it per
square would get the same answer every time. *Is there an unmoved rook beyond
**this** square?* has no answer until there is a square, so it cannot be asked
in `needs`. `fill` sits between the two — also per square, but it knows only
what is standing there, and `where` is for everything else about it.

Everywhere else the format offers one word and not the other, and **which one
you are given says what is being asked**. A `play` block has no `where` because
nothing has been chosen yet. A `target` block has no `needs` because the card's
own gate has already happened.

**The escape hatch on `needs`.** A `needs`-gated card becomes playable anyway
when nothing else the phase would let you play is playable, so a mandatory play
can never soft-lock a hand. `cost` is checked *before* the hatch, so an
unaffordable card is never opened by it — only a gated one. A zone tagged
`optional` opts out: chess's four castling cards are gated most of the game, and
"nothing else here is playable" is their ordinary state rather than a trap.

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

A **tag** scope means cards *in play* — zones whose `status` is `board` —
exactly like `count:<tag>`. A card in hand is not in play; name the zone
(`@hand`) when that is what you want. Zone and tag names may never collide, and
the validator refuses a file where they do.

### What counts as in play

A pile of rules mean *in play* and none of them say which zones those are:
`count:<tag>`, `card:<key>`, `tagged:`, a bare tag scope, `sacrifice:<tag>` as a
cost, a card's `turn` block acting by itself, and a reaction answered
`"from": "board"`. The zone answers for all of them at once, with `status`:

| `status` | Means |
|---|---|
| `board` | **In play.** Every rule above means these cards. A `grid` is this without saying so |
| `offer` | A card lent to a question — nobody's while it is there, and gone when the question is answered. An `options` zone is this without saying so |
| `supply` | **Stock.** A shop's shelves, a bank of tokens, the box a game deals from: visible and countable, but nobody's and not in play |
| `exile` | Everything else, and the default: a deck, a discard, a bag, a trash |

**Exile is not oblivion.** Naming a zone has always reached inside it, so
`@trash` finds what is there and `count:cursed@mine.trash` counts it. What an
exiled card is not is counted by a rule that *didn't* name the zone, sacrificed,
or asked to act. That is how MTG's exile and Slay the Spire's trash are said: a
place a rule can point at and nothing else can reach.

**Why it is not just the layout.** It was, and the layout was `grid`, which held
until a game laid its ongoing effects in a face-up row in front of one player.
That row is in play by every rule of the game and a `hand` by every rule of the
engine, so a chip on it was not counted, could not be sacrificed, was never asked
to act, and no reaction could answer from it. A row that is in play says so:

```json
{ "key": "ongoing", "label": "In play", "layout": "row",
  "status": "board", "copies": "per_seat" }
```

Note the default is `exile`, not `board`: a zone is inert until it says
otherwise, so a forgotten word leaves a card unreachable rather than quietly
countable.

### `supply` — a stock the engine counts for you

The word a `supply` adds to "not in play" is **interchangeable**. Sixty-four
identical gems differ in nothing a rule may ask about, so the engine keeps one of
each kind as a real card and a number for the rest:

```json
{ "key": "bank", "layout": "grid", "grid": [3, 6], "status": "supply",
  "use": "abilities", "applies": ["for_sale"],
  "contents": ["gem_1:64", "gem_2:20", "wound:24"] }
```

That declares 108 cards and creates three, each stamped with a `stock` — a stat
the engine writes, which you never declare and may read and spend like any other.
Nothing else in the game file knows, and nothing else has to.

**It is safe because nothing may point at one.** A supply's cards are out of every
candidate list, exactly as `immutable` scenery is — and it is that nobody can
point which lets one card stand for sixty-four. A rule able to tell two gems
apart would find out there is only one.

**Buying is a cost and a fill, not a draw:**

```json
{ "key": "buy", "cost": { "coin@mine.player": "price@self", "stock@self": 1 },
  "action": ["fill:mine.discard:@self:1"] }
```

**A cost amount may be measured rather than typed.** A shared buy cannot write a
number — the ability lives on the tag the zone hands out, and every shelf wants a
different one — so it reads the price off the card being bought. Any subject
works, and so does a `compute` the ability bound before it ran, which is where a
price with something taken off it is said: a compute has the arithmetic a cost
has no room for. A *quoted* number (`"3"`) is refused rather than read, since it
measures nothing.

The shelf card never moves. `stock@self` running out is what makes a sold-out
stack refuse, with no rule written for it. Drawing *from* a supply is refused by
the validator, since it would move the one card standing for the whole stock —
and so are `reach` and `refill_from`, because a stock has no order to have a top
or to run out in. Filling a supply raises the number instead of minting a card,
so `contents`, `fill:` and a rule returning something to the box all land right
without knowing.

**An empty shelf keeps its card.** That is what lets a game count how many stacks
have run out — `count:spent@bank` where `spent` is a computed tag on `stock` —
which a heap of real cards could never answer, because an absence carries no tag.

Two games built this by hand before it existed: Splendor's token piles and Puzzle
Strike's bank are the same counter card tagged `immutable`, with the take written
as its `activate`. If you find yourself writing that, this is the word for it.

### `<zone>.<tag>` — one place, one kind

A zone key may be narrowed by a tag written after it. It reads left to right,
widest first — whose, where, which:

```
count:purple@enemy.hand    the purples in one opponent's hand
sum:value@mine.hand.gem    what your gems in hand are worth
destroy:mine.discard.wound every wound in your own discard pile
```

This is the search a bare tag refuses to do. A bare `count:gem` means the board,
on purpose, so that most rules cannot read a hand they are not allowed to see;
naming the zone is how a rule says it means to. It is also the pair a **target
spec has always been able to write** — `"tags"` beside `"zones"` in the same
block — so this is one question finally having one spelling rather than two.

**Both halves must exist.** A zone that is not there answers nothing rather than
falling back to the tag alone: a typo must not quietly widen a search. The
validator names whichever half is wrong.

### `@everywhere` — every card, hands and decks included

That board-only default is deliberate: most rules must not read a hand they
cannot see, and a bare tag keeps that promise. When a rule genuinely does want a
tag counted *wherever the card sits* — in play, in a hand, or still in the
deck — and cannot name every zone one at a time, `@everywhere` is the opt-in:

```
count:gem@everywhere       every gem there is, in play or in hand or in the bag
count:gem@mine.everywhere  the same, narrowed to the seat whose turn it is
sum:value@enemy.everywhere an opponent's total, wherever they are holding it
```

It is the one search naming a single zone cannot do, because a card may be in
any of several. Naming a zone still reaches a hand, a pile or a deck as it always
has (`count:gem@hand`, `sum:value@mine.discard`) — `@everywhere` is only for
when you mean *all of them at once*. The owner word narrows it like anywhere
else, so a card in a shared deck belongs to nobody and drops out of both `mine`
and `enemy`. (Distinct from `@all`, which takes every entity of every kind —
zones and squares included — and is almost never what a rule wants.)

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

**Zones that belong to a seat** say `"copies": "per_seat"`, and are then created once
per seat with one rect each:

```json
{ "key": "hand",  "layout": "row", "visibility": "owner", "copies": "per_seat",
  "pos": [[0.02, 0.75, 0.78, 0.87], [0.02, 0.88, 0.78, 0.99]] },
{ "key": "arena", "layout": "grid", "copies": "per_seat", "grid": [5, 1],
  "pos": [[0.02, 0.05, 0.60, 0.30], [0.02, 0.32, 0.60, 0.57]] }
```

An unqualified zone key means **the active seat's** copy — `move_to:arena`
puts the card in your own arena, `draw_from:deck:hand:1` deals into your own
hand. Say `enemy.arena` for the other. A per-seat zone also receives its own
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

**`not_self`** is the same yes/no shape asked about identity: *is nothing in
this scope the card doing the asking*. It takes no argument, which no other
measuring fn does — there is nothing to name, since what it compares against is
the card whose condition this is:

```json
"target": { "zones": ["hand"], "tags": ["fire"],
            "where": ["not_self@target >= 1"] }
```

That is "a **different** Fire card in your hand", which nothing else in the
vocabulary can say: every other question here is about a property, and *which
one you are* is not one. With nobody asking — an ability the engine ran with no
card aimed at anything — every candidate is somebody else and the answer is yes.

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

### Which end of a deck a card lands on

Every zone is a list, and the **top of a pile is the end of it**: a draw takes
from there, and an arrival lands there. So "put it on top of your deck" is what
every move already does, and needs saying only when you want to be sure:

```json
"play": { "action": ["move_target_to:mine.bag:top"] }
```

The word worth knowing is the other one. `bottom` **buries** a card, and nothing
else can:

```
move:mine.hand:mine.bag:bottom          the whole hand, underneath
move_target_to:enemy.bag:bottom         the one they chose, out of their way
draw_from:mine.bag:mine.bag:1:bottom    the top card of a deck, put under it
```

It is the last argument of `move`, `move_target_to`, `add_to`, `draw_from` and
`return_to` — every op that names a destination. It means something in any zone,
since every zone is a list, but it only *reads* as anything in a deck, which is
where somebody is about to draw.

### `origin` — back where it came from

Every destination names one place, which is wrong for a set of cards gathered
from all over. A combat pulls a unit out of one of ten zones, and the survivor
has to return to the one *it* left, not to the one its neighbour left. The
engine records where each card was immediately before its last move, and
`origin` reads it back:

```json
"action": ["return_to:duel:origin"]
```

One line, and each card goes somewhere different. That is the whole of it —
`origin` is not a place, it is a different place per card, which is why nothing
else could say this.

It is a **destination and never a source**. `return_to:origin:hand` is refused,
because there is no one zone to drain.

**On a grid it is the square, not the zone.** A row of five patrol posts that
sends three cards into a fight gets each of them back into its own post; a post
somebody else has taken since is not one to evict them from, so that card comes
home to the zone the ordinary way.

```
move_to:origin                   the acting card, home
move_target_to:origin            the ones the player chose, each to its own
move:duel:origin                 empty a zone, sending everything back
return_to:duel:origin            the same, said the other way round
```

Three things worth knowing:

- It means **immediately before**, not "where this lives". A card that was
  played from a hand, sent to a duel and bounced remembers the duel. For "where
  this lives", give the card's tag a `zone` and write `move_to` with nothing
  after it.
- A card that has **never moved** — dealt by `setup`, and still where it was
  dealt — has no origin, and stays where it is.
- Going home **from home** is not a move, so a card already standing in its
  origin is left alone rather than pulled out and put back.

If the origin is a bounded zone that has since filled up, the move refuses like
any other and the card stays where it is. A duel zone big enough for what it
holds is the answer; the engine will not evict somebody to make room.

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

### `across` and `beside` — pointing at the other cards

A pattern is the only way to say **"not me, over there"**. No scope means it: a
zone name includes the card asking, and `mine`/`enemy` answer for the *active
seat*, not for whoever is speaking. So a rule about the card opposite, or the
card next along, is a pattern used as a scope.

Two that earn their keep, both one line:

```json
"patterns": {
  "across": { "vectors": [[0, 1], [0, -1]], "class": ["step"] },
  "beside": { "vectors": [[1, 0], [-1, 0]], "class": ["step"] }
}
```

**`across` in a `grid: [1, 2]`** is "the other card here", and that is what makes
a fight writable. Two cards step into a duel zone, a phase or an action list
walks it, and one ability serves both sides:

```json
{ "key": "aim", "action": ["stat_gain:incoming@across:sum:power@self"] }
```

Each card in turn deals its own damage to whoever is opposite. Nothing says who
is fighting whom, and nothing needs to: the geometry says it.

**`beside` in a `grid: [5, 1]`** is "the next post along", which is how a row of
five patrol slots answers *sparkshot* — 1 damage to a patroller adjacent to the
one struck:

```json
{ "key": "sparked", "when": ["count:marked@beside >= 1"],
  "action": ["stat_damage:hp@self:1"] }
```

Read it from the neighbour's side: each card in the row asks whether the marked
one is next to it. **A gap breaks adjacency for free** — the pattern names the
immediate squares and nothing beyond, so an empty post between two cards makes
them not adjacent, which is usually exactly what a rulebook means.

**What a pattern anchors on.** The acting card's *square* — so it names nothing
for a card that is not standing on one — or, inside a target's `where`, the
candidate square being considered. Inside `activate_zone` the context is rebuilt
for each card as the walk reaches it, which is why one ability written once
speaks for every card in the zone.

**`y` is forward for whoever owns the anchor**, so a one-way pattern reads the
same from both sides of a board. `across` and `beside` list both directions
precisely because they are *not* one-way: they should mean the same thing to
either player.

Three things to know before reaching for one:

- **A pattern needs squares**, which means `layout: "grid"`. A `row` has none, so
  a row of cards has no neighbours. If you want adjacency, make it a grid one
  row tall.
- **Range is 1 unless you say otherwise**, and a longer ray stops at the first
  occupied square — a rook takes the first piece on the file and nothing behind
  it. `phasing` is the piece that ignores that.
- **A card that leaves the grid stops having neighbours.** If a rule needs to
  know where something *was* after it has moved, ask the row before it goes and
  keep the answer as a stat.

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
| `fit` | zones | `card` (default) keeps card proportions inside whatever box the layout gives; `fill` takes the whole of it. Board tiles want it, and so does a button — a word you have to read is not a picture of a card, and a portrait button in a wide strip gives most of the strip back. On a `row` it also settles the shape: a filled row has no card ratio to lay out against, so it picks the column count whose cells come out closest to square |
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
"zones": [{ "key": "board", "layout": "grid", "use": "abilities", "grid": [8, 8], "tags": ["chessboard"] }]
```

**`color: false` is where two ideas became one.** A card's colour and "draw no
plate behind it" were a field and a tag deciding the same thing; now the plate
has a colour, or it has none.

**Badges draw wherever a card's face does** — a grid cell, a hand, the browse
view. A card in a hand shows its description *and* its numbers, with the numbers
on the title's line rather than on the bottom edge, because the prose is under
it.

**What a card wears is what a printed card wears.** A physical card says what it
gives in symbols and reads at arm's length; a paragraph of English in a
forty-pixel band does not. So the things a card *gives* are stats, badged, and
the exact words stay in the tooltip:

```json
"stats": [
  { "key": "act",  "icon": "arrow",  "tags": ["hidden"] },
  { "key": "draw", "icon": "card",   "tags": ["hidden"] },
  { "key": "react", "icon": "shield", "number": false, "tags": ["hidden"] }
],
"styles": { "chip": { "badges": ["act", "draw", "react"], "badge_zeros": false } },
"cards": [
  { "key": "roundhouse", "text": "Roundhouse", "tags": ["chip"],
    "tooltip": "+1 action, +2 chips",
    "card_stats": { "act": 1, "draw": 2 } }
]
```

`badge_zeros: false` is what keeps a card that gives no buys from printing a
zero, and a stat a card never declares is simply absent — an absent stat draws
nothing, which is what makes one style serve forty different chips.

**`number: false` is a badge that is the shape alone.** Some facts have no
quantity: a banner meaning *this is an attack*, a shield meaning *this has a
reaction half*. The 1 that would carry it is noise. It is the mirror of
`icon: "none"`, which is a number with no shape, and it sits on the stat for the
same reason — the badge and the HUD row draw through the same call and must not
disagree.

The shapes are a closed set, so one nobody draws is refused rather than quietly
becoming a diamond: `coin`, `heart`, `shield`, `banner`, `leaf`, `blade`,
`arrow`, `card`, `fist`, `orb`, `pot`, `diamond`, `none`. They are named by shape and
not by meaning, because what a game calls its currency is its own business.

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

### `merge` — what an ability says to the others on its card

Adding is right far more often than not, but not always. A shop is the case that
wants substituting back: a chip lying in the bank is *merchandise*, and its own
upkeep ability paying out on a click is money from the shop window. So an
ability may say what it does when it meets the others:

| `merge` | |
|---|---|
| `both` | the default, and what every ability said before this existed: added to whatever else the card can do, and the player is asked which |
| `this` | mine alone — everything else the card offers goes quiet |
| `other` | the understudy: mine only when the card offers nothing else |

```json
"tags": {
  "for_sale": { "abilities": [
    { "key": "buy", "text": "Buy it", "merge": "this",
      "cost": { "money": 3 }, "action": ["gain:widget:1"] }] }
},
"zones": [{ "key": "shop", "layout": "grid", "use": "abilities", "applies": ["for_sale"] }]
```

**The word is on the ability, not on the zone that granted it.** The zone's whole
say is naming the tag in `applies`; what applying it *means* belongs to the tag,
and a card's own tag needs the same word — "this card's abilities do not work" is
the same conflict with no zone anywhere in it.

**It is settled before anything asks what is usable**, so it says what a card *is*
where it lies rather than what it can afford this instant: merchandise stays
merchandise to a player with no money, instead of turning back into a card with a
spare ability going free.

Two abilities both claiming `this` is a contradiction — each wants the other
silent — and the validator refuses it rather than picking a winner.

### `when` — an ability with an if in it

`phases` and `cost` say whether a **player** may use an ability. `when` says
whether the ability **happens at all**, and it is a list of ordinary conditions:

```json
{ "key": "spill", "text": "Overwhelm",
  "when": ["attacking@self >= 1", "count:unit@across == 0"],
  "action": ["stat_set:spill@self:sum:power@self"] }
```

The difference matters because a phase walking a zone (`activate_zone`) is
*ungated* — it has already decided it is time — but it still honours `when`.
Permission is about the player; a `when` is part of the rule. "Damage past the
blocker hits the Nexus" is a sentence with an *if* in it, and without somewhere
to write that if, the only spelling left is multiplying by a stat that is 0 or 1:

```
before  stat_damage:spill@self:sum:health@across:x:count:overkilled@across:x:sum:attacking@self
after   when   ["attacking@self >= 1", "overkill >= 1"]
        action ["stat_gain:spill@self:overkill"]
```

Every rule about conditions holds here — a list means *and*, one comparison per
string, and an absent stat fails every comparison.

### Reactions — answering another player's action

A reaction is an ability with a subscription on the front: it names the thing it
answers, and it may be used **out of turn**. Three pieces make it work, and a
game that writes none of them plays exactly as it always did.

**1. A zone tagged `stack`, which is where announcements wait.**

```json
{ "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
```

Nothing on it is a game card. Each entry is a *record* of something announced,
and the card that announced it stays where it was — in the hand, on the table.
That is what keeps a counter from having to know the rules: it removes a record,
and nothing was ever moved.

**2. `emits`, which is a card saying its play is answerable.**

```json
"emits": { "play": "cast" }
```

The word is yours: `cast`, `summon`, `crash`, `buy`. Playing the card now puts a
record up under that verb instead of happening at once, and it happens only when
nobody answers. Written on a **tag** nearly always, because that is one line for
a whole game instead of one per card:

```json
"tags": { "spell": { "emits": { "play": "cast" } } }
```

`activate` is the other moment, and it is kept apart from `play` on purpose: a
spell cast from hand that resolves onto the board and is used from there is
answered as two different things, and a reaction watching for one must not catch
the other.

**3. `reactions`, a list shaped like `abilities`:**

```json
"reactions": [
  { "to": "cast", "text": "Counter it",
    "where": ["tagged:fire@event >= 1"],
    "when":  ["mana@mine.player >= 1"],
    "cost":  { "mana@mine.player": 1 },
    "action": ["counterspell"],
    "spent": "mine.graveyard" }
]
```

| Field | Says |
|---|---|
| `to` | the verb answered — the only required one |
| `where` | a condition about **the event**, read through `@event` |
| `when` | a condition about **the reactor**, asked as their seat |
| `from` | `hand` (played out of one), `board` (used where it lies), or **a zone by name** — a row of ongoing effects laid face up in front of a player is in play and is a *hand* as far as zone types go, so `"from": "ongoing"` is how it says so. Left out, the zone decides |
| `whose` | `enemy` (somebody else's announcement — the default), `mine` (your own), or `anyone`. See below |
| `forced` | `optional` (the player is asked, the default) or `mandatory` (it fires on its own) |
| `cost`, `target`, `action`, `text` | exactly as on an ability |
| `spent` | where the reacting card goes once its answer is over |

**The card acted on never names what answers it.** A fireball announces `cast`
carrying its own tags; a counter says which events it wants. That is the whole
shape, and it is why adding a counter to a game touches no other card.

#### What the player sees

Casting puts the record up and **priority** — who may act — moves to the seat
who can answer, *while the turn stays where it was*. They answer or pass; an
answer goes on the stack above what it answers, so it too can be answered.
Records resolve last-in-first-out, and when the stack empties priority goes
home. `counterspell`, written in a reaction's action, means the record it
answered never happens.

Nothing about this shows up in a game with no reactions to a verb. **A window
opens only when somebody could actually answer**, so a game that emits `cast`
with no counter in the box plays every spell the instant it is clicked.

**Ordinary play is locked while a window is open.** Priority was the whole of the
out-of-turn unlock, and without the lock it would unlock everything — the
reactor could empty their hand into your turn. A card playable out of turn says
so with `reactions` and no other way.

#### `whose` — whose announcement it answers

A shield answers the other player. Half of Magic does not: you put a spell on
the stack and then cast your own instant that copies it, and no opponent is
involved. Three readings, so a word, and the words are the ones a scope already
uses:

| `whose` | Answers |
|---|---|
| `enemy` | somebody else's announcement — **the default**, and what every reaction meant before the word existed |
| `mine` | your own, and only your own |
| `anyone` | either |

```json
"reactions": [
  { "to": "cast", "whose": "mine", "text": "Copy it",
    "action": ["copy:event:play"], "spent": "mine.graveyard" }
]
```

The seat that announced is asked **first** when `anyone` or `mine` applies,
because it is already holding priority — which is the order Magic uses and the
order the window already had.

**What keeps this from looping is not the seat check.** It is that one card
answers one record once: an answer is a *new* record with its own memory, so a
chain gets longer rather than going round. The one shape that could still run
away — a mandatory reaction on a card that never leaves the board, answering the
verb its own answers go up as — is bounded: the stack has a depth it will not
pass, and it says so in the log rather than hanging.

#### `spent` — where a card lands however it ends

```json
"play": { "action": ["stat_gain:damage@enemy.player:3"], "spent": "mine.graveyard" }
```

Resolved, or countered before it ever ran: either way the card goes there. An
MTG sorcery reaches the graveyard both ways and a deck-builder's chip the table
both ways, and neither the action list nor the card that countered it should be
the one that remembers. Opt-in — leave it out and the action list is answerable
for its own card, as before. It is run as the card's **owner**, so `mine` means
whose card it is and not whoever answered.

#### A phase announces itself

Everything else here is caused by somebody: a card is played, an ability is
used, an action emits. **A phase beginning and ending is caused by nobody**, so
it announced nothing — and *"at the end of your turn"*, which half the ongoing
effects in every deck-builder are written as, had nowhere to be said.

A phase says it the same way a card does, with the two moments it already has:

```json
{ "key": "cleanup", "type": "automatic",
  "emits": { "end": "turn_end" },
  "next": [{ "then": "handover", "ends_round": true }] }
```

| Moment | Fires |
|---|---|
| `begin` | every time the phase is entered, beside the `actions` it runs there |
| `end` | as it hands over, beside the hand it discards there |

**The subject is the player card of whoever the phase belongs to**, so a
reaction reads `@event` as whose turn it is, and `whose: "mine"` means what it
means everywhere else — which is how *"at the end of **your** turn"* is written:

```json
"reactions": [
  { "to": "turn_end", "whose": "mine", "forced": "mandatory", "from": "board",
    "action": ["draw_from:mine.bag:mine.hand:1"] }
]
```

Nothing is deferred: a phase has no action list waiting on the answer, so the
announcement goes up, the phase carries on, and whatever answers it resolves
beside it. That is how the sentence reads at a table — the turn is over, and
*then* the thing that triggers on it happens.

Filter A applies as it does everywhere: a game that writes `emits` on every
phase and holds no reaction to any of them pays exactly nothing for it.

#### `emit:` — announcing something that is not a card being played

A crash, a summon, a purchase:

```json
"action": ["emit:crash:move_target_to:enemy.pile"]
```

The verb is announced and **what follows it is the part that waits** — the rest
of the crash, held until the window closes unanswered. That is the only way to
defer half an action, because a ravel action list runs to completion; there is no
pausing one. Nothing answers that verb, or the game has no stack zone: it runs
now, so an emit costs a game without reactions exactly nothing.

The subject is the acting card, which carries the tags a reaction reads —
`"where": ["tagged:gem@event >= 1"]` — so the emitter names nobody who might
answer.

#### A mandatory reaction is how you ask somebody else a question

An action list cannot wait for another player. A reaction can, because the engine
already stopped to ask them:

```json
{ "to": "hex", "from": "board", "forced": "mandatory",
  "action": ["options:take_a_wound,discard_two"] }
```

Put that on a card in each seat's own board zone and *each opponent chooses* is
finally sayable: priority is theirs while the offer is open, so the choice and
its consequences are read as them. A mandatory reaction that has to be aimed is
a question after all, so it is offered rather than fired.

**A reaction may hand its player a whole phase**, with `push_phase`. Puzzle
Strike's Rigorous Training answers an opponent's buy by handing *you* a buy; the
game returns to where it was when the phase pops. Play inside an interjected
phase is not locked, because a phase pushed for a seat is a hand-over and playing
in it is the point.

#### What it will not do yet

- **Replacement effects** — "if it would die, exile it instead". Those do not use
  a stack; they rewrite the event before it happens.
- **Saying an event cannot be answered.** There is no way for a card to make its
  own announcements unanswerable.
- **Reactions from a tag or a zone.** `abilities` come from three places;
  `reactions` are the card's own only.

### `computes` — a number with a name

A value worked out where it is used, rather than stored on anything. Declared at
the top level, like a stat, because that is what it is minus the storing:

```json
"computes": [
  { "key": "overkill", "from": "0 - health@across",
    "tooltip": "How far past death the unit across this one was struck." }
]
```

An ability names the ones it wants, and they are worked out just before it is
judged and again before it runs:

```json
{ "key": "spill", "compute": ["overkill"],
  "when": ["overkill >= 1"], "action": ["stat_gain:spill@self:overkill"] }
```

The name then stands **as an amount** in that ability's actions and **as an
operand** in its `when`. Nowhere else: it is not a stat, nothing carries it, and
a compute sharing a stat's key is refused — one word cannot be two numbers.

`from` is `"<term>"`, or `"<term> <op> <term>"` with one of `+ - *` and spaces
around it. A term is a number or a subject. **One operator and no parentheses**,
so there is no precedence to remember. n-ary addition already has a spelling —
successive `stat_gain` lines onto one stat — so what was missing was subtraction
into a value slot, and that is exactly one operator.

A term may name another compute, and then the ability using it must list that
one **first**: they are worked out in the order the ability gives, each seeing
the ones before it. That is the whole of the dependency rule — there is no graph
to walk, and the validator says which line to move.

**What a compute is for is the name.** `sum:health@across` does not say why it
is being read; `overkill` does. Use one wherever an action list is passing a
number through a hidden stat that nothing else reads.

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

That last point is what makes an offer the right home for a **question asked
before the game starts**. A roster of ten characters wants half the screen for
one click and nothing at all for the rest of the game, and a zone declared for
it is a strip of board kept empty for an hour. Puzzle Strike claims the
`options` key, positions it across the middle, and asks each seat in turn:

```json
{ "key": "pick_1", "type": "player_input", "seat": "next",
  "label": "Choose your character",
  "actions": ["options:char_grave,char_jaina,…"],
  "ends_when": "picked@mine.player >= 1", "next": [{ "then": "pick_2" }] }
```

`ends_when` rather than `ends_after`, because **choosing out of an offer is
deliberately not a play** — the counter that bounds a hand belongs to the phase
under the overlay, and counting a choice would end that phase early. So the
chosen card sets a flag and the phase watches it.

### A question that may go unanswered

An offer the rules opened cannot normally be walked away from. Some questions
are genuinely optional — *you may discard a chip*, *look at their hand and take
one* — and those say so:

```json
"action": ["options:tr_tempo,tr_money:optional"]
```

The word puts a **No choice** button under the offer and changes nothing else.
Right-click and Escape did this all along, and neither is discoverable; on a
touch screen neither exists.

### Doing what another card does

`copy:` runs a card's action list without playing the card:

```json
"play": {
  "target": { "type": "card", "zones": ["hand", "discard"], "count": 1 },
  "action": ["copy:target:play:2", "destroy:target"]
}
```

That is *Play it twice, then trash it* — one line, and the line says it. What is
copied is the **effect**, not the card: nothing is created, nothing is spent, no
cost is paid, and the copied card does not move. A verb that duplicated the card
instead would leave a second one lying about for somebody to find.

`copy:<scope>:activate` runs the card's **abilities** instead of its play, which
is the same rule aimed at a card already on the board. Every one of them whose
`when` holds, in the order they are written — the same thing `activate_zone`
does, and for the same reason: *resolve that card* means the card, not the first
line of it. Running only the first ability dropped every rider with an if in it,
and dropped any question the card asks, since a card that asks keeps the asking
in a later ability so the offer opens after the rest has run.

An ability that is **not** part of being resolved has to say so, since the list
is flat and nothing else tells them apart. A `when` is how: Spellstorm's discard
effects are looking only when no card stands in a battle spot, which is every
moment except a resolution.

Two things it does not do, both on purpose:

- **It carries no targets.** Nobody aimed the copy, so a copied action that
  waits to be pointed at something finds nothing. A card meant to be copied
  should say what it acts on rather than wait to be told.
- **It does not change whose turn it is.** The copied card is the one acting, so
  its action reads `@self` as itself — but `mine` still means whoever is *up*.
  Copying an opponent's card gives *you* the benefit, which is what a card that
  copies wants and a trap for a card that meant to make them do something. For
  that, see *Making them choose* below.

A card that copies itself is a rule that runs away; it is bounded, stops, and
says so in the log.

### Reading somebody else's hand

`options:` deals *copies* of the cards it names. That is right for a menu and
wrong for a hand: reading an opponent's hand is about the cards they are
actually holding, and a copy of one is a different card that cannot then be
taken. `show:` borrows the real ones:

```json
"play": { "action": ["show:enemy.hand:optional"] },
"chosen": { "action": ["move_target_to:void"] }
```

Each borrowed card remembers where it came from, and everything still lying in
the offer when it closes goes home — including the pick, if the rule did not
move it. While it is in the offer it is face up and clickable whoever owns it,
because that is what an offer is for.

**Choosing one does not play it.** It is not yours to play. The asking card's
`chosen` block runs instead, with the pick as `@target` and the asker as
`@self`. That is the `options:` relationship said the other way round: there the
entry carries the rule and the asker is what it is about; here the entry is
somebody else's property and carries nothing of ours.

#### `chosen.where` — which of the revealed cards may be taken

An offer of somebody's hand is a whole hand, and a rule is usually about part of
one: *their largest gem*, *a blue-banner chip*, *a non-Puzzle chip*. The asking
card says which part, beside the block that says what happens:

```json
"play": { "action": ["show:enemy.hand:optional"] },
"chosen": {
  "where": ["tagged:gem@target >= 1", "sum:value@target >= max:value@options"],
  "action": ["move_target_to:void"]
}
```

Same word and same vocabulary as a target's `where`, asked the same way: the
candidate is `@target` and the asking card is `@self`. **The whole scope still
comes up** — revealing a hand is usually half the rule — and only the cards that
qualify can be clicked; the rest are shown and dimmed.

"Largest" is the second condition and it is worth reading twice: `@options` is
the offer itself, so the candidate is being compared with what it is lying
beside. Any question you can ask of a scope, you can ask here.

Two things fall out of it, both on purpose:

- **An offer where nothing qualifies does not open.** A question with no answer
  is a mandatory offer that never closes, so `show:` checks first and skips it
  entirely — the same rule as an empty hand being nothing to look at.
- **Only borrowed cards are asked.** An entry `options:` dealt is a line you
  wrote from your own list, and narrowing a list you wrote is writing a shorter
  list.

#### Only one of them: `random.`

The scope may say `random.`, and then one card comes up rather than the whole
hand — the same quantifier `move` and `destroy` take, meaning the same thing:

```json
"play": { "action": ["show:random.enemy.hand"] },
"chosen": { "action": ["stat_gain:seen@mine.player:1"] }
```

That is the whole of "reveal a card from their hand". The seeded generator picks
it, so a replay and a networked opponent see the same card.

#### Making *them* choose

Everything above shows their hand to **you**. The other sentence — *they* reveal
a card, of their choosing, to you — needs no new verb either. `set_priority`
makes the other seat the one who is up without the turn moving, and every scope
is relative to whoever is up, so from inside that window `mine.hand` is theirs:

```json
"play": { "action": ["set_priority:enemy.player", "show:mine.hand"] },
"chosen": { "action": ["move_target_to:enemy.table", "clear_priority"] }
```

Read it as the seat being asked and it says what it means: their hand comes up,
they pick, the pick goes to the other player's table — `enemy` is *you* now —
and priority goes home. Nothing about the turn moved, so whatever your card was
doing carries on afterwards.

The trap is that both readings look right from one side of the screen. Say the
scope out loud as **the seat who is up**, and check who that is at that line.

#### Nothing moves while an offer is open

Notice where the `clear_priority` above sits: in `chosen`, not beside the
`show:`. That is not a stylistic choice. **While an offer is open, the phase, the
seat and priority are frozen**, and the seven actions that would move one of them
are refused where they stand:

`next_phase` · `push_phase` · `pop_phase` · `set_active_seat` · `set_priority` ·
`clear_priority` · `each_seat`

An offer was asked in a phase, of a seat, holding priority. Move any of the three
and the answer lands somewhere the question never was — the cards the offer
borrowed have nowhere to come home to, and the player is left staring at a
chooser over a board that has moved on. This is not theoretical: it is how Puzzle
Strike's whole eighteen-chip bank came to be stranded in an overlay nobody could
reach.

So this does not work, and the validator says so before you run it:

```json
"play": { "action": ["show:bank:optional", "next_phase"] }
```

And this does, because `chosen` runs **after** the offer has closed:

```json
"play":   { "action": ["show:bank:optional"] },
"chosen": { "action": ["fill:mine.discard:@target:1", "next_phase"] }
```

The refusal is deliberate rather than the engine tidying up for you. A rule that
opens a question and then walks away from it has not decided what should happen
to the question, and closing it on the rule's behalf would withdraw an answer the
player was owed. Setting a seat or priority *before* the `show:` is fine — that
is the setup for the offer, not a change made underneath it.

### `leaves` — a card on its way out

**Most of a card game's triggers are about a card leaving**, and this is the
moment for them. It fires when a card goes out of a `status: board` zone into
one that is not, with `@self` as the departing card:

```json
"leaves": { "into": "discard", "action": ["stat_damage:hp@enemy.hero:1"] }
```

`into` names the zone it landed in, and **that is what tells one kind of leaving
from another**. The engine learns none of their names:

| The rulebook says | `into` |
|---|---|
| "when this dies" | the discard your units go to |
| "when this is exiled" / trashed | the trash you send them to |
| "when this is returned to your hand" | `hand` |
| "when this leaves play" | leave `into` out — any departure |

Moving between two board zones is not leaving anything, so a unit walking off a
patrol slot and into your army fires nothing.

**Write it on a tag and a whole class announces itself.** The other half of a
trigger is usually a card *watching*, and that is an ordinary reaction — so one
line makes every unit's death answerable and no unit knows it is being watched:

```json
"tags":  { "unit": { "leaves": { "into": "discard", "action": ["emit:died"] } } }
```

```json
"reactions": [{ "to": "died", "whose": "anyone", "forced": "mandatory", "from": "board",
                "action": ["stat_damage:hp@enemy.hero:1"] }]
```

A tag hands the block over whole, and a card writing its own takes none of the
tag's — the same rule `play` keeps, and for the same reason. So a card with its
own `leaves` that still wants the announcement writes `emit:` into its own list.

**`destroy:` does not fire it, and that is the point of the verb.** A destroyed
card lands in no zone, so there is no `into` to name, and its stats are cleared
along with it, so a rule asked to run afterwards would have nothing left to
read. The rule is one sentence: **if you want a removal answered, give it a
zone** — which is what naming one has always been for. `destroy:` stays the way
to take something off the table that nobody may ask about, which is what a token
vanishing and a swept husk both want.

### `pays_for` — one thing spent as another

A cost is one map of **what is owed**, always. That some other pool will settle
part of it is not a fact about the card — it is a fact about *that pool*, and it
is said once, on the stat:

```json
{ "key": "acts", "label": "Actions", "icon": "arrow",
  "pays_for": ["act_brown", "act_red", "act_blue", "act_purple"] }
```

A Puzzle Strike chip then costs one arrow of its own banner colour and says
nothing else:

```json
"play": { "phases": ["action"], "cost": { "act_red@mine.player": 1 } }
```

Three games want this and want it in three directions. A **wild** pays for any
colour (Splendor's gold, `pays_for` the five token stats). A **generic** demand
is paid by any colour (Magic: each coloured mana `pays_for: ["generic"]`, and
`generic` is a stat nobody ever holds). A **plain** resource pays for a
restricted one (Puzzle Strike, above). All three are the same sentence — *a unit
of this may be spent as that* — pointing different ways.

**Nothing on the card says which pool to drain, because the engine works it
out.** Deciding that is a matching, and the rule is two lines:

- the **most constrained demand first** — the one fewest pools can serve;
- and a demand's **own stat before any substitute** — a substitute is by
  definition the more useful of the two elsewhere.

Magic's *four generic and three red* is the case that needs both halves. Against
three red and four blue it is payable; spend the red on the generic first and it
is not. `red` is served by one pool and `generic` by several, so `red` settles
first, out of red. Puzzle Strike gets the behaviour that used to be written by
hand for free: a red arrow is spent before the plain one, because the plain one
can still pay for anything and the red one cannot.

**The validator refuses the shape the rule could get wrong.** The greedy is
exact as long as the substitution sets are *nested or disjoint* — one pool
strictly more general than another, or the two unrelated — which is every real
case. Two pools that share something while each paying for something the other
does not is the one shape where a greedy can refuse a payable cost, and it is
refused at load rather than discovered mid-game.

`each` is left alone: `{"hp@each.creature": 1}` asks that *every* one of them
pays, which is not a total and has nothing to substitute across.

### A card with nothing to run is not a move

A card whose `play` has no actions — or which has no `play` block at all —
cannot be played. Playing it would change nothing, and a card that looks live
and does nothing when clicked is worse than one that is plainly dead. Puzzle
Strike's Wound is the case: the printed chip says *this chip does nothing*, and
it says so in the file by having no `play`.

It matters more than it looks, because of the escape hatch: a needs-gated card
becomes playable when nothing else the phase would let you play is playable, so
that a mandatory play cannot soft-lock a hand. A card with no cost and no needs never reaches that
gate — it is simply always playable — and a hand of them is a row of buttons
that do nothing.

### `fan` — a stack you can read

A `pile` draws its top card, because that is what a stack of cards looks like.
Some stacks are meant to be read down their whole length — a solitaire tableau,
a Lost Cities expedition, a row of tricks won — and for those the pile says
which way it spreads:

```json
"styles": { "expedition": { "fit": "fill", "fan": "down" } },
"zones":  [{ "key": "red", "layout": "stack", "label": "Red", "tags": ["expedition"] }]
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
nineteen are the exceptions — the words the engine itself looks for:

| Tag | On | What it does |
|---|---|---|
| `generate_art` | card | with no asset, draws a shape derived from its key rather than a bare colour |
| `immutable` | card | scenery: nothing may target it and its template can never be edited |
| `no_undo` | card | playing or picking it clears the undo stack — the choice is final |
| `player` | card | this card is a seat. Stamped by the engine from the players section, not written by hand |
| `token` | card | vanishes when a hand is swept, instead of joining the discard |
| `optional` | zone | nothing here ever has to be played, so a gated card stays gated |
| `refill_when_empty` | zone | recreates its contents when the last card leaves |
| `shuffle` | zone | shuffled when its contents are created, and on every refill |
| `stack` | zone | announcements wait here to be answered — see *Reactions*. A game with no such zone has no response window |
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

### `buffs` — a tag that changes a number

Every continuous effect in every card game is the same sentence: *while this is
true, that number is different*. `buffs` is that sentence.

```json
"tags": {
  "elite":  { "buffs": { "atk": 1 } },
  "raging": { "buffs": { "atk": 3, "hp": 1 } }
}
```

A card wearing `elite` reads one higher, for as long as it wears it. **Nothing
is written to the card.** The shift is worked out on every read, so it arrives
and leaves with the tag, and the printed number underneath is never touched.

That is the whole reason for the word. Written as an action instead:

```json
"receive": ["stat_gain:atk@target:1"]
```

— and now something has to take it away again, on every path the card can
leave by. Codex kept a hidden `elited` stat for no other purpose and undid it in
ten places, because a unit can leave the elite post ten ways: promoted, killed,
bounced to hand, sent to the duel and back. Miss one and a unit keeps a bonus
for the rest of the game, silently, and the file that says `+1` is not the file
that is wrong.

**All three tag sources work**, which is what makes it worth having:

```
"tags": { "elite": ... }                  what a card IS      a printed keyword
"applies": ["raging"]  (on a zone)        where it STANDS     "+3 while in the arena"
"computed_tags": { "damaged": ... }       how it is DOING     "+2 while damaged"
```

The last is the single exception to the rule that a computed tag carries no
behaviour. A buff is not behaviour — it is a property of wearing the word, the
same as a style is — and there is no card for the behaviour version to belong
to. So a computed tag may write `buffs` and nothing else:

```json
"computed_tags": { "damaged": { "stat": "hp", "less_than_max": true } },
"tags":          { "damaged": { "buffs": { "atk": 2 } } }
```

**The ceiling rises with the value; the floor stays.** Both ends matter and they
want opposite treatment. A 1/1 handed +1 hp has to be able to reach 2, or the
clamp eats the buff the moment it is granted — and it has to be able to reach 0,
or two damage leaves it standing at the one point it was printed with. So:

```
a 1/1 in the arena         reads 2/2, and is not damaged
take 1                     reads 1/2, and is
leave the arena            reads 0/1 — the wound is what is left, and it is dead
```

Which is what the physical cards do. Damage comes off what the card *is*, and
when the buff goes what remains is the printed number with the hurt still on it.

**A write addresses the card's own number; a read and a clamp see the whole.**
What a buff adds is not the card's to set — it belongs to the tag and goes when
the tag does — so a hero levelled to `"stat_set:atk@self:2"` is printed at 2 and
still reads 3 in the elite post. A level-up cannot eat a bonus it has never
heard of.

Everything reads through it — every condition, `compute`, cost, amount and
badge — so a price with a tag on it is simply dearer and nothing in the cost
machinery learned a new word:

```json
"play": { "cost": { "gold@mine.player": "price@self" } }
```

Two limits. The amount is a **plain number**, never a subject: anything worked
out belongs in a `compute`. And a buff may not lead back to itself — a computed
tag shifting the very stat that decides whether it holds is refused, since
working out the shift would need to know its own answer. `"damaged units get +1
hp"` is a card that is damaged only while it is not.

### `verbs` and `adjusts` — a moment with a name, and something that answers it

`buffs` changes a number **on** a card. `adjusts` changes a number **done to**
one — how much this damage is, what this cost comes to. Both are reads, and
neither runs anything.

It needs a word first, and the word is the game's rather than the engine's.

**`stat_damage` is a mechanism, not a meaning.** Poison and a sword both take
`hp` and armour stops one of them. A plane losing altitude is neither. There is
nowhere in an action string for the difference to live — an action is a verb and
its arguments, and Ravel has no per-action metadata anywhere. So a game names
the moments it means:

```json
"verbs": [
  { "key": "damage", "does": "stat_damage", "tooltip": "Damage — armour stops some of it." },
  { "key": "poison", "does": "stat_damage", "tooltip": "Poison — armour does not." },
  { "key": "mend",   "does": "stat_gain" }
]
```

and writes them where it means them:

```json
"action": ["damage:hp@target:3"]
"action": ["poison:hp@target:1"]
```

Then a tag may answer one:

```json
"tags": {
  "armoured": {
    "tooltip": "Armour 1 — takes 1 less damage, but not from poison.",
    "adjusts": [{ "key": "armour", "verb": "damage", "stat": "hp", "covers": "self", "by": -1 }]
  }
}
```

**An aura may watch a declared verb and never an engine one.** That rule is the
whole point, and it does more than tidy the vocabulary — it makes being
interfered with **opt-in**. Codex's combat steps push `incoming`, `raw`, `back`
and `spill` about with plain `stat_damage`, and none of it can ever be
intercepted, because nothing is able to name it. A game says which of its
moments are moments by giving them words; everything else stays plumbing.

The fields:

- **`verb`** — a key from `verbs`.
- **`stat`** — which number. `damage` to `hp` is not `damage` to `gold`, and it
  is what keeps a shield off the plane losing altitude.
- **`covers`** — who it is about, as a scope read from the card holding it.
  `"self"` is a keyword; `"each.mine.unit"` is an anthem that covers a side.
- **`when`** — conditions, in the one grammar. `@self` holds the aura, `@target`
  is being acted on, and **`@source`** is doing it:

```json
{ "key": "ward", "verb": "damage", "stat": "hp", "covers": "self", "by": -2,
  "when": ["tagged:witch@source >= 1"] }
```

- **`by`** — how much, in the ordinary amount grammar.

Four rules keep it predictable:

```
it adjusts the number the action says     "3 damage" less one is 2
several sum, in a fixed order              armour and an anthem take two off
it may not change the sign                 three less five is none, never a heal of two
it is asked before the change              "1 less while damaged" reads the hp not yet taken
```

And an aura only works while its card is in play, which is what a tag scope has
always meant. A shield in a deck shields nothing.

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

**Every action the engine runs is in the table below** — all forty-five of them,
with nothing kept back for a later section. The test suite holds it that way: a
handler the engine gains and this table does not describe fails the build, for
the same reason SCHEMA.json is held to the same list. A verb you cannot find
here is a verb the engine does not have.

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
| `fill:zone:card:n` | Create n instances of card in zone. The card slot takes a template key, or `@<scope>` to read the template off a card that is already lying somewhere — `fill:mine.discard:@self:1` is a shop selling what it is. Not a clone: what arrives is fresh off the template, with the stats the game declared |
| `shuffle:zone` | Shuffle |
| `draw_from:from:to:n` | Move n cards off the top |
| `return_to:from:to` | Move all cards (bounded; safe with refilling zones) |
| `move_to:zone` | Move the acting card (uses a slot target when given); without a zone, its home tag decides |
| `move_to:target` | Move the acting card into the **chosen target's** zone — how one card offers two destinations ("advance the expedition, or discard it") |
| `move_to:target:<what>` | …and say what becomes of a piece already standing there: `destroy`, or the zone it goes to (a captured-pieces tray). Left out, an occupied square refuses the move. This is capture; with it, aiming at a *piece* means taking its square rather than joining its zone |
| `gain:card:n` | Create n instances of a card in its home zone (or the hand) |
| `add_to:zone` | Move the acting card (overlay picks) |
| `move_target_to:zone` | Move each targeted card |
| `…:top` / `…:bottom` | **Which end of the destination a card lands on**, as a last argument to `move`, `move_target_to`, `add_to`, `draw_from` and `return_to`. Every zone is a list and the top of a pile is the end of it, so an arrival lands on top unless told otherwise — `bottom` is the word that buries a card, and `draw_from:bag:bag:1:bottom` puts the top card of a deck underneath it |
| `place:<who>:<where>` | Put every card the scope names on a square of the only board. `<where>` is a square by name (`"g1"`) or a **pattern pointing at one from the acting card** (`"one_left"`) — the second is how a rule works for both sides of a board, since a named square is only ever one player's. Refuses an occupied square |
| `stat_gain:<subject>:n` / `stat_damage:<subject>:n` | Change the current value, held between its floor and its ceiling, logged, and floated on the card. Two words for one arithmetic, because "damage 2" and "gain −2" read differently to everybody but the engine. The subject may carry a scope: `hp@target`, `hp@each.follower`, `hp@random.beast` |
| `stat_boost:<subject>:n` | Move the **ceiling** of a stat that has one (`card_stats` written `{ "value": n, "max": n }`). Lowering it under the number standing there brings the current down with it; nothing else does |
| `stat_set:<subject>:n` | Set directly, past every bound, silently. A dev and authoring tool — how a phase resets a counter, not how a rule changes a number |
| `move:<scope>:<zone>` | Move every card the scope names into that zone. The scope-first sibling of the two above, for a set nobody picked: written twice with opposite owner words (`move:mine.battle:mine.bench`, then `enemy`) it covers both seats whoever is up |
| `set_active_seat:<scope>` | Whoever the scope names becomes the seat whose turn it is — the trick winner leading, the attack token holder acting first. Every other way of naming a seat is settled before the game starts, so this is the only one that reads off what just happened. Two seats is refused, none does nothing, and the handover ends the undo history |
| `set_owner:<scope>:<who>` | Hand those cards to a seat, to the one that is up (`mine`), or to nobody (`none`). Whose a card is is settled when it is dealt and stays settled, so this is the only thing that changes it: mind control, and a pile that disowns whatever lands in it |
| `activate_zone:<zone>[:<order>[:<step>]]` | Every card lying there does what it does — how a *phase* makes cards act instead of waiting for a click. Put the rule on a card, the card in a hidden zone, and have the phase say so. **Ungated** for permission — the phase has already decided it is time — but an ability's own `when` is honoured, because that is the rule and not the permission. The order is the game's to state — naming none acts in the order the cards are in, `by_column` reads a board left to right; any other word is refused. A **step** names abilities: give one and only the abilities keyed to that word run, so a phase can walk the same zone several times and order things *between* cards — every unit works out what it is dealt, then every keyword that reduces a number reduces it, then every unit takes it. Naming none runs every ability |
| `ready:<scope>` | Un-spend those cards, the counterpart to the `exhaust` cost. A phase's own actions run when it begins, so this is how a game says *when* being spent wears off rather than taking the engine's round boundary for it |
| `attach_to_target` | Attach the acting card under the first target |
| `options:<source>[:optional]` | Offer a choice and open it. `<source>` is a zone, whose cards name the choices, or a comma-separated list of card keys. The chosen card is played with **the asking card as its target**. `optional` puts a No choice button on the offer |
| `show:<scope>[:optional]` | Put the **real** cards a scope names into the offer, face up, and open it — how one player reads another's hand. They go home when it closes. Choosing one runs the asking card's `chosen` block with the pick as `@target`, rather than playing it. The scope may say `random.`, and then one of them comes up rather than all: `show:random.enemy.hand` is the whole of "reveal a card from their hand" |
| `transform:<scope>:<card>` | Replace each card in scope with a new one of that key, standing on the same square, in the same zone, belonging to the same player. Everything else is the new card's own |
| `copy:<scope>[:play\|activate[:<n>]]` | Every card the scope names **does what it does**, n times over, without being played and without moving. The card is not copied, its effects are: nothing is created, nothing is spent, no cost is paid, and it stays where it lies — which is what "play it twice, then trash it" means and what duplicating the card would get wrong. The moment picks which list to run, `play` (the default) or `activate` (every ability whose `when` holds, in order). The copied card is the one acting, so its action reads `@self` as itself — but `mine` still means whoever is *up*, so copying somebody else's card benefits the copier. Targets are not carried over: nobody aimed the copy |
| `resolve_challenge` | Ask the card's `challenge`: run its `pass` or its `fail`. The condition is asked with the acting card and its targets in hand, so it may say `@self` and `@target` |
| `effect:name` | Play a named visual effect on the acting card (headless: skipped) |
| `reveal:card` | Conjure the card into the page overlay; playing it there continues the story |
| `reveal_top:zone` | Turn over a zone's top card into the page overlay (shuffle secrets) |
| `next_phase` / `push_phase:key` / `pop_phase` | Phase control |
| `destroy:<scope>[:<n>]` / `destroy_self` | Remove cards from play entirely. A bare zone key is a scope, so `destroy:hand` is unchanged; `destroy:each.enemy.creature` is a board wipe that spares your own. A count takes that many rather than all of them, in the ordinary amount grammar (`destroy:mine.pile:sum:crashed@enemy.player`), and takes the earliest unless the scope says `random.`. **Nothing is triggered by it**: a destroyed card lands in no zone, so there is no `into` for a `leaves` to name, and its stats are cleared, so a rule asked to run afterwards has nothing left to read. That is what the verb is *for* — removing something nobody may ask about. If you want a removal answered, give it a zone and `move` it there |
| `emit:<verb>[:<action>]` | Announce that something happened, so anybody holding a reaction to that verb may answer it first. What follows the verb is the part that **waits**. Nothing answers it, or the game has no `stack` zone: it runs now. See *Reactions* |
| `counterspell` | Written in a reaction: the event it answers does not happen. **It names no zone** — the stack holds records, not cards, so nothing moved and there is nothing to put back |
| `set_priority:<scope>` / `clear_priority` | Whoever the scope names may act right now, without the turn moving. The response window does this for itself; write it only for an out-of-turn moment of your own |
| `load_game:file` | Switch games (menu items, endings). `file` must be a bare `name.json` — no path, no `..` — and is refused otherwise |
| `open_game` | Ask the player for a game file of *theirs* and play it — a file picker in the browser, a dropped file on the desktop. Nothing is uploaded and nothing is installed: the engine already runs a game handed to it as text, which is how a network invite carries its rules to somebody who has never seen the file, so this is only the asking. A build with no way to ask says nothing and does nothing |
| `each_seat:<action>` | Run one action once per seat, in seat order, with each seat up in turn — so `mine` does the work and a four-seat deal is one line rather than four. Whoever was up is up again when it returns, and no handover happens: the undo history is not cleared, because dealing to everybody is not anybody's turn. See *Every seat, once* |
| `net_invite` / `net_join` / `net_panel` / `net_seat:<who>` / `net_offline` | The networking layer's own UI, offered as actions so a game may put "Host" and "Join" on its own menu cards. The engine knows the words; the behaviour arrives only if the net module is loaded, and a game without one is unaffected. See *Playing over a network* |
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

Reserved words that a zone or tag may never be named: `self`, `all`,
`everywhere`, `reach` and `owner_of` (the engine answers for them in scopes),
plus the quantifiers `any` / `each` / `random` and the owner words `mine` /
`enemy` / `anyone`, which are read as prefixes in a scope expression rather than
as names. `player` is deliberately *not* reserved — it is an ordinary tag you
put on a card.
