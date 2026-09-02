# Spellstorm — Icon glossary

Card text is mostly icons. Transcriptions in the other files spell each icon out in `[BRACKETS]`.
Visual reference: `images/rulebook/page-08.jpg` (symbol list) and `page-05.jpg` (counter wheel).

## Element icons (top-left corner of every spell card)

| Icon | Element | Look |
|---|---|---|
| `[FIRE]` | Fire | red rounded square, orange flame |
| `[WATER]` | Water | blue rounded square, a cresting wave |
| `[EARTH]` | Earth | gold/brown rounded square, a cave mouth with glowing gems |

**Counter wheel: Fire beats Earth, Earth beats Water, Water beats Fire.**
Countering the next clockwise opponent draws you a card.

## Effect icons (in card text)

| Icon | Name | Look | Meaning |
|---|---|---|---|
| `[DRAW]` | Draw | blue card with a white `+` | Draw 1 card from your deck to hand |
| `[GAIN]` | Gain Card | pale card with a gold gem | *May* gain a card from the Storm Cloud of your Tier or lower, to hand |
| `[DISCARD]` | On Discard | grey card with a red curling arrow | The following effect fires when the card is discarded from hand |
| `[MANA]` | Gain Mana | magenta **pentagon** gem with a `+` | Gain 1 mana |
| `[POWER]` | Power Up | gold **octagon** gem with a `+` | Gain 1 Power Token onto the Power Track |
| `[INIT]` | Initiative | yellow lightning bolt | The Initiative Tracker |
| `[ULT]` | Ultimate | blue/violet orb with a white arrow | You may pay your Ultimate's mana cost and resolve it here |

Note the two gem shapes are the whole distinction between mana and power: **pentagon = mana, octagon = power**.

Written-out concepts with no dedicated icon: *Damage*, *Heal*, *Give an ICE/ASH/CURSE*, *VOID*.

## Card frame anatomy

```
┌──────────────────────────────┐
│ [ELEM]   Type label   [DISC] │   Type = "Basic Spell Card", "Wizard Spell Card", …
│         CARD NAME            │   Discard symbol only present if the card has a discard effect
│                              │
│           (art)              │
│                              │
├──────────────────────────────┤
│  spell effect line(s)        │
│  [DISCARD] discard effect    │
│                              │
│  flavour text        [TIER]  │   Tier = I / II / III / IV, bottom right
└──────────────────────────────┘
```

Cards with a discard effect have a **white border**; ordinary spells have a dark border.
Wizard Spell Cards carry a small "cannot be voided" mark at bottom right instead of a Tier.
The three Essence cards carry a small **E** at bottom left.
