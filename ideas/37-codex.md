# 37 — Codex

Built and playing, and the biggest game in the box by a distance. All 330 cards
are in the file: red, green and blue play; black, white, purple and the two
neutral specs are *scaffolding* — printed for their numbers and their text,
tagged `scaffold`, with none of what they say running. They are not inert,
because the tag-level `play` and the fighter abilities reach them like anything
else, so a scaffolded unit is a vanilla one of the right size. Every card's art
is listed in [codex/card_art.md](codex/card_art.md), and the card text comes from
codexcarddb.com rather than from the JPEGs.

What follows is what the box still cannot say, counted over all 330 rather than
over the 92 that were in when blue was surveyed — which changes the order, and
the top of it is not what that survey guessed.

## What the whole box wants

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

## Blue's gaps, grouped

Blue is in and playable — Bigby, Onimaru and Sirus all win games against red and
green. What it could not say, worst first. The full rule for each card is on the
card, in its own tooltip.

- **The Truth spec's remainder.** An Illusion dies of being aimed at, which
  `receive`'s `when` and `action` say on the tag. What is left wants its own
  word each:

  - **Macciatus** — *"Your Illusions get +1/+1 and no longer die when a spell or
    ability aims at them."* The **dying** half is writable now: `receive`'s
    `when` and `action` run as the aimed-at card's own owner, so `mine` inside
    them is the Illusion's controller and the exception can be a condition on
    the keyword. It wanted no word — `zones.as_seat` already held the seat over
    a call, and `give_priority` would have been wrong for it, being game state
    that drops undo.

    The **+1/+1** half is still stuck, and on the wider question: a `buffs` or
    `adjusts` block is asked ambiently, about a card, at no moment and with
    nobody acting, so there is no seat to hold. See README §67.
  - **Dreamscape** and **Hallucination** — *"All tech 0, I and II units are
    Illusions"* and *"Up to two tech 0, I or II units are Illusions this turn"*.
    Handing a tag out, which nothing does; the dying they would hand out is in.
  - **Guardian of the Gates** and **Spectral Flagbearer**'s compulsion, both of
    which the word now reaches and neither of which is written yet.

- **A card cannot become another card and come back.** `transform` destroys and
  creates, keeping no memory of what it replaced. **Manufactured Truth** and
  both of **Sirus Quince**'s copying levels want it, and so does Green's
  **Polymorph: Squirrel** and **Fairie Dragon**. Five cards across two colours.

- **Obliterate still takes the first units rather than the lowest tech ones.**
  **Lawbringer Gryphon** is the third customer, after Pirate Gunship and
  Guargum. `QUANTS` is `any / each / random / others`; a phase's `order` already
  spells `highest:<stat>`.

- **Jandra, the Negator** is writable now: *"spells and abilities aimed at your
  other cards hit Jandra instead"* is a mandatory reaction whose `where` reads
  the aim through `@target` and whose action is `redirect:answered:self`. Both
  halves shipped with the stack words; what is left is writing the card.

- Single-customer, listed so they are not rediscovered: **Jail** (nothing can
  redirect somebody else's *play* — a destination, not an aim, so the stack
  words do not reach it), **Reputable Newsman** (a choice is made among
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

## Six ways into the codex, and five of them are one missing word

The codex is a `supply` now, so `show:mine.codex` answered by
`take:target:<zone>:1` is the whole of fetching, and three cards do it — Warp
Gate Disciple, Circle of Life, Calamandra's tiger. Five more all failed at one
joint: a pick out of an offer resolved and stopped, so nothing could follow it.

**That joint is open.** An action list waits for the question it asked, and a
`chosen` block is an action list — so a pick may now ask a second question and
carry on afterwards (`tests/integration/offer_queue.lua`, *a pick may ask and
then carry on*). Three of the five are a matter of writing the card now, and
worth trying the next time Codex is opened: **Vandy**, whose price is a discard,
and **Feral Strike** and **Temporal Distortion**, which each want the pick to
then aim somewhere. The other two are not about ordering at all —
**Jurisdiction** wants the pick to pay a price the *picked card* names, and
**Cinderblast Dragon** wants it to cost nothing, which is the cost-adjust gap
below.

The sixth, **Rambasa Twin**, is the only one the box already answered: going back
to the codex is `purge:self`, and what is still missing there is the death
replacement it shares with four other cards.

## The tech offer is public, and the rulebook makes the hidden pick a rule

*"Every time you put two cards from your codex face down into your discard pile,
other players won't know what you put there… Think of it like a fog of war."*
`show:mine.codex` lends the shelves to the shared `options` zone, which has no
seat, and `zones.visible` only hides an `owner` zone that has one — so both
clients draw the whole codex and the shelf that was taken. Harmless hot-seat,
and the discard is `owner` so only the moment of the pick leaks. Fixing it wants
an offer that belongs to the seat that asked, and there is exactly one `options`
zone and one overlay by design, so this is a question about that design rather
than a line to change.

## Nothing can say "this card costs nothing"

Four cards want it and none of them is an aim, so `adjusts` cannot reach any of
them — it is keyed on a verb and a chosen target, and a unit played out of a hand
has neither. **Guargum, Eternal Sentinel**: *"Resist 2, obliterate 4. You may
play Growth spells for free and without having a Growth hero."* **Pirate-Gang
Commander**: *"Arrives: summon three 2/2 red Pirate tokens. Your units have 'Dies:
deal 1 damage to each opposing base' and you may play tech I or II Blood units
for free."* **Cinderblast Dragon**: *"Flying, resist 2. Arrives or attacks: you
may play a non-ultimate Fire spell from your hand or codex for free."* These
three want a word on a tag that shifts what a *class of card* costs its owner,
the way `pays_for` says one pool settles another. **Cinderblast Dragon may be
reachable another way now**: a card put into the `todo` zone is played free by
construction, so *"play a non-ultimate Fire spell from your hand or codex for
free"* could be a fetch that mints rather than a cost that is adjusted. Worth
trying before writing the word. The same trick is what **Jurisdiction** wants
from the other end — a pick that then pays the price the picked card names is an
ordinary play, if the pick is handed over to be played rather than resolved. Cost adjusts can subtract now
(`resisted` is signed and `plan` clamps at free), which is the right shape and
reaches none of them.

## Sparkshot cannot be lent

The last of **Wandering Mimic**'s six: *"As long as a unit or hero with flying is
in play, Wandering Mimic has flying. The same is true for overpower, haste,
sparkshot, untargetable and stealth."* Flying, stealth, overpower, haste and
untargetable are all copied now. Sparkshot is read as `count:sparkshot@self` on
the attacker in the middle of the duel walk, by `strike_lead`'s own action list,
so a union tag would have to be threaded through the combat columns rather than
declared once the way `hasty` is. Worth doing only if a second card ever wants to
grant it.
