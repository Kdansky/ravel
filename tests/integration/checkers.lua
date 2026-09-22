-- Checkers: a scripted game, in the shape chess's opening script has.
--
-- Three things here are not chess. The first is the **jump**, which takes a
-- piece standing on neither the square it left nor the square it lands on —
-- written with no new word, because a pattern is also a scope and the anchor
-- follows the piece: `down_right` read after `move_to:target` names the square
-- flown over. The second is the **chain**, which is a flow question rather than
-- a targeting one: a jump leaves `chaining` standing on the piece, the phase's
-- own route reads it and comes back to the same player, and the piece's gate
-- (`max:chaining@mine.board == chaining@self`) is what stops anybody else
-- moving while it is in the middle of one.
--
-- The third is **forced capture**, which is `aims:` read once per card. A
-- computed tag's condition is asked about one card at a time, so `can_jump`
-- worn by a piece is that piece having a jump and `tagged:can_jump@mine.board`
-- is a jump being on offer anywhere on my side — which is the rule. The same
-- tag under `chaining` is `chain_open`, and it is what ends a chain: the route
-- home stops firing the moment the jumps run out, so nobody has to say so.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")
local cards = require("cards")
local tags = require("tags")
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

-- Which of a piece's abilities it may use right now, by the index a test names:
-- 1 step, 2 and 3 the forward jumps, 4 and 5 a king's backward ones. `reach`
-- above answers where a piece could go if every ability were open, which is what
-- a threat is and not what a turn allows.
local function usable(from)
	local out = {}
	for _, u in ipairs(flow.usable_abilities(on(from).id)) do out[#out + 1] = u.index end
	table.sort(out)
	return table.concat(out, " ")
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

local function play(moves)
	for _, m in ipairs(moves) do
		if not move(m[1], m[2], m[3]) then return m[1] .. "-" .. m[2] end
	end
end

-- **A position set out directly.** Twelve men a side is the game's own opening
-- and says nothing about a chain, and walking one out of it takes eight moves
-- that forced capture now refuses half of. So a test about a rule clears the
-- board and puts down the four or five pieces the rule is about. The spare men
-- on a1 and h8 are there so that the last capture does not end the game, which
-- is a route the board is checked against before the chain's is.
local function position(pieces)
	start()
	local any
	for e in entity.each("card") do
		if e.def_key == "how_to_play" then any = e.id end
	end
	actions.run({ "purge:each.anyone.board" }, { card_id = any, targets = {} })
	for _, p in ipairs(pieces) do
		local e = cards.create(p[2], board.id)
		-- Set before the piece lands, because which way a rank counts is read
		-- off the owner when the square stamps it.
		e.stats.owner = p[1] == "red" and 1 or 2
		zones.place_in_slot(e.id, sq(p[3]))
	end
end

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

function M.test_checkers_a_chain_of_jumps_ends_itself(check)
	position({ { "red", "man", "d2" }, { "white", "man", "c3" }, { "white", "man", "c5" },
		{ "red", "man", "a1" }, { "white", "man", "h8" } })
	check("the jump is the only move red has", usable("d2") == "2" and flow.can_activate(on("a1").id) == false)

	check("d2 takes c3 and lands on b4", move("d2", "b4", 2) and at("b4") == "red man")
	check("red is still to move", zones.active_seat() == "player_red" and phase.current().key == "red_move")
	check("because the man it moved still has a jump", tags.entity_has(on("b4"), "chain_open"))
	check("and no other red man may move while that one is mid-jump", flow.can_activate(on("a1").id) == false)

	check("the same man takes c5 and lands on d6", move("b4", "d6", 3) and at("d6") == "red man")
	check("two white men are in the tray", #tray("player_red").cards == 2)
	check("the chain ends itself, because there is no third jump",
		tags.entity_has(on("d6"), "can_jump") == false and zones.active_seat() == "player_white")
	check("and the next turn starts with no chain standing", on("d6").stats.chaining == 0)
end

function M.test_checkers_a_jump_on_offer_must_be_taken(check)
	position({ { "red", "man", "c3" }, { "white", "man", "d4" },
		{ "red", "man", "a1" }, { "white", "man", "h8" } })
	check("a man with no jump has nothing to do at all", flow.can_activate(on("a1").id) == false)
	check("and the one with a jump may not step instead", move("c3", "b4", 1) == false)
	check("c3 takes d4 and lands on e5", move("c3", "e5", 3) and at("e5") == "red man")

	position({ { "red", "man", "c3" }, { "red", "man", "a1" }, { "white", "man", "h8" } })
	check("with the jump gone, the same man steps", flow.can_activate(on("a1").id)
		and move("c3", "b4", 1) and at("b4") == "red man")
end

function M.test_checkers_the_far_row_crowns_a_man(check)
	position({ { "red", "man", "f6" }, { "white", "man", "e7" }, { "white", "man", "c7" },
		{ "red", "man", "a1" }, { "white", "man", "h6" } })
	check("f6 takes e7 and lands on the far row", move("f6", "d8", 2) and at("d8") == "red king")
	check("the crowned king has a jump waiting", tags.entity_has(on("d8"), "can_jump"))
	check("and the crowning ends the move anyway", zones.active_seat() == "player_white"
		and on("d8").stats.chaining == 0)
	check("a king steps back the way a man may not", move("c7", "b6") and move("d8", "c7")
		and at("c7") == "red king")
end

function M.test_checkers_a_king_jumps_backwards_and_goes_on_jumping(check)
	position({ { "red", "king", "e7" }, { "white", "man", "d6" }, { "white", "man", "b6" },
		{ "red", "man", "a1" }, { "white", "man", "h8" } })
	check("the king takes d6 backwards and lands on c5", move("e7", "c5", 4) and at("c5") == "red king")
	check("it is still red's move", zones.active_seat() == "player_red")
	check("and it takes b6 forwards in the same turn", move("c5", "a7", 2) and at("a7") == "red king")
	check("two white men are in the tray", #tray("player_red").cards == 2)
	check("the turn passes when the jumps run out", zones.active_seat() == "player_white")
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
