-- Load-time content checks. Returns a list of problem strings; the engine
-- prints them and plays on — content errors warn, they never kill the game.
-- Messages are written for game authors, not programmers: they name the
-- entry, say what the engine expected, and suggest the nearest valid word.
-- Conflicts (duplicate keys, tags that disagree, ambiguous placement) are
-- called out explicitly. The test suite asserts that shipped games validate
-- clean.

local actions = require("actions")

local M = {}

local RESERVED = { round = true, plays = true }

-- Fields the engine reads on each kind of entry (including the derived ones
-- declaration.parse adds). Anything else is almost certainly a typo.
local CARD_FIELDS = {
	key = true, text = true, tooltip = true, story = true, asset = true,
	color = true, tags = true, card_stats = true, cost = true,
	activate_cost = true, needs = true, requires = true, target = true,
	on_play = true, on_activate = true, on_turn = true, on_pass = true,
	on_fail = true, on_pick = true, auto_play = true, to_zone = true,
	to_slot = true, irreversible = true, tags_set = true,
}
local ZONE_FIELDS = {
	key = true, label = true, type = true, pos = true, grid = true,
	contents = true, on_click = true, tags = true, tags_set = true,
}
local PHASE_FIELDS = {
	key = true, label = true, type = true, actions = true, deck = true,
	draw = true, zone = true, pass_card = true, on_pick = true, next = true,
	page = true,
}
local STAT_FIELDS     = { key = true, label = true, min = true, max = true, hidden = true }
local TAG_FIELDS      = { zone = true }
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
	local known_tags = {}
	for _, def in pairs(G.card_defs) do
		if type(def.tags) == "table" then
			for _, t in ipairs(def.tags) do known_tags[t] = true end
		end
	end
	for t in pairs(G.computed_tags) do known_tags[t] = true end
	for t in pairs(tag_defs) do known_tags[t] = true end

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

	local grids = {}
	for key, zd in pairs(G.zone_defs) do
		if zd.type == "grid" then grids[#grids + 1] = key end
	end
	table.sort(grids)

	local function stat_ok(key)
		return all_stats[key] ~= nil
	end

	-- A condition subject: stat, count:<tag> or card:<key>.
	local function subject_ok(where, key)
		local tag = tostring(key):match("^count:(.+)$")
		local ck  = tostring(key):match("^card:(.+)$")
		if tag then
			if not known_tags[tag] then
				warn("%s: counts the tag '%s', but no card has it%s", where, tag, suggest(tag, known_tags))
			end
		elseif ck then
			if not G.card_defs[ck] then
				warn("%s: checks for the card '%s', but no template has that key%s",
					where, ck, suggest(ck, G.card_defs))
			end
		elseif not stat_ok(key) then
			warn("%s: uses the stat '%s', but it is never declared or set up%s",
				where, tostring(key), suggest(key, all_stats))
		end
	end

	local function check_map(where, map, allow_counts)
		if map == nil then return end
		if type(map) ~= "table" then
			warn('%s: should be written like { "gold": 2 }', where)
			return
		end
		for key, v in pairs(map) do
			if allow_counts then
				subject_ok(where, key)
			elseif not stat_ok(key) then
				warn("%s: uses the stat '%s', but it is never declared or set up%s",
					where, tostring(key), suggest(key, all_stats))
			end
			if type(v) ~= "number" then
				warn("%s: the value of '%s' should be a number", where, tostring(key))
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

	-- Action strings: op exists, referenced keys exist, count:/card: known.
	local ZONE_ARGS = {
		fill = { 2 }, shuffle = { 2 }, destroy = { 2 }, move_to = { 2 },
		add_to = { 2 }, move_target_to = { 2 }, draw_from = { 2, 3 },
		return_to = { 2, 3 }, reveal_top = { 2 },
	}
	local known_ops = actions.ops()
	local function check_action(where, str)
		local p = {}
		for w in str:gmatch("[^:]+") do p[#p + 1] = w end
		local op = p[1]
		if not actions.known(op) then
			warn("%s: '%s' is not an action the engine knows%s", where, tostring(op), suggest(op, known_ops))
			return
		end
		for _, i in ipairs(ZONE_ARGS[op] or {}) do
			if p[i] and not G.zone_defs[p[i]] then
				warn("%s: '%s' points at zone '%s', but no zone has that key%s",
					where, op, p[i], suggest(p[i], G.zone_defs))
			end
		end
		if (op == "fill" or op == "gain" or op == "reveal") then
			local ci = op == "fill" and 3 or 2
			if not G.card_defs[p[ci] or ""] then
				warn("%s: '%s' names the card '%s', but no template has that key%s",
					where, op, tostring(p[ci]), suggest(p[ci], G.card_defs))
			end
		end
		if op == "push_phase" and not G.phase_by_key[p[2] or ""] then
			warn("%s: push_phase to '%s', but no phase has that key%s",
				where, tostring(p[2]), suggest(p[2], G.phase_by_key))
		end
		if (op == "gain_stat" or op == "lose_stat" or op == "spend_stat" or op == "set_stat")
			and p[2] and not stat_ok(p[2]) then
			warn("%s: %s of '%s', but that stat is never declared or set up%s",
				where, op, p[2], suggest(p[2], all_stats))
		end
		if (op == "gain_target_stat" or op == "lose_target_stat")
			and p[2] and not (card_stats[p[2]] or stat_ok(p[2])) then
			warn("%s: %s of '%s', but no card carries that stat", where, op, p[2])
		end
		for i, w in ipairs(p) do
			if w == "count" and p[i + 1] and not known_tags[p[i + 1]] then
				warn("%s: counts the tag '%s', but no card has it%s",
					where, p[i + 1], suggest(p[i + 1], known_tags))
			end
			if w == "card" and i > 1 and p[i + 1] and not G.card_defs[p[i + 1]] then
				warn("%s: checks for the card '%s', but no template has that key%s",
					where, p[i + 1], suggest(p[i + 1], G.card_defs))
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
			local carried = false
			for _, def in pairs(G.card_defs) do
				if def.tags_set and def.tags_set[tag] then carried = true break end
			end
			if not carried then
				warn("%s: has behaviour defined, but no card carries this tag", where)
			end
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
		if def.tags ~= nil and type(def.tags) ~= "table" then
			warn('%s: tags should be a list like ["item", "weapon"]', where)
		end
		check_map(where .. " cost", def.cost)
		check_map(where .. " activate_cost", def.activate_cost)
		check_map(where .. " needs", def.needs, true)
		check_map(where .. " requires", def.requires, true)
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

		if type(def.target) == "table" then
			check_fields(where .. " target", def.target, TARGET_FIELDS)
			if def.target.type and def.target.type ~= "card" and def.target.type ~= "slot" then
				warn("%s target: type should be 'card' or 'slot', not '%s'", where, tostring(def.target.type))
			end
			for _, t in ipairs(type(def.target.tags) == "table" and def.target.tags or {}) do
				if not known_tags[t] then
					warn("%s target: looks for the tag '%s', but no card has it%s", where, t, suggest(t, known_tags))
				end
			end
			for _, zk in ipairs(type(def.target.zones) == "table" and def.target.zones or {}) do
				if not G.zone_defs[zk] then
					warn("%s target: searches zone '%s', but no zone has that key%s", where, zk, suggest(zk, G.zone_defs))
				end
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
		if def.type == "grid" then
			if def.grid == nil then
				warn('%s: a board needs "grid": [columns, rows]', where)
			else
				check_numbers(where, "grid", def.grid, 2)
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
