# 02 — Between two states

*From the observation that most of the animation in the engine plays after the
thing it is animating has already happened.*

**Stages 1 and 2 shipped.** A click is recorded as it happens, sealed into a
queue of beats, and played back one beat at a time — and each beat is a whole
state, so the board the player is looking at is one the rules have already left
behind. `game/stage.lua`, tested by `tests/integration/stage.lua` and exercised
end to end by `tests/render_smoke.lua`.

The mechanism and its cost are in [ARCHITECTURE](../ARCHITECTURE.md)'s
presentation section. What is worth keeping here is what the two stages cost to
find out.

**A step is a whole state, not a description of a difference.** `net.make_delta`
existed and would have stored one more cheaply, but a run's snapshots live for
the length of one click, so the saving bought nothing and cost a second account
of the board to keep true. Being real states is why numbers, flips, pile counts,
hidden hands and a destroyed card all came along without being asked for.

**The swap is what made it small.** `entity.restore` already pointed the registry
at another table, so presenting a state is a swap in and a swap back around the
frame. The alternative — routing 26 call sites in `render.lua` through a
`stage.get` — would have left every derived answer (`zones.visible`,
`browse_order`, `card_places`) to be found and routed separately, and a missed
one reveals a hidden hand a beat early.

**Stage 1's pin was the right thing to throw away.** Holding a card where the
player last saw it was how one state could be shown in an order; with a state per
step the sequencing is inherent — the card is simply still in its old zone — so
`anim.hold`/`release`/`cut` went with it. The **cut** went too, and that was the
point: a chip discarded, shuffled back in and drawn again used to wait and then
be somewhere else, because one state has no honest flight to offer. It now makes
both moves.

**Layout follows the presented state, not the live one.** `sync_places` runs
inside the swap. Outside it, every card would be asked for its final position on
the first frame of a run and the whole click would happen at once — the exact
thing the run exists to stop, and the one ordering mistake that does not announce
itself.

**A card that came from nothing still pops**, and that is now the only case left:
`take` shipped, so a component out of a box remembers which box. What remains is
a genuine `fill`, and if a supply stocks the kind the renderer still guesses at
it — gated on a run being in progress, or every chip in the box would fly to its
seat the moment a game loaded.

## Left

**Stage 3 — pruning.** `actions.on_act(id, ordinal, step)` was the only ordering
signal the presentation owned and the queue replaced it; it still carries its
`step` argument. `fx.after` and the `pending` list behind it are a hand-rolled
queue with no callers left. Both want one pass to find out whether anything still
wants a delay that is not a beat.

**A destroyed card disappears on its beat rather than leaving.** It is drawn
until the step that removes it, which is the honest half; an exit — a fade, a
flight to the discard — needs somewhere to go, which is
[28](28-a-zone-by-its-parts.md)'s question about where a destroyed card lands.
