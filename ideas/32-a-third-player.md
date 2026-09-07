# 32 — A third player

*From building Spellstorm, whose `play_1` and `play_2` are the same phase
written twice, and from the reveal question in [16](16-the-player-at-this-screen.md).*

**The phase half shipped as `type: "turn"`. The `enemy` half shipped as `opponent`, with the zone scopes left open.**
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

## Shipped: `opponent`, and what `enemy` turns out to do

`predicate.owned_by` is three lines: `mine` is `seat == active`, `enemy` is
`seat ~= active`. As a **filter** `enemy` is exactly right for any number —
"every creature an opponent controls" wants all of them. As a **subject** it was
a trap, and **not the trap this file predicted**: the draft said
`stat_damage:health@enemy.player:2` would damage both opponents at three seats.
It does not. The default quantifier is `any`, so it lands on the *first* member
of the pool — one arbitrary opponent, chosen by declaration order, with the
third player never touched. Said `each.enemy` it hits them all, which at least
says so out loud.

`@opponent` is in, and **it is a scope rather than an owner word** — a seat, the
way `@self` is a card, so it takes nothing after it. That was the second try:
written as an owner word it needed `@opponent.player`, which is `@enemy.player`
with a concept added and not a word saved. If the reason to have it is that
`enemy` names a pool where the rule meant a person, then the word should *be*
the person; `.player` was the tell that it was still a filter.

It resolves only in a game with exactly two seats, is refused by the validator
anywhere else, and names nobody at run time if it gets there anyway. Failing
closed is deliberate — the word exists to turn a silent misreading into a
sentence somebody can act on, so silence would be the same bug with a new
spelling. `opponent` joins `self`, `all`, `reach`, `owner_of` and `everywhere`
as a name content may not claim.

34 sites migrated: every `@enemy.player` in the corpus, across Spellstorm,
Puzzle Strike, Codex and Arnak, all of them two-seat games where the two words
agree today. Each one lost a word as well as gaining a meaning.

**The open half is the zone scopes** — `@enemy.hand`, `@enemy.patrol`,
`@enemy.taken`, 40 of them. `zones.lua` picks the first matching seat there too,
so the trap is the same shape, but a zone scope is a place *and* a filter and
the two readings are genuinely different per site: `count:king@enemy.taken` may
well want the pool. Migrating them blind would be the same silent widening in
reverse, so each wants looking at.

Still missing, and none of it blocking any game in the corpus:

- **one opponent, chosen by the player** — a `target` already does this
  (`owner: "enemy"`), and `opponent` deliberately does not, since choosing one
  of several is what a target is for;
- **the seat to my left** — turn order exists in `seat_index` and nothing can
  read it relationally;
- **the seat with the most/least of something** — `set_active_seat:has_init`
  does this in Spellstorm by putting a computed tag on a seat card, which is the
  idiom and probably the answer.

`opponents` and `any_opponent` are the variants that may want writing later; a
three-seat game is what would ask for them.

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
