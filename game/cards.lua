local entity      = require("entity")
local declaration = require("declaration")
local json        = require("json")
local art         = require("art")

local M = {}

local EMPTY = {}

-- The look a card's tags add up to: every style they name, merged. Two styles
-- claiming the same property is an authoring conflict the validator reports, so
-- nothing here has to invent a winner.
--
-- The definition tags are merged once at load (`def.style`). Only a style word
-- that is also a *computed* tag can change while the game runs, and the parse
-- knows which those are — so a game with none returns the cached table and pays
-- nothing, and one with them pays only for the entities carrying them.
function M.style(e)
	local G    = declaration.G
	local def  = e and M.def(e)
	local base = (def and def.style) or EMPTY
	local dyn  = G.dynamic_styles
	if not e or not dyn or #dyn == 0 then return base end
	local out
	for _, name in ipairs(dyn) do
		if require("tags").entity_has(e, name) then
			if not out then
				out = {}
				for k, v in pairs(base) do out[k] = v end
			end
			local sd = G.style_defs[name]
			for k, v in pairs(sd) do
				if k ~= "hide" then out[k] = v end
			end
			-- "hide" unions rather than replacing, as it does at load. The set is
			-- copied first: the base style's is cached and shared by every card
			-- of that definition, and writing into it would hide a part on all
			-- of them the moment one wore the computed tag.
			if sd.hide then
				local h = {}
				for word in pairs(out.hide or {}) do h[word] = true end
				out.hide = h
				declaration.merge_hide(out, sd.hide)
			end
		end
	end
	return out or base
end

-- Image cache: def_key → love.graphics.Image or false
local img_cache = {}
-- Web-asset fetches in flight: url id -> job. The two platforms keep different
-- shapes in here ({ at = last poll } in the browser, { thread, channel } on the
-- desktop) and share the table safely only because exactly one of them ever
-- runs — see the branch in M.asset_image.
local pending   = {}
-- How far along its list of sources each key has got. Without it a chain whose
-- first source is a host that refuses us would ask that host again every frame,
-- for as long as the card is on screen.
local chain_at  = {}

-- Strict allowlist for URLs that get spliced into a generated JS program
-- (see fetch_browser below): only the characters RFC 3986 actually permits
-- unencoded in a URL. This is the real defense, not the escaping further
-- down — it outright refuses anything containing a quote, backslash, angle
-- bracket, raw whitespace/control byte, or non-ASCII byte (which includes
-- the U+2028/U+2029 line separators JS string literals forbid raw), so
-- there is no character left that could ever break out of the string
-- literal it's placed in. A malformed/suspicious asset is treated exactly
-- like a missing one — refused, not "cleaned up".
local URL_SAFE_PATTERN = "^https?://[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]+$"

function M.url_is_safe(url)
	return type(url) == "string" and #url > 0 and #url < 2000
		and url:match(URL_SAFE_PATTERN) ~= nil
end

function M.reset()
	img_cache = {}
	pending   = {}
	chain_at  = {}
end

-- Give a card a stat it does not have yet, from what the game file wrote.
--
-- A number is a bare current value. A card that carries its own bounds writes
-- them by name, in the same words the "stats" entry uses:
--
--   "hp": 4                              current 4, bounds as the stat declares
--   "hp": { "value": 4, "max": 4 }       current 4, its own ceiling of 4
--   "hp": { "value": 4, "min": 0, "max": 4 }
--
-- The bound left out is whatever the global "stats" entry says, and nothing if
-- it says nothing — so a card only writes one it actually differs on.
--
-- **It used to be a list**, `[current, max]` or `[min, current, max]`, which is
-- a rule a reader had to be taught and could not check: the middle is the
-- value, and the middle of two is the first. Named, it says itself. Nothing in
-- the format is positional now except a zone's `pos`, which is a rectangle.
--
-- **The three live in three tables, and only this function knows that.** A
-- stat is read as `e.stats[key]` everywhere it was before; the ceiling and the
-- floor sit beside it rather than inside it, which is what stops "hp_max" being
-- a stat in its own right that conditions count, actions spend and a tooltip
-- lists as if the player had one point of maximum.
--
-- Untrusted content: every value is coerced to a real number here so nothing
-- downstream can be tricked into arithmetic on a string or a table.
function M.attach_stat(e, key, value)
	local lo, cur, hi
	if type(value) == "table" then
		cur, lo, hi = tonumber(value.value), tonumber(value.min), tonumber(value.max)
	else
		cur = tonumber(value)
	end
	e.stats[key] = cur or 0
	if hi then e.stat_max[key] = hi end
	if lo then e.stat_min[key] = lo end
end

function M.create(def_key, zone_id)
	local def = declaration.G.card_defs[def_key]
	assert(def, "Unknown card def: " .. tostring(def_key))
	local e = {
		kind      = "card",
		def_key   = def_key,
		zone_id   = zone_id,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		stats     = {},    -- per-entity stats: the current value of each
		stat_max  = {},    -- the ceiling of each, where one was declared
		stat_min  = {},    -- the floor of each, where one was declared
		parent_id = nil,   -- set when attached to another card
		attached  = {},    -- IDs of cards attached to this card
	}
	if def.card_stats then
		for k, v in pairs(def.card_stats) do M.attach_stat(e, k, v) end
	end
	entity.register(e)
	local zone = entity.get(zone_id)
	-- **A card is born owned, and stays owned.** Ownership is a property of the
	-- card, not of wherever it happens to be lying: dealt out of a seat's own
	-- deck, it is that seat's through the hand, the board and the discard, and
	-- only something that says so in as many words takes it away. Derived from
	-- the zone instead, it was a fact that evaporated the moment a card was
	-- played onto a shared board — which is where "a board can be shared while
	-- the pieces on it are not" quietly stopped being true.
	--
	-- A card created in a shared zone has no owner and never gains one by
	-- moving, which is what keeps a discard pile a discard pile: Lost Cities
	-- deals from one shared deck, so either player may take from either pile.
	-- setup.place writes its own owner straight after this, and so does
	-- transform, so an explicit answer still wins.
	if zone and zone.seat then
		e.stats.owner = (declaration.G.seat_index or {})[zone.seat]
	end
	if zone then table.insert(zone.cards, e.id) end
	return e
end

function M.def(card_entity)
	return declaration.G.card_defs[card_entity.def_key]
end

-- What an ability says when it meets the others on the same card. Written on the
-- ability, not on the zone that granted it: the zone's whole say is naming the
-- tag in "applies", and a card's *own* tag needs the same word — "this card's
-- abilities do not work" is the same conflict with no zone anywhere in it.
--
--   both   the default, and what every ability said before this existed
--   this   mine alone; the rest of the card goes quiet
--   other  mine only when the card offers nothing else
--
-- Two abilities claiming "this" is a contradiction, and the validator says so.
-- At runtime both survive and the player is asked, because a card that offers
-- two things is a visible mistake and a card that silently lost one is not.
local function merged(list)
	local keep = {}
	for _, a in ipairs(list) do if a.merge == "this" then keep[#keep + 1] = a end end
	if #keep > 0 then return keep end
	for _, a in ipairs(list) do if a.merge ~= "other" then keep[#keep + 1] = a end end
	-- Nothing but understudies: they are the card's whole repertoire, so they play.
	if #keep == 0 then return list end
	return keep
end

-- Every activated ability this card has right now: its own, then any its zone
-- hands out. **Added, not substituted** unless one of them says otherwise — a
-- zone that grants an ability used to hide the card's own, so a rook lying in a
-- discard pile could be taken and no longer moved. One card can do two things,
-- and the player is asked which. A shop is the case that wants the old
-- behaviour back: a chip lying in the bank is merchandise, and its own upkeep
-- paying out on a click is money from the shop window. That is what "merge"
-- is for, and why adding stayed the default.
-- Everything this card can do, in the order it is asked.
--
--   1. its own, written on the card
--   2. what lying *here* lets it do, from the zone's "applies"
--   3. what its own tags give it — its keywords
--
-- **Keywords come last on purpose.** A keyword is usually an addition to
-- whatever else applies, and one that changes an *outcome* has to run after the
-- outcome: Overwhelm sends the damage past a dead blocker onwards, and there is
-- nothing to send until the blocker has been struck.
--
-- Precedence is settled here rather than in the callers that ask what is usable,
-- so it says what a card *is* where it lies and not what it can afford this
-- instant: merchandise stays merchandise to a player who cannot buy it.
function M.abilities(card_entity)
	local out = {}
	local def = M.def(card_entity)
	for _, a in ipairs((def and def.abilities) or EMPTY) do out[#out + 1] = a end
	local z = card_entity and card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		for _, a in ipairs((td and td.abilities) or EMPTY) do out[#out + 1] = a end
	end
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		for _, a in ipairs((td and td.abilities) or EMPTY) do out[#out + 1] = a end
	end
	-- **And what it is doing right now.** A computed tag is worn the same way a
	-- printed one is, so the abilities under its name reach the same cards — the
	-- difference is only that the wearing comes and goes. That is how a keyword
	-- is *granted*: say what the keyword does once, under its name, and let a
	-- condition decide who is wearing it.
	--
	-- Last, and after the card's own, so an index into this list is stable for
	-- everything that does not depend on the board. It still moves when the
	-- condition flips, which is the same thing a zone's "applies" already does
	-- and the reason a menu entry carries the index it meant.
	for _, tag in ipairs(declaration.G.computed_list or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		if td and td.abilities and #td.abilities > 0 and require("tags").entity_has(card_entity, tag) then
			for _, a in ipairs(td.abilities) do out[#out + 1] = a end
		end
	end
	return merged(out)
end

-- **What a card will let be aimed at it**, from all four places anything else
-- about it comes from: its own `receive`, its zone's `applies`, its own tags,
-- and the computed tags it is wearing. A list of conditions is an *and*, so
-- several wards are several gates and the order they are gathered in says
-- nothing.
--
-- It read only the card's own block until now, which is why "cannot be targeted
-- by spells" had to be written on every card that has it rather than once on the
-- keyword, and why nothing could ever grant it.
-- **Blocks and not one flat condition list**, for the reason `on_receive` below
-- gives about its own: each source brought its own side. Codex's Invisible is
-- "to opponents without a detector" and its Untargetable is "can't be the target
-- of spells or abilities" -- one card may wear both, and flattening them would
-- hold every aim to both sides' gates or to neither.
function M.accepts(card_entity)
	local out = {}
	local function take(d)
		if d and d.accepts and #d.accepts > 0 then
			out[#out + 1] = { whose = d.receive_whose, needs = d.accepts }
		end
	end
	local def = M.def(card_entity)
	take(def)
	local z = card_entity and card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or EMPTY) do take(declaration.G.tag_defs[tag]) end
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		take(declaration.G.tag_defs[tag])
	end
	for tag in pairs(declaration.G.computed_tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		if td and td.accepts and require("tags").entity_has(card_entity, tag) then take(td) end
	end
	return out
end

-- **What a card does about having been aimed at**, gathered from the same four
-- places as `accepts` above, because the two are one word's two halves: `accepts`
-- answers whether the aim may be made and this answers the aim that was. A zone
-- has had both since it had either; a card and a tag had only the first, which
-- is why an Illusion could refuse to be pointed at and could not die of it.
--
-- **Blocks and not one flat action list**, because each source brought its own
-- `when`: "dies to a spell" and "disabled by anything" are two keywords one card
-- may wear at once, and flattening them would run both gates or neither.
--
-- Unlike `accepts` the order is load-bearing — these are actions and they run in
-- sequence — so it is the order a reader would guess: the card's own block, then
-- what its zone lends it, then its printed keywords, then what it is wearing
-- right now.
function M.on_receive(card_entity)
	local out = {}
	local function take(d)
		if d and d.on_receive then
			out[#out + 1] = { whose = d.receive_whose, needs = d.on_receive_needs, action = d.on_receive }
		end
	end
	local def = M.def(card_entity)
	take(def)
	local z = card_entity and card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or EMPTY) do take(declaration.G.tag_defs[tag]) end
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		take(declaration.G.tag_defs[tag])
	end
	-- Sorted, unlike the gather above it: a list of conditions is an and and the
	-- order says nothing, while two computed keywords that both act would run in
	-- whatever order pairs felt like and a replay would not match itself.
	local worn = {}
	for tag in pairs(declaration.G.computed_tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		if td and td.on_receive and require("tags").entity_has(card_entity, tag) then worn[#worn + 1] = tag end
	end
	table.sort(worn)
	for _, tag in ipairs(worn) do take(declaration.G.tag_defs[tag]) end
	return out
end

-- Every reaction a card carries, in the order it is asked. Its own, written on
-- the card, come first; tag-granted and zone-applied reactions are a later
-- refinement (a keyword that reacts, a zone that makes what lies in it react).
function M.reactions(card_entity)
	local out = {}
	local def = M.def(card_entity)
	for _, r in ipairs((def and def.reactions) or EMPTY) do out[#out + 1] = r end
	return out
end

-- Every verb this card announces at one moment ("play", "activate"): its own, its
-- zone's through "applies", and its tags'. A tag is the useful place to write one
-- — "spell" says cast once, for the whole game — and these are the same three
-- sources abilities come from, for the same reason.
--
-- Asked per moment, because a card is often answered as two different things. A
-- spell that resolves onto the board and is used from there is a cast when it is
-- played and something else entirely when it is activated, and the two must not
-- be confused for each other. Verbs from several sources at one moment all count:
-- a creature spell is a cast and a summon both, and nothing has to choose.
function M.emits(card_entity, moment)
	local out, seen = {}, {}
	local function take(map)
		for _, v in ipairs((map or EMPTY)[moment] or EMPTY) do
			if not seen[v] then seen[v] = true; out[#out + 1] = v end
		end
	end
	local def = M.def(card_entity)
	take(def and def.emits)
	local z = card_entity and card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or EMPTY) do
		take((declaration.G.tag_defs[tag] or EMPTY).emits)
	end
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		take((declaration.G.tag_defs[tag] or EMPTY).emits)
	end
	return out
end

-- Only what the zone a card lies in hands it, through "applies". Prose wants
-- this on its own: "advance the expedition" and "take this into your hand"
-- describe different acts, and the tooltip shows both.
function M.zone_grant(card_entity, field)
	local z = card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or {}) do
		local td = declaration.G.tag_defs[tag]
		if td and td[field] ~= nil then return td[field] end
	end
end

-- What a card does *here*. Where a card is decides what it can do, so the zone
-- answers first and the card's own definition answers when the zone says
-- nothing: a creature lying in a graveyard that grants "return to hand" offers
-- that, not the tap ability it had on the board. There is no card-wins rule
-- behind it — a card and its zone defining the same behaviour is an authoring
-- conflict, which the validator reports rather than silently picking a winner.
--
-- Deliberately not folded into def(): that is a bare table lookup on the
-- per-frame path for render, targeting, costs and tooltips, and it must stay
-- one. Only the handful of sites that ask "can this be used" come through here.
function M.behaviour(card_entity, field)
	local granted = M.zone_grant(card_entity, field)
	if granted ~= nil then return granted end
	local def = M.def(card_entity)
	return def and def[field]
end

-- What a card's *own* tags say about it, in the order the card wrote them.
--
-- A keyword is a tag with a meaning, and the meaning belongs in one place: the
-- game says once what Tough does and every card that has it inherits the
-- sentence, instead of thirty templates each carrying their own copy for
-- somebody to keep in step. The tag itself is what the *rules* read; this is
-- only what a player reads.
--
-- Distinct from zone_grant, which answers for tags a zone hands out through
-- "applies" — that is what a card can do *here*, and this is what it is
-- everywhere.
function M.keywords(card_entity)
	local out = {}
	local def = M.def(card_entity)
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		if td and type(td.tooltip) == "string" and td.tooltip ~= "" then
			out[#out + 1] = { tag = tag, text = td.tooltip }
		end
	end
	-- **And what it is wearing at the moment.** A granted keyword is the one a
	-- player most needs told, because it is not printed anywhere on the card:
	-- the sentence is written once under the tag that grants it, and the card
	-- shows it for as long as the condition holds. Marked, so the panel can say
	-- it was lent rather than printed.
	for tag in pairs(declaration.G.computed_tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		if td and type(td.tooltip) == "string" and td.tooltip ~= ""
			and require("tags").entity_has(card_entity, tag) then
			out[#out + 1] = { tag = tag, text = td.tooltip, granted = true }
		end
	end
	return out
end

-- The zone a card's tags call home, or nil when none does.
--
-- It reads the boolean map rather than the authored list, because there is
-- nothing here to order — and when two tags disagree, which the validator
-- reports, the answer is **nothing** rather than whichever the file happened to
-- write first. An ambiguous home is no home: the callers' fallbacks say what
-- they do, where a precedence nobody wrote down would only look decided.
function M.home_zone(def)
	local home
	for t in pairs(def.tags_set or {}) do
		local td = declaration.G.tag_defs[t]
		if td and td.zone then
			if home and home ~= td.zone then return nil end
			home = td.zone
		end
	end
	return home
end

-- The zone a card's tags send it to when it dies, or nil when none does.
--
-- Read the same way home_zone is, and ambiguous for the same reason: two tags
-- naming different graves is a card with no settled answer, so it falls through
-- to the zone and the seat rather than taking whichever was written first.
function M.grave_zone(def)
	local grave
	for t in pairs(def.tags_set or {}) do
		local td = declaration.G.tag_defs[t]
		if td and td.grave then
			if grave and grave ~= td.grave then return nil end
			grave = td.grave
		end
	end
	return grave
end

-- Overwrite instance stats with the template's card_stats. Used when a
-- template's stats change: immediate dev feedback beats preserving damage.
local function restamp(def_key, card_stats)
	for e in entity.each("card") do
		-- skip purged husks (no zone): they must stay stat-less
		if e.def_key == def_key and e.zone_id then
			e.stats, e.stat_max, e.stat_min = {}, {}, {}
			for k, v in pairs(card_stats or {}) do M.attach_stat(e, k, v) end
		end
	end
end

-- Edit a card template in place, for live development. Instances only hold a
-- def_key, so every one of them reflects the change immediately. `raw` is
-- parsed as JSON; if that fails it's taken as a plain string. "null" clears
-- the field.
function M.edit(def_key, field, raw)
	local def = declaration.G.card_defs[def_key]
	if not def then return false, "unknown card: " .. tostring(def_key) end
	-- Scenery is not content. The menu is a game like any other, which means the
	-- live-edit tools point straight at it; "immutable" is how a card says it is
	-- part of the furniture and must not be rewritten under the player.
	if def.tags_set and def.tags_set.immutable then
		return false, "immutable card: " .. tostring(def_key)
	end
	local ok, value = pcall(json.decode, raw)
	if not ok then value = raw end
	def[field] = value
	if field == "tags" then
		def.tags_set = {}
		if type(value) == "table" then
			for _, t in ipairs(value) do def.tags_set[t] = true end
		end
	elseif field == "card_stats" then
		restamp(def_key, value)
	elseif field == "asset" then
		img_cache[def_key] = nil
	end
	return true
end

-- Copy of a template without derived fields, for dumps and the debug API.
function M.template(def_key)
	local def = declaration.G.card_defs[def_key]
	if not def then return nil, "unknown card: " .. tostring(def_key) end
	local copy = {}
	for k, v in pairs(def) do
		if k ~= "tags_set" then copy[k] = v end
	end
	return copy
end

-- Template as pretty JSON, ready to paste back into the game file.
function M.dump(def_key)
	local copy, err = M.template(def_key)
	return copy and json.encode(copy, true), err
end

local function stats_equal(a, b)
	a, b = a or {}, b or {}
	for k, v in pairs(a) do
		local w = b[k]
		-- A card carrying its own bounds writes a table, and two parses of the
		-- same file never produce the same one — so comparing them by identity
		-- restamped those cards on every reload and put their live hp back.
		if type(v) == "table" then
			if not (type(w) == "table" and w.value == v.value and w.min == v.min and w.max == v.max) then
				return false
			end
		elseif w ~= v then
			return false
		end
	end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Re-read templates from the current game file: edit the JSON in your editor,
-- reload, keep playing. Only template-ish data is swapped — zones and phases
-- are structural and need a full game load. Instances whose card_stats
-- changed on disk are re-stamped.
function M.reload()
	local ok, fresh = pcall(declaration.parse, declaration.filename)
	if not ok then return false, fresh end
	local G = declaration.G
	for key, def in pairs(fresh.card_defs) do
		local old = G.card_defs[key]
		if not (old and stats_equal(old.card_stats, def.card_stats)) then
			restamp(key, def.card_stats)
		end
	end
	for _, k in ipairs(declaration.TEMPLATE_FIELDS) do G[k] = fresh[k] end
	img_cache = {}
	return true
end

-- A condition as prose. "gold >= 3" is exact and is written for the game file;
-- a tooltip is read by somebody who has never seen one, so the operator becomes
-- a phrase and the two operands swap into English order.
local WORDS = { [">="] = "at least ", ["<="] = "at most ", [">"] = "more than ",
	["<"] = "fewer than ", ["=="] = "exactly ", ["!="] = "anything but " }

local function condition_text(s)
	-- Required here rather than at the top: predicate reaches zones, and zones
	-- reaches this file. The parse is pure, so late is as good as early.
	local c = require("predicate").parse_condition(s)
	if not c then return tostring(s) end
	return WORDS[c.op] .. (c.right.src or tostring(c.right.n)) .. " " .. (c.left.src or tostring(c.left.n))
end

-- What one entry of a cost comes to. **A cost amount may be a subject rather
-- than a number** — `"price@self"` is a card charging what is printed on it,
-- which is the only way one `play` block can serve ninety cards that cost
-- different things — and everything that *spends* a cost has always measured it.
-- Everything that *shows* one printed the string, so a card whose price was
-- measured wore the expression on its face. Measured against the card the cost
-- is about, since `@self` names it; with no card to ask, the expression is all
-- there is to say.
function M.cost_amount(v, card_id, rule)
	if type(v) ~= "string" or not card_id then return v end
	local predicate = require("predicate")
	-- Bound the same way flow does before it pays, so the number quoted in a
	-- hand is the number that comes out of the pile. A price with arithmetic in
	-- it is a compute the block named, and reading it with nothing bound made it
	-- nought — right in the file, wrong on the card.
	local c   = entity.get(card_id)
	local ctx = predicate.bind((rule and rule.compute) or (c and M.behaviour(c, "compute")),
		{ card_id = card_id })
	return predicate.total(v, ctx)
end

-- "2 gold, 1 food" for a cost, "at least 3 gold" for a condition. One function
-- because one tooltip row shows either: a cost is a map of what gets spent, and
-- `needs` / `accepts` are lists of conditions.
function M.cost_text(cost, card_id, rule)
	local parts = {}
	if type(cost) ~= "table" then return "" end
	if type(cost[1]) == "string" then
		for _, s in ipairs(cost) do parts[#parts + 1] = condition_text(s) end
		return table.concat(parts, ", ")
	end
	local keys = {}
	for k in pairs(cost) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local tag = k:match("^sacrifice:(.+)$")
		local n   = tostring(M.cost_amount(cost[k], card_id, rule))
		parts[#parts + 1] = tag and ("sacrifice " .. n .. " " .. tag) or (n .. " " .. k)
	end
	return table.concat(parts, ", ")
end

-- Web assets ("asset": "https://...") are fetched at runtime and held only
-- in the in-memory cache above — the engine never writes them to its own
-- filesystem. Desktop decodes straight from the socket response. The
-- browser build (love.js) has no sockets, so instead it asks the real
-- browser to fetch the URL with its own fetch() — the caller's actual
-- session (HTTP cache, CORS) — via the love.js.eval bridge, and
-- polls for the result; a cross-origin host without permissive CORS
-- headers will still fail, same as it would for a plain <img> tag.

local function js_escape(s)
	s = tostring(s):gsub("\\", "\\\\")
	s = s:gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
	return s
end

local id_cache = {}

local function url_id(url)
	local cached = id_cache[url]
	if cached then return cached end
	local h = 5381
	for i = 1, #url do h = (h * 33 + url:byte(i)) % 4294967296 end
	cached = string.format("%08x", h)
	id_cache[url] = cached
	return cached
end

-- Build an Image directly from a byte string, no disk involved. Returns the
-- Image, or nil and what went wrong: the failures used to arrive as one silent
-- nil, and in the browser they mean very different things.
--
-- ByteData first, and love.filesystem only as a fallback: love.js's normalize
-- shim wraps love.filesystem.newFileData and answers nil where desktop LÖVE
-- answers a FileData, which is how a perfectly good 2 MB JPEG arrived intact
-- and became "no image" in the browser and nowhere else. love.data is not
-- wrapped, and newImage takes any Data.
local function image_from_bytes(bytes)
	local head = (bytes:sub(1, 4):gsub(".", function(c) return string.format("%02X ", c:byte()) end))
	local data, why
	if love.data and love.data.newByteData then
		local ok, d = pcall(love.data.newByteData, bytes)
		data, why = ok and d or nil, (not ok) and tostring(d) or "newByteData answered nil"
	end
	if not data then
		local ok, d = pcall(love.filesystem.newFileData, bytes, "asset")
		data = ok and d or nil
		why = (not ok) and tostring(d) or why or "newFileData answered nil"
	end
	if not data then return nil, "no Data could be made from the bytes: " .. tostring(why) end
	local ok2, img = pcall(love.graphics.newImage, data)
	if not ok2 then
		return nil, ("newImage refused it (%s), first bytes %s, lua heap %d KB")
			:format(tostring(img), head, collectgarbage("count"))
	end
	return img
end

-- Desktop: the request runs on a worker thread, because it used to run inside
-- love.draw — a card with a slow host froze the frame for as long as the
-- socket took (and LÖVE 12's https module takes no timeout at all). LÖVE
-- threads get their own Lua state, so the worker requires what it needs and
-- hands back raw bytes; only the main thread may build an Image.
local FETCH_SOURCE = [[
local url, channel = ...
require("love.thread")
local body
if url:match("^https://") then
	local ok, https = pcall(require, "https")   -- LÖVE 12 only
	if ok then
		local code, b = https.request(url)
		if code == 200 then body = b end
	end
else
	local ok, http = pcall(require, "socket.http")
	if ok then
		http.TIMEOUT = 10
		local b, code = http.request(url)
		if code == 200 then body = b end
	end
end
love.thread.getChannel(channel):push(body or false)
]]

-- Returns nil while the fetch is in flight (ask again next frame), an Image on
-- success, false on failure — the same contract the browser path uses, so
-- M.image treats both platforms identically.
local function fetch_desktop(url, id)
	local job = pending[id]
	if not job then
		if not (love.thread and love.thread.newThread) then return false end
		local ok, thread = pcall(love.thread.newThread, FETCH_SOURCE)
		if not ok then return false end
		job = { thread = thread, channel = "ravel_asset_" .. id }
		pending[id] = job
		pcall(thread.start, thread, url, job.channel)
		return nil
	end

	local result = love.thread.getChannel(job.channel):pop()
	if result == nil then
		-- A worker that died would otherwise leave the card pending forever.
		local err = job.thread.getError and job.thread:getError()
		if err then
			pending[id] = nil
			print("asset fetch failed: " .. url .. " (" .. tostring(err) .. ")")
			return false
		end
		return nil
	end

	pending[id] = nil
	if result == false then
		print("asset download failed: " .. url)
		return false
	end
	local img, why = image_from_bytes(result)
	if not img then
		print(("asset unusable: %s, %d bytes, %s"):format(url, #result, tostring(why)))
		return false
	end
	return img
end

-- Browser: kick off a real fetch() in the page (once per URL), then poll a
-- JS-side global for the result. love.js.eval's calling convention isn't
-- documented, so every call is pcall-guarded; if it doesn't behave as
-- expected this just never resolves — same safe "no image" as a missing
-- asset, never a crash. Returns nil while still waiting, else Image/false.
--
-- `credentials: "same-origin"` and not "include": cookies belong to our own
-- host, and asking for them cross-origin is not merely pointless but fatal.
-- The fetch spec refuses a credentialed response whose
-- Access-Control-Allow-Origin is the wildcard, and a wildcard is what every
-- public image host answers with — i.imgur.com included. Every off-site
-- asset the engine was ever pointed at died of that, as a bare "NetworkError"
-- with no hint that the request had been the wrong shape all along.
--
-- The browser decodes the picture before Lua sees it, and hands back either the
-- original bytes or a re-encode. It re-encodes for two reasons only:
--
--   too big     4092 on the long edge is the ceiling, because pixels are what
--               the heap pays for: 4092 square is 67 MB of RGBA, and the
--               browser build's heap does not grow (index.html puts a floor
--               under it — read the note there before raising this).
--   wrong kind  LÖVE reads what stb_image reads. The browser reads far more, so
--               anything else comes back as PNG or JPEG and a remote WebP or
--               AVIF simply works.
--
-- A JPEG or PNG that already fits crosses untouched, because re-encoding a
-- picture the author chose is a quality loss for nothing.
--
-- Fetching to a blob first is what keeps the canvas untainted — an <img>
-- pointed straight at another origin poisons toDataURL, which is the usual way
-- this trick fails.
local function fetch_browser(url, id, max)
	if not pending[id] then
		pending[id] = { at = 0 }
		local kickoff = string.format([[(function(){
			window.__ravelAssets = window.__ravelAssets || {};
			var id = "%s";
			if (window.__ravelAssets[id]) return "dup";
			window.__ravelAssets[id] = { status: "pending" };
			var MAX = %d;
			var asIs = function(blob){
				return new Promise(function(res, rej){
					var fr = new FileReader();
					fr.onload = function(){ res(fr.result); };
					fr.onerror = function(){ rej(fr.error); };
					fr.readAsDataURL(blob);
				});
			};
			var shrink = function(src, type){
				var s = Math.min(1, MAX / Math.max(src.width, src.height));
				var c = document.createElement("canvas");
				c.width = Math.max(1, Math.round(src.width * s));
				c.height = Math.max(1, Math.round(src.height * s));
				c.getContext("2d").drawImage(src, 0, 0, c.width, c.height);
				return c.toDataURL(type === "image/jpeg" ? "image/jpeg" : "image/png", 0.85);
			};
			var native = function(t){ return t === "image/jpeg" || t === "image/png"; };
			var handle = function(bm, blob){
				if (native(blob.type) && Math.max(bm.width, bm.height) <= MAX) return asIs(blob);
				return shrink(bm, blob.type);
			};
			var decode = function(blob){
				if (window.createImageBitmap) {
					return createImageBitmap(blob).then(function(bm){ return handle(bm, blob); });
				}
				return new Promise(function(res, rej){
					var u = URL.createObjectURL(blob), im = new Image();
					im.onload = function(){
						var d = handle(im, blob);
						URL.revokeObjectURL(u);
						res(d);
					};
					im.onerror = function(){ URL.revokeObjectURL(u); rej(new Error("the browser could not decode it")); };
					im.src = u;
				});
			};
			fetch("%s", { credentials: "same-origin" })
				.then(function(r){ if (!r.ok) throw new Error("http " + r.status); return r.blob(); })
				.then(decode)
				.then(function(durl){ window.__ravelAssets[id] = { status: "ok", data: durl }; })
				.catch(function(e){ window.__ravelAssets[id] = { status: "error", message: String(e && e.message || e) }; });
			return "started";
		})()]], id, max, js_escape(url))
		pcall(love.js.eval, kickoff)
	end

	local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
	if now - pending[id].at < 0.2 then return nil end   -- throttle polling
	pending[id].at = now

	local poll = string.format([[(function(){
		var a = (window.__ravelAssets || {})["%s"];
		if (!a) return "";
		if (a.status === "ok") return a.data;
		if (a.status === "error") return "ERROR:" + a.message;
		return "";
	})()]], id)
	local ok, result = pcall(love.js.eval, poll)
	if not ok or type(result) ~= "string" or result == "" then return nil end

	pending[id] = nil
	if result:sub(1, 6) == "ERROR:" then
		print("asset download failed: " .. url .. " (" .. result:sub(7) .. ")")
		return false
	end
	-- Everything below this line used to fail by returning nil or false without
	-- a word, so a picture that never appeared looked exactly like a picture
	-- still on its way. The bytes have crossed by now; say what became of them.
	print(("asset arrived: %s (%d bytes across the bridge)"):format(url, #result))
	local b64 = result:match("^data:[^,]*,(.*)$")
	if not b64 then
		print("asset unusable: not a data URL, starts " .. string.format("%q", result:sub(1, 40)))
		return false
	end
	if not (love.data and love.data.decode) then
		print("asset unusable: this build has no love.data.decode")
		return false
	end
	local ok2, bytes = pcall(love.data.decode, "string", "base64", b64)
	if not ok2 then
		print("asset unusable: base64 would not decode (" .. tostring(bytes) .. ")")
		return false
	end
	local img, why = image_from_bytes(bytes)
	if not img then
		print(("asset unusable: %d bytes decoded, %s"):format(#bytes, tostring(why)))
		return false
	end
	return img
end

-- Load (and cache) the asset image for a card def, returns nil if missing
-- (or, for a browser URL asset, not yet fetched — ask again next frame).
-- Load an asset spec — a bare filename in games/assets, an http(s) URL, or a
-- shape the art module draws — and cache it under `key`.
--
-- Split out of M.image because none of this ever cared which *card* asked: a
-- zone wants a picture on its board by the same rules, with the same allowlist
-- and the same refusals. Callers own the cache key, so a zone named like a card
-- cannot collide with it.
-- A name with no source in it — no extension, no scheme, no shape colon — is a
-- key into the game's `assets` table, which is the only place that carries
-- options. Resolving here rather than at every call site also makes the name
-- the cache key, so twenty cards drawn from one picture cost one download and
-- one texture.
local DEFAULT_MAX = 1024

-- A picture that cannot be produced draws a generated one, never nothing.
--
-- The reasons a picture goes missing are mostly not the author's: a remote host
-- is down or refuses the fetch, or — the common one — somebody is playing a game
-- file that arrived over the network, which carries the JSON and not the art
-- sitting in the sender's assets folder. A card with no image at all reads as a
-- bug in the game; a shape derived from its key reads as a card.
--
-- The **key** is hashed, not the text, because the key is the card's identity
-- and the text is presentation: renaming a card's title should not give it a
-- different picture, and a saved game should not change under a copy-edit.
--
-- Said once per key rather than per frame, which img_cache gives for free — the
-- caller is a draw path and would otherwise print sixty times a second.
local function placeholder(key, why)
	print(("no picture for '%s' (%s) — drawing a generated one"):format(tostring(key), why))
	-- A placeholder is a drawing, and drawing needs a canvas. The headless shim
	-- has no graphics layer and nothing to show it to, so there answering nil is
	-- the honest result rather than an error on a path that only ever runs
	-- because something else already went wrong.
	local ok, img = pcall(art.render, art.auto(tostring(key)))
	return ok and img or nil
end

-- Which seat a card belongs to, as an index. Its own `owner` first — that is
-- placement state and beats everything — then the seat of the zone it lies in,
-- so a per-seat hand works without every card being stamped.
local function seat_of(e)
	if type(e) ~= "table" then return nil end
	if e.stats and e.stats.owner then return e.stats.owner end
	local seat = require("tags").owner_of(e)
	return seat and declaration.G.seat_index and declaration.G.seat_index[seat] or nil
end

-- One source, resolved: an Image, false and what is wrong with it, or nil while
-- a fetch is still in flight (ask again next frame).
local function resolve(src, max)
	if src:match("^https?://") then
		if not M.url_is_safe(src) then return false, "that URL has characters no URL may contain" end
		-- A real branch, not `cond and browser(...) or desktop(...)`: both of the
		-- browser fetch's unfinished answers are falsy — nil while in flight,
		-- false on failure — so `or` ran the desktop path too, which found the
		-- browser's job in `pending` and asked for its nonexistent thread
		-- channel. Every web asset in the browser build crashed on the first
		-- frame it was drawn.
		-- The size is part of the identity: the same URL asked for at two sizes
		-- is two different pictures, and one id would hand the second asker the
		-- first one's answer.
		local id = url_id(src .. "|" .. max)
		local img
		if love.js and love.js.eval then img = fetch_browser(src, id, max)
		else img = fetch_desktop(src, id) end
		if img == nil then return nil end
		if img == false then return false, "the fetch failed" end
		return img
	end
	-- A local asset is untrusted content too: require a bare filename (no
	-- path separators or "..") so it can only ever name a file directly in
	-- games/assets, never traverse elsewhere. Filenames carry an extension and
	-- shape specs never do, so the two can't be confused.
	if not src:match("^[%w_%-]+%.[%w]+$") then
		local drawn = art.render(src)
		if drawn then return drawn end
		return false, (art.parse(src) == nil and src:find(":"))
			and ("'" .. src .. "' is not a shape the engine knows")
			or ("'" .. src .. "' is neither a plain filename nor a shape")
	end
	local ok, img = pcall(love.graphics.newImage, "games/assets/" .. src)
	if ok and img then return img end
	return false, "'" .. src .. "' is not in games/assets"
end

function M.asset_image(asset, key, e)
	local srcs, max = { asset }, DEFAULT_MAX
	local named = asset and declaration.G.asset_defs and declaration.G.asset_defs[asset]
	if named then
		max = named.max or DEFAULT_MAX
		if named.per_player then
			-- One name, one picture per seat. A rook is a rook — whose it is decides
			-- only which sprite is drawn — and that is what lets six cards stand for
			-- thirty-two pieces. The seat index is part of the cache key, or the
			-- second player is handed the first one's rook.
			local i = seat_of(e) or 1
			key, srcs = "asset:" .. asset .. "#" .. i, named.per_player[i] or named.per_player[1]
		else
			key, srcs = "asset:" .. asset, named.src
		end
		if type(srcs) == "string" then srcs = { srcs } end
	end
	if img_cache[key] ~= nil then return img_cache[key] or nil end
	if type(srcs) ~= "table" or srcs[1] == nil then img_cache[key] = false; return nil end

	-- **The first source that can be drawn**, and the rest are what to do when it
	-- cannot. Two hosts serving one picture is the case that asked for it: a
	-- desktop LÖVE with no https module and a browser that refuses a response
	-- without CORS headers can have no URL in common, so the name carries one of
	-- each and each platform silently takes the one it can reach.
	local i, why = chain_at[key] or 1, nil
	while srcs[i] do
		local img, no = resolve(tostring(srcs[i]), max)
		if img == nil then chain_at[key] = i; return nil end
		if img then
			chain_at[key] = nil
			img_cache[key] = img
			return img
		end
		why = no
		if srcs[i + 1] then print(("'%s': %s — trying the next source"):format(tostring(key), why)) end
		i = i + 1
	end
	chain_at[key] = nil
	img_cache[key] = placeholder(key, why) or false
	return img_cache[key] or nil
end

-- Takes the card entity, because a picture can depend on whose card it is.
-- A bare key still works and means "the template's own picture".
function M.image(e)
	local def_key = type(e) == "table" and e.def_key or e
	local def   = declaration.G.card_defs[def_key]
	local asset = def and def.asset
	-- `generate_art` is a card asking for a shape derived from its key, which is
	-- what a card with nothing to show should look like rather than a bare
	-- colour. A tag and not a field, because a thing a card either does or does
	-- not do is exactly what a tag is: the boolean field this replaced could
	-- only ever be set for a whole game at once, so a file could not have six
	-- generated cards among thirty-five photographs.
	if not asset and def and def.tags_set and def.tags_set.generate_art then asset = "auto" end
	if asset == "auto" then asset = art.auto(def_key) end
	return M.asset_image(asset, def_key, type(e) == "table" and e or nil)
end

return M
