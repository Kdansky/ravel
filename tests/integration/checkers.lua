-- Checkers: a scripted game, in the shape chess's opening script has.
--
-- Two things here are not chess. The first is the **jump**, which takes a piece
-- standing on neither the square it left nor the square it lands on — written
-- with no new word, because a pattern is also a scope and the anchor follows the
-- piece: `down_right` read after `move_to:target` names the square flown over.
-- The second is the **chain**, which is a flow question rather than a targeting
-- one: a jump leaves `chaining` standing on the piece, the phase's own route
-- reads it and comes back to the same player, and the piece's gate
-- (`max:chaining@mine.board == chaining@self`) is what stops anybody else
-- moving while it is in the middle of one.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")
local actions = require("actions")
local geometry = require("geometry")
local predicate = require("predicate")
local targeting = require("targeting")

local M = {}

local board

local function start()
	flow.init("checkers.json", 1)
	board = zones.find("board")
end

local function sq(name)
	return geometry.slot_named(board, name)
end

-- Pieces are addressed by the square they stand on: twenty-four of them share
-- two templates, so where a man is is the only thing that tells it from another.
local function on(name)
	local occ = entity.get(sq(name)).occupant
	return occ and entity.get(occ)
end

local function at(name)
	local e = on(name)
	if not e then return nil end
	return (predicate.owner_of(e) == "player_red" and "red " or "white ") .. e.def_key
end

-- A man's abilities are step, jump left, jump right; a king's add the two
-- backward jumps. A test naming an index is naming one of those.
local function move(from, to, ability)
	local p = on(from)
	return p ~= nil and flow.activate(p.id, { sq(to) }, ability or 1)
end

local function reach(from)
	local p, out = on(from), {}
	for _, sid in ipairs(targeting.moves_of(p.id)) do
		local s = entity.get(sid)
		out[#out + 1] = string.char(96 + s.stats.col) .. tostring(s.stats.row)
	end
	table.sort(out)
	return table.concat(out, " ")
end

-- A per-seat zone is addressed by its seat here rather than by "mine"/"anyone",
-- because which of the two trays a taken man went to is the thing under test.
local function tray(seat)
	for _, z in ipairs(zones.all_with_key("taken")) do
		if z.seat == seat then return z end
	end
end

local function button(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function done()
	return flow.activate(button("done_jumping").id, {}, 1)
end

local function play(moves)
	for _, m in ipairs(moves) do
		if not move(m[1], m[2], m[3]) then return m[1] .. "-" .. m[2] end
	end
end

-- Eight moves that walk a white man down to e3 and leave a second on c5, with
-- d4 and b6 empty behind them: the position a double jump needs.
local DOUBLE_JUMP_SET_UP = {
	{ "e3", "f4" }, { "b6", "c5" },
	{ "f4", "g5" }, { "c5", "d4" },
	{ "a3", "b4" }, { "d4", "e3" },
	{ "b4", "a5" }, { "d6", "c5" },
}

function M.test_checkers_opens_with_twelve_men_a_side_on_the_dark_squares(check)
	start()
	check("twenty-four men, red to move", #board.cards == 24 and zones.active_seat() == "player_red")
	check("each side fills its own three rows", at("g1") == "red man" and at("a3") == "red man"
		and at("h6") == "white man" and at("b8") == "white man")
	check("and the light squares are empty", on("h1") == nil and on("g8") == nil)
	check("a rank counts from a piece's own side, so both front rows are 3",
		on("g3").stats.rank == 3 and on("h6").stats.rank == 3)
	check("the back row has nowhere to go", reach("g1") == "")
	check("the front row steps forward, and only forward", reach("g3") == "f4 h4")
end

function M.test_checkers_a_man_steps_diagonally_forward(check)
	start()
	check("g3-f4, and the turn passes", move("g3", "f4") and at("f4") == "red man"
		and zones.active_seat() == "player_white")
	check("white may not move red's men", flow.can_activate(on("f4").id) == false)
	check("white steps the other way down the board", move("f6", "e5") and at("e5") == "white man")
	check("a man may not step back the way it came", move("f4", "g3") == false)
end

function M.test_checkers_a_jump_takes_the_piece_it_flies_over(check)
	start()
	check("the opening plays", play({ { "g3", "f4" }, { "d6", "e5" } }) == nil)
	local victim = on("e5")
	check("f4 takes e5 and lands on d6", move("f4", "d6", 2) and at("d6") == "red man" and on("e5") == nil)
	check("the taken man is in red's tray, off the board",
		entity.get(victim.id).zone_id == tray("player_red").id and #board.cards == 23)
	check("and a square the jump did not fly over keeps what stands on it", at("e7") == "white man")
end

function M.test_checkers_a_jump_keeps_the_turn_until_the_player_says_it_is_over(check)
	start()
	check("*Done jumping* is not offered while nobody is jumping",
		flow.can_activate(button("done_jumping").id) == false)
	check("the set-up plays", play(DOUBLE_JUMP_SET_UP) == nil)

	check("f2 takes e3 and lands on d4", move("f2", "d4", 2) and at("d4") == "red man")
	check("red is still to move", zones.active_seat() == "player_red" and phase.current().key == "red_move")
	check("and no other red man may move while that one is mid-jump",
		flow.can_activate(on("g5").id) == false and flow.can_activate(on("c3").id) == false)

	check("the same man takes c5 and lands on b6", move("d4", "b6", 2) and at("b6") == "red man")
	check("two white men are in the tray", #tray("player_red").cards == 2)
	check("*Done jumping* hands the turn over", done() and zones.active_seat() == "player_white")
	check("and the next turn starts with no chain standing", on("b6").stats.chaining == 0)
end

function M.test_checkers_the_far_row_crowns_a_man(check)
	start()
	check("the set-up plays", play(DOUBLE_JUMP_SET_UP) == nil)
	check("the double jump plays", move("f2", "d4", 2) and move("d4", "b6", 2) and done())
	check("the way to the far row opens", play({
		{ "c7", "d6" }, { "b6", "c7" },
		{ "a7", "b6" }, { "g3", "h4" },
		{ "b8", "a7" } }) == nil)

	check("c7-b8, and the man is crowned", move("c7", "b8") and at("b8") == "red king")
	check("the crowning ends the move", zones.active_seat() == "player_white"
		and on("b8").stats.chaining == 0)
	check("white replies", move("f6", "e5"))
	check("a king steps back the way a man may not", move("b8", "c7") and at("c7") == "red king")
end

function M.test_checkers_a_king_jumps_backwards_and_goes_on_jumping(check)
	start()
	check("the game up to the crowning plays", play(DOUBLE_JUMP_SET_UP) == nil
		and move("f2", "d4", 2) and move("d4", "b6", 2) and done()
		and play({ { "c7", "d6" }, { "b6", "c7" }, { "a7", "b6" }, { "g3", "h4" }, { "b8", "a7" },
			{ "c7", "b8" }, { "f6", "e5" }, { "b8", "c7" }, { "e5", "f4" } }) == nil)

	check("the king takes d6 backwards and lands on e5", move("c7", "e5", 5) and at("e5") == "red king")
	check("it is still red's move", zones.active_seat() == "player_red")
	check("and it takes f4 in the same turn", move("e5", "g3", 5) and at("g3") == "red king")
	check("four white men are in the tray", #tray("player_red").cards == 4)
	check("the turn passes when red says so", done() and zones.active_seat() == "player_white")
end

function M.test_checkers_the_last_man_taken_ends_the_game(check)
	start()
	check("red opens", move("g3", "f4"))
	check("white replies", move("f6", "e5"))
	-- The last twelve captures are a long script and prove nothing the one above
	-- does not; what is under test is the route, which reads the board and not
	-- how it got that way.
	actions.run({ "purge:each.enemy.board" }, { card_id = on("f4").id, targets = {} })
	check("red moves onto an empty board", move("f4", "g5"))
	check("and the game is over", phase.current().key == "reveal"
		and entity.get(zones.find("reveal").cards[1]).def_key == "red_wins")
end

return M
