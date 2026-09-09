Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

- **The log says `{name}`.** A seat renamed by `set_name` reads correctly on its
  card, in its tooltip and on the ending banner, because `label.fill` runs when
  a string is *drawn*. A log line is not drawn from anything: `flow` writes
  `log.add("Played " .. def.text)` and the finished string keeps the template, so
  `tooltip.lua`'s event-log card prints `{name} +1 mana` and `— {name} to play —`.
  Filling it at write time would defeat the whole point of [27]'s answer-when-drawn
  rule; filling it at read time needs the entity the line was about, which the log
  does not keep. Found by watching an engine-played Spellstorm seat.

- **The engine seat stalls on an offer whose cards cannot fill their own aim.**
  `opponent.lua`'s `M.legal` builds targets for every playable card out of
  `cards.def(e).target`, and drops the move when the pool is short. But a card
  lying in an offer is being *chosen*, not played: `flow.play_card` skips the
  target check entirely for an overlay (`flow.lua:1013`) and hands the choice the
  asker as its target. So a codex offer holding two Final Showdowns in front of a
  seat with no Balance hero is a question the engine cannot answer, and the game
  stops with a legal move on the table — one in forty random Codex games, seed 5,
  around move 231. A player at the screen is not blocked: `flow.play_card(card, {})`
  succeeds there. The fix is to ask `flow` whether the card is being chosen before
  reaching for its target spec, which is the same question `choosing()` already
  answers inside flow.

- **Nothing can say "this card costs nothing".** Four cards want it and none of
  them is an aim, so `adjusts` cannot reach any of them — it is keyed on a verb
  and a chosen target, and a unit played out of a hand has neither. **Guargum,
  Eternal Sentinel**: *"Resist 2, obliterate 4. You may play Growth spells for
  free and without having a Growth hero."* **Pirate-Gang Commander**: *"Arrives:
  summon three 2/2 red Pirate tokens. Your units have 'Dies: deal 1 damage to
  each opposing base' and you may play tech I or II Blood units for free."*
  **Cinderblast Dragon**: *"Flying, resist 2. Arrives or attacks: you may play a
  non-ultimate Fire spell from your hand or codex for free."* These three want a word on a tag that shifts what a *class of card* costs its
  owner, the way `pays_for` says one pool settles another. Cost adjusts can subtract now (`resisted` is signed
  and `plan` clamps at free), which is the right shape and reaches none of them.


- **Sparkshot cannot be lent.** It is the last of **Wandering Mimic**'s six:
  *"As long as a unit or hero with flying is in play, Wandering Mimic has flying.
  The same is true for overpower, haste, sparkshot, untargetable and stealth."*
  Flying, stealth, overpower, haste and untargetable are all copied now. Sparkshot
  is read as `count:sparkshot@self` on the attacker in the middle of the duel
  walk, by `strike_lead`'s own action list, so a union tag would have to be
  threaded through the combat columns rather than declared once the way `hasty`
  is. Worth doing only if a second card ever wants to grant it.

- **An offer opened from a departure is re-entrant, and it lends the base out.**
  Crash Bomber's own-turn half — *"Dies on your turn: deal 1 damage to a patroller
  or building. Dies on another player's turn: deal 1 damage to that player's
  base."* — can be written now that `leaves` has a `needs`: the departing card
  opens `show:enemy.bombable:optional` and its own `chosen` resolves the pick from
  the discard it landed in. It works in isolation. Pointed at twenty bot games it
  hangs two of them: the offer opens inside `r_units`' death sweep and the sweep
  can reach it again, and worse, `show:` **borrows** what it shows — so the base
  sits in the offer zone rather than in `base`, and `integrity@enemy.base` finds
  nothing, which is an end condition that cannot fire while the question is open.
  Two things would fix it: a way to offer a card without moving it, and a guard on
  opening an overlay from inside a `leaves`. Until then the bomber does the base
  half only, and the note on the card says so.
