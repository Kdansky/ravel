function love.conf(t)
	t.window.title   = "Ravel"
	t.window.width   = 960
	t.window.height  = 540
	t.window.resizable = true
	t.modules.joystick = false
	t.modules.physics  = false
	-- Without an identity LÖVE has no save directory at all, and save.lua has
	-- nowhere to put a game. In the browser this names the folder inside the
	-- IndexedDB-backed home directory love.js mounts.
	t.identity = "ravel"
	t.console = true
end
