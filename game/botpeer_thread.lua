-- botpeer on a love.thread: the desktop's second engine (netlink.engine).
require("love.filesystem")
require("love.timer")
-- Layout asks the window's size and a thread has no window. Nothing here is drawn.
love.graphics = { getDimensions = function() return 960, 540 end }
math.randomseed(os.time())

local peer = require("botpeer")
local inbox, outbox = love.thread.getChannel("ravel_engine_in"), love.thread.getChannel("ravel_engine_out")
peer.start({
	name = "screen",
	send = function(text) outbox:push(text) end,
	recv = function() return inbox:pop() end,
})
while true do
	if not peer.step() then love.timer.sleep(0.02) end
end
