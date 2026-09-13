-- "copy" — a card doing what another card does.
--
-- **A copied play makes a card; a copied ability runs a list.** The two moments
-- are not the same kind of thing. An ability is not a move: nothing aims it and
-- there is nothing to create, so it runs where it stands. A play *is* a move —
-- it is aimed, it may be refused, and it says @self about itself — so copying
-- one makes what the table makes: an imaginary card, out of thin air, standing
-- in the player's "todo" for them to play like any other.
--
-- It costs nothing, is spent nowhere, and stops existing once it has gone off.
-- Nothing moves while it is unplayed, so the list that made it waits — the same
-- rule an open offer keeps.
--
-- "mine" is untouched by any of it: it means whoever is up, here as everywhere,
-- which is what makes copying somebody else's card a benefit to the copier.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Copy",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "landed", "label": "Landed", "subject": "landed@mine.player" },
    { "key": "mana", "label": "Mana", "subject": "mana@mine.player" }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "todo", "label": "Play these", "status": "todo", "layout": "row",
      "copies": "per_seat", "pos": "hand" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "landed": 0, "mana": 5 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "landed": 0, "mana": 5 } },
    { "key": "torch", "text": "Torch", "tags": ["spell"],
      "play": { "cost": { "mana@mine.player": 2 },
        "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.table" } },
    { "key": "aimed", "text": "Aimed", "tags": ["spell"],
      "play": { "target": { "type": "card", "zones": ["board"], "count": 1 },
        "action": ["move:target:mine.table"] } },
    { "key": "engine", "text": "Engine", "tags": ["machine"],
      "play": { "action": ["move_to:board"] },
      "abilities": [{ "cost": { "mana@mine.player": 1 },
        "action": ["stat_gain:landed@mine.player:3"] }] },
    { "key": "echo", "text": "Echo",
      "play": { "target": { "type": "card", "zones": ["hand"], "count": 1 },
        "action": ["copy:target:play:2"], "spent": "mine.table" } },
    { "key": "relay", "text": "Relay", "play": { "action": ["move_to:board"] },
      "abilities": [{ "key": "go", "text": "Go",
        "target": { "type": "card", "zones": ["hand"], "count": 1 },
        "action": ["copy:target:play:2"] }] },
    { "key": "chain", "text": "Chain", "play": { "action": ["move_to:board"] },
      "abilities": [{ "key": "go", "text": "Go",
        "target": { "type": "card", "zones": ["board"], "count": 1 },
        "action": ["copy:target:activate"] }] },
    { "key": "crank", "text": "Crank",
      "play": { "action": ["copy:mine.board:activate"], "spent": "mine.table" } },
    { "key": "holder", "text": "Holder",
      "play": { "target": { "type": "card", "zones": ["hand"], "count": 1 },
        "action": ["copy:target:play:2", "stat_gain:mana@mine.player:1"] } },
    { "key": "snake", "text": "Snake",
      "play": { "action": ["stat_gain:landed@mine.player:1", "copy:self:play"] } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_copy.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_copy.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function give(seat_key, def_key)
	return zones.add(hand_of(seat_key), def_key)
end

-- Play whatever is owed, aiming each at the first thing it may be aimed at,
-- until the todo is empty. What an interface does when the player clicks.
local function play_owed(limit)
	for _ = 1, limit or 12 do
		local z = zones.todo_of(zones.active_seat())
		local id = z and z.cards[1]
		if not id then return end
		local def = require("cards").def(entity.get(id))
		local spec = def and def.play and def.play.target
		local targs = spec and require("targeting").candidates(id, spec) or {}
		flow.play_card(id, targs[1] and { targs[1] } or {})
	end
end

local function owed()
	local z = zones.todo_of(zones.active_seat())
	return z and #z.cards or 0
end

local function count_in(zone_key, def_key)
	local n = 0
	for _, z in ipairs(zones.all_with_key(zone_key)) do
		for _, id in ipairs(z.cards) do
			if entity.get(id).def_key == def_key then n = n + 1 end
		end
	end
	return n
end

-- The whole of the verb: two imaginary torches to play, and when they have been
-- played the real one is still in the hand it was chosen from, unspent, unpaid
-- for, and with no second torch left lying about.
function M.test_copy_of_a_play_makes_a_card_to_play(check)
	with_game(function(name)
		flow.init(name, 3)
		local torch = give("one", "torch")
		local echo  = give("one", "echo")

		flow.play_card(echo.id, { torch.id })
		check("two imaginary torches are waiting to be played", owed() == 2, owed())
		check("and nothing has happened yet", seat("one").stats.landed == 0,
			seat("one").stats.landed)

		play_owed()
		check("playing them both is the copied play running twice",
			seat("one").stats.landed == 2, seat("one").stats.landed)
		check("the real torch never left the hand",
			entity.get(torch.id).zone_id == hand_of("one").id)
		check("its cost was never paid — a copy is not a play",
			seat("one").stats.mana == 5, seat("one").stats.mana)
		check("nor was a second torch left lying about", count_in("hand", "torch") == 1
			and count_in("table", "torch") == 0, count_in("table", "torch"))
		check("and nothing is owed any more", owed() == 0, owed())
		check("the echo itself was spent as it says", count_in("table", "echo") == 1)
	end)
end

-- Nothing moves while a card is owed. The list that made it stops where it
-- stands and picks up when the last one has been played, which is the same
-- thing an unanswered offer does to it.
function M.test_copy_holds_the_rest_of_the_list(check)
	with_game(function(name)
		flow.init(name, 3)
		give("one", "torch")
		local hold = zones.add(hand_of("one"), "holder")
		flow.play_card(hold.id, { entity.get(hand_of("one").cards[1]).id })
		check("the copies are waiting", owed() == 2, owed())
		check("and what was written after the copy has not run",
			seat("one").stats.landed == 0, seat("one").stats.landed)

		play_owed()
		check("both copies ran", seat("one").stats.landed == 2, seat("one").stats.landed)
		check("and then the rest of the list did", seat("one").stats.mana == 6,
			seat("one").stats.mana)
	end)
end

-- The other list. A card in play is copied through its ability, and the cost
-- that ability charges is not charged either.
function M.test_copy_runs_an_ability(check)
	with_game(function(name)
		flow.init(name, 3)
		local eng = give("one", "engine")
		flow.play_card(eng.id, {})
		check("the engine is on the board", entity.get(eng.id).zone_id == zones.find_id("board"))

		local crank = give("one", "crank")
		flow.play_card(crank.id, {})
		check("its ability ran once", seat("one").stats.landed == 3, seat("one").stats.landed)
		check("and paid nothing for it", seat("one").stats.mana == 5, seat("one").stats.mana)
	end)
end

-- A scope naming nothing copies nothing, and a card with no such list is a copy
-- of nothing rather than a mistake: "copy the chosen chip" has no opinion about
-- what the player chose.
function M.test_copy_of_nothing_is_not_an_error(check)
	with_game(function(name)
		flow.init(name, 3)
		local crank = give("one", "crank")
		flow.play_card(crank.id, {})
		check("an empty board copied nothing", seat("one").stats.landed == 0, seat("one").stats.landed)
		check("and the game is still standing", flow.pending_event() == nil)
	end)
end

-- **A copy is aimed, because it is a card being played.** This is the whole
-- reason a play makes a card rather than running a list: a copied Crash Gem
-- used to go off at nothing, since nobody had pointed it, and the target lived
-- on the play rather than in it.
function M.test_copy_of_a_play_is_aimed_like_any_other(check)
	with_game(function(name)
		flow.init(name, 3)
		local eng = give("one", "engine")
		flow.play_card(eng.id, {})
		local aimed = give("one", "aimed")
		local echo  = give("one", "echo")

		flow.play_card(echo.id, { aimed.id })
		check("two imaginary copies of it are waiting", owed() == 2, owed())

		play_owed()
		check("and the first one aimed at the engine and moved it",
			entity.get(eng.id).zone_id ~= zones.find_id("board"),
			entity.get(entity.get(eng.id).zone_id).key)
		check("the real card is still in the hand", count_in("hand", "aimed") == 1)
	end)
end

-- A copy with nothing to aim at is not a lock. The offer keeps the same rule --
-- nothing to take is nothing to look at -- and a card that must be played needs
-- it more, because it cannot be declined.
function M.test_copy_of_a_play_nobody_can_aim_goes_away(check)
	with_game(function(name)
		flow.init(name, 3)
		local aimed = give("one", "aimed")
		local echo  = give("one", "echo")

		flow.play_card(echo.id, { aimed.id })
		flow.settle()
		check("an empty board is nothing to aim at, so nothing is owed", owed() == 0, owed())
		check("and the turn is not stuck", flow.can_play(give("one", "torch").id))
	end)
end

-- A card copying itself is a rule that runs away. It is bounded the same way a
-- zone passing cards round in a circle is: it stops, and it says so.
function M.test_copy_of_itself_stops(check)
	with_game(function(name)
		flow.init(name, 3)
		local snake = give("one", "snake")
		flow.play_card(snake.id, {})
		play_owed(40)
		local n = seat("one").stats.landed
		check("it ran a bounded number of times and stopped", n > 1 and n <= 10, n)
		check("and left nothing owed", owed() == 0, owed())
	end)
end

-- What the copied card is, and what it is not. @self is the copied card — its
-- own action is running, and it is the one running it. "mine" is not: it means
-- whoever is up, here as everywhere else, so copying somebody else's card gives
-- the benefit to the copier. That is the reading a card that copies wants, and
-- the trap for a card that meant to make the other seat do something.
function M.test_copy_is_the_copied_card_acting_for_whoever_is_up(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "torch")
		local crank = give("one", "crank")
		actions.execute("copy:enemy.hand:play", { card_id = crank.id, targets = {} })
		play_owed()
		check("the seat that is up gained it", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("and the card's owner did not", seat("two").stats.landed == 0, seat("two").stats.landed)
		check("the copied card is still in its own hand",
			count_in("hand", "torch") == 1, count_in("hand", "torch"))
	end)
end

-- A copy is not fussy about who asked for it: an *ability* that copies a play
-- hands over the same imaginary cards a play would.
function M.test_copy_an_ability_may_copy_a_play(check)
	with_game(function(name)
		flow.init(name, 3)
		local relay = give("one", "relay")
		flow.play_card(relay.id, {})
		local torch = give("one", "torch")

		flow.activate(relay.id, { torch.id })
		check("two imaginary torches are owed", owed() == 2, owed())
		play_owed()
		check("and playing them is the copied play running twice",
			seat("one").stats.landed == 2, seat("one").stats.landed)
	end)
end

-- **A copied ability is not aimed, and now it says so.** `activate` runs the
-- list where the card stands — there is nothing to create and nothing aims it —
-- so an ability that waits to be pointed at something would run at nothing and
-- look like it had worked. It is reported instead.
--
-- That is the untouched half of the same hole a copied play used to have. It is
-- reachable only by copying an ability that is itself aimed, which no shipped
-- game does: 55 abilities across five games declare a target, and the one game
-- that copies abilities has none of them.
function M.test_copy_of_an_ability_that_must_be_aimed_says_so(check)
	with_game(function(name)
		flow.init(name, 3)
		local chain = give("one", "chain")
		flow.play_card(chain.id, {})
		local relay = give("one", "relay")
		flow.play_card(relay.id, {})
		give("one", "torch")

		flow.activate(chain.id, { relay.id })
		check("nothing was owed, because nothing could be aimed", owed() == 0, owed())
		check("nothing happened quietly", seat("one").stats.landed == 0,
			seat("one").stats.landed)
		local said = table.concat(require("log").tail(6), " | ")
		check("and it named the card and the reason", said:find("must be aimed", 1, true), said)
	end)
end

return M
