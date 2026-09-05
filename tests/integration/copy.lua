-- "copy" — a card doing what another card does.
--
-- The thing being copied is the *effect*, not the card. Nothing is created,
-- nothing is spent, no cost is paid and the copied card does not move — which
-- is what "play it twice, then trash it" means, and what duplicating the card
-- would get wrong by leaving a second one lying about afterwards.
--
-- The copied card is the one acting, so its own action reads @self as itself.
-- "mine" is not touched by that: it means whoever is up, here as everywhere,
-- which is what makes copying somebody else's card a benefit to the copier.
-- What is deliberately not carried over is targets: nobody aimed the copy, so a
-- copied action that waits to be pointed at something finds nothing.

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
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] }
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
    { "key": "crank", "text": "Crank",
      "play": { "action": ["copy:mine.board:activate"], "spent": "mine.table" } },
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

local function count_in(zone_key, def_key)
	local n = 0
	for _, z in ipairs(zones.all_with_key(zone_key)) do
		for _, id in ipairs(z.cards) do
			if entity.get(id).def_key == def_key then n = n + 1 end
		end
	end
	return n
end

-- The whole of the verb: the copied card's play runs, twice, and the card is
-- still sitting in the hand it was chosen from, unspent and unpaid for.
function M.test_copy_runs_the_play_without_playing_the_card(check)
	with_game(function(name)
		flow.init(name, 3)
		local torch = give("one", "torch")
		local echo  = give("one", "echo")

		flow.play_card(echo.id, { torch.id })
		check("the copied play ran twice", seat("one").stats.landed == 2, seat("one").stats.landed)
		check("but the torch never left the hand",
			entity.get(torch.id).zone_id == hand_of("one").id)
		check("and its cost was never paid — a copy is not a play",
			seat("one").stats.mana == 5, seat("one").stats.mana)
		check("nor was a second torch conjured up", count_in("hand", "torch") == 1)
		check("the echo itself was spent as it says", count_in("table", "echo") == 1)
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

-- Nobody aimed the copy, so a copied action that waits to be pointed finds
-- nothing — and says nothing, rather than moving whatever was nearest.
function M.test_copy_carries_no_targets(check)
	with_game(function(name)
		flow.init(name, 3)
		local eng = give("one", "engine")
		flow.play_card(eng.id, {})
		local aimed = give("one", "aimed")
		local echo  = give("one", "echo")

		flow.play_card(echo.id, { aimed.id })
		check("the engine was not moved by a copy that had no target",
			entity.get(eng.id).zone_id == zones.find_id("board"))
	end)
end

-- A card copying itself is a rule that runs away. It is bounded the same way a
-- zone passing cards round in a circle is: it stops, and it says so.
function M.test_copy_of_itself_stops(check)
	with_game(function(name)
		flow.init(name, 3)
		local snake = give("one", "snake")
		flow.play_card(snake.id, {})
		local n = seat("one").stats.landed
		check("it ran a bounded number of times and stopped", n > 1 and n <= 9, n)
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
		check("the seat that is up gained it", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("and the card's owner did not", seat("two").stats.landed == 0, seat("two").stats.landed)
		check("the copied card is still in its own hand",
			count_in("hand", "torch") == 1, count_in("hand", "torch"))
	end)
end

return M
