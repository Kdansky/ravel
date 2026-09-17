# 39 — Spellstorm at the table

*From four `todo.md` notes after a play session (2026-09-16).* The rules play;
what is missing is a player being able to follow them without hovering.

## What is already built

- **A seat's numbers are on its card**, a hover away: `tooltip.lua`'s `blocks()`
  lists them. Since 2026-09-16 a stat's `display` keeps helpers out and holds a
  track back until it moves (`nonzero`), so the panel is short — but still a hover.
- **Every stat change on an on-screen card floats**, `+2 mana` / `-3 health`, and
  any decrease also takes a `damage` burst while the acting card leans in
  (`main.lua`, `actions.on_stat_change`). Health is on the seat card in `wizard`,
  so Spellstorm's damage already animates — on the screen that made the move.
- **Weather is a card flipped into `weather_now`**, a stack at the far left.

## Gap 1 — the numbers a player plays by — built 2026-09-17

The seat card badges health, mana, tier, power, shards and Initiative in a
column, zeros hidden, so the Initiative arrow is only its holder's. The character
card badges its Ultimate cost. Badges are sized to the card now (AUTHORING,
*What a card wears*), and the wizard boxes took height from the weather column
to give them room; the weather discard sits behind the Weather on its rect.
Left: power and shards at 0 are hidden with the rest, and "very clearly" for
Initiative may still want more than an arrow.

## Gap 2 — the weather, announced

> Spellstorm: Animations for weather to show it to everybody.

The flip is a card moving onto a small stack in a corner, and it changes what
everyone's turn does. [Assumption: "to everybody" means both players over the
network, which is gap 3 and not Spellstorm's; and also that the flip is too quiet
even locally.] The in-format answer to the second is showing the new card large
for a beat — the built-in `reveal` overlay, or a `layout: "page"` zone the flip
passes through. [Assumption: which of the two, unexamined.]

## Gap 3 — damage, seen — built 2026-09-17

A verb carries its look: `hit` says `"effect": "blast"`, a bolt from the acting
card to each card the blow lands on (AUTHORING, *Effects*). Left: whether the
other verbs — `heal`, `power_up` — want one too, after a look at a real game.

## Gap 4 — the other screen sees nothing move

Appended to [02](02-between-two-states.md), whose mechanism it is. Weather, damage
and every other beat are recorded only for a click made **at this screen**; a
state arriving over the network is applied whole. [Assumption: at least one of the
three notes above came from a networked game.]

## Gap 5 — a [GAIN] bought off the shelf — built 2026-09-17

Asked for: no offer overlay for a gain, buy in place as Splendor does, and no rule
changed. Engine-free, in `tools/make_spellstorm.py`: a gain runs one of the
Gaining rule's `gain_<kind>` abilities, which writes `gain_owed` and `gain_kind`
and pushes the one `gaining` step; the shelf's single `take` reads the kind and
routes the card through an offscreen `gained` zone, which is also where Coffee Run
reads it. The Regroup's gain is the same counter at kind 0. Mana Font, Meteorite,
New Curriculum's VOIDs and Abragail's Water resolve are not gains and stay offers.

What it cost to find:
- **One `take`, not one per kind.** The engine keeps every `merge: "this"` ability,
  but the validator calls two on one zone a contradiction and does not look at
  `phases`. A report worth making if a second game wants per-phase shop answers.
- **A push is refused while an offer is open.** New Curriculum's gain is written
  behind its two VOID asks on the rule card, so it is parked with their tail.
- **Stacked steps know nothing about seats.** Falling Star pushes two in one sweep;
  each step's entry hands priority to whoever is owed, Initiative first.
- **An empty offer never opened**, so a step with nothing takeable passes on entry
  — which is also what keeps Amber's MUST honest with an empty shelf.

Left: how the step looks — the label and a "Don't gain" button in the menu column.
Not yet seen in a real game.
