# 46 — One list of conditions

**Shipped.** Every condition an ability carries sits in one `needs`, keyed by
what failing it does — `req`, `where`, `fizzle`, `event`, or a gate named by
the lines behind it (`init? …`, `!init? …`). AUTHORING "`needs` — what failing
it does" and "Gates"; `game/needs.lua`; DONE.md.

## Left

- **Other lists with no `needs` beside them** — a phase's `actions` and
  `on_enter`, an end condition's `then`. Same rule: add one when a game needs it.
