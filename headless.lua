-- Minimal love shim so the engine runs outside LÖVE (tests, CLI play).
-- Load from the repo root; game modules become require-able afterwards.

package.path = "game/?.lua;" .. package.path

-- LÖVE hands the game a save directory; headless has no host to ask, so saves
-- land in .saves/ beside the process — visible, disposable, and never the
-- player's real one, which a test run would otherwise write over. Read looks
-- there first and in the game folder second, which is the order physfs uses.
-- `save_dir` is a field so the test harness can give each test its own.
local function saved(path)
	return love.filesystem.save_dir .. "/" .. path
end

local function slurp(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

love = {
	filesystem = {
		save_dir = os.getenv("RAVEL_SAVE_DIR") or ".saves",
		read = function(path)
			return slurp(saved(path)) or slurp("game/" .. path)
		end,
		write = function(path, data)
			local f = io.open(saved(path), "wb")
			if not f then return false, "cannot write " .. path end
			f:write(data)
			f:close()
			return true
		end,
		-- The one call here that reaches a shell, so the path is checked rather
		-- than trusted: everything else in this file is confined to io.open.
		createDirectory = function(path)
			if not tostring(path):match("^[%w_%-/]+$") then return false end
			os.execute("mkdir -p " .. saved(path))
			return true
		end,
		getInfo = function(path)
			local f = io.open(saved(path), "rb") or io.open("game/" .. path, "rb")
			if not f then return nil end
			f:close()
			return { type = "file" }
		end,
		remove = function(path)
			return os.remove(saved(path)) and true or false
		end,
	},
	graphics = {
		getDimensions = function() return 960, 540 end,
	},
}
