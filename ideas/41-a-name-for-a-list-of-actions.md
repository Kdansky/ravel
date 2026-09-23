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
  `lose_initiative`, `gain_<kind>`; Ghost Stories `drive_out`, `place_ghost`,
  `spend_action`. Splendor and Grimm have only short or gated runs, and were left.
- **A parameter is a whole word**, so Spellstorm's `GIVE(kind)` and
  `GAIN_JUNK(kind)` — `activate_zone:rules:by_column:dry_give_<kind>` then a draw
  off `<kind>_pile` — cannot be one verb over the kind. Either pass both names
  (`give_junk:dry_give_ice:ice_pile`), or leave them; they are 30 call sites.
- **A routine behind a `needs`.** `r_dry_ash`/`_curse`/`_ice` and every other
  rules card whose abilities are gated stay as rules zones: a body has no if,
  and `needs` on a verb was turned down because an ability's `needs` is asked
  *before* anything runs and decides whether it is a move at all — a verb's would
  be asked halfway through a list. Wants its own design; the `by_column`
  gating itself is in `todo.md`.
- **Once per point of something.** `r_croh_redraw_1..4` is *"once per point of
  Doom"* as four cards. A repeat by an amount is its own word.
- **The 18 phase hooks** are a moment rather than a call, and stay out of this
  track.
