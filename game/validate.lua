-- Load-time content checks. Returns a list of problem strings; the engine
-- prints them and plays on — content errors warn, they never kill the game.
-- Messages are written for game authors, not programmers: they name the
-- entry, say what the engine expected, and suggest the nearest valid word.
-- Conflicts (duplicate keys, tags that disagree, ambiguous placement) are
-- called out explicitly. The test suite asserts that shipped games validate
-- clean.

local actions   = require("actions")
local predicate = require("predicate")   -- parse_subject only: pure, no game state

-- The same allowlist the loader enforces, so an author sees the problem at
-- load time instead of only in the console when the fetch is refused. Shared
-- rather than copied: a security rule kept in two files is the one that drifts.
local url_is_safe = require("cards").url_is_safe
-- art.parse is pure (no love, no state) for exactly this: a typo in a shape
-- spec is caught at load time rather than as a blank card at play time.
local art         = require("art")
local geometry    = require("geometry")
-- MOMENTS only: the table that says which flat fields a block becomes. Pure
-- data, and the loader requires nothing back, so there is no cycle here.
local MOMENTS     = require("declaration").MOMENTS

local M = {}

local RESERVED = { round = true, plays = true }

-- Stamped by the engine on every square of a grid (zones.lua), so a *scoped*
-- subject may read one off a slot although no card declares it. Not reserved:
-- a card declaring "col" or "row" is opting in to being stamped with where it
-- stands, which is how "rank" already works.
local SLOT_STATS = { col = true, row = true }

-- Every tag the engine itself reads, what it attaches to, and what it does.
--
-- One table because there were four half-lists: a set in this file that only
-- knew card words, three paragraphs in AUTHORING, and four prose strings in
-- SCHEMA.json. A word that two of them disagreed about would be reported as a
-- typo or silently ignored, and both failures look like the game being wrong.
--
-- **These names are reserved.** A game may not define a style, a tag with
-- behaviour, or a computed tag under one of them: the engine reads the word off
-- the entity and would obey both meanings at once. It costs a game the ability
-- to colour, say, everything `hidden` by naming a style after it — worth it, to
-- make "this word already means something" impossible to write by accident.
--
-- `on` is what carries it. Anything not listed is the game's own vocabulary and
-- the engine never looks at it.
M.ENGINE_TAGS = {
	-- cards
	player       = { on = "card", what = "this card is a seat. Stamped by the engine from the players section, not written by hand" },
	token        = { on = "card", what = "vanishes when a hand is swept, instead of joining the discard" },
	immutable    = { on = "card", what = "scenery: nothing may target it and its template can never be edited" },
	no_undo      = { on = "card", what = "playing or picking it clears the undo stack — the choice is final" },
	generate_art = { on = "card", what = "with no asset, draws a shape derived from its key rather than a bare colour" },
	-- zones
	per_seat          = { on = "zone", what = "one copy per seat; pos then takes one rect each" },
	shuffle           = { on = "zone", what = "shuffled when its contents are created, and on every refill" },
	refill_when_empty = { on = "zone", what = "recreates its contents when the last card leaves" },
	face_up           = { on = "zone", what = "cards here are shown, whatever the type would do — including a per-seat hand, which is how an open hand is said" },
	face_down         = { on = "zone", what = "cards here are hidden, whatever the type would do" },
	no_peek           = { on = "zone", what = "no tooltip and no browsing the pile" },
	activate          = { on = "zone", what = "cards here may use their abilities — without it an ability is unreachable" },
	optional          = { on = "zone", what = "nothing here ever has to be played, so a gated card stays gated" },
	page              = { on = "zone", what = "its cards are drawn as full-screen story pages" },
	last_acted        = { on = "card", what = "the card a player most recently played or activated. Written by the engine, one at a time, and it lingers until the next thing a player does" },
	hidden            = { on = "zone", what = "not drawn and not clickable — offer zones, fate decks" },
	-- phases
	discard_hand = { on = "phase", what = "leaving it discards the unplayed hand; tokens vanish" },
	keep_hand    = { on = "phase", what = "a draw_and_play phase opting out of the discard it would otherwise get" },
}
-- One word means two things, on two different kinds, and always has: a hidden
-- zone is not drawn, a hidden stat is not in the HUD. Listed apart rather than
-- given a second entry, since the table is keyed by the word.
M.ENGINE_TAGS_ALSO_ON_STATS = { hidden = "kept out of the HUD, while cards may still read and change it" }

-- Names conditions answer for themselves, so a zone or tag may not take one.
-- "self" is the acting card, "all" is everything, "reach" is wherever a set of
-- pieces could move, and "owner_of" is the seat something belongs to; none can
-- be expressed as a tag, which is why they are the only four the engine claims.
-- "player" is deliberately NOT reserved — it is an ordinary tag that content
-- puts on one card, which is what makes finding that card trivial.
local RESERVED_SCOPES = { "self", "all", "reach", "owner_of" }

-- The shapes a stat may ask to be drawn with. Named by shape rather than by
-- meaning, so a game's own word for its currency is its own business — and a
-- closed set, so a shape nobody draws is refused rather than silently becoming
-- a diamond. Held in step with render.icons() by the test suite; validate must
-- not require the presentation layer.
M.ICONS = {
	coin = true, heart = true, shield = true, banner = true, leaf = true,
	blade = true, diamond = true,
}

-- The fx base-effect vocabulary. The test suite asserts this stays in step
-- with fx.bases() — validate must not require the presentation layer.
M.EFFECT_BASES = {
	damage = true, bleed = true, power_up = true, sparkle = true,
	stars = true, heal = true, smoke = true, explosion = true,
}

-- Fields the engine reads on each kind of entry (including the derived ones
-- declaration.parse adds). Anything else is almost certainly a typo.
--
-- Exported below as M.FIELDS, because SCHEMA.json describes the same fields in
-- prose and the two must not drift: a schema that documents a field the engine
-- dropped is worse than none, since it looks machine-made and is believed.
-- tests/integration/schema.lua compares them both ways.
-- What a card is, then the moments it has. Everything a moment carries is
-- reached through its block; the flat names beside them are what the parser
-- derives, and writing one is an error rather than a second spelling.
local CARD_FIELDS = {
	key = true, text = true, tooltip = true, story = true, asset = true,
	tags = true, card_stats = true, outcome = true,
	play = true, activate = true, challenge = true, receive = true, turn = true,
	-- Several activated abilities instead of one. Authored as a list, and
	-- normalised in place into the same shape a lone "activate" produces, so
	-- nothing downstream asks which form was written.
	abilities = true,
	-- derived by declaration.parse from the blocks above
	cost = true, needs = true, target = true, phases = true, on_play = true,
	activate_cost = true, activate_target = true,
	activate_phases = true, on_activate = true, moves = true,
	move_rules = true, requires = true, on_pass = true, on_fail = true,
	accepts = true, on_receive = true, on_turn = true,
	auto_play = true, to_zone = true, to_slot = true, tags_set = true, injected = true,
	style = true,
	-- Written by the engine onto the menu entry it generates for each ability of
	-- a card that has several. Never authored: a game names abilities, not the
	-- cards that stand for them in a chooser.
	menu_for = true,
}
local PLAY_FIELDS      = { cost = true, needs = true, target = true, phases = true,
	action = true }
local ACTIVATE_FIELDS  = { cost = true, target = true, phases = true, action = true,
	moves = true }
local RECEIVE_FIELDS   = { needs = true, action = true }
local TURN_FIELDS      = { action = true }
local ZONE_FIELDS = {
	key = true, label = true, type = true, pos = true, grid = true, style = true,
	contents = true, tooltip = true, tags = true, tags_set = true,
	-- its own ability, and what declaration.parse derives from that block
	activate = true, on_activate = true, activate_phases = true, activate_cost = true,
	activate_target = true, moves = true,
	injected = true, applies = true, accepts = true, on_receive = true, receive = true,
	asset = true,
}
local PHASE_FIELDS = {
	key = true, label = true, type = true, actions = true, deck = true,
	draw = true, zone = true, pass_card = true, next = true,
	ends_after = true, ends_when = true, injected = true, tags = true, tags_set = true,
	seat = true, on_enter = true,
	-- derived: "zone" normalised to a list (declaration.parse)
	zone_list = true,
}
local STAT_FIELDS     = { key = true, label = true, min = true, max = true, subject = true,
	tags = true, tags_set = true, icon = true,
	-- Whose number this is, and where they start. See the check below.
	on = true, start = true,
	-- The colour of that icon, when the shape's own is wrong for it.
	color = true }
-- A tag def is a mixin: it may carry a home zone, and the card behaviour a zone
-- hands to whatever sits in it ("applies"). Kept to the fields a granted rule
-- can honestly mean — nothing that would have to be re-derived as state moves.
-- A tag def is a card mixin, so it speaks a card's moments. What a tag can
-- honestly grant is an ability and a home — nothing that would have to be
-- re-derived as state moves — so `activate` is the only block it takes.
-- The flat names a tag's "play" block becomes, and which the loader then copies
-- onto every card wearing the tag. Derived from the loader's own table rather
-- than typed out again: a moment gaining a field must not need editing twice.
local GRANTED_PLAY    = { play = true }
for _, internal in pairs(MOMENTS.play) do GRANTED_PLAY[internal] = true end

local TAG_FIELDS      = { zone = true, tooltip = true, activate = true, play = true,
	abilities = true,
	-- derived from the blocks, as on a card
	on_activate = true, activate_target = true, activate_cost = true,
	activate_phases = true, moves = true,
	on_play = true, cost = true, needs = true, target = true, phases = true }
-- Stats the engine writes on a card for itself. A game declaring one gets it
-- overwritten and no error — which is the shape of bug that costs an afternoon,
-- because the number is right in the file and wrong in the game.
--
-- Only asked of cards a game wrote. The engine stamps several of these onto its
-- own injected defs, and "won" it stamps onto whichever card a game named as a
-- seat — that collision is reported at parse, where the authored value still
-- exists to be compared against.
local ENGINE_STATS    = {
	owner      = "which seat a piece belongs to, from where it was placed",
	turn       = "whose go it is, on the system card",
	round      = "the round counter, on the system card",
	plays      = "how many cards have been played this phase",
	last_acted = "the card a player most recently played or activated",
	ability    = "which ability a chooser entry stands for",
}
local EFFECT_FIELDS   = { base = true, size = true, speed = true, count = true, color = true }
local TARGET_FIELDS   = { type = true, min = true, max = true, count = true, tags = true, zones = true,
	owner = true, fill = true, moves = true, where = true }
-- How a pattern's vectors are walked. A closed set the engine defines, unlike
-- card and zone tags, which are the game's own vocabulary — hence the different
-- word for it in the JSON.
local PATTERN_CLASSES = { step = true, ray = true, phasing = true,
	absolute = true }
-- Words that describe how a pattern is *walked*, and so mean nothing once its
-- pairs are squares rather than directions.
local WALKING_CLASSES = { step = true, ray = true, phasing = true }
-- What may already be standing on a targeted square. See targeting.slot_offered.
local FILL_WORDS      = { empty = true, enemy = true, open = true, any = true }
-- A routing entry and an end condition ask the same question and do different
-- things with the answer, which is the whole of what still separates them: one
-- may end the round, the other remembers having fired.
local ROUTE_FIELDS    = { when = true, zone_empty = true, ["then"] = true, ends_round = true,
	seat = true }
-- What a route may say about whose turn it becomes, overruling the phase's own.
-- Two words rather than a boolean, because "same" is a decision a game makes and
-- not the absence of one — a phase leading back to itself is asked for opposite
-- answers by Splendor and by The Crew.
local ROUTE_SEATS     = { next = true, same = true }
local END_FIELDS      = { when = true, zone_empty = true, ["then"] = true, fired = true }
local COMPUTED_FIELDS = { stat = true, injected = true, less_than = true, less_than_stat = true,
	at_least = true, equals = true, less_than_max = true }
-- The assets table: named pictures, and the only place a picture carries
-- options. Everything a card's `asset` can spell out inline is legal as a `src`
-- here too, so the source is checked by the same rules.
-- What a style may carry. Presentation only, and deliberately closed: the
-- moment a style could change a rule, every rules bug becomes a drawing bug.
local STYLE_FIELDS    = { color = true, title = true, border = true, fit = true,
	ratio = true, chequer = true, paint = true, cell_outline = true, fan = true,
	badges = true, badge_run = true, badge_zeros = true }
-- Which way a card's badges go. Two words rather than four: nothing has asked
-- to run up or leftwards, and a direction nobody draws would be a silent shrug.
local BADGE_RUNS      = { right = true, down = true }
local FAN_DIRS        = { up = true, down = true, left = true, right = true }
-- The orders activate_zone will walk a zone in. Naming none is the order the
-- cards are in, which is why this set does not contain a word for it.
local ORDER_WORDS     = { by_column = true }
local ASSET_FIELDS    = { src = true, max = true }
-- A challenge is asked by the resolve_challenge action: one condition, and the
-- two action lists it chooses between. They only ever work together, which is
-- why they are one block rather than three fields that can be half-written.
local CHALLENGE_FIELDS = { needs = true, pass = true, fail = true }
local PATTERN_FIELDS  = { vectors = true, class = true, zone = true }
local ZONE_TYPES      = { deck = true, pile = true, hand = true, grid = true, options = true }
local PHASE_TYPES     = { automatic = true, player_input = true, draw_and_play = true, overlay = true }

-- The same tables, reachable. Named for the JSON section each belongs to, since
-- that is how the schema document is organised and how an author meets them.
M.FIELDS = {
	cards         = CARD_FIELDS,
	zones         = ZONE_FIELDS,
	phases        = PHASE_FIELDS,
	stats         = STAT_FIELDS,
	tags          = TAG_FIELDS,
	effects       = EFFECT_FIELDS,
	assets        = ASSET_FIELDS,
	patterns      = PATTERN_FIELDS,
	computed_tags = COMPUTED_FIELDS,
	styles        = STYLE_FIELDS,
	end_conditions = END_FIELDS,
	target        = TARGET_FIELDS,
	route         = ROUTE_FIELDS,
	play          = PLAY_FIELDS,
	activate      = ACTIVATE_FIELDS,
	challenge     = CHALLENGE_FIELDS,
	receive       = RECEIVE_FIELDS,
	turn          = TURN_FIELDS,
}

-- Fields declaration.parse adds to a def after reading it. They are legal on an
-- entry the engine hands around and are not things an author ever writes, so
-- the schema document must not describe them.
M.DERIVED = { tags_set = true, injected = true, move_rules = true, fired = true, style = true,
	-- flattened out of the moment blocks by declaration.parse, never authored
	cost = true, needs = true, target = true, phases = true, on_play = true,
	activate_cost = true, activate_target = true,
	activate_phases = true, on_activate = true, moves = true,
	requires = true, on_pass = true, on_fail = true, accepts = true,
	on_receive = true, on_turn = true, zone_list = true,
	auto_play = true, to_zone = true, to_slot = true }

-- Edit distance (with swapped-letter typos counting as one edit), for
-- "did you mean" suggestions.
local function distance(a, b)
	local la, lb = #a, #b
	local d = {}
	for i = 0, la do d[i] = { [0] = i } end
	for j = 0, lb do d[0][j] = j end
	for i = 1, la do
		for j = 1, lb do
			local cost = a:byte(i) == b:byte(j) and 0 or 1
			local v = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
			if i > 1 and j > 1 and a:byte(i) == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then
				v = math.min(v, d[i - 2][j - 2] + 1)
			end
			d[i][j] = v
		end
	end
	return d[la][lb]
end

-- " — did you mean 'X'?" when something in the set is close enough, else "".
local function suggest(name, set)
	name = tostring(name):lower()
	local best, bd = nil, math.max(1, math.floor(#name / 3)) + 1
	for k in pairs(set or {}) do
		local d = distance(name, tostring(k):lower())
		if d < bd then best, bd = tostring(k), d end
	end
	return best and (" — did you mean '" .. best .. "'?") or ""
end

function M.check(G)
	local problems = {}
	local function warn(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end

	for _, p in ipairs(G.parse_problems or {}) do warn("%s", p) end

	local tag_defs = G.tag_defs or {}

	-- Known universes.
	-- Tags written on a card, kept separate from the ones a zone hands out: a
	-- zone granting a tag proves the tag is *used*, never that it is defined,
	-- so the two questions need two sets or "applies" vouches for itself.
	local card_tags = {}
	for _, def in pairs(G.card_defs) do
		if type(def.tags) == "table" then
			for _, t in ipairs(def.tags) do card_tags[t] = true end
		end
	end
	local carried_tags = {}
	for t in pairs(card_tags) do carried_tags[t] = true end
	for _, zd in pairs(G.zone_defs) do
		for _, t in ipairs(type(zd.applies) == "table" and zd.applies or {}) do
			carried_tags[t] = true
		end
	end
	local known_tags = {}
	for t in pairs(carried_tags) do known_tags[t] = true end
	for t in pairs(G.computed_tags) do known_tags[t] = true end
	for t in pairs(tag_defs) do known_tags[t] = true end

	-- Zones and tags share one namespace: a condition that points at "@holdings"
	-- means either the zone or the cards carrying that tag, and it must not
	-- have to guess. Caught here, at authoring time, rather than resolved by a
	-- precedence rule nobody would remember. RESERVED_SCOPES are the names the
	-- engine answers for itself, so content may not claim them either.
	-- One edit from a reserved word, and long enough that the resemblance cannot
	-- be a coincidence. Short words collide by accident — "mage" is one edit from
	-- "page" and is nobody's mistake — so both the word and the reserved one have
	-- to be at least six letters. "activaet" is eight and unmistakable.
	local function near_reserved(word)
		if #word < 6 then return nil end
		local best
		for name in pairs(M.ENGINE_TAGS) do
			if #name >= 6 and distance(word, name) == 1 and (not best or name < best) then best = name end
		end
		return best
	end

	-- A tag the engine *nearly* knows. Free vocabulary is the point, so an
	-- unknown word is never an error — but a word one edit away from a reserved
	-- one is almost always that word misspelled, and every one of them fails
	-- silently: a board tagged "activaet" holds cards whose abilities can never
	-- be used, and nothing anywhere says so.
	do
		local carriers = {
			card  = { defs = G.card_defs,  what = "card" },
			zone  = { defs = G.zone_defs,  what = "zone" },
			phase = { defs = G.phase_by_key, what = "phase" },
			stat  = { defs = G.stat_defs,  what = "stat" },
		}
		local order = { "card", "zone", "phase", "stat" }
		for _, kind in ipairs(order) do
			local keys = {}
			for key in pairs(carriers[kind].defs) do keys[#keys + 1] = key end
			table.sort(keys)
			for _, key in ipairs(keys) do
				local def = carriers[kind].defs[key]
				local words = {}
				for tag in pairs(def.tags_set or {}) do words[#words + 1] = tag end
				table.sort(words)
				for _, tag in ipairs(words) do
					local near = not M.ENGINE_TAGS[tag] and near_reserved(tag)
					if near then
						warn("%s '%s': is tagged '%s', which the engine does not read — did you mean '%s'?",
							carriers[kind].what, key, tag, near)
					end
				end
			end
		end
	end

	-- A reserved word may not be redefined. The engine reads it off the entity,
	-- so a style or a tag def under the same name would have the engine obeying
	-- one meaning and the game intending another, with nothing to say which won.
	for kind, defs in pairs({ style = G.style_defs or {}, tag = tag_defs,
		["computed tag"] = G.computed_tags or {} }) do
		local names = {}
		for name in pairs(defs) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local e = M.ENGINE_TAGS[name]
			-- The engine's own registrations are how some of those words come to
			-- be readable at all; only a game writing one is a collision.
			if e and not (type(defs[name]) == "table" and defs[name].injected) then
				warn("%s '%s' redefines a word the engine already reads on a %s (%s) — pick another name",
					kind, name, e.on, e.what)
			end
		end
	end

	-- One namespace, and only one: the words a *scope* resolves. `@board` is
	-- asked of patterns first, then zones, then tags (predicate.lua:145), so two
	-- kinds sharing a name means a condition silently picks one.
	--
	-- Names outside this set are free to repeat, and two of those repetitions are
	-- load-bearing. A card key doubling as a tag is how a chess piece is named by
	-- another piece's condition. And a style sharing its name with a computed tag
	-- is what makes a look follow the numbers — both are tag words, so they are
	-- one kind here and never in conflict.
	local scope_kind, conflicts = {}, {}
	local function claim(name, kind)
		local had = scope_kind[name]
		if had and had ~= kind then
			conflicts[#conflicts + 1] = { name = name, a = had, b = kind }
		end
		scope_kind[name] = had or kind
	end
	for name in pairs(G.zone_defs) do claim(name, "zone") end
	for name in pairs(G.pattern_defs or {}) do claim(name, "pattern") end
	for name in pairs(known_tags) do claim(name, "tag") end
	for name in pairs(G.style_defs or {}) do claim(name, "tag") end
	table.sort(conflicts, function(x, y) return x.name < y.name end)
	for _, c in ipairs(conflicts) do
		warn("'%s' is the name of both a %s and a %s — a condition pointing at it "
			.. "could mean either, so rename one of them", c.name, c.a, c.b)
	end

	-- Walk the two reserved names, not every tag and zone: deterministic order
	-- without sorting, and the list is stated once.
	for _, name in ipairs(RESERVED_SCOPES) do
		local what = known_tags[name] and "tag" or G.zone_defs[name] and "zone"
		if what then
			warn("%s '%s' uses a name the engine reserves for conditions (%s) — rename it",
				what, name, table.concat(RESERVED_SCOPES, ", "))
		end
	end

	local player_stats = {}
	for k in pairs((G.setup or {}).player or {}) do player_stats[k] = true end
	-- A bare subject resolves to the seat whose go it is, so a stat declared on
	-- a seat card is one a bare subject may legitimately name — which is what
	-- lets a cost be written "mana" rather than "mana@mine.player".
	for _, key in ipairs(G.seat_list or {}) do
		local sd = G.card_defs[key]
		for k in pairs(type(sd) == "table" and type(sd.card_stats) == "table" and sd.card_stats or {}) do
			player_stats[k] = true
		end
	end

	local card_stats = {}
	for _, def in pairs(G.card_defs) do
		for k in pairs(type(def.card_stats) == "table" and def.card_stats or {}) do
			card_stats[k] = true
		end
	end

	local all_stats = {}
	for k in pairs(G.stat_defs) do all_stats[k] = true end
	for k in pairs(RESERVED) do all_stats[k] = true end
	for k in pairs(player_stats) do all_stats[k] = true end

	-- Boards a card could be moved onto: hidden grids (the engine's own) are
	-- not among them, exactly as actions.sole_grid decides at runtime.
	local grids = {}
	for key, zd in pairs(G.zone_defs) do
		if zd.type == "grid" and not (zd.tags_set and zd.tags_set.hidden) then
			grids[#grids + 1] = key
		end
	end
	table.sort(grids)

	local function stat_ok(key)
		return all_stats[key] ~= nil
	end

	-- Everything a scope may name, for checking and for suggestions.
	local scope_names = { target = true }
	for _, k in ipairs(RESERVED_SCOPES) do scope_names[k] = true end
	for k in pairs(G.zone_defs) do scope_names[k] = true end
	for k in pairs(known_tags) do scope_names[k] = true end
	-- A pattern names a shape, and a shape answers "what is standing there" as
	-- readily as "where may I go", so it is a scope too.
	for k in pairs(G.pattern_defs or {}) do scope_names[k] = true end

	-- The name a scope expression really has to resolve. "owner_of.<scope>" is a
	-- prefix — it names the seats owning what the rest of it names — so the rest
	-- is what has to exist, and a typo in it is a typo in an ordinary scope.
	local function scope_named(name)
		local inner = type(name) == "string" and name:match("^owner_of%.(.+)$")
		if not inner then return name end
		local sc = predicate.parse_scope(inner)
		return sc and scope_named(sc.name) or inner
	end

	-- A subject: [<fn>:]<stat|tag|card>[@[<quant>.]<scope>]. allow_fn is false
	-- for costs, where count:/card:/sum:/max:/min: have nothing to spend.
	local function subject_ok(where, key, allow_fn)
		if allow_fn == nil then allow_fn = true end
		local p = predicate.parse_subject(key)
		if not p then
			warn("%s: '%s' is not something the engine can measure", where, tostring(key))
			return
		end
		local named = p.scope and scope_named(p.scope)
		if p.scope and not scope_names[named] then
			warn("%s: '@%s' is neither a zone nor a tag%s",
				where, p.scope, suggest(named, scope_names))
		end
		if p.fn and not allow_fn then
			warn("%s: '%s:' measures something rather than spending it, so it cannot be a cost",
				where, p.fn)
			return
		end
		if p.fn == "saved" then
			if not tostring(p.arg):match("^[%w_%-]+$") then
				warn("%s: '%s' is not a save slot — letters, digits, - and _, and the engine decides where it lands",
					where, tostring(p.arg))
			end
		elseif p.fn == "count" or p.fn == "tagged" or p.fn == "not_tagged" then
			if not known_tags[p.arg] then
				warn("%s: %s the tag '%s', but no card has it%s", where,
					p.fn == "count" and "counts" or "asks about",
					p.arg, suggest(p.arg, known_tags))
			end
		elseif p.fn == "card" then
			if not G.card_defs[p.arg] then
				warn("%s: checks for the card '%s', but no template has that key%s",
					where, p.arg, suggest(p.arg, G.card_defs))
			end
		elseif not stat_ok(p.arg) then
			-- A scoped subject reads a stat off the cards it names, so a stat
			-- only ever carried by cards is legitimate there.
			if not (p.scope and (card_stats[p.arg] or SLOT_STATS[p.arg])) then
				warn("%s: uses the stat '%s', but it is never declared or set up%s",
					where, tostring(p.arg), suggest(p.arg, all_stats))
			end
		end
	end

	-- A condition written as one string. The parse is the engine's own, so a file
	-- the validator calls clean cannot be one the runtime silently drops — and
	-- what it hands back names the two operands, which are ordinary subjects and
	-- are checked as such.
	local function condition_ok(where, s)
		local c, err = predicate.parse_condition(s)
		if not c then
			warn('%s: "%s" — %s', where, tostring(s), err)
			return
		end
		-- Two cost words that read as ordinary subjects and would be reported as
		-- misspelled stats. Both are mistakes somebody actually made, and the
		-- useful thing to say is which block they belong in.
		local left = c.left.subject and c.left.subject.arg
		if left == "exhaust" then
			warn("%s: 'exhaust' is a cost, not a condition — a card cannot need itself spent", where)
			return
		elseif type(left) == "string" and left:match("^sacrifice:") then
			warn("%s: 'sacrifice:' belongs in cost or activate_cost, not here", where)
			return
		end
		subject_ok(where, c.left.src or c.left.n)
		if c.right.subject then subject_ok(where, c.right.src) end
	end

	-- A gate: a list of conditions, every one of which must hold. It was a map
	-- keyed by its own subject, which could not hold one subject twice — so a
	-- range had nowhere to live — and which spelled the comparison in a nested
	-- object. Both are gone; this is what says so to a file that still has one.
	local function check_conditions(where, list)
		if list == nil then return end
		if type(list) ~= "table" then
			warn('%s: should be a list of conditions like ["gold >= 3"]', where)
			return
		end
		if next(list) ~= nil and list[1] == nil then
			warn('%s: is written as a map, which a condition no longer is — write ["gold >= 3"], '
				.. "one entry per condition, and all of them have to hold", where)
			return
		end
		for i, entry in ipairs(list) do
			condition_ok(where .. "[" .. i .. "]", entry)
		end
	end

	-- A cost: a map of subject to number, and it stays one. A cost is what gets
	-- *spent*, which is a subject and an amount — "mana >= 3" says what to check
	-- and not what to take away, so the two never wanted the same shape.
	local function check_cost(where, map, kind)
		if map == nil then return end
		if type(map) ~= "table" then
			warn('%s: should be written like { "gold": 2 }', where)
			return
		end
		if type(map[1]) == "string" then
			warn('%s: a cost is what gets spent, not a condition — write it as { "gold": 2 }', where)
			return
		end
		for key, v in pairs(map) do
			local sac = tostring(key):match("^sacrifice:(.+)$")
			-- Being spent is a cost like any other, and the only one a card pays
			-- with itself. It has no place on a card being played out of a hand:
			-- there is nothing there to stay spent.
			if key == "exhaust" then
				if not (kind == "activate" or where:find("activate", 1, true)) then
					warn("%s: 'exhaust' belongs in an activate cost — a card leaving a hand has nothing to spend", where)
				elseif tonumber(v) ~= 1 then
					warn("%s: exhaust is 1 — a card is either spent or it is not", where)
				end
			elseif sac then
				if not known_tags[sac] then
					warn("%s: sacrifices the tag '%s', but no card has it%s",
						where, sac, suggest(sac, known_tags))
				end
			else
				-- A cost's subjects may carry a scope, but not a measuring fn.
				subject_ok(where, key, false)
			end
			if type(v) ~= "number" then
				warn("%s: the value of '%s' should be a number", where, tostring(key))
			elseif v < 0 then
				warn("%s: '%s' is negative — costs and requirements must be zero or more",
					where, tostring(key))
			end
		end
	end

	-- Answers whether it recognised the entry as a stale one, so the caller can
	-- skip the unknown-field pass: "stat", "at_least" and "at_most" are three
	-- complaints about one mistake, and only this one says what to write.
	local function check_cond(where, cond)
		if cond.stat ~= nil then
			warn('%s: says its condition as a stat and a comparison, which it no longer is — '
				.. 'write { "when": "%s >= 1" }', where, tostring(cond.stat))
			return true
		end
		if cond.when ~= nil then
			condition_ok(where, cond.when)
			return
		end
		if cond.zone_empty ~= nil then
			if type(cond.zone_empty) ~= "table" then
				warn('%s: zone_empty should be a list of zones like ["road", "hand"]', where)
				return
			end
			for _, zk in ipairs(cond.zone_empty) do
				if not G.zone_defs[zk] then
					warn("%s: watches zone '%s', but no zone has that key%s", where, zk, suggest(zk, G.zone_defs))
				end
			end
		end
	end

	local function check_fields(where, def, fields)
		if type(def) ~= "table" then return end
		for k in pairs(def) do
			if not fields[k] then
				warn("%s: has a field '%s' the engine doesn't read%s", where, tostring(k), suggest(k, fields))
			end
		end
	end

	local function check_numbers(where, what, arr, n)
		if arr == nil then return end
		if type(arr) ~= "table" or #arr ~= n then
			warn("%s: %s should be a list of %d numbers", where, what, n)
			return
		end
		for _, v in ipairs(arr) do
			if type(v) ~= "number" then
				warn("%s: %s should contain only numbers", where, what)
				return
			end
		end
	end

	-- Action strings. The per-argument reference checks are derived from each
	-- op's declared shape (actions.spec), so the validator can't drift from
	-- the handlers.
	local known_ops = actions.ops()
	local check_action
	function check_action(where, str)
		local p = {}
		for w in str:gmatch("[^:]+") do p[#p + 1] = w end
		local op   = p[1]
		local spec = actions.spec(op)
		if not spec then
			warn("%s: '%s' is not an action the engine knows%s", where, tostring(op), suggest(op, known_ops))
			return
		end
		local i = 1
		for word in spec:gmatch("%S+") do
			i = i + 1
			local t, optional = word:match("^(%w+)(%??)$")
			local a = p[i]
			if a == nil then
				if optional == "" and t ~= "n" and t ~= "any" then
					warn("%s: '%s' is missing its %s argument", where, op, t)
				end
				break
			end
			if t == "action" then
				-- A wrapping op: everything after it is an action of its own, so
				-- the argument checks that matter are that one's. Rejoined
				-- rather than taken word by word, since an action carries its
				-- own colons.
				check_action(where, table.concat(p, ":", i))
				break
			elseif t == "zone" then
				-- A zone argument may say whose it is ("enemy.arena"), so the
				-- key to check is the last word. An unknown owner word simply
				-- stays part of the name and is caught as an unknown zone.
				local sc = predicate.parse_scope(a)
				if not (sc and (G.zone_defs[sc.name] or sc.name == "target")) then
					warn("%s: '%s' points at zone '%s', but no zone has that key%s",
						where, op, a, suggest(sc and sc.name or a, G.zone_defs))
				end
			elseif t == "occupied" then
				-- Either of the two words, or the zone a taken piece goes to.
				local sc = a ~= "refuse" and a ~= "destroy" and predicate.parse_scope(a)
				if sc and not G.zone_defs[sc.name] then
					warn("%s: '%s' says '%s' happens to a piece already standing there — it should be 'destroy', 'refuse', or the zone taken pieces go to%s",
						where, op, a, suggest(sc.name, G.zone_defs))
				end
			elseif t == "scope" then
				local sc = predicate.parse_scope(a)
				local named = sc and scope_named(sc.name)
				if not (sc and scope_names[named]) then
					warn("%s: '%s' names '%s', which is neither a zone nor a tag%s",
						where, op, a, suggest(named or a, scope_names))
				end
			elseif t == "card" and not G.card_defs[a] then
				warn("%s: '%s' names the card '%s', but no template has that key%s",
					where, op, a, suggest(a, G.card_defs))
			elseif t == "stat" then
				-- An action's stat argument is a full subject: it may carry a
				-- scope, and a scoped one may read a stat only cards have.
				subject_ok(where .. ": " .. op, a)
			elseif t == "order" then
				-- A closed set, and today it holds one word. Refusing the rest
				-- is the point: an order the engine cannot honour must not look
				-- like one it can, and a game asking for something else should
				-- be told rather than quietly given the default.
				if not ORDER_WORDS[a] then
					warn('%s: "%s" is not an order the engine knows — it knows "by_column", and naming '
						.. "none acts in the order the cards are in%s",
						where, tostring(a), suggest(a, ORDER_WORDS))
				end
			elseif t == "seat" then
				-- A seat by its own key, the one that is up, or nobody.
				if a ~= "none" and a ~= "mine" and not (G.seat_index or {})[a] then
					warn("%s: '%s' hands the card to '%s', which is neither a seat nor \"mine\" nor \"none\"%s",
						where, op, tostring(a), suggest(a, G.seat_index or {}))
				end
			elseif t == "phase" and not G.phase_by_key[a] then
				warn("%s: '%s' points at phase '%s', but no phase has that key%s",
					where, op, a, suggest(a, G.phase_by_key))
			elseif t == "effect" and not (G.effect_defs or {})[a] then
				warn("%s: '%s' plays the effect '%s', but the game defines no such effect%s",
					where, op, a, suggest(a, G.effect_defs))
			elseif t == "save" then
				if not tostring(a):match("^[%w_%-]+$") then
					warn("%s: '%s' names the save '%s', which isn't a plain word — the engine decides where a save lands, and it will be refused when it runs",
						where, op, tostring(a))
				end
			elseif t == "gamefile" then
				if not tostring(a):match("^[%w_%-]+%.json$") then
					warn("%s: '%s' names '%s', which isn't a plain name.json — no folders or '..' are allowed (and it will be refused when it runs)",
						where, op, tostring(a))
				elseif not love.filesystem.read("games/" .. a) then
					warn("%s: '%s' points at '%s', but that file doesn't exist", where, op, a)
				end
			end
		end
		for j, w in ipairs(p) do
			if (w == "sum" or w == "max" or w == "min") and p[j + 1] then
				subject_ok(where .. ": " .. tostring(op), p[j + 1])
			end
			if (w == "count" or w == "card") and p[j + 1] and not (w == "card" and j == 1) then
				subject_ok(where .. ": " .. tostring(op), w .. ":" .. p[j + 1])
			end
		end
		if op == "return_to" and p[2] and G.zone_defs[p[2]]
			and G.zone_defs[p[2]].tags_set and G.zone_defs[p[2]].tags_set.refill_when_empty then
			warn("%s: return_to drains '%s', which refills itself when empty — it would refill mid-drain", where, p[2])
		end
	end

	local function check_list(where, list)
		if list == nil then return end
		if type(list) ~= "table" then
			warn('%s: should be a list of actions like ["stat_gain:gold:1"], not a single value', where)
			return
		end
		for _, str in ipairs(list) do
			if type(str) ~= "string" then
				warn("%s: every action must be a text string", where)
			else
				check_action(where, str)
			end
		end
	end

	-- A target spec, wherever it is written: a card's "play.target", its
	-- "activate.target", or one inside an entry of an "abilities" list. Extracted
	-- because the third of those was going unchecked entirely — the card loop read
	-- the two flat fields and nothing walked the list.
	local function check_target(where, field, spec)
		if type(spec) ~= "table" then return end
		check_fields(where .. " " .. field, spec, TARGET_FIELDS)
		if spec.type and spec.type ~= "card" and spec.type ~= "slot"
			and spec.type ~= "zone" then
			warn("%s %s: type should be 'card', 'slot' or 'zone', not '%s'", where, field, tostring(spec.type))
		end
		if spec.type == "zone" then
			if not spec.zones then
				warn("%s %s: targets a zone but names none — list them in \"zones\"", where, field)
			end
			if spec.tags then
				warn("%s %s: targets a zone, so \"tags\" is not read (zones are named, not tagged)", where, field)
			end
		end
		if spec.fill ~= nil then
			if not FILL_WORDS[spec.fill] then
				warn("%s %s: fill should be 'empty', 'enemy', 'open' or 'any', not '%s'",
					where, field, tostring(spec.fill))
			end
			if spec.type ~= "slot" then
				warn("%s %s: \"fill\" says what may be standing on a square, so it only applies to \"type\": \"slot\"", where, field)
			end
		end
		for _, t in ipairs(type(spec.tags) == "table" and spec.tags or {}) do
			if not known_tags[t] then
				warn("%s %s: looks for the tag '%s', but no card has it%s", where, field, t, suggest(t, known_tags))
			end
		end
		for _, zk in ipairs(type(spec.zones) == "table" and spec.zones or {}) do
			if not G.zone_defs[zk] then
				warn("%s %s: searches zone '%s', but no zone has that key%s", where, field, zk, suggest(zk, G.zone_defs))
			end
		end
		-- Asked of each candidate with that candidate as the target, so its
		-- subjects are checked exactly as a move rule's "where" already is.
		check_conditions(where .. " " .. field .. " where", spec.where)
	end

	-- "phases": which phases a card (or a tag granting it one) may be used in.
	-- Overlays are excluded on purpose: they lock every other action while they
	-- are open, so naming one is a rule that can never come true.
	local function check_phases(where, list)
		if list == nil then return end
		local keys = type(list) == "string" and { list } or list
		if type(keys) ~= "table" then
			warn('%s: phases should be a phase key or a list of them', where)
			return
		end
		for _, key in ipairs(keys) do
			local pd = type(key) == "string" and G.phase_by_key[key]
			if not pd then
				warn("%s: is limited to phase '%s', but no phase has that key%s",
					where, tostring(key), suggest(key, G.phase_by_key))
			elseif pd.type == "overlay" then
				warn("%s: is limited to phase '%s', which is an overlay — an open "
					.. "overlay locks every other action, so it could never be used there",
					where, tostring(key))
			end
		end
	end

	-- The move rules of one ability: which patterns it moves by, and what may be
	-- standing on the square it lands on.
	local function check_moves(where, rules)
		for _, rule in ipairs(rules or {}) do
			for _, pname in ipairs(rule.patterns or {}) do
				if not G.pattern_defs[pname] then
					warn("%s: moves by the pattern '%s', but none is declared under \"patterns\"%s",
						where, tostring(pname), suggest(pname, G.pattern_defs))
				end
			end
			if not FILL_WORDS[rule.fill] then
				warn("%s: a move's fill should be 'empty', 'enemy', 'open' or 'any', not '%s'",
					where, tostring(rule.fill))
			end
			-- Asked of each square the rule offers, with that square as the
			-- target — so it reads like any other condition, and its subjects
			-- are checked like any other's.
			check_conditions(where .. " where", rule.where)
		end
	end

	-- One entry of an "abilities" list, which nothing used to read.
	--
	-- A card writing several abilities was invisible here: the loop below checks
	-- the flat activate_* fields, and those exist only for the one-ability form.
	-- Everything chess's pawn and king are written as — costs, actions, patterns,
	-- fills, phases, targets — went unvalidated, which is to say the game driving
	-- the whole feature was the one the validator had stopped reading.
	local function check_ability(where, ab)
		if type(ab) ~= "table" then return end
		check_cost(where .. " cost", ab.cost, "activate")
		check_list(where .. " action", ab.action)
		check_phases(where, ab.phases)
		check_target(where, "target", ab.target)
		check_moves(where, ab.moves)
		if ab.moves and not ab.action then
			warn("%s: says how it moves but does nothing when the square is chosen "
				.. '(usually "move_to:target")', where)
		end
		if ab.target and not ab.action then
			warn("%s: has a target but no action — there is nothing for it to target", where)
		end
	end

	-- Stats.
	for key, def in pairs(G.stat_defs) do
		local where = "stat '" .. key .. "'"
		check_fields(where, def, STAT_FIELDS)
		if RESERVED[key] and (def.min or def.max) then
			warn("%s: is managed by the engine; its min/max are ignored", where)
		end
		-- A stat may display something wider than itself ("sum:defense@board"):
		-- the HUD reads the subject, the stat key still names what is spent.
		if def.subject ~= nil then subject_ok(where, def.subject) end
		if type(def.min) == "number" and type(def.max) == "number" and def.min > def.max then
			warn("%s: min (%s) is greater than max (%s)", where, def.min, def.max)
		end
		if def.icon ~= nil and not M.ICONS[def.icon] then
			warn("%s: asks to be drawn as '%s', which is not a shape the engine has%s",
				where, tostring(def.icon), suggest(def.icon, M.ICONS))
		end
		-- A colour without a shape colours the fallback diamond, which is legal
		-- and is what a stat wanting a colour and no opinion on the silhouette
		-- would write.
		if def.color ~= nil and not art.colour(def.color) then
			warn("%s: '%s' is not a colour — a palette name, or #rrggbb",
				where, tostring(def.color))
		end
	end

	-- **Whose number a stat is.** Carrying a stat is how a card says it takes
	-- part in one — an action skips a card that has none, and an absent stat
	-- fails every comparison rather than reading as zero — so a deck of forty
	-- used to declare the same zero forty times. A stat says it once instead,
	-- beside the floor and the ceiling of the same number.
	--
	-- With `start`, every card carrying one of those tags is handed that value
	-- and may still say its own. Without one, each of them has to say — "a
	-- creature has hp, and every creature says how much" — and forgetting is
	-- what the second loop catches. Walked in declared order, because a warning
	-- per card is a list somebody reads.
	for _, key in ipairs(G.stat_defs_list or {}) do
		local def   = G.stat_defs[key] or {}
		local where = "stat '" .. key .. "'"
		if def.start ~= nil and def.on == nil then
			warn('%s: says where it starts but not whose it is — name the cards with "on": ["<tag>"]', where)
		end
		for _, tg in ipairs(type(def.on) == "table" and def.on or {}) do
			if not known_tags[tg] then
				warn("%s: is a number about '%s', which nothing defines or wears%s",
					where, tostring(tg), suggest(tg, known_tags))
			end
		end
		if type(def.on) == "table" and def.start == nil then
			for _, ck in ipairs(G.card_list) do
				local cd = G.card_defs[ck] or {}
				for _, tg in ipairs(def.on) do
					if cd.tags_set and cd.tags_set[tg] then
						if type(cd.card_stats) ~= "table" or cd.card_stats[key] == nil then
							warn("%s: is a number every '%s' carries, and the card '%s' never says"
								.. " what it starts at", where, tostring(tg), tostring(ck))
						end
						break
					end
				end
			end
		end
	end

	-- Tag behaviour.
	for tag, td in pairs(tag_defs) do
		local where = "tag '" .. tostring(tag) .. "'"
		if type(td) ~= "table" then
			warn('%s: should be written like { "zone": "inventory" }', where)
		else
			check_fields(where, td, TAG_FIELDS)
			if td.zone and not G.zone_defs[td.zone] then
				warn("%s: sends cards to zone '%s', but no zone has that key%s",
					where, tostring(td.zone), suggest(td.zone, G.zone_defs))
			end
			check_list(where .. " on_activate", td.on_activate)
			check_phases(where, td.phases)
			if not td.on_activate then
				for i, ab in ipairs(td.abilities or {}) do
					check_ability(("%s ability %d ('%s')"):format(where, i, tostring(ab.key)), ab)
				end
			end
			-- A tag hands behaviour to the cards carrying it, so a card that
			-- also declares the same field is two answers to one question.
			-- Reported rather than resolved: there is no precedence rule to
			-- fall back on, and inventing one hides the mistake.
			--
			-- Abilities are the exception, and the only one: two answers is
			-- exactly what they are for. A card that can already do something
			-- and is handed another thing can do both, and the player is asked
			-- which — where a granted ability used to hide the card's own.
			--
			-- "play" is the second exception, and unlike abilities it *does* have
			-- a precedence rule: the card's own wins and the tag fills in for the
			-- cards that say nothing. So the flat fields are skipped here — by the
			-- time this runs the loader has already copied the tag's onto every
			-- card that inherited it, and every one of them would look like a card
			-- answering twice. A card writing its own is not a conflict at all:
			-- it is one template opting out of the sentence the others share,
			-- which is the whole point of there being a rule.
			for field in pairs(td) do
				if field ~= "zone" and field ~= "abilities" and not GRANTED_PLAY[field] then
					for _, ck in ipairs(G.card_list) do
						local cd = G.card_defs[ck]
						if cd.tags_set and cd.tags_set[tag] and cd[field] ~= nil then
							warn("%s: defines '%s', but the card '%s' carries the tag and defines it too "
								.. "— one of them has to give", where, field, ck)
						end
					end
				end
			end
			if G.computed_tags[tag] then
				warn("%s: is defined under both 'tags' and 'computed_tags' — computed tags can't carry behaviour", where)
			end
			if not carried_tags[tag] then
				warn("%s: has behaviour defined, but no card carries this tag%s",
					where, suggest(tag, carried_tags))
			end
		end
	end

	-- Abilities need somewhere to be used. Activation is the zone's to allow,
	-- so a game full of on_activate cards and no zone tagged "activate" has
	-- written abilities nobody can ever reach — silently, which is the worst
	-- way for it to be wrong.
	do
		local can_use = false
		for _, zd in pairs(G.zone_defs) do
			if zd.tags_set and zd.tags_set.activate then can_use = true end
		end
		if not can_use then
			local who
			for _, key in ipairs(G.card_list) do
				if G.card_defs[key].on_activate then who = key; break end
			end
			for tag, td in pairs(tag_defs) do
				if type(td) == "table" and td.on_activate then who = who or ("tag '" .. tag .. "'") end
			end
			if who then
				warn("'%s' has an ability, but no zone is tagged \"activate\" — "
					.. "abilities are only usable in a zone that allows them", who)
			end
		end
	end

	-- Effects.
	for name, def in pairs(G.effect_defs or {}) do
		local where = "effect '" .. tostring(name) .. "'"
		if type(def) ~= "table" then
			warn('%s: should be written like { "base": "sparkle", "size": 1.5 }', where)
		else
			check_fields(where, def, EFFECT_FIELDS)
			if not M.EFFECT_BASES[def.base or ""] then
				warn("%s: '%s' is not a base effect%s", where, tostring(def.base),
					suggest(def.base, M.EFFECT_BASES))
			end
			for _, k in ipairs({ "size", "speed", "count" }) do
				if def[k] ~= nil and type(def[k]) ~= "number" then
					warn("%s: %s should be a number", where, k)
				end
			end
			check_numbers(where, "color", def.color, 3)
		end
	end

	-- Styles: a named look, claimed by tagging it. Two styles on one card
	-- claiming the same property is an authoring conflict, reported rather than
	-- resolved by a precedence rule nobody could remember — the same stance the
	-- engine takes when a card and its zone define one behaviour twice.
	for name, sd in pairs(G.style_defs or {}) do
		local where = "style '" .. tostring(name) .. "'"
		if type(sd) ~= "table" then
			warn('%s: should be a map of look, like { "color": [0.8, 0.2, 0.2] }', where)
		else
			check_fields(where, sd, STYLE_FIELDS)
			-- One property for the plate: a colour, or false for none.
			if sd.color ~= false then check_numbers(where, "color", sd.color, 3) end
			if sd.title ~= nil and sd.title ~= false then
				warn("%s: title takes only false, which means draw none", where)
			end
			if sd.cell_outline ~= nil and sd.cell_outline ~= false then
				warn("%s: cell_outline takes only false, which means draw none", where)
			end
			if sd.border ~= nil and sd.border ~= false then
				warn("%s: border takes only false, which means draw none", where)
			end
			if sd.fit ~= nil and sd.fit ~= "card" and sd.fit ~= "fill" then
				warn("%s: fit should be 'card' or 'fill', not '%s'", where, tostring(sd.fit))
			end
			-- Which way a stack spreads when it is shown spread out. The word is
			-- the direction the *next* card is laid, so "down" is a tableau and
			-- "up" is an expedition growing away from its owner.
			if sd.fan ~= nil and not FAN_DIRS[sd.fan] then
				warn('%s: fan should be "up", "down", "left" or "right", not %s', where, tostring(sd.fan))
			end
			-- Which way this card's badges go: along the bottom, or down the
			-- side when there are more of them than fit across.
			if sd.badge_run ~= nil and not BADGE_RUNS[sd.badge_run] then
				warn('%s: badge_run should be "right" or "down", not %s', where, tostring(sd.badge_run))
			end
			if sd.badge_zeros ~= nil and sd.badge_zeros ~= false then
				warn("%s: badge_zeros takes only false, which means leave a zero out", where)
			end
			if (sd.badge_run or sd.badge_zeros ~= nil) and sd.badges == nil then
				warn("%s: says how its badges are drawn but names none — add \"badges\"", where)
			end
			-- The shape a zone keeps whatever the window does: a number is width
			-- over height, "grid" reads it from the cell count.
			if sd.ratio ~= nil and sd.ratio ~= "grid" and not (tonumber(sd.ratio) and tonumber(sd.ratio) > 0) then
				warn('%s: ratio should be a positive number (width over height, 1 is square) or "grid", not %s',
					where, tostring(sd.ratio))
			end
			if sd.chequer ~= nil then
				if type(sd.chequer) ~= "table" or #sd.chequer ~= 2 then
					warn('%s: chequer should be two colours, like ["#f0d9b5", "#b58863"]', where)
				else
					for _, w in ipairs(sd.chequer) do
						if not art.colour(w) then
							warn("%s: '%s' is not a colour — use a palette name or #rrggbb%s",
								where, tostring(w), suggest(w, art.colours()))
						end
					end
				end
			end
			-- Squares named by an absolute pattern, given a colour or a picture.
			for name, look in pairs(type(sd.paint) == "table" and sd.paint or {}) do
				local pat = G.pattern_defs[name]
				if not pat then
					warn("%s: paints the squares of '%s', but no pattern has that name%s",
						where, tostring(name), suggest(name, G.pattern_defs))
				elseif not pat.absolute then
					warn("%s: paints '%s', which is a pattern of directions — only an absolute pattern names squares to paint",
						where, tostring(name))
				end
				if type(look) ~= "string" then
					warn("%s: what '%s' is painted with should be a colour or a filename", where, tostring(name))
				end
			end
		end
	end
	-- **Badges are read off the card, so a style only a zone claims draws none.**
	-- A style is claimed by carrying a tag of its name, and `cards.style` asks
	-- the card — not the zone the card is lying in. Splendor named badges on
	-- three zone styles and drew all three nowhere, for a year, with no warning:
	-- the property is legal, the style exists, and nothing was wrong to find.
	do
		local worn = {}
		for _, def in pairs(G.card_defs) do
			for tag in pairs(def.tags_set or {}) do worn[tag] = true end
		end
		for name, sd in pairs(G.style_defs or {}) do
			if type(sd) == "table" and sd.badges ~= nil and not worn[name] then
				warn("style '%s': names badges, but no card carries '%s' — a badge is drawn from the card's own style, so a look only a zone claims shows nothing",
					tostring(name), tostring(name))
			end
		end
	end

	for key, def in pairs(G.card_defs) do
		local claimed = {}
		for tag in pairs(def.tags_set or {}) do
			for prop in pairs(type((G.style_defs or {})[tag]) == "table" and G.style_defs[tag] or {}) do
				if claimed[prop] then
					warn("card '%s': styles '%s' and '%s' both set %s — one look, one word for it",
						key, claimed[prop], tag, prop)
				end
				claimed[prop] = tag
			end
		end
	end

	-- Computed tags.
	for tag, def in pairs(G.computed_tags) do
		local where = "computed tag '" .. tostring(tag) .. "'"
		if type(def) == "table" and def.injected then
			-- The engine's own, over a stat the engine writes: no card declares
			-- it and none should.
		elseif type(def) ~= "table" then
			warn('%s: should be written like { "stat": "hp", "equals": "0" }', where)
		else
			check_fields(where, def, COMPUTED_FIELDS)
			if def.stat and not card_stats[def.stat] then
				warn("%s: reads the card stat '%s', but no card carries it%s",
					where, tostring(def.stat), suggest(def.stat, card_stats))
			end
		end
	end

	for name, def in pairs(type(G.raw_assets) == "table" and G.raw_assets or {}) do
		local where = "asset '" .. tostring(name) .. "'"
		local src = type(def) == "table" and def.src or def
		if type(def) == "table" then
			check_fields(where, def, ASSET_FIELDS)
			if def.src == nil then
				warn('%s: needs a "src" — the filename, URL or shape it draws', where)
			end
			if def.max ~= nil and (tonumber(def.max) == nil or tonumber(def.max) < 1 or tonumber(def.max) > 4092) then
				warn("%s: max is the longest edge in pixels, between 1 and 4092 — %s is not", where, tostring(def.max))
			end
		end
		-- One source, or one per seat. A piece that is the same piece in two
		-- colours is one name with two pictures, which is what lets a game
		-- declare six kinds instead of six kinds times however many players.
		local srcs = src
		if type(src) == "string" then srcs = { src }
		elseif type(src) == "table" and #src == 0 then srcs = nil end
		if type(srcs) ~= "table" then
			warn("%s: should be a source, an object with one, or one source per player", where)
		else
			local seats = #(G.seat_list or {})
			if seats > 0 and #srcs > seats then
				warn("%s: has %d pictures for %d player%s — the rest can never be drawn",
					where, #srcs, seats, seats == 1 and "" or "s")
			end
			for _, s in ipairs(srcs) do
				if type(s) ~= "string" then
					warn("%s: '%s' is not a source", where, tostring(s))
				elseif s:match("^https?://") then
					if not url_is_safe(s) then
						warn("%s: its URL contains characters that aren't valid in a URL — it will be refused at load time", where)
					end
				elseif s:find(":") then
					if not art.parse(s) then
						warn("%s: '%s' isn't a shape the engine can draw", where, s)
					end
				elseif s:find("%.") then
					if not love.filesystem.read("games/assets/" .. s) then
						warn("%s: '%s' is not in games/assets", where, s)
					end
				else
					warn("%s: '%s' names no picture — a filename, an http(s) URL or a shape", where, s)
				end
			end
		end
	end

	-- Movement patterns. Checked against the raw JSON shape rather than the
	-- normalised one, because a mistyped class word or a vector that isn't a
	-- pair is silently dropped by the normaliser and would otherwise show up
	-- only as a piece that mysteriously cannot move.
	local raw_patterns = type(G.raw_patterns) == "table" and G.raw_patterns or {}
	for name, def in pairs(raw_patterns) do
		local where = "pattern '" .. tostring(name) .. "'"
		local vectors, class = def, nil
		if type(def) == "table" and def.vectors ~= nil then
			vectors, class = def.vectors, def.class
			check_fields(where, def, PATTERN_FIELDS)
		end
		if class ~= nil and type(class) ~= "table" then
			warn('%s: "class" should be a list, like ["ray"]', where)
		end
		local absolute = false
		for _, w in ipairs(type(class) == "table" and class or {}) do
			if tostring(w) == "absolute" then absolute = true end
		end
		if type(vectors) ~= "table" or #vectors == 0 then
			warn(absolute and '%s: should be a list of squares, like ["a1", "h1"]'
				or '%s: should be a list of [x, y] pairs, like [[1,0],[0,1]]', where)
		end
		-- Two different things wear the same field. An absolute pattern names
		-- squares — places, said the way a player says them — and a relative one
		-- names directions, which are pairs counted from the piece outwards.
		-- The board an absolute pattern names, or the only one there is: a pattern
		-- may leave "zone" out exactly when the game has a single grid, and
		-- predicate.pattern_slots then resolves it against that one. Leaving it nil
		-- here measured every square against a placeholder 26x99 instead, so on a
		-- sole 8x8 board "z9" validated clean and then named nothing at all.
		local named = absolute and type(def) == "table" and def.zone
		local board = named and G.zone_defs[def.zone] or (absolute and #grids == 1 and G.zone_defs[grids[1]])
		local grid = board and board.grid or nil
		for _, v in ipairs(type(vectors) == "table" and vectors or {}) do
			if absolute then
				local col, rank = geometry.square({ grid = grid or { 26, 99 } }, v)
				if not col then
					warn('%s: "%s" is not a square — write a column letter and a rank, like "e1"',
						where, tostring(v))
				elseif grid and (col < 1 or rank < 1 or col > grid[1] or rank > grid[2]) then
					-- Both ends, because a rank counts from 1: "e0" parses, passes
					-- an upper bound, and is refused by geometry.slot_at at runtime,
					-- so the pattern quietly names one square fewer than it reads.
					warn("%s: square '%s' is off '%s', which is %dx%d", where, tostring(v),
						tostring(board.key or named), grid[1], grid[2])
				end
			elseif type(v) ~= "table" or tonumber(v[1]) == nil or tonumber(v[2]) == nil or #v ~= 2 then
				warn("%s: every direction is a pair of whole numbers — [1,2] means one column across and two ranks on", where)
			elseif tonumber(v[1]) == 0 and tonumber(v[2]) == 0 then
				warn("%s: [0,0] is not a direction — it never leaves the square it started on", where)
			end
		end
		for _, w in ipairs(type(class) == "table" and class or {}) do
			local word, arg = tostring(w):match("^([%a_]+):?(%d*)$")
			if not (word and PATTERN_CLASSES[word]) then
				warn("%s: '%s' is not a way of walking a pattern%s", where, tostring(w),
					suggest(word or tostring(w), PATTERN_CLASSES))
			elseif arg ~= "" and word ~= "ray" then
				warn("%s: only 'ray' takes a distance — '%s:%s' means nothing", where, word, arg)
			elseif absolute and WALKING_CLASSES[word] then
				warn("%s: is absolute, so its pairs are squares and '%s' has no path to describe",
					where, word)
			end
		end
		-- A square belongs to a board; a direction is anchored on whoever is
		-- moving and needs none.
		if type(def) == "table" and def.zone ~= nil then
			if not absolute then
				warn('%s: only an absolute pattern names a "zone" — a direction is anchored on the piece using it', where)
			elseif not G.zone_defs[def.zone] then
				warn("%s: names zone '%s', but no zone has that key%s", where,
					tostring(def.zone), suggest(def.zone, G.zone_defs))
			end
		elseif absolute and #grids ~= 1 then
			warn('%s: is absolute, so it needs a "zone" — this game has %d boards and a bare square could mean either',
				where, #grids)
		end
	end

	-- Cards.
	for key, def in pairs(G.card_defs) do
		local where = "card '" .. key .. "'"
		check_fields(where, def, CARD_FIELDS)
		for moment, fields in pairs({ play = PLAY_FIELDS, activate = ACTIVATE_FIELDS,
			receive = RECEIVE_FIELDS, turn = TURN_FIELDS, challenge = CHALLENGE_FIELDS }) do
			if type(def[moment]) == "table" then
				check_fields(where .. " " .. moment, def[moment], fields)
			end
		end
		if type(def.challenge) == "table" then
			if def.challenge.needs == nil then
				warn('%s: a challenge with no "needs" has nothing to decide — it always passes', where)
			end
		end
		for _, rule in ipairs(def.move_rules or {}) do
			for _, pname in ipairs(rule.patterns) do
				if not G.pattern_defs[pname] then
					warn("%s: moves by the pattern '%s', but none is declared under \"patterns\"%s",
						where, tostring(pname), suggest(pname, G.pattern_defs))
				end
			end
			if not FILL_WORDS[rule.fill] then
				warn("%s: a move's fill should be 'empty', 'enemy', 'open' or 'any', not '%s'",
					where, tostring(rule.fill))
			end
			-- Asked of each square the rule offers, with that square as the
			-- target — so it reads like any other condition, and its subjects
			-- are checked like any other's.
			check_conditions(where .. " where", rule.where)
		end
		if def.moves and not def.on_activate then
			warn("%s: says how it moves but has no on_activate — nothing happens when the square is chosen (usually \"move_to:target\")", where)
		end
		if def.asset and G.asset_defs and G.asset_defs[def.asset] then
			-- Named in the assets table, which is checked once on its own below.
		elseif def.asset and tostring(def.asset):match("^https?://") then
			if not url_is_safe(def.asset) then
				warn("%s: its image URL contains characters that aren't valid in a URL — it will be refused at load time",
					where)
			end
		elseif def.asset == "auto" then
			-- generated from the key; nothing to check
		elseif def.asset and tostring(def.asset):find(":") then
			if not art.parse(def.asset) then
				local shape = tostring(def.asset):match("^([^:]+)")
				warn("%s: its art '%s' isn't a shape the engine can draw%s — the form is <shape>[:<n>]:<colour>[:<colour>]",
					where, tostring(def.asset),
					art.shapes()[shape] and "" or suggest(shape, art.shapes()))
			end
		elseif def.asset and not tostring(def.asset):find("%.") then
			warn("%s: nothing is named '%s' in the assets section%s", where, tostring(def.asset),
				suggest(tostring(def.asset), G.asset_defs or {}))
		elseif def.asset and not love.filesystem.read("games/assets/" .. tostring(def.asset)) then
			warn("%s: its image '%s' is not in games/assets", where, tostring(def.asset))
		end
		-- One word, and it is a word about the only player there is. A game with
		-- two seats says who won by setting "won" on one of them instead, since
		-- the same card is read by both and would be wrong for one.
		if def.outcome and def.outcome ~= "victory" and def.outcome ~= "defeat" then
			warn("%s: outcome should be 'victory' or 'defeat', not '%s'%s — a game with seats names its winner with stat_gain:won@<seat>:1",
				where, tostring(def.outcome), suggest(def.outcome, { victory = true, defeat = true }))
		end
		if def.tags ~= nil and type(def.tags) ~= "table" then
			warn('%s: tags should be a list like ["item", "weapon"]', where)
		end
		check_cost(where .. " cost", def.cost)
		check_cost(where .. " activate_cost", def.activate_cost, "activate")
		check_conditions(where .. " needs", def.needs)
		check_conditions(where .. " requires", def.requires)
		-- "accepts" is asked of this card about the one arriving, so @self is
		-- this card and @target the newcomer. "on_receive" answers the same way.
		check_conditions(where .. " accepts", def.accepts)
		check_list(where .. " receive action", def.on_receive)
		check_phases(where, def.phases)
		-- card_stats declare new per-card stats, so only their values are checked.
		if def.card_stats ~= nil then
			if type(def.card_stats) ~= "table" then
				warn('%s: card_stats should be written like { "hp": 3 } or { "hp": [3, 3] }', where)
			else
				for k, v in pairs(def.card_stats) do
					-- A number is a bare current value; a list is the bounds
					-- beside it — [current, max], or [min, current, max].
					if type(v) == "table" then
						local n = #v
						if n < 1 or n > 3 then
							warn("%s card_stats: '%s' should be a number, [current, max], or [min, current, max]",
								where, tostring(k))
						end
						for _, part in ipairs(v) do
							if type(part) ~= "number" then
								warn("%s card_stats: every number in '%s' should be a number", where, tostring(k))
							end
						end
						if n == 3 and type(v[1]) == "number" and type(v[3]) == "number" and v[1] > v[3] then
							warn("%s card_stats: '%s' has a floor above its ceiling", where, tostring(k))
						end
					elseif type(v) ~= "number" then
						warn("%s card_stats: the value of '%s' should be a number, or a list of them", where, tostring(k))
					end
					if ENGINE_STATS[k] and not def.injected then
						warn("%s card_stats: '%s' is the engine's own — it is %s, and whatever this card"
							.. " says is overwritten", where, tostring(k), ENGINE_STATS[k])
					end
				end
			end
		end
		check_numbers(where, "color", def.color, 3)
		check_list(where .. " on_play", def.on_play)
		check_list(where .. " on_activate", def.on_activate)
		check_list(where .. " on_turn", def.on_turn)
		check_list(where .. " on_pass", def.on_pass)
		check_list(where .. " on_fail", def.on_fail)

		-- "target" gates playing the card, "activate_target" its board ability;
		-- same shape, same checks, and an ability in a list takes the same again.
		for _, field in ipairs({ "target", "activate_target" }) do
			check_target(where, field, def[field])
		end

		if def.activate_target and not def.on_activate then
			warn("%s: has an activate_target but no on_activate — there is no ability for it to target", where)
		end

		-- The flat fields above are the one-ability form's, and only that form
		-- sets on_activate — so this walks exactly the entries nothing else read.
		if not def.on_activate then
			for i, ab in ipairs(def.abilities or {}) do
				check_ability(("%s ability %d ('%s')"):format(where, i, tostring(ab.key)), ab)
			end
		end

		-- Placement: where does this card go? Its tags may disagree (a
		-- conflict), or nothing may say (ambiguous once there are several
		-- boards).
		local homes = {}
		if type(def.tags) == "table" then
			for _, t in ipairs(def.tags) do
				local td = tag_defs[t]
				if td and type(td) == "table" and td.zone then homes[#homes + 1] = { tag = t, zone = td.zone } end
			end
		end
		for i = 2, #homes do
			if homes[i].zone ~= homes[1].zone then
				warn("%s: its tags disagree about where it goes — '%s' places it in '%s', but '%s' places it in '%s'",
					where, homes[1].tag, homes[1].zone, homes[i].tag, homes[i].zone)
			end
		end
		local function bare_move(list)
			if type(list) ~= "table" then return false end
			for _, s in ipairs(list) do
				if s == "move_to" then return true end
			end
			return false
		end
		if #homes == 0 and (bare_move(def.on_play)
			or bare_move(def.on_pass) or bare_move(def.on_fail)) then
			if #grids > 1 then
				warn("%s: is moved with 'move_to' but nothing says where — this game has %d boards (%s); give the card a tag with a home zone, or write move_to:<zone>",
					where, #grids, table.concat(grids, ", "))
			elseif #grids == 0 then
				warn("%s: is moved with 'move_to' but this game has no board zone to put it on", where)
			end
		end

		if def.auto_play then
			local tz = def.to_zone or (homes[1] and homes[1].zone) or "board"
			if not G.zone_defs[tz] then
				warn("%s: starts in play, but its zone '%s' doesn't exist%s", where, tz, suggest(tz, G.zone_defs))
			end
		end
	end

	-- Zones.
	for key, def in pairs(G.zone_defs) do
		local where = "zone '" .. key .. "'"
		check_fields(where, def, ZONE_FIELDS)
		if def.type and not ZONE_TYPES[def.type] then
			warn("%s: '%s' is not a zone type (deck, pile, hand, grid or options)%s",
				where, tostring(def.type), suggest(def.type, ZONE_TYPES))
		end
		-- A grid puts each card in an addressed slot; a fan lays them in a run.
		-- Both answer "where does this card go", so a zone wearing both has two
		-- answers and the renderer would take whichever it read last.
		if def.type == "grid" then
			for tag in pairs(def.tags_set or {}) do
				local sd = G.style_defs and G.style_defs[tag]
				if type(sd) == "table" and sd.fan then
					warn("%s: is a grid and wears '%s', which fans — a grid places by slot and a fan by order, "
						.. "and they cannot both decide. Make it a pile, or drop the style", where, tag)
				end
			end
		end
		if type(def.activate) == "table" then
			check_fields(where .. " activate", def.activate, ACTIVATE_FIELDS)
			if def.activate.action == nil then
				warn('%s: has an "activate" block with no action — nothing would happen', where)
			end
		end
		if def.tags_set and def.tags_set.per_seat then
			local seats = #(G.seat_list or {})
			if seats > 1 then
				if type(def.pos) ~= "table" or #def.pos ~= seats then
					warn("%s: exists once per seat, so pos should be a list of %d rects — one per seat, or they draw on top of each other",
						where, seats)
				else
					for i, r in ipairs(def.pos) do
						check_numbers(where, "pos[" .. i .. "]", r, 4)
					end
				end
			end
		else
			check_numbers(where, "pos", def.pos, 4)
		end
		-- The lower-left corner belongs to the undo button and event log.
		if type(def.pos) == "table" and #def.pos == 4
			and type(def.pos[1]) == "number" and type(def.pos[4]) == "number"
			and not (def.tags_set and def.tags_set.hidden)
			and def.pos[1] < 0.17 and def.pos[4] > 0.82 then
			warn("%s: covers the lower-left corner where the undo button and event log live — start it at x 0.19 or higher", where)
		end
		if def.type == "grid" then
			if def.grid == nil then
				warn('%s: a board needs "grid": [columns, rows]', where)
			else
				check_numbers(where, "grid", def.grid, 2)
			end
			if type(def.grid) == "table" and type(def.grid[1]) == "number"
				and type(def.grid[2]) == "number" and type(def.contents) == "table" then
				local cap, total = def.grid[1] * def.grid[2], 0
				for _, entry in ipairs(def.contents) do
					local _, n = tostring(entry):match("^([^:]+):?(%d*)$")
					total = total + (tonumber(n) or 1)
				end
				if total > cap then
					warn("%s: starts with %d cards but the board only has %d slots — the extras are dropped",
						where, total, cap)
				end
			end
		end
		for _, entry in ipairs(type(def.contents) == "table" and def.contents or {}) do
			local ckey, n = tostring(entry):match("^([^:]+):?(%d*)$")
			if not ckey or not G.card_defs[ckey] then
				warn("%s: starts with the card '%s', but no template has that key%s",
					where, tostring(ckey or entry), suggest(ckey or entry, G.card_defs))
			elseif entry:find(":") and n == "" then
				warn("%s: '%s' should look like 'card' or 'card:3'", where, tostring(entry))
			end
		end
		if def.contents ~= nil and type(def.contents) ~= "table" then
			warn('%s: contents should be a list like ["sword:3", "trap"]', where)
		end
		check_conditions(where .. " accepts", def.accepts)
		check_list(where .. " receive action", def.on_receive)
		if def.applies ~= nil then
			if type(def.applies) ~= "table" then
				warn('%s: applies should be a list of tag names like ["takeable"]', where)
			else
				for _, tag in ipairs(def.applies) do
					if G.computed_tags[tag] then
						warn("%s: hands out '%s', which is a computed tag — those are "
							.. "derived from a card's own stats and cannot be granted", where, tostring(tag))
					elseif not tag_defs[tag] and not card_tags[tag] and not M.ENGINE_TAGS[tag] then
						warn("%s: hands out '%s', which nothing defines or reads%s",
							where, tostring(tag), suggest(tag, known_tags))
					end
				end
			end
		end
	end

	-- Two zones in the same place. A zone paints its background whether or not
	-- it holds anything, so an empty one covers whatever it is drawn over, and
	-- the cards underneath cannot be clicked either. Lost Cities shipped for a
	-- while with its tally zone lying across both players' hands, which looks
	-- like a rendering bug and is really a layout one. Reported once per pair,
	-- and only when the overlap is big enough to be a mistake rather than a
	-- shared edge.
	do
		local rects = {}
		for _, key in ipairs(G.zone_list) do
			local def = G.zone_defs[key]
			if def and not (def.tags_set and def.tags_set.hidden) and type(def.pos) == "table" then
				local per_seat = def.tags_set and def.tags_set.per_seat
				local list = per_seat and def.pos or { def.pos }
				-- A per_seat zone declaring one rect shares it between seats,
				-- which the check above already warns about; skip it here so one
				-- mistake is not reported twice.
				if type(list[1]) == "table" then
					for i, r in ipairs(list) do
						-- All four, not just the first: a rect is content, so it
						-- may be any shape at all, and the arithmetic below has
						-- to be unreachable for a malformed one.
						local numeric = type(r) == "table" and #r == 4
						for k = 1, 4 do numeric = numeric and type(r[k]) == "number" end
						if numeric then
							rects[#rects + 1] = { key = key .. (per_seat and ("[" .. i .. "]") or ""), r = r }
						end
					end
				end
			end
		end
		for i = 1, #rects do
			for j = i + 1, #rects do
				local a, b = rects[i].r, rects[j].r
				local ox = math.min(a[3], b[3]) - math.max(a[1], b[1])
				local oy = math.min(a[4], b[4]) - math.max(a[2], b[2])
				if ox > 0.01 and oy > 0.01 then
					warn("zone '%s' overlaps zone '%s' by %d%% x %d%% of the screen — "
						.. "an empty zone still paints over what is under it",
						rects[i].key, rects[j].key, math.floor(ox * 100 + 0.5), math.floor(oy * 100 + 0.5))
				end
			end
		end
	end

	-- Phases and routing.
	for key, pd in pairs(G.phase_by_key) do
		local where = "phase '" .. key .. "'"
		check_fields(where, pd, PHASE_FIELDS)
		if pd.type == nil then
			warn("%s: has no type (automatic, player_input, draw_and_play or overlay)", where)
		elseif not PHASE_TYPES[pd.type] then
			warn("%s: '%s' is not a phase type (automatic, player_input, draw_and_play or overlay)%s",
				where, tostring(pd.type), suggest(pd.type, PHASE_TYPES))
		end
		if pd.deck and not G.zone_defs[pd.deck] then
			warn("%s: draws from '%s', but no zone has that key%s", where, tostring(pd.deck), suggest(pd.deck, G.zone_defs))
		end
		-- Both the authored field and the list parse derived from it, deduped
		-- and in order: a warning has to survive a game text the normaliser
		-- never saw, which is what the debug API and this file's own tests do.
		local seen_zone = {}
		local function zone_named(zk)
			if type(zk) ~= "string" or seen_zone[zk] then return end
			seen_zone[zk] = true
			if not G.zone_defs[zk] then
				warn("%s: plays out of '%s', but no zone has that key%s", where, zk, suggest(zk, G.zone_defs))
			end
		end
		if type(pd.zone) == "table" then
			for _, zk in ipairs(pd.zone) do zone_named(zk) end
		elseif pd.zone ~= nil and type(pd.zone) ~= "string" then
			warn("%s: zone should be a zone key or a list of them", where)
		else
			zone_named(pd.zone)
		end
		for _, zk in ipairs(pd.zone_list or {}) do zone_named(zk) end
		if pd.draw ~= nil and type(pd.draw) ~= "number" then
			warn("%s: draw should be a number", where)
		end
		if pd.ends_after ~= nil then
			if type(pd.ends_after) ~= "number" then
				warn("%s: ends_after should be a number of plays", where)
			elseif pd.type ~= "player_input" and pd.type ~= "draw_and_play" then
				warn("%s: has ends_after, but only phases where cards are played count plays", where)
			end
		end
		if pd.ends_when ~= nil then
			check_cond(where .. " ends_when", { when = pd.ends_when })
			if pd.type == "automatic" or pd.type == "overlay" then
				warn("%s: has ends_when, but %s phases end themselves — the condition never decides",
					where, pd.type)
			end
			if pd.ends_after ~= nil then
				warn("%s: says both ends_after and ends_when — one phase, one way of ending", where)
			end
		end
		if pd.discard_hand and pd.type == "overlay" then
			warn("%s: has discard_hand, but overlays pop back — it never fires", where)
		end
		local pcs = type(pd.pass_card) == "table" and pd.pass_card or { pd.pass_card }
		for _, pk in ipairs(pcs) do
			if not G.card_defs[pk] then
				warn("%s: its pass card '%s' has no template%s", where, tostring(pk), suggest(pk, G.card_defs))
			end
		end
		if pd.type == "draw_and_play" and not pd.pass_card then
			warn("%s: forces a play every turn but has no pass_card — players can get stuck with nothing playable", where)
		end
		check_list(where .. " actions", pd.actions)
		check_list(where .. " on_enter", pd.on_enter)
		-- on_enter is what a phase does when the turn *begins*, as against every
		-- time round — so a phase nothing can lead back to has only one kind of
		-- entry, and splitting its actions in two says a distinction that isn't
		-- there. Cheap to spot and it always means the author meant "actions".
		if pd.on_enter ~= nil then
			local loops = false
			for _, r in ipairs(type(pd.next) == "table" and pd.next or {}) do
				if r["then"] == pd.key then loops = true end
			end
			if not loops then
				warn("%s: has on_enter, but nothing leads back to it — every entry is an arrival,"
					.. " so this is what \"actions\" already means", where)
			end
		end
		if pd.next then
			if type(pd.next) ~= "table" then
				warn("%s: next should be a list of routes", where)
			elseif pd.type == "overlay" then
				warn("%s: has routing, but overlays pop back — the routing never runs", where)
			else
				if pd.type == "automatic" then
					local fallback = false
					for _, r in ipairs(pd.next) do
						if r.stat == nil and r.zone_empty == nil and r.when == nil then fallback = true end
					end
					if not fallback then
						warn("%s: is automatic but every route has a condition — when none matches, the game stalls", where)
					end
				end
				local saw_unconditional = false
				for i, r in ipairs(pd.next) do
					local rwhere = where .. " next[" .. i .. "]"
					if not check_cond(rwhere, r) then check_fields(rwhere, r, ROUTE_FIELDS) end
					if saw_unconditional then
						warn("%s: can never be reached — an earlier route always matches", rwhere)
					end
					local target = G.phase_by_key[r["then"] or ""]
					if not target then
						warn("%s: goes to '%s', but no phase has that key%s",
							rwhere, tostring(r["then"]), suggest(r["then"], G.phase_by_key))
					elseif target.type == "overlay" then
						warn("%s: goes to '%s', which is an overlay — overlays can only be pushed", rwhere, r["then"])
					end
					if r.seat ~= nil and not ROUTE_SEATS[r.seat] then
						warn('%s: says seat "%s", which is not a word here — "next" passes to the following'
							.. ' seat, "same" keeps the one that is up%s',
							rwhere, tostring(r.seat), suggest(r.seat, ROUTE_SEATS))
					end
					if r.stat == nil and r.zone_empty == nil and r.when == nil then
						saw_unconditional = true
					end
				end
			end
		end
	end

	-- The built-in reveal pair works together: replacing only half of it
	-- leaves the other half pointing at the wrong shape.
	local zr, pr = G.zone_defs.reveal, G.phase_by_key.reveal
	if zr and pr and (zr.injected or false) ~= (pr.injected or false) then
		local own     = zr.injected and "phase" or "zone"
		local missing = zr.injected and "zone" or "phase"
		warn("this game defines its own 'reveal' %s but not the matching 'reveal' %s — define both or neither",
			own, missing)
	end

	-- End conditions.
	for i, cond in ipairs(G.end_conditions) do
		local where = "end condition " .. i
		if not check_cond(where, cond) then check_fields(where, cond, END_FIELDS) end
		check_list(where, cond["then"])
		if cond["then"] == nil then
			warn("%s: has no 'then' — nothing happens when it fires", where)
		end
	end

	-- Setup.
	if G.setup then
		check_fields("setup", G.setup, { place = true })
		-- Setup arranges the box: every entry names a card, and may say which
		-- zone, which squares, and whose it is. A square outside the grid is
		-- silently ignored at init, which reads as a piece that simply is not
		-- there — so it is worth saying out loud here.
		for i, e in ipairs(type(G.setup.place) == "table" and G.setup.place or {}) do
			local where = ("setup.place entry %d"):format(i)
			if type(e) == "table" then
				check_fields(where, e, { card = true, zone = true, at = true, owner = true })
				if not G.card_defs[e.card] then
					warn("%s: places '%s', but no card has that key%s", where, tostring(e.card),
						suggest(e.card, G.card_defs))
				end
				if e.owner ~= nil and not (G.seat_index and G.seat_index[e.owner]) then
					warn('%s: gives the piece to "%s", which is not one of this game\'s players%s',
						where, tostring(e.owner), suggest(e.owner, G.seat_index or {}))
				end
				local z = e.zone and G.zone_defs[e.zone]
				if e.zone and not z then
					warn("%s: places into '%s', but no zone has that key%s", where, tostring(e.zone),
						suggest(e.zone, G.zone_defs))
				elseif e.at ~= nil then
					local at = type(e.at) == "string" and { e.at } or e.at
					local cols = z and type(z.grid) == "table" and tonumber(z.grid[1]) or 0
					local rows = z and type(z.grid) == "table" and tonumber(z.grid[2]) or 0
					if type(at) ~= "table" then
						warn('%s: "at" should be a square like "e1", or a list of them', where)
					elseif cols == 0 or rows == 0 then
						warn("%s: names a square, but '%s' is not a grid", where, tostring(e.zone))
					else
						for _, name in ipairs(at) do
							local col, row = geometry.square({ grid = { cols, rows } }, name)
							if not col then
								warn('%s: "%s" is not a square — write a column letter and a rank, like "e1"',
									where, tostring(name))
							elseif col > cols or row < 1 or row > rows then
								warn("%s: square '%s' is off '%s', which is %dx%d",
									where, tostring(name), tostring(e.zone), cols, rows)
							end
						end
					end
				end
			end
		end
	end

	-- Who is playing. A seat is still a card; this says which cards those are,
	-- in seat order, so "is this a two-player game" is read rather than scanned.
	for i, e in ipairs(type(G.players) == "table" and G.players or {}) do
		local where = ("player %d"):format(i)
		if type(e) ~= "table" then
			warn('%s: should be an object, like { "card": "north" }', where)
		else
			check_fields(where, e, { card = true, stats = true, text = true })
			if e.card ~= nil and type(e.card) ~= "string" then
				warn("%s: its \"card\" should be the key of a card", where)
			end
			for k, v in pairs(type(e.stats) == "table" and e.stats or {}) do
				if type(v) ~= "number" then
					warn("%s: the starting value of '%s' should be a number", where, tostring(k))
				end
			end
		end
	end
	-- Checked against the normalised list too, not only the raw section: the
	-- parse drops an entry naming nothing so the walk below never has to defend
	-- itself, and a check that only read the raw form would miss what the engine
	-- actually ended up with.
	for i, seat in ipairs(G.player_list or {}) do
		if not G.card_defs[seat.card] then
			warn("player %d: names the card '%s', but no card has that key%s", i,
				tostring(seat.card), suggest(seat.card, G.card_defs))
		end
	end

	-- Offering an invite is content's decision, not the engine's — but a game
	-- with one chair offering one is a mistake nothing else would catch, since
	-- the action is a silent no-op without a second seat to hand over to.
	if #(G.player_list or {}) < 2 then
		for key, def in pairs(G.card_defs) do
			for _, act in ipairs(type(def.on_play) == "table" and def.on_play or {}) do
				if tostring(act):match("^net_invite") then
					warn("card '%s': offers an invite, but this game declares one seat — "
						.. 'add a second entry to "players" or drop the invite', key)
				end
			end
		end
	end

	-- The tag is stamped onto a seat, so one written by hand names a card the
	-- engine does not consider a player — and every "@mine.player" would reach it.
	for key, def in pairs(G.card_defs) do
		if def.tags_set and def.tags_set.player and not G.seat_set[key] then
			warn("card '%s': is tagged \"player\" but is not one — list it under \"players\" to make it a seat, or drop the tag", key)
		end
	end

	-- Guaranteed hangs: a cycle of automatic phases over unconditional edges.
	local function auto_successor(pd)
		if pd.next then
			for _, r in ipairs(type(pd.next) == "table" and pd.next or {}) do
				if r.stat == nil and r.zone_empty == nil then return r["then"] end
			end
			return nil
		end
		for i, key in ipairs(G.phase_list) do
			if key == pd.key then return G.phase_list[i + 1] end
		end
	end
	for key, pd in pairs(G.phase_by_key) do
		if pd.type == "automatic" then
			local seen, cur = {}, pd
			while cur and cur.type == "automatic" do
				if seen[cur.key] then
					warn("the automatic phases around '%s' run each other in a circle — the game would never stop", cur.key)
					break
				end
				seen[cur.key] = true
				cur = G.phase_by_key[auto_successor(cur) or ""]
			end
		end
	end

	table.sort(problems)
	return problems
end

return M
