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
| [04](04-simulation-games.md) | Cultist Simulator, turn-based | **not started**, unblocked, and smaller than written |
| [05](05-assets-and-repo.md) | Assets, and what the repo carries | **closed** — named assets, remote pictures, a generated placeholder. Art stays in git: that gap was a misunderstanding, and remote art was the real requirement |
| [06](06-schema-and-types.md) | Saying what things are | **closed.** Gap 1 reopened and shipped as [28](28-a-zone-by-its-parts.md); the rest shipped, folded into [17](17-conditions-as-expressions.md), or dissolved |
| [07](07-presentation.md) | Presentation and its gestures | **gaps 1–6, 8 and fill shipped.** Left: a word for where the buttons go, where the stat readout sits, and an offer of fifty-one |
| [08](08-grid-movement-notation.md) | How a piece says where it may go | **chess plays** — castling, check, promotion, en passant. Left: the scope anchor word, and checkmate |
| [09](09-composition.md) | One game out of several files | **paused on purpose**, not unstarted — see the note below |
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
| [20](20-puzzle-strike.md) | Puzzle Strike | **built and playing**, the whole box drafted. Left: a short list of engine features, one buy-count rule to settle, and the per-chip state is in the game file |
| [21](21-lost-ruins-of-arnak.md) | Lost Ruins of Arnak | **researched — zero new primitives**, and the largest content bill of the three |
| [22](22-the-crew.md) | The Crew | **built and playing.** Left: the order tokens and the printed fifty missions |
| [23](23-splendor.md) | Splendor | **built and playing**, two seats |
| [24](24-save-and-load.md) | Saving a game | **shipped** over `net.snapshot`, with no second format |
| [25](25-derived-stats.md) | A stat that keeps itself | **not started, and to be re-read rather than built** — [26](26-an-if-and-a-name.md) answers two of its three blocking questions by construction |
| [26](26-an-if-and-a-name.md) | An ability with an if, and a number with a name | **shipped** — `when` and `computes` |
| [27](27-reactions-and-the-stack.md) | Reactions and the stack | **shipped and in use.** Left: speeds, Magic depth, and an emission suppressor |
| [28](28-a-zone-by-its-parts.md) | A zone by its parts | **shipped whole**, and `supply` is a fourth `status` since. Left: where a destroyed card goes, so nothing has to name the bank |
| [29](29-a-place-to-fight.md) | A place to fight | **shipped whole.** Combat is a zone walked in nine steps, `origin` sends everyone home, and one patrol row made adjacency fall out. Left: resist, which [30](30-things-that-are-true.md) reaches |
| [30](30-things-that-are-true.md) | Things that are true | **mostly built.** `buffs` and `adjusts` both ship, keyed to verbs a game declares so that being interferable is opt-in; the targeting ward already shipped as `receive.needs` and no game uses it. Left: the cost half, which is resist, and which waits only on what the player is shown |
| [31](31-either-of-two.md) | Either of two | **not started.** `or` between conditions, where the list is already the `and`; one decision and about ten lines |

## What to do next

Cheap things that let other things happen come first.

| # | Item | Difficulty | Why here |
|---|---|---|---|
| ~~1~~ | [07](07-presentation.md) — **a card that fills the zone it is in** | tiny | **shipped.** `fit: "fill"` is read outside grids now, and a filled row picks the column count whose cells come out closest to square. It did *not* fix Puzzle Strike's buttons: those are 28px because the zone is 179×46px, which is gap 7's question, not this one |
| 2 | [28](28-a-zone-by-its-parts.md) — **where a destroyed card goes** | small + one decision | `zones.add` already reclaims a card into a supply; nothing reclaims the other way, so a finite box has to name the bank at every site that removes a component. `destroy_card` is the single choke point every path reaches. The decision is what happens when two supplies stock the same kind |
| 3 | [20](20-puzzle-strike.md) — **buying more than one chip a turn** | small | a bug: the buy ability costs `buys: 1` and the phase sets `buys` to 1, so money on the table cannot be spent. **Settled** — "+2 buys" on Always in Control was a transcription error for "+2 piggy", so nothing argues for a ceiling: buy as many as you can afford, at least one, and *End turn* ends the phase. Generator edit, plus that chip's own text. The piggybank rename rides along |
| 4 | [07](07-presentation.md) gap 7 — **a word for where the buttons go** | small | eight games have each invented their own chrome in raw fractions, and an author must answer "where do the buttons go" before putting a button anywhere. The cheap version is a named region resolved in `zones.resize`, one branch, keeping the model that a button is a card in a zone. After item 1, because a filled button changes what a sidebar has to be shaped like |
| 5 | [07](07-presentation.md) — **where the numbers are read, and whether zeros are** | medium, and a word to agree first | `draw_stats` is hard-anchored to the top-right corner in pixels, so any game using that corner has its readout printed over it. Two independent halves: a place, which needs a new field and therefore consent; and zeros, where `badge_zeros` already exists for the card end of the same question |
| 6 | [09](09-composition.md) — **`include`, then a base file of patterns** | medium | worth re-opening with the pause's two findings settled. Four generated games now, whose files are only maintainable *because* of the generator — the argument arriving from a new direction |
| 7 | [25](25-derived-stats.md) — **re-read, not built** | small + one decision | what is left is whether a stat that keeps itself is worth anything *once a formula can sit at its use site with a name on it*. Answer it with The Crew's `weigh` migrated. The one thing a compute cannot do is clamp, and Splendor's pricing rests on `min: 0` |
| 8 | [01](01-boardgames.md) gap 1 — **the square a move passes over** | medium | a jump takes the piece it flies past, and nothing can name that square. Castling-through-check asks for the same word; en passant no longer does, having shipped as `where` |
| 9 | [31](31-either-of-two.md) — **`or` between conditions** | small, and no customer counted | `meets_all` is the one function fourteen consumers share, so whatever spelling wins lands once. Ranked here rather than higher because no card in the corpus is actually blocked on it — find the honest customer first, the way every other track did |
| 10 | [15](15-many-on-one-square.md) — **a number on a square** | small | a slot is already an entity whose stats a condition can read; it just cannot declare one, so `stat_gain` aimed at a square does nothing. One field on the grid. It has a first honest customer at last — Mage Knight's per-hex terrain cost — but that game is ranked last |
| 11 | [04](04-simulation-games.md) — **a Cultist Simulator prototype, JSON only** | small | free: answers "is turn-based CS fun" for the price of a game file |
| 12 | [07](07-presentation.md) — **an offer of fifty-one** | small, after 1 | the draft may only look bad because its two buttons are 23px squares. Look again with item 1 in, then decide whether `layout: "page"` — which already draws the reveal overlay — should serve an offer too |
| 13 | [16](16-the-player-at-this-screen.md) — **a name, and something to say with it** | medium | parked deliberately, and cheaper than it was: [24](24-save-and-load.md) built the store both halves waited on, so what is left is the handshake field and the input surface |
| 14 | [21](21-lost-ruins-of-arnak.md) — **Arnak** | large | needs nothing from the engine. Worth doing when authoring volume is the thing there is appetite for, not when capability is |
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

## Two standing decisions

**[09](09-composition.md) is paused, and the pause is a decision.** The collision
rule wanted is union-with-identical-or-error rather than override, and how far a
path may reach touches the network: a peer's game text parses through the same
door, so an include in it reads local files and forwards them.

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
