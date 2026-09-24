-- The escape hatch opens a gated card when nothing else in the hand can be
-- played, so a mandatory play can never soft-lock a hand.
--
-- "Can be played" is the whole of can_play's question, asked of the other card.
-- It used to be only cost and needs, so a neighbour with nothing to run, or one
-- for another phase, held the hatch shut while being unplayable itself — and the
-- hand had no move at all.

local entity   = require("entity")
local flow     = require("flow")
local opponent = require("opponent")

local M = {}

local GAME = [==[{
  "title": "Hatch",
  "players": [{ "card": "one" }],
  "stats": [{ "key": "gold", "on": ["player"], "start": 0 }],
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.2, 0.8, 0.5, 0.95], "contents": ["gated", "other"] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.2, 0.4, 0.5, 0.55] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] },
    { "key": "later", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "gated", "text": "Gated", "play": { "needs": { "req": ["gold@mine.player >= 1"] }, "action": ["move_to:field"] } },
    { "key": "other", "text": "Other" %s }
  ],
  "setup": { "place": [{ "card": "one", "zone": "field" }] }
}]==]

local function with_game(other, fn)
	local path = "game/games/tmp_hatch.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME:format(other))
	f:close()
	local ok, err = pcall(function()
		flow.init("tmp_hatch.json", 1)
		fn()
	end)
	os.remove(path)
	if not ok then error(err, 0) end
end

local function playable(key)
	for e in entity.each("card") do
		if e.def_key == key then return flow.can_play(e.id) end
	end
end

function M.test_escape_hatch_stays_shut_while_another_card_can_be_played(check)
	with_game(', "play": { "action": ["move_to:field"] }', function()
		check("the other card is playable", playable("other"))
		check("so the gated one waits", not playable("gated"))
	end)
end

function M.test_escape_hatch_opens_beside_a_card_with_nothing_to_run(check)
	with_game("", function()
		check("the other card is no move", not playable("other"))
		check("so the gated one may go", playable("gated"))
		check("and the hand has a move", #opponent.legal() > 0)
	end)
end

function M.test_escape_hatch_opens_beside_a_card_for_another_phase(check)
	with_game(', "play": { "phases": ["later"], "action": ["move_to:field"] }', function()
		check("the other card is not for this phase", not playable("other"))
		check("so the gated one may go", playable("gated"))
		check("and the hand has a move", #opponent.legal() > 0)
	end)
end

return M
