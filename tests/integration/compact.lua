-- A row that closes up.
--
-- `compact` exists so that where a card sits goes on meaning how long it has
-- been there. A market row is a queue drawn sideways: cards enter at one end,
-- slide along as their neighbours are bought, and the one that has sat longest
-- is at the far end waiting to be exiled. Without a slide the cells are only a
-- set, and "the oldest card" is whichever the engine happens to reach first.
--
-- The half worth testing hardest is the ordering. Sliding each card as far as
-- it will go is not enough on its own: done in the wrong order a card behind
-- overtakes one in front, and the row still holds the same cards while no
-- longer saying anything true about them.

local entity  = require("entity")
local zones   = require("zones")
local actions = require("actions")
local flow    = require("flow")

local M = {}

local GAME = [==[{
  "title": "Compact",
  "patterns": {
    "rightward": { "vectors": [[1, 0]], "class": ["ray"] },
    "leftward":  { "vectors": [[-1, 0]], "class": ["ray"] },
    "nudge":     { "vectors": [[1, 0]] },
    "sideways":  { "vectors": [[1, 0], [-1, 0]], "class": ["ray"] }
  },
  "zones": [
    { "key": "row", "layout": "grid", "use": "abilities", "grid": [7, 1],
      "pos": [0.05, 0.40, 0.95, 0.60] },
    { "key": "off", "layout": "stack", "display": "offscreen" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "row", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "a", "text": "a", "tags": ["art"] },
    { "key": "b", "text": "b", "tags": ["art"] },
    { "key": "c", "text": "c", "tags": ["art"] },
    { "key": "x", "text": "x", "tags": ["item"] },
    { "key": "y", "text": "y", "tags": ["item"] },
    { "key": "s", "text": "s", "tags": ["staff"] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_compact.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_compact.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- The row as one word, a dot for an empty cell, so an assertion reads the way
-- the shelf looks.
local function reads()
	local z, out = zones.find("row"), {}
	for i, sid in ipairs(z.slots) do
		local s = entity.get(sid)
		out[i] = s.occupant and entity.get(s.occupant).def_key or "."
	end
	return table.concat(out)
end

-- Deal the row out of a written picture, so a test says its own starting state.
local function lay(picture)
	local z = zones.find("row")
	for i = 1, #picture do
		local key = picture:sub(i, i)
		if key ~= "." then
			local card = zones.add(zones.find("off"), key)
			zones.place_in_slot(card.id, z.slots[i])
		end
	end
end

-- The plain case, and the one that catches the ordering. Two cards with a hole
-- between them slide to the far end and arrive in the order they set off in:
-- taken in the order the scope hands them over, "a" would move first, take the
-- last cell, and end up behind "b".
function M.test_compact_a_gap_closes_and_the_order_survives(check)
	with_game(function(name)
		flow.init(name, 3)
		lay("a.b....")
		actions.execute("compact:row.art:rightward", {})
		check("both cards packed against the end", reads() == ".....ab", reads())
	end)
end

-- The same row read the other way. A direction is the pattern's whole job here,
-- so the one written picture has two right answers and the pattern picks.
function M.test_compact_the_pattern_says_which_end(check)
	with_game(function(name)
		flow.init(name, 3)
		lay("..a.b..")
		actions.execute("compact:row.art:leftward", {})
		check("packed against the near end instead", reads() == "ab.....", reads())
	end)
end

-- Two scopes, two directions, and something in the middle that is in neither.
-- This is Arnak's card row: artifacts close toward the moon staff from one
-- side, items from the other, and the staff itself does not move because no
-- scope names it.
function M.test_compact_two_sides_close_on_something_that_stays(check)
	with_game(function(name)
		flow.init(name, 3)
		lay("a.bsx.y")
		actions.execute("compact:row.art:rightward", {})
		actions.execute("compact:row.item:leftward", {})
		check("each side closed against the staff, which stayed", reads() == ".absxy.", reads())
	end)
end

-- A row with nothing to close is left exactly as it is — worth an assertion
-- because the alternative is a verb that reshuffles a full shelf every time it
-- runs, and a full shelf is the commonest state a market is in.
function M.test_compact_a_full_row_does_not_move(check)
	with_game(function(name)
		flow.init(name, 3)
		lay("....abc")
		actions.execute("compact:row.art:rightward", {})
		check("already packed, so nothing shifts", reads() == "....abc", reads())
	end)
end

-- How far is the pattern's to say. A bare pair is one step, which is a nudge
-- rather than a closing, and a game that wants one should be able to have it.
function M.test_compact_a_step_pattern_moves_one_cell(check)
	with_game(function(name)
		flow.init(name, 3)
		lay("a......")
		actions.execute("compact:row.art:nudge", {})
		check("a step pattern moves a single cell", reads() == ".a.....", reads())
	end)
end

return M
