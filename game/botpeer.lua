-- The engine's seats, played by a second engine that is linked to the first the
-- way a remote player is. The screen keeps nothing of the bot but a link: it
-- hands its state over, its player moves, and the engine's moves come back as a
-- network peer's do — with the run that made them, to be watched a beat at a
-- time. The search can take seconds, and here it takes them on a thread of its
-- own (a love.thread on desktop, a Web Worker in the browser) while the screen
-- goes on drawing.
--
-- **The sender says which seat is theirs, and every other seat is the engine's.**
-- A whole state carries `from_seat`; a delta does not, and does not need to,
-- because a new game always arrives whole. No seat named is nobody sitting: a
-- hot-seat table the engine has no business at.
--
-- Interface-side, like opponent: it requires net, which no engine module may.

local net = require("net")
local opponent = require("opponent")
local stage = require("stage")

local M = {}

local theirs = nil

function M.start(transport)
	stage.listen()
	net.beats = stage.recorded
	net.on_apply = function(snap)
		if snap.count == nil then theirs = snap.from_seat end
	end
	net.link(transport)
end

-- Hear what has arrived, then move for as long as an engine seat is up. True
-- when a move was made, so a driver knows to come straight back.
function M.step()
	net.poll()
	opponent.leave()
	if theirs then
		for _, k in ipairs(net.seats()) do
			if k ~= theirs then opponent.take(k) end
		end
	end
	stage.arm()
	local moved = opponent.act()
	stage.seal()
	stage.clear()
	return moved
end

return M
