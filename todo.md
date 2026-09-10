Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

- **What the whole box wants.** All 330 Codex cards are in the file now: red,
  green and blue play; black, white, purple and the two neutral specs are
  *scaffolding* — printed for their numbers and their text, tagged `scaffold`,
  with none of what they say running. They are not inert, because the tag-level
  `play` and the fighter abilities reach them like anything else, so a scaffolded
  unit is a vanilla one of the right size. Every card's art is listed in
  `ideas/codex/card_art.md`. Counting mechanics over all 330 rather than over the
  92 we had changes the order of this list, and the top of it is not what the blue
  survey guessed:

  - **Sacrifice as an effect — 30 cards, 23 new.** `sacrifice:<tag>` exists only
    as a *cost*, takes the oldest match, and the player never chooses. *"Sacrifice
    a unit. If you do…"* is a choice with a consequence, and *"Sacrifice this →"*
    is a card spending itself, which the cost cannot say either since a cost
    cannot name its own card.

  - **Forecast — 7 cards, the whole of purple's Future spec.** *"Starts off in the
    future, not in play. Put three time runes on this and remove one each upkeep.
    When you remove the last, it arrives."* A zone that is not in play, a counter
    ticking at the upkeep, and an arrival when it empties — most of which the file
    can already say. What it cannot say is Hardened Mox's *"when you have a tech II
    unit (even a forecasted one)"*, which asks about a card that is deliberately
    nowhere.

  - **Sideline — 15 cards, 8 new.** Move a unit out of the patrol zone. Written
    inline three times in blue already (`stat_set:slot@x:0`, `stat_set:guard@x:0`,
    `move:x:…army`); a name for it would stop the fourth being written wrong.

  - **Return to hand — 12 cards, 8 new.** A bounce, and half the time a death
    replacement. With Brave Knight, Justice Juggernaut's Two Lives, Reteller of
    Truths and purple's Indestructible, *replacing* a death is now five cards and
    wants generalising rather than another rules column each.

  - **Swift strike — 6 cards, 4 new.** A blow struck before the exchange rather
    than in it. Ferocity and The Art of War already say so on the card.

- **Blue's gaps, grouped.** Blue is in and playable — Bigby, Onimaru and Sirus all
  win games against red and green. What it could not say, worst first. The full
  rule for each card is on the card, in its own tooltip.

  - **An aim has no answering moment, so an Illusion cannot die of being pointed
    at.** *"Illusions die when they are targeted by spells or abilities"* is the
    whole of the Truth spec: **Spectral Aven, Hound, Flagbearer, Roc, Tiger**,
    **Reteller of Truths**, **Liberty Gryphon**, and the three cards that hand the
    word out — **Dreamscape**, **Hallucination**, **Macciatus** (who takes it
    away). `receive.needs` already reads an aim and answers yes or no; what is
    missing is the *write* half. A zone has both (`accepts` and `on_receive`); a
    card and a tag have only the first. `receive: { needs: [...], action: [...] }`,
    run on each chosen target once the aim resolves, is the same word finished —
    and it would also give **Guardian of the Gates** its disable-on-damage and
    **Spectral Flagbearer** half of its compulsion. Ten cards.

  - **A card cannot become another card and come back.** `transform` destroys and
    creates, keeping no memory of what it replaced. **Manufactured Truth** and
    both of **Sirus Quince**'s copying levels want it, and so does Green's
    **Polymorph: Squirrel** and **Fairie Dragon**. Five cards across two colours.

  - **Obliterate still takes the first units rather than the lowest tech ones.**
    **Lawbringer Gryphon** is the third customer, after Pirate Gunship and
    Guargum. `QUANTS` is `any / each / random / others`; a phase's `order` already
    spells `highest:<stat>`.

  - Single-customer, listed so they are not rediscovered: **Jail** (nothing can
    redirect somebody else's play), **Reputable Newsman** (a choice is made among
    cards, and a number is not one), **Censorship Council** (no card may put a
    condition on what another player may play), **Free Speech** (nothing takes a
    card's abilities away), **Building Inspector** (a cost is adjustable only
    through an aim, and a building is raised from a board button), **Jurisdiction**
    (a pick out of an offer cannot then pay a price the picked card names),
    **Eyes of the Chancellor** (hands revealed), **Bigby's stash** (nothing may be
    held back through the draw), **Traffic Director** (unstoppable against one
    kind of target only), **Drill Sergeant** (spending a rune to move it), **The
    Art of War** and **Ferocity** both want swift strike.

  - **Modelled with a stated simplification:** **Insurance Agent** insures only
    your own units, because a rune does not remember who put it there; **Brave
    Knight** returns to hand from any death rather than only from combat damage;
    **Community Service** and **Lawful Search** look at a hand but not at the
    choice of a discard pile instead.

- **An empty pool answers 0 to `max:` and `sum:`, and is absent to `min:`.**
  Deliberate and tested — *"nothing adds to nothing, nothing is at most nothing"*,
  while a zero minimum would sit below every real value and open a gate exactly
  when the thing it measures is not there. Six live conditions lean on it:
  `max:level@enemy.h_blood <= 3` means yes when they hold no Blood hero at all,
  and The Crew's four `max:v_<colour>@mine.hand <= min` say the same about a suit
  nobody holds. Worth re-reading only if a card ever wants the other answer, and
  then it wants a word rather than a change — the asymmetry is the design.

- **Two validator messages still cannot be reached.** 300 of 302 `warn()` calls
  fire under the suite now, measured by counting the lines a full run touches
  rather than by matching prose. The two left are both in the action-argument
  walk and both look like the *binder* rather than the check: `"cannot take cards
  out of 'origin'"` has a twin one loop above that does fire, and `"it should be
  'top' or 'bottom', or a count and then one"` wants an argument to land in an
  `n?` slot where every spelling tried put it in `pos?` instead. Worth an hour on
  `SPEC` argument binding rather than on the messages.

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
