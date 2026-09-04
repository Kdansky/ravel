# 02 — Between two states

*From the observation that most of the animation in the engine plays after the
thing it is animating has already happened.*

**Stage 1 shipped. Stage 2 — the presented state — is what is left.**

A click runs the rules to completion in one frame. `flow.play_card` mutates,
`flow.settle` runs the automatic phases behind it, and the function returns with
the board in its next state. Only then does the renderer notice, on its next
frame, and start tweens toward wherever things ended up. Everything in between —
the order the cards moved in, the intermediate positions, the card that was
destroyed on the way — never existed for longer than one call stack.

**The ask is that a move becomes a short film rather than a cut.** From the state
before a click to the state after it, every visual step is recorded in order,
then played back one beat at a time while input is held; the board the player is
looking at only becomes the new state when the last beat lands.

## Why this is cheaper than it sounds

Most of the machinery is already built, and built the right way round.

| Piece | Where | What it already does |
|---|---|---|
| a full state, deep-copied | `entity.snapshot` / `restore` | undo's checkpoint. `flow.checkpoint` (`flow.lua:224`) already takes one **before every action** — state A is recorded for free, today |
| a visual layer that touches nothing | `anim.lua` | tweens keyed by card id, read through one function. The rules cannot see it and headless never loads it |
| one chokepoint for a card's rect | `anim.visual_place(id, rest)` | the renderer asks it for every card it draws. Whatever answers that question controls what is on screen |
| a delay queue | `fx.after(delay, fn)` | already spaces bursts out so a run of hits reads as a run |
| a hint of ordering | `actions.on_act(id, ordinal, step)` | the only signal the presentation has that a zone resolved card by card |
| a state diff | `net.make_delta` / `diff_ents` (`net.lua:210`) | whole-entity replacement between two snapshots, already tested over the wire |

The engine has been keeping presentation out of the rules since the beginning,
and the bill for that discipline is now the thing being collected.

## What is actually missing

**One: nothing records the order.** `render.sync_places` (`render.lua:1893`)
infers movement by diffing the layout against `c.place` at frame boundaries. That
is a good trick and it is why animation works at all today, but it is a diff of
two *frames*, not of two *steps*. A card that goes deck → hand → discard inside
one click tweens deck → discard. Ten cards that moved in a strict order all start
on the same frame. The information was never lost, because it was never taken.

**Two: the renderer draws the live registry.** So a destroyed card is gone from
`ALL` and there is nothing left to fly out; a stat snaps to its new number while
its card is still in the air; a hand's count updates before the card reaches it.
Deferring only *positions* would fix the first half of the problem and leave the
second half visibly broken, so it is not worth building as a stop.

## The design: a stage

A new module, `stage.lua`, sitting beside `anim.lua` on the presentation side of
the line — no engine module requires it, and deleting the file leaves the game
working with the pop it has today.

It holds two things:

**A queue of steps.** A step is a snapshot of the whole state plus a note about
what changed to produce it: `{ ents = <snapshot>, what = "move", card = 17 }`.
The rules push one every time something visible happens. Playing a step means
swapping the presented state for that snapshot and starting whatever tween or
burst the note asks for.

**The presented state.** While the queue is draining, this is the snapshot of the
step currently playing. When it is empty, it is the live registry, and everything
behaves exactly as it does now.

The drawing path then reads `stage.get(id)` and `stage.each(kind)` instead of
`entity.get` and `entity.each`. That is **21 sites in `render.lua`**, and the
derived questions the renderer leans on — `zones.visible`, `zones.browse_order`,
`card_places` — have to be answered against the same state.

**Because each presented state is a real state, everything comes along for free:**
stats, hidden hands, pile counts, destroyed cards, the banner, the summary. There
is no second description of the board to keep true, which is the trap
[24](24-save-and-load.md) named when a save turned out to be a network message.

### Where the steps come from

Emission goes at the bottom, not at the call sites of the bottom, so nothing can
move a card without saying so:

| Site | Step |
|---|---|
| `zones.move_card` (`zones.lua:479`) | a card changed zone. `move_top` and `place_in_slot` both funnel here |
| `zones.destroy_card` (`zones.lua:589`) | a card left the board. **The one that needs the presented state**, because the entity is emptied in place |
| `zones.add` (`zones.lua:221`) | a card arrived from a supply |
| the stat setter (`actions.lua:234`) | already calls `on_stat_change`; it gains a snapshot |
| `actions.on_effect` (`actions.lua:895`) | already a hook, already the right shape |
| `zones.shuffle` (`zones.lua:658`) | one step, not `n` — a shuffle is one gesture |

Every one is a `nil` hook by default, so **headless discards all of it by not
having anything to discard**: `tests/run.lua`, `play.lua` and `check.lua` never
set the hooks, the branches never fire, and the rules run at the speed they
always did. This is the same seam `save.lua` and `net.lua` already sit on.

## Build order

**Stage 1 — steps, played through the tweener you have. Shipped.**
`game/stage.lua` records a run, seals it into a queue of beats, and lets one card
go at a time. Positions sequence; numbers ride the same queue; the rest still
pops. Nothing in it has to be undone by stage 2.

**Stage 2 — the presented state.** Route the drawing path through `stage`. The
whole picture then lags, and a destroyed card can be animated out because it is
still in the snapshot being drawn.

**Stage 3 — pruning.** Two things are already dead and left standing on purpose.
`actions.on_act` had the only ordering signal the presentation owned, and the
queue replaced it — it keeps its `step` argument until stage 2 has said whether
it wants that for grouping. `fx.after` and the `pending` list behind it are a
hand-rolled queue with no callers left; stage 2 is the moment to find out whether
anything still wants a delay that is not a beat.

## What stage 1 actually did, and where it differs from this plan

- **`anim` grew a pin.** `hold`/`release`, and `move` on a held card keeps the
  flight it was asked for instead of refusing it. The renderer is untouched:
  `visual_place` was already the one question it asks, and pinning is a new
  answer to it. `sync_places` did not change either — a held card's target
  arrives through the same call every other card's does.

- **A conjured card now flies out of the bank that stocks it.** This was the
  worst gap stage 1 shipped with, and Puzzle Strike found it: **a crash is not a
  move**. `fill:enemy.gem_pile:gem_1:N` conjures the gems and a separate
  `stat_damage:stock@bank.gem_1:N` docks the bank, with nothing in the engine
  linking the two — so the most important event in the game happened in no time
  at all, because the gems had never been anywhere to travel from. `zones` can
  now answer `supply_of(def_key)` (a supply keeps one real card per kind, which
  is the rect), the renderer uses it as a last-resort origin, and `add` joins
  `move` as a step a card can be held for. Gated on the card being held, or
  every chip in the box would fly to its seat the moment a game loaded.

  **The asymmetry is deliberate, and `fill` is not a workaround.** A supply keeps
  one entity per kind and the other sixty-three gems are a number written on it,
  so there is no card to move out — taking one would move the card that *is* the
  stock. ARCHITECTURE's "Supply zones" section says so, `validate.lua:982`
  refuses `draw_from` on one, and `targeting.candidates` drops supply cards
  outright, which is the promise that makes one-card-for-a-stock safe in the
  first place. Buying spells it the same way the crash does: `stock@self: 1` as a
  cost beside a `fill`.

  **What is actually missing is that the two halves are two statements.**
  `fill:enemy.gem_pile:gem_1:N` and `stat_damage:stock@bank.gem_1:N` are separate
  lines with nothing tying them together, so the engine cannot know they are one
  event — which is why the gems had no origin, and why a game file can put the
  two out of step and only find out by counting. One op that takes N of a kind
  out of a named supply and puts them somewhere would make the origin a fact
  rather than a guess, make the halves impossible to desync, and let the
  validator bound the box. That is written up as [03](03-a-move-out-of-a-stock.md)
  and it is a new word, so it waits on consent; until then the presentation
  guesses, which is the right layer to guess in — a wrong guess draws a wrong line
  and changes no rule.

- **`destroy` and `shuffle` are emitted and cost no beat.** They are in
  the queue, in order, ready for stage 2 — but a destroyed card is already gone
  from the drawing and a conjured one has nowhere to come from, so weighting them
  would buy nothing but dead air. Only `move`, `stat` and `effect` have a gap.
  A card moved into a stock fires `destroy` and `add` rather than `move`, and the
  silent half keeps that from reading as two events.

- **A stack had one place and gave it to one card, and both ends of that were
  wrong.** Leaving: a card off the top of a pile had no rect to set off from, so
  the commonest animation in a card game — the draw — appeared in the hand rather
  than travelling to it. `sync_places` now falls back to the *origin zone's*
  rect, which `move_card` already records on every move as `origin_zone_id`.
  Arriving: a chip discarded under three others is buried the instant the rules
  run, and with nowhere to land it never travelled at all — it stopped existing
  in the hand it left. Every card in a stack now takes the pile's rect, and
  `draw_animated_cards` walks the whole pile rather than its top: what is still
  in the air is not in the pile yet. Only the top is drawn at rest and only the
  top answers a click, which `zones.card_at` said already and still says.

- **A card in the air now shows its back when it should.** Flight was a hole in
  what a zone promises to hide — `draw_flying_card` drew a face whatever it was
  sailing into. It was reachable before and unmissable once a whole hand can be
  seen crossing the table into a face-down pile.

- **One card, one *moment*, not one flight.** A card that moved once flies. A
  card that moved several times in a run waits where it stood and is then simply
  somewhere else: a chip discarded, shuffled back into the bag and drawn again
  would otherwise sail from the board to the hand, which is a trip it never made
  and, worse, shows the result of a shuffle nobody may see. It cuts — no line
  drawn, nothing claimed — at the beat of its *last* move, so it stays where the
  player last had it for as long as it honestly can. **Stage 2 is what replaces
  the cut with the truth**: the chip goes to the discard, the pile is shuffled,
  and a card comes off the bag face down.

- **The debug server arms a run too.** A command is an input like any other, and
  without it `screenshot` could only ever catch the aftermath.

- **What still pops:** everything that is not a position. A stat lands on its
  beat but its *number* changed the moment the rules ran; a flipped card, a pile
  count and the banner are all read live. That is the whole of stage 2 and the
  reason it is worth doing.

## The three that bite

**Input.** Blocking is a guard at the top of the four `love.*` handlers, which is
trivial and wrong on its own — a swallowed click makes the game feel broken.
**A click during playback speeds the sequence up rather than skipping it**: a
rate multiplier on the queue's clock, raised on each click. It is a multiplier on
one number and it keeps the player's causal thread intact, which skipping does
not. If it turns out that a 4× tween looks bad rather than fast, fall back to
draining the queue and snapping to the final state — but try the multiplier
first. Either way, a hard cap on total sequence length, so no cascade can wedge
the board.

**Networking.** `net.apply_full` and `apply_delta` hand you a whole state with no
step list, because the moves that produced it were made in a process this one was
not running. So a remote turn has no sequence, and inventing one is not free.
**Keep `render.sync_places`' frame diffing as exactly that fallback** — it is
already the right code for the job, and the answer to "how do we animate a state
that arrived from nowhere" is "the way we animate everything today".

**Undo.** It must not replay anything: undoing into a state and then watching it
assemble is a lie about what happened. Jump straight there and drop the queue.
`flow.on_reset` (`flow.lua:25`) is already the hook that clears visual state and
already fires from `M.undo`.

## Decisions made

- **The full version, not deferred positions.** Half the effect for most of the
  work, and a board where the cards lag but the numbers do not is worse than one
  where nothing lags.
- **Snapshots, not patches.** `net.make_delta` exists and could store a step more
  cheaply, but a sequence's snapshots are transient — they live for the length of
  one click — so the storage saving buys nothing and costs a second thing to keep
  true. Revisit only if the per-step deep copy measures badly on the largest
  board, which is Arnak's twenty-one zones.
- **Speed up on click, skip only if that looks bad.**
- **The emission hooks are engine-internal.** No new word in the game file, so no
  consent needed: a game cannot ask for an animation it does not already ask for
  through `effects`.

## Traps, before they are paid for

**Every derived answer must come from the presented state.** `zones.visible`
compares a zone's seat against `M.watching()`; if that reads the live registry
while the cards are drawn from a snapshot, a hidden hand reveals itself a beat
early. Same for `browse_order` and for `card_places`. The rule is that nothing on
the drawing path reads `entity` directly — which is also how it gets enforced,
by there being no import.

**`c.place` is written onto live entities by `sync_places` and read back by
hit-testing.** During a sequence, layout comes from the snapshot, so `place` lags
and hit-testing is wrong — harmless, because input is blocked for exactly that
window, but it must be recomputed on the frame the queue empties rather than left
to the next move.

**A card with no rect anywhere still pops.** The origin-zone fallback covers a
pile, which was the case that mattered; a card conjured from nothing has no
previous position by definition and appears. Stage 2 answers it by not drawing
the card until its beat.

**A card that moved twice cuts, and a cut is still a jump.** It is an honest one
— it asserts no path — but a player watching a chip leave the board and reappear
in hand is watching the shuffle happen with the middle removed. This is the
sharpest argument for stage 2 that the corpus has produced, and it came from
playing Puzzle Strike rather than from reading the code.

**A cascade can be long.** `settle` runs up to 64 phase transitions and an
`each_seat` loop inside one of them can move a lot of cards. Cap the recorded
steps and coalesce the tail into one, rather than making the player watch an
upkeep resolve card by card.

**A step is not an action.** One action can produce several steps and several
actions can produce none. Do not try to make the queue line up with the rules'
own structure; it is a list of things a player would see, and that is all.
