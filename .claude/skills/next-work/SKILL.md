---
name: next-work
description: Use when the user wants to move on to the next piece of work in ravel — "what's next", "next thing", "let's pick up the next piece of work" — typically right after finishing a task. Surveys todo.md and ideas/ for open notes, folds them into the ideas plan in priority order, presents a shortlist, and opens a worktree for whichever one gets picked.
---

# Next piece of work

Ravel's planning trail: `todo.md` is the inbox, `ideas/README.md` is the plan
(its "What to do next" table), `ideas/NN-*.md` are the worked-through
write-ups, `ideas/DONE.md` is the shipped record. This skill walks that trail
end to end.

## 1. Read the inbox

Open `todo.md`. The `## Open` section holds new, unstruck notes — often just a
sentence. Items under `## Worked through, see ideas/` are already handled;
skim them only as examples of the strike-through pointer format, to reuse in
step 3.

## 2. Read the plan

Read `ideas/README.md` in full, then every numbered `ideas/NN-*.md` file in
ascending order (currently 01, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15).
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
- Strike the item in `todo.md`'s `## Open` section with `~~...~~ — <pointer>`,
  in the exact format already used under "Worked through, see ideas/" (e.g.
  `~~Fix the run.sh script~~ — done (\`hash\`).` or
  `~~text~~ — [NN gap X](ideas/NN-topic.md).`).

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

## 6. Open a worktree

Once the user picks one, call `EnterWorktree` (name it after the idea's slug,
e.g. `06-schema-tags`) to create and switch into an isolated worktree. Before
that, check `git worktree list` — the repo's own guidance is 2–3 concurrent
worktrees at a time, and a second worktree touching the same hot files as one
already open (`predicate.lua`, `actions.lua`, `validate.lua`, `tests/run.lua`)
is pure cost, so flag that to the user if it applies. Inside the worktree,
follow the append-only conventions `ideas/README.md` documents (`actions.lua`'s
`SPEC`/`HANDLERS` and `validate.lua`'s field tables append at the end, never
sorted-insert; shared docs — `AUTHORING.md`, `DESIGN.md`, `ARCHITECTURE.md` —
aren't edited on a track branch, the track writes its own `ideas/` file
instead).

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
