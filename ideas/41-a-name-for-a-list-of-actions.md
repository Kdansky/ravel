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
  `lose_initiative`, `gain_<kind>`, `give_junk`, `gain_junk`; Ghost Stories `drive_out`, `place_ghost`,
  `spend_action`. Splendor and Grimm have only short or gated runs, and were left.
- **A routine behind a `needs`.** A body has no if, so a gated routine stays
  on a rules card — reached by `activate_zone`, or by tag through
  `copy:<zone>.<tag>:activate` as `give_junk` does. `needs` on a verb was turned
  down: an ability's `needs` is asked *before* anything runs and decides whether
  it is a move at all, where a verb's would be asked halfway through a list.
  The if belongs to [42](42-an-if-inside-an-action-list.md).
- **The 18 phase hooks** are a moment rather than a call, and stay out of this
  track.
