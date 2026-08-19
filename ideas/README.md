# Ravel — Idea Workstreams

`IDEAS.md` is the raw list. These files are the worked-through versions: what
each idea actually requires, where it lands in the code, what order to build it
in, and what to refuse to build.

**Start with [DONE.md](DONE.md).** It records everything already built — what it
does, which files it lives in, the decisions that are load-bearing and the traps
that cost real time — so that finding out what exists does not mean reading the
whole engine. The design documents for shipped ideas have been folded into it
and deleted; their content is all there, minus the parts that were speculation
about how it might go.

| # | Idea | Size | State |
|---|---|---|---|
| [DONE](DONE.md) | **Everything already built** | — | stats on cards · seats and hot-seat · the engine's own RNG · procedural art · Lost Cities · networked play · stacks and mixins · chess · named and remote assets · the inspector |
| [01](01-boardgames.md) | Any board game as JSON | large, staged | **Lost Cities and chess shipped.** Left: checkers' jumped square, Klondike, triggers |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | medium | not started — unblocked, and smaller than written |
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | small | **closed** — named assets, remote pictures, and a generated placeholder when one cannot be produced. Art stays in git: that gap was a misunderstanding, and remote art was the real requirement |
| [06](06-schema-and-types.md) | Saying what things are | medium | gap 1 **surveyed and refused** (2026-08-13, `85e51eb`) — the matrix of what a zone's `type` bundles is worth reading even so. Left: lists everywhere, then guards at the door |
| [07](07-presentation.md) | Presentation and its gestures | medium-large | **closed** — text, contrast, board chrome, zone ratios, clicking the deck, the multi-ability chooser, and an ending that knows who won. A win is the reserved `won` stat on a seat, and the banner and the numbers under it are both answered for the seat watching |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | medium | **chess plays** — castling, check, promotion and en passant included. `patterns` (relative and absolute), capture, ownership, patterns as scopes, `@reach` and `where`. Left: the scope anchor word, and checkmate with the legality filter |
| [09](09-composition.md) | One game out of several files | small + one trap | not started — `include`, and a base file of shared patterns |
| [10](10-schema-document.md) | A game file that describes itself | medium | **shipped** — `SCHEMA.json`, held to the engine both ways by a test. Nine findings; two were bugs and are fixed |
| [11](11-styles-as-tags.md) | Styles are tags too | medium-large | **shipped** — `styles`, claimed by tagging one. Absorbed `color`, `fit`, `ratio`, `checker`, `paint` and three tags; `color: false` replaced `transparent_background`. A style that is also a computed tag makes a look follow the numbers |
| [12](12-card-moments.md) | A card is a list of moments | large, mostly migration | **shipped** — `play` / `activate` / `challenge` / `receive` / `turn` / `start`. The `activate_` prefix, `requires`, `accepts` and every `on_` name are gone, and `pick` turned out to be `play` |
| [13](13-one-name-one-thing.md) | One name, one thing | small check | **shipped**, and narrower: a key is unique within its kind, and the *scope* namespace (patterns, zones, tags) may not collide. Everything else may repeat — two repeats are load-bearing |
| [15](15-many-on-one-square.md) | Several cards on one square | answered: *not yet* | **refused for now.** Three questions in one: cards on a card is `attach_to_target`, **built and unused**; a count on a square is a slot stat, half built; an ordered run is a zone with `fan`, shipped. What is left over — identity *and* order *and* a square — no target game asks for |
| [14](14-kinds-and-placements.md) | Six kinds, thirty-two pieces | medium | **shipped** — chess is 13 cards and 279 lines, and its generator is deleted. Ownership is placement state, squares are named (`"at": ["a1", "h1"]`), and a named asset takes one picture per player. Dynamic styles turned out to be the wrong route, and the doc says why |
| [16](16-the-player-at-this-screen.md) | The player at this screen | small + three afternoons | **gap 1 shipped** (`fb3d704`) — `zones.viewer` is the seat in front of the screen, and a networked opponent's hand now stays hidden while they think. Left: a name, a place to set it, and debug mode as an announced thing |
| [17](17-conditions-as-expressions.md) | A condition is one string | large | not started — [10](10-schema-document.md)'s finding 5 from the inside. The operands exist; what is new is the infix spelling, and whether arithmetic comes with it |
| [18](18-legends-of-runeterra.md) | Legends of Runeterra | large, document first | **stage 1 and milestone 1 shipped** — it plays: draw, mana, the pass, the attack token, attackers and blockers as lane placement, the strike, the Nexus, a winner. Tough and Overwhelm came with it, as arithmetic. Left: spells, the response stack, the rest of the keywords, champions |
| [19](19-mage-knight.md) | Mage Knight | large, research first | **researched, and ranked last of the three deckbuilders.** Two compounding engine gaps — hex geometry, and a map whose *extent* grows — plus a change to the arithmetic grammar. Buildable only as a stripped prototype, and the cuts are dishonest ones |
| [20](20-puzzle-strike.md) | Puzzle Strike | medium | **researched — buildable now as a 2-player game, mostly content.** One real gap (`flow.reachable` refuses a card played out of turn) and it is cleanly cuttable. Found that `refill_when_empty` is the wrong tool for a personal pile, which pays for itself on 21 too |
| [21](21-lost-ruins-of-arnak.md) | Lost Ruins of Arnak | large | **researched — zero new primitives, the largest content bill of the three.** Worker placement resolved into two shipped idioms (`exhaust` on the *space*, a capped counter for the workers), which is not what the stub predicted |
| [22](22-the-crew.md) | The Crew: The Quest for Planet Nine | medium | **researched — buildable in full, contingent on one small primitive**: read whose card a scope resolves to and make that seat active. Two customers for it inside one game, which is the ladder's own bar for generalising |
| [23](23-splendor.md) | Splendor | small, mostly content | **researched, and the cleanest verdict of the five** — zero new primitives, zero cut content, and the 90-card data is already collected and cross-checked |
| [24](24-save-and-load.md) | Saving a game, and loading it back | small, on a store that does not exist | not started — the format is already shipped (`net.snapshot`), and so is the has-the-file-changed check. What is missing is somewhere to write |

---

## Where things stand

The engine can express a two-player Knizia game, play it between two computers
over the internet with no server, and hand the game file itself to somebody who
has never seen it. It can express a piece that moves across a board — chess
plays, in six pattern entries and no engine knowledge of what a bishop is. Its
pictures can live on somebody else's server, which is what makes a game file
shareable without shipping binaries with it. What it cannot yet promise is that
your opponent is honest. It does now promise that their hand is hidden, that the
ending screen congratulates the right one of them, and that a row labelled *Your
score* is yours: every one of those asks which seat is *watching* rather than
which one is *up*, one question at one screen and two questions over a network.
Chess and Lost Cities both end with a screen that names the winner, and so
does a two-player creature game with combat in it: Runeterra's vanilla
milestone plays, and every rule of the fight is written in the game file.

**Five games have now been researched rather than guessed at**, and the research
kept paying before any of them was built: LoR's rules corrected *simultaneous
combat* to left-to-right and turned blocking from a stored pairing into
placement; Puzzle Strike found that `refill_when_empty` is the wrong tool for any
personal pile that grows through play, which is true of Arnak too; Arnak's worker
placement — the one row its own file was written to interrogate — dissolved into
two idioms already shipped. The pattern across all five is the same and worth
stating: **what looks like a missing capability is usually a missing
combination**, and the exceptions are few enough to name — hex geometry, a board
whose extent grows, a card played out of turn, and the seat a scope points at.

## What to do next

Ordered by urgency × difficulty × what it unblocks — cheap things that let other
things happen come first.

| # | Item | Urgency | Difficulty | Why here |
|---|---|---|---|---|
| ~~1~~ | ~~[01](01-boardgames.md) gap 3 — **the offset stack**~~ | — | — | **shipped** as the `fan` style property, not as a zone type. Lost Cities' expeditions are piles that spread out, every played card showing a strip with its name; the tally tray uses it too. Klondike still wants the *reach* half — dropping onto the top card rather than onto the zone |
| ~~—~~ | ~~**A nameplate and a pass-the-device overlay**~~ | — | — | **refused.** Hot-seat is a testing mode — two seats driven by one person — so a handover ceremony has nobody to hand over to. The real multiplayer path is networked, where each machine has its own active seat and the leak cannot happen. See [DONE.md](DONE.md), stage A |
| ~~2~~ | ~~[07](07-presentation.md) gap 2 — **click the deck to draw**~~ | — | — | **shipped**, and it never needed the predicate: a zone carries its own `activate` block, so the deck answers rather than the card on top of it becoming clickable |
| ~~—~~ | ~~[14](14-kinds-and-placements.md) — **six chess kinds instead of thirty-two**~~ | — | — | **shipped.** 39 cards to 13, 704 lines to 279, and `make_chess.py` deleted. The blocker was not a style that varies by owner — a computed tag reads one stat, so it cannot say "rook *and* black" — it was a named asset taking one picture per player |
| — | [09](09-composition.md) — **`include`, then a base file of patterns** | — | — | **paused**, and the pause is a decision rather than a backlog: the collision rule wanted is union-with-identical-or-error, not override, and how far a path may reach turned out to touch the network — a peer's game text parses through the same door, so an include in it reads local files and forwards them. Worth re-opening with that settled |
| ~~—~~ | ~~[06](06-schema-and-types.md) gap 1 — **zone qualities as tags**~~ | — | — | **surveyed and refused** (2026-08-13, at `85e51eb`). The full matrix of what `type` bundles is in the idea file and is worth reading — but the split trades one familiar word for five or six a game must keep consistent, and tags are a flat set with no grouping or defaults. The bundles are not wrong, only unexplained. Two small things fell out that are worth doing alone |
| ~~—~~ | ~~[08](08-grid-movement-notation.md) — **check, as a stamped `threat` stat**~~ | — | — | **shipped, and not as a stat.** A threat map is the engine deciding chess is special; `@reach` is a scope word the game file asks with (`count:king@enemy.reach`), computed from the `moves` each piece already declares. Left: refusing a move that leaves your king attacked, and checkmate |
| ~~—~~ | ~~[07](07-presentation.md) gap 3 — **multi-ability chooser**~~ | — | — | **shipped** (`d27d18a`) as `abilities`, and the refusal held right up to the card that needed it: Coronation's Small Council is five advisors on one card. The chooser is the offer overlay that already existed |
| ~~1~~ | ~~[16](16-the-player-at-this-screen.md) gap 1 — **the seat at this screen**~~ | — | — | **shipped** (`fb3d704`). `zones.viewer` is the seat in front of *this* screen and `visible`/`peekable` ask it instead of `active_seat()`, so an opponent's hand stays face down while they think. A field written from outside rather than a call into `net`, since no engine module may require it — and `net.claim_seat` is now the single place a seat is taken, of which there turned out to be **three**, not the two the write-up counted |
| ~~1~~ | ~~[07](07-presentation.md) gap 6 — **an ending that knows who won**~~ | — | — | **shipped** (`f964bbe`, reworked the same day in `0f01bc3`). A win is the reserved `won` stat on the winning seat, set by an ordinary action — so the snapshot carries it, undo takes it back, and a rule can read `won@mine`. It was a field on the ending card first, which could do none of those things. `flow.outcome()` answers it against the seat watching, and `zones.as_seat` fixed the numbers underneath, which had been reporting whoever was to move |
| ~~—~~ | ~~[06](06-schema-and-types.md) gaps 2–3 — **lists everywhere, then guards at the door**~~ | — | — | **measured and folded into [17](17-conditions-as-expressions.md)** (2026-08-16). It is three fields, not six — `patterns` was normalised at the door already and is the model — and six guards, not twenty-two: the `type(` count grew 106 → 184 and *all* of it is in the two files that must keep them, which is this gap's own goal happening on its own. An hour's work with nothing downstream of it but 17, so it is 17's first step rather than an item ahead of it |
| ~~—~~ | ~~**A boolean flag nothing reads**~~ | — | — | **done** (2026-08-16). `exhausts` outlived the engine reading it by three passes and was still recommended by AUTHORING for board buttons; `setup.place`'s `slot` became `at` in [14](14-kinds-and-placements.md) and the same example still wrote it. Both gone, with a retired-vocabulary guard in `tests/integration/docs.lua` so a dropped word cannot stay on offer in a game file, the schema, the generator or an example. See [10](10-schema-document.md) for why the two-way schema test could not see it |
| ~~1~~ | ~~[18](18-legends-of-runeterra.md) stage 1 — **the LoR rules document**~~ | — | — | **done** (`f40a5c2`). It paid for itself twice before a line of combat code existed: strikes resolve **left to right by board position**, not simultaneously, and blocking is strictly one-to-one — which makes it *placement*, and took a missing capability off the list. The card texts came from Riot's Data Dragon, checked in under `lor/data/`, and corrected the deck: only four collectible units in set1 have no keyword at all |
| ~~1~~ | ~~[18](18-legends-of-runeterra.md) milestone 1 — **the combat walk**~~ | — | — | **shipped** (`3f02237`, corrected in `a03c899`). Combat turned out to be *content*: the battlefield applies one tag whose single ability holds five actions, so all ten templates stay text-free and Tough and Overwhelm are terms in a formula rather than words the engine knows. It cost four words — `where` on a slot spec, `move:<scope>:<zone>`, `set_owner`, and a zone's `receive.action` — plus the rule underneath them, **a card is born owned**. And it found a bug no solo game could: an unscoped subject was the *pool* of every seat's copy of a stat, so one player could buy a card out of another's mana |
| ~~2~~ | ~~**Two loose ends on `lor.json`**~~ | — | — | **done** with the above. The controls moved to `[0.82, 0.32, 0.98, 0.68]` — the right edge, between the two decks — and gained an attack button each; a leading `setup` phase deals the opening four, so round one ends with five in hand as [lor/rules.md](lor/rules.md) says |
| ~~1~~ | ~~**Chequer parity: a1 takes the first colour listed**~~ | — | — | **shipped.** `zones.chequer_index` flips one parity and loses the paragraph that justified the old one: the rule is now *the first colour listed is a1's*, with no flag and nothing to check against a real chessboard. `chess.json` and `lor.json` swapped their two strings, which is the whole migration and is what the rule promises a designer. The test (`tests/integration/layout.lua`) says the rule rather than the chessboard, and `AUTHORING.md`'s style table and `SCHEMA.json` both state it where the colouring options are described |
| 1 | [22](22-the-crew.md) — **the seat a scope points at** | medium | small | the primitive, not the game, and it is the cheapest thing on this list that lets another whole game happen: `"seat": "owner_of:<scope>"` (or `set_active_seat:<scope>`) built from `predicate.seat_of` and `G.seat_index`, both already internal — a lookup, not a subsystem. The Crew names two customers for it inside one game — the trick winner and the mission commander — and **LoR names a third**: its attack token's holder is supposed to act first in the round, and nothing can point the turn at a named seat, which milestone 1 records as a deliberate deviation. This repository's bar for generalising is a second customer; this has three, and The Crew has no honest cut around it |
| 2 | [17](17-conditions-as-expressions.md) — **a condition is one string** | medium | large | the format's biggest remaining lever: [10](10-schema-document.md)'s findings 4, 5 and 6 are one fix, and the ending screen added a sixth — a condition cannot name a seat, only `mine` / `enemy`. It opens by normalising the three key-or-list fields, which is all that is left of [06](06-schema-and-types.md) gaps 2–3. The golden traces prove the migration — and every game file written before it lands is added to its bill, which is the argument for doing it ahead of the three buildable games below |
| 3 | [06](06-schema-and-types.md) gap 5 — **a tag is a boolean below the door** | low | small | ride along with 2, because it is the same door and the same normalising pass. Mostly shipped already: a zone entity's `tags` *is* the boolean map, and only two card readers still walk the array. One of them (`cards.home_zone`) depends on tag **order**, so the real deliverable is a validation error for two tags claiming a home zone, not a representation change |
| 4 | [23](23-splendor.md) — **Splendor, from the data already collected** | medium | small | the cheapest whole game on the board: zero new primitives, zero cut content, and all 90 cards plus 10 nobles already triangulated across three sources. It is the strongest available answer to "does the vocabulary reach a euro nobody designed it for", for the price of a JSON file and a scripted test |
| 5 | [16](16-the-player-at-this-screen.md) gaps 2–3 — **a name, and somewhere to type it** | medium | medium | there is no client-side store of any kind — no `love.filesystem.write` in `game/`, no `t.identity`. The browser panel is nearly free; a text field in the engine is a second input surface. It now unblocks two things rather than one: the ending screen prints a seat's key where a player's name belongs, and [24](24-save-and-load.md) has nowhere to write |
| 6 | [24](24-save-and-load.md) — **save and load** | medium | small | strictly after 5, and small once the store exists: the save format is `net.snapshot()` unchanged, loading is `net.apply_full`, and *has the game file changed* is `net.game_hash` with the error message already written. The engine work is two actions and a slot |
| 7 | [20](20-puzzle-strike.md) — **Puzzle Strike, two-player** | low | medium | researched and buildable now. Its one real gap — `flow.reachable` refuses a card played out of turn, which blocks counter-crashing — is cuttable without changing what the game is, and it is the *same* gap LoR's response stack names, so whichever is built second gets it for free |
| 8 | [16](16-the-player-at-this-screen.md) gap 4 — **debug mode, announced** | low | small | wants the store and the handshake field from 5 to exist. Says plainly what it does not buy: an honest client announcing itself is not a defence against a modified one |
| 9 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | low | medium | a jump takes the piece it flies past, and nothing can name that square. Castling-through-check asks for the same word — en passant no longer does, having shipped as `where` |
| 10 | [15](15-many-on-one-square.md) — **a number on a square** | low | small | a slot is already an entity whose stats a condition can read (`row@target`); it just cannot declare one, so `gain_stat` aimed at a square does nothing. One field on the grid. It has a **first honest customer at last** — Mage Knight's per-hex terrain cost — but that game is ranked last, so it stays cheap-and-unasked-for |
| 11 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | low | small | free: answers "is turn-based CS fun" for the price of a game file |
| 12 | [06](06-schema-and-types.md) — **a face-up deck is still unsearchable** | low | small | of the three exclusions the survey called incoherent, two went with `db0cbbd`: a deck can be clicked and browsed now. `tags.find_targets` (`tags.lua:76`) still skips deck zones outright, so `count:<tag>` cannot see a market |
| 13 | [21](21-lost-ruins-of-arnak.md) — **Arnak** | low | large | needs nothing from the engine and the largest content bill of the five researched games. Worth doing when authoring volume is the thing there is appetite for, not when capability is |
| — | [18](18-legends-of-runeterra.md) stages 2–5, and [01](01-boardgames.md) gap 5 — **triggers, spells, the stack** | low | large | not ranked as one item on purpose, and the combat walk in row 1 is deliberately ahead of all of it. What stays missing: spell mana, the mulligan (the offer overlay picks exactly one, and a mulligan picks a subset), a hand bounded at ten, and a response stack that Burst and Focus never enter |
| — | [19](19-mage-knight.md) — **Mage Knight** | low | large | **ranked last on evidence, not on taste.** Hex geometry and a map whose extent grows are two compounding gaps content cannot route around, and the cut that buys both back — a fixed, pre-placed, mostly-hidden map — stops it being Mage Knight. Worth revisiting only if hex geometry is wanted for its own sake |

**The draw path is still where bugs hide, and there is now a way to look.** The
text pass found six faults no test could see — a wrap splitting "Yellow 9" into
"Yello"/"w 9", a badge sitting where the title goes, the tooltip reporting the
engine's own counters as card statistics — every one of them obvious in the
first screenshot. `ideas/07` records the scratch harness and the two things that
stop it working (`captureScreenshot` is asynchronous; the canvas needs
`stencil = true`). Any visual item below should be done against it.

**The syntax pass is done**, and `players` and `setup.place` finished it: a card no longer says whether it is a seat or where it starts. [10](10-schema-document.md) measured it — nine
findings, two of them bugs — and the diagnosis held: **the format had grown
synonyms**. Those are gone. Two names for the card section became `cards`; three
names for one gate became `needs`, with the block saying what it gates; the
`activate_` prefix became structure; seven ways to say how a thing looks became
`styles`. A card is now what it *is*, then the moments it has.

What the schema pass found and this did **not** fix, in case it still itches:
one condition still has three spellings and the site decides which is legal
(finding 5), and a routing entry's `stat` field still takes any subject
(finding 4). Both are additive to fix — nothing would have to be rewritten to
benefit — and neither has cost anybody anything yet.
[17](17-conditions-as-expressions.md) is now where that thread goes: the same
diagnosis arrived independently from the other direction, as *write a condition
as one string instead of a struct*, and the two findings are one fix.

## Worktrees: no. Work in the repository.

**Dropped, 2026-08-16, after using them.** The advice here used to be "two or
three at a time"; the honest verdict from actually doing it is that they make
committing and testing harder for a benefit nobody was collecting. Paths move,
the stash stack is shared with every other checkout, and every command has to be
re-aimed. Work on `main`, or on a branch in this directory.

**What was really being protected survives, and it is worth keeping**: the
append-only conventions. They cost nothing and they are good practice whether or
not two branches ever exist at once.

- **`actions.lua`'s `SPEC` and `HANDLERS`** — append new entries at the **end**,
  never insert alphabetically. Append-only hunks merge cleanly; sorted insertion
  conflicts every time.
- **`validate.lua`'s field tables and `tests/integration/validator.lua`'s
  `CASES`** — same rule. `CASES` is "every error message, once", so a new
  message is a new line at the bottom.
- **Game files** — one new `.json` per track plus one line in `menu.json`. A
  generated game conflicts in the generator, not the output: regenerate rather
  than merging the JSON.
- **`AUTHORING.md` / `DESIGN.md` / `ARCHITECTURE.md`** — a track in flight
  writes its user-facing documentation into its own `ideas/` file, and one pass
  folds them into the shared docs. That is exactly how `DONE.md` came to exist,
  and it is about keeping one voice in those three files rather than about
  merge conflicts.
