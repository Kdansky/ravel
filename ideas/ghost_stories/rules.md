# Ghost Stories — the rules, transcribed

Antoine Bauza, Repos Production 2008. Transcribed from the scans in
`ideas/Ghost Stories/`: `GS_RULES_US_ver1.2-NB.pdf` (the rulebook),
`GhostStories_v3 ref.pdf` pages 3–4 (Universal Head's play reference, which is
where the village tile and ghost icon wordings below come from),
`Ghost_Stories_Reference_Sheet_Printer_Friendly_EN.pdf` (the publisher's own
play aid) and `Idiots_guide_to_GS_ambiguity_1_1.pdf` (which settles who a ghost
ability is *about*). The 65 cards are read off `4 ghosts 1.jpg`,
`5 ghosts 2.jpg` and `6 ghosts 3.jpg`, five cards to a row, five rows to a
sheet, numbered the way the rulebook's own card list numbers them.

**This file invents nothing.** Where the engine cannot say something, that is
recorded in `ideas/44-ghost-stories.md`, not papered over here.

## The table

Nine Village tiles in a 3×3 square. Four player boards along its sides, each
with three ghost spaces facing the three tiles of its side. A Taoist figurine
stands on a Village tile; the four start on the centre tile.

A tile is **active** (face up, its villager available) or **haunted** (face
down). All nine start active.

Initiation level, four players: 4 Qi each, one Yin-Yang token, one Tao token of
the player's colour and one black Tao token. Two Buddha figurines on the
Buddhist Temple tile.

The deck is 45 ghosts, then one of the ten Wu-Feng incarnations drawn at random
and unseen, then the last 10 ghosts.

## A turn

**Yin phase (the ghosts on the active player's board).**

1. Ghosts' actions — every middle-stone ability of every ghost on this player's
   board, left to right.
   - a **Haunter** advances its haunting figurine: card → first stone → second
     stone. Reaching the second stone haunts the first *active* Village tile in
     front of the ghost and puts the figurine back on the card. So a haunter
     haunts every second turn.
     If all three tiles in front of it are already haunted, the players lose.
   - a **Tormentor** rolls the Curse die: no effect / haunt the first active
     tile in front of the ghost / bring a ghost into play / discard all your Tao
     tokens / lose 1 Qi.
2. Board overrun — if all three of this player's ghost spaces are occupied,
   lose 1 Qi and skip step 3.
3. Arrival — draw the top ghost and place it. A red, green, blue or yellow
   ghost goes on the board of its colour if a space is free, a black ghost on
   the active player's board if a space is free; otherwise the active player
   chooses any free space anywhere. Left-stone abilities apply as soon as the
   space is chosen. If all twelve spaces are full, the active Taoist loses 1 Qi
   instead of a ghost arriving.

**Yang phase (the Taoist).** In this order, with the Yin-Yang usable before or
after any step but never inside one:

1. Move to an adjacent tile, diagonals included. Optional.
2. Either ask the villager on your tile for help, **or** attempt one exorcism.
3. Place a Buddha, if you are holding one and face an empty ghost space.

**An exorcism.** Roll the three Tao dice (faces: red, green, blue, yellow,
black, white; white is wild). You need as many faces of the ghost's colour as
its resistance. Tao tokens of that colour may be spent afterwards to make up the
difference, and you are never obliged to spend one — but if the dice alone
suffice you must exorcise. From a corner tile you face two spaces and may
exorcise both on one roll, splitting the dice as you like. Tao tokens of other
Taoists standing on your own tile may be spent too.

An exorcised ghost is discarded; its right-stone curse is applied first, then
its right-stone reward. A ghost killed by a Buddha or the Sorcerer's Hut applies
neither.

**Death.** A Taoist at 0 Qi is dead. Everything they hold is lost, their board
keeps its ghosts and still plays steps 1 and 2 of its Yin phase, and the
Cemetery can bring them back.

**Winning** is exorcising the incarnation of Wu-Feng. **Losing** is all Taoists
dead, or a fourth Village tile haunted (Initiation; three at Normal and above),
or the deck running out with the incarnation still in play.

## The nine Village tiles

| Tile | What asking it does |
|---|---|
| Cemetery | Return a dead Taoist to the game with 2 Qi, then roll the Curse die |
| Taoist Altar | Turn one haunted tile back to its active side, then bring a ghost into play |
| Herbalist's Shop | Roll 2 Tao dice and take a Tao token of each colour rolled; a white face is any colour you choose |
| Sorcerer's Hut | Discard any ghost in play, without its ability or its reward. Lose 1 Qi |
| Buddhist Temple | Take a Buddha figurine; you may place it from your next turn on |
| Night Watchman's Beat | Move every haunting figurine on one board back onto its card |
| Circle of Prayer | Put a Tao token from the supply on this tile, or change the one there. Every ghost of that colour has its resistance reduced by 1, for every Taoist. The token stays |
| Pavilion of the Heavenly Wind | Move one ghost of your choice to any free space, then move a *different* Taoist to any Village tile |
| Tea House | Take a Tao token of your choice and 1 Qi, then bring a ghost into play |

The Yin-Yang is spent either to ask any villager without standing on their tile,
or to turn one haunted tile back to its active side.

## The ghost icons

Sixteen, from the play aid. A left stone fires when the card is laid, a middle
stone each Yin phase of the board it sits on, a right stone when it is
exorcised; a middle stone that is a *state* rather than an action holds for as
long as the ghost is in play.

| Code | Icon | Meaning |
|---|---|---|
| `G` | white tile, 鬼 | bring a new ghost into play |
| `H` | tile with a figure on it | haunt the first active Village tile in front of the ghost |
| `QI-` | −1 Qi | the Taoist loses 1 Qi |
| `HAUNTER` | a figurine | place a haunting figurine on the card; advance it each Yin phase |
| `QUICK` | figurine, red arrow | the figurine starts on the board rather than on the card |
| `CURSE` | black die, 鬼 | roll the Curse die |
| `R_QI` | Qi and Yin-Yang | gain 1 Qi **or** take your Yin-Yang back |
| `R_TAO` | four dots | gain 1 Tao token of your choice |
| `R_TAO2` | four dots, 2 | gain 2 Tao tokens of your choice |
| `POWER_OFF` | crossed creature | the board this ghost sits on loses its power while it lives |
| `DICE_OFF` | quartered shield | Tao dice do nothing to this ghost. Tokens, the Circle, Buddhas and the Sorcerer still work |
| `TAO_OFF` | padlock and dots | nobody may spend Tao tokens while it lives (the Circle still works) |
| `DIE_CAPTIVE` | −1 and a die | it holds one Tao die; exorcisms roll one die fewer |
| `GROUP` | a running figure | the ability beside it is about every player and every board |
| `TAO-` | −1 and four dots | lose 1 Tao token, if you have one |
| `INC` | Qi + Yin-Yang | an exorcised incarnation gives the group 1 Qi and 1 Yin-Yang |

## The 55 ghosts

Five colours of eleven, and the eleven are the same shape in every colour. `L`,
`M`, `R` are the three stones.

| # | Name | Colour | Res | L | M | R |
|---|---|---|---|---|---|---|
| 1 | Ghoul | yellow | 1 | | HAUNTER | |
| 2 | Walking Corpse | yellow | 1 | | DICE_OFF | |
| 3 | Coffin Breakers | yellow | 1 | G | POWER_OFF | |
| 4 | Coffin Breakers | yellow | 1 | G | | |
| 5 | Restless Dead | yellow | 2 | | HAUNTER | |
| 6 | Zombie | yellow | 2 | | | CURSE |
| 7 | Zombie | yellow | 2 | | | CURSE |
| 8 | Hopping Vampire | yellow | 3 | | HAUNTER | |
| 9 | Hopping Vampire | yellow | 3 | | HAUNTER | |
| 10 | Yellow Plague | yellow | 3 | | | R_TAO2 |
| 11 | Lich | yellow | 4 | | CURSE | R_QI |
| 12 | Drowned Maiden | blue | 1 | | HAUNTER | |
| 13 | Hound of Depth | blue | 1 | | DICE_OFF | |
| 14 | Perfidious Nymph | blue | 1 | G | POWER_OFF | |
| 15 | Perfidious Nymph | blue | 1 | G | | |
| 16 | Sticky Feet | blue | 2 | | HAUNTER | |
| 17 | Abysmal | blue | 2 | | | CURSE |
| 18 | Abysmal | blue | 2 | | | CURSE |
| 19 | Ooze Devil | blue | 3 | | HAUNTER | |
| 20 | Ooze Devil | blue | 3 | | HAUNTER | |
| 21 | Liquid Horror | blue | 4 | | | R_TAO2 |
| 22 | Fury of Depth | blue | 4 | | CURSE | R_QI |
| 23 | Creeping One | green | 1 | | HAUNTER | |
| 24 | Fungus Thing | green | 1 | | DICE_OFF | |
| 25 | Fallen Monks | green | 1 | G | POWER_OFF | |
| 26 | Fallen Monk | green | 1 | G | | |
| 27 | Restless Spirit | green | 2 | | HAUNTER | |
| 28 | Rotten Soul | green | 2 | | | CURSE |
| 29 | Rotten Soul | green | 2 | | | CURSE |
| 30 | Wicked One | green | 3 | | HAUNTER | |
| 31 | Wicked One | green | 3 | | HAUNTER | |
| 32 | Green Abomination | green | 4 | | | R_TAO2 |
| 33 | Great Putrid | green | 4 | | CURSE | R_QI |
| 34 | Skinner | red | 1 | | HAUNTER | |
| 35 | Reaper | red | 1 | | DICE_OFF | |
| 36 | Sharp-Nailed Mistresses | red | 1 | G | POWER_OFF | |
| 37 | Sharp-Nailed Mistresses | red | 1 | G | | |
| 38 | Bleeding Eyes | red | 2 | | HAUNTER | |
| 39 | Blood Drinker | red | 2 | | | CURSE |
| 40 | Blood Drinker | red | 2 | | | CURSE |
| 41 | Scarlet Evildoer | red | 3 | | HAUNTER | |
| 42 | Scarlet Evildoer | red | 3 | | HAUNTER | |
| 43 | Flesh Devourer | red | 4 | | | R_TAO2 |
| 44 | Raging One | red | 4 | | CURSE | R_QI |
| 45 | Gloomy Minion | black | 1 | QUICK | HAUNTER | R_TAO |
| 46 | Repellent Beauty | black | 1 | DIE_CAPTIVE | DICE_OFF | R_TAO |
| 47 | Severed Heads | black | 1 | DIE_CAPTIVE, G | | R_TAO |
| 48 | Severed Heads | black | 1 | DIE_CAPTIVE, G | | R_TAO |
| 49 | Grave Walker | black | 2 | QI- | HAUNTER | R_QI |
| 50 | Black Widow | black | 2 | TAO_OFF | | CURSE, R_QI |
| 51 | Black Widow | black | 2 | TAO_OFF | | CURSE, R_QI |
| 52 | Dark Wraith | black | 3 | QUICK | HAUNTER | R_QI |
| 53 | Dark Wraith | black | 3 | QUICK | HAUNTER | R_QI |
| 54 | Shapeless Evil | black | 2 | H | | R_QI |
| 55 | Soul Eater | black | 2 | GROUP, TAO- | CURSE | R_QI |

## The ten incarnations

Each is a ghost with a colour, a resistance and one rule of its own, and every
one gives the group 1 Qi and 1 Yin-Yang when exorcised. Exorcising the
incarnation wins the game.

| # | Name | Colour | Res | Its own rule |
|---|---|---|---|---|
| 56 | Howling Nightmare | black | 3 | May only be exorcised while the ghost space facing it on the opposite board is empty. Brings a ghost into play on arrival |
| 57 | Uncatchable | black | 3 | May only be exorcised while it stands on a space holding a Buddha — the only incarnation a Buddha affects. Brings a ghost into play on arrival |
| 58 | Hope Killer | multi | 2 each of blue, red, green, yellow | Roll the Curse die when it is exorcised |
| 59 | Death Army | black | 5 | A Tormentor: roll the Curse die each Yin phase, and again when it is exorcised |
| 60 | Forgotten Ones | black | 3 | While it lives no Taoist may use their power, Power tokens included |
| 61 | Bone Cracker | red | 4 | Every player discards a Tao token when it arrives, and again at the start of each Yin phase of the board it sits on |
| 62 | Dark Mistress | blue | 3 | While it lives nobody may spend Tao tokens. The Circle of Prayer still works |
| 63 | Creeping Horror | green | 4 | Holds a Tao die captive while it lives |
| 64 | Vampire Lord | yellow | 4 | A Haunter, and nothing else |
| 65 | Nameless | multi | 1 each of blue, green, yellow, red, black | Discards the Tao token on the Circle of Prayer when it arrives, and the white faces of the Tao dice stop counting as wild |

## What the rulebook says about fewer than four players

Not transcribed, and not built: boards with nobody behind them become neutral
boards with 3 Qi, a shorter Yin phase and no Yang phase, and the players get
Power tokens to borrow those boards' powers. Four seats is the rulebook's own
default and the only arrangement with no neutral board in it.

## The eight Taoist powers

Two per board, one used per game.

| Board | Power | What it does |
|---|---|---|
| Yellow | Bottomless Pockets | Before your move, take a Tao token of any colour |
| Yellow | Enfeeblement Mantra | Before your move, put the Mantra on any ghost: its resistance is 1 lower for everybody |
| Red | Dance of the Spires | You may move to any Village tile, not only an adjacent one |
| Red | Dance of the Twin Winds | Before your move, move one other Taoist one space |
| Green | The Gods' Favorite | Reroll any Tao dice, and the Curse die; the second result stands |
| Green | Strength of a Mountain | A fourth Tao die on exorcisms, and you never roll the Curse die |
| Blue | Heavenly Gust | Ask a villager **and** attempt an exorcism, in either order |
| Blue | Second Wind | Ask twice, or exorcise twice; the two rolls are separate |
