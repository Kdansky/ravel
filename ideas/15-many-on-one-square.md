# 15 — Several cards on one square

**Answered: not yet.** The question is three questions wearing one coat, and two
are already answered.

| What is wanted | Example | What answers it |
|---|---|---|
| Cards **on a card** | a buff, a weapon, a meeple on a tile | `attach_to_target` — built, and **used by nothing** |
| A **count** on a square | armies on a territory, workers on a space | a stat on the slot — half built |
| An **ordered run** you read down | a tableau, an expedition, a trick pile | a zone with `fan` — shipped |

A checkers king is none of them, however much the physical game stacks two
pieces. It is a promotion, which is a tag.

## The half that is left

**A grid cannot declare per-square stats.** A square already carries `col` and
`row` as ordinary stats, so *reading* works — `row@target` on a live chessboard
answers. Writing does not, and not for the reason you would guess: a stat may
only be changed on something that already has it, and a square has no way to
declare a starting one, so `stat_gain:armies@target:5` silently does nothing.

The whole feature is one field on the zone, defaults copied into each slot where
`col` and `row` are already written. Everything downstream works the moment the
number exists, because none of it ever cared that the bearer was a card. **No
game has asked for it**, and the one this was filed with turned out not to be a
customer: `threat` is stamped by the engine, and a stat the engine writes never
needed declaring.

## What none of the three covers

A stack where each card keeps **its identity, its order, and an addressed
square**, all three. Backgammon is the clean example. Nothing on the capability
ladder asks for it — checkers' king is a tag, Klondike's columns are zones,
Hearthstone's buffs are attachments, chess and Go are one per square by rule.

The cost is not the sixteen reads of `occupant`, it is the *questions*. Movement
blocking asks a square "is anybody there"; a stack turns that into "how many,
whose, and does one enemy still block a slide". `place_in_slot`'s `on_occupied`
chooses between refusing, destroying and moving the occupant to a tray; with a
stack it must say *which* occupant, or that the arrival goes on top and
displaces nobody — a fourth answer and a different rule. Rendering is no longer
an argument either way: `fan` is the same arithmetic in a smaller box.

## Refused, for now

- **Building it before a game needs it.** `fan` came of waiting until Lost
  Cities was unreadable and Klondike asked independently. Nothing has asked here
  once.
- **Making `occupant` a list "just in case"** — sixteen reads each gain a second
  answer, and the second answer is a guess until a real game says which.
- **A second attachment mechanism.** The first move is to play something through
  `attach_to_target` and find where it is thin — it has never been played, only
  tested, so expect to find detaching, destroying a parent with children, and
  whether a child can be targeted apart from its parent all unfinished.
