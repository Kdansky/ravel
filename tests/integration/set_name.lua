-- set_name copies a field off one card onto another as its "name" — written
-- for a seat card whose text is "{name}", so choosing a wizard can give the
-- seat that wizard's own text without a second copy of it living on the pick.

local zones       = require("zones")
local entity      = require("entity")
local actions     = require("actions")
local flow        = require("flow")
local label       = require("label")
local declaration = require("declaration")

local M = {}

local GAME = [==[{
  "title": "Set Name",
  "players": [ { "card": "p1" }, { "card": "p2" } ],
  "cards": [
    { "key": "p1", "text": "Player One" },
    { "key": "p2", "text": "Player Two" },
    { "key": "merlin", "text": "Merlin", "tags": ["wizard"] }
  ],
  "zones": [
    { "key": "roster", "layout": "row", "use": "abilities" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "roster", "next": [{ "then": "act" }] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_set_name.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_set_name.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat_entity(seat_key)
	for e in entity.each("card") do
		if e.def_key == seat_key then return e end
	end
end

-- Standing in for "the wizard's own on_play": @self is the card whose action
-- this is, which is exactly ctx.card_id here — the shape a real wizard's
-- on_play would run this in.
function M.test_set_name_copies_a_field_from_one_card_to_another(check)
	with_game(function(name)
		flow.init(name, 3)
		local wizard = zones.add(zones.find("roster"), "merlin")
		actions.execute("set_name:mine.player:text@self", { card_id = wizard.id })
		local seat = seat_entity(declaration.G.seat_list[1])
		check("the seat entity carries the wizard's text as its name",
			seat and seat.name == "Merlin", seat and seat.name)
	end)
end

-- The point of the verb: a seat card whose text is a template picks up the
-- new name everywhere {owner}/{active} already read it, with no other change.
function M.test_set_name_feeds_a_seat_s_own_template_text(check)
	with_game(function(name)
		flow.init(name, 3)
		declaration.G.card_defs.p1.text = "{name}"
		local wizard = zones.add(zones.find("roster"), "merlin")
		actions.execute("set_name:mine.player:text@self", { card_id = wizard.id })
		check("the seat's templated text now reads the wizard's name",
			label.seat_text("p1") == "Merlin", label.seat_text("p1"))
	end)
end

-- A source scope naming nothing leaves the target untouched rather than
-- writing a nil or blank name over whatever it already had.
function M.test_set_name_with_no_source_does_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("set_name:mine.player:text@self", { card_id = nil })
		local seat = seat_entity(declaration.G.seat_list[1])
		check("no source card, so no name written", seat and seat.name == nil)
	end)
end

return M
