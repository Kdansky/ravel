Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and struck off with a pointer — this file is the
inbox, not the plan. `ideas/README.md` is the plan.

## Worked through, see ideas/

- ~~Debug features (CTRL+hover) behind an explicit "enable debug", told to all
  players so cheating can be seen~~ —
  [16 gap 4](ideas/16-the-player-at-this-screen.md). Half of it shipped for
  another reason (`63220e6`): the inspector no longer reads what a player may
  not see. What is left is the opposite — giving an author the unconditional
  view back, opt-in, and telling the peer.
- ~~Small eval blocks (`a.b@c.d > e.f@g.h`) instead of `{stat, at_least}`
  structs, parsed at validation into lambdas~~ —
  [17](ideas/17-conditions-as-expressions.md). The subjects already exist and
  the right-hand side is already a subject; what is new is the infix spelling
  and arithmetic, and arithmetic is the decision to take first.
- ~~A good win/lose screen, fireworks for the winner and the loser told who
  won~~ — [07 gap 6](ideas/07-presentation.md). The flourish is built
  (`fx.celebrate`); what is missing is that an outcome is a word rather than a
  seat, and the two-seat games have no ending screen at all.
- ~~A player could set their name~~ —
  [16 gap 2](ideas/16-the-player-at-this-screen.md). Needs a client-side store,
  which does not exist anywhere yet.
- ~~A menu where settings can be adjusted~~ —
  [16 gap 3](ideas/16-the-player-at-this-screen.md). Three surfaces, and the
  browser panel is nearly free while a text field in the engine is a whole new
  input surface.
- ~~Write down the rules of Legends of Runeterra, check them, copy two simple
  decks, and implement LoR instead of MTG~~ —
  [18](ideas/18-legends-of-runeterra.md). The rules document is stage 1 and the
  re-read loop is the point of it; LoR names three missing capabilities, one of
  which is triggers.

## Open

(nothing yet — add as it comes up)
