-- Which cell of a grid a card lands in.
--
-- Every zone is a list and a grid is also a set of squares, so the argument
-- that says which *end* of a pile a card lands on had nothing to say about a
-- board: an arrival took the first free cell by index and no rule could ask for
-- another. That is right for a hand of five and wrong for a row that fills from
-- both ends — Arnak's market deals artifacts at one end and items at the other,
-- and its file splits the row into two zones sized by arithmetic to say so.
--
-- No new word: the position argument that already reads "top" and "bottom"
-- reads a cell name too, in the spelling every other square is written in. It
-- is one argument on every op that names a destination, so `move`, `take` and
-- `draw_from` all gained it at once, and a cell that cannot take the card
-- refuses the whole move rather than quietly landing it somewhere else.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Named Cell",
  "players": [{ "card": "one" }],
  "stats": [{ "key": "stock", "min": 0, "max": 99, "label": "Left" }],
  "zones": [
    { "key": "row", "layout": "grid", "grid": [5, 1], "pos": [0.05, 0.35, 0.9, 0.3] },
    { "key": "deck", "layout": "stack", "visibility": "secret", "pos": [0.05, 0.05, 0.15, 0.25] },
    { "key": "box", "layout": "grid", "grid": [1, 1], "status": "supply",
      "contents": ["chip:4"], "pos": [0.25, 0.05, 0.15, 0.25] },
    { "key": "hand", "layout": "row", "pos": [0.05, 0.7, 0.9, 0.25] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "alpha", "text": "Alpha", "tags": ["letter"] },
    { "key": "beta", "text": "Beta", "tags": ["letter"] },
    { "key": "gamma", "text": "Gamma", "tags": ["letter"] },
    { "key": "chip", "text": "Chip", "tags": ["chip"] }
  ],
  "setup": { "place": [
    { "card": "alpha", "zone": "deck" },
    { "card": "beta", "zone": "deck" },
    { "card": "gamma", "zone": "hand" }
  ] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_named_cell.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_named_cell.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- The row read left to right, a dot for a cell nobody is standing on.
local function row()
	local z = zones.find("row")
	local out = {}
	for i, sid in ipairs(z.slots) do
		local occ = entity.get(sid).occupant
		out[i] = occ and entity.get(occ).def_key or "."
	end
	return table.concat(out, ",")
end

local function cell_of(def_key)
	for _, id in ipairs(zones.find("row").cards) do
		local e = entity.get(id)
		if e.def_key == def_key then return e.slot_id end
	end
end

-- The far end of an empty row, which is the cell auto_slot would never pick.
function M.test_named_cell_a_deal_lands_where_it_is_told(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:deck:row:1:e1", {})
		check("it went to the end of the row", row() == ".,.,.,.,beta", row())
		actions.execute("draw_from:deck:row:1:a1", {})
		check("and the next one to the other end", row() == "alpha,.,.,.,beta", row())
	end)
end

-- The count is optional in that slot, as it is for "top" and "bottom": nothing
-- in the grammar reads a bare word as an amount, so a cell may stand where the
-- number would have gone.
function M.test_named_cell_the_count_may_be_left_out(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:deck:row:c1", {})
		check("one card, in the middle", row() == ".,.,beta,.,.", row())
	end)
end

-- Every op that names a destination takes it, so a rule does not have to pick
-- its verb by whether it can say where the card goes.
function M.test_named_cell_every_destination_op_takes_it(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("move:hand:row:1:d1", {})
		check("move places", row() == ".,.,.,gamma,.", row())
		actions.execute("take:box.chip:row:1:b1", {})
		check("and take, out of the box", row() == ".,chip,.,gamma,.", row())
		check("the box paid for it", entity.get(zones.find("box").cards[1]).stats.stock == 3)
	end)
end

-- The whole point of the word: without it the arrival takes the first free cell
-- by index, which is the right answer for a hand and the wrong one for a row
-- that fills from both ends.
function M.test_named_cell_saying_nothing_still_takes_the_first_free_cell(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:deck:row:2", {})
		check("both cards packed against the left", row() == "beta,alpha,.,.,.", row())
	end)
end

-- A refusal, not a card dropped somewhere else. Both halves matter: the row is
-- unchanged, and the card is still where it was to be moved again.
function M.test_named_cell_a_taken_cell_refuses_the_move(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:deck:row:1:c1", {})
		actions.execute("move:hand:row:1:c1", {})
		check("the row is as it was", row() == ".,.,beta,.,.", row())
		check("and the card never left the hand", #zones.find("hand").cards == 1)
	end)
end

function M.test_named_cell_a_cell_that_is_not_there_refuses(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("move:hand:row:1:z9", {})
		check("nothing moved", row() == ".,.,.,.,." and #zones.find("hand").cards == 1, row())
	end)
end

-- A grid is the only zone with cells to name, and a pile asked for one is a
-- mistake the validator catches — the engine's part is to refuse rather than to
-- guess which end was meant.
function M.test_named_cell_a_zone_without_cells_refuses(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("move:hand:deck:1:a1", {})
		check("the card stayed put", #zones.find("hand").cards == 1)
		check("and the deck is untouched", #zones.find("deck").cards == 2)
	end)
end

-- The square is the card's, not the zone's: a card that arrived by name says
-- where it stands the way one placed by a rule does, so conditions reading
-- "col" and the renderer both see the same board.
function M.test_named_cell_the_card_knows_the_square_it_took(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:deck:row:1:d1", {})
		local slot = entity.get(cell_of("beta"))
		check("it holds the card back", slot.occupant == zones.find("row").cards[1])
		check("and it is the fourth cell", slot.stats.col == 4, tostring(slot.stats.col))
	end)
end

return M
