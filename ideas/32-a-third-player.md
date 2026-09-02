# 32 — A third player

*From building Spellstorm, whose `play_1` and `play_2` are the same phase
written twice, and from the reveal question in [16](16-the-player-at-this-screen.md).*

**Not started, and deliberately parked: Spellstorm is a two-player game and stays
one.** This is the note so the next person does not re-derive it.

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

## The phase shape: `seat: "all"`

`play_1` and `play_2` are byte-identical but for their keys and their `next`.
That duplication is what makes the game two-player, not anything in the engine.

A `player_input` phase already understands `seat: "next"`, read at
`flow.lua:471`. A third value — `"all"` — would mean *run this phase once per
seat, in turn order, then take `next`*. It is `each_seat:` for phases, and it is
the same idea in the same words the format already uses.

Two things to settle if it is ever built:

1. **Where the loop counter lives.** `phase.lua`'s stack frames already carry a
   `seat`; a frame that knows it is on pass 2 of 3 is the smallest version.
2. **What `ends_when` is asked about.** Per seat, presumably — the phase ends for
   *you* when your card is down. That is what makes the condition readable, and
   it is what `mine.` already means inside a phase.

The payoff is not only player count: it removes the copy-paste, and a copy-pasted
phase is the shape [09](09-composition.md) exists to stop.

## What stays two-player on purpose

- **`geometry.facing`** returns "away from the bottom" for everyone but seat one,
  and says so in its own comment. A four-player board has no shared forward;
  such a game writes its vectors per seat. Not a gap.
- **Screen room.** Four hands, four discards and four battle spots do not fit the
  fractional layout Spellstorm uses. That is a presentation question
  ([07](07-presentation.md)), and it is the real reason a four-player game would
  be work.

## What this is worth

Low, for now. No game in the corpus is blocked on it — the same test
[31](31-either-of-two.md) failed. The value is that `seat: "all"` would pay for
itself in *two*-player games by collapsing every `_1`/`_2` phase pair, and that
is the honest customer to find first.
