local json = require("json")

local M = {}
M.G        = {}   -- current game definition; templates may be edited live (see cards.edit)
M.filename = nil  -- source file of the current game, for template reloads

-- Template-ish fields swapped wholesale by cards.reload. Zones and phases
-- are structural and need a full game load.
M.TEMPLATE_FIELDS = {
	"card_defs", "card_list", "computed_tags", "stat_defs", "stat_defs_list",
	"tag_defs", "effect_defs", "pattern_defs", "asset_defs", "raw_assets", "parse_problems",
	"style_defs", "dynamic_styles", "seat_index",
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
		action = "on_activate", moves = "moves" },
	challenge = { needs = "requires", pass = "on_pass", fail = "on_fail" },
	receive   = { needs = "accepts", action = "on_receive" },
	turn      = { action = "on_turn" },
}
M.MOMENTS = MOMENTS

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
				where    = rule.where,
			}
		end
	end
	return out
end

local ABILITY_FIELDS = { key = true, text = true, tooltip = true, asset = true,
	cost = true, target = true, phases = true, action = true, moves = true }

-- Every activated ability a card has, as one list, whether it wrote one
-- (`activate`) or several (`abilities`). Downstream never asks which form was
-- used — the shorthand is the list with one entry in it, and a chooser never
-- appears for a card that has one thing to do.
--
-- The entries keep the authored words: cost, target, phases, action, moves.
-- `text` is what a chooser shows, and only a card with more than one ability
-- has anything to choose between, so only that card has to write it.
local function abilities_of(def, pp, where)
	local out = {}
	if type(def.abilities) == "table" and #def.abilities > 0 then
		if def.on_activate or def.activate_cost or def.activate_target then
			pp[#pp + 1] = where .. ": has both an 'activate' block and an 'abilities' list"
				.. " — one card, one way of saying what it can do"
		end
		for i, a in ipairs(def.abilities) do
			if type(a) ~= "table" then
				pp[#pp + 1] = where .. ": ability " .. i .. " should be an object"
			else
				-- Checked here rather than in the validator, because this is
				-- the last place the *authored* entry exists: what leaves this
				-- function is the normalised one, and a typo has been dropped
				-- from it by then. Same reason flatten_moments checks names.
				for k in pairs(a) do
					if not ABILITY_FIELDS[k] then
						pp[#pp + 1] = ("%s ability %d: has a field '%s' the engine doesn't read")
							:format(where, i, tostring(k))
					end
				end
				-- An ability that says how it moves is asking for the ordinary
				-- board targeting, exactly as a card with one does: the engine
				-- writes the spec rather than making every ability repeat it.
				local rules  = a.moves and normalise_moves(a.moves) or nil
				local target = a.target
				if rules and not target then
					target = { type = "slot", count = 1, moves = rules }
				end
				out[#out + 1] = { key = a.key or ("ability_" .. i), text = a.text,
					tooltip = a.tooltip, asset = a.asset,
					cost = a.cost, target = target, phases = a.phases,
					action = a.action, moves = rules }
			end
		end
	elseif def.on_activate then
		out[1] = { key = "activate", text = def.text, cost = def.activate_cost,
			target = def.activate_target, phases = def.activate_phases,
			action = def.on_activate, moves = def.move_rules }
	end
	return out
end

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
			-- Presence is the flag: a card with a "start" block starts in play,
			-- so auto_play stops being a boolean somebody can forget beside it.
			if moment == "start" then def.auto_play = true end
		end
	end
end

-- Every style a tag set names, merged into one flat table. Two styles claiming
-- one property is an authoring conflict the validator reports, so nothing here
-- has to invent a winner.
local function merge_styles(G, tags_set)
	local out = {}
	for tag in pairs(tags_set or {}) do
		local sd = G.style_defs[tag]
		if type(sd) == "table" then
			for k, v in pairs(sd) do out[k] = v end
		end
	end
	return out
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
	end_conditions = true, setup = true, tags = true, effects = true, players = true,
	patterns = true, assets = true, styles = true,
}
M.KNOWN_SECTIONS = KNOWN_SECTIONS

-- A movement pattern: direction vectors, plus class words saying how they are
-- walked. The bare form is a list of pairs and means "these squares, one step",
-- which is much the commonest; the long form adds the class list.
--
--   "adjacent":   [[1,0],[-1,0],[0,1],[0,-1]]
--   "line_ortho": { "vectors": [[1,0],[-1,0],[0,1],[0,-1]], "class": ["ray"] }
--
-- Class words: "step" (once, the default), "ray" (repeat until stopped),
-- "ray:n" (up to n times), "phasing" (nothing on the way stops it). Every
-- direction is written out: a "mirrored" word used to negate each axis and let
-- one vector stand for its family, and it went because four saved pairs are
-- not worth a reader working out which eight directions [1,2] meant — nor the
-- bug it hid, where mirroring a zero produced "-0" and dodged the dedupe, so
-- a rook walked eight rays down four lines.
--
-- **y is a rank: [0,1] is one square forward, up the board.** The grid draws
-- its rows top-down, which is geometry's business and nobody else's.
-- The coordinate pairs are the only nested arrays the schema allows outside a
-- per_seat "pos", and they are the same category: a list of coordinates.
--
-- "absolute" makes the entries *squares* rather than directions, and then they
-- are written the way a player says them — "e1", not a pair. Nothing in the pair itself can
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
		-- nowhere, and the same guard drops a direction written twice.
		if dx == 0 and dy == 0 then return end
		local k = dx .. "," .. dy
		if seen[k] then return end
		seen[k] = true
		p.vectors[#p.vectors + 1] = { dx, dy }
	end
	for _, v in ipairs(type(vectors) == "table" and vectors or {}) do
		if p.absolute then
			-- A square is a name and stays one. Which cell it is depends on the
			-- board, and the board is not known here — geometry resolves it,
			-- which is the only place a rank becomes a row.
			if type(v) == "string" then p.vectors[#p.vectors + 1] = v end
		else
			local dx, dy = tonumber(type(v) == "table" and v[1]), tonumber(type(v) == "table" and v[2])
			if dx and dy then add(dx, dy) end
		end
	end
	return p
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
		card_defs      = {},
		card_list      = {},       -- ordered array of card keys (file order, for deterministic setup)
		zone_defs      = {},
		zone_list      = {},       -- ordered array of zone keys (preserves JSON order)
		stat_defs      = {},
		stat_defs_list = {},       -- ordered array of stat keys (for HUD display)
		phase_list     = {},       -- ordered array of phase keys
		phase_by_key   = {},
		computed_tags  = parsed.computed_tags or {},
		-- A style is a named bundle of presentation properties, claimed by
		-- tagging it. "This card is crimson" becomes a word instead of three
		-- numbers repeated on fourteen cards, and the word can be a computed
		-- tag, which is conditional rendering with nothing in render.lua that
		-- knows what wounded means.
		style_defs     = type(parsed.styles) == "table" and parsed.styles or {},
		dynamic_styles = {},   -- style names that are also computed tags
		end_conditions = parsed.end_conditions or {},
		setup          = parsed.setup or {},
		-- Where the game begins, in the order the manual would say it. A card
		-- does not declare its own place: the list of cards is what comes out of
		-- the box, and this is the setup section that arranges them. Repeats are
		-- the point — eight pawns are eight entries naming one kind.
		setup_place    = {},
		players        = type(parsed.players) == "table" and parsed.players or {},
		player_list    = {},   -- seats, in declared order: { card = key, owns = tag }
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
		if type(td) == "table" then
			flatten_moments(td, pp, "tag '" .. tostring(name) .. "'")
			-- A granted ability is an ability: same shape, so a card that has
			-- one of its own and is handed another simply has two.
			td.abilities = abilities_of(td, pp, "tag '" .. tostring(name) .. "'")
		end
		G.tag_defs[name] = td
	end

	-- Only a style word that is *also* a computed tag can change under a running
	-- game; every other look is settled at load. So a game with none pays
	-- nothing per frame, which is every shipped game today.
	for name in pairs(G.style_defs) do
		if G.computed_tags[name] then G.dynamic_styles[#G.dynamic_styles + 1] = name end
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
		-- A string, or one per seat: the same named picture drawn differently
		-- depending on whose card wears it. Kept as given, because which one is
		-- wanted is not known until a card asks.
		if type(src) == "string" or (type(src) == "table" and #src > 0) then
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
			cd.style = merge_styles(G, cd.tags_set)
			-- A piece that says how it moves is asking for the ordinary board
			-- targeting, so the engine writes the spec rather than making every
			-- piece repeat the same four fields.
			if cd.moves then
				cd.move_rules = normalise_moves(cd.moves)
				if not cd.activate_target then
					cd.activate_target = { type = "slot", count = 1, moves = cd.move_rules }
				end
			end
			cd.abilities = abilities_of(cd, pp, "card '" .. cd.key .. "'")
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
			zd.style = merge_styles(G, zd.tags_set)
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
			sd.tags_set = tag_set(sd.tags)
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
			pd.tags_set = tag_set(pd.tags)
			-- draw_and_play is shorthand: play once, discard the rest, advance.
			if pd.type == "draw_and_play" then
				if pd.ends_after == nil then pd.ends_after = 1 end
				-- It discards by default; `keep_hand` opts out, because a tag is
				-- carried or it is not and there is no "false" to write.
				if not pd.tags_set.keep_hand then pd.tags_set.discard_hand = true end
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

	-- The engine places its own first: the system card, an injected player, and
	-- any seat that named no place. Those are plumbing rather than setup — a
	-- seat has to exist before it can act — so a game never writes them down.
	-- Everything else is an entry an author put in "setup".
	for _, e in ipairs(type(G.setup.place) == "table" and G.setup.place or {}) do
		if type(e) == "table" and type(e.card) == "string" then
			-- One square or several: eight pawns are one entry naming eight
			-- squares, which is how the placement list reads like the diagram
			-- in a rulebook rather than like a table of cell numbers.
			local at = e.at
			if type(at) == "string" then at = { at } end
			G.setup_place[#G.setup_place + 1] = { card = e.card, zone = e.zone,
				at = type(at) == "table" and at or nil,
				owner = type(e.owner) == "string" and e.owner or nil }
		elseif type(e) == "string" then
			G.setup_place[#G.setup_place + 1] = { card = e }
		else
			pp[#pp + 1] = 'a "setup.place" entry should name a card, like { "card": "throne", "zone": "board", "at": "c3" }'
		end
	end

	-- Who is playing, declared rather than inferred. A seat used to be any card
	-- carrying the "player" tag, which meant the answer to "is this a two-player
	-- game" was a scan — and a game that wanted an invite card had to know its
	-- own seat count without ever stating it. The list says it, in seat order.
	--
	-- A seat is still a card: it has stats, it can be looked at, targeted,
	-- damaged and destroyed, and castle's throne room is a building on the board
	-- that happens to be the player. An entry naming one adopts it; an entry
	-- naming none gets an invisible stat bag injected, which is what a solitaire
	-- game has always had without writing it down.
	local players = type(parsed.players) == "table" and parsed.players or nil
	if players and #players == 0 then
		pp[#pp + 1] = 'the "players" section is empty — a game needs at least one seat'
		players = nil
	end
	-- Saying nothing means one seat, exactly as before this section existed.
	players = players or { {} }
	local injected = 0
	for i, entry in ipairs(players) do
		if type(entry) ~= "table" then
			pp[#pp + 1] = 'a "players" entry should be an object, like { "card": "north" }'
		else
			local key = entry.card
			if key == nil or G.card_defs[key] == nil then
				-- No card of that name, so the engine makes one. Its stats are
				-- untrusted content: coerce to numbers, or later arithmetic can
				-- be handed a string and crash.
				injected = injected + 1
				key = key or (injected == 1 and "player" or ("player_" .. injected))
				local stats = {}
				for k, v in pairs(type(entry.stats) == "table" and entry.stats or {}) do
					stats[k] = tonumber(v) or 0
				end
				-- The engine owns these two, wherever a game tried to put them: a
				-- second bearer of either would be counted twice and advanced once.
				stats.plays, stats.round = 0, nil
				G.card_defs[key] = { key = key, text = entry.text or "You", injected = true,
					tags = {}, tags_set = {}, style = {},
					card_stats = stats, auto_play = true, to_zone = "system" }
				table.insert(G.card_list, i, key)
			elseif entry.stats ~= nil then
				pp[#pp + 1] = "player '" .. tostring(key) .. "' names a card, so its starting "
					.. 'numbers belong in that card\'s "card_stats" rather than in "stats"'
			end
			G.player_list[#G.player_list + 1] = { card = key, owns = entry.owns }
		end
	end

	-- Seats, in declared order. The "player" tag is stamped rather than read:
	-- twenty-seven conditions across the shipped games scope by @mine.player, so
	-- the word stays the way you name a seat's cards — it just stops being how
	-- the engine finds out who the seats are.
	--
	-- Seats in declared order, and the index of each. The index is what a piece
	-- carries: ownership is decided where a piece is placed, so it is written on
	-- the piece as an ordinary stat rather than inferred from a tag it wears.
	G.seat_list, G.seat_set, G.seat_index = {}, {}, {}
	for _, seat in ipairs(G.player_list) do
		local cd = G.card_defs[seat.card]
		if cd then
			G.seat_list[#G.seat_list + 1] = seat.card
			G.seat_set[seat.card] = true
			G.seat_index[seat.card] = #G.seat_list
			cd.tags_set = cd.tags_set or {}
			if not cd.tags_set.player then
				cd.tags_set.player = true
				cd.tags = cd.tags or {}
				cd.tags[#cd.tags + 1] = "player"
			end
			-- Any seat can be the one that won, so the engine puts the stat on all
			-- of them rather than making every game declare it. It has to exist
			-- before it can be written: gain_stat only reaches a card that already
			-- carries the stat, so a game missing the line would name its winner
			-- and change nothing at all.
			cd.card_stats = cd.card_stats or {}
			if cd.card_stats.won ~= nil then
				pp[#pp + 1] = ("card '%s' is a seat and declares \"won\", which the engine keeps for who"
					.. " has won — it starts at 0 whatever the card says"):format(tostring(seat.card))
			end
			cd.card_stats.won = 0
			-- A seat has to exist before it can act, and one that says nothing
			-- about where it sits is a stat bag — it goes where the injected one
			-- goes rather than onto a board it never asked for.
			if cd.auto_play == nil then cd.auto_play = true end
			local homed = false
			for _, tg in ipairs(type(cd.tags) == "table" and cd.tags or {}) do
				local td = G.tag_defs[tg]
				if type(td) == "table" and td.zone then homed = true end
			end
			if not (cd.to_zone or homed) then cd.to_zone = "system" end
		else
			pp[#pp + 1] = "player " .. tostring(#G.seat_list + 1) .. " names the card '"
				.. tostring(seat.card) .. "', but no card has that key"
		end
	end

	-- The round belongs to the game, not to a player: two seats must not get
	-- two calendars, and a hero who dies must not take one with them.
	if not G.card_defs.system then
		G.card_defs.system = { key = "system", injected = true,
			tags = {}, tags_set = {}, style = {},
			card_stats = { round = 1, turn = 0 }, auto_play = true, to_zone = "system" }
		table.insert(G.card_list, 1, "system")
	end

	-- The engine's own placements go in front, in card_list order: the system
	-- card, an injected seat, a declared seat that named no place. None of these
	-- is written down by a game — a seat has to exist before it can act — and
	-- the order is load-bearing, since entity IDs are handed out as cards are
	-- created and a seed only replays a board built the same way twice.
	do
		local named = {}
		for _, e in ipairs(G.setup_place) do named[e.card] = true end
		local own = {}
		for _, key in ipairs(G.card_list) do
			local cd = G.card_defs[key]
			if not named[key] and (cd.injected or G.seat_set[key]) then
				own[#own + 1] = { card = key, engine = true }
			end
		end
		for i = #own, 1, -1 do table.insert(G.setup_place, 1, own[i]) end
	end

	-- Built-in "turn the page": the reveal actions conjure cards into this
	-- hidden zone and push this overlay. A game may claim either key to
	-- override the presentation.
	-- The engine writes "last_acted" onto whichever card a player touched last,
	-- so it hands games the word for reading it back rather than making each one
	-- declare the same computed tag.
	-- The engine's meaning is the one that survives, and a game silently losing
	-- its own definition is worse than being told: the injected flag below is what
	-- makes the validator skip its redefinition warning, so without this nothing
	-- anywhere would mention the collision.
	if G.computed_tags.last_acted then
		pp[#pp + 1] = "computed_tags: 'last_acted' is the engine's own word for the card a player"
			.. " just touched, and the engine's meaning is the one that survives — pick another name"
	end
	G.computed_tags.last_acted = { stat = "last_acted", at_least = 1, injected = true }

	-- A card with more than one ability needs something to *show* for each, and
	-- the offer deals cards. So the engine writes one per ability: a menu entry,
	-- never dealt or played by a game, carrying the ability's own words and a
	-- shape generated from its name. It is not a card the game has to invent,
	-- because it is not a card the game means.
	--
	-- One per ability wherever an ability is *declared*, which means tags as much
	-- as cards: a zone's "applies" hands its cards an ability, so a rook lying in
	-- a discard pile has two — its move and the pile's "take me". Minting only for
	-- cards, and only for cards already declaring two of their own, left that
	-- second entry with no card to deal and the chooser asked for a card called
	-- nil. Minting for every ability costs a def nobody deals and removes the
	-- coupling entirely.
	local function mint(owner_key, list, what)
		for _, a in ipairs(list or {}) do
			local mk = owner_key .. "#" .. a.key
			if G.card_defs[mk] then
				pp[#pp + 1] = ("%s '%s' has two abilities called '%s' — the chooser deals one entry per"
					.. " ability and could not tell them apart"):format(what, tostring(owner_key), tostring(a.key))
			end
			a.menu_card = mk
			G.card_defs[mk] = { key = mk, injected = true, menu_for = { card = owner_key },
				text = a.text or a.key, tooltip = a.tooltip or a.text,
				-- A picture the ability named, or a shape from its name. A named
				-- asset resolves per player like any other, so a chooser wears
				-- the colours of whoever opened it.
				asset = a.asset or "auto", tags = {}, tags_set = { token = true },
				abilities = {}, style = merge_styles(G, { token = true }) }
		end
	end
	for _, key in ipairs(G.card_list) do mint(key, G.card_defs[key].abilities, "card") end
	for key, td in pairs(G.tag_defs) do mint(key, td.abilities, "tag") end

	-- An "options" zone is hidden by its own type rather than by a tag it has to
	-- remember: an offer that is not open is not on the board, and forgetting to
	-- say so is how a zone ends up invisible and still clickable.
	for _, zd in pairs(G.zone_defs) do
		if zd.type == "options" then
			zd.tags_set = zd.tags_set or {}
			zd.tags_set.hidden = true
		end
	end

	-- The offer, and the phase that shows it — the same pair "reveal" gets, and
	-- for the same reason: a game that never mentions either still has one, and
	-- a game that wants it drawn somewhere else claims the key.
	if not G.zone_defs.options then
		G.zone_defs.options = { key = "options", type = "options", injected = true,
			pos = { 0.12, 0.38, 0.88, 0.62 },
			tags_set = { hidden = true } }
		G.zone_list[#G.zone_list + 1] = "options"
	end
	if not G.phase_by_key.options then
		G.phase_by_key.options = { key = "options", type = "overlay", zone = "options",
			injected = true, tags_set = {} }
	end

	if not G.zone_defs.reveal then
		G.zone_defs.reveal = { key = "reveal", type = "hand", injected = true,
			pos = { 0.22, 0.14, 0.78, 0.88 },
			tags_set = { hidden = true, page = true, no_peek = true } }
		G.zone_list[#G.zone_list + 1] = "reveal"
	end
	if not G.phase_by_key.reveal then
		G.phase_by_key.reveal = { key = "reveal", type = "overlay", zone = "reveal",
			injected = true, tags_set = {} }
	end

	return G
end

function M.load(filename)
	M.G        = M.parse(filename)
	M.filename = filename
	return M.G
end

return M
