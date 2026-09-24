# 46 — One list of conditions

**Shipped.** Every condition an ability carries sits in one `needs`, keyed by
what failing it does — `req`, `where`, `fizzle`, `event`, or a gate named by
the lines behind it (`init? …`, `!init? …`). AUTHORING "`needs` — what failing
it does" and "Gates"; `game/needs.lua`; DONE.md.

## Left

- **A verb with gates.** A verb has no `needs`, so a verb body cannot gate a line,
  and the gated routines in rules zones ([41](41-a-name-for-a-list-of-actions.md))
  stay where they are. The decision was to add `needs` where it is needed: a verb
  taking gates only (never `req`, which would be asked halfway through the
  caller's list) is the likely shape, when a routine asks for it.
- **Other lists with no `needs` beside them** — a phase's `actions` and
  `on_enter`, an end condition's `then`. Same rule: add one when a game needs it.
