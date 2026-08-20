-- What ends a turn, and where a turn's cards come from.
--
-- `ends_after` counts plays and cannot tell one from another. That is true of
-- the games written first — a turn is one card — and false of most: in a
-- trick-taking game putting a card into the middle ends your turn and
-- everything else you may do does not. `ends_when` is the phase saying so, in
-- the ordinary condition vocabulary, asked every time the game comes to rest.
--
-- Beside it, the other half of the same question: a phase's `zone` may be a
-- list, because a player may hold two hands — an open one beside a closed one.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")

local M = {}

-- One seat, two hands and a table. The lever is deliberately not a play: it is
-- an activation, so a phase that counted plays could never see it and a phase
-- that asks a condition can.
local GAME = [==[{
  "title": "Turn End",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "pot", "label": "Pot", "min": 0, "max": 99 },
    { "key": "purse", "min": 0, "max": 99, "tags": ["hidden"] }
  ],
  "zones": [
    { "key": "hand", "type": "hand", "tags": ["per_seat"], "pos": [[0.02, 0.80, 0.60, 0.95]] },
    { "key": "open", "type": "hand", "tags": ["per_seat", "face_up"], "pos": [[0.02, 0.60, 0.60, 0.75]] },
    { "key": "table", "type": "grid", "grid": [4, 1], "pos": [0.02, 0.30, 0.98, 0.50] },
    { "key": "levers", "type": "grid", "grid": [1, 1], "tags": ["activate", "optional"],
      "pos": [0.65, 0.80, 0.80, 0.95] },
    { "key": "bank", "type": "grid", "grid": [1, 1], "tags": ["hidden"] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": ["hand", "open"],
      "ends_when": "count:chip@table >= 1", "next": [{ "then": "over" }] },
    { "key": "over", "type": "player_input", "label": "done", "next": [{ "then": "over" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "card_stats": { "purse": 2, "pot": 0 } },
    { "key": "vault", "text": "Vault", "tags": ["vault"], "card_stats": { "purse": 3 } },
    { "key": "chip", "text": "Chip", "tags": ["chip"],
      "play": { "action": ["move_to:table"] } },
    { "key": "note", "text": "Note", "tags": ["note"],
      "play": { "action": ["move_to:open"] } },
    { "key": "lever", "text": "Lever", "tags": ["immutable"],
      "abilities": [
        { "key": "mine", "text": "Spend mine", "cost": { "purse@mine.player": 1 },
          "action": ["stat_gain:pot:1"] },
        { "key": "shared", "text": "Spend the vault's", "cost": { "purse@vault": 1 },
          "action": ["stat_gain:pot:1"] }
      ] }
  ],
  "setup": {
    "place": [
      { "card": "lever", "zone": "levers", "at": ["a1"] },
      { "card": "vault", "zone": "bank", "at": ["a1"] },
      { "card": "chip", "zone": "hand" },
      { "card": "note", "zone": "hand" },
      { "card": "chip", "zone": "open" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_turn_end.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_turn_end.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function in_zone(key, def_key)
	for _, cid in ipairs((zones.find(key) or {}).cards or {}) do
		local c = entity.get(cid)
		if c.def_key == def_key then return c end
	end
end

local function lever()
	return zones.find("levers").cards[1]
end

local function use(name)
	for _, u in ipairs(flow.usable_abilities(lever())) do
		if u.ability.key == name then return flow.activate(lever(), {}, u.index) end
	end
	return false
end

-- The whole point: an action that is not a play, run over and over, and the
-- phase stays exactly where it is because its condition is about the table.
function M.test_turn_end_only_the_move_that_matters_ends_it(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the turn is open", phase.current().key == "act")

		local me
		for e in entity.each("card") do if e.def_key == "one" then me = e end end
		check("the lever works", use("mine"))
		check("and again", use("mine"))
		check("twice over", me.stats.pot == 2, tostring(me.stats.pot))
		check("and the turn has not ended", phase.current().key == "act", phase.current().key)

		-- ...and a card played somewhere the condition does not watch is just as
		-- harmless, which is what `ends_after` could never express.
		flow.play_card(in_zone("hand", "note").id, {})
		check("a card laid face up is not the end of a turn",
			phase.current().key == "act", phase.current().key)
		check("and it went where it was sent", in_zone("open", "note") ~= nil)

		flow.play_card(in_zone("hand", "chip").id, {})
		check("the card that reaches the table does end it",
			phase.current().key == "over", phase.current().key)
	end)
end

-- The condition is asked whenever the game comes to rest, so a move made by
-- something other than the player ends the turn just as readily.
function M.test_turn_end_is_asked_after_every_action(check)
	with_game(function(name)
		flow.init(name, 3)
		check("still going", phase.current().key == "act")
		-- Nothing was played and nobody clicked a card: a rule moved it.
		actions.execute("move:open:table", {})
		flow.settle()
		check("a chip that arrived by any means ends the turn",
			phase.current().key == "over", phase.current().key)
	end)
end

-- A player with two hands. Both are the phase's, so both may be played out of —
-- and the first is still the singular one, which is where a deal would land.
function M.test_turn_end_a_phase_may_name_two_hands(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the phase names both", #phase.current().zone_list == 2)
		check("and the first is still the one thing it is", phase.current().zone == "hand")

		check("a card in the closed hand is playable", flow.can_play(in_zone("hand", "note").id))
		check("and one in the open hand is too", flow.can_play(in_zone("open", "chip").id))

		flow.play_card(in_zone("open", "chip").id, {})
		check("playing out of the second hand works", in_zone("table", "chip") ~= nil)
	end)
end

-- A cost key is a whole subject, so where the money lives is the game's to
-- decide: one purse per seat, or one purse on a card everybody spends from.
-- Neither needs a word of its own.
function M.test_turn_end_a_cost_may_be_per_seat_or_shared(check)
	with_game(function(name)
		flow.init(name, 3)
		local me
		for e in entity.each("card") do if e.def_key == "one" then me = e end end
		local vault = entity.get(zones.find("bank").cards[1])

		check("two in my own purse and three in the shared one",
			me.stats.purse == 2 and vault.stats.purse == 3)

		check("spending mine", use("mine"))
		check("came out of mine", me.stats.purse == 1 and vault.stats.purse == 3,
			("mine %d, vault %d"):format(me.stats.purse, vault.stats.purse))

		check("spending the shared one", use("shared"))
		check("came out of the vault", me.stats.purse == 1 and vault.stats.purse == 2,
			("mine %d, vault %d"):format(me.stats.purse, vault.stats.purse))

		me.stats.purse = 0
		local offered = {}
		for _, u in ipairs(flow.usable_abilities(lever())) do offered[u.ability.key] = true end
		check("an empty purse takes its own ability off the table", offered.mine == nil)
		check("and leaves the shared one standing", offered.shared == true)
	end)
end

return M
