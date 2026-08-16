# 23 — Splendor

**Status:** not started · **Size:** small — mostly a content and
confirmation exercise · **Depends on:** none

> *Named alongside the trick-taking research as a likely-easy win.*

**Objective.** Splendor is a market-row engine builder: 90 development
cards across three tiers, each costing a combination of five gem colors and
granting a permanent gem-colored discount toward future purchases, plus ten
noble tiles claimed automatically once a player's discounts cross a
threshold. Nothing about the rules looks like a gap against `kingdom.json`'s
existing market/tableau pattern — this file exists to prove that out against
the real card list rather than assume it, and to produce the actual data
(all 90 cards, all 10 nobles), since that's the real authoring cost here, not
a rules puzzle.

---

## Deliverable

`ideas/splendor/cards.md` — the full 90-card tier list (cost in gems, the
gem color it produces, its victory points) and the 10 noble tiles (cost in
accumulated discounts, victory points), sourced or reconstructed carefully
enough to build from directly.

Plus a short confirmation note in this file once that's done: does the game
validate clean against the engine's current vocabulary with zero new
capability, or did something small turn up (reserving a card sight-unseen
from the deck, the gold/wild joker gem, the simultaneous-turn-order
question if playing with more than two seats).

**Done** — card data at [ideas/splendor/cards.md](splendor/cards.md),
triangulated from three independently-authored data files (not prose) and
cross-checked programmatically rather than eyeballed: all three agree
byte-for-byte on all 90 development cards and both noble sources agree
exactly on all 10 nobles. Turn structure, token counts and win condition
are cross-confirmed across three independent rules summaries. See that
file's own sourcing note and its numbered unverified section (mainly:
noble flavor names conflict across fan sites and are omitted rather than
guessed).

## Confirmation against engine vocabulary

Checked each mechanic against real `AUTHORING.md` constructs, not just
asserted:

- **Reserve, capped at 3.** An ordinary `per_seat` `hand`-type zone. Its
  privacy is free: "a hand with a seat is its owner's alone" is already
  the rule for any per-seat hand, so reserved cards are visible to their
  owner and invisible to everyone else with no extra tagging. The cap
  itself is **not** a zone-capacity primitive — that only exists for
  `grid` zones ("a full board refuses new arrivals"). It's an ordinary
  `receive.needs` on the zone's own definition:
  `{"count:development@reserve": {"at_most": 2}}` — legality-of-a-
  destination is already documented as living on the zone, and `count:`
  already takes an explicit zone-key scope for non-grid zones. No gap.
- **Reserve sight-unseen vs. from the tableau.** These are already two
  different verbs in the engine, for exactly the reason Splendor needs
  two different verbs: `draw_from:tier1_deck:reserve:1` takes the deck's
  own top card blind (decks default face-down, "a deck is a box, not a
  stack of clickable cards"); reserving a *specific* visible tableau card
  is an ordinary `move_to:target` from a face-up market-row zone. The
  distinction Splendor draws is the same one `DESIGN.md` draws between a
  deck and a pile — this isn't a gap, it's confirmation the vocabulary
  already has the right shape. Refilling the vacated tableau slot is one
  appended `draw_from:` step on the buy/reserve action, the same pattern
  `kingdom.json`'s draft row already uses.
- **Noble auto-claim, at most one per turn.** The eligibility test is
  free — noble cost is a set of plain `needs` constants
  (`{"white_bonus": 3, "blue_bonus": 3, "black_bonus": 3}`), read against
  the claiming player's own stats by default (no scope needed at all,
  let alone the `needs`-measured-against-a-subject bend). The *trigger*
  is the documented "board button with fixed destinations" pattern from
  castling: nobles sit in a shared zone tagged `optional` (so an
  ineligible noble is never falsely forced-playable by the needs escape
  hatch), each with `play.needs` = its cost and
  `play.action: ["gain_stat:score:3", "destroy_self"]`. A dedicated
  `automatic`-then-`player_input` phase pair runs right after buy/reserve
  and before handover — ordinary phase sequencing, the same "insert a
  phase at the exact granularity you need" move Puzzle Strike's Cleanup
  check and The Crew's per-trick check both already established, here at
  per-turn (not per-round) granularity, which is what the real rule
  needs. "At most one, player's choice among ties" falls out for free:
  multiple qualifying nobles are simultaneously clickable, one click ends
  the phase. Nothing here is a move/destroy-over-a-scope trick (which
  *would* have been a gap: unlike `gain_stat`/`destroy`, no move-type
  action takes an `each`/`random`/`any` scope) — it's the simpler,
  already-documented needs-gated-button idiom, and it fits without
  bending anything.
- **Take-2-same-color only if 4+ remain.** Token stacks are stats on the
  shared bank (or system) card. The take-2 action needs
  `{"white_tokens@bank": {"at_least": 4}}` before it fires — an ordinary
  `needs` read of a shared stat. No gap.
- **10-token hand limit, forced discard.** No aggregate stat cap exists
  (`min`/`max` clamp a single stat, not a sum across 6), so this isn't a
  built-in cap — it's the documented "discard a card of your choice"
  overlay pattern, looped: a routing check
  (`{"sum:token_count@mine": {"at_most": 10}}`) after taking tokens,
  falling through to a self-looping discard overlay when it fails,
  exactly the shape Puzzle Strike's reshuffle loop already established
  for "the obvious one-liner doesn't apply, but the construct that
  replaces it is already in the engine." Not a gap, but not a one-liner
  either.
- **3–4 seats.** Trivially fine, as expected — Splendor is fully open
  information (only reserved-card *contents* are private) and strictly
  sequential, which is exactly the shape `"seat": "next"` and per-seat
  zones already assume for any seat count. No special-casing needed.

### Verdict

**Validates clean — the stub's prediction holds, and holds more cleanly
than any of the other four sibling games.** Every mechanic maps onto an
existing, already-documented idiom: the noble claim reuses castling's
needs-gated-button pattern verbatim rather than needing anything new, the
reserve/deck distinction turns out to already be how decks and piles
differ, and the token-stack and hand-limit rules are ordinary stat reads.
Two things are heavier than a one-liner (the hand-limit discard loop, and
the noble-check phase pair) but both are authored *content*, not missing
*capability* — the same "closed set, a generator's job" texture the other
four docs kept finding, here without even that: nothing in Splendor needs
a generator, since 90 cards fit a hand-checkable table and the ruleset
itself is five mechanics deep. Contrast with Puzzle Strike, the closest
prior bar — buildable now, but with one real, if small, engine-level gap
(`flow.lua` refuses to let a card played by the non-active seat resolve,
which blocks counter-crashing). Splendor asks for no such thing: every
seat acts strictly in turn, nothing responds out of turn, and the one
place a genuine gap looked plausible on paper (auto-claiming a noble
without a click) resolved into an existing pattern once actually worked
through against real `AUTHORING.md` syntax rather than assumed. Of the
five games in this series, this is the only one that needed zero new
primitives and zero cut content.
