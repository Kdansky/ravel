# 38 — The shapes that repeat

A survey of the three biggest games in the box — Codex (425 cards, 279
abilities), Puzzle Strike (195 / 30) and Spellstorm (150 / 234) — for structure
that appears often enough to be a spelling rather than a card. Counted
mechanically: action n-grams, ability shapes with the numbers blanked, target
blocks compared whole, and `mine`/`enemy` mirror pairs.

Two kinds of finding, kept apart because they cost different things. The first
kind is a sentence the format already holds and the file does not use — content
work, no engine change, and the only real question is whether the validator
should have said so. The second kind is a word that is missing.

## Already sayable

- **Codex's combat macro, written out three times** — built. All 33 duel
  passes sit on `tags.fighter` now, in one place. The lesson it paid for: the
  three `strike_*` abilities differed in nothing but which zone they aimed at,
  and reading them side by side was the only way to see it.
- The rest of this kind is [43](43-what-the-files-already-say-twice.md), which
  surveyed the same three files again and found a tag that carries 63 identical
  `play` blocks, a stat `start` worth 46 `card_stats` entries, and 19 `subject`
  lines that say what a bare subject already says.

## Missing words, in the order worth building

### 4. The death half

**The word shipped: `becomes`** (2026-10-01) — a card or tag block keyed by a tag,
run when a card starts wearing it, heard in `flow.settle` before the response
window. `dead` is already Codex's computed tag, so "when this dies" is
`"becomes": { "dead": ... }`. Reference: AUTHORING *`becomes` — a card starting to
wear a tag*; COOKBOOK *Triggers*; tests `tests/integration/becomes.lua`.

What cost the time, kept because it is why the word has the shape it has: four
hooks failed on one fact — **death here is a state the rules resolve, not a
moment** — and any hook that moved the corpse first threw away the slot it died
in, whose it was, and whether it is insured or comes back. Hence noticed at rest,
blocks run only while the card still wears the tag and stands where it stood
(that is death replacement), and every card's own block before any tag's (a
rattle must find the others that fell with it still standing).

**Left — Codex does not use it yet.** Codex still writes its death as the
`rules_death` column plus 54 `activate_zone:rules_death` calls:

- Move the column's abilities onto `tags.unit.becomes.dead` (and hero,
  building) and onto the cards that replace their death (Brave Knight, Justice
  Juggernaut, Insurance Agent's payout), then delete the 46 trailing calls, the
  attack abilities' three, `draw`'s one, and `deteriorate`/`sickness`'s two.
  [Assumption: every column ability splits cleanly into "what every unit does"
  and "what one card does instead"; the payout rules that read `at_scav` and
  `insured` are the ones to check first.]
- **`shadow_blade` and `nature_reclaims` need deaths settled mid-list**, which
  `becomes` alone does not do — it is heard when the list ends. They keep their
  `activate_zone` call until an action meaning "hear it now" exists; that is a
  new word and wants agreeing first.
- **`destroy:` still moves before anyone asks.** `r_scav` reads
  `count:dead@mine.patrol.at_scav`, and a destroyed patroller has already left
  the patrol, so the Scavenger pays nothing where Codex pays on any death.
  [Assumption: Codex's fix is a game verb `destroy` that sets hp to nought, so
  both roads end in `becomes.dead`; content only.]
- `hp` must come back when a card leaves play, or a Brave Knight bounced at
  nought is still wearing `dead` in hand. [Assumption: unchecked — `unhook`
  clears stats only on `purge`.]

### 6. A printed stat that steps

Codex heroes read *"Levels 1-3 2/3, levels 4-6 3/3, level 7 4/3"*. The file says
it as the 36 `lvlN` abilities that §"Already sayable" could not collapse, each
`stat_set`ting `atk` and `life` on the way past — which is also why levelling
heals, as an accident of `stat_set` rather than because anything says so.

`card_stats` already takes an object where a plain number will not do
(`"life": { "value": 3, "max": 3 }`). A stepped form would let the card say its
own sentence and would take the accident out. `buffs` cannot do this: the amount
"is a plain number, never a subject" by design, so it cannot vary per card.

### 7. An ability cannot act and then ask

**The gate half of this split shipped** as gates in `needs`
([46](46-one-list-of-conditions.md)): all 22 of Spellstorm's `cast2`/`cast3`
abilities were a gate and not one a genuine second step, and they are lines
in `cast` now. What stays here is the
`cast_ask` half — acting and then asking, which is about the offer queue rather
than about a condition.

29 Spellstorm cards split their resolution into `cast` and `cast_ask`, with the
answer landing in `chosen`. The resolve phase then walks the zone four times —
`cast`, `cast2`, `cast3`, `cast_ask` — and the ordering of a card's own
resolution lives in the spelling of its ability keys. Codex does the same thing
harder, walking the duel zone eleven times.

Naming a step is the right word for *"every unit works out its damage, then
every keyword reduces it, then every unit takes it"* — that is a genuine
resolution in passes, and actions.lua says so at length. It is the wrong word
for "this one card does a thing and then asks a question", which is one card's
business and is being paid for by every card in the zone.

## Smaller, and already noted in the generators

- `move:` and `destroy:` both take a count now (`move = "scope zone n? pos?"`),
  so "discard two at random" is one line — and Spellstorm still writes it twice.
  See [43](43-what-the-files-already-say-twice.md).
- A one-tracker toggle like initiative is two writes and cannot be said as one
  (make_spellstorm.py:45).
- `needs` has no `or`, which is deliberate and on `todo.md`. Worth recording
  that the `any_of` workaround is now load-bearing in all three games: `hidden`,
  `buildable`, `finished`, `hasty`, `ranged`, `exhaustable` in Codex, `held` and
  `curse_or_ice` in Spellstorm, `stowed` in Puzzle Strike.
- "Is this card mine?" has no word — two clumsy spellings and no clean one.
  Most of the sites went when a card learned to read as its own side, which made
  the guards tautologies; the question is [17](17-conditions-as-expressions.md)'s
  now, ranking row 70.
