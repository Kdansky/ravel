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

- **Second Chances** — *"Whenever one of your non-token units leaves play from
  something other than combat damage, return it to play. Once-per-turn. (Choose
  randomly if multiples leave at once.)"* The rest of it fits: a counter like
  Reteller's `retold` and a gate at the end of the `unit` tag's `leaves`, with
  `not_tagged:slain` for the combat damage, plus `reset:self` and the deploy lines,
  because a move onto another board is no reprint. The random choice is what cannot
  be said, since deaths are settled one at a time in the sweep's order. Purple is
  scaffolding, so it waits.

## Blue's gaps, grouped

Blue is in and playable — Bigby, Onimaru and Sirus all win games against red and
green. What it could not say, worst first. The full rule for each card is on the
card, in its own tooltip.

- **The Truth spec's remainder.** An Illusion dies of being aimed at, which
  `receive`'s `when` and `action` say on the tag. What is left wants its own
  word each:

  - **Dreamscape** and **Hallucination** — *"All tech 0, I and II units are
    Illusions"* and *"Up to two tech 0, I or II units are Illusions this turn"*.
    Handing a tag out, which nothing does; the dying they would hand out is in.
  - **Spectral Flagbearer**'s compulsion — an aim narrowed after it is made, which is a word
    nothing has yet (COOKBOOK, *Known gaps*).

- **A card cannot become another card and come back.** `transform` destroys and
  creates, keeping no memory of what it replaced. **Manufactured Truth** and
  both of **Sirus Quince**'s copying levels want it, and so does Green's
  **Polymorph: Squirrel** and **Fairie Dragon**. Five cards across two colours.

- Single-customer, listed so they are not rediscovered: **Jail** (nothing can
  redirect somebody else's *play* — a destination, not an aim, so the stack
  words do not reach it), **Reputable Newsman** (a choice is made among
  cards, and a number is not one), **Censorship Council** (no card may put a
  condition on what another player may play), **Free Speech** (nothing takes a
  card's abilities away), **Building Inspector** (a cost is adjustable only
  through an aim, and a building is raised from a board button),
  **Eyes of the Chancellor** (hands revealed), **Bigby's stash** (nothing may be
  held back through the draw), **Traffic Director** (unstoppable against one
  kind of target only), **Drill Sergeant** (spending a rune to move it).

- **Modelled with a stated simplification:** **Insurance Agent** insures only
  your own units, because a rune does not remember who put it there;
  **Community Service** and **Lawful Search** look at a hand but not at the
  choice of a discard pile instead.

## Three heroes a side: what the 3-hero rules still want

The pick is six colours, each dealing its starter ten, three specs' codex and
three heroes (mono-colour; the rulebook's mixed-colour team is a later variant).
`hero_wait` and `ripe` are each hero's own, levels are gated on
`not_self@mine.command`, and summoning is capped by the `hero_limit` compute —
1, 2 with tech II, 3 with tech III, one more with a heroes' hall. The one-hero
beginner's game is gone.

**The engine question answered no, and did not need to be asked.** An `each`
cannot read the card it stands on: `stat_set` works its amount out once, before
the sweep (`actions.lua`, `HANDLERS["stat_set"]`). `ripe` moved into an `upkeep`
ability on the `hero` tag instead, which the upkeep walk already runs on every
hero in play, as itself.

Left, from the rulebook's *Codex 3-Hero Game* pages (pp. 10–12). The tech lab and heroes' hall
shipped; their costs, 1 and 2 gold, are not in the rulebook and were not checked against the cards.

- **The two neutral specs cannot be declared.** Bashing and Finesse have no
  hero in the file and so no mini-card, which leaves their tech II and III
  unbuildable now rather than free. Scaffolding either way until a neutral
  hero is.
- **A hero's death levels one opposing hero twice.** *"The active player
  chooses which hero if there are multiple opposing heroes, and they can only
  choose a hero that actually can level up at least once."* Modelled as two
  `xp` on the opposing seat, which may be split across heroes — a stated
  simplification.
- **"This card is in play"** has no spelling of its own: a hero's 109 level
  and ability gates read `not_self@mine.command`, which is true because a hero
  is only ever in command or in play. Belongs with
  [17](17-conditions-as-expressions.md)'s readability row (README 70).

## Fetching out of the codex

The codex is a `supply`, so `show:mine.codex` answered by `take:target:<zone>:1` is the whole of
fetching. A pick handed to the `todo` zone is played rather than resolved, which is Jurisdiction
(at the picked card's price) and Cinderblast Dragon (a free copy). **Rambasa Twin** goes back to the codex with `purge:self`; what it still lacks is the death
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

## Sparkshot cannot be lent

The last of **Wandering Mimic**'s six: *"As long as a unit or hero with flying is
in play, Wandering Mimic has flying. The same is true for overpower, haste,
sparkshot, untargetable and stealth."* Flying, stealth, overpower, haste and
untargetable are all copied now. Sparkshot is read as `count:sparkshot@self` on
the attacker in the middle of the duel walk, by `strike_lead`'s own action list,
so a union tag would have to be threaded through the combat columns rather than
declared once the way `hasty` is. Worth doing only if a second card ever wants to
grant it.
