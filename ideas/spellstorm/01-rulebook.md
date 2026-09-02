# Spellstorm — Rulebook

Source: `ideas/Spellstorm/Spellstorm Rulebook.pdf` (20 pages, Aug 2024). Raw text in `raw/rulebook-layout.txt`.
Designed by Keith Burgun. Art by Christina Zhong (Rain of Toads by Peter Siecienski, Robot Boy by Keith Burgun).

## Introduction & Goal

Tactical deckbuilding card game for **1–4 players**. Choose one of eight wizards with wildly asymmetrical
powers and battle in the Spellstorm. Acquire cards, collect resources, cast spells.

**Win by collecting 8 Storm Shards, or by reducing every opponent's health to 0.**

## Components

| Count | Component |
|---|---|
| 1 | Battle Board |
| 1 | Spellstorm Board |
| 4 | Stat Boards |
| 1 | Initiative Tracker |
| 4 | Storm Shard Markers |
| 25 | Power Tokens |
| 25 | Mana Tokens |
| 4 | Health Markers |
| 4 | DOOM Tokens (Croh Vosh) |
| 3 | Energy Tokens (May Danaris) |
| 6 | Research Tokens (Abragail) |
| 63 | Spell Cards (includes four 6-card starting decks and 3 Essence cards) |
| 16 | Wizard Spell Cards (2 per wizard) |
| 23 | Special Cards (6 Ice, 6 Ash, 6 Curse, 5 Dragons) |
| 24 | Weather Cards (8 Calm Before the Storm, 16 standard) |
| 3 | Trap Cards (Omar Evans) |
| 9 | Potion Cards (Oren Bark) |
| 8 | Wizard Character Cards |
| 1 | Abragail's Research Journal |
| 1 | Oren Bark's Chemistry Board |
| 1 | Robot Boy Character Card |
| 9 | Robot Boy Spell Cards |
| 3 | Element Tokens (Oren Bark) |
| 6 | Blast Tokens (Robot Boy) |

## Setup

1. Place the Battle Board and the Spellstorm Board in the middle of the table.
2. Place the Ash, Curse and Ice card decks **face-up** on their slots on the Spellstorm Board.
3. Shuffle the Dragon Deck and place it **face-up** in its slot.
4. Find the three Essence cards in the Spellstorm Deck (small "E" icon, bottom left) and place them into any
   of the Storm Cloud spots. Shuffle the Spellstorm Deck, place it face-down on its off-board spot, then draw
   2 more cards into the remaining 2 Storm Cloud spots. The Storm Cloud always holds **5** cards.
5. Shuffle the 8 "Calm Before the Storm" Weather cards and the 16 regular Weather cards *separately*. Place
   the Calm cards **on top** of the regular ones to form the Weather Deck.

### Player setup

1. Each player takes a 6-card Basic Spell Deck, a Stat Board, a Health Marker and a Storm Shard Marker.
2. Each player selects a Wizard. (First game: Derby and Eve.)
3. Take the large Wizard Character Card, its 2 Wizard Spell Cards, and any special components.
4. Set health to the number in the heart icon on the Wizard Character Card; place the Health Marker there.
5. The player with the **lower** Initiative number takes the Initiative Tracker. (Derby, of Derby vs Eve.)
6. Shuffle the two Wizard Spell Cards into the Starting Deck (8 cards total); place it face-down.
7. Each player starts with **2 mana**.

Board layout notes: the Spellstorm Board holds the Storm Cloud slots (spell cards available to gain), the
Dragon slot (face-up), the Weather Deck slot, the three Special Card slots (Ice/Curse/Ash, face-up), the
Spellstorm Deck spot, and the **VOID** (starts empty). The Stat Board holds the Power Track, Tier Slots,
Health Track and Storm Shard Track. The Battle Board holds the Initiative spot and each player's battle card spot.

## Game structure

Two alternating parts, repeating until someone wins:

- **Battle Phase** — four rounds of playing cards.
- **Regroup Phase** — score Storm Shards and gain a new card from the Storm Cloud.

### Battle Phase

At the start of a battle, each player draws from their deck until they have **3 cards in hand**. (First battle:
draw 3. Later battles: you already hold 1 card gained from the Storm Cloud, so draw 2.)

Whenever you need to draw, reveal or otherwise access your deck and it is empty, immediately reshuffle your
discard to form the new Draw Deck.

Each of the four rounds:

1. **Flip Weather Card.** Flip the round's Weather card face-up; all players resolve it. Only ever one active
   Weather card — earlier rounds' cards are inactive.
2. **Play a Card.** All players play one card from hand, face-down, to their Battle Card spot.
3. **Reveal.** All reveal simultaneously. Compare the element icon (top left) and check for COUNTERS.
4. **Resolve.** Starting with the player who has Initiative, each player resolves their card. Then move
   played cards to the discard.

#### Countering

The Elemental Counter Wheel: **Fire beats Earth, Earth beats Water, Water beats Fire.**

If the card you played COUNTERS the next clockwise opponent, **you draw a card**.

#### Unplayable hand

At the Play a Card step, if your hand is entirely cards that can't be played (Ice, Curse, Ash): reveal them,
discard them all (their discard effects trigger), take **1 damage** on top of any damage from the discards,
then draw a new hand of 4 cards. Repeat if the new hand is also unplayable.

### Regroup Phase

1. **Discard Weather Cards.** Discard the four Weather cards from the battle.
2. **Discard Effects.** All players discard every card in hand that has a DISCARD EFFECT (white border,
   discard symbol top right) and trigger those effects. You choose the order. (Each ICE discarded here gives
   -1 for the next step.)
3. **Blast Scoring.** Count and discard the cards remaining in hand — that count is your **Blast Score**.
   - Single highest Blast Score → gain **2 Storm Shards**.
   - Two or more tied for highest → those players gain **1 Storm Shard** each.
   - Reaching 8 Storm Shards wins immediately.
4. **Gain Spell Step.** Each player gains **exactly one** card from the Storm Cloud, starting with the player
   with Initiative, then clockwise.
   - Cards have a Tier icon (I, II, III, IV) bottom right. You may only take a card at or below your Tier.
   - If there is no card you can or want to take, you **must** take one of the free Special Cards (ICE, CURSE
     or ASH). If that pile is empty, do what's printed on that spot on the board instead.
   - If the Spellstorm Deck is depleted, reshuffle the VOID to become the new Spellstorm Deck.
   - Gained cards go to your **hand** unless the card says otherwise (e.g. ICE goes to discard).
   - After gaining, draw until you have a hand of **three** cards. (Robot Boy does neither; he starts the
     battle with no Blast Tokens.)
   - **After any card leaves the Storm Cloud, immediately draw a replacement.**

## Spell cards

Card anatomy: Element (top left) · Type · Name · Discard Symbol (top right) · art · Spell effect ·
Discard effect · Flavor text · Spell Tier (bottom right).

To **RESOLVE** a spell card is to do everything on it *except* its "On Discard" effect.

| Symbol | Meaning |
|---|---|
| Draw | Draw a card from your deck into your hand. (Empty deck → reshuffle discard first.) |
| Gain Card | You **may** gain a card from the Spellstorm of your Tier or lower. It goes to your hand unless specified. Always optional unless the card says MUST. |
| On Discard | Triggers when you discard the card, typically at end of battle. Does **not** trigger when you play a card in battle (playing RESOLVES it), nor when you VOID a card. |
| Gain Mana | Gain 1 mana from the supply onto your Stat Board. Mana is mainly for your Ultimate. |
| Power Up | Gain 1 Power Token onto your Power Track. |
| Initiative | Gain: take the Initiative Tracker. Lose: hand it to the next clockwise player. |
| Ultimate | If you have the required mana, you may discard that much to use your Ultimate Ability. |
| Damage | "Deal 1 damage" = 1 damage to **all** opponents. "Deal 1 damage to an opponent" = you choose one. |
| Give an ICE/ASH/CURSE | All opponents gain one of that type, to their **discard**. If none are left, do what's printed on that board spot. |
| VOID | Place the card in the VOID spot — unless it's an ICE/ASH/CURSE, which goes back to its supply pile. |

### Power, Tier and Dragons

You start at **Tier I**, so you may only gain Tier I spells. The Power Track has **6 octagonal slots**.
Place each new Power Token in an empty slot. When the track is full and you'd place another:

- Put the new token in the lowest empty Tier slot on your Stat Board (first time → the "II" slot, meaning you
  are now Tier II; next time → "III").
- Return the other six tokens to the supply.
- If you were already at **Tier III** and fill the track, remove all six tokens and you may gain a powerful
  **Tier IV Dragon** card.

Power Tokens sitting on your Tier II and III spots can **never** be lost. "Lose 1 Power Token" returns one
token from your Power Track, if you have any; otherwise ignore it. You cannot lose a Tier this way.

### Initiative

At all times exactly one player holds the Initiative Tracker. It determines the order everything happens in:
the holder goes first, then clockwise.

## Wizards

Eight asymmetrical wizards. Each is defined by their Wizard Character Card, 2 Wizard Spell Cards, and any
special components. Each wizard is best at two of the three elements.

Wizard Character Card sections:

- **Game Start** — happens once, at the start of the game.
- **Battle Start** — happens at the start of each Battle Phase, before the first Weather card.
- **Passive Ability** — active throughout the game, in both phases.
- **Starting Health** — where the Health Marker begins. Wizards can never exceed starting health
  (Bunny Wizard excepted).
- **Initiative Rating** — lowest number takes the Initiative Tracker at game start.
- **Ultimate Ability** with a mana cost (usually ~5).

The back of each Wizard Character Card is a quick reference.

**Using your Ultimate:** activate it while resolving a spell card that has the Ultimate icon, if you have the
mana. Return the mana to the supply and resolve the Ultimate fully before continuing with the rest of the card.

**Wizard Spell Cards** go into your starting deck and **can never be voided** (small icon, bottom right).

## Game end

The game ends the moment a player gains their 8th Storm Shard, or all of a player's opponents are at 0 health.
Health cannot go below 0.

Tiebreakers:

- Simultaneous 0 health → the player with more Storm Shards wins.
- Simultaneous 8 Storm Shards → the player with the most health wins.
- Still tied → the player with the Initiative Tracker wins. (In a FFA where neither tied player has it, the
  one closest to receiving it next wins.)

## Basic strategy (from the book)

- Want to kill the opponent before they reach 8 Shards? Gain more **Fire** cards.
- Want Power Tokens, Tiers and Dragons? Gain more **Earth** cards.
- Want the long game, disrupting their deck and healing? Gain more **Water** cards.

Elements counter each other both tactically (on reveal) and strategically.

## Alternate game modes

### Single player — vs Robot Boy

Set Robot Boy up as another player: Stat Board, Character Card, health **15**. Shuffle his 9-card deck, draw
two cards — one face-up, one face-down — onto his Character Card.

Difficulty: Easy / Medium / Hard = he starts with **0 / 2 / 4** Power Tokens. Always 0 mana and 0 Blast Tokens.

Robot Boy has no hand. When he would draw or discard a card (weather, countering, anything), he instead gains
or loses that many **Blast Tokens**, which are his Blast Score. Return them all after Blast Scoring. Only 6
exist, so his Blast Score caps at 6.

Each round, after you play your card face-down, play the top card of his deck opposite yours, then flip and
resolve as usual.

- He never gains cards from the Storm Cloud, but can gain ICE, CURSES and ASH. Anything else that would enter
  his possession is VOIDED.
- When he reveals an ICE/ASH/CURSE, use it to COUNTER as usual, then reveal more cards from his deck until a
  Robot Boy card appears (don't re-check COUNTER). Resolve and then discard all revealed cards.
- His Ultimate always triggers at the end of his turn if he has the mana: discard it, resolve the face-up card
  on his Character Card, then flip and resolve the face-down one, then draw a new face-up and face-down pair.
  (Two cards on his Character Card at all times.)
- If he'd increase his Tier while already Tier III, he instantly resolves the top Dragon card.
- He can win via either victory condition. His starting cards cannot be voided.
- Anything checking "current hand size" checks his Blast Tokens instead; "discard a random card" loses him 1.
- Any decision Robot Boy must make is made collectively by all players (also true in Co-op).

### Co-op (2–4 players vs Robot Boy)

- ICE/CURSE/ASH you give go only to Robot Boy.
- No damage to allies — only to Robot Boy.
- When you HEAL, you may heal an ally instead.
- If any player wins, the whole team wins. The team continues if a player is eliminated.

### Two on Two

Two vs two. Co-op's damage, healing and victory rules apply.

### Free for All (3 or 4 players)

Same as 2-player, except:

- Each player starts with **2 Storm Shards**.
- Players at 0 health are eliminated. They lose initiative (hand off clockwise), and their deck, discard, hand
  and played cards go into the VOID **face-up** — other players can eventually pick up their Wizard Spell Cards.

## FAQ

- **Hand limit?** No.
- **Can the game be a draw?** No — see tiebreakers.
- **Where does a gained card go?** Your HAND, unless the card says otherwise.
- **Empty deck when drawing/revealing?** Immediately reshuffle discard into a new deck. If your entire deck
  and discard are in your hand, you simply don't draw.
- **Where do VOIDED cards go?** The VOID, next to the Spellstorm Deck. Exceptions: Wizard Spell Cards can
  never be voided for any reason; voided ICE/CURSE/ASH return to their piles on the Storm Board. If the
  Spellstorm Deck is depleted, reshuffle the VOID into it.
- **"Resolve another card"** — resolve a card straight from your hand as if played to the board. Both cards
  then go to your discard, and neither triggers its discard effect (both were played).
- **"Reveal"** — refers specifically to the face-down battle card revealed simultaneously, nothing else.
  There is exactly one "reveal" per player per round.
- **What's optional?** Everything on a card is mandatory if you can do it, except "you may X" and the
  Gain Card icon (always optional unless the card says MUST, e.g. Amber). The Gain Spell Step of Regroup is
  mandatory.
- **Discard order at end of round?** Any order you prefer — it can matter.
- **Can I look through any discard pile?** Yes. All face-up cards are public, including the Dragon Deck and
  the VOID.
- **Abragail's upgrades:** her Ultimate adds one token to an empty space on her Journal (while she has tokens
  left). At the start of each **battle** (not round) she activates all researched powers, in any order.
- **Robot Boy and "discard your hand"** (e.g. Wave): yes, he discards all Blast Tokens, then gains one Blast
  Token per card he would have drawn afterwards.
- **Omar's trap:** you may decline to trigger it. You may reveal his Dodge trap even when an opponent deals
  0 damage to you.
- **Croh and May's tokens:** gained tokens go onto slots on the character card; losing one takes it off.
- **Ultimate inside an Ultimate?** Yes, as long as you have another icon and the mana.
- **Oren's Ultimate:** pay the mana, shuffle the Potion Deck, draw the top card. If you have the amount of the
  shown Chemistry Board element, lower that element by that much and resolve the effect. You may then stop or
  draw again, as often as you like. Drawing a **third TOXIC** card ends the Ultimate and Oren gains 1 ICE,
  1 ASH and 1 CURSE.
- **Playing a card then discarding it — discard effect?** No.

## Setting

Spellstorm is set in the **Gem Wizards Universe**, shared with Dragon Bridge and the tactical digital wargame
Gem Wizards Tactics. The world is **Omia**; the Spellstorm is a rocky crag in the bay north of the Ashen Char,
surrounded by violent storms and magical Dragons, holding **Storm Shards** of immense magical power.

Recurring names: the Business Demons and Bill Milton; Terre de Pomme and the Rootkin; the Zuzuni (Bug People)
of Tiya Bannet; the Azure Order (formerly the Water Kingdom); Azura Academy; the Harraway Archipelago and
Alcove Prefex; Bunny Island and the Kindred Society; Temple Kress; the shattered Omni-Gem.
