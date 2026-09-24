-- "Once per point of something", said with the copy that already exists.
--
-- Croh Vosh's Ultimate is *"for each DOOM Token you have, take a card from your
-- discard or draw one"*, and Spellstorm spells it as four rules cards gated at
-- doom >= 1 .. >= 4 — correct only while the stat's ceiling is four. `copy`'s
-- count is an amount, so it can read the stat, and one card with no gate ought
-- to be the same rule. The risk is the offer: each run opens a question, and a
-- copy runs its loop straight through.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")

local M = {}

local GAME = [==[{
  "title": "Copy Per Point",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "doom", "min": 0, "max": 4, "on": ["player"], "start": 0 },
    { "key": "drew", "min": 0, "max": 99, "on": ["player"], "start": 0 }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.75, 0.9, 0.2], [0.05, 0.05, 0.9, 0.2]] },
    { "key": "discard", "layout": "stack", "copies": "per_seat", "display": "offscreen",
      "pos": [[0.05, 0.5, 0.1, 0.2], [0.05, 0.3, 0.1, 0.2]] },
    { "key": "rules", "layout": "stack", "display": "offscreen", "use": "none" },
    { "key": "options", "layout": "row", "status": "offer", "display": "offscreen" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "chip", "text": "Chip", "tags": ["chip"] },
    { "key": "ultimate", "text": "DOOOOM", "play": { "action": ["copy:everywhere.redraw:activate:sum:doom@mine.player"] } },
    { "key": "redraw", "text": "Redraw", "tags": ["immutable", "redraw"],
      "abilities": [{ "key": "redraw", "action": ["options:take,draw:optional"] }] },
    { "key": "gated_1", "text": "Doom 1", "tags": ["immutable"],
      "abilities": [{ "key": "gated", "needs": { "req": ["doom@mine.player >= 1"] }, "action": ["options:take,draw:optional"] }] },
    { "key": "gated_2", "text": "Doom 2", "tags": ["immutable"],
      "abilities": [{ "key": "gated", "needs": { "req": ["doom@mine.player >= 2"] }, "action": ["options:take,draw:optional"] }] },
    { "key": "old_ultimate", "text": "DOOOOM, a card per point", "play": { "action": ["activate_zone:rules:by_column:gated"] } },
    { "key": "take", "text": "Take a card back",
      "play": { "action": ["show:mine.discard:optional"] },
      "chosen": { "action": ["move:target:mine.hand"] } },
    { "key": "draw", "text": "Draw instead", "play": { "action": ["stat_gain:drew@mine.player:1"] } }
  ],
  "setup": { "place": [{ "card": "redraw", "zone": "rules" }, { "card": "gated_1", "zone": "rules" },
    { "card": "gated_2", "zone": "rules" }] }
}]==]

local PATH, FILE = "game/games/tmp_copy_per_point.json", "tmp_copy_per_point.json"

local function with_game(fn)
	local f = assert(io.open(PATH, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, FILE)
	os.remove(PATH)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function mine(key)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == "one" then return z end
	end
end

local function offered()
	local keys = {}
	for _, id in ipairs(zones.find("options").cards) do keys[#keys + 1] = entity.get(id).def_key end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function pick(def_key)
	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == def_key then return flow.play_card(id, {}) end
	end
	return false
end

local function cast(doom, key)
	seat("one").stats.doom = doom
	local ult = zones.add(mine("hand"), key or "ultimate")
	flow.play_card(ult.id, {})
	flow.settle()
end

-- Three points, three questions, one at a time — and each answered on its own.
function M.test_copy_per_point_asks_once_per_point(check)
	with_game(function(name)
		flow.init(name, 3)
		cast(3)
		for i = 1, 3 do
			check("question " .. i .. " is open, alone", offered() == "draw,take", offered())
			pick("draw")
			flow.settle()
		end
		check("three answers", seat("one").stats.drew == 3, seat("one").stats.drew)
		check("and no fourth question", offered() == "", offered())
	end)
end

-- No doom, no question: the count is zero and the copy runs nothing.
function M.test_copy_per_point_zero_asks_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		cast(0)
		check("nothing offered", offered() == "", offered())
		check("and the turn is not stuck", flow.can_play(zones.add(mine("hand"), "draw").id))
	end)
end

-- Croh's own shape: an answer that opens a question of its own while the next
-- point's question is still waiting. Whichever order the engine asks them in,
-- the copy must ask them in the order the card-per-point spelling does — it is
-- a respelling, not a new rule. (That order is every point's question first,
-- then the discards: an answer's own offer queues behind the ones already owed.)
local function walk(key)
	local seen = {}
	with_game(function(name)
		flow.init(name, 3)
		zones.add(mine("discard"), "chip")
		zones.add(mine("discard"), "chip")
		cast(2, key)
		seen[#seen + 1] = offered()
		for _ = 1, 6 do
			local o = zones.find("options").cards
			if not o[1] then break end
			local id = o[1]
			for _, c in ipairs(o) do
				if entity.get(c).def_key == "take" then id = c end
			end
			flow.play_card(id, {})
			flow.settle()
			seen[#seen + 1] = offered()
		end
		local chips = 0
		for _, id in ipairs(mine("hand").cards) do
			if entity.get(id).def_key == "chip" then chips = chips + 1 end
		end
		seen[#seen + 1] = chips .. " chips in hand"
	end)
	return table.concat(seen, " -> ")
end

function M.test_copy_per_point_asks_in_the_order_the_gated_cards_do(check)
	local old, new = walk("old_ultimate"), walk("ultimate")
	check("the same questions, in the same order", old == new, old .. "  vs  " .. new)
	check("and both chips came home", new:find("2 chips in hand$") ~= nil, new)
end

return M
