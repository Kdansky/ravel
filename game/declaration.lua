local json = require("json")

local M = {}
M.G        = {}   -- current game definition; templates may be edited live (see cards.edit)
M.filename = nil  -- source file of the current game, for template reloads

-- Template-ish fields swapped wholesale by cards.reload. Zones and phases
-- are structural and need a full game load.
M.TEMPLATE_FIELDS = {
	"card_defs", "computed_tags", "stat_defs", "stat_defs_list",
	"tag_defs", "effect_defs", "parse_problems",
}

local function tag_set(arr)
	local s = {}
	if type(arr) ~= "table" then return s end
	for _, t in ipairs(arr) do s[t] = true end
	return s
end

-- Sections the engine reads from a game file. Anything else is a typo the
-- validator should surface, not silently ignore.
local KNOWN_SECTIONS = {
	title = true, seed = true, stats = true, computed_tags = true,
	templates = true, cards = true, zones = true, phases = true,
	end_conditions = true, setup = true, tags = true, effects = true,
}

-- Parse a game file into a definition table without touching current state.
-- Structural problems (typo'd sections, duplicate or missing keys) are
-- collected in G.parse_problems for the validator to report — a broken entry
-- is skipped, never fatal.
function M.parse(filename)
	local data = love.filesystem.read("games/" .. filename)
	assert(data, "Cannot read game file: " .. filename)
	local ok, parsed = pcall(json.decode, data)
	assert(ok, "Bad JSON in " .. filename .. ": " .. tostring(parsed))

	local G = {
		title          = parsed.title or "Ravel",
		seed           = parsed.seed,       -- optional: fixed RNG seed for the game
		card_defs      = {},
		zone_defs      = {},
		zone_list      = {},       -- ordered array of zone keys (preserves JSON order)
		stat_defs      = {},
		stat_defs_list = {},       -- ordered array of stat keys (for HUD display)
		phase_list     = {},       -- ordered array of phase keys
		phase_by_key   = {},
		computed_tags  = parsed.computed_tags or {},
		end_conditions = parsed.end_conditions or {},
		setup          = parsed.setup or {},
		tag_defs       = parsed.tags or {},  -- tag behaviour: { "item": { "zone": "inventory" } }
		effect_defs    = parsed.effects or {},  -- named effects on the fx base vocabulary
		parse_problems = {},
	}
	local pp = G.parse_problems
	local function entries(list, what)
		if list == nil then return {} end
		-- A JSON object decodes to a table too: non-list shapes have keys
		-- but no array part.
		if type(list) ~= "table" or (next(list) ~= nil and #list == 0) then
			pp[#pp + 1] = "the '" .. what .. "' section should be a list — wrap its entries in [ ... ]"
			return {}
		end
		return list
	end

	local sections = {}
	for k in pairs(KNOWN_SECTIONS) do sections[#sections + 1] = k end
	table.sort(sections)
	for k in pairs(parsed) do
		if not KNOWN_SECTIONS[k] then
			pp[#pp + 1] = "this file has a section '" .. tostring(k)
				.. "' the engine doesn't read (known sections: "
				.. table.concat(sections, ", ") .. ")"
		end
	end

	for _, cd in ipairs(entries(parsed.templates or parsed.cards, "templates")) do
		if type(cd) ~= "table" or not cd.key then
			pp[#pp + 1] = "a template has no \"key\" — every card needs a unique one"
		else
			if G.card_defs[cd.key] then
				pp[#pp + 1] = "two templates share the key '" .. cd.key
					.. "' — the second silently replaces the first"
			end
			cd.tags_set = tag_set(cd.tags)
			G.card_defs[cd.key] = cd
		end
	end

	-- Zones may omit pos: every type has a sensible default spot, so a first
	-- game needs no layout numbers at all (tune later). Hidden zones default
	-- off-screen, which also gives dealt cards their fly-in.
	local DEFAULT_POS = {
		hand   = { 0.19, 0.62, 0.97, 0.97 },
		grid   = { 0.03, 0.05, 0.60, 0.55 },
		deck   = { 0.75, 0.05, 0.95, 0.40 },
		pile   = { 0.75, 0.45, 0.95, 0.80 },
		hidden = { 0.42, -0.40, 0.58, -0.08 },
	}

	for _, zd in ipairs(entries(parsed.zones, "zones")) do
		if type(zd) ~= "table" or not zd.key then
			pp[#pp + 1] = "a zone has no \"key\" — every zone needs a unique one"
		else
			if G.zone_defs[zd.key] then
				pp[#pp + 1] = "two zones share the key '" .. zd.key
					.. "' — the second silently replaces the first"
			else
				G.zone_list[#G.zone_list + 1] = zd.key
			end
			zd.tags_set = tag_set(zd.tags)
			if not zd.pos then
				zd.pos = zd.tags_set.hidden and DEFAULT_POS.hidden
					or DEFAULT_POS[zd.type] or DEFAULT_POS.pile
			end
			G.zone_defs[zd.key] = zd
		end
	end

	for _, sd in ipairs(entries(parsed.stats, "stats")) do
		if type(sd) ~= "table" or not sd.key then
			pp[#pp + 1] = "a stat has no \"key\" — every stat needs a unique one"
		else
			if G.stat_defs[sd.key] then
				pp[#pp + 1] = "two stats share the key '" .. sd.key
					.. "' — the second silently replaces the first"
			else
				G.stat_defs_list[#G.stat_defs_list + 1] = sd.key
			end
			G.stat_defs[sd.key] = sd
		end
	end

	for _, pd in ipairs(entries(parsed.phases, "phases")) do
		if type(pd) ~= "table" or not pd.key then
			pp[#pp + 1] = "a phase has no \"key\" — every phase needs a unique one"
		else
			if G.phase_by_key[pd.key] then
				pp[#pp + 1] = "two phases share the key '" .. pd.key
					.. "' — the second silently replaces the first"
			-- Overlays are push-only (modals): reachable via push_phase, never via next_phase.
			elseif pd.type ~= "overlay" then
				G.phase_list[#G.phase_list + 1] = pd.key
			end
			-- draw_and_play is shorthand: play once, discard the rest, advance.
			if pd.type == "draw_and_play" then
				if pd.ends_after == nil then pd.ends_after = 1 end
				if pd.discard_hand == nil then pd.discard_hand = true end
			end
			G.phase_by_key[pd.key] = pd
		end
	end

	-- Built-in "turn the page": the reveal actions conjure cards into this
	-- hidden zone and push this overlay. A game may claim either key to
	-- override the presentation.
	if not G.zone_defs.reveal then
		G.zone_defs.reveal = { key = "reveal", type = "hand", injected = true,
			pos = { 0.22, 0.14, 0.78, 0.88 },
			tags_set = { hidden = true, page = true, no_peek = true } }
		G.zone_list[#G.zone_list + 1] = "reveal"
	end
	if not G.phase_by_key.reveal then
		G.phase_by_key.reveal = { key = "reveal", type = "overlay", zone = "reveal",
			page = true, injected = true }
	end

	return G
end

function M.load(filename)
	M.G        = M.parse(filename)
	M.filename = filename
	return M.G
end

return M
