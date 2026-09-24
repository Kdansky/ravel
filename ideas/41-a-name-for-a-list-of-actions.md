# 41 — A name for a list of actions

**The word shipped; the migration has not.** A declared verb may carry an
`action` list in place of `does`, with `param1`, `param2` … filled from the call
by position — AUTHORING.md's *A verb with a body* and the COOKBOOK's *Sideline
it* and *Burn* entries say what it does, `tests/integration/verb_body.lua` holds
it. Chosen over a new top-level section because `verbs` already existed, `@self`
was already the caller, and a body change being the verb's change is what makes
`adjusts` reach it for free.

## Left

- **Moved so far** (each checked by seeded bot games reaching the same states):
  Puzzle Strike `crash_gems`, `pick_fighter`; Codex `deploy`, `summon_hero`,
  `leave_patrol`, `disable`; Spellstorm `drink`, `take_initiative`,
  `lose_initiative`, `gain_<kind>`, `give_junk`, `gain_junk`, and thirteen gated
  rules cards once a verb took gates (DONE.md, *A verb with gates*); Ghost Stories `drive_out`, `place_ghost`,
  `spend_action`. Splendor and Grimm have only short or gated runs, and were left.
- **Rules zones in other games that are an if.** Puzzle Strike's `rules_ante`,
  `rules_combine`, `rules_upgrade*` and `rules_height` are a switch on a number, one
  card per value (the cookbook's *Take the gem the panic level says*); `rules_piggy`
  is one if. Arnak's `rules_market`, `rules_win` and `rules_temple` likewise. Each
  would be a gated verb. Codex's `rules_death`, `rules_upkeep` and `rules_endturn`
  are a different shape — a phase sweeping a column of independent rules — and are
  [38](38-repeated-shapes.md)'s death half, not this.
- **The 18 phase hooks** are a moment rather than a call, and stay out of this
  track.
