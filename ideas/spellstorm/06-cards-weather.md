# Spellstorm — Weather Cards

Images: `images/weather/` (16 standard) and `images/weather-calm/` (8 Calm Before the Storm).
Landscape cards; the extracted images have been rotated upright.

One Weather card is flipped at the start of each round and resolved by **all** players. Only the current
round's card is active — previous rounds' cards do nothing. Four are used per battle and discarded in Regroup.

The deck is built so the **8 Calm Before the Storm cards sit on top of the 16 standard ones**: the first two
battles are gentle, and the storm escalates as the game goes on. That ramp is the whole point of two decks.

## Calm Before the Storm (8 cards, 7 designs)

Card back: `images/weather-calm/weather-beforethestorm-back.jpg`. Crystal Flurries appears twice.

| Card | Text |
|---|---|
| **Nice Breeze** | `[DRAW]` `[MANA]` `[POWER]` |
| **Crystal Flurries** ×2 | `[DRAW]` `[MANA]`. If you reveal `[WATER]` this round, `[MANA]`. |
| **Heatwave** | `[DRAW]`. If you reveal `[FIRE]` this round, `[MANA]`. |
| **Falling Earth** | `[DRAW]`. If you reveal `[EARTH]` this round, `[POWER]`. |
| **Dust Cloud** | `[DRAW]`, `[POWER]`. All players discard a random card. |
| **Falling Star** | `[DRAW]`. All players may `[GAIN]` (player with `[INIT]` first). |
| **Strange Weather** | `[DRAW]`, `[DRAW]`. Discard the next card in the Weather Deck. |

## Standard Weather (16 cards, 12 designs)

Energy Wave, Ionic Atmosphere, Magnetic Warp and Soothing Rain each appear twice.

| Card | Text |
|---|---|
| **Burning Blizzard** | `[DRAW]`. If you reveal `[FIRE]` this round, `[MANA]` `[MANA]`. |
| **Energy Wave** ×2 | `[DRAW]`. After resolving their cards here, players may use their Ultimate ability (still need the required mana). |
| **Gemlight Omen** | `[DRAW]`. Tier 2 players `[MANA]`. Tier 1 players `[POWER]` `[POWER]` `[POWER]`. |
| **Glittering Dust** | `[DRAW]` `[DRAW]`. `[EARTH]` cards do nothing when resolved but Heal 2. |
| **Ionic Atmosphere** ×2 | `[DRAW]` `[DRAW]`. All players `[MANA]`. Tier II and III players lose 2 Power Tokens. |
| **Lightning Strike!** | `[DRAW]`. All players `[MANA]`. Players with more than 8 health take 1 damage. |
| **Magnetic Warp** ×2 | `[DRAW]` `[DRAW]`. VOID all cards in the Storm Cloud and draw out 5 new ones. |
| **Rain of Toads** | `[DRAW]`. The player with `[INIT]` loses it. Whoever gets it gains a CURSE and `[MANA]`. |
| **Shooting Star** | `[DRAW]` `[DRAW]` and `[POWER]` `[POWER]`. |
| **Soothing Rain** ×2 | `[DRAW]`. Each player may VOID an ASH, CURSE or ICE in their hand or discard pile. |
| **Tidal Wave** | `[DRAW]` `[DRAW]`, `[MANA]`. All players randomly discard 2 cards. |
| **Wildcolor Winds** | `[DRAW]`. All players draw a card from the Storm Deck and place it face up in their discard (don't trigger discard effects). |

Rain of Toads art is by Peter Siecienski; the rest of the game's art is by Christina Zhong.

## Notes for implementation

- Every Weather card starts with at least one `[DRAW]`, so hand size grows every round. That draw is what
  feeds Blast Score, and the four Weather cards a battle are the main reason hands don't run dry.
- Two of them redefine other rules for the round rather than granting resources: **Energy Wave** opens an
  extra Ultimate window, **Glittering Dust** replaces every Earth card's effect with "Heal 2".
- **Strange Weather** burns the next Weather card, so a battle can skip a scheduled effect.
- Several are conditional on what *you* reveal that round, which means Weather is flipped **before** cards are
  played — you know the incentive before you choose.
