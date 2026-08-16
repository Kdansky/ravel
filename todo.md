Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and struck off with a pointer — this file is the
inbox, not the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

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

Do a full pass on every function that does some sort of if type(a.b) == "some lua type" and find out whether we really need it, or if we can guarantee that the validator has it under control. If we absolutely need such type checks, consider putting the different branches into a module-local table and access it via TABLE[type(a.b)](<function params>), because that just reads cleaner.

Add a safe/load functionality to the engine which produces what is essentially an encoded json (just like what we send over the network for multiplayer), and give games the ability to save/load. We might want to check that a game's json hasn't changed between saves, though I'm not sure how.

When parsing the tags, replace every single tag in memory with a boolean. It's drastically simpler to code against, so tags = [a, b, c] just becomes tagsMap = { a=true, b=true, c=true}. I just don't want this format in my API, because it's cumbersome and errorprone, but it's totally okay inside the running engine. Also throw any boolean values in there which are not yet marked as tags. 

Chequer-index is pointless: A1 in any game that uses the chequered logic should always be whatever colour is listed first. If that ends up being the wrong one, the rules designer can always just switch the two colours.
 