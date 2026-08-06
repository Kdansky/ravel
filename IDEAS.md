Boardgames:
* Can we improve the engine so far that it is possible for us to take any boardgame rule set and just turn it into a json, and then have the board game be simulated?
* We should write basic rulesets for a couple games and keep adding features until we can do them all, then consolidate. Chess, Checkers, Solitaire? Then do something less abstract, like a numbers-based game by Rainer Knizia? Then go to Magic:TG, or Hearthstone, or some other more complex board game (and ignore timers, we're not doing real time yet).
* Hard mode: Do the equivalent of Book of Hours or Cultist Simulator, but instead of real time, just have it be turn-based (1 second in CS = 1 turn, or whatever works for Book of Hours (maybe split a day into 10 turns, 6 day, 4 night?))

Multiplayer:
* How do we do more than one player? 
* Start with hot-seating, and have the game just consist of two types of turns, player1 and player2, and show clearly whose turn it is. For simulating games, this is good enough. We might just need two hands and two boards, or something like that, but that would absolutely work.
* Ideally it would be networked and actually support two players, but that is a massive ask. Maybe we could run the engine in two places at once, and rely on everything being synchronous, and just send the turns back and forth? Or even just the whole new state? Linking of the players could be as low level as possible, by giving it a common URL or port. Or maybe we use an existing chat-type software where we transmit the data? As a very low level logic, we could have a button that says "transfer to other player" which returns a (compressed) json, and a "receive move" button where that can be pasted on a different machine. Then the players can use discord or email to play, which is cumbersome, but means we don't need infrastructure.


Graphics:
* Better basic placeholders are needed, such as blank colors and shapes instead of pictures, so that we don't need to reference a jpg, but can just do something like "polygon:5 ; green" and have that work reasonably well for prototyping.
* Graphics need to absolutely stay independent of the game engine, and the engine will stay 100% turn-based to make this possible.
