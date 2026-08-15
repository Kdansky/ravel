-- How a game ends, and who it ended for.
--
-- A solo game's ending is one word and cannot be wrong: you against the tower.
-- The moment two seats read the same card, one word is wrong for one of them —
-- so a win is a number on the winning seat, and the screen answers it against
-- whoever this client has claimed. That makes the *same state* end differently
-- on two machines, which is the property no other test in the suite can express.
--
-- The numbers under the banner are the same question asked of the HUD: a row
-- labelled "Your score" must be your score, not the score of whoever is to move.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local net = require("net")
local geometry = require("geometry")
local predicate = require("predicate")
local declaration = require("declaration")

local M = {}

-- Chess, addressed the way a player says it: a piece is the square it stands on.
local function move(from, to)
	local board = zones.find("board")
	local occ = entity.get(geometry.slot_named(board, from)).occupant
	return occ ~= nil and flow.activate(occ, { geometry.slot_named(board, to) }, 1)
end

function M.test_ending_a_taken_king_ends_the_game(check)
	flow.init("chess.json", 1)
	check("no outcome while the game runs", flow.outcome() == nil)

	-- Fool's mate, then the mate played out: this game has no legality filter,
	-- so white is free to ignore the check and black is free to take the king.
	move("f2", "f3"); move("e7", "e5")
	move("g2", "g4"); move("d8", "h4")
	check("white is in check and must answer", flow.outcome() == nil)
	move("a2", "a3")
	check("black takes the king", move("h4", "e1"))

	check("the game announced an ending instead of dropping to the menu",
		flow.outcome() ~= nil and declaration.G.title == "Chess")
	check("and it knows which side it was", flow.winner() == "Black")

	-- The win is on the seat, so it is state: a rule can read it, the snapshot
	-- carries it to the other machine, and undo takes it back. Read through a
	-- subject rather than off a captured entity — undo restores whole tables, so
	-- a reference taken before it points at a game that no longer exists.
	check("the winner is a number on the winning seat", predicate.total("won@black_side") == 1)
	check("and the loser carries the stat unset, not missing",
		predicate.total("won@white_side") == 0)
	flow.undo()
	check("undoing the last move un-wins it", predicate.total("won@black_side") == 0
		and flow.outcome() == nil and flow.winner() == nil)
end

function M.test_ending_the_same_state_reads_two_ways(check)
	flow.init("chess.json", 1)
	move("f2", "f3"); move("e7", "e5")
	move("g2", "g4"); move("d8", "h4")
	move("a2", "a3"); move("h4", "e1")

	-- Nobody at this screen is playing, so there is nobody to congratulate: the
	-- room is told who won. This is the hot-seat ending, and the spectator's.
	check("with no seat claimed the ending is only announced",
		zones.watching() == nil and flow.outcome() == "decided")

	net.claim_seat("player_black")
	check("black, who took the king, is told they won", flow.outcome() == "victory")
	net.claim_seat("player_white")
	check("and white is told they lost, from the very same card",
		flow.outcome() == "defeat" and flow.winner() == "Black")
	net.claim_seat(nil)
end

function M.test_ending_a_winner_names_a_seat_not_a_side(check)
	flow.init("lost_cities.json", 11)
	actions.execute("gain_stat:won@north_side:1", {})
	actions.execute("reveal:north_wins", {})
	check("the tally's ending card is an ending", flow.outcome() == "decided")

	net.claim_seat("south")
	check("south reads its own defeat off it", flow.outcome() == "defeat")
	net.claim_seat("north")
	check("north reads its victory", flow.outcome() == "victory")

	-- A claim naming no seat in *this* game names nobody, so the ending falls
	-- back to being announced rather than delivered to whoever is up.
	net.claim_seat("player_white")
	check("a seat from another game is no seat here",
		zones.watching() == nil and flow.outcome() == "decided")
	net.claim_seat(nil)
end

function M.test_ending_a_solo_game_still_says_the_word(check)
	-- Six games say "victory" outright and every one of them is right to. A seat
	-- would be meaningless in them, so the word must survive untouched.
	flow.init("castle.json", 7)
	actions.execute("reveal:triumph", {})
	check("a solo ending is a word", flow.outcome() == "victory" and flow.winner() == nil)

	net.claim_seat("north")
	check("and no claim can change it", flow.outcome() == "victory")
	net.claim_seat(nil)
end

-- The seat cards hold the numbers, so a readout has to say whose it is asking
-- about. "Mine" is answered from the turn, which is the right seat at one screen
-- and the wrong one on a machine whose player is not to move.
function M.test_ending_the_numbers_belong_to_the_viewer(check)
	flow.init("lost_cities.json", 11)
	for e in entity.each("card") do
		if e.def_key == "north" then e.stats.score = 111 end
		if e.def_key == "south" then e.stats.score = 222 end
	end
	local function seat_turn(n)
		for e in entity.each("card") do
			if e.def_key == "system" then e.stats.turn = n end
		end
	end

	check("north is up and reads its own score", flow.summary()[1] == "Your score 111")
	seat_turn(2)
	check("with nobody claiming a seat the readout follows the turn",
		flow.summary()[1] == "Your score 222")

	net.claim_seat("north")
	check("a claimed seat reads its own while the other plays",
		flow.summary()[1] == "Your score 111", flow.summary()[1])
	net.claim_seat(nil)
	check("and standing up hands the readout back to the turn",
		flow.summary()[1] == "Your score 222")

	-- The override is scoped, and scoped means restored even when the body
	-- raises: an engine that stays somebody else afterwards is worse than a
	-- crash, because nothing says it happened.
	local ok = pcall(zones.as_seat, "north", function() error("boom") end)
	check("a raise inside a seat override still puts the seat back",
		ok == false and zones.active_seat() == "south")
end

return M
