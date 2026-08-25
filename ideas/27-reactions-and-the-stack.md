# 27 — Reactions and the stack

**Status:** design, building · **Size:** large, staged · **Depends on:** the one
gap four games now name from four sides — a card played out of turn
([18](18-legends-of-runeterra.md)'s response stack, [20](20-puzzle-strike.md)'s
counter-crash, and row *triggers, spells, the stack* of
[README](README.md:245)).

> *One reaction mechanism in the engine, so every game that lets a player answer
> another player's action — Puzzle Strike's counter-crash, Runeterra's spell
> stack, Magic's stack whole — spells it the same way, instead of each reinventing
> Runeterra's.*

## Built so far

The engine core is in and tested (suite green at every step); no shipped game
uses it yet, so every existing game reads byte-identically.

- **`@event` scope** (`predicate.lua`) — a reaction reads what it answers through
  the one grammar. `tests/integration/event_scope.lua`.
- **Priority, distinct from turn** (`zones.lua active_seat`, `set_priority` /
  `clear_priority` in `actions.lua`) — `active_seat` reads priority over turn, so
  moving priority is the whole of out-of-turn play; the turn stays put.
  `tests/integration/priority.lua`.
- **`reactions[]` schema + Filter A** (`declaration.lua`, `validate.lua`,
  `cards.lua`, `SCHEMA.json`) — authored, validated, indexed by verb into
  `G.react_index`. `tests/integration/reactions.lua`.
- **The suppression brain** (`reactions.lua` — `responders(verb, subject)`):
  Filter A + `where`/`when` match + Filter B (zone/`from` eligibility).
  `tests/integration/react_match.lua`.
- **The response window** (`flow.lua react_step` in `settle`, + `cast` / `react`
  / `pass_react`): a `stack`-tagged zone, LIFO resolution, priority passing, the
  window opening only for a real answer and resolving on all-pass. A deferred
  effect carries its context on its own stack-card entity (deep-copy snapshot
  keeps it across undo). Depth-1 and depth-2 (answer the answer) both tested:
  `tests/integration/react_window.lua`.

- **Announcing** (`emits` on a card *and on a tag*, `cards.emits`,
  `flow.defer_play` / `flow.defer_activation`) — the deferral wiring, and it
  wanted no new concept at all. `emits` is keyed by the **moment**, because one
  card is often two things: `{ "play": "cast", "activate": "ability" }` is a
  spell from hand and a machine on the board, and a reaction to one must not
  catch the other. What goes on the stack differs to match — a card played is
  put up *itself*; a card activated stays where it lies and its effect goes up on
  an event standing for it. Written on a tag, one `"spell": { "emits": { "play":
  "cast" } }` makes every spell in the game answerable. Beside the moment blocks
  rather than inside them, and that is load-bearing: a `play` block is granted
  whole or not at all, so a tag inside `play` would take the card's own action
  away from it. A card that emits nothing is byte-identical to before.
  `tests/integration/emits.lua`.
- **`emit:<verb>[:<action>]`** (`actions.lua`, `flow.emit`) — the non-card event:
  a crash, a summon, a buy. The subject is the acting card, so a reaction reads
  its tags; the action written after the verb is the part that *waits*, which is
  how half an action is deferred when a ravel action list runs to completion.
  Nothing answers → the tail runs in place, so an emit is free to sprinkle about.
  A stack entry with no card to be — an injected `event` def, minted only where
  the game has reactions.
- **`counterspell`** — what a reaction answers does not happen. Named for the
  word every player knows; `cancel` already meant six things, one of them the
  button that abandons a targeting session. **It names no zone**, and that is the
  whole design: a counter that had to know where a spent chip goes would need half
  the rules of every game it appears in.
- **The validator reads reactions** — as abilities (cost, action, phases, target,
  compute, `when`), plus `where`, `from`, and the verb: a reaction answering
  something nothing in the game emits is now reported rather than silently dead.

**Field name landed:** `forced: "optional" | "mandatory"`.

- **The input surface** — `flow.pending_event()` and `flow.usable_reactions()` are
  the two queries an interface asks, beside `can_react` / `sole_reaction` (the
  `can_activate` / `sole_ability` of a window). All three interfaces reach them:
  the CLI's `r <n>` / `p`, the GUI's top bar with a Pass button and a lit card that
  answers on click, and the debug server's `react` / `pass` / `pending`. A card
  answering two ways opens the ordinary chooser — `mint` writes menu cards for
  reactions too, and the entry carries `stats.reaction` because the two indices
  point into different lists. `net` wraps `react` / `pass_react`, so a reaction
  publishes and a networked reactor is allowed while the turn player is refused.
- **A window locks everything else** (`can_play`, `usable_abilities`,
  `can_activate_zone`) — priority was the whole out-of-turn unlock and it unlocked
  *everything*: the reactor could empty their hand into the turn player's turn.
  `reactions` is ravel's only spelling for a card played out of turn, so the lock
  costs nothing that should have worked. `tests/integration/emits.lua`.
- **`forced: "mandatory"` fires** — `fire_forced` puts a matching one
  straight onto the stack as that seat, nobody asked. Run inside `settle` rather
  than through `M.react`, which would checkpoint and re-settle. One thing it will
  not do on its own: a forced reaction that has to be *aimed* is a question after
  all, so it is offered like any other.
- **Filter B needs no field at all.** It was going to be a `prompt` enum,
  `possible` / `certain`. It is not: the loose reading is the only one worth
  having, because a game that hides nothing has no secret zone for the loose read
  to widen, so it already gets the exact answer. The setting could only ever have
  been used to *turn the leak on*.
  `"possible"` (the default) treats every zone the opponent cannot read as one
  pool: a hand and the bag behind it are the same place from across the table, so
  the window opens on what is publicly possible and its appearance says nothing.
  `"certain"` reads the real location and skips. What the asked seat is then
  *offered* is exact either way — `usable_reactions`, `M.react` and `fire_forced`
  all pass `strict`, since a question that was a guess must not become a lie to
  the player's face. Where nothing is hidden the two agree, which is why most
  games never write the field. `tests/integration/emits.lua`.
- **Nothing on the stack is a game card** — every entry is an `event` record
  standing for something announced, and the card that announced it stays where the
  play found it. This replaced putting the played card up itself, which was the
  riskiest thing in the design: `resolve_top` had to reason about whether a card's
  own action had moved it (a check that had already eaten every card whose play
  ends in `move_to`), a reaction had to mint a fresh copy of itself to get back
  into a bag, and countering meant destroying a real game object. All three
  disappear. Records also mean an id is the only handle anything holds, which is
  what keeps undo's deep copy honest.
- **`spent`, on the play block and on a reaction** — where the card goes once its
  play is over, **however it ends**: resolved, or countered before it ever ran. An
  MTG sorcery goes to the graveyard either way and a Puzzle Strike chip to the
  table either way, and neither the action list nor the counter should be the one
  that remembers. Opt-in, so a card that does not say it is unchanged. Run as the
  card's *owner* rather than as whoever is up, since a counter resolves while the
  answering seat holds priority and "mine.table" has to mean mine. It replaced 54
  hand-written `move_to` lines in Puzzle Strike alone.
  - Tags grant a whole `play` block or none of it, so `spent` cannot come from a
    tag and every Puzzle Strike chip writes its own. **Settled: leave it that way.**
    Editing a block rather than granting one is a different act and would want a
    different word for it — `"play_merge": { "spent": ... }` — rather than
    quietly making `play` mean both. Revisit only if the repetition starts to hurt.
- **One card answers one announcement once** — the stack no longer takes the
  reaction out of the hand it came from, so without this a reaction that moves
  itself nowhere answers the same record forever. Tracked per record
  (`re_answered`), which is the right granularity: the seat may still answer again
  with a *different* card.
- **Priority is released when nothing holds it** — a phase interjected mid-answer
  (an offer, a shopping trip handed to the seat that just reacted) is up because
  *they* are, so the stack emptying does not hand their phase to the turn player.
  One seat stat stays the single answer to "who is acting"; `phase.depth() > 1` is
  the whole test. Two rules fall out: the stack **suspends** under an interjection
  (it is part of resolving the record that opened it, so the turn player's deferred
  effects must not land mid-answer), and the window lock **lifts** inside one
  (a phase pushed for this seat is a hand-over, not a window — playing in it is
  the point). `tests/integration/interject.lua`.

- **The first customer** (`puzzle_strike.json`) — the four crashes
  end with `emit:crash`, a `pending` zone tagged `stack` holds what is announced,
  and Bubble Shield's ongoing half answers. Two decisions carried it: the chip
  `transform`s into `bubble_shield_up` when laid out, so the two halves are two
  cards and `from` never has to tell `ongoing` from `hand`; and the negation is
  *remove a gem already landed* rather than *prevent one arriving*, which is
  free because defeat is only read at the end of your own turn
  (`puzzle_strike.json:334`) and gems never auto-combine. That cheat is what
  lets the emit carry an empty tail — nothing waits, so the one-action limit on
  `emit`'s tail never bites. `tests/integration/puzzle_strike.lua`.

- **Rigorous Training** — an opponent's expensive buy hands *you* a shopping trip.
  The bank hands whatever lies in it a `buy` announcement through `applies`, so the
  eighteen piles say nothing about being answerable and one tag says it once — and
  it un-says it the moment a card leaves, for free. The answer interjects a phase.
  What it did **not** need is a way to filter a shop by price: the allowance is
  handed over as *money*, so the ordinary price of every pile does the gating.
  That is why `options` never grew a `where` filter, which was the plan.
  It answers from **hand** and is spent to the discard, like any other reaction —
  it is not laid out. The trigger is the *colour*: any purple bought (Combine,
  Crash Gem, Double Crash), not a price threshold. The three piles carry `purple`
  themselves, since a pile of purple chips is purple; the style merge is by key and
  `stack` sets only badges, so they compose.
- **Every chip carries `price`** — it was only ever on the eighteen bank piles, and
  it is not a duplicate of `value`: a 2-gem costs 3 and counts 2. Note `price` is
  still read by *nothing* in the rules — each pile duplicates the number by hand
  into its cost block. Making the cost read the price would kill eighteen
  duplications, but cost values go through `plan`, and `can_afford` is the hot
  legality path (asked per board card per frame, on a browser build with no JIT).
  Left alone deliberately.

**Left:** Dragon Form, and nothing else in Puzzle Strike. `red` emits `attack` from
the tag — the printed rule is that every red chip is an attack, so it is written
once on the colour rather than on ninety cards — and Bubble Shield's reaction half
is four lines on the back of it: `to: "attack"`, `counterspell`, `spent`. No colour
had to reach the event after all, because the tag that emits is the colour.
**Dragon Form** ("your purples can't be reacted to") is deferred: it needs an emission suppressor keyed on the
emitting seat, which is genuinely new surface — distinct from `applies` (zone-local)
and from `where` (event-local), and not reachable by making Dragon Form react to its
own purples, since `react_step` skips the actor's own seat and countering is the
opposite of what it wants. Under the record design a suppressed emit would simply
create no record, so the card resolves as in a game with no reactions at all.
AUTHORING.md is still silent on reactions; SCHEMA.json carries the full reference.

**`destroy` takes a count** (`destroy:<scope>[:<n>]`), which is what Stone Wall
needed and what repeating the line could never give: how many is the size of the
crash, known only as the game runs. It takes the same amount grammar every other
count does, so this was letting one op read an argument its siblings already read
rather than new vocabulary. Which ones, where there are more than asked for: the
earliest, unless the scope says `random` — most pools are identical cards and
spending randomness on a choice that does not matter costs a reproducible game for
nothing.

---

## The core idea: invert the dependency

The instinct to write "this card can be countered by X, Y, Z" onto every
counterable card is the wrong direction. A fireball must not know what answers
it. The fix is the observer shape: **the thing acted on emits a generic,
self-describing event; each reaction declares which events it answers.** Fireball
never mentions flame-counter. Flame-counter says *"I answer a `play` whose subject
is tagged `fireball`."* The engine scans reactions for a match, never the reverse.

This costs no new vocabulary, which is the whole reason it fits here (invariant 6,
`ARCHITECTURE.md`). The engine already has the two languages it needs:

- **tags** say what a card *is* (`fireball`, `creature`, `gem`, `red`) — already
  the basis of targeting, counting and styling.
- **predicates** (`[<fn>:]<arg>[@<scope>]`, `predicate.lua:68`) say conditions.

So an event is *"a card carrying these tags did verb V,"* and a reaction matches
it with an ordinary predicate over a new `@event` scope. All the conditional
"reduced reaction" logic — react to a summon with a summon-counter, to a fireball
with a flame-counter, and neither to the other — falls out of the existing
grammar with nothing bespoke.

## What the engine is missing today

Diagnosed already, from both sides, and this file agrees with the diagnosis:

1. **Out-of-turn play is refused.** `reachable()` (`game/flow.lua:47`) gates every
   play and activation on `owner == active_seat`. A reaction *is* a card acted on
   out of turn — the one hard blocker, named at `ideas/18:517` and `ideas/20:160`.
2. **There is no "when something else happens" moment.** Abilities fire only from
   a player click or a phase's `activate_zone`. `ideas/18:431` names the absent
   moment.
3. **No stack, no speeds.** Greenfield.

Everything adjacent already exists: the pass/priority idiom (`lor.json:182-198`
plus the `pass_button` card at `lor.json:399`), `set_active_seat`
(`actions.lua:850`), the ordered zone walk (`activate_zone`, `actions.lua:414`),
and the case-table-is-a-zone pattern (`ideas/20:331`). This work is mostly
combining them, plus the one genuine unlock in (1).

---

## The design, in ravel idioms

### 1. Events — the emit side, generic and tag-described

An event is `{ verb, subject (card ids), actor_seat, payload }`. It is emitted
when a reactable thing happens; it describes itself entirely through the tags the
subject cards already carry, so the emitter never names a reactor.

- `flow.play_card` emits `("play", card)`; `flow.activate` emits `("activate", card)`.
- A new `emit:<verb>` action lets content raise its own: `emit:summon`,
  `emit:crash`, `emit:buy`. Puzzle Strike's crash action ends `emit:crash`; a
  Magic creature entering ends `emit:summon`.

**Events are queued, serviced by `settle`, never mid-action.** A ravel action
list runs to completion synchronously — you cannot pause one to open a window. So
`emit` enqueues; `settle` (`flow.lua:302`) drains the queue at its stable points,
which is exactly where invariant 3 says after-an-action work belongs. This also
happens to be *correct*: it is Magic's own rule that triggers wait for the next
priority rather than interrupting a resolution, so we get re-entrancy safety and
rules-faithfulness from the same decision.

### 2. `reactions` — the "in response to X" syntax

A new card moment, a **list** (like `abilities`, `declaration.lua:77`, not a
single block like `play` — a permanent can answer several different events, and
Runeterra lets you answer one event more than once). Each entry:

```json
"reactions": [
  {
    "to": "play",
    "where": ["tagged:fireball@event >= 1"],
    "when": ["act_blue@mine.player >= 1"],
    "forced": "optional",
    "from": "hand",
    "cost": { "act_blue@mine.player": 1 },
    "action": ["destroy:event", "move_to:mine.table"]
  }
]
```

- **`to`** — the verb answered.
- **`where`** — a predicate **over the event's subject**, via a new `@event`
  scope added to `predicate.entities_in_scope` (`predicate.lua:142`), beside
  `@self` and `@target`. This is the whole trick: every conditional match reuses
  the one grammar. `tagged:fireball@event`, `value@event <= 3` (Puzzle Strike's
  "4-gems are immune to counter-crash", `ideas/20:77`), `tagged:creature@event`.
- **`when`** — a predicate over the *reactor's own* state (can I pay, is it legal
  now). Same distinction as everywhere: `where` is about the event, `when` is
  about the reacting card, `needs` would be about the player.
- **`forced`** — an enum, `optional` (prompt the controller; they may decline)
  or `mandatory` (fires on its own — Magic's mandatory triggered ability). An enum
  and not the boolean `may` the first sketch had, because "you may" and "it must"
  are both triggered abilities and the difference is the whole of what this says.
- **`from`** — where the reaction is performed from, which decides what "reacting"
  *does* (see the third addendum). Default is the sensible one for the zone the
  card sits in.
- **`cost` / `action`** — as any moment.

The dependency is inverted exactly as wanted: the reactor names the event; the
event names nobody. The two examples stay disjoint for free — `to: "play"` +
`fireball` never fires on a `summon`, `to: "summon"` + `creature` never fires on
fireball's `play`, "not vice versa" costing nothing.

### 3. The stack — one mechanism, three depths

A `stack` zone holding pending effects, resolved last-in-first-out. Each entry is
a card carrying its deferred `action` and bound context (`@event`, `@target`) —
a card is the unit of everything, so this is more of the same, not a new kind of
state.

The response window is a **phase loop** driven by `settle`, reusing the pass
idiom Runeterra already ships: emit → `settle` pushes a `respond` phase → priority
passes seat to seat → a reaction pushes onto the stack and *re-opens* the window
→ two passes in succession pop-and-resolve the top → repeat until the stack is
empty, then resume. That is Magic's algorithm and Runeterra's, and the "two
passes end it" routing is already at `lor.json:187`.

**Deferral is opt-in and local.** Today `play_card` runs `on_play` at once. In a
game with a stack, playing a *stacked* card moves it to the stack and defers its
action to resolution; an *immediate* card (Runeterra's Burst/Focus) keeps
today's run-now behaviour. Games with no stack zone (chess, Splendor, Puzzle
Strike's core loop) are untouched.

### 4. Priority, distinct from turn — the `reachable` unlock

Do **not** rotate the turn seat to let a reaction happen. Introduce a **priority**
holder (a stat on the system card, beside `turn`). Outside a window,
`priority == turn`, so every existing game is byte-identical. During a window,
priority rotates; `reachable()` asks priority, not turn. `mine`, cost payment and
the `plays` counter follow priority for the duration, so a reactor pays from
their own pool.

The reason not to reuse the turn seat: Puzzle Strike's loss condition is "checked
at the end of *your own* turn" (`ideas/20:132`) and Magic is thick with
"until end of turn" effects. Turn ownership must stay put while a reaction runs
inside it. A separate priority holder is the minimal correct generalisation, and
it stays in the snapshot for free because it is a stat on a card already there.

---

## The three addendums

### A. Reacting as the stack resolves (Magic)

Covered by the same queue: **a resolution is itself an event.** Popping the top
and running its action can emit — its own `resolve`, or the concrete `damage` /
`dies` / `summon` its action raises — and those enqueue, so `settle` opens a fresh
window before the next pop. Players get priority after every object resolves,
which is Magic's rule verbatim, and it needs nothing past "resolution emits like
anything else." A triggered ability that fires from a resolution goes on the stack
*above* what is left, because it is enqueued after and the stack is LIFO.

### B. Reacting to one thing more than once (Runeterra)

The window does not close after a single reaction — it re-opens, priority resets,
and only all-players-pass-in-succession ends it. There is **no per-event "already
reacted" latch**; the same trigger may match an event repeatedly, bounded only by
its own `cost`/`when` (you run out of mana, or the condition lapses). A `forced`
static reaction on the board may fire every time its event recurs, arbitrarily
often. This is a thing to get right by *not* building the obvious dedup.

### C. A reaction can be a play, an activation, or a static board effect

`reactions` is a subscription; **where the card sits plus `from` decides what
answering it means:**

- **`from: "hand"`** (a reaction card, e.g. Puzzle Strike's counter-crash chip):
  answering *plays* it out of turn. The card becomes the stack object and is
  consumed on resolution, like a spell.
- **`from: "board"` as an activation** (an in-play card with a usable reactive
  ability): answering *activates* it out of turn. The card stays; an effect goes
  on the stack. Mechanically this is `usable_abilities` (`flow.lua:851`) offering
  a matching ability to the priority seat during a window — an ability whose
  `phases` admit the `respond` phase.
- **`from: "board"` as a static/triggered effect** ("whenever X happens, this
  reacts with Y" — Magic triggered abilities, Runeterra on-board triggers): the
  subscription auto-evaluates for cards **in play**, not only in hand. `forced`
  ones fire on their own; `optional` ones prompt. The card stays put; only its
  effect is stacked.

So the engine scans, for a given event, every `reactions` entry on every card the
priority seat controls whose zone + `from` make it eligible. Played reactions come
from the hand; activated and static ones from the board.

**Layout.** A window that surfaces a board reaction must not be a modal overlay
that covers the very card it is asking about. This is why the response window is a
**player_input phase** (in-place highlighting, the way `declare_block` lights up
benched units, `lor.json:65`), **not** an `options:` overlay. The player sees the
board with the eligible cards lit and a pass button, and clicks the card where it
lies. The overlay-covers-the-card problem is sidestepped by choosing the phase
form over the offer form. Anything that genuinely needs an offer (choose one of
several reactions on one card) reuses the existing chooser, which is small.

---

## Not prompting for everything (the Arena problem)

Two filters, coarse then fine.

### Filter A — static, load-time, every game

Precompute a `react_index` at load: for each `verb`, the set of reaction
signatures `(required tags, legal phases, which seats could hold one)` across all
`card_defs`. Then:

- If **no card in the game** reacts to verb V, V is not even emitted. Plays, buys,
  moves — the 95% of actions nothing answers — open no window, ever.
- If some card reacts to V, an event opens a window only when its subject's tags
  are compatible with some signature.

Sound and cheap: computed once, and it alone kills the over-prompting. This is the
"scan the whole card list; if nothing reacts to X, X never asks" the objective
named.

### Filter B — dynamic, per-event, tightened per game

Before opening a window for seat S, ask *"could S have a matching, playable
reaction right now?"* One precision to keep straight:

> **The engine has full information; a player has only public inference.** Hidden
> hands are renderer-only in ravel — "this hides, it does not protect"
> (`zones.lua:261`, `net.lua:18`). The engine *could* read S's real hand and skip
> with perfect tightness — but if the *appearance of a prompt* is driven by S's
> secret hand, the prompt itself leaks that S can react.

So Filter B is a per-game policy:

- **Public-inference (leak-free, the Puzzle Strike default).** Decide from
  **public information only** whether it is *possible* S holds a match. In Puzzle
  Strike this is exactly determinable: a player's *possible* chips are public —
  the fixed character trio plus every visible buy — so if every copy S owns of
  every matching reaction chip is visibly sitting outside hand+bag (discard,
  table, ongoing, void), skip. That is the objective's "all they have are in the
  graveyard" and "none are in the bank to buy," and it leaks nothing because it
  reads only what both players can see. Expressible over the `@everywhere` scope
  (`ideas/20:268`) against the public zones.
- **Exact (leaky, fine for open-information games and much of Magic).** Let the
  engine consult S's true hand and skip whenever there is genuinely no reaction.
  Tighter, but the prompt's presence is informative — acceptable where reaction
  potential (untapped mana, cards in hand) is already observable.

*Landed differently, and better:* Filter A always on, Filter B always
public-inference, and **no setting for the exact reading**. A game with nothing
hidden has no secret zone for the loose read to widen, so it lands on the exact
answer by itself — which leaves the switch with only one thing it could ever do,
turn the leak on in a game that hides something.

---

## How it lands per game

- **Puzzle Strike:** the counter-crash rule is **mutual annihilation**, not two
  independent halves: the smaller of the two crashes is struck off both, and only
  the remainder arrives. Crash 3 into a counter of 4 and the attacker takes 1, the
  defender none, both having spent their gem. A counter announces itself with the
  remainder in flight and can be answered again, and **a broken 4-gem cannot be
  answered at all** — which is what ends every chain, not a depth limit. A Double
  Crash that breaks a four shields the gem beside it, because the rule reads the
  biggest gem broken rather than the size of the crash.

  Built with no new engine surface. `stat_damage` already clamps at a stat's
  minimum, so two subtractions through one scratch stat give `max(0, a-d)` and
  `max(0, d-a)` — the annihilation, exactly. Gems still land the moment they are
  sent and the counter bounces them: destroying and re-adding 1-gems is lossless,
  so nothing has to be held in flight and `emit`'s deferred tail is not needed.
  The biggest gem broken rides on its own hidden stat because the crash event's
  subject is the *chip*, so `value@event` reads the wrong thing.

  The one wart: "a four cannot be answered" is a fact about the crash, but with no
  conditional action there is nowhere to say it once, so it is a `when` repeated on
  each of the three chips that answer a crash. A fourth would have to remember.
  Depth-1 stack otherwise.
- **Runeterra:** the four speeds collapse to two booleans, as `ideas/18:79` found —
  playable-during-combat? and answerable-before-it-resolves? Burst/Focus =
  immediate (run now, no window); Fast/Slow = stacked (defer + window). Keep this
  reaction stack separate from the positional strike, which already resolves as
  `activate_zone:battle:by_column` (`lor.json:221`) and must not be forced LIFO.
- **Magic:** the same machinery at full extent — arbitrary depth, priority after
  every object, `forced: "mandatory"` abilities auto-stacking, state-based actions
  re-checked between resolutions (`settle` already fires end conditions each loop).

---

## Build order

Smallest customer first, mirroring the repo's prerequisite chain (`ideas/18:517`):

1. **`@event` scope** in predicate — the primitive every match reads through.
2. **Priority, distinct from turn** + `set_priority` + relaxed `reachable` — the
   out-of-turn unlock, nothing else.
3. **`reactions` schema** (declaration + validate) + **Filter A** (`react_index`).
4. **`emit` + the response window** in `settle`: stack zone, LIFO drain, the
   pass/priority loop.
5. **Puzzle Strike counter-crash** as the first real customer + Filter B
   public-inference, with a soak test.
6. **The general stack + speeds** for Runeterra Fast/Slow.
7. **Magic-only depth:** triggered-ability ordering (APNAP), targeting at cast vs.
   resolution.

## Deliberately cut, for now

- **Replacement effects** ("if it would die, exile it instead"). These do not use
  the stack; they rewrite the event before it happens. Magic needs them; Puzzle
  Strike and Runeterra do not. Named here so the cut is a decision, not a
  surprise.
- **APNAP trigger ordering** and cast-time vs. resolution targeting — Magic depth,
  parked behind a working two-player stack.

## Open questions

1. **A chip nobody can buy has no price**, so trashing a character chip to
   Rigorous Training allows 2. *Settled: correct as it stands* — character chips
   are dealt rather than bought and have no price to read.
