local json = require("json")

local M = {}
M.G        = {}   -- current game definition; templates may be edited live (see cards.edit)
M.filename = nil  -- source file of the current game, for template reloads

-- Template-ish fields swapped wholesale by cards.reload. Zones and phases
-- are structural and need a full game load.
M.TEMPLATE_FIELDS = {
	"card_defs", "card_list", "computed_tags", "stat_defs", "stat_defs_list",
	"tag_defs", "effect_defs", "pattern_defs", "asset_defs", "raw_assets", "parse_problems",
}

-- A card is written as a list of moments, and read as a flat def.
--
-- A moment is a block naming when something happens, holding the vocabulary of
-- that moment: "challenge" carries the condition a trial asks and the two action
-- lists it chooses between. Position is what disambiguates, so one word can mean
-- one thing — `needs` is a gate wherever it appears, and the block says what it
-- gates.
--
-- The engine keeps flat names. This table maps one to the other, so every read
-- site downstream is untouched by a change to what an author writes, and the
-- golden traces are what prove a move was faithful. Turning a document into
-- engine data is what this file is for.
--
-- Entries arrive here as each moment migrates, and not before: a block the
-- parser accepted while the validator rejected it would be worse than no block.
local MOMENTS = {
	play      = { cost = "cost", needs = "needs", target = "target", phases = "phases",
		action = "on_play" },
	activate  = { cost = "activate_cost", target = "activate_target", phases = "activate_phases",
		action = "on_activate", exhausts = "exhausts", moves = "moves" },
	challenge = { needs = "requires", pass = "on_pass", fail = "on_fail" },
	receive   = { needs = "accepts" },
	turn      = { action = "on_turn" },
	start     = { zone = "to_zone", slot = "to_slot" },
}
M.MOMENTS = MOMENTS

-- Flatten the moment blocks onto the def, in place. The authored blocks stay
-- where they are: ctrl+hover shows an author their own JSON, not our version of
-- it, and cards.dump has to round-trip back into the file.
--
-- The internal name is refused as an authored one. Without that the flat form
-- keeps working by accident — the engine reads def.requires either way — and an
-- accidental alias is exactly what moving the field was meant to remove. Checked
-- before anything is written, and driven by MOMENTS so there is no second list
-- to keep in step.
local function flatten_moments(def, pp, what)
	for moment, fields in pairs(MOMENTS) do
		for authored, internal in pairs(fields) do
			if def[internal] ~= nil and pp then
				pp[#pp + 1] = ('%s writes "%s", which is not a field: it is "%s" inside the "%s" block')
					:format(what, internal, authored, moment)
			end
		end
		local block = def[moment]
		if type(block) == "table" then
			for authored, internal in pairs(fields) do
				if block[authored] ~= nil then def[internal] = block[authored] end
			end
			-- Presence is the flag: a card with a "start" block starts in play, so
			-- there is no separate boolean to forget beside it.
			if moment == "start" then def.auto_play = true end
			-- Presence is the flag: a card with a "start" block starts in play,
			-- so auto_play stops being a boolean somebody can forget beside it.
			if moment == "start" then def.auto_play = true end
		end
	end
end

local function tag_set(arr)
	local s = {}
	if type(arr) ~= "table" then return s end
	for _, t in ipairs(arr) do s[t] = true end
	return s
end

-- Sections the engine reads from a game file. Anything else is a typo the
-- validator should surface, not silently ignore.
-- Exported as M.KNOWN_SECTIONS: SCHEMA.json describes the same list in prose,
-- and a test compares them so a new section cannot arrive undocumented.
local KNOWN_SECTIONS = {
	title = true, seed = true, stats = true, computed_tags = true,
	cards = true, zones = true, phases = true,
	end_conditions = true, setup = true, tags = true, effects = true,
	placeholder_art = true, patterns = true, assets = true,
}
M.KNOWN_SECTIONS = KNOWN_SECTIONS

-- A movement pattern: direction vectors, plus class words saying how they are
-- walked. The bare form is a list of pairs and means "these squares, one step",
-- which is much the commonest; the long form adds the class list.
--
--   "adjacent":   [[1,0],[0,1],[1,1]]
--   "line_ortho": { "vectors": [[1,0],[0,1]], "class": ["ray", "mirrored"] }
--
-- Class words: "step" (once, the default), "ray" (repeat until stopped),
-- "ray:n" (up to n times), "phasing" (nothing on the way stops it), "mirrored"
-- (negate each axis independently, so one vector stands for its whole family).
-- The coordinate pairs are the only nested arrays the schema allows outside a
-- per_seat "pos", and they are the same category: a list of coordinates.
--
-- "absolute" makes the pairs *squares* rather than directions — [1,1] is the
-- top-left cell, not "one across and one on". Nothing in the pair itself can
-- say which is meant, so the pattern says it: one label for the whole list,
-- rather than a marker repeated in every entry. It is a kind, not a modifier,
-- so walking words mean nothing beside it and the validator says so.
local function normalise_pattern(def)
	local vectors, class = def, nil
	if type(def) == "table" and def.vectors ~= nil then
		vectors, class = def.vectors, def.class
	end
	local p = { vectors = {}, range = 1, phasing = false, class = {},
		-- Absolute squares belong to a board, and there is nothing to anchor
		-- them on. Named here, or the only grid in the game.
		zone = type(def) == "table" and def.zone or nil }
	for _, w in ipairs(type(class) == "table" and class or {}) do
		local word, arg = tostring(w):match("^([%a_]+):?(%d*)$")
		p.class[word or tostring(w)] = true
		if word == "ray" then
			p.range = tonumber(arg) or math.huge
		elseif word == "step" then
			p.range = 1
		elseif word == "phasing" then
			p.phasing = true
		end
	end
	p.absolute = p.class.absolute or false
	local seen = {}
	local function add(dx, dy)
		-- A zero vector never leaves the square it started on; dropping it here
		-- keeps the walk from having to defend against a pattern that goes
		-- nowhere. Mirroring also generates duplicates ([1,0] mirrors onto
		-- itself twice), so the same guard dedupes. An absolute [0,0] is off the
		-- board rather than a non-move, and is dropped by the same line.
		if dx == 0 and dy == 0 then return end
		local k = dx .. "," .. dy
		if seen[k] then return end
		seen[k] = true
		p.vectors[#p.vectors + 1] = { dx, dy }
	end
	for _, v in ipairs(type(vectors) == "table" and vectors or {}) do
		local dx, dy = tonumber(type(v) == "table" and v[1]), tonumber(type(v) == "table" and v[2])
		if dx and dy then
			if p.class.mirrored then
				for _, sx in ipairs({ 1, -1 }) do
					for _, sy in ipairs({ 1, -1 }) do add(dx * sx, dy * sy) end
				end
			else
				add(dx, dy)
			end
		end
	end
	return p
end

-- How a piece may move: a list of rules, each naming patterns and saying what
-- may be standing on the square it lands on. A bare string is a rule of its
-- own, which is what lets a rook be ["line_ortho"] and only the pawn — whose
-- three rules differ in exactly that — pay for the long form.
local function normalise_moves(moves)
	local out = {}
	for _, rule in ipairs(type(moves) == "table" and moves or {}) do
		if type(rule) == "string" then
			out[#out + 1] = { patterns = { rule }, fill = "open" }
		elseif type(rule) == "table" then
			local names = rule.patterns
			out[#out + 1] = {
				patterns = type(names) == "table" and names or { names },
				fill     = rule.fill or "open",
				needs    = rule.needs,
			}
		end
	end
	return out
end

-- Parse a game file into a definition table without touching current state.
-- Structural problems (typo'd sections, duplicate or missing keys) are
-- collected in G.parse_problems for the validator to report — a broken entry
-- is skipped, never fatal.
-- Game files handed to us at runtime rather than read from disk. A networked
-- opponent can send the whole game along with the position, so somebody who has
-- never seen a file can be dealt into it — which is the difference between
-- "install this first" and "click here". Checked before the filesystem so a
-- shared game wins over a stale local copy of the same name.
M.provided = {}

function M.provide(filename, text)
	M.provided[filename] = text
end

function M.parse(filename)
	local data = M.provided[filename] or love.filesystem.read("games/" .. filename)
	assert(data, "Cannot read game file: " .. filename)
	local ok, parsed = pcall(json.decode, data)
	assert(ok, "Bad JSON in " .. filename .. ": " .. tostring(parsed))

	local G = {
		title          = parsed.title or "Ravel",
		seed           = parsed.seed,       -- optional: fixed RNG seed for the game
		placeholder_art = parsed.placeholder_art,  -- generate art for cards with no asset
		card_defs      = {},
		card_list      = {},       -- ordered array of card keys (file order, for deterministic setup)
		zone_defs      = {},
		zone_list      = {},       -- ordered array of zone keys (preserves JSON order)
		stat_defs      = {},
		stat_defs_list = {},       -- ordered array of stat keys (for HUD display)
		phase_list     = {},       -- ordered array of phase keys
		phase_by_key   = {},
		computed_tags  = parsed.computed_tags or {},
		end_conditions = parsed.end_conditions or {},
		setup          = parsed.setup or {},
		tag_defs       = {},       -- tag behaviour, moments flattened like a card's
		pattern_defs   = {},       -- named direction sets, for movement and neighbourhood
		asset_defs     = {},       -- named pictures: name -> { src, max }
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

	-- The normaliser drops anything malformed so the walk never has to defend
	-- itself; the raw shape is kept beside it so the validator can say *why* a
	-- piece it silently dropped cannot move.
	-- A tag def is a card mixin, so it is written in the same moments a card is
	-- and flattened by the same table. If the two vocabularies drifted, a zone's
	-- "applies" would hand its cards a shape nothing reads.
	for name, td in pairs(type(parsed.tags) == "table" and parsed.tags or {}) do
		if type(td) == "table" then flatten_moments(td, pp, "tag '" .. tostring(name) .. "'") end
		G.tag_defs[name] = td
	end

	G.raw_patterns = type(parsed.patterns) == "table" and parsed.patterns or {}
	for name, def in pairs(G.raw_patterns) do
		G.pattern_defs[name] = normalise_pattern(def)
	end

	-- Named pictures. A card's `asset` says what to draw and can spell a source
	-- out inline; naming one here instead is what buys options (`max`), and what
	-- lets twenty cards share one download and one texture, since the name is
	-- also the cache key. The bare form is a source on its own, because that is
	-- the common case and an object for it would be ceremony.
	G.raw_assets = type(parsed.assets) == "table" and parsed.assets or {}
	for name, def in pairs(G.raw_assets) do
		local src = type(def) == "table" and def.src or def
		if type(src) == "string" then
			G.asset_defs[name] = { src = src, max = tonumber(type(def) == "table" and def.max) }
		end
	end

	for _, cd in ipairs(entries(parsed.cards, "cards")) do
		if type(cd) ~= "table" or not cd.key then
			pp[#pp + 1] = "a card has no \"key\" — every card needs a unique one"
		else
			if G.card_defs[cd.key] then
				pp[#pp + 1] = "two cards share the key '" .. cd.key
					.. "' — the second silently replaces the first"
			else
				G.card_list[#G.card_list + 1] = cd.key
			end
			flatten_moments(cd, pp, "card '" .. cd.key .. "'")
			cd.tags_set = tag_set(cd.tags)
			-- A piece that says how it moves is asking for the ordinary board
			-- targeting, so the engine writes the spec rather than making every
			-- piece repeat the same four fields.
			if cd.moves then
				cd.move_rules = normalise_moves(cd.moves)
				if not cd.activate_target then
					cd.activate_target = { type = "slot", count = 1, moves = cd.move_rules }
				end
			end
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
			flatten_moments(zd, pp, "zone '" .. zd.key .. "'")
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

	-- The engine's own two cards live here, out of sight and out of reach of
	-- anything that sweeps a zone. A game may claim the key to put them
	-- somewhere else.
	if not G.zone_defs.system then
		G.zone_defs.system = { key = "system", type = "grid", grid = { 2, 1 },
			injected = true, pos = DEFAULT_POS.hidden,
			tags_set = { hidden = true } }
		G.zone_list[#G.zone_list + 1] = "system"
	end

	-- The player is a card. A game that wants a visible one tags it (castle's
	-- throne room) and gets stats, targeting, rendering and undo for free;
	-- otherwise the engine injects an invisible stat bag from setup.player, so
	-- games that never think about it change by zero bytes.
	local has_player = false
	for _, key in ipairs(G.card_list) do
		if G.card_defs[key].tags_set.player then has_player = true; break end
	end
	if not has_player then
		-- setup.player is untrusted content: coerce to numbers so later stat
		-- arithmetic can never be handed a string/table and crash.
		local stats = {}
		for k, v in pairs(type(G.setup.player) == "table" and G.setup.player or {}) do
			stats[k] = tonumber(v) or 0
		end
		-- The engine owns these two, wherever a game tried to put them: a
		-- second bearer of either would be counted twice and advanced once.
		stats.plays, stats.round = 0, nil
		G.card_defs.player = { key = "player", text = "You", injected = true,
			tags = { "player" }, tags_set = { player = true },
			card_stats = stats, auto_play = true, to_zone = "system" }
		table.insert(G.card_list, 1, "player")
	end

	-- The round belongs to the game, not to a player: two seats must not get
	-- two calendars, and a hero who dies must not take one with them.
	if not G.card_defs.system then
		G.card_defs.system = { key = "system", injected = true,
			tags = {}, tags_set = {},
			card_stats = { round = 1, turn = 0 }, auto_play = true, to_zone = "system" }
		table.insert(G.card_list, 1, "system")
	end

	-- Seats, in file order: every card carrying the "player" tag, named by its
	-- own key. Computed after the injection above so a game that declares none
	-- still has exactly one. One seat is the ordinary case and costs nothing —
	-- per_seat zones instance once and every owner word means the same cards.
	-- `owns` names the tag marking a seat's pieces on a board it shares with the
	-- other players. It used to be the seat's own key, which cost no field and
	-- one ambiguity: `@white` named the pieces while `card:white` named the seat
	-- card, so one word meant two sets. Declared on the seat rather than on every
	-- piece, because that is where the relationship lives, and it is two lines
	-- rather than thirty-two.
	G.seat_list, G.seat_set, G.seat_owns = {}, {}, {}
	for _, key in ipairs(G.card_list) do
		local cd = G.card_defs[key]
		if cd.tags_set.player then
			G.seat_list[#G.seat_list + 1] = key
			G.seat_set[key] = true
			G.seat_owns[key] = type(cd.owns) == "string" and cd.owns or nil
			-- A seat has to exist before it can act, and one that says nothing
			-- about where it sits is a stat bag — it goes where the injected
			-- one goes rather than onto a board it never asked for. Declaring
			-- a seat is then just tagging a card, which is the point.
			if cd.auto_play == nil then cd.auto_play = true end
			local homed = false
			for _, t in ipairs(type(cd.tags) == "table" and cd.tags or {}) do
				local td = G.tag_defs[t]
				if type(td) == "table" and td.zone then homed = true end
			end
			if not (cd.to_zone or homed) then cd.to_zone = "system" end
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
