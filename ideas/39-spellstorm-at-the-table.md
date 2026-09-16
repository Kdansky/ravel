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
- **`effects` + `effect:<name>`** play a named burst, landing on the *acting*
  card. Spellstorm declares one (`spark`) and never uses it.
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

## Gap 3 — damage, seen

> Spellstorm: Animation for damage dealing (Animation field for actions?)

A float and a burst already happen on the seat card (above). Open question for
the user: is it missing, too small, or not seen on the other screen? If the last,
it is gap 3. If too small, the existing `effect:` action is the field asked for,
except that it lands on the acting card and damage wants the *victim* — so the
word is a scope on `effect:`, [Assumption: `effect:<name>@<scope>`], not a new
field on actions.

## Gap 4 — the other screen sees nothing move

Appended to [02](02-between-two-states.md), whose mechanism it is. Weather, damage
and every other beat are recorded only for a click made **at this screen**; a
state arriving over the network is applied whole. [Assumption: at least one of the
three notes above came from a networked game.]
