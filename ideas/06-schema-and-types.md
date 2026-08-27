# 06 — Saying what things are

**Closed.** Six requests that were the same request in different clothes: the
engine should know the shape of its own data before it runs, instead of asking
at every use. Most of the answer turned out to be *it already does, or it is a
different question*.

## A tag scope that sees a hand — shipped as `@everywhere`

`count:<tag>` and a bare tag scope search grid zones only, and that stays the
default **on purpose**: most rules must not read a hand they cannot see. What
was missing was the opt-in. `@everywhere` is a reserved scope word resolving to
every card in any zone, composing with the owner word and every measuring form.

**The gap was narrower than three games' notes claimed, and measuring is what
showed it.** *Naming a zone by key already reaches a hand, a pile or a deck* —
a zone scope goes through `zones.all_with_key` and never touches
`find_targets`. The board-only limit is **only** the bare tag and the tag scope.
So the two recorded workarounds were not workarounds for this: The Crew's
commander walk is irreducibly per-seat (`@everywhere` answers *how many*, not
*whose*), and Puzzle Strike's gem pile is a grid for legitimate display reasons,
not to make a scope work. There was no game migration to make.

## Gap 1 — what a zone's `type` decides

**Refused 2026-08-13, reopened and shipped as [28](28-a-zone-by-its-parts.md).**

The refusal was against the shape it was offered in — tags: *a flat unordered
set with no grouping and no defaults, so `stack` + `face_down` + `closed` +
`top_only` is four independent chances to write three of them.* The condition to
revisit on was *a game genuinely wants a combination no current type offers*,
and Puzzle Strike's ongoing row fired it. 28 shipped it as fields, which is what
the refusal named as the more honest alternative.

Two findings from the survey outlived it. **`deck`'s three exclusions have
nothing to do with facing** — never clickable, never found by a tag search, not
browsable is "a closed box", so a deck tagged face-up looked like a pile and
behaved like a box. And **`on_turn` fired on grids alone**, a rule wearing a
layout's clothes. Both were latent bugs rather than design debt, and 28 made
them unsayable.

## Gaps 2 and 3 — lists everywhere, then fewer type guards

**Both measured 2026-08-16, both much smaller than written, both folded into
[17](17-conditions-as-expressions.md) as its first step.**

Three fields were left rather than six, and `patterns` had already been
normalised at the door — which *is* the proposal, done once and the model for
the rest. Two entries were decisions rather than tidy-ups and were left alone: a
phase's `zone` as a list means "the player acts in all of these", which is a
feature and shipped as one for The Crew's open hand; and a shared zone writing
`[[…]]` to match a per-seat one reads worse for the common case.

Gap 3's `type(x)` guard count *grew* 106 → 184, and all the growth is in
`declaration` and `validate` — the two files that read the document and are the
only places malformed input arrives. That is the gap's own goal happening by
itself.

**Refused along the way:** validating which combinations of tags are *legal*.
Normalise the shape, leave the meaning alone.

## Gap 4 — every tag the engine knows, in one place — shipped

`validate.lua`'s `ENGINE_TAGS`, with SCHEMA's strings and AUTHORING's table held
to it by a two-way test.

**The check went further than proposed.** It was to *suggest* on a near miss; it
also **refuses redefinition** — a style, tag def or computed tag named after a
reserved word is an error, because the engine reads the word off the entity and
would obey both meanings at once. That costs a game the ability to name a style
after an engine word, accepted deliberately rather than worked around.

Measurement changed one thing: the near-miss check first flagged `mage` as a
typo for `page`. Short words collide by accident, so both words must be six
letters or longer — which still catches `activaet`, `stays_redy` and
`discard_hnd`, the cases that actually fail silently.

## Gap 5 — a tag is a boolean below the door, a list above it — shipped

The `tags_set` map was already built at the door for every kind. What was left
was two card readers, and one of them **could not convert**: `cards.home_zone`
took the *first* tag whose def named a zone, which is order-dependent, and a map
has no order.

The fix was not to keep the array. `cards.home_zone` now answers **nothing**
when two tags name different zones, so the callers' own fallbacks decide. That
is what makes the map safe to read: it removes the file order the array encoded
without inventing a precedence to replace it, and an ambiguous home is more
honestly no home than whichever tag was typed first.

**The tail of the note is refused on evidence.** *"Throw any boolean values in
there which are not yet marked as tags"* — counted across ten games, the
booleans are 22 `ends_round` and five style `false`s. `ends_round` is on a
routing entry, which has no identity for a tag to attach to. The others are
`false`, and **a tag set can say present; it can never say absent** — turning
them into tags means naming the negative, which is the vocabulary
[11](11-styles-as-tags.md) deliberately collapsed.

## Gap 6 — a stat that says what kind of number it is

**Dissolved entirely**, including the measurement that looked real underneath it.

The registry the note asked about exists. The question was whether *"this number
is a price"* is a fact about the number, and the note answers itself with MTG:
red mana is a cost on most cards, a resource on some, and the subject of an
effect on others. A `type: cost` would be true in one sentence and misleading in
two. Either it changes behaviour — which is `play.cost`, a map on the *moment*,
right to be there because the same number costs 2 on one card and 5 on another —
or it changes presentation, which is a style question in a schema's clothes.

The salvage looked like Splendor's 450 written-out zeros: five `cost_*` stats
with no `start`, so every one of ninety cards carries all five, three of them
`0`. **Checked, and the assumption was wrong.** The missing `start` is
deliberate, and the generator says so: *a development card without a white cost
is a bug in this file, not a card that costs nothing.* The zeros are a checksum,
not duplication, and granting a default would turn a card that forgot its price
into a card that is free, silently. What the zeros cost on the face was answered
in presentation instead, by `badge_zeros`.

**A stat says its bounds, whose number it is, where they start, and what it
looks like. It does not say what it is *for*.**

**Refused:** a vocabulary of stat kinds — `cost`, `resource`, `counter`,
`score` — a closed set always missing somebody's, and every word in it a
behaviour the engine would then own. The engine does not know one game's words,
and "cost" is one game's word about one of its numbers.
