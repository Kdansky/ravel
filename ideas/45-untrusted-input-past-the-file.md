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

The shape pass covers the game file and only the game file. What is left is
the other two doors content comes in by, and two smaller things found on the
way.

## 1. A state from the network is not checked past its phases

`net.lua`'s `restore` says every field is checked before it is believed. That
is true of the phase stack — each frame's key must name a phase, a turn's key a
`turn` phase — and of the entity list being a list of tables. It is not true of
the entities themselves. A peer can send a card whose `stats.hp` is a string, a
zone whose `cards` is a number, a `zone_id` naming a card, or a `def_key` the
game has no template for, and the first read of it crashes the receiving game.
`apply_delta` patches entities through the same door.

Invariant 5 counts the network as untrusted — the header of `net.lua` puts
*cheating* out of scope, which is a different thing from a crash. A malformed
message should be refused whole, the way a bad phase key already is.

What it needs:

- **A shape for an entity**, in the same terms `shape.lua` already uses:
  `kind` one of `zone`, `slot`, `card`; `stats`, `stat_max`, `stat_min` maps of
  numbers; `cards`, `attached`, `re_answered`, `re_targets` lists of numbers;
  `slots` a map of numbers; the `re_*` fields their own types. *[Assumption: the
  field list is read off `cards.create`, `zones.build` and `stack.push` rather
  than written from memory, and a test holds the spec to what those three
  write — the same move `tests/integration/shape.lua` makes against
  `validate.FIELDS`.]*
- **References checked, not just types.** An id must be an index into the
  array it arrived in, of the right kind: a `zone_id` names a zone, a
  `slot_id` a slot, a `def_key` a template this game has. The entity at index
  *i* must say `id = i`.
- **Refused whole.** Unlike the game file, a half-believed state is worse than
  none: `restore` already returns `false, why` before touching anything, and
  `apply_full` then asks for a resync. The entity check goes before
  `entity.restore`, at the same point.

*[Assumption: this is fuzzed the way the game file was — a script that takes
`net.snapshot()` of a real game mid-play, mangles values, and hands it to
`apply_full` — and it probably belongs in `tests/fuzz.lua` as a second mode
rather than a second script.]*

## 2. The live template editor writes anything

`cards.edit(def_key, field, raw)` — the debug server's `edit` command — decodes
`raw` as JSON if it can and writes the result straight onto the template,
whatever field it names and whatever type it is. It is the one path into `G`
that does not go through `shape.lua`, so `edit zap cost "gold:2"` puts back the
crash the shape pass removed. `cards.reload` is fine: it goes through
`declaration.parse`.

Smaller than item 1, because the debug server only listens with `RAVEL_DEBUG=1`
and is a developer's tool. The fix is to hold the one field to its type with the
spec `shape.lua` already has — `shape.SPECS.cards.fields[field]` — and refuse
the edit, with the message, when it does not fit. *[Assumption: exposing a
`shape.check(value, spec, where)` for a single value, rather than `clean` on a
whole file, is the natural shape of that call.]*

## 3. `test_codex_shape` fails when run on its own

`luajit tests/run.lua codex_shape` fails; the full suite passes. The test reads
`local G = declaration.G` **before** `flow.init("codex.json", 7)`, and
`flow.init` replaces `declaration.G` with a fresh table — so `G` is whatever the
previous test loaded, and alone it is the empty table. A one-line move of the
`local` below the `init`. ARCHITECTURE says each test must survive being run
alone; this one is the exception found, and there may be others. *[Assumption:
worth one pass running every integration test in isolation —
`for t in tests; luajit tests/run.lua $t` — since that is how this one was
found, by accident.]*

## 4. What else could leave flow

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
