-- Which end of a pile a card lands on.
--
-- Every zone is a list and the top of a pile is the end of it: move_top draws
-- from there, and an arrival lands there. That was the only end reachable, so
-- "put it on top of your deck" was already written and "bury it underneath"
-- could not be said at all — and a deck-builder that buries a card is a rule,
-- not a detail.
--
-- One word, on the ops that name a destination: "bottom". It means something in
-- every zone, since every zone is a list, and it only *reads* as anything in a
-- deck, which is where somebody is going to draw next.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Pile Ends",
  "players": [{ "card": "one" }],
  "zones": [
    { "key": "hand", "type": "hand", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "bag", "type": "deck", "tags": ["face_down"], "pos": [0.55, 0.80, 0.65, 0.95] },
    { "key": "spare", "type": "deck", "tags": ["face_down"], "pos": [0.55, 0.55, 0.65, 0.70] },
    { "key": "table", "type": "pile", "pos": [0.75, 0.80, 0.85, 0.95] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "stats": [{ "key": "value", "label": "Value", "subject": "sum:value@spare" }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "alpha", "text": "Alpha", "tags": ["letter"] },
    { "key": "beta", "text": "Beta", "tags": ["letter"] },
    { "key": "omega", "text": "Omega", "tags": ["letter", "omega"], "card_stats": { "value": 1 } },
    { "key": "burier", "text": "Burier",
      "play": { "target": { "type": "card", "zones": ["hand"], "count": 1 },
        "action": ["move_target_to:bag:bottom"] } }
  ],
  "setup": {
    "place": [
      { "card": "alpha", "zone": "bag" },
      { "card": "beta", "zone": "bag" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_pile_ends.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_pile_ends.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- A pile read bottom to top, which is the order its list is in.
local function order(zone_key)
	local out = {}
	for _, id in ipairs(zones.find(zone_key).cards) do out[#out + 1] = entity.get(id).def_key end
	return table.concat(out, ",")
end

local function drawn()
	actions.execute("draw_from:bag:hand:1", {})
	local h = zones.find("hand")
	return entity.get(h.cards[#h.cards]).def_key
end

-- The default, stated so it stays true: nothing said means the top, and the top
-- is what the next draw takes.
function M.test_pile_ends_an_arrival_lands_on_top(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("fill:spare:omega:1", {})
		actions.execute("return_to:spare:bag", {})
		check("it went on top", order("bag") == "alpha,beta,omega", order("bag"))
		check("and it is the next card drawn", drawn() == "omega")
	end)
end

-- The word that could not be said before.
function M.test_pile_ends_bottom_buries(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("fill:spare:omega:1", {})
		actions.execute("return_to:spare:bag:bottom", {})
		check("it went under the pile", order("bag") == "omega,alpha,beta", order("bag"))
		check("so the next draw is what it always was", drawn() == "beta")
	end)
end

-- Every op that names a destination takes it, so a rule does not have to pick
-- its verb by which end it needs.
function M.test_pile_ends_every_destination_op_takes_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local om = zones.add(zones.find("hand"), "omega")
		actions.execute("move:hand:bag:bottom", {})
		check("move buries", order("bag") == "omega,alpha,beta", order("bag"))

		actions.execute("draw_from:bag:table:1", {})
		actions.execute("move:table:bag:bottom", {})
		check("and a card taken off the top can be put back underneath",
			order("bag") == "beta,omega,alpha", order("bag"))
		check("the buried card is the entity that was there all along",
			entity.get(om.id).zone_id == zones.find_id("bag"))
	end)
end

-- The one that had to be taught to count: an amount is one slot or five, so the
-- word after it is not found by counting colons.
function M.test_pile_ends_reads_past_a_measured_amount(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("fill:spare:omega:1", {})
		actions.execute("draw_from:spare:bag:sum:value@spare:bottom", {})
		check("the measured amount still drew one", #zones.find("bag").cards == 3,
			#zones.find("bag").cards)
		check("and the word after the measure was still read as the end",
			order("bag") == "omega,alpha,beta", order("bag"))
	end)
end

-- The top card of a deck goes under it — the move that has one zone at both
-- ends, and the reason a bare "top" is worth being able to write.
function M.test_pile_ends_a_deck_can_bury_its_own_top_card(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:bag:bag:1:bottom", {})
		check("the top card is now the bottom one", order("bag") == "beta,alpha", order("bag"))
	end)
end

-- Written on a card, through targeting, which is where an author will meet it.
function M.test_pile_ends_a_card_may_bury_what_it_targets(check)
	with_game(function(name)
		flow.init(name, 3)
		local om  = zones.add(zones.find("hand"), "omega")
		local bur = zones.add(zones.find("hand"), "burier")
		flow.play_card(bur.id, { om.id })
		check("the chosen card went under the deck", order("bag") == "omega,alpha,beta", order("bag"))
	end)
end

return M
