-- The module graph, asserted rather than hoped for.
--
-- Lua will happily load a cycle, which is exactly the problem: a require written
-- inside a function instead of at the top of the file is how one gets in, and
-- nothing complains afterwards. Three of them had been standing long enough to
-- be documented in the comments that apologised for them.
--
-- So the shape is a test. Reading the files rather than the loaded modules is
-- deliberate: `package.loaded` cannot tell a require at the top from one buried
-- in a branch, and the buried one is the whole thing being guarded against.

local M = {}

local SRC = "game/"

-- Every module named by a require in this file, wherever it is written. A lazy
-- require is still a dependency; hiding it in a function only hides it.
local function requires(mod)
	local f = io.open(SRC .. mod .. ".lua")
	if not f then return nil end
	local src = f:read("*a")
	f:close()
	local out = {}
	for name in src:gmatch('require%("([a-z_]+)"%)') do out[name] = true end
	return out
end

local function modules()
	local out = {}
	-- No directory listing in plain Lua, so the layer under test names its own
	-- members. A module the test does not know about is one it says nothing
	-- about, which is honest; the layers below are what the rule is for.
	for _, m in ipairs({ "entity", "declaration", "tags", "stats", "predicate", "zones",
		"auras", "targeting", "cards", "actions", "flow", "phase", "reactions",
		"tooltip", "render", "label", "validate" }) do
		local r = requires(m)
		if r then out[m] = r end
	end
	return out
end

-- Leaf utilities are not a layer and are allowed anywhere: they hold no game
-- state and require nothing themselves, so they cannot be half of a cycle.
local UTIL = { json = true, table_ext = true, log = true, rng = true }

-- The bottom of the engine, where everything else is built. These five are worth
-- pinning by name because every question the board is asked passes through them,
-- so a cycle here is a cycle in nearly every call.
--
-- `tags` answers what a card *is* and must not know what anything above it does
-- with the answer. `stats` is built on it, because a number is what is stored
-- plus what the tags shift it by — and not the other way round, which is what
-- kept two copies of "the ceiling rises with a buff" in step by luck.
local FLOOR = {
	entity      = {},
	shape       = {},
	needs       = { shape = true },
	declaration = { entity = true, shape = true, needs = true },
	tags        = { entity = true, declaration = true },
	stats       = { declaration = true, tags = true },
}

function M.test_layering_the_floor_of_the_engine_depends_only_downwards(check)
	local all = modules()
	for mod, allowed in pairs(FLOOR) do
		for dep in pairs(all[mod] or {}) do
			check(("%s may require %s"):format(mod, dep), allowed[dep] == true or UTIL[dep] == true,
				("%s requires %s, which is not below it"):format(mod, dep))
		end
	end
end

-- The one a tag genuinely has to ask upwards, and the shape that keeps it from
-- being a cycle: a computed tag's membership is a condition, and conditions are
-- predicate's language. Named slot, one implementation, installed at load.
function M.test_layering_the_condition_seam_is_a_slot_and_not_a_require(check)
	local tags = require("tags")
	check("tags declares the seam", type(tags.asks) == "function")
	check("and does not require predicate to do it",
		(requires("tags") or {}).predicate == nil)
	check("predicate is what fills it",
		(io.open(SRC .. "predicate.lua"):read("*a")):find("function tags.asks", 1, true) ~= nil)

	-- And it is filled by the time anything can ask, which is what makes the
	-- default safe to be a "no" rather than an error.
	require("predicate")
	local entity = require("entity")
	local found
	for e in entity.each("card") do found = e; break end
	if found then
		check("a computed tag answers through it",
			type(tags.entity_has(found, "dead")) == "boolean")
	end
end

-- Cycles that are still standing. Written down so that the number only ever goes
-- down: a new one fails this, and closing one of these fails it too and is meant
-- to, because the entry then comes out of the list.
local KNOWN = {
	["cards|predicate"]     = "cards asks what a condition says; predicate asks a card for its abilities",
	["predicate|targeting"] = "`aims:` counts what an ability could point at, and targeting is built on conditions",
	["predicate|zones"]     = "a zone's leaves/arrives carry conditions, and every scope names a place",
}

function M.test_layering_no_cycle_is_left_that_is_not_written_down(check)
	local all = modules()
	local seen = {}
	for a, deps in pairs(all) do
		for b in pairs(deps) do
			if all[b] and all[b][a] then
				local key = a < b and (a .. "|" .. b) or (b .. "|" .. a)
				seen[key] = true
				check("the " .. key .. " cycle is a known one", KNOWN[key] ~= nil,
					"undeclared cycle between " .. a .. " and " .. b)
			end
		end
	end
	for key, why in pairs(KNOWN) do
		check(key .. " is still there, so its entry earns its place", seen[key] == true,
			"closed: delete this entry — " .. why)
	end
end

return M
