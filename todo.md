Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

- **Codex: reshuffling is unlimited, and the cap needs the engine.** The
  rulebook allows one reshuffle per main phase, and refuses further draws that
  phase. Codex's deck has `refill_from: "discard"`, so `zones.move_card` calls
  `restock` the instant the pile empties — engine-driven, ungated, and invisible
  to the game. A stat cannot count it: `restock` moves the cards one at a time
  through `move_card`, so the deck's `receive` fires once *per card* rather than
  once per reshuffle, and by the time it fires the pile is no longer empty. The
  missing word is a gate or a count on the refill itself. Low stakes — it only
  bites when a deck is emptied twice in one main phase.
