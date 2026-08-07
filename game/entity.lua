-- Flat entity registry. All mutable game state lives here.
-- Entities reference each other by integer ID (index into ALL), never by table pointer.
-- This makes snapshots trivial: deep-copy ALL = full undo checkpoint.

local ALL = {}

local function register(e)
	table.insert(ALL, e)
	e.id = #ALL
	return e
end

local function get(id)
	return ALL[id]
end

-- Iterate all entities, or only those of the given kind.
local function each(kind)
	local i = 0
	return function()
		while true do
			i = i + 1
			if i > #ALL then return nil end
			if not kind or ALL[i].kind == kind then return ALL[i] end
		end
	end
end

local function reset()
	ALL = {}
end

local function deep_copy(x)
	if type(x) ~= "table" then return x end
	local c = {}
	for k, v in pairs(x) do c[k] = deep_copy(v) end
	return c
end

local function snapshot()
	return deep_copy(ALL)
end

local function restore(snap)
	ALL = snap
end

return {
	register  = register,
	get       = get,
	each      = each,
	reset     = reset,
	snapshot  = snapshot,
	restore   = restore,
}
