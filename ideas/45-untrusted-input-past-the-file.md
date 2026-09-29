# 45 — Untrusted input past the game file

**What shipped (2026-09-23).** A game file is held to its types before anything
reads it: `game/shape.lua` walks the merged file, reports and leaves out a value
of the wrong type, and hands `declaration.parse` a copy in which every known
field is a number, a list or an object as it should be. A name that points at
nothing — a card in `contents`, a phase in `push_phase`, a `pass_card`, a zone
`pos` naming a missing host — is skipped where it is used. `tests/fuzz.lua`
went from about forty-five crash sites to none, and
`tests/integration/shape.lua` fails the build when the validator knows a field
`shape.lua` has no type for. The same pass split `flow.lua` into `costs.lua`
and `stack.lua`.

The network got the same treatment (2026-09-30): `net.lua`'s `believe` holds a
peer's state to `shape.ENTITY` before it is restored — see ARCHITECTURE
invariant 5. What is left is two smaller things found on the way.

## 1. The live template editor writes anything

`cards.edit(def_key, field, raw)` — the debug server's `edit` command — decodes
`raw` as JSON if it can and writes the result straight onto the template,
whatever field it names and whatever type it is. It is the one path into `G`
that does not go through `shape.lua`, so `edit zap cost "gold:2"` puts back the
crash the shape pass removed. `cards.reload` is fine: it goes through
`declaration.parse`.

Smaller than the network was, because the debug server only listens with `RAVEL_DEBUG=1`
and is a developer's tool. The fix is to hold the one field to its type with the
spec `shape.lua` already has — `shape.SPECS.cards.fields[field]` — and refuse
the edit, with the message, when it does not fit. `shape.check(value, spec, where)` exists now — the network uses it — so this is
the one call.

## 2. What else could leave flow

`flow.lua` is 1,600 lines after `costs.lua` and `stack.lua`. Two more blocks read
as self-contained, and both were left because the gain is smaller and the seams
are less clean:

- **Offers and choosers** — `offer_choices`, `offer_abilities`,
  `offer_zone_abilities`, `offer_reactions`, `can_dismiss`, `dismiss_offer`,
  `menu_choice`, `close_offer`, about 130 lines. They open and close the
  options overlay, and `clear_offer` is shared with `play_card`.
- **The ending** — `ending`, `victor`, `outcome`, `winner`, `summary`, about 90
  lines, all reads of state and nothing a move needs.

Neither is worth doing for its own sake. *[Assumption: the ending moves first,
if either does, since it depends on nothing in flow and nothing in flow depends
on it except `fire_end_condition`.]*
