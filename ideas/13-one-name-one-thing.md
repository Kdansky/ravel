# 13 — One name, one thing

**Status:** not started · **Size:** small check, one real redesign in front of it

> *We can absolutely have duplicate keys during the game because a card exists
> twice. What I do not want is that a game.json file has overlapping keys. The
> obvious problem is two different cards having the same name. But the less
> obvious one is a zone sharing a key with a card sharing a key with a tag
> sharing a key with a style. That needs to be stopped. This is mostly to
> prevent mistakes for game.json writing.*

**Instances are not names.** Twenty copies of one card are twenty entities with
one `def_key`, and nothing here touches that. The rule is about *declared*
names in a game file.

---

## The rule

Every name a game file declares — a card key, a zone key, a phase key, a stat
key, a tag, a style, a pattern, an asset, an effect — is unique across all of
them. The validator refuses a file that breaks it.

Half of it exists already, for the pair that actually collides in a scope:

> *Zones and tags share one namespace. A condition that points at a name means
> either the zone or the cards carrying that tag, so the two may never collide —
> the validator refuses a file where they do, rather than picking a winner by a
> precedence rule you would have to remember.* — AUTHORING.md

The change is to stop treating that as a special pair and make it the general
rule. The argument is the one already written down: *rather than picking a
winner by a precedence rule you would have to remember.*

## What it costs today: all ten games

Measured, not guessed:

| Collision | Where | What it is |
|---|---|---|
| `system` card + `system` zone | all 10 | engine-injected: the round counter, and the hidden zone holding it |
| `player` card + `player` tag | 7 | engine-injected when a game declares no seat of its own |
| `white` / `black` card + tag | chess | **the ownership mechanism** |
| `w_rook_h` … card + own-key tag | chess, ×32 | so a castling gate can ask `moves_made@w_rook_h` |
| `challenge`, `origin` phase + tag | castle, kingdom | harmless — nothing resolves a phase and a tag together |

The first two are the engine's own and cost a rename. The chess pair is a real
redesign, and it has to happen first.

## The redesign in front of it: ownership

`tags.owner_of` answers "whose piece is this" by looking for a tag matching a
seat's card key. `tags.lua:39` states the bargain:

> *It costs no new field: a seat is already a card key, so claiming one is
> writing `"tags": ["white"]`.*

That is exactly the collision, and it is also the ambiguity worth refusing on
its own merits: `@white` as a scope means **the pieces**, while `card:white`
means **the seat card**. One word, two sets. A reader cannot tell which without
knowing that seats are cards.

**Replace it with a field that says so:**

```json
{ "key": "w_rook_h", "owner": "white", ... }
```

`owner_of` reads the field, falls back to the zone's seat as it does now, and
`mine` / `enemy` are unchanged. This is one new field against a rule that
removes a class of mistake — a trade the original comment could not make,
because the rule did not exist yet.

## The part that gets *easier*, not harder

Chess tags each piece with its own key so a castling gate can write
`moves_made@w_rook_h`. That looks like the rule's biggest casualty. It is the
opposite.

**Unique names make a bare scope unambiguous**, so the resolver can look a name
up across zones, tags, patterns *and card keys* and be certain which it found.
`@w_rook_h` then resolves to the card **by key**, the self-tags are deleted, and
**the game file does not change at all** — 32 tags disappear from the generator
and every condition that used them keeps working.

That is the sign the rule is right: it pays for itself in the place it looked
most expensive.

Checked before claiming it: chess's scopes are `@self`, `@<piece key>` and
`@<pattern name>`. **No shipped game scopes a seat by name** (`@white`), so
nothing depends on a seat key resolving to its pieces.

## The two injected names

- **`system` card in the `system` zone.** Nothing depends on the two matching,
  and the pair is confusing to read. Rename the zone `engine`, or the card
  `round` — it holds the round counter, which is what it is for.
- **`player` card tagged `player`.** The *tag* must keep the name: DESIGN.md is
  explicit that `player` is deliberately unreserved because it is how a game
  marks a seat. So rename the injected **card**. Games declaring their own seats
  already use their own keys (`white`, `north`), so nothing in a game file
  moves.

## Where the check goes

`validate.check` already builds most of these sets for its cross-references.
One pass claiming each name with its kind, reporting `'board' is both a zone and
a card` with both kinds named, is a few lines — and it must come **last**, after
the migrations above, or it turns every shipped game red.

Note it must read *declared* names only. Instances, seats' per-seat zone copies,
and the derived `tags_set` are not declarations.

## Refuse

- **Namespacing to dodge the problem** — `zone:board` / `card:board` as distinct
  names. That is the precedence rule the existing comment already rejected,
  wearing a prefix.
- **A warning rather than an error.** The whole value is that the mistake cannot
  be made; a warning in a list of warnings is a mistake that gets made.
- **Reserving more words.** `self` and `all` are claimed because conditions
  answer for them. Nothing else needs claiming, and every reserved word is one
  an author cannot use for the obvious thing.

## Build order

1. `owner` field, `owner_of` reading it, generator updated. Golden traces
   unchanged.
2. Scopes resolve card keys. Delete chess's 32 self-tags. Traces unchanged
   again — the same conditions, reaching the same cards by a different route.
3. Rename the injected `system` and `player` cards.
4. The uniqueness check, and the test that every shipped game passes it.
5. `SCHEMA.json` and AUTHORING both state the rule in one sentence, which is the
   point of having it.
