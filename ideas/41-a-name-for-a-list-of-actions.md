# 41 — A name for a list of actions

**Open, and the largest single duplication in the box.** Three games have each
invented the same workaround independently, and each spelled it differently:
**a zone of invisible cards is how the format says *subroutine*.**

Counted over the three biggest files:

| | rules zones | cards in them | bytes | `setup.place` lines | `activate_zone:` strings |
|---|---|---|---|---|---|
| Spellstorm | 1 | 36 | 17,299 | 36 | 103 |
| Codex | 3 | 23 | 9,878 | 23 | 101 |
| Puzzle Strike | 8 | 21 | 4,351 | 21 | 10 |

**80 cards that are not cards, 31 KB, 80 placements, 214 call sites.** None of
them is a game object. Not one can be looked at, targeted, hovered or played;
every one is `immutable` and `display: "offscreen"`, which is the file saying so
out loud.

## Three spellings of one idea

The three games disagree about what names the routine, which is the tell that
the format names nothing:

- **Spellstorm** — one `rules` zone, addressed by *ability key*:
  `activate_zone:rules:by_column:gain_tier`. 90 calls over 47 keys.
- **Codex** — a zone *per moment*, addressed by zone:
  `activate_zone:rules_death` (54 calls), `rules_upkeep`, `rules_endturn`.
- **Puzzle Strike** — a zone *per routine*, eight of them:
  `rules_ante`, `rules_combine`, `rules_upgrade`, `rules_upgrade_hand`,
  `rules_upgrade_pile`, `rules_height`, `rules_piggy`, `rules_signature`.

Puzzle Strike's is the clearest statement of the problem: **eight zones, each
existing to hold one function body.**

## It is a call, not a moment

The distinction matters, because the engine already answers half of it and
should not answer this half the same way.

Of Spellstorm's 47 rules keys, **29 are never called by a phase** — only by
cards and tags. Those are not hooks that fire when something happens; they are
blocks of actions invoked from a call site, by name, mid-list. `gain_tier` is
called 9 times, `potion_toxic` 9, `dry_give_ice` 9, `dry_take_ash` 4.

The other 18 are phase hooks, and those are a different question. A phase
already has `emits`, and a card already has `reactions`; the reason no game uses
that pair for bookkeeping is that it routes through the response window and
opens a prompt. Nothing here wants a prompt.

**So this track is about the 29, not the 18.** A word for a moment already
shipped (`arrives`, `leaves`, a phase's `emits`). What is missing is a word for
a *name*.

## What it costs today, beyond the byte count

- **A routine that runs N times is N cards.** `r_croh_redraw_1` through `_4` are
  four identical Spellstorm cards whose only difference is `doom >= 1`, `>= 2`,
  `>= 3`, `>= 4` — because a column pass runs once per card standing in it.
  That is *"you may redraw once per point of Doom"*, spelled as four cards.
- **A moment answered by several routines is several cards.** Spellstorm's
  `r_journal_1`, `_3`, `_5`, `_7`, `_8` all carry the ability `bstart`.
- **A routine parameterised by one word is a card per value.** `r_dry_ash`,
  `r_dry_curse` and `r_dry_ice` are the same two abilities three times, differing
  in which pile they name.
- **A library becomes one enormous card.** Spellstorm's `r_gain` carries
  **16 abilities**.
- **Ordering is positional and invisible.** Which routine runs first is the
  order of `setup.place`, 36 lines away from every call site, and nothing warns
  when it is wrong.

## And where no rules zone was reached for, the run is simply copied

The workaround is not always taken, and then the duplication is raw. Longest
repeated runs, measured as action n-grams across each file:

- **Puzzle Strike, 20×**: `take:bank.crash_gem:mine.bag:1`,
  `take:bank.gem_1:mine.bag:6`, `set_name:mine.player:text@self`,
  `stat_gain:picked@mine.player:1`, `set_owner:self:mine.player`. That is
  *"this character is chosen"*, written out once per character.
- **Codex, 17×**: `reset:self`,
  `stat_set:ready_since@self:count:hasty@self`, `move_to:mine.army` — *"this
  unit enters play"*.
- **Codex, 7×**: `exhaust:target`, `stat_set:disabled@target:1`,
  `stat_set:slot@target:0`, `stat_set:guard@target:0` — *"sideline it"*, which
  [37](37-codex.md) already lists as a missing word in its own right. It is this
  one.
- **Spellstorm, 7×**: `activate_zone:reveal:by_column:sip`,
  `…:again`, `activate_zone:rules:by_column:potion_toxic`,
  `move_to:potion_discard` — *"drink the potion"*, three of whose four steps are
  themselves calls into rules columns.

**A sideline word, a summon word and a drink-the-potion word are not three
features.** They are one missing word, asked for three times by three games.

## The shape of the answer

The engine already composes actions, and does it twice, so the slot exists:

```
each_seat:<action>      wraps any action, runs it once per seat   (actions.lua)
emit:<verb>:<action>    announces, then runs the rest             (actions.lua)
```

Both take the remainder of the string and hand it to `M.execute`. A call word is
the same shape with a declaration behind it, and the declaration is the part
that needs consent:

- **Where the list is declared.** A new top-level section is the obvious home
  and also the thing [38](38-repeated-shapes.md) already refused once for the
  death sweep — *"a section is a claim that the game declares a new kind of
  thing"*. The difference here is that a named list **is** a new kind of thing,
  and the file is already declaring 80 of them badly. `verbs` is the nearest
  existing neighbour and is not it: a verb renames an engine action so a rule
  can answer it, and takes no body.
- **Whether it takes arguments.** `r_dry_ash`/`r_dry_curse`/`r_dry_ice` say yes,
  and the moment it does, this is a function and the format has grown a
  programming language. **The recommendation is no**: three cards for three
  piles is a price worth paying to keep a call from having a parameter list.
  Revisit only with a customer that cannot be spelled as three names.
- **Whether a call can be recursive.** No. A budget the way `settle` carries one,
  and a validator refusal for a cycle it can see statically.
- **What `@self` is inside one.** The card that *called* it, not the declaration
  — otherwise every routine needs a card to belong to and we are back where we
  started. This is the one semantic decision that cannot be deferred.

## What to refuse

- **Arguments.** See above.
- **A return value.** A routine that answers a question is a `computes` entry;
  this is for a list of actions and nothing else.
- **Using it for moments.** The 18 phase hooks are not this. If they hurt, the
  word for them is a phase's `emits` without a prompt, which is a separate
  question and should stay one.

## Before building

Count the 80 again after [43](43-what-the-files-already-say-twice.md) lands —
some of the rules cards exist only to work around things the format already
says, and the honest size of this track is what is left after those go.
