# 32 — A third player

*From building Spellstorm, whose `play_1` and `play_2` are the same phase
written twice, and from the reveal question in [16](16-the-player-at-this-screen.md).*

**The phase half shipped as `type: "turn"`; the `enemy` half is still open.**
Spellstorm is a two-player game and stays one — what this bought is that its
phases no longer say so.

The surprise is how little is missing. Almost everything that touches seats was
written against `seat_list` rather than against two, and already generalises:

| Already N | Where |
|---|---|
| turn rotation | `flow.rotate_seat` is `(turn % #seats) + 1` — round the table, any size |
| `each_seat:` | `actions.lua:1269` walks `seat_list` and restores the prior seat |
| `set_active_seat` / `set_priority` | name one seat by scope; naming two is refused outright |
| per-seat zones | `copies: "per_seat"` builds one per seat, and the validator already asks for one `pos` rect per seat (`validate.lua:2073`) |
| per-seat art | one source per player, checked against the seat count (`validate.lua:1703`) |
| hidden hands | `visibility: "owner"` compares against the watching seat, not against "the other one" |

So a three-player game loads and runs today. What it cannot do is *say things
about* three players.

## The one real missing word: `enemy` means "not me"

`predicate.owned_by` (`predicate.lua:115`) is three lines: `mine` is `seat ==
active`, and `enemy` is `seat ~= active`. As a **filter** that is exactly right
for any number — "every creature an opponent controls" wants all of them.

As a **subject** it is a trap. `stat_damage:health@enemy.player:2` resolves
through `bearers`, which returns every entity in scope, so with three seats it
damages both opponents for 2. Spellstorm writes `@enemy.player` 53 times meaning
*the* opponent, and every one of them would silently become a table-wide effect.

The format has no way to say any of:

- **one opponent, chosen by the player** — a `target` can already do this
  (`owner: "enemy"`), so the gap is only that an *action's* subject cannot;
- **the seat to my left** — turn order exists in `seat_index` and nothing can
  read it relationally;
- **the seat with the most/least of something** — `set_active_seat:has_init`
  does this in Spellstorm by putting a computed tag on a seat card, which is the
  idiom and probably the answer.

**The decision to make first is whether `enemy` keeps its meaning.** It should:
it is honest, and the games written against it are two-player, where both
readings agree. What is missing is a *narrower* word beside it, and that is a new
word in the format — so it needs consent before anything is built.

## Shipped: the phase shape

`type: "turn"` is in, and it landed as a phase whose body is other phases rather
than as one phase repeated — because the duplication was never one phase. Three
of Spellstorm's five sites were a *run*: `journal` is three phases and
`ult`/`resolve` is two, and a run is what `each_seat:` cannot reach, living
inside one action list. Written up in AUTHORING.md (*A turn each*).

Two decisions worth keeping:

- **The repeat went in `seat`, not in the type name.** `seat` was already the
  enum for "whose is this" (`next`/`same`), so `each` is a third value there and
  a group without it is an ordinary named run — which is Magic's turn, and costs
  nothing extra.
- **`order` sorts the seat cards by a stat, and is settled once.** An Initiative
  tracker is `highest:initiative`; acting in score order is `lowest:score`. Asked
  again per player, somebody who scored on their own turn would pick who came
  after them and could take two turns or none.

**One gap it left: a group cannot start with whoever is already up.** No `order`
means *round from the next seat*, which is right for a follow — The Crew's leader
comes last and their pass ends the moment it begins, because their card is
already in the middle. It is wrong for a group meant to open with the seat a
previous phase named, and there is no word for that yet. Nothing is blocked on
it; the games that wanted it had a stat to sort by instead.

## What stays two-player on purpose

- **`geometry.facing`** returns "away from the bottom" for everyone but seat one,
  and says so in its own comment. A four-player board has no shared forward;
  such a game writes its vectors per seat. Not a gap.
- **Screen room.** Four hands, four discards and four battle spots do not fit the
  fractional layout Spellstorm uses. That is a presentation question
  ([07](07-presentation.md)), and it is the real reason a four-player game would
  be work.

## What this is worth

The phase half paid for itself in two-player games, which is what it was ranked
for: sixteen of Spellstorm's twenty-five phases were per-seat copies and are now
eight, and Codex, Puzzle Strike and The Crew went the same way. A third seat
costs nothing in phases now where it used to cost eight.

The `enemy` half is still worth low. No game in the corpus is blocked on it, and
it is a new word, so it waits on a customer and on consent.
