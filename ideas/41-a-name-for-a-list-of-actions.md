# 41 — A name for a list of actions

**The word shipped; the migration has not.** A declared verb may carry an
`action` list in place of `does`, with `param1`, `param2` … filled from the call
by position — AUTHORING.md's *A verb with a body* and the COOKBOOK's *Sideline
it* and *Burn* entries say what it does, `tests/integration/verb_body.lua` holds
it. Chosen over a new top-level section because `verbs` already existed, `@self`
was already the caller, and a body change being the verb's change is what makes
`adjusts` reach it for free.

## Left

- **Move the games onto it.** `activate_zone:` call sites today: Spellstorm
  117, Codex 101, Ghost Stories 65, Grimm 21, Puzzle Strike 10, Splendor 5.
  Spellstorm, Ghost Stories, Puzzle Strike and Splendor are written by their
  `make_*.py`, so the change goes there. The runs copied rather than put in a
  rules zone are the cheapest first customers: Puzzle Strike's *"this character
  is chosen"* ×20, Codex's *"enters play"* ×17 and *sideline* ×7, Spellstorm's
  *drink the potion* ×7. [Assumption: one game per commit, Codex's sideline
  first because [37](37-codex.md) already asks for that word.]
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
