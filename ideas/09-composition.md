# 09 — One game out of several files

**Status:** not started · **Size:** small engine change, one large decision, and
one trap that will bite hard if it is found late.

Two requests that are really one:

> *Let game.json files load other game.json files like includes — pure
> convenience for tags, cards, patterns. Possibly nice for MTG where every set
> can be its own file.*
>
> *Have a base config json with a bunch of non-obvious dynamic tags or patterns
> that many games need, just for easier creation.*

The second is a *use* of the first. Build the first; the base file is then one
ordinary game file that ships in `game/games/`.

---

## Why now

Three pressures, none of them urgent alone:

- **`patterns` are copy-paste today.** `line_ortho`, `line_diag`, `adjacent` are
  general geometry, not chess, and the next grid game retypes them.
- **A card set is not a game.** MTG is the honest example: 20,000 cards cannot
  live in one file, and per-set files are how everyone else splits it.
- **`tools/make_lost_cities.py` exists** because a big game
  file wants generating. Some of what they generate is boilerplate that would
  not need generating if it could be included.

---

## The shape

```json
{
  "title": "My Game",
  "include": ["base.json", "sets/alpha.json"],
  "cards": [ ... ]
}
```

A list, in order, resolved relative to `games/` — the same namespace every other
filename in the engine lives in.

### Merge at the raw JSON level, not at the parsed one

`declaration.parse` is ~240 lines of normalisation that ends in a `G`. There are
two places a merge could happen and only one of them is right:

| | |
|---|---|
| **Merge the parsed `G`s** | every section's normalised shape becomes a merge case, and the validator sees something no file ever said |
| **Merge the raw JSON, then parse once** | includes cost the rest of the engine *nothing*: `parse`, `validate`, the network layer and `check.lua` all keep seeing one game |

Take the second. It needs `parse(filename)` split into `read(filename) → table`
(read, decode, resolve includes, merge) and `build(table) → G` — which is a
mechanical refactor, and the seam is worth having anyway.

**The property that makes this work: the merged table is itself a valid game
file.** Everything downstream, including the thing in the next section, follows
from that.

### Merge rules

Sections are one of two shapes, so there are two rules.

- **Maps** — `tags`, `patterns`, `assets`, `computed_tags`, `effects`, `setup`:
  merged key by key. The including file wins.
- **Lists** — `cards`, `zones`, `stats`, `phases`: concatenated in include
  order, includes first, the file's own last. An entry whose `key` already
  exists **replaces the earlier one in place**, keeping its position. Position
  is not decoration: `phases` is an ordered list and `card_list` is file order,
  which is what makes an unseeded setup deterministic.
- **Scalars** — `title`, `seed`: the top file wins outright.
  An included file setting `title` is a bug in that file, and the validator
  should say so rather than the engine resolving it quietly.

Replacement is the interesting rule and the one to get right: *a set file
defines `lightning_bolt`, my game redefines it* has to work, or an include is
useless the moment you want one card different. It is also how the base file
stays overridable without needing an opt-out mechanism.

### Each file included once

Depth-first, `visited` keyed by resolved filename. A diamond (`a` includes `b`
and `c`, both include `base`) loads `base` once, and a cycle is a validation
error naming the chain, never a hang.

---

## The trap: the network sends *a file*

This is the part that will be found late and painfully if it is not designed
now. `net.game_text` (`net.lua:157`) reads one file and sends it; `net.game_hash`
hashes one file's text and that hash is how two peers check they are playing the
same game at all. An opponent who does not have the game **is dealt in by
receiving its text** — which is the difference between "install this first" and
"click here", and it is a shipped feature.

An include breaks both halves: the text that arrives references files the
receiver does not have, and the hash covers one file out of three, so two peers
with different `base.json` files agree they are playing the same game and then
diverge.

**The fix is free if the merge is at the raw JSON level:** send and hash the
**flattened** file. `json.encode` of the merged table is an ordinary game file
with no `include` in it, and it is exactly what the local engine is playing.

Two consequences worth stating plainly:

- `game_hash` must hash the flattened text. Hashing the top file is the
  silent-divergence bug above; hashing the file list is the same bug wearing a
  hat.
- `json.encode` must be **stable** for this to hold — same table, same bytes, on
  both machines. It already sorts map keys for `state_hash`, so this is a
  property to *assert in a test*, not one to add.

---

## Validation: a fragment is not a game

Whole-game rules — there must be phases, an end condition, a seat, a menu entry
— cannot run on `base.json`, which has none of them and should not. Per-entry
rules — is this a shape the engine draws, does this zone key exist — must run on
everything.

So `validate` needs the distinction it does not have today: **file-level checks
run on the flattened result only.** `check.lua base.json` then reports what is
wrong *with the fragment* and stays silent about the game it is not.

The second half is error provenance. `card 'lightning_bolt': ...` stops being
enough when the card came from a file you did not open. Keep a `key → source
file` map while merging and append `(from sets/alpha.json)` when the source is
not the top file. Cheap, and the alternative is an error message that sends you
looking in the wrong file.

---

## Then the base file

With includes built, this is content, not engine work — which is the argument
for this order.

**What belongs in it:** things that are (a) wanted by many games, (b) annoying
to write from memory, and (c) genuinely game-neutral. Geometry qualifies and is
the clearest case:

```json
"patterns": {
  "adjacent":    { "vectors": [[1,0],[0,1],[1,1]], "class": ["step", "mirrored"] },
  "line_ortho":  { "vectors": [[1,0],[0,1]],       "class": ["ray", "mirrored"] },
  "line_diag":   { "vectors": [[1,1]],             "class": ["ray", "mirrored"] },
  "knight_leap": { "vectors": [[1,2],[2,1]],       "class": ["step", "mirrored"] }
}
```

**What does not belong in it:** cards, zones, phases. Those are the game. A base
file that starts carrying them becomes a junk drawer, and the first author who
inherits a zone they did not ask for will not find where it came from.

**Tags with behaviour are the borderline case.** A tag def carries card
behaviour, and behaviour is usually game-specific — `takeable` means something
different in Lost Cities than it would in solitaire. Start with patterns only.
Add a tag to the base file when *two shipped games have written the same one*,
which is this repository's existing rule for generalising and works here too.

### Explicit, not implicit

The base file must be **named in `include` like any other**, not loaded
automatically.

DESIGN.md's standing property is that reading a game file tells you the game. A
tag whose definition is nowhere in the file, and nowhere in anything the file
mentions, breaks that — and it breaks it in the worst way, by working. The
counter-argument is real and worth recording: the engine already injects a
`system` card and a `player` card that no file mentions. The difference is that
those are plumbing the author never writes by name, whereas a prelude's patterns
are words the author types. One line of `include` is a small price for "every
name in this file is findable from this file".

---

## Refuse

- **Remote includes.** `"include": ["https://..."]` turns a game file into a
  supply chain. Local files under `games/`, nothing else — the same rule the
  asset path already enforces, and for the same reason.
- **Partial includes** (`"include only these keys"`). It is a query language
  waiting to happen; a file too big to include whole should be split.
- **Parameterisation** — substitutions, variables, a template that an including
  file fills in. That is a programming language, and DESIGN.md's whole schema
  section exists to prevent one.
- **Lazy loading.** `include` is concatenation before parse and must stay so. A
  30,000-card set file loading every def into memory is fine — they are small
  tables — and the moment it becomes lazy, "which cards exist" stops having an
  answer, which the validator, the network hash and `dump` all depend on.

---

## Build order

1. Split `parse` into `read` and `build`. No behaviour change, tests stay green.
2. `include` resolution and the merge, with the cycle check. Test the merge
   rules directly — replacement in place is the one that will regress.
3. Flatten for the network: `game_text`/`game_hash` over the merged JSON, plus
   a test that two peers with the same includes hash identically and two peers
   with different ones **do not**.
4. Provenance in validator messages, and the fragment/whole-game split.
5. `base.json` with the four patterns above, and chess switched to use them —
   which is the proof the feature works, since chess is where they were written.
