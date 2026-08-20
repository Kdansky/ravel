-- Saving a game, and loading it back. Sits beside the engine the way net.lua
-- does: no engine module requires this one, the only lines it needed elsewhere
-- are two hooks, and deleting the file leaves the game as it was — the two ops
-- go silent, which is the honest answer for a build with nowhere to write.
--
-- **A save is a network message, not a format of its own.** net.snapshot() is
-- already everything ARCHITECTURE.md lists as state, plus the RNG position and
-- the file it belongs to, encoded with sorted keys; net.apply_full puts it back
-- and refuses a state whose game file has changed underneath it. So there is no
-- serialisation here at all — only somewhere for those bytes to live, and a
-- word a game can say. Anything that made the two diverge would buy a second
-- thing to keep correct against state_hash, the delta protocol and undo.
--
-- What a load costs, deliberately and in one place: the log comes back and the
-- undo history does not. That is what the network already does with every state
-- that arrives, for the same reason — the moves before a save were made in a
-- game this process was not running, and undoing into one of them would fork it.

local actions     = require("actions")
local predicate   = require("predicate")
local json        = require("json")
local log         = require("log")
local net         = require("net")

local M = {}

local DIR = "saves"

-- A slot is a plain word out of a game file, and the engine decides where it
-- lands. The same rule as load_game's filename and for the same reason: a game
-- text can arrive from a stranger through net.accept_game, and a save path it
-- controls would be a write primitive handed to one.
local function slot_path(slot)
	if type(slot) ~= "string" or not slot:match("^[%w_%-]+$") then return nil end
	return DIR .. "/" .. slot .. ".json"
end

-- love.js keeps the save directory in IndexedDB and flushes it when the game
-- quits, which a browser tab never does — so a write that is not pushed across
-- explicitly is lost at the next reload. The bridge is the one
-- netlink.lua documents: player.js overrides window.open, so a javascript: URL
-- runs. Fire and forget — syncfs is asynchronous, the value it leaves in
-- window._output is overwritten by the next snippet anybody evaluates, and
-- there is nothing useful to do with a failure a whole tab away.
local FLUSH = "javascript:(function(){try{var M=window.Module;"
	.. "if(M&&M.FS&&M.FS.syncfs)M.FS.syncfs(false,function(){});return \"ok\"}"
	.. "catch(e){return \"!\"+String(e&&e.message||e)}})()"

local function flush()
	if not (love.system and love.system.getOS and love.system.getOS() == "Web") then return end
	pcall(love.system.openURL, FLUSH)
end

function M.exists(slot)
	local path = slot_path(slot)
	if not (path and love.filesystem.getInfo) then return false end
	return love.filesystem.getInfo(path) ~= nil
end

function M.write(slot)
	local path = slot_path(slot)
	if not path then return false, "'" .. tostring(slot) .. "' is not a slot name" end
	if not love.filesystem.write then return false, "this build has nowhere to write" end
	-- Two people saving one shared game write two files that both claim to be
	-- it, and loading either one silently forks the game. A resync problem
	-- wearing a new hat, so it is refused rather than solved.
	if net.linked() then return false, "not while you are connected" end

	local snap = net.snapshot()
	snap.gh = net.game_hash(snap.game)
	love.filesystem.createDirectory(DIR)
	local ok, err = love.filesystem.write(path, json.encode(snap))
	if not ok then return false, "could not write " .. path .. ": " .. tostring(err) end
	flush()
	return true
end

function M.read(slot)
	local path = slot_path(slot)
	if not path then return false, "'" .. tostring(slot) .. "' is not a slot name" end
	-- Worse than saving while connected: this one silently forks the game.
	if net.linked() then return false, "not while you are connected" end
	local text = love.filesystem.read(path)
	if not text then return false, "nothing saved in '" .. slot .. "'" end
	local ok, snap = pcall(json.decode, text)
	if not ok or type(snap) ~= "table" then return false, "the save in '" .. slot .. "' cannot be read" end

	local name = tostring(snap.game)
	if not name:match("^[%w_%-]+%.json$") then return false, "that save names no game the engine would load" end
	local mine = net.game_hash(name)
	if not mine then return false, "that save is of " .. name .. ", which is not here" end
	-- The half of this the original note was unsure how to do, and the half a
	-- silent failure would hurt most: an edited game file makes a saved position
	-- mean something else, and no amount of loading it fixes that.
	if snap.gh and snap.gh ~= mine then
		return false, name .. " has changed since this was saved"
	end
	return net.apply_full(snap)
end

function M.forget(slot)
	local path = slot_path(slot)
	if not (path and love.filesystem.remove) then return false end
	local ok = love.filesystem.remove(path)
	flush()
	return ok and true or false
end

---------------------------------------------------------------- as cards

-- Saving is a thing a card does — invariant 7, the same route networking took.
-- actions.lua declares the words so the validator checks them like any other;
-- this supplies the meaning, and not requiring this file is what makes them
-- silent. What a player sees is the log, which is the only channel a card has.
actions.on_save = function(what, slot)
	local ok, err
	if what == "save" then
		ok, err = M.write(slot)
		if ok then log.add("Saved.") end
	else
		ok, err = M.read(slot)
	end
	if not ok then log.add("! " .. tostring(err)) end
	return ok
end

-- Whether a slot holds a game, for a condition. A fact about the machine rather
-- than about the game, so predicate cannot answer it itself and asks whoever
-- can — and a build without this file answers no, which is true there.
predicate.saved_slot = M.exists

return M
