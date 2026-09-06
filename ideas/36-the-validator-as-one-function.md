# 36 — The validator as one function

**Status:** not started. Came out of the architecture review of 2026-09-06, which
found it and left it: it was the one finding on that list nobody assigned.

`validate.M.check` is `game/validate.lua:397`–`3099` — **2,702 lines, one
function, 27 nested closures.** Everything inside it shares state by closing over
what the first fifty lines build: `problems` and the `warn` that appends to it
(281 call sites), `claim`, the tag universes (`card_tags`, `carried_tags`,
`known_tags`, `union_members`), and the per-kind predicates `stat_ok`,
`scope_named`, `subject_ok`, `condition_ok` that every later check leans on.

The cost is not the length. It is that **no part of it can be read or tested
alone.** `tests/integration/validator.lua` is 970 lines of `CASES` that each load
a whole game file and grep the returned strings, because a string is the only
surface the checker has. A check that fires on the wrong shape and one that never
fires at all look identical from outside.

It is also the file every format word has to be edited into. Items 9, 11 and 14
on the plan each add a word, and each will add a closure to the middle of a
2,700-line function that already has 27.

## What is worth doing

Not a decomposition for its own sake — the closures genuinely share state, and
hoisting them to file scope means threading a context record through every one,
which trades one problem for a longer one.

The shape that pays: **the universes and the predicates are the context; the
checks are consumers of it.** `stat_ok`, `scope_named`, `subject_ok`,
`condition_ok`, `check_conditions`, `check_cost`, `check_fields`,
`check_labels`, `check_numbers`, `computed_reads` and `amount_ok` are a
vocabulary — they answer questions about the game and warn. Above them,
`check_list`, `check_target`, `check_phases`, `check_moves`, `check_compute`,
`check_ability` and the long unnamed stretches are one pass each over one kind.

[Assumption: the split that falls out is a single `local function context(G)`
returning that vocabulary as a table, and one file-scope function per kind taking
it — so a new format word is a few lines in one named function, and a check can
be exercised without a game file. Nothing was measured about how much of the
2,700 lines is the unnamed stretches between the closures, which is the number
that decides whether this is a medium job or a large one.]

## What to refuse

**Do not change a single warning string.** The 970-line `CASES` table matches on
them, `check.lua` prints them, and the strings are the diagnosis — the review
that just landed spent its time making one of them name both halves of a
contradiction. A refactor that reworded them would be indistinguishable from a
refactor that broke them.
