-- **What a game file is made of, by type.** The one place the engine checks that
-- a field holding a number holds a number, and the reason nothing past this point
-- has to.
--
-- A game file is untrusted content (invariant 5), and it used to reach the engine
-- whole: every reader of a field was its own guard, and a reader that forgot was
-- a crash — a cost written as a string, a zone's "applies" written as one word
-- rather than a list. The validator often knew and said so, and the game crashed
-- anyway, because a warning does not stop anything.
--
-- So the file passes through here before `declaration.parse` sees it. Each value
-- is held to the type its field takes; one that is wrong is reported and left
-- out, exactly as if the author had not written it. What comes out is a copy of
-- the file with every known field the right type — not necessarily sensible,
-- which is the validator's question, but never a string where a number goes.
--
-- A field this table does not know is copied as it stands. Nothing reads it, and
-- the validator is what names it as a typo.

local M = {}

-- Constructors. A spec is a table saying what a value must be; `like` is an
-- example for the message, where the type alone would not say enough.
local STR  = { t = "string", what = "a word" }
local NUM  = { t = "number", what = "a number" }
local BOOL = { t = "boolean", what = "true or false" }
local ANY  = { t = "any" }

-- A list of `of`, with `n` the exact length or `{ lo, hi }` its bounds. A bad
-- entry is dropped and the rest are kept: one typo in a deck is one card fewer.
local function list(of, n, like)
	return { t = "list", of = of, n = n, like = like }
end

-- String keys of the game's own choosing, each holding `of`.
local function map(of, like)
	return { t = "map", of = of, like = like }
end

-- Named fields, each with its own spec.
local function rec(fields, like)
	return { t = "rec", fields = fields, like = like }
end

-- Any one of several shapes, tried in order.
local function either(...)
	return { t = "either", ... }
end

local STRS    = list(STR)
local ACTIONS = list(STR)
ACTIONS.what  = 'a list of actions like ["stat_gain:gold:1"]'
-- One condition, or a list that must all hold.
local COND    = either(STR, list(STR))
local WORDS   = either(STR, list(STR))
local RECT    = list(NUM, 4, "[0.1, 0.1, 0.4, 0.3]")
local COLOUR  = list(NUM, { 3, 4 }, "[0.8, 0.2, 0.2]")
-- A cost's values are amounts: a number, or an expression the amount reader parses.
local COST    = map(either(NUM, STR), '{ "gold": 2 }')

local MOVE_RULE = rec({ patterns = WORDS, fill = STR, needs = COND, where = COND })
local MOVES     = list(either(STR, MOVE_RULE))

local TARGET = rec({
	type = STR, min = NUM, max = NUM, count = NUM, spread = NUM,
	tags = STRS, zones = STRS, owner = STR, fill = STR,
	moves = MOVES, where = COND, verb = STR,
}, '{ "type": "card", "count": 1 }')

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
-- Here rather than in declaration.lua because each word's type is read off it
-- below: a moment gaining a field is one edit, and cannot arrive unchecked.
M.MOMENTS = {
	play      = { cost = "cost", needs = "needs", target = "target", phases = "phases",
		action = "on_play", spent = "spent", compute = "compute" },
	challenge = { needs = "requires", pass = "on_pass", fail = "on_fail" },
	-- Three gates and a side. "needs" is whether the aim may be made at all,
	-- asked of every candidate before a player may point; "when" is whether the
	-- card answers the aim that was. An Illusion is targetable by everything and
	-- dies only to some of it, so one list could not have said both.
	--
	-- "whose" is the side, in a reaction's own word, and it gates the whole block
	-- rather than either half: Codex writes Invisible as "to *opponents* without a
	-- detector" and Mindparry as "*opponents* can't aim spells at your units", so
	-- the one-sidedness is a property of the ward and not a clause inside it.
	-- Written as a condition it would be repeated in every one-sided ward and got
	-- wrong once. Default "anyone", since Untargetable, Illusion and every zone's
	-- accepts are about the aim and not about who made it.
	receive   = { needs = "accepts", when = "on_receive_needs", action = "on_receive",
		whose = "receive_whose" },
	-- The arrival counterpart to a card's "leaves", on the zone that receives.
	-- Separate from "receive" and not a field on it: "receive" fires on every
	-- landing in any zone -- which is what a discard stamping its owner wants
	-- -- and this fires only when a card comes *into play*, which is what an
	-- arrival trigger means. One word each rather than a mode on one word.
	arrives   = { needs = "arrives_needs", action = "on_arrives" },
	round     = { action = "on_round" },
	chosen    = { where = "chosen_where", action = "on_chosen" },
	-- A card on its way out, which is the moment a card game keeps most of its
	-- triggers at and the engine had no word for. `into` is the zone it landed
	-- in, and naming one is how death, exile and bounce are told apart without
	-- the engine learning what any of them means: they are one sentence pointed
	-- at three different places.
	--
	-- `from` is which departure is meant. Left out it is leaving *play*, which
	-- is what a card that dies does; naming a zone makes it leaving that zone,
	-- which is what a card discarded out of a hand does. Both are "leaves", and
	-- a game with no board at all -- a whole hand of them -- had no way to say
	-- the second until this existed, so it wrote the trigger as an ability and
	-- then had to keep every other rule from running it.
	--
	-- `needs` is the same word every other block carries, and it is here for the
	-- same reason: a departure a rule cares about is often only *some* of them.
	-- "Dies on your turn" and "dies on anybody else's" are one moment with a
	-- condition on it, and without this the only gate a leaving card had was
	-- arithmetic — an amount that comes to zero, which says nothing about a rule
	-- that chooses or moves.
	leaves    = { from = "leaves_from", into = "leaves_into", needs = "leaves_needs",
		action = "on_leaves" },
}

-- What each authored word inside a moment holds.
local IN_MOMENT = {
	cost = COST, needs = COND, target = TARGET, phases = WORDS, action = ACTIONS,
	spent = STR, compute = STRS, pass = ACTIONS, fail = ACTIONS, when = COND,
	whose = STR, where = COND, from = STR, into = STR,
}

local ABILITY = rec({
	key = STR, text = STR, tooltip = STR, asset = STR, cost = COST, target = TARGET,
	phases = WORDS, action = ACTIONS, moves = MOVES, needs = COND, compute = STRS, merge = STR,
})

local REACTION = rec({
	key = STR, text = STR, tooltip = STR, to = STR, where = COND, needs = COND,
	forced = STR, ["in"] = STR, whose = STR, cost = COST, target = TARGET,
	action = ACTIONS, moves = MOVES, compute = STRS, spent = STR,
})

-- The moment a card or a phase announces, and the verb or verbs it says.
local EMITS = map(WORDS, '{ "play": "cast" }')

local STAT_VALUE = either(NUM, rec({ value = NUM, min = NUM, max = NUM }, '{ "value": 4, "max": 4 }'))

-- The fields a card, a tag and a zone share: every moment block, and every flat
-- name a block becomes. The flat names are not authored, but a file may write one
-- anyway and the parser only reports it — so it is held to the same type as the
-- word it stands for, or it would reach the engine unchecked.
local function with_moments(fields)
	for moment, words in pairs(M.MOMENTS) do
		local block = {}
		for authored, internal in pairs(words) do
			block[authored] = IN_MOMENT[authored]
			fields[internal] = IN_MOMENT[authored]
		end
		fields[moment] = rec(block)
	end
	fields.abilities = list(ABILITY)
	fields.emits = EMITS
	return fields
end

local CARD = rec(with_moments({
	key = STR, text = STR, name = STR, tooltip = STR, story = STR, asset = STR,
	tags = STRS, card_stats = map(STAT_VALUE, '{ "hp": 3 }'), outcome = STR, grave = STR,
	reactions = list(REACTION),
}))

local ADJUST = rec({ key = STR, verb = STR, stat = STR, covers = STR, needs = COND,
	by = either(NUM, STR), instead = ACTIONS })

local TAG = rec(with_moments({
	zone = STR, grave = STR, tooltip = STR,
	buffs = map(NUM, '{ "atk": 1 }'), adjusts = list(ADJUST),
}))

local ZONE = rec(with_moments({
	key = STR, label = STR, tooltip = STR, asset = STR, grave = STR, refill_from = STR,
	-- A rectangle, a rectangle per seat, or the key of the zone whose rect it shares.
	pos = either(RECT, list(RECT, { 1, math.huge }), STR),
	layout = STR, visibility = STR, reach = STR, use = STR, status = STR, display = STR, copies = STR,
	grid = list(NUM, 2, "[8, 8]"), row = STR,
	contents = STRS, tags = STRS, applies = STRS,
}))

local ROUTE = rec({ when = COND, ["then"] = STR, ends_round = BOOL, seat = STR })

local PHASE = rec({
	key = STR, label = STR, type = STR, actions = ACTIONS, on_enter = ACTIONS,
	deck = STR, draw = NUM, zone = WORDS, pass_card = WORDS, next = list(ROUTE),
	ends_when = COND, tags = STRS, seat = STR, emits = EMITS, phases = STRS, order = STR,
})

local STAT = rec({
	key = STR, label = STR, min = NUM, max = NUM, subject = STR, tags = STRS,
	icon = STR, color = either(STR, COLOUR), on = STRS, start = NUM, pays_for = STRS,
	buffs = map(NUM), number = BOOL, display = STR,
})

-- Directions as [dx, dy] pairs, or squares by name in an absolute pattern.
local VECTORS = list(either(list(NUM, 2, "[1, 0]"), STR))

local FILE = rec({
	title = STR, seed = NUM, include = STRS, replaces = STRS,
	cards = list(CARD), zones = list(ZONE), phases = list(PHASE), stats = list(STAT),
	tags = map(TAG),
	computes = list(rec({ key = STR, value = either(STR, NUM), tooltip = STR })),
	computed_tags = map(rec({ needs = COND, any_of = STRS })),
	verbs = list(rec({ key = STR, does = STR, action = ACTIONS, tooltip = STR, effect = STR })),
	effects = map(rec({ base = STR, size = NUM, speed = NUM, count = NUM, color = COLOUR })),
	end_conditions = list(rec({ when = COND, ["then"] = ACTIONS })),
	setup = rec({
		place = list(either(STR, rec({ card = STR, zone = STR, at = WORDS, owner = STR }))),
	}),
	players = list(rec({ card = STR, text = STR, owns = STR, stats = map(NUM) })),
	patterns = map(either(VECTORS, rec({ vectors = VECTORS, class = STRS, zone = STR }))),
	assets = map(either(STR, list(STR), rec({
		src = WORDS, max = NUM,
		-- One entry per seat, each a source or a list of them.
		per_player = list(WORDS),
	}))),
	styles = map(rec({
		color = COLOUR, hide = STRS, fit = STR, ratio = either(NUM, STR),
		chequer = list(STR, 2, '["#f0d9b5", "#b58863"]'), paint = map(STR), fan = STR,
		badges = STRS, badge_run = STR,
	})),
	prompt = rec({ pos = RECT }),
})

-- Names the parser writes onto a def. A file writing one would have it read as
-- the engine's own, so it goes, whatever it holds.
local ENGINE_WRITES = { tags_set = true, style = true, injected = true, zone_list = true,
	move_rules = true, auto_play = true, to_slot = true, menu_card = true }

local function kind(v)
	local t = type(v)
	if t ~= "table" then return t end
	if next(v) == nil then return "empty" end
	local n = 0
	for _ in pairs(v) do n = n + 1 end
	return n == #v and "list" or "object"
end

local FITS = {
	string = { string = true }, number = { number = true }, boolean = { boolean = true },
	list = { list = true, empty = true }, map = { object = true, empty = true },
	rec = { object = true, empty = true },
}

local function fits(v, spec)
	if spec.t == "any" then return true end
	if spec.t == "either" then
		for _, s in ipairs(spec) do
			if fits(v, s) then return true end
		end
		return false
	end
	return FITS[spec.t][kind(v)] == true
end

local function describe(spec)
	if spec.t == "list" and spec.what then return spec.what end
	if spec.like then return "written like " .. spec.like end
	if spec.t == "list" then
		local n = type(spec.n) == "number" and (spec.n .. " ") or ""
		return "a list of " .. n .. (spec.of.what and spec.of.what:gsub("^an? ", "") .. "s" or "entries")
	end
	if spec.t == "map" or spec.t == "rec" then return "an object, { ... }" end
	if spec.t == "either" then
		local out = {}
		for i, s in ipairs(spec) do out[i] = describe(s) end
		return table.concat(out, ", or ")
	end
	return spec.what
end

local function shown(v)
	local k = kind(v)
	if k == "string" then return '"' .. v .. '"' end
	if k == "number" or k == "boolean" then return tostring(v) end
	return k == "list" and "a list" or k == "empty" and "an empty list" or "an object"
end

local clean

local function refuse(v, spec, where, pp)
	pp[#pp + 1] = ("%s should be %s, not %s — left out"):format(where, describe(spec), shown(v))
end

-- Held to `spec`. Returns the clean copy, or nil when the value cannot be one.
clean = function(v, spec, where, pp)
	if spec.t == "any" then return v end
	if spec.t == "either" then
		-- The first shape that takes the value without complaint wins; failing
		-- that, the first it fits at all, so the message is about the likeliest one.
		local first
		for _, s in ipairs(spec) do
			if fits(v, s) then
				local mine = {}
				local out = clean(v, s, where, mine)
				if #mine == 0 then return out end
				first = first or { out = out, said = mine }
			end
		end
		if not first then return refuse(v, spec, where, pp) end
		for _, p in ipairs(first.said) do pp[#pp + 1] = p end
		return first.out
	end
	if not fits(v, spec) then return refuse(v, spec, where, pp) end
	if type(v) ~= "table" then return v end
	if spec.t == "list" then
		local lo, hi = spec.n, spec.n
		if type(spec.n) == "table" then lo, hi = spec.n[1], spec.n[2] end
		if lo and (#v < lo or #v > hi) then return refuse(v, spec, where, pp) end
		local out = {}
		for i, x in ipairs(v) do
			local c = clean(x, spec.of, where .. " entry " .. i, pp)
			if c ~= nil then out[#out + 1] = c end
		end
		-- A fixed length is part of the type: a rectangle missing a corner is not one.
		if lo and #out < lo then return nil end
		return out
	end
	local out = {}
	for k, x in pairs(v) do
		local sub = spec.t == "map" and spec.of or spec.fields[k]
		local at = where .. " " .. tostring(k)
		if ENGINE_WRITES[k] and spec.t == "rec" then
			pp[#pp + 1] = ("%s is worked out by the engine and never written — left out"):format(at)
		elseif sub then
			out[k] = clean(x, sub, at, pp)
		else
			out[k] = x
		end
	end
	return out
end

-- **Anything the engine writes onto a game file wears "ravel_".** The two it
-- writes are ravel_fired (which end condition has gone off) and ravel_menu_for
-- (the card standing in for one ability in a chooser), and a file that says
-- either is refused rather than quietly overwritten.
--
-- Said as a prefix and not as a list, so the rule is one a reader can apply
-- without looking anything up: a word starting with ravel_ is the engine's,
-- everywhere and in every section. Removed as well as reported, because the
-- engine reads both and would believe whatever the file said.
local function refuse_reserved(node, at, depth, pp)
	if type(node) ~= "table" or depth > 12 then return end
	for k, v in pairs(node) do
		if type(k) == "string" and k:sub(1, 6) == "ravel_" then
			pp[#pp + 1] = ("%s writes '%s', which is the engine's to write: every field"):format(at, k)
				.. " starting with \"ravel_\" is bookkeeping, and a game file says none of them"
			node[k] = nil
		else
			refuse_reserved(v, type(k) == "string" and (at .. " " .. k) or at, depth + 1, pp)
		end
	end
end

-- What an entry is called in a message: by its key where it has one, and by its
-- place in the list where it has not.
local LISTED = { cards = "card", zones = "zone", phases = "phase", stats = "stat",
	computes = "compute", verbs = "verb", end_conditions = "end condition", players = "player" }
local NAMED  = { tags = "tag", patterns = "pattern", assets = "asset", styles = "style",
	effects = "effect", computed_tags = "computed tag" }

-- The whole file, held to its shape. Returns the clean copy and adds a line to
-- `pp` for everything left out. The file handed in is not changed.
function M.clean(file, pp)
	local out = {}
	if kind(file) ~= "object" and kind(file) ~= "empty" then
		pp[#pp + 1] = "the file should be an object, { ... }, holding the game's sections"
		return out
	end
	for section, v in pairs(file) do
		local spec = FILE.fields[section]
		if not spec then
			out[section] = v
		elseif (LISTED[section] or NAMED[section]) and not fits(v, spec) then
			pp[#pp + 1] = LISTED[section]
				and ("the '%s' section should be a list — wrap its entries in [ ... ]"):format(section)
				or ("the '%s' section should be an object, { ... }, keyed by name"):format(section)
		elseif LISTED[section] then
			local entries = {}
			for i, e in ipairs(v) do
				local key = type(e) == "table" and type(e.key) == "string" and e.key
				local where = key and (LISTED[section] .. " '" .. key .. "'") or (section .. " entry " .. i)
				local c = clean(e, spec.of, where, pp)
				if c ~= nil then entries[#entries + 1] = c end
			end
			out[section] = entries
		elseif NAMED[section] then
			local entries = {}
			for name, e in pairs(v) do
				entries[name] = clean(e, spec.of, NAMED[section] .. " '" .. tostring(name) .. "'", pp)
			end
			out[section] = entries
		else
			out[section] = clean(v, spec, section, pp)
		end
	end
	refuse_reserved(out, "this file", 0, pp)
	return out
end

-- Every named shape, under the name the validator's field tables use, so a test
-- can hold the two together: a field the validator knows and this file does not
-- would reach the engine unchecked.
local F = FILE.fields
M.SPECS = {
	cards = CARD, zones = ZONE, phases = PHASE, stats = STAT, tags = TAG,
	effects = F.effects.of, assets = F.assets.of[3], patterns = F.patterns.of[2],
	computed_tags = F.computed_tags.of, computes = F.computes.of, styles = F.styles.of,
	end_conditions = F.end_conditions.of, verbs = F.verbs.of,
	target = TARGET, route = ROUTE, adjusts = ADJUST, ability = ABILITY, reaction = REACTION,
	setup = F.setup, place = F.setup.fields.place.of[2], move_rule = MOVE_RULE,
	player = F.players.of, prompt = F.prompt,
}
for moment in pairs(M.MOMENTS) do M.SPECS[moment] = CARD.fields[moment] end
M.FILE = FILE
M.ENGINE_WRITES = ENGINE_WRITES

return M
