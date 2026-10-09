-- The engine's seats played by a second engine, linked to the first the way a
-- remote player is.
--
-- net's own tests say one process cannot hold two engines, and for a peer that
-- is only a convention: every module is a table held by package.loaded, so
-- loading the game's modules a second time with that emptied builds a second
-- engine that shares nothing with the first. Each side is run with its own
-- modules in package.loaded, because a module may still require another while
-- it runs.

local net = require("net")
local netlink = require("netlink")
local flow = require("flow")
local zones = require("zones")
local opponent = require("opponent")

local M = {}

local function ours(name)
	return package.searchpath(name, "game/?.lua") ~= nil
end

local function modules()
	local set = {}
	for k, v in pairs(package.loaded) do
		if ours(k) then set[k] = v end
	end
	return set
end

local function swap(set)
	for k in pairs(modules()) do package.loaded[k] = nil end
	for k, v in pairs(set) do package.loaded[k] = v end
end

local function second_engine()
	local first = modules()
	swap({})
	local peer = require("botpeer")
	local second = modules()
	swap(first)
	return function(fn)
		swap(second)
		local ok, res = pcall(fn, peer, second)
		swap(first)
		if not ok then error(res, 0) end
		return res
	end
end

function M.test_a_second_engine_plays_the_seats_the_screen_is_not_in(check)
	local there = second_engine()
	local here, away = netlink.loopback()
	math.randomseed(3)
	flow.init("spellstorm.json", 3)
	local mine = net.claim_seat("seat_one")
	net.link(here)
	net.publish(true)
	there(function(peer) peer.start(away) end)

	local runs, theirs, landed = 0, 0, true
	net.on_apply = function(_, run)
		if run then runs = runs + 1 end
	end
	for _ = 1, 400 do
		if theirs >= 6 then break end
		if there(function(peer) return peer.step() end) then theirs = theirs + 1 end
		net.poll()
		landed = landed and net.desync == nil
		if zones.active_seat() == mine then
			local moves = opponent.legal()
			if #moves > 0 then moves[math.random(#moves)]() end
		end
	end
	local far = there(function(_, m)
		m.net.poll()
		return m.net.fingerprint()
	end)
	check("the engine moved for the other seat", theirs >= 6, theirs)
	check("its moves arrived as the runs that made them", runs > 0, runs .. " runs for " .. theirs .. " moves")
	check("and both sides agree where the game is", landed and far == net.fingerprint(), tostring(net.desync))
	check("it never moved for this screen's seat", not there(function(_, m) return m.opponent.seats[mine] end))
	net.on_apply = nil
	net.unlink()
	net.claim_seat(nil)
end

return M
