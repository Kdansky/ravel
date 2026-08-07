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

local M = {}

local RESERVED = { round = true, plays = true }

-- Names conditions answer for themselves, so a zone or tag may not take one.
-- "self" is the acting card and "all" is everything; neither can be expressed
-- as a tag, which is why they are the only two the engine claims. "player" is
-- deliberately NOT reserved — it is an ordinary tag that content puts on one
-- card, which is what makes finding that card trivial.
local RESERVED_SCOPES = { "self", "all" }

-- The fx base-effect vocabulary. The test suite asserts this stays in step
-- with fx.bases() — validate must not require the presentation layer.
M.EFFECT_BASES = {
	damage = true, bleed = true, power_up = true, sparkle = true,
	stars = true, heal = true, smoke = true, explosion = true,
}

-- Fields the engine reads on each kind of entry (including the derived ones
-- declaration.parse adds). Anything else is almost certainly a typo.
local CARD_FIELDS = {
	key = true, text = true, tooltip = true, story = true, asset = true,
	color = true, tags = true, card_stats = true, cost = true,
	activate_cost = true, needs = true, requires = true, target = true,
	activate_target = true, exhausts = true,
	on_play = true, on_activate = true, on_turn = true, on_pass = true,
	on_fail = true, on_pick = true, auto_play = true, to_zone = true,
	to_slot = true, irreversible = true, outcome = true, tags_set = true,
	injected = true,
}
local ZONE_FIELDS = {
	key = true, label = true, type = true, pos = true, grid = true, fit = true,
	contents = true, on_click = true, tags = true, tags_set = true,
	injected = true,
}
local PHASE_FIELDS = {
	key = true, label = true, type = true, actions = true, deck = true,
	draw = true, zone = true, pass_card = true, on_pick = true, next = true,
	ends_after = true, discard_hand = true, page = true, injected = true,
}
local STAT_FIELDS     = { key = true, label = true, min = true, max = true, hidden = true, subject = true }
local TAG_FIELDS      = { zone = true }
local EFFECT_FIELDS   = { base = true, size = true, speed = true, count = true, color = true }
local TARGET_FIELDS   = { type = true, min = true, max = true, count = true, tags = true, zones = true }
local ROUTE_FIELDS    = { stat = true, zone_empty = true, equals = true, at_least = true,
	at_most = true, ["then"] = true, ends_round = true }
local END_FIELDS      = { stat = true, zone_empty = true, equals = true, at_least = true,
	at_most = true, ["then"] = true, fired = true }
local COMPUTED_FIELDS = { stat = true, less_than = true, less_than_stat = true,
	at_least = true, equals = true }
local ZONE_TYPES      = { deck = true, pile = true, hand = true, grid = true }
local PHASE_TYPES     = { automatic = true, player_input = true, draw_and_play = true, overlay = true }

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
	local carried_tags = {}
	for _, def in pairs(G.card_defs) do
		if type(def.tags) == "table" then
			for _, t in ipairs(def.tags) do carried_tags[t] = true end
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
	local conflicts = {}
	for name in pairs(known_tags) do
		if G.zone_defs[name] then conflicts[#conflicts + 1] = name end
	end
	table.sort(conflicts)
	for _, name in ipairs(conflicts) do
		warn("'%s' is the name of both a zone and a tag — a condition pointing at it "
			.. "could mean either, so rename one of them", name)
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

	-- A subject: [<fn>:]<stat|tag|card>[@[<quant>.]<scope>]. allow_fn is false
	-- for costs, where count:/card:/sum:/max: have nothing to spend.
	local function subject_ok(where, key, allow_fn)
		if allow_fn == nil then allow_fn = true end
		local p = predicate.parse_subject(key)
		if not p then
			warn("%s: '%s' is not something the engine can measure", where, tostring(key))
			return
		end
		if p.scope and not scope_names[p.scope] then
			warn("%s: '@%s' is neither a zone nor a tag%s",
				where, p.scope, suggest(p.scope, scope_names))
		end
		if p.fn and not allow_fn then
			warn("%s: '%s:' measures something rather than spending it, so it cannot be a cost",
				where, p.fn)
			return
		end
		if p.fn == "count" then
			if not known_tags[p.arg] then
				warn("%s: counts the tag '%s', but no card has it%s", where, p.arg, suggest(p.arg, known_tags))
			end
		elseif p.fn == "card" then
			if not G.card_defs[p.arg] then
				warn("%s: checks for the card '%s', but no template has that key%s",
					where, p.arg, suggest(p.arg, G.card_defs))
			end
		elseif not stat_ok(p.arg) then
			-- A scoped subject reads a stat off the cards it names, so a stat
			-- only ever carried by cards is legitimate there.
			if not (p.scope and card_stats[p.arg]) then
				warn("%s: uses the stat '%s', but it is never declared or set up%s",
					where, tostring(p.arg), suggest(p.arg, all_stats))
			end
		end
	end

	local function check_map(where, map, is_cost)
		if map == nil then return end
		if type(map) ~= "table" then
			warn('%s: should be written like { "gold": 2 }', where)
			return
		end
		for key, v in pairs(map) do
			local sac = tostring(key):match("^sacrifice:(.+)$")
			if sac then
				if not is_cost then
					warn("%s: 'sacrifice:' belongs in cost or activate_cost, not here", where)
				elseif not known_tags[sac] then
					warn("%s: sacrifices the tag '%s', but no card has it%s",
						where, sac, suggest(sac, known_tags))
				end
			else
				-- A cost's subjects may carry a scope, but not a measuring fn.
				subject_ok(where, key, not is_cost)
			end
			if type(v) ~= "number" then
				warn("%s: the value of '%s' should be a number", where, tostring(key))
			elseif v < 0 then
				warn("%s: '%s' is negative — costs and requirements must be zero or more",
					where, tostring(key))
			end
		end
	end

	local function check_cond(where, cond)
		if cond.zone_empty then
			if type(cond.zone_empty) ~= "table" then
				warn('%s: zone_empty should be a list of zones like ["road", "hand"]', where)
				return
			end
			for _, zk in ipairs(cond.zone_empty) do
				if not G.zone_defs[zk] then
					warn("%s: watches zone '%s', but no zone has that key%s", where, zk, suggest(zk, G.zone_defs))
				end
			end
		elseif cond.stat then
			subject_ok(where, cond.stat)
			for _, cmp in ipairs({ "equals", "at_least", "at_most" }) do
				if cond[cmp] ~= nil and type(cond[cmp]) ~= "number" then
					warn("%s: %s should be a number", where, cmp)
				end
			end
			if cond.equals == nil and cond.at_least == nil and cond.at_most == nil then
				warn("%s: names a stat but no comparison (equals / at_least / at_most)", where)
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
	local function check_action(where, str)
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
			if t == "zone" and not G.zone_defs[a] then
				warn("%s: '%s' points at zone '%s', but no zone has that key%s",
					where, op, a, suggest(a, G.zone_defs))
			elseif t == "card" and not G.card_defs[a] then
				warn("%s: '%s' names the card '%s', but no template has that key%s",
					where, op, a, suggest(a, G.card_defs))
			elseif t == "stat" then
				-- An action's stat argument is a full subject: it may carry a
				-- scope, and a scoped one may read a stat only cards have.
				subject_ok(where .. ": " .. op, a)
			elseif t == "phase" and not G.phase_by_key[a] then
				warn("%s: '%s' points at phase '%s', but no phase has that key%s",
					where, op, a, suggest(a, G.phase_by_key))
			elseif t == "effect" and not (G.effect_defs or {})[a] then
				warn("%s: '%s' plays the effect '%s', but the game defines no such effect%s",
					where, op, a, suggest(a, G.effect_defs))
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
			if w == "count" and p[j + 1] and not known_tags[p[j + 1]] then
				warn("%s: counts the tag '%s', but no card has it%s",
					where, p[j + 1], suggest(p[j + 1], known_tags))
			end
			if w == "card" and j > 1 and p[j + 1] and not G.card_defs[p[j + 1]] then
				warn("%s: checks for the card '%s', but no template has that key%s",
					where, p[j + 1], suggest(p[j + 1], G.card_defs))
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
			warn('%s: should be a list of actions like ["gain_stat:gold:1"], not a single value', where)
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
			if G.computed_tags[tag] then
				warn("%s: is defined under both 'tags' and 'computed_tags' — computed tags can't carry behaviour", where)
			end
			if not carried_tags[tag] then
				warn("%s: has behaviour defined, but no card carries this tag%s",
					where, suggest(tag, carried_tags))
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

	-- Computed tags.
	for tag, def in pairs(G.computed_tags) do
		local where = "computed tag '" .. tostring(tag) .. "'"
		if type(def) ~= "table" then
			warn('%s: should be written like { "stat": "hp", "equals": "0" }', where)
		else
			check_fields(where, def, COMPUTED_FIELDS)
			if def.stat and not card_stats[def.stat] then
				warn("%s: reads the card stat '%s', but no card carries it%s",
					where, tostring(def.stat), suggest(def.stat, card_stats))
			end
		end
	end

	-- Cards.
	for key, def in pairs(G.card_defs) do
		local where = "card '" .. key .. "'"
		check_fields(where, def, CARD_FIELDS)
		if def.asset and tostring(def.asset):match("^https?://") then
			if not url_is_safe(def.asset) then
				warn("%s: its image URL contains characters that aren't valid in a URL — it will be refused at load time",
					where)
			end
		elseif def.asset and not love.filesystem.read("games/assets/" .. tostring(def.asset)) then
			warn("%s: its image '%s' is not in games/assets", where, tostring(def.asset))
		end
		if def.outcome and def.outcome ~= "victory" and def.outcome ~= "defeat" then
			warn("%s: outcome should be 'victory' or 'defeat', not '%s'%s",
				where, tostring(def.outcome), suggest(def.outcome, { victory = true, defeat = true }))
		end
		if def.tags ~= nil and type(def.tags) ~= "table" then
			warn('%s: tags should be a list like ["item", "weapon"]', where)
		end
		check_map(where .. " cost", def.cost, true)
		check_map(where .. " activate_cost", def.activate_cost, true)
		check_map(where .. " needs", def.needs)
		check_map(where .. " requires", def.requires)
		-- card_stats declare new per-card stats, so only their values are checked.
		if def.card_stats ~= nil then
			if type(def.card_stats) ~= "table" then
				warn('%s: card_stats should be written like { "hp": 3, "hp_max": 3 }', where)
			else
				for k, v in pairs(def.card_stats) do
					if type(v) ~= "number" then
						warn("%s card_stats: the value of '%s' should be a number", where, tostring(k))
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
		check_list(where .. " on_pick", def.on_pick)

		-- "target" gates playing the card, "activate_target" its board ability;
		-- same shape, same checks.
		for _, field in ipairs({ "target", "activate_target" }) do
			local spec = def[field]
			if type(spec) == "table" then
				check_fields(where .. " " .. field, spec, TARGET_FIELDS)
				if spec.type and spec.type ~= "card" and spec.type ~= "slot" then
					warn("%s %s: type should be 'card' or 'slot', not '%s'", where, field, tostring(spec.type))
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
			end
		end

		if def.activate_target and not def.on_activate then
			warn("%s: has an activate_target but no on_activate — there is no ability for it to target", where)
		end
		if def.exhausts ~= nil and type(def.exhausts) ~= "boolean" then
			warn("%s: exhausts should be true or false, not '%s'", where, tostring(def.exhausts))
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
		if #homes == 0 and (bare_move(def.on_play) or bare_move(def.on_pick)
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
			warn("%s: '%s' is not a zone type (deck, pile, hand or grid)%s",
				where, tostring(def.type), suggest(def.type, ZONE_TYPES))
		end
		check_numbers(where, "pos", def.pos, 4)
		if def.fit ~= nil and def.fit ~= "card" and def.fit ~= "fill" then
			warn("%s: fit should be 'card' or 'fill', not '%s'", where, tostring(def.fit))
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
		check_list(where .. " on_click", def.on_click)
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
		if pd.zone and not G.zone_defs[pd.zone] then
			warn("%s: deals into '%s', but no zone has that key%s", where, tostring(pd.zone), suggest(pd.zone, G.zone_defs))
		end
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
		if pd.actions and pd.type ~= "automatic" then
			warn("%s: has 'actions', but only automatic phases run them", where)
		end
		if pd.on_pick and pd.type ~= "overlay" then
			warn("%s: has 'on_pick', but only overlay phases use it", where)
		end
		check_list(where .. " actions", pd.actions)
		check_list(where .. " on_pick", pd.on_pick)
		if pd.next then
			if type(pd.next) ~= "table" then
				warn("%s: next should be a list of routes", where)
			elseif pd.type == "overlay" then
				warn("%s: has routing, but overlays pop back — the routing never runs", where)
			else
				if pd.type == "automatic" then
					local fallback = false
					for _, r in ipairs(pd.next) do
						if r.stat == nil and r.zone_empty == nil then fallback = true end
					end
					if not fallback then
						warn("%s: is automatic but every route has a condition — when none matches, the game stalls", where)
					end
				end
				local saw_unconditional = false
				for i, r in ipairs(pd.next) do
					local rwhere = where .. " next[" .. i .. "]"
					check_fields(rwhere, r, ROUTE_FIELDS)
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
					if r.stat == nil and r.zone_empty == nil then
						saw_unconditional = true
					else
						check_cond(rwhere, r)
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
		check_fields(where, cond, END_FIELDS)
		check_cond(where, cond)
		check_list(where, cond["then"])
		if cond["then"] == nil then
			warn("%s: has no 'then' — nothing happens when it fires", where)
		end
	end

	-- Setup.
	if G.setup then
		check_fields("setup", G.setup, { player = true })
		for k, v in pairs(type(G.setup.player) == "table" and G.setup.player or {}) do
			if type(v) ~= "number" then
				warn("setup: the starting value of '%s' should be a number", tostring(k))
			end
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
