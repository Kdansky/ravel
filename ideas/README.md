# Ravel — Idea Workstreams

`IDEAS.md` is the raw list. These files are the worked-through versions: what
each idea requires, where it lands in the code, what order to build it in, and
what to refuse to build.

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
| [DONE](DONE.md) | **Everything already built** | stats on cards · seats and hot-seat · the engine's own RNG · procedural art · networked play · stacks and mixins · named and remote assets · the inspector |
| [01](01-boardgames.md) | Any board game as JSON | **the ladder.** Lost Cities and chess shipped. Left: checkers' jumped square, Klondike's run moves, and triggers |
| [02](02-between-two-states.md) | An animation between two states | **shipped**: a click's steps are recorded in order and played back a beat at a time, and each beat is a whole state — so numbers, flips, pile counts and a destroyed card all agree with the cards. Left: stage 3, which is pruning two things the queue replaced |
| [03](03-a-move-out-of-a-stock.md) | A move out of a stock | **shipped** — `take` is `move` for a source that counts instead of keeps, and the count on `move` went in ahead of it. 95 pairs in Puzzle Strike became 95 statements, and the ten pairs going the other way went with [28](28-a-zone-by-its-parts.md)'s reclaim. Closed |
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | **not started**, unblocked, and smaller than written |
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | **closed** — named assets, remote pictures, a generated placeholder. Art stays in git: that gap was a misunderstanding, and remote art was the real requirement |
| [06](06-schema-and-types.md) | Saying what things are | **closed.** Gap 1 reopened and shipped as [28](28-a-zone-by-its-parts.md); the rest shipped, folded into [17](17-conditions-as-expressions.md), or dissolved |
| [07](07-presentation.md) | Presentation and its gestures | **gaps 1–6, 8 and fill shipped.** Left: a word for where the buttons go, where the stat readout sits, and an offer of fifty-one |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | **chess plays** — castling, check, promotion, en passant. Left: the scope anchor word, and checkmate |
| [09](09-composition.md) | One game out of several files | **shipped** — `include` merges raw JSON before parse, `replaces` says what a file takes over, and the network sends the merged game rather than the file. A game stays self-contained, so an include names the *same game's* files — a variant, or a set belonging to it — and never a library two games share. Left: a module actually written, and provenance in validator messages |
| [10](10-schema-document.md) | A game file that describes itself | **shipped** — `SCHEMA.json`, held to the engine both ways |
| [11](11-styles-as-tags.md) | Styles are tags too | **shipped**, and it deleted more than it added |
| [12](12-card-moments.md) | A card is a list of moments | **shipped** — the `activate_` prefix, `requires`, `accepts` and every `on_` name are gone |
| [13](13-one-name-one-thing.md) | One name, one thing | **shipped**, and narrower: a key is unique within its kind, and the *scope* namespace may not collide |
| [14](14-kinds-and-placements.md) | Six kinds, thirty-two pieces | **shipped** — chess is 13 cards and 279 lines, and its generator is deleted |
| [15](15-many-on-one-square.md) | Several cards on one square | **answered: not yet.** Three questions in one; two are already built and the third has no customer |
| [16](16-the-player-at-this-screen.md) | The player at this screen | **gap 1 shipped**, the rest parked — a name pays off only over a network, and there chat is wanted as much |
| [17](17-conditions-as-expressions.md) | A condition is one string | **shipped whole**, and 112 conditions across ten game files went with the struct forms |
| [18](18-legends-of-runeterra.md) | Legends of Runeterra | **milestone 1 plays.** Left: spells, speeds, the rest of the keywords, champions |
| [19](19-mage-knight.md) | Mage Knight | **researched, ranked last of three.** Two compounding engine gaps; the cuts that buy them back are dishonest ones |
| [20](20-puzzle-strike.md) | Puzzle Strike | **built and playing**, the whole box drafted. Buying has a floor and no ceiling, the chips that trade one in for another offer the bank, everything trashed goes back on its plate, and Signature Move searches both piles and plays what it finds. Left: a short list of engine features, and the per-chip state is in the game file |
| [21](21-lost-ruins-of-arnak.md) | Lost Ruins of Arnak | **built and playing**, hand-written, two seats. Left: three and four players, the travel hierarchy, and the branching half of the research track |
| [22](22-the-crew.md) | The Crew | **built and playing.** Left: the order tokens and the printed fifty missions |
| [23](23-splendor.md) | Splendor | **built and playing**, two seats |
| [24](24-save-and-load.md) | Saving a game | **shipped** over `net.snapshot`, with no second format |
| [25](25-derived-stats.md) | A stat that keeps itself | **not started, and to be re-read rather than built** — [26](26-an-if-and-a-name.md) answers two of its three blocking questions by construction |
| [26](26-an-if-and-a-name.md) | An ability with an if, and a number with a name | **shipped** — `when` and `computes` |
| [27](27-reactions-and-the-stack.md) | Reactions and the stack | **shipped and in use.** A reaction may open an offer of its own. Left: speeds, Magic depth, and an emission suppressor |
| [28](28-a-zone-by-its-parts.md) | A zone by its parts | **shipped whole**, `supply` is a fourth `status` since, and a destroyed component now goes home to the box that stocks its kind — no new word, because a supply's shelves already say what it stocks |
| [29](29-a-place-to-fight.md) | A place to fight | **shipped whole.** Combat is a zone walked in nine steps, `origin` sends everyone home, and one patrol row made adjacency fall out. Left: resist, which [30](30-things-that-are-true.md) reaches |
| [30](30-things-that-are-true.md) | Things that are true | **mostly built.** `buffs` and `adjusts` both ship, keyed to verbs a game declares so that being interferable is opt-in; the targeting ward already shipped as `receive.needs` and no game uses it. Left: the cost half, which is resist, and which waits only on what the player is shown |
| [31](31-either-of-two.md) | Either of two | **half done.** The `or` between *kinds* landed as `computed_tags.any_of`/`all_of` — a union with a name, usable wherever a tag is, and a zone `applies` tag is how that union comes to mean a *place*. `or` between *conditions* is still open, is one decision, and has no customer |
| [33](33-a-row-that-closes-up.md) | A row that closes up | **`compact` shipped**, and its ordering is the whole of it: the furthest card moves first, so nothing behind overtakes something in front. Left: a cell on `draw_from`, then Arnak's row rebuilt as one seven-wide grid with the moon staff standing in it |
| [32](32-a-third-player.md) | A third player | **not started, parked.** Rotation, `each_seat:` and per-seat zones are already any size; what is missing is a word narrower than `enemy`, which means "not me", and a `seat: "all"` phase to stop writing `_1`/`_2` twice |

## What to do next

Cheap things that let other things happen come first.

| # | Item | Difficulty | Why here |
|---|---|---|---|
| ~~1~~ | [02](02-between-two-states.md) — **stage 2, the presented state** | medium | **shipped**, and smaller than written: the registry is already a swappable pointer, so presenting a state is `entity.restore` around the frame rather than an accessor over 26 sites in `render.lua`. Stage 1's pin and its cut both went — with a state per step the sequencing is inherent, and a card that moved twice makes both moves |
| ~~2~~ | [07](07-presentation.md) — **a card that fills the zone it is in** | tiny | **shipped.** `fit: "fill"` is read outside grids now, and a filled row picks the column count whose cells come out closest to square. It did *not* fix Puzzle Strike's buttons: those are 28px because the zone is 179×46px, which is gap 7's question, not this one |
| ~~3~~ | [03](03-a-move-out-of-a-stock.md) — **`take`** | small | **shipped**, and the count on `move` with it. 95 sites in Puzzle Strike stopped being two statements that can drift apart, and the card now arrives remembering the box — so [02](02-between-two-states.md) reads an origin instead of guessing one. The renderer takes the *stack* off the zone, since a bank is a shelf of eighteen and the eye was on one of them |
| ~~4~~ | [28](28-a-zone-by-its-parts.md) — **where a destroyed card goes** | small + one decision | **shipped**, and the decision turned out not to need making: two boxes stocking one kind is a game nobody has written, so it takes the first that matches — the owner's own box first, the same preference a refill makes. No new word, because a supply's `contents` were already the declaration. Ten pairs in Puzzle Strike were a destroy beside the refund it now makes itself. The box and MTG's graveyard turned out to be two questions on two axes — a component goes home by *kind*, a card to its owner's graveyard by *seat* — so the graveyard is still open and will be a different word |
| ~~5~~ | [20](20-puzzle-strike.md) — **Signature Move's second half, and the gems that break into the void** | small each | **shipped whole, and the void with it.** Every trashed thing goes back on its plate now — nine gem sites and eleven chip ones as `destroy:target`, eight self-trashers as `destroy_self` — so the offscreen stack that stood in for "out of the game" has nothing left in it and is deleted. `destroy` rather than a move to the bank is what makes the two *character* chips that trash themselves safe: nothing stocks one, so it is simply gone, where a move would have built it a plate. **Signature Move** asks its second question from a rules card, the way the piggy bank does, and the offer queue sequenced the two with nothing said about it; its search is `mine.everywhere.character_stowed`, a union of two tags the bag and the discard hand out — the idiom Spellstorm already uses, which I had failed to find |
| ~~6~~ | `todo.md` — **`compute` on a lone `activate`** | tiny | **answered by deleting the question.** The asymmetry was the point: two spellings of one thing drift the moment either grows a field, and this was the drift. So the shorthand block is gone — a card, a tag and a zone all write `abilities`, and one that does a single thing writes a list of one. The flat `activate_cost` / `activate_when` / `on_activate` names went with it, having existed only because a block had to flatten into something. 56 sites migrated, `compute` fell out free, and it reached `play` in the same pass — a played card's cost and gate can name a number now. A zone came down a path of its own and could only ever offer one thing; it goes through the same door, chooser and all |
| ~~7~~ | `todo.md` — **the merge warning that names the same tag twice** | tiny | **fixed.** The zone side names what the card side already named: `the tag 'shop' ability 'buy' and the tag 'shop' ability 'steal'`, so one tag holding both halves of the contradiction reads as one tag. It is worth a test of its own because the sentence *is* the diagnosis — a zone-granted tag is not in the card's own `tags`, so nothing else catches this pairing. Went with it: `make_spellstorm.py` was the one generator that never checked whether the guard let it write, and died in `open(None)` on a dirty tree instead of exiting; it also aimed at a path relative to the shell rather than to itself |
| 8 | [07](07-presentation.md) gap 7 — **a word for where the buttons go** | small | eight games have each invented their own chrome in raw fractions, and an author must answer "where do the buttons go" before putting a button anywhere. The cheap version is a named region resolved in `zones.resize`, one branch, keeping the model that a button is a card in a zone. Unblocked: item 2 shipped and left the buttons at 28px, which is this question's answer to give |
| 9 | [07](07-presentation.md) — **where the numbers are read, and whether zeros are** | medium, and a word to agree first | `draw_stats` is hard-anchored to the top-right corner in pixels, so any game using that corner has its readout printed over it. Two independent halves: a place, which needs a new field and therefore consent; and zeros, where `badge_zeros` already exists for the card end of the same question |
| ~~10~~ | [09](09-composition.md) — **`include`, then a base file of patterns** | medium | **shipped.** The pause's two questions were answered the other way round from how they were written: the *specific* file includes the general one — a module includes the whole game, never the reverse, or the base would *be* one of its own variants — and a collision is an error unless the including file says `replaces`, which keeps what "refuse every collision" was protecting while letting a layout module exist. `setup` travels now, which that draft said it would not: it assumed a base with no setup of its own. Merged as raw JSON before parse, so nothing downstream learns the word; the network sends the merged game, since a file naming two others is no use to a peer holding neither. A shared `base.json` of geometry was built as the proof and then taken back out: a pattern in a file that does not define it sends the reader elsewhere to find out what their own game means, and four saved lines do not pay for that. Chess writes its own eight knight vectors, which is the format working rather than repeating itself |
| 11 | [25](25-derived-stats.md) — **re-read, not built** | small + one decision | what is left is whether a stat that keeps itself is worth anything *once a formula can sit at its use site with a name on it*. Answer it with The Crew's `weigh` migrated. The one thing a compute cannot do is clamp, and Splendor's pricing rests on `min: 0` |
| 12 | [33](33-a-row-that-closes-up.md) — **a cell on `draw_from`, then Arnak's row** | small, then medium | **`compact` is in.** Sliding a shelf shut turned out to be one pass rather than a settling loop, because the direction says what order to move in — the furthest card packs against the end and every card behind stops against a final wall. What is left is the deal: after a compaction the free cells are the two outer ends, and `draw_from` fills by slot index, which is right for one end of a shared row and exactly wrong for the other. Then the staff becomes a card standing in a seven-wide grid and `destroy:beside` is the rulebook sentence |
| 13 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | medium | a jump takes the piece it flies past, and nothing can name that square. Castling-through-check asks for the same word; en passant no longer does, having shipped as `where` |
| 14 | [31](31-either-of-two.md) — **`or` between conditions** | small, and no customer | **all three of its customers went away rather than being built, and it is ranked on the strength of the idea alone.** The rulebook's escape from buy-one when the Wound stack empties is answered by a stack nobody can empty; and the shopping a reaction hands over turned out to be an offer of the bank, not a rationed buy phase — only Upgrade still needs a purse, and its looseness is a chip per chip trashed, which no `or` would fix. `meets_all` is the one function fourteen consumers share, so whatever spelling wins lands once |
| 15 | [32](32-a-third-player.md) — **`seat: "all"`, and a word narrower than `enemy`** | small each, and a word to agree first | ranked for the two-player payoff, not the player count: `seat: "all"` collapses every `_1`/`_2` phase pair, of which Spellstorm has two. The `enemy` half is a new word and waits on consent |
| 16 | [15](15-many-on-one-square.md) — **a number on a square** | small | a slot is already an entity whose stats a condition can read; it just cannot declare one, so `stat_gain` aimed at a square does nothing. One field on the grid. It has a first honest customer at last — Mage Knight's per-hex terrain cost — but that game is ranked last |
| 17 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | small | free: answers "is turn-based CS fun" for the price of a game file |
| 18 | [07](07-presentation.md) — **an offer of fifty-one** | small | the draft may only look bad because its two buttons are 23px squares — and item 2 is in now, so the second look is available. Decide then whether `layout: "page"` — which already draws the reveal overlay — should serve an offer too |
| 19 | [16](16-the-player-at-this-screen.md) — **a name, and something to say with it** | medium | parked deliberately, and cheaper than it was: [24](24-save-and-load.md) built the store both halves waited on, so what is left is the handshake field and the input surface |
| ~~20~~ | [21](21-lost-ruins-of-arnak.md) — **Arnak** | large | **shipped.** Sixty-one templates, twenty-one zones, no generator, and nothing in `game/` touched — the research's "zero new primitives" held. It found two words the engine has not got: dealing into a *named* cell, and *who* spent a card's exhaust. Both are written up in [arnak/design.md](arnak/design.md) and neither is ranked yet |
| ~~21~~ | `todo.md` — **five verbs that were other verbs** | small | **done.** An audit of the 48 ops found five saying what another already said: `destroy_self` → `destroy:self`, `add_to` → `move_to`, `move_target_to` → `move:target:`, `gain` → `fill:<zone>:`, `return_to` → `move:`. 134 sites across 12 games, 5 generators, 12 test files and both documents. Two were also wrong: `gain` inferred its zone from tags and dropped the card in the hand *silently* when two tags disagreed; and `move` sorted its cards by entity id, so Arnak shuffled its table into the bag and had the shuffle undone in the same breath. `return_to` was checked for a reaction it skipped and skips none — both verbs end in `zones.move_card`, and nothing on the move path raises a verb at all |
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
`destroy:self`, `move_target_to` is `move:target:`. Two of the five were also
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

## A standing decision

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
