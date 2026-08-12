Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and struck off with a pointer — this file is the
inbox, not the plan. `ideas/README.md` is the plan.

## Open

Put the debug features (CTRL+hover) behind an explicit "enable debug" which is told to all players so that cheating can be seen more easily.

Consider instead of complex {stat "at_least": 8 } struct to just use small eval blocks, which look more like "a.b@c.d > e.f@g.h", allowing simple math and lookup logic. This might just be easier, and we can parse this on validation and generate lambda functions for it all instead of having to write unique special cases for every field type.

We need a good win/lose screen. With fireworks for the player if they win, and some sad effects if they lose. If multiple players are in the game, the winner should get the fireworks, and the loser(s) should get the loss screen, but also display in smaller text below who won.

It would be nice if a player could set their name somehow.

Maybe we need a menu where settings can be adjusted, such as the player name? This might be tricky.

En passant for chess?
