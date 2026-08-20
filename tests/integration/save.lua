-- Saving a game, and loading it back.
--
-- The format is the network's, already tested by tests/integration/net.lua, so
-- what is worth testing here is everything around it: that the bytes reach a
-- file and come back identical, that a game file edited since is refused rather
-- than half-believed, and that the words a game file says reach all of it.

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local flow        = require("flow")
local actions     = require("actions")
local predicate   = require("predicate")
local log         = require("log")
local json        = require("json")
local net         = require("net")
local save        = require("save")

local M = {}

local SLOT = "test_slot"

local function find(key, zone)
	local zid = zone and zones.find_id(zone)
	for e in entity.each("card") do
		if e.def_key == key and (not zid or e.zone_id == zid) then return e end
	end
end

-- Read the file back as a table, change one field, put it back: the only way to
-- ask what happens to a save that no longer describes the world it came from.
local function tamper(field, value)
	local snap = json.decode(love.filesystem.read("saves/" .. SLOT .. ".json"))
	snap[field] = value
	love.filesystem.write("saves/" .. SLOT .. ".json", json.encode(snap))
end

function M.test_save_a_position_comes_back_the_same(check)
	flow.init("chess.json", 7)
	actions.execute("stat_gain:round:3", {})
	flow.settle()
	local want, said = net.fingerprint(), log.count()

	check("it writes", save.write(SLOT))
	check("and the slot now holds something", save.exists(SLOT))

	flow.init("menu.json", 7)
	check("it loads", save.read(SLOT))
	check("into the game it was saved from", declaration.filename == "chess.json")
	check("landing on the identical state", net.fingerprint() == want)
	check("with the log it had", log.count() == said)
	save.forget(SLOT)
end

function M.test_save_is_refused_when_the_game_file_has_changed(check)
	flow.init("chess.json", 7)
	save.write(SLOT)
	tamper("gh", "deadbeef")

	local ok, err = save.read(SLOT)
	check("a save whose game hash does not match is refused", ok == false)
	check("and says which file moved", tostring(err):find("chess.json", 1, true) ~= nil, err)
	check("the game it refused to replace is untouched", declaration.filename == "chess.json")

	tamper("game", "no_such_game.json")
	ok, err = save.read(SLOT)
	check("a save of a game we do not have is refused too", ok == false)
	check("and says so rather than blaming the hash",
		tostring(err):find("not here", 1, true) ~= nil, err)
	save.forget(SLOT)
end

function M.test_save_refuses_a_slot_that_is_not_a_word(check)
	flow.init("chess.json", 7)
	-- The same rule as load_game's filename, and for the same reason: a game
	-- file can arrive from a stranger, so a path it names is a write primitive
	-- handed to one.
	for _, bad in ipairs({ "../escape", "saves/../../x", "a b", "" }) do
		local ok = save.write(bad)
		check("'" .. bad .. "' is not a slot", ok == false)
	end
	check("nothing was written outside the slot",
		love.filesystem.getInfo("saves/../escape.json") == nil)
end

function M.test_save_refuses_to_run_while_a_network_game_is_connected(check)
	flow.init("chess.json", 7)
	net.link({ name = "test", send = function() return true end, recv = function() end })
	local ok, err = save.write(SLOT)
	check("saving is refused while connected", ok == false)
	check("and says why", tostring(err):find("connected", 1, true) ~= nil, err)
	net.unlink()
	check("and works again once offline", save.write(SLOT))
	save.forget(SLOT)
end

function M.test_save_the_menu_offers_continue_only_when_there_is_one(check)
	save.forget("quick")
	flow.init("menu.json", 7)
	local cont = find("m_continue", "menu")
	check("the menu deals a Continue card", cont ~= nil)
	check("which cannot be played with nothing saved", flow.can_play(cont.id) == false)
	check("and the condition says the same", predicate.total("saved:quick") == 0)

	-- The whole path a player takes: a button in a game writes the save, the
	-- menu card reads it, and neither knows anything about a file.
	flow.init("chess.json", 7)
	local btn = find("save_button", "controls")
	check("chess deals a Save button", btn ~= nil)
	flow.play_card(btn.id, {})
	check("playing it saves", save.exists("quick"))
	local want = net.fingerprint()

	flow.init("menu.json", 7)
	cont = find("m_continue", "menu")
	check("now Continue can be played", flow.can_play(cont.id))
	flow.play_card(cont.id, {})
	check("and it brings the game back", declaration.filename == "chess.json")
	check("exactly as it was", net.fingerprint() == want)
	save.forget("quick")
end

function M.test_save_a_loaded_game_keeps_its_log_and_loses_its_undo(check)
	flow.init("chess.json", 7)
	local btn = find("save_button", "controls")
	flow.play_card(btn.id, {})
	check("there is something to undo before the load", flow.undo())

	flow.init("menu.json", 7)
	save.read("quick")
	check("the log came back", log.count() > 0)
	-- The same trade the network already makes, and for the same reason: the
	-- moves before the save were made in a game this process never ran, so
	-- undoing into one of them would fork it.
	check("but the history did not", flow.undo() == false)
	save.forget("quick")
end

return M
