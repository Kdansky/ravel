-- Where this screen's engine seats are played: by a second engine on a thread of
-- its own, linked the way a remote player is (botpeer.lua), so the screen goes
-- on drawing — and can be pointed at — while the engine thinks.
--
-- Seats handed to `opponent` here are passed on the frame they appear, which is
-- what lets every way of asking for an opponent (the title screen, `o`) stay
-- what it was. Where no second engine can start they stay with `opponent`, which
-- plays them in a frame of this screen's, as it always has.

local net = require("net")
local netlink = require("netlink")
local opponent = require("opponent")
local declaration = require("declaration")
local zones = require("zones")

local M = {}

local link = nil     -- the transport, once one has started; false where none can
local linked = false
local seats = {}     -- the engine's, while it holds them
local game = nil     -- the game it holds them in
local said = 0       -- when the whole state was last sent and not answered
local checked = 0    -- when the far end was last asked whether it died

function M.leave()
	if linked then net.unlink() end
	linked, seats, game = false, {}, nil
end

function M.active()
	return linked
end

-- The seat the engine is deciding for, or nil.
function M.thinking()
	local seat = zones.active_seat()
	return linked and seat ~= nil and seats[seat] and seat or nil
end

function M.update(now)
	if next(opponent.seats) then
		if link == nil then link = netlink.engine() or false end
		if not link then return end
		seats, game = opponent.seats, declaration.G
		opponent.leave()
		if not linked then net.link(link) end
		linked = true
		net.publish(true)
		said = now
		return
	end
	if not linked then return end
	if declaration.G ~= game then return M.leave() end
	-- A worker still loading its Lua hears nothing, and a BroadcastChannel keeps
	-- nothing for a listener that is not there yet: say it again until answered.
	if not net.last_heard and now - said > 1 then
		net.publish(true)
		said = now
	end
	if now - checked < 1 then return end
	checked = now
	local err = link.failed and link.failed()
	if not err then return end
	-- The seats come back here, where at least they are played.
	print("the engine's thread failed (" .. tostring(err) .. "); it thinks on this one instead")
	local back = seats
	M.leave()
	link = false
	for k, b in pairs(back) do opponent.seats[k] = b end
end

return M
