# 42 — An if inside an action list

**The if has shipped:** `{ "if": [conditions], "do": [actions] }` stands in an
action list (AUTHORING "`if` and `do`", DONE.md). Spellstorm's `cast2`/`cast3`
moved into it. What is left is the other half.

## The gate `activate_zone` reads

From the inbox (2026-09-23): *"Runeterra's `by_column` gating (a rules column
whose abilities run only where their `needs` pass) is an if inside an action
list in disguise and breaks with how `needs` works everywhere else (asked
before, deciding legality). Remove it at some point."*

`actions.lua`'s `activate_zone` handler runs each ability only
`if predicate.meets_all(a.needs, c)`. Everywhere else a `needs` is asked
*before* — may this be played, may this be aimed — and a failed one means the
move is not offered. Here it is asked *during* a resolution the phase has already
committed to, and a failed one means the rule silently skips. Same word, two
meanings. The handler's own comment still says it honours an ability's `when`,
the field's name before the validator folded it into `needs`.

Counted as an ability keyed to a step some `activate_zone …:by_column:<step>`
names *and* carrying a `needs` (after Spellstorm's `cast2`/`cast3` moved):

| | step gates | distinct conditions |
|---|---|---|
| Spellstorm | 43 | 41 |
| Ghost Stories | 63 | 16 |
| Codex | 36 | 16 |
| Grimm | 10 | 8 |
| Arnak | 1 | 1 |

LoR's `spill` (Overwhelm) is the named case; its cards sit where the count
missed them.

Each moves mechanically: `needs: X` + `action: Y` becomes
`action: [{ "if": X, "do": Y }]`, in the generators. Then `activate_zone` stops
reading `needs`, and the validator refuses a `needs` on an ability only a phase
ever runs. [Assumption: "`by_column` gating" means the gate, not the order —
`by_column` as a column-first ordering is unaffected.]

**Watch the order.** Merging passes changes cross-card order; folding a gate into
the same ability does not. Spellstorm's fold kept `cast_ask` as its own pass for
that reason. Check each game by random play, old file against new, as
Spellstorm's was.
