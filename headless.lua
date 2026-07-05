-- Minimal love shim so the engine runs outside LÖVE (tests, CLI play).
-- Load from the repo root; game modules become require-able afterwards.

package.path = "game/?.lua;" .. package.path

love = {
	filesystem = {
		read = function(path)
			local f = io.open("game/" .. path, "rb")
			if not f then return nil end
			local data = f:read("*a")
			f:close()
			return data
		end,
	},
	graphics = {
		getDimensions = function() return 960, 540 end,
	},
}
