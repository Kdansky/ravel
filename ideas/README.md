# Ravel — Idea Workstreams

These are the worked-through ideas: what each requires, where it lands in the
code, what order to build it in, and what to refuse to build. (`../IDEAS.md` is
the original brainstorm they grew out of, kept for provenance only.)

**They are pruned as they ship.** Once a track is built, the plan it was built
from is spent: build orders, pre-build drafts of a design that shipped
differently, and worked examples in a spelling the format has since deleted all
go. What survives is **the decision, the reason for it, and the trap it cost**.
A rejected option keeps one sentence saying why it lost. Nothing that is still
open is shortened.

**Start with [DONE.md](DONE.md).** It records everything already built — what it
does, which files it lives in, the decisions that are load-bearing and the traps
that cost real time — so that finding out what exists does not mean reading the
engine.

## The tracks

| # | Idea | State |
|---|---|---|
| [DONE](DONE.md) | **Everything already built** | stats on cards · seats and hot-seat · the engine's own RNG · procedural art · networked play · stacks and mixins · named and remote assets · the inspector · a label that reads the board |
| [01](01-boardgames.md) | Any board game as JSON | **the ladder.** Lost Cities and chess shipped. The jumped square turned out to need no word — a pattern is already a scope, and the anchor follows the piece. Left: checkers' **chained** jumps, Klondike's run moves, and triggers |
| [02](02-between-two-states.md) | An animation between two states | **shipped whole**: a click's steps are recorded in order and played back a beat at a time, and each beat is a whole state — so numbers, flips, pile counts and a destroyed card all agree with the cards. A move from the network plays its beats too. Left: an exit for a destroyed card, which waits on somewhere for it to go |
| [03](03-a-move-out-of-a-stock.md) | A move out of a stock | **shipped** — `take` is `move` for a source that counts instead of keeps, and the count on `move` went in ahead of it. 95 pairs in Puzzle Strike became 95 statements, and the ten pairs going the other way went with [28](28-a-zone-by-its-parts.md)'s reclaim. Closed |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | **not started**, unblocked, and smaller than written |
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | **closed** — named assets, remote pictures, a generated placeholder. Art stays in git: that gap was a misunderstanding, and remote art was the real requirement |
| [06](06-schema-and-types.md) | Saying what things are | **closed.** Gap 1 reopened and shipped as [28](28-a-zone-by-its-parts.md); the rest shipped, folded into [17](17-conditions-as-expressions.md), or dissolved |
| [07](07-presentation.md) | Presentation and its gestures | **gaps 1–8, 10 and fill shipped.** Gap 7 turned out to be a game file rather than a word: `games/system.json` is merged into every game, so the buttons are ordinary cards. Left: an offer of fifty-one, the log's `{name}`, and whose screen a system button's question goes to |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | **chess plays** — castling, check, promotion, en passant. Left: the scope anchor word, and checkmate |
| [09](09-composition.md) | One game out of several files | **shipped, and no longer opt-in** — `include` merges raw JSON before parse, `replaces` says what a file takes over, the network sends the merged game rather than the file, and `system.json` now goes through the same door into all seventeen games. A game stays self-contained, so an include names the *same game's* files — a variant, or a set belonging to it — and never a library two games share. Left: a variant that adds a seat |
| [10](10-schema-document.md) | A game file that describes itself | **shipped** — `SCHEMA.json`, held to the engine both ways |
| [11](11-styles-as-tags.md) | Styles are tags too | **shipped**, and it deleted more than it added |
| [12](12-card-moments.md) | A card is a list of moments | **shipped** — the `activate_` prefix, `requires`, `accepts` and every `on_` name are gone |
| [13](13-one-name-one-thing.md) | One name, one thing | **shipped whole.** A key is unique within its kind and the *scope* namespace may not collide; a **field** name means one thing too — `from` kept the departure, a compute is a `value` and a reaction answers `in` a place, both old spellings refused by name. The sweep that found it had a hole of its own: it compared candidates only against names that already collided, so `at` read as free and was applied everywhere before `setup.place` turned up owning it |
| [14](14-kinds-and-placements.md) | Six kinds, thirty-two pieces | **shipped** — chess is 13 cards and 279 lines, and its generator is deleted |
| [15](15-many-on-one-square.md) | Several cards on one square | **answered: not yet.** Three questions in one; two are already built and the third has no customer |
| [16](16-the-player-at-this-screen.md) | The player at this screen | **gap 1 shipped**, the rest parked — a name pays off only over a network, and there chat is wanted as much. Chat is now asked for on its own |
| [17](17-conditions-as-expressions.md) | A condition is one string | **shipped whole**, and 112 conditions across ten game files went with the struct forms. Reopened 2026-09-15: one spelling, and it reads like code — `count@mine.self >= 1` is "this card is mine" |
| [18](18-legends-of-runeterra.md) | Legends of Runeterra | **milestone 1 plays.** Left: spells, speeds, the rest of the keywords, champions |
| [19](19-mage-knight.md) | Mage Knight | **researched, ranked last of three.** Two compounding engine gaps; the cuts that buy them back are dishonest ones |
| [20](20-puzzle-strike.md) | Puzzle Strike | **built and playing**, the whole box drafted. Buying has a floor and no ceiling, the chips that trade one in for another offer the bank, everything trashed goes back on its plate, and Signature Move searches both piles and plays what it finds. Left: a short list of engine features, and the per-chip state is in the game file |
| [21](21-lost-ruins-of-arnak.md) | Lost Ruins of Arnak | **built and playing**, hand-written, two seats. Left: three and four players, the travel hierarchy, and the branching half of the research track |
| [22](22-the-crew.md) | The Crew | **built and playing.** Left: the order tokens and the printed fifty missions |
| [23](23-splendor.md) | Splendor | **shipped whole**, two seats |
| [24](24-save-and-load.md) | Saving a game | **shipped** over `net.snapshot`, with no second format |
| [25](25-derived-stats.md) | A stat that keeps itself | **closed unbuilt 2026-09-07.** The corpus's arithmetic is a sequence, not an expression — chained intermediates, a stat reassigned from its own derivative, a conditional write — so a declaration expresses none of it. Three scratch stats went in the pass that answered it, none of them for a reason this track predicted |
| [26](26-an-if-and-a-name.md) | An ability with an if, and a number with a name | **shipped** — `when` and `computes` |
| [27](27-reactions-and-the-stack.md) | Reactions and the stack | **shipped and in use.** A reaction may open an offer of its own. Left: speeds, Magic depth, and an emission suppressor |
| [28](28-a-zone-by-its-parts.md) | A zone by its parts | **shipped whole**, `supply` is a fourth `status` since, and a destroyed component now goes home to the box that stocks its kind — no new word, because a supply's shelves already say what it stocks. Reopened once: a refill fires on demand and no game can say whether it may |
| [29](29-a-place-to-fight.md) | A place to fight | **shipped whole.** Combat is a zone walked in nine steps, `origin` sends everyone home, and one patrol row made adjacency fall out. Resist landed with [30](30-things-that-are-true.md), lookout post included. Left: overpower's spill, which wants a second victim picked mid-step |
| [30](30-things-that-are-true.md) | Things that are true | **shipped whole.** `buffs` and `adjusts` both ship, keyed to verbs a game declares so that being interferable is opt-in. The cost half landed as a game naming its own *aims* — `attack`, `cast`, verbs that `does: "target"` — rather than as the draft's engine-level `"verb": "target"`, which would have broken that very rule. One word then answered two questions: `not_verb:cast` in a card's `receive.needs` is untargetable, and the same key on an `adjusts` is resist. Codex lost 22 ward clauses and gained 2. Buff *stacking* was asked and needed nothing: two tags shifting one stat already add, and a measured amount was refused because a buff is read on every stat read |
| [31](31-either-of-two.md) | Either of two | **half done.** The `or` between *kinds* landed as `computed_tags.any_of` — a union with a name, usable wherever a tag is, and a zone `applies` tag is how that union comes to mean a *place*. `or` between *conditions* is still open, is one decision, and has no customer |
| [33](33-a-row-that-closes-up.md) | A row that closes up | **closed.** `compact`'s ordering is the whole of the first half — the furthest card moves first, so nothing behind overtakes something in front — and the second is that a cell on `draw_from` was not a new word: the position argument every destination op already had learned to name a square. Arnak's row is one `grid: [7, 1]` with the moon staff standing in it |
| [34](34-an-opponent.md) | An opponent | **steps 1 and 2 shipped.** A seat the engine plays: `M.legal()` and one `math.random`, reachable as `bot <seat>` in the CLI and `o` in the GUI. The work was around it — a test's move list had to become an interface's (a window, a place, a card outside the hand), and a claimed seat had to stop forbidding the very move it was hiding a hand for. Left: what winning is as a *number*, which is where better-than-random starts, and where the switch belongs — a card, by the invariant |
| [35](35-a-board-that-fits-the-game.md) | A board that fits the game | **shipped, both halves.** The seat's own name is `set_name` over a `{name}` template; the shelf is `pos` naming a zone, so several mutually exclusive zones share one rect and the one showing is the first holding a card. Left: `shown_when`, which the shelf may have answered — it wants a customer the shelf does not already serve |
| [32](32-a-third-player.md) | A third player | **both halves shipped.** `type: "turn"` is a phase whose body is other phases, run once per player with `seat: "each"` and in the order `order` names — so a step every player takes is one declaration, and sixteen of Spellstorm's twenty-five phases stopped being per-seat copies. `@opponent` is the seat beside the filter: *the* other player, a scope like `@self` rather than an owner word, refused at any other seat count. Left: the zone scopes `enemy` still owns, and a group that starts with whoever is already up |
| [36](36-a-card-on-a-card.md) | A card on a card | **shipped whole.** A card stands on another rather than beside it: the link survives a move because `zones.move_card`/`destroy_card` maintain it, `attached_to.<scope>` and `host_of.<scope>` read across it in either direction, a rider keeps no square and draws on its host, and a full grid still has room for one. Arnak is the customer — two `digger` cards a seat, `workers` and `guarded` both deleted, and `overcome` gated on `guard@host_of.self` instead of a per-seat tally. The guardian deck went in behind it: a guardian is a card with its own price, dealt onto the site by the island's own `receive`, and `overcome` is its ability asking who is standing underneath |
| [37](37-codex.md) | Codex | **built and playing**, all 330 cards in the file: red, green and blue run, black, white, purple and the two neutral specs are scaffolding. Sacrifice is closed both ways, and so is the Truth spec: an Illusion dies of being aimed at, which is one line on a tag now. Left: Macciatus and the two cards that hand the word out — an owner scope anchored on `@self`, and granting a tag at all — forecast, and three small words the box asks for 33 times between them |
| [38](38-repeated-shapes.md) | The shapes that repeat | **surveyed, mostly built.** Codex, Puzzle Strike and Spellstorm counted for structure that repeats. Left: the **death half** (a state the rules resolve, not a moment), Codex's combat macro written out three times, a printed stat that steps, and an ability that cannot act and then ask |
| [39](39-spellstorm-at-the-table.md) | Spellstorm at the table | **the seat card and damage shipped.** A verb carries its look, so every blow throws a bolt. Left: the weather flip, and Initiative |
| [40](40-reconnecting.md) | Picking a dropped game back up | **not started.** The survivor holds the whole state and a full state already travels; the original WebRTC string cannot be reused, so the reconnect is a fresh invite from the side still in the game — and seats, which follow roles, have to survive the swap |

## What to do next

Cheap things that let other things happen come first. **The number is a stable id,
not a position** — rows below refer to each other by it — so the *order* of the rows
is the ranking and a new item keeps the next free number wherever it lands.

**A shipped row is deleted, not struck through.** What it built is in the real
docs and in [DONE.md](DONE.md); a second copy here is a third place to keep in
step. A row stays only while something in it is still open, and then it says what
is left rather than what was done.

| # | Item | Difficulty | Why here |
|---|---|---|---|
| 71 | [39](39-spellstorm-at-the-table.md) — **what the seat card still leaves out** | small | badges on the seat and the Ultimate cost shipped, sized to the card. Left: power and shards read nothing at 0, and whether Initiative wants more than an arrow — both want a look at a real game first |
| 72 | [39](39-spellstorm-at-the-table.md) — **the weather, announced** | small | damage now throws a bolt from the verb (`hit`'s `effect`). Left: the weather flip wants a beat shown large — the `reveal` overlay or a `layout: "page"` zone it passes through — and whether `heal` and `power_up` want a look of their own |
| 24 | [16](16-the-player-at-this-screen.md) — **chat with the peer, and a name** | medium | asked for again, and on its own this time: a wire kind beside `H` that changes no state, and a text field — the input surface is still the decision. The name can follow rather than ship with it |
| 63 | [38](38-repeated-shapes.md) — **the death half** | small, and a word to agree first | worked through and **not built**: four hooks tried, all failing on one fact — arrival is a moment, death here is a *state* the rules then resolve, and the corpse standing at nought carries which slot it died in, whose it was, whether it is insured and whether it has a second life. Codex has death replacement (Brave Knight to hand, Juggernaut healed, Agent paid), so arriving in the graveyard is the rules' *answer*, not their trigger. 14 of the 54 already need nothing (`destroy:` fires `leaves`, which already emits `died`); 8 more are load-bearing. What fits is a state check at a moment — one engine zone tag, the weight of `shuffle`. The mirror pairs went first: the death column is 40 abilities down to 24, with `each_seat:` wrapping the *action* inside each ability rather than the zone — around the zone it re-runs the whole column per seat, and `r_units` sweeping both sides would clear the corpses the next seat's Bloodburn is about to count. The gate goes with the halves, a `needs` being read from whoever is up, so each rule says its condition as the amount instead; it turned up an Insurance Agent that summed gold per claim but only ever drew one card. Three pairs stay (a guard about a third card, which no amount carries), and so do the two sweeps: a `leaves` moment is also read from whoever is up, so `each_seat:` around a *move* puts the owner's seat up and Crash Bomber's bomb goes off in nobody's face. Still open: `r_scav` looks to pay nothing on a `destroy` where Codex pays on any death |
| 70 | [17](17-conditions-as-expressions.md) — **a condition a non-programmer can read** | medium, and a word to agree first | `count@mine.self >= 1` is *"this card is mine"* spelled as a set-membership test, because a count is the only thing the grammar can compare. Eleven sat in Codex as a guard. `count:<tag>@<scope> >= 1` for *"there is one"* is the same shape and the most common condition in the corpus. The honest version is a replacement with a migration rather than aliases beside the arithmetic, since two ways to say one thing is the synonym-with-a-schedule the README warns about — which is what makes it more than an afternoon |
| 52 | [37](37-codex.md) — **sideline, return to hand, swift strike** | small each | 33 cards between the three, and each is already written inline somewhere — sideline three times in blue, as `stat_set:slot@x:0` and a move. Ranked as one because none is hard and each one stops the next inline copy being written wrong. Return to hand is half a death replacement, which is five cards and wants generalising rather than a rules column each |
| 50 | [27](27-reactions-and-the-stack.md) — **an offer opened from a departure** | medium, and two guards | Crash Bomber's own-turn half works alone and hangs two bot games in twenty: the offer opens inside a death sweep that can re-enter it, and `show:` *borrows* the base out of `base`, so the end condition reading it cannot fire while the question is open. Wants a way to offer a card without moving it. Above 42 and 35 because it is the only open row that loses a game outright |
| 49 | [07](07-presentation.md) — **the log says `{name}`** | small, and one decision | a renamed seat reads right everywhere a label is *drawn* and wrong in the event log, because `flow` writes the string finished. Filling at write time defeats [27](27-reactions-and-the-stack.md)'s answer-when-drawn rule; filling at read time needs the entity the log does not keep. The decision is which of the two the log gets |
| 48 | [09](09-composition.md) — **the validator messages nothing reaches** | small | all but a couple of `warn()` calls fire under the suite. The survivors sit in the action-argument walk and look like the binder rather than the check, so the hour goes on `SPEC` argument binding and not on the prose. Re-measure before starting — the count moves with every new check |
| 35 | [32](32-a-third-player.md) — **the zone scopes `enemy` still owns** | small each, forty of them, and a judgment per site | `@opponent` took the 34 *player* sites; `@enemy.hand`, `@enemy.patrol` and `@enemy.taken` are what is left, and they are not a sed — a zone scope is a place *and* a filter, so `count:king@enemy.taken` may honestly want the pool where `stat_damage:health@enemy.player` never did. Finishes the word that just landed, while the reason each of the forty was written is still legible |
| 42 | [28](28-a-zone-by-its-parts.md) — **a refill a game may gate** | small, and a word to agree first | Codex reshuffles without limit where the rulebook allows one per main phase, and the inbox note that raised it had the moment wrong in the direction that makes it cheaper: `refill_from` fires **on demand** in `zones.move_top`, not on emptying, so a cap has one site and it is already the draw attempt. A stat cannot stand in — `restock` tips the pile over a card at a time, so `receive` fires per card and not per refill. Above 40 because both are Codex bugs and this one's fix site is known; below 35 because it wants a new word and has exactly one customer of six |
| 40 | [29](29-a-place-to-fight.md) — **overpower's spill** | small, and one decision | `clear` zeroes a `spill` stat nothing reads, so overkill stops at the card it killed. The step was drafted and never written because the excess has to reach *another attackable thing* — a second victim chosen after the first is dead, which nothing in the walk picks. Decide whether the walk may choose, or whether the game names the base and stops there |
| 51 | [37](37-codex.md) — **a card that costs nothing** | small, and a word to agree first | four cards, none of them an aim, so `adjusts` reaches none of them: it is keyed on a verb and a chosen target, and a unit played out of a hand has neither. Wants a word on a tag that shifts what a *class* of card costs its owner, the way `pays_for` says one pool settles another. Below 40 because the subtract half already works and only the reach is missing |
| 53 | [37](37-codex.md) — **forecast** | medium, and a zone that is not in play | purple's whole Future spec, 7 cards: three time runes, one off each upkeep, arrival when the last goes — most of which the file can say already. Hardened Mox is the part it cannot, since *"even a forecasted one"* asks about a card that is deliberately nowhere. Here because purple is scaffolding and nothing else waits on it |
| 23 | [07](07-presentation.md) — **an offer of fifty-one** | small | the draft may only look bad because its two buttons are 23px squares — and item 2 is in now, so the second look is available. Decide then whether `layout: "page"` — which already draws the reveal overlay — should serve an offer too |
| 19 | [09](09-composition.md) — **a seat count as a module, over Spellstorm** | medium | the *variant* test, which is the half `system.json` did not prove: that module adds a zone nobody had, where a seat count changes rects and phases a game already wrote. Adding *and* removing a seat, because the two fail differently. Spellstorm is two seats and 6 per-seat zones, and its file is generated while the module would be hand-written — the split `include` exists to make possible. **The proof is a test over a POC game rather than a new game**, so nothing has to be authored twice. The `_1`/`_2` phase pairs it was blocked on are gone, so what is left is the merge itself |
| 22 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | small | free: answers "is turn-based CS fun" for the price of a game file |
| 21 | [15](15-many-on-one-square.md) — **a number on a square** | small | a slot is already an entity whose stats a condition can read; it just cannot declare one, so `stat_gain` aimed at a square does nothing. One field on the grid. It has a first honest customer at last — Mage Knight's per-hex terrain cost — but that game is ranked last |
| 15 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | **no word needed; only chained jumps left** | probed 2026-09-08 and the file's claim was wrong: a jump takes the piece it flies past *today*. A pattern is already a scope, and the anchor follows the piece — `where` reads it from the destination, and after `move_to:target` the action's fallback to `c.slot_id` is that same square, so `purge:back_sw` takes the victim. It costs one rule per direction (a man is 2, a king is 4), and the word that would collapse that is written up as **only implement when needed** — after checkers is written and the verbose version has been read. What is actually left is **chained jumps**, which is a flow question |
| 43 | [34](34-an-opponent.md) — **where the switch for an engine seat belongs** | small, and a word to agree first | `o` in the GUI and `bot <seat>` in the CLI both work and both are an interface inventing its own affordance, which is what the networking panel used to do before *networking is a thing a card does*. A two-player game deals a card offering an invite; the same game should be able to deal one offering an opponent. Needs an action word, so it waits on consent rather than on effort |
| 16 | [31](31-either-of-two.md) — **`or` between conditions** | small, and no customer | **all three of its customers went away rather than being built, and it is ranked on the strength of the idea alone.** The rulebook's escape from buy-one when the Wound stack empties is answered by a stack nobody can empty; and the shopping a reaction hands over turned out to be an offer of the bank, not a rationed buy phase — only Upgrade still needs a purse, and its looseness is a chip per chip trashed, which no `or` would fix. `meets_all` is the one function fourteen consumers share, so whatever spelling wins lands once |
| 75 | [40](40-reconnecting.md) — **a dropped game, tried in two browsers** | small, and a manual check | parked behind the rest 2026-09-17 — the check is a person with two browsers. Rejoining is built and tested over loopback: the survivor invites again, and the other side sits back in its own seat. Left: watch the panel notice a real WebRTC drop, and decide whether a crashed tab should keep a copy of the game to host from |
| 74 | [07](07-presentation.md) — **a system button's question, over a network** | small | not wanted (2026-09-17), kept for the record. Menu asks first and names its question through `{asker.…}`; the offer is shared state, so across a network it goes to the seat to play, not the one that clicked. Untested, and a loopback test says which |
| — | [18](18-legends-of-runeterra.md) + [01](01-boardgames.md) gap 5 — **triggers, spells, speeds** | large | not ranked as one item on purpose. [27](27-reactions-and-the-stack.md) shipped the window; what is left is speeds, spell mana, the mulligan, and a hand bounded at ten |
| — | [19](19-mage-knight.md) — **Mage Knight** | large | **ranked last on evidence, not taste.** Worth revisiting only if hex geometry is wanted for its own sake |

## What the tracks have taught

Ordered by how often the lesson comes back rather than by date.

**What looks like a missing capability is usually a missing combination.** Five
games researched rather than guessed at, and the research kept paying before any
was built: LoR's rules corrected *simultaneous combat* to left-to-right and
turned blocking from a stored pairing into placement; Puzzle Strike found
`refill_when_empty` was the wrong tool for any pile that grows through play;
Arnak's worker placement — the one row its file existed to interrogate —
dissolved into two shipped idioms. The exceptions are few enough to name: hex
geometry, a board whose extent grows, and the seat a scope points at
absolutely. (A card played out of turn was the fourth, and
[27](27-reactions-and-the-stack.md) closed it.)

**The floor is the only arithmetic operator the grammar has, and it is enough
for both directions.** `stat_damage` against `min: 0` is `max(0, a - b)`, which
is the whole of Splendor's pricing; and `min(a, k)` is `a - max(0, a - k)`, the
same floor used twice. Runeterra's Tough needed less again — the only reason it
looked impossible was that the arithmetic was being done on the way *out*
instead of on a number on the way *in*.

**A default that was never stated is a rule nobody chose.** `ends_after` counting
plays was true of every game written first and false of most. `on_turn` firing
on grids alone, `face_up` claimed on a hand and never honoured, a phase's `zone`
holding one key — each was an unexamined default rather than a decision.

**A bend that keeps needing more keys is usually the wrong axis.** The condition
struct was added because a flat `key: number` map cannot ask a condition the
other way, which was true; what was wrong was concluding the format needed a
*richer object*. It needed a string.

**The format had grown synonyms**, and the syntax pass is what removed them: two
names for the card section, three for one gate, an `activate_` prefix meaning
structure, seven ways to say how a thing looks. A card is now what it *is*, then
the moments it has.

**The verbs grew them too, and a synonym hides a bug.** Five of forty-eight ops
were another op with a scope or a zone folded into the name — `destroy_self` is
`purge:self`, `move_target_to` is `move:target:`. Two of the five were also
*wrong*, and in the same way: the short name had quietly picked an answer.
`gain` worked its zone out from the card's tags and, when two tags disagreed,
put the card in the hand saying nothing. `move` sorted by entity id — when a
card was made — so emptying a shuffled pile dealt it back in creation order.
Neither would have been found by reading the verb; both fell out of asking what
the longer spelling did differently. **The scope words were the tell**: `self`
and `target` had been scopes all along, so any verb naming one in its own name
was a scope that could not be written where a scope belonged.

**A shorthand for the one-of case is a synonym with a schedule.** The `activate`
block and the `abilities` list said the same thing in two arrangements, and the
pair held only while neither grew: `when` reached both, `compute` reached one,
and naming a number meant reshaping the card that wanted one. The cost of the
short form is paid every time either side changes, and it is paid in silence.
One shape, and one thing to do is a list of one.

**A stat says whose number it is.** A card carrying a stat is how it says it
takes part in that number, so scratch registers had to be declared at zero on
every card an arithmetic was about. `on` and `start` moved that to the stats
section; `on` with no `start` is the other half and is a *check* rather than a
default — *a creature has hp, and every creature says how much*. Splendor went
from 1,256 zeros to 301, The Crew from 282 to 10.

**A condition about the targets is a `challenge`; a condition about the card is
a `needs`.** A `needs` is asked before there is a pair to be about.

**Arithmetic in these games is a sequence, not an expression**, which is why it
lives in an action list and why a stat that computes itself found no customer.
The shapes that keep it there are chained intermediates, a stat reassigned from
its own derivative, and a write with an if on it. The deciding case is a value
read *between* two mutations of the numbers it is made of — Puzzle Strike's
`sent`, Codex's `over` — where the value has to be frozen at a step, and a
stored register is what freezing looks like. Evaluating on read would be wrong,
not merely slow.

**A workaround outlives the limit it was written for.** Splendor spent ten
actions a turn and a stat keeping `plenty` because an ability was believed to be
gated by its cost and its phase and by nothing else — a belief the engine has
never held. The comment saying so is what made it survive: it read as a decision
rather than as an assumption, so nobody re-asked. Worth checking whenever a
number exists only to be compared against once.

**Only a phase a player acts in can hand the turn over**, so a turn's opening
bookkeeping belongs on the first phase the player acts in. And **the first
`seat: "next"` selects seat one**, because the turn counter starts at nobody —
so a two-seat draft carries the word on *both* of its phases, which reads wrong
and is right.

**The draw path is where bugs hide, and there is a way to look.** The text pass
found six faults no test could see — a wrap splitting "Yellow 9" into
"Yello"/"w 9", a badge sitting where the title goes, the tooltip reporting the
engine's own counters as card statistics — every one obvious in the first
screenshot. [07](07-presentation.md) records the scratch harness and the two
things that stop it working. Any visual item above should be done against it.

## Standing decisions

**The validator stays one function.** Declined 2026-09-06. `validate.M.check`
was 2,702 lines then and has only grown, with 27 nested closures sharing `warn`, `claim` and four tag
universes by capture, and long is not the same as badly structured: the closures
share exactly the state they are about, the order they run in is the order a
game file is read, and splitting them would thread a context record through 27
signatures to buy a shorter file. Raise it again only if a *specific* check
turns out to be untestable, which is a different complaint.

**Worktrees: no, except when somebody else is in the tree.** The exception was
taken on 2026-09-03, with a second person editing Spellstorm in the checkout,
and it is the only reason that holds. Two things to know before repeating it:
`tools/guard.py` walks up for a `.git` **directory**, and in a worktree `.git`
is a *file*, so it reads the main checkout's status and refuses every generator
run over somebody else's uncommitted work — `RAVEL_ALLOW_DIRTY=1` is the way
past once your own worktree is committed. And the planning files stay in the
main checkout, because the other person is editing those too.

**Otherwise: no. Work in the repository.** Dropped 2026-08-16 after using them —
they make committing and testing harder for a benefit nobody was collecting.
Paths move, the stash stack is shared with every checkout, and every command has
to be re-aimed. What was really being protected survives and is worth keeping:
the append-only conventions.
