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
- **A routine behind a `needs`.** A body has no `needs`, so it has no gates, and
  gated routines still sit on rules cards — reached by `activate_zone`, or by tag
  through `copy:<zone>.<tag>:activate` as `give_junk` does. Moving them wants a
  verb that takes a `needs` of gates only ([46](46-one-list-of-conditions.md) left
  that open: add it when a routine asks for it). A `req` on a verb stays refused —
  it would be asked halfway through the caller's list.
- **The 18 phase hooks** are a moment rather than a call, and stay out of this
  track.
