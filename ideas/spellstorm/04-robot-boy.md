# Spellstorm — Robot Boy (solo / co-op opponent)

Images: `images/large/robotboy.jpg` (character card), `images/spells/robot-boy*.jpg` (his 9-card deck).
Rules for driving him: `01-rulebook.md` § Alternate game modes.

## Character card

> **ROBOT BOY** — *(FOR 1 PLAYER / CO-OP ONLY)*
>
> **START OF GAME — Mode Switch.** Place the top card of Robot Boy's deck on this card, face up.
> Place another, face down.
>
> **PASSIVE — No Traction.** Whenever Robot Boy reveals an ICE (including as part of Mode Switch),
> he loses 1 **Blast Token**.
>
> **ULTIMATE (6 mana) — "El3mEnt4l CaScAdE#%$".** Resolve the face up, and then the face down card on this
> card, and then discard both. Then, draw a new face up and face down card and place them on this card.
>
> Health **15** · Initiative **0**
>
> *"I sing, I do tricks, and… I'm Robot Boy! What else do you really need to know?"*

Difficulty is set by his starting Power Tokens: Easy 0, Medium 2, Hard 4.

## His 9-card deck

Every card is titled "ROBOT BOY" with a subtitle. **Tier II / Tier III lines are extra effects that apply
once Robot Boy has reached that Tier** — his cards grow with him rather than being replaced. None can be voided.

### Water (3)

| File | Name | Text |
|---|---|---|
| `robot-boy1` | **Robot Repair** | Heal 1/opponent. `[DRAW]` `[MANA]`. · Tier II: VOID an ICE or CURSE in Robot Boy's discard. · Tier III: Heal 3, `[DRAW]`. |
| `roboy-boy2` | **Ice Block** | `[POWER]`. Heal 1/opponent. · Tier II: Give an ICE. · Tier III: `[DRAW]`. Heal 1/opponent. |
| `robot-boy9` | **Blast You** | `[DRAW]` `[DRAW]` · Tier II: Heal 1. · Tier III: Heal 1/opponent. |

### Fire (3)

| File | Name | Text |
|---|---|---|
| `robot-boy3` | **Robo Bounce** | Resolve and then VOID the "X" card in the Storm Cloud. · Tier II: If Robot Boy has `[INIT]`, deal 2 damage. — *"Oof! Sorry!"* |
| `robot-boy4` | **Laser EYE** | Gain `[INIT]`. Deal 1 damage. Robot Boy discards a Blast Token. · Tier II: Give a CURSE. · Tier III: `[MANA]` |
| `robot-boy5` | **Robo-Fist** | `[MANA]`. Robot Boy discards a Blast Token. Deal 1 damage. · Tier II: Deal 1 damage. · Tier III: Deal 1 damage. — *"Hey! Watch my trick!"* |

### Earth (3)

| File | Name | Text |
|---|---|---|
| `robot-boy6` | **Upgrade** | `[POWER]` `[POWER]` `[MANA]` — VOID the "X" card in the Storm Cloud. · Tier III: `[POWER]` `[MANA]`. |
| `robot-boy7` | **Hack You Badly** | `[POWER]` `[DRAW]` `[MANA]` · Tier II: Other players discard a card randomly. · Tier III: `[POWER]` — *"!scabbalee BaYTOBORMi Ω ####"* |
| `robot-boy8` | **Drill Ya** | `[POWER]` `[MANA]` — Opponents who revealed `[WATER]` gain an ASH. · Tier III: Deal 1 damage. — *"I'm Robot Boy!"* |

## The "X" card

Robot Boy's *Robo Bounce* and *Upgrade* refer to "the X card in the Storm Cloud". The Spellstorm Board's five
Storm Cloud slots are marked **E, E, E, (blank), X** — the X is the bottom slot. See `08-boards.md`. The
rulebook never explains the marking.
