-- A seat the engine plays.
--
-- The move list was the terminator's for as long as its only caller was a test;
-- it is an interface's now, and an interface has to offer everything a player
-- could click. What it was missing is what stalled it: a response window, a
-- place with an ability, and a card whose zone the phase never names.
--
-- The turn gate is the other half. Claiming a seat is how the opponent's hand
-- is hidden, and it was also what forbade the opponent from moving.

local entity   = require("entity")
local zones    = require("zones")
local flow     = require("flow")
local net      = require("net")
local opponent = require("opponent")
local harness = require("harness")

local M = {}

local GAME = [==[{
  "title": "Engine Seat",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "loot", "label": "Loot", "subject": "loot@mine.player" }],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "deck", "layout": "stack", "visibility": "secret",
      "pos": [0.80, 0.40, 0.90, 0.60],
      "abilities": [{ "action": ["draw_from:deck:hand:1"] }],
      "contents": ["coin:6"] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "next": [{ "then": "act" }] }],
  "tags": { "loud": { "emits": { "play": "shout" } } },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "loot": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "loot": 0 } },
    { "key": "coin", "text": "Coin", "play": { "action": ["stat_gain:loot@mine.player:1"] } },
    { "key": "horn", "text": "Horn", "tags": ["loud"],
      "play": { "action": ["stat_gain:loot@mine.player:1"], "spent": "mine.table" } },
    { "key": "envy", "text": "Envy",
      "reactions": [{ "to": "shout", "action": ["stat_gain:loot@mine.player:5"], "spent": "mine.table" }] }
  ],
  "setup": {
    "place": [
      { "card": "one", "owner": "one", "zone": "table" },
      { "card": "two", "owner": "two", "zone": "table" }
    ]
  }
}]==]

-- The same game under a second name, seats and all: what a claim outliving its
-- game looks like when the next game has a seat of the same name.

local function with_game(fn)
	local f = assert(io.open("game/games/" .. harness.tmp("engine_seat"), "w"))
	f:write(GAME)
	f:close()
	local g = assert(io.open("game/games/" .. harness.tmp("engine_seat_two"), "w"))
	g:write(GAME)
	g:close()
	local ok, err = pcall(fn, harness.tmp("engine_seat"), harness.tmp("engine_seat_two"))
	os.remove("game/games/" .. harness.tmp("engine_seat"))
	os.remove("game/games/" .. harness.tmp("engine_seat_two"))
	net.claim_seat(nil)
	opponent.leave()
	if not ok then error(err, 0) end
end

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == seat then return z end
	end
end

local function seat_card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- Step 2 itself: a seat nobody is sitting at plays by itself, and only when it
-- is that seat's turn.
function M.test_opponent_plays_its_own_turn_and_no_other(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		zones.add(zone_of("hand", "two"), "coin")
		check("nothing moves while no seat is the engine's", not opponent.act())
		opponent.take("two")
		check("and none while the other seat is up", not opponent.act())
		check("the loot is untouched", seat_card("two").stats.loot == 0)
		require("actions").execute("set_active_seat:owner_of.target",
			{ targets = { seat_card("two").id } })
		check("the engine plays when its own seat is up", opponent.act())
		check("and it moved for itself and not the other seat",
			seat_card("one").stats.loot == 0, tostring(seat_card("one").stats.loot))
	end)
end

-- Claiming a seat is how the opponent's hand is hidden, so it must not be what
-- stops the opponent playing. The gate is about the human at this screen.
function M.test_opponent_moves_through_a_claimed_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		local theirs = zones.add(zone_of("hand", "two"), "coin")
		net.claim_seat("one")
		opponent.take("two")
		require("actions").execute("set_active_seat:owner_of.target",
			{ targets = { seat_card("two").id } })
		check("a human may not move for the seat they are not in",
			not flow.play_card(theirs.id, {}))
		check("but the engine seat still moves", opponent.act())
	end)
end

-- A claim belongs to the game it was made in. Two games with the same seat
-- names is the case a name check would miss, and both of these are one and two.
function M.test_opponent_a_claim_does_not_outlive_its_game(check)
	with_game(function(name, other)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		net.claim_seat("two")
		check("a seat that is not up may not act",
			not flow.play_card(zone_of("hand", "one").cards[1], {}))
		flow.init(other, 3)
		zones.add(zone_of("hand", "one"), "coin")
		check("and another game is not held by the old claim",
			flow.play_card(zone_of("hand", "one").cards[1], {}))
	end)
end

-- Everything a player could click, which the hand-only list was not: a place
-- with an ability is a move, and it was the commonest thing the old list missed.
function M.test_opponent_offers_a_place(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		zones.add(zone_of("hand", "one"), "horn")
		check("the deck offers one", #flow.usable_zone_abilities(zones.find("deck").id) == 1)
		check("and the list is the hand plus the place", #opponent.legal() == 3,
			tostring(#opponent.legal()))
	end)
end

-- A game's own button in the system column is a move when a phase gates it, and
-- the engine's buttons beside it, and a game's ungated one, are not. Spellstorm
-- keeps "Unplayable hand" there, the only way past a hand of ASH, and a seat
-- holding one stopped the game.
function M.test_opponent_presses_a_gated_button_in_the_system_column(check)
	local text = GAME
		:gsub('{ "key": "coin", "text": "Coin",',
			'{ "key": "bell", "text": "Bell", "abilities": [{ "phases": ["act"], "action": ["stat_gain:loot@mine.player:3"] }] },\n'
			.. '    { "key": "rules", "text": "Rules", "abilities": [{ "action": ["stat_gain:loot@mine.player:1"] }] },\n'
			.. '    { "key": "coin", "text": "Coin",')
		:gsub('{ "card": "two", "owner": "two", "zone": "table" }',
			'{ "card": "two", "owner": "two", "zone": "table" },\n'
			.. '      { "card": "bell", "zone": "menu" }, { "card": "rules", "zone": "menu" }')
	local f = assert(io.open("game/games/" .. harness.tmp("engine_seat_menu"), "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(function()
		flow.init(harness.tmp("engine_seat_menu"), 3)
		check("the bell stands in the system column", flow.is_system_card(seat_card("bell").id))
		check("and is on the list beside the deck, where the rules and the engine's buttons are not",
			#opponent.legal() == 2, tostring(#opponent.legal()))
	end)
	os.remove("game/games/" .. harness.tmp("engine_seat_menu"))
	if not ok then error(err, 0) end
end

-- A win shared by every seat is a win for the engine's too. The Crew sets `won`
-- on all four seats, and the first seat holding it was read as the winner, so a
-- completed mission scored as a loss for the other three.
function M.test_opponent_a_win_for_everybody_is_a_win(check)
	-- Without the stack, so a card's play lands when it is played; with the
	-- seats in play, so a stat written to one lands on it; and with a turn that
	-- is one play, so a try that did not play the pact stops before it can.
	local text = GAME
		:gsub('"next": %[{ "then": "act" }%] }', '"ends_when": "plays >= 1", "next": [{ "then": "act", "seat": "next", "ends_round": true }] }')
		:gsub('{ "key": "table", "layout": "stack",', '{ "key": "table", "layout": "stack", "status": "board",')
		:gsub(',\n    { "key": "stack", "layout": "stack", "tags": %["stack"%], "pos": %[0.55, 0.45, 0.70, 0.65%] }', '')
		:gsub('"tags": { "loud"', '"bots": [{ "name": "looter", "description": "Loot.", "value": "loot@mine.player" }],\n  "tags": { "loud"')
		:gsub('{ "key": "coin", "text": "Coin",',
			'{ "key": "pact", "text": "Pact", "play": { "action": ["stat_gain:won@each.anyone.player:1"] } },\n'
			.. '    { "key": "coin", "text": "Coin",')
	local f = assert(io.open("game/games/" .. harness.tmp("engine_seat_pact"), "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(function()
		flow.init(harness.tmp("engine_seat_pact"), 3)
		local hand = zone_of("hand", "two")
		zones.add(hand, "coin")
		zones.add(hand, "pact")
		require("actions").execute("set_active_seat:owner_of.target", { targets = { seat_card("two").id } })
		local moves = opponent.legal()
		net.unattended(function()
			local i = opponent.choose("two", moves)
			moves[i]()
		end)
		check("the second seat plays the card that wins for both", (seat_card("two").stats.won or 0) > 0,
			"loot " .. tostring(seat_card("two").stats.loot))
	end)
	os.remove("game/games/" .. harness.tmp("engine_seat_pact"))
	if not ok then error(err, 0) end
end

-- A window is answerable, and a window nobody wants to answer still closes:
-- passing is always on the list. Without it a seat with no reaction sat there
-- for ever, which is what stalled Spellstorm.
function M.test_opponent_answers_a_window(check)
	with_game(function(name)
		flow.init(name, 3)
		local horn = zones.add(zone_of("hand", "one"), "horn")
		zones.add(zone_of("hand", "two"), "envy")
		flow.play_card(horn.id, {})
		check("the window opened for the other seat", zones.active_seat() == "two",
			zones.active_seat())
		local moves = opponent.legal()
		check("which is the answer and the pass", #moves == 2, tostring(#moves))

		opponent.take(zones.active_seat())
		for _ = 1, 8 do
			if not flow.pending_event() then break end
			opponent.act()
		end
		check("and an engine seat always closes one it is handed",
			flow.pending_event() == nil)
	end)
end

-- Standing up again.
function M.test_opponent_leaves_the_seat_when_told(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		opponent.take("one")
		check("it is the engine's turn", opponent.act())
		opponent.leave()
		check("and nobody's once it stands up", not opponent.act())
	end)
end


-- A seat the engine weighs moves for. Seat one holds two guesses and a dud; seat
-- two holds one colour in a hidden hand and the other in a hidden deck. A guess
-- scores if the hand holds its colour, so the true answer is red every time —
-- and a bot that may not look should not know that. A round is one play, so a
-- try is scored on the move it tried rather than on the rest of the hand.
local GUESS = [==[{
  "title": "Guess",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "on": ["player"], "start": 0, "min": 0, "max": 9 }],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "deck", "layout": "stack", "visibility": "secret", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "table", "layout": "row", "status": "board", "copies": "per_seat",
      "pos": [[0.75, 0.80, 0.95, 0.95], [0.75, 0.05, 0.95, 0.20]] },
    { "key": "box", "layout": "stack", "use": "none", "pos": [0.45, 0.45, 0.55, 0.55] }
  ],
  "phases": [
    { "key": "deal", "type": "automatic", "next": [{ "then": "act" }],
      "actions": ["move:box.guess:mine.hand", "move:box.red:enemy.hand", "move:box.blue:enemy.deck"] },
    { "key": "act", "type": "player_input", "zone": "hand", "seat": "next", "ends_when": "plays >= 1",
      "next": [{ "then": "act", "ends_round": true }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["player"] },
    { "key": "two", "text": "Two", "tags": ["player"] },
    { "key": "red", "text": "Red", "tags": ["red"], "play": { "action": [], "spent": "mine.table" } },
    { "key": "blue", "text": "Blue", "tags": ["blue"], "play": { "action": [], "spent": "mine.table" } },
    { "key": "guess_red", "text": "Guess red", "tags": ["guess"],
      "play": { "action": ["stat_gain:score@mine.player:count:red@enemy.hand"], "spent": "mine.table" } },
    { "key": "guess_blue", "text": "Guess blue", "tags": ["guess"],
      "play": { "action": ["stat_gain:score@mine.player:count:blue@enemy.hand"], "spent": "mine.table" } },
    { "key": "dud", "text": "Dud", "tags": ["guess"], "play": { "action": [], "spent": "mine.table" } }
  ],
  "bots": [
    { "name": "guesser", "description": "Scores.", "value": "score@mine.player" },
    { "name": "spoiler", "description": "Scores as little as it can, once it has scored.", "rating": "score@mine.player",
      "value": "0 - score@mine.player" },
    { "name": "indifferent", "description": "Cares for nothing.", "value": "0" }
  ],
  "setup": { "place": [
    { "card": "one", "owner": "one", "zone": "table" },
    { "card": "two", "owner": "two", "zone": "table" },
    { "card": "guess_red", "zone": "box" }, { "card": "guess_blue", "zone": "box" },
    { "card": "dud", "zone": "box" }, { "card": "red", "zone": "box" }, { "card": "blue", "zone": "box" }
  ] }
}]==]

local function with_guess(fn)
	local name = harness.tmp("guess")
	local f = assert(io.open("game/games/" .. name, "w"))
	f:write(GUESS)
	f:close()
	local ok, err = pcall(fn, name)
	os.remove("game/games/" .. name)
	opponent.leave()
	if not ok then error(err, 0) end
end

local function picked(moves, i)
	local before = {}
	for e in entity.each("card") do before[e.id] = e.zone_id end
	local key
	flow.rehearse(function()
		moves[i]()
		for e in entity.each("card") do
			if e.zone_id ~= before[e.id] then key = e.def_key end
		end
	end)
	return key
end

function M.test_engine_seat_weighs_a_move_without_reading_the_hidden_hand(check)
	with_guess(function(name)
		local count = { guess_red = 0, guess_blue = 0, dud = 0 }
		for n = 1, 40 do
			math.randomseed(n)
			flow.init(name, n)
			local moves = opponent.legal()
			local k = picked(moves, opponent.choose("one", moves))
			count[k] = (count[k] or 0) + 1
		end
		check("a guess beats a move worth nothing", count.dud <= 4,
			count.dud .. " dud, " .. count.guess_red .. " red, " .. count.guess_blue .. " blue")
		check("red, which is the truth, is picked", count.guess_red > 0, count.guess_red)
		check("and so is blue, which a bot reading the hand would never pick", count.guess_blue > 0, count.guess_blue)
	end)
end

-- A seat plays as the bot it was handed, and one handed nothing as the first.
function M.test_engine_seat_plays_as_the_bot_it_was_handed(check)
	with_guess(function(name)
		local count = { guess_red = 0, guess_blue = 0, dud = 0 }
		for n = 1, 20 do
			math.randomseed(n)
			flow.init(name, n)
			opponent.take("one", "spoiler")
			local moves = opponent.legal()
			local k = picked(moves, opponent.choose("one", moves))
			count[k] = count[k] + 1
		end
		check("the spoiler plays the dud", count.dud >= 18,
			count.dud .. " dud, " .. count.guess_red .. " red, " .. count.guess_blue .. " blue")
	end)
end

-- A seat handed no bot by name plays as one its ratings draw, chosen afresh on a
-- coin each turn. The spoiler rates its own score and the guesser rates nothing,
-- so once there is a score the spoiler is the only draw, and a new turn takes
-- the seat over half the time.
function M.test_engine_seat_plays_as_its_ratings_draw(check)
	with_guess(function(name)
		local function one()
			for e in entity.each("card") do if e.def_key == "one" then return e end end
		end
		local kept, switched = 0, 0
		for n = 1, 40 do
			math.randomseed(n)
			flow.init(name, n)
			opponent.take("one")
			check("every bot rating nothing is the first bot's seat", opponent.rated("one") == opponent.bot("guesser"))
			one().stats.score = 1
			check("and a turn keeps its bot whatever the ratings say", opponent.rated("one") == opponent.bot("guesser"))
			-- One play is a round, so two make it seat one's turn again.
			opponent.legal()[1]()
			opponent.legal()[1]()
			if opponent.rated("one") == opponent.bot("spoiler") then switched = switched + 1 else kept = kept + 1 end
		end
		check("the next turn sometimes keeps it", kept >= 10, kept)
		check("and sometimes hands it to the spoiler", switched >= 10, switched)
		check("which is then the bot the seat plays as", opponent.playing("one") ~= nil)
	end)
end

-- Moves worth the same are a coin, all the way down: the search halves its list
-- by score, and a tie cut in list order made the first move the only one.
function M.test_engine_seat_breaks_a_tie_at_random(check)
	with_guess(function(name)
		local count = { guess_red = 0, guess_blue = 0, dud = 0 }
		for n = 1, 30 do
			math.randomseed(n)
			flow.init(name, n)
			opponent.take("one", "indifferent")
			local moves = opponent.legal()
			local k = picked(moves, opponent.choose("one", moves))
			count[k] = count[k] + 1
		end
		check("every move is picked sometimes", count.dud > 0 and count.guess_red > 0 and count.guess_blue > 0,
			count.dud .. " dud, " .. count.guess_red .. " red, " .. count.guess_blue .. " blue")
	end)
end

function M.test_engine_seat_leaves_nothing_of_what_it_tried(check)
	with_guess(function(name)
		math.randomseed(1)
		flow.init(name, 1)
		local json = require("json")
		local log = require("log")
		local board, lines, undo = json.encode(entity.registry()), log.count(), flow.can_undo()
		opponent.choose("one", opponent.legal())
		check("the board is as it was", json.encode(entity.registry()) == board)
		check("the log has nothing of the tries", log.count() == lines)
		check("and undo is where it was", flow.can_undo() == undo)
	end)
end

-- A rehearsal makes as many moves as it likes, and every one of them checkpoints.
-- Past MAX_HISTORY those would push the player's own undo off the far end.
function M.test_a_rehearsal_keeps_the_undo_stack_it_found(check)
	math.randomseed(2)
	flow.init("tower.json", 2)
	local json = require("json")
	local board = json.encode(entity.registry())
	opponent.legal()[1]()
	flow.rehearse(function()
		for _ = 1, 200 do
			local moves = opponent.legal()
			if #moves == 0 then break end
			moves[math.random(#moves)]()
		end
	end)
	check("the move before it can still be taken back", flow.undo())
	check("all the way back", json.encode(entity.registry()) == board)
end

-- A move that ends the game by loading another is one the engine has to be able
-- to weigh, and weighing it must not leave this game.
function M.test_a_rehearsal_cannot_load_another_game(check)
	local declaration = require("declaration")
	flow.init("menu.json", 1)
	local G = declaration.G
	local card
	for e in entity.each("card") do
		if e.def_key == "play_spellstorm" and e.zone_id then card = e end
	end
	flow.play_card(card.id, {})
	local answer
	for e in entity.each("card") do
		if e.def_key == "m_table" and e.zone_id then answer = e end
	end
	flow.rehearse(function() flow.play_card(answer.id, {}) end)
	check("still the menu", declaration.G == G and declaration.filename == "menu.json", declaration.filename)
	check("with no load left waiting", require("actions").pending_load == nil)
	check("and the answer still on offer", flow.can_play(answer.id))
end

-- The title screen asks who sits across the table. `bot_seats` is written beside
-- a `load_game` and runs before the load lands, so it has to mean the next game.
function M.test_engine_seat_chosen_on_the_menu_is_the_next_games(check)
	local function card(k)
		for e in entity.each("card") do
			if e.def_key == k and e.zone_id then return e end
		end
	end
	local function choose(answer)
		flow.init("menu.json", 1)
		flow.play_card(card("play_spellstorm").id, {})
		flow.play_card(card(answer).id, {})
	end
	choose("m_engine")
	check("the engine plays the second seat", opponent.seats.seat_two == true)
	check("and the first is this screen's", net.seat == "seat_one" and not opponent.seats.seat_one)
	flow.init("menu.json", 1)
	check("loading another game stands it down", next(opponent.seats) == nil)
	choose("m_table")
	check("at the table nobody is the engine", next(opponent.seats) == nil)
	net.claim_seat(nil)
end

return M
