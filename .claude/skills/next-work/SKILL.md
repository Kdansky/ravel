---
name: next-work
description: Use when the user wants to move on to the next piece of work in ravel — "what's next", "next thing", "let's pick up the next piece of work" — typically right after finishing a task. Surveys todo.md and ideas/ for open notes, folds them into the ideas plan in priority order, and presents a shortlist to pick from.
---

# Next piece of work

Ravel's planning trail: `todo.md` is the inbox, `ideas/README.md` is the plan
(its "What to do next" table), `ideas/NN-*.md` are the worked-through
write-ups, `ideas/DONE.md` is the shipped record. This skill walks that trail
end to end.

## 1. Read the inbox

Open `todo.md`. It is one `## Open` section of loose notes, often a sentence
each. It stays short on purpose — the file's own rule is that anything handed
off to `ideas/` is **removed** from it rather than left struck through, because
strike-through is only worth reading while something is half-done.

## 2. Read the plan

Read `ideas/README.md` in full, then every numbered `ideas/NN-*.md` file in
ascending order (currently 01, 04–24 — there is no 02 or 03).
For each, note what it says is already shipped versus what it lists as still
left. `ideas/DONE.md` and root-level `IDEAS.md` are historical records, not
part of this pass — skip them unless a specific todo item needs cross-checking
against something already built.

## 3. Fold the inbox into the plan

For each open `todo.md` note:

- Check whether it's already covered by an existing numbered idea (a "left"
  item, a listed gap). If so it doesn't need a new home — just carry it into
  the ranking in step 4.
- Otherwise decide size, using the rule `todo.md` already states: **more than
  an afternoon → gets worked through in `ideas/`.** That means either a new
  gap appended to the relevant existing `ideas/NN-*.md`, or — if it fits no
  existing track — a new `ideas/NN-topic.md` at the next free number.
- Expand the terse note into what it actually requires, where it lands in the
  code, and what it depends on, matching the prose style of the existing idea
  files (terse, concrete, names real files and functions).
  **Wrap every inferred detail in `[Assumption: ...]`** — anything you add
  that the user did not literally say. Never let an assumption read as
  something the user dictated; that has caused confusion before and is the
  one rule in this skill that isn't optional.
- **Delete the item from `todo.md`** once it has a home in `ideas/`. The
  pointer lives in the idea file and in the ranking table, and a copy in the
  inbox is a third place to keep in step. Leave it — struck through, with a
  pointer — only when part of it is still genuinely open and unwritten.

## 4. Order the candidates

Rebuild `ideas/README.md`'s "What to do next" table
(`# | Item | Urgency | Difficulty | Why here`), keeping its stated ordering
rule: **urgency × difficulty × what it unblocks — cheap things that let other
things happen come first.** On top of that:

- Respect dependencies — an item needing another item's groundwork sorts
  after it, regardless of its own urgency.
- Bugs before features at equal unblocking value.
- Sequence refactors so they clean up code that just landed, or make the next
  feature easier to write — not refactors for their own sake.

Keep already-shipped rows struck through (`~~1~~`) exactly as the file already
does, so the table stays a full history, not just an open list.

## 5. Present options

Pull the top 3–5 rows of the refreshed table and present them as a short list,
one line of "why here" each. Wait for a pick — don't default to the top row
unasked; the ranking is a heuristic, not a decision.

## 6. Build it, in the repository itself

**No worktrees.** Work in `/home/kdansky/code/ravel` on whatever branch is
checked out. A worktree buys isolation nobody asked for and charges for it at
every commit and every test run — the paths move, the stash is shared, and
`luajit tests/run.lua` has to be re-taught where it is. Tried and dropped
(2026-08-16); `ideas/README.md`'s "Worktrees: no" section records the verdict.

The append-only conventions still hold, and they are what the worktree advice
was really protecting: `actions.lua`'s `SPEC`/`HANDLERS`, `validate.lua`'s field
tables and `tests/integration/validator.lua`'s `CASES` all append at the end,
never sorted-insert.

Shared docs — `AUTHORING.md`, `DESIGN.md`, `ARCHITECTURE.md` — are still not the
place to write a track's own findings while it is in flight: put those in its
`ideas/NN-*.md`, and fold them into the shared docs in a pass of their own.

## 7. After the task is done

Once the work is complete and committed, tell the user this is a good point to
run `/compact` — there is no tool to trigger it directly, so say so rather than
attempting it.

## Notes

- If `todo.md`'s `## Open` section is empty, skip step 3 and go straight to
  re-ranking whatever the idea files already list as left to do.
- "More than an afternoon" is the repo's own heuristic for todo.md vs.
  ideas/, not a precise measure — when in doubt, treat it as more than an
  afternoon and give it a proper writeup.
