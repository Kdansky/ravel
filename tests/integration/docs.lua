-- The examples in AUTHORING.md, run through the validator.
--
-- Both walkthroughs are written to be copied, and both had quietly stopped
-- working: the minimal game pushed a phase it never declared and put its hand
-- under the undo button, and the story game still spoke a vocabulary the engine
-- had dropped. Nothing noticed, because a document cannot fail.
--
-- Only whole games are checked. The rest of the file is fragments and ellipses
-- on purpose — a reference entry is clearer for showing one field than for
-- being runnable — so anything that does not parse as a game file is skipped
-- rather than mangled into one.

local declaration = require("declaration")
local validate = require("validate")
local json = require("json")
local actions = require("actions")
local predicate = require("predicate")

local M = {}

local function examples()
	local f = assert(io.open("AUTHORING.md"), "AUTHORING.md should be at the repo root")
	local text = f:read("*a")
	f:close()
	local out = {}
	for body in text:gmatch("```json\n(.-)```") do
		local ok, d = pcall(json.decode, body)
		if ok and type(d) == "table" and d.cards and d.zones and d.phases then
			out[#out + 1] = { title = d.title or "untitled", text = body }
		end
	end
	return out
end

function M.test_docs_every_whole_game_example_validates(check)
	local found = examples()
	check("AUTHORING carries complete game examples", #found >= 2, tostring(#found) .. " found")
	for _, ex in ipairs(found) do
		local path = "game/games/tmp_docs_test.json"
		local f = assert(io.open(path, "w"))
		f:write(ex.text)
		f:close()
		local ok, G = pcall(declaration.parse, "tmp_docs_test.json")
		os.remove(path)
		if not ok then
			check("'" .. ex.title .. "' parses", false, tostring(G))
		else
			local problems = validate.check(G)
			check("'" .. ex.title .. "' validates clean", #problems == 0,
				table.concat(problems, "; "))
		end
	end
end

-- Vocabulary the format used to have, and what to write instead.
--
-- A word leaves the engine in one commit and lives on for months in the things a
-- game is written from. `exhausts` outlived the engine reading it by three
-- passes and was still recommended by the manual, so a card built from the
-- board-button example tired for the round anyway. `stays_ready` outlived its
-- own deletion inside the generator that writes a shipped game file. Neither was
-- noticed, because a document cannot fail and a generator is not run by the
-- suite.
--
-- Prose may still name a retired word — the history is worth writing down, and
-- several comments explain why a word went. This looks for the word as a *token*
-- a game could be carrying: quoted whole, which is a key or a value and never a
-- sentence.
local RETIRED = {
	{ "exhausts", 'a cost — "exhaust": 1 on the ability that spends the card' },
	{ "stays_ready", "nothing at all — an ability charging no exhaust stays ready" },
	{ "transparent_background", 'the style property "color": false' },
	{ "invisible_title_text", 'the style property "title": false' },
	{ "invisible_slot_outlines", 'the style property "cell_outline": false' },
	{ "on_pick", 'the "play" block' },
	-- The four that move a number are prefixed now, so they sort together and a
	-- reader looking for "what can change a stat" finds them in one place.
	{ "gain_stat", "stat_gain" },
	{ "lose_stat", "stat_damage" },
	{ "spend_stat", "stat_damage — a cost is an ordinary reduction and never needed its own word" },
	{ "set_stat", "stat_set" },
	{ "hp_max", 'the bound beside the value: "hp": { "value": 4, "max": 4 }' },
	-- It refused a tooltip and the browse view, and every zone carrying it was
	-- "hidden" as well — which zone_at skips outright, so there was never a
	-- hover or a right-click for it to refuse.
	{ "no_peek", "nothing — a zone nobody can reach is not browsable already" },
	-- A zone's shape and its rules are seven fields now, not one word and a
	-- handful of tags overriding it. Only the words that went entirely are
	-- listed: "per_seat" and "page" are values on the new fields, "activate" is
	-- still a zone's own ability block and "hidden" is still a stat tag, so the
	-- word turning up is not evidence of the old meaning.
	{ "face_up", '"visibility": "public"' },
	{ "face_down", '"visibility": "secret"' },
}

local function read(path)
	local f = io.open(path)
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

-- Every action the engine runs, named in the manual's own table.
--
-- SCHEMA.json is already held to this list, and a schema is what a machine
-- reads. The table in AUTHORING is what a *person* reads, and it had quietly
-- fallen six verbs behind — each_seat and the five net_ ops were in the engine,
-- in the schema, and nowhere a reader would look. A verb you cannot look up may
-- as well not exist, so the manual is held to the same list the schema is.
--
-- Looked for as `op` in code ticks anywhere in the section, not as a whole row:
-- several verbs are documented as a pair on one line, which is how they read
-- best and is nobody's mistake.
function M.test_docs_the_manual_lists_every_action(check)
	local text = read("AUTHORING.md")
	check("AUTHORING.md is there", text ~= nil)
	local from = text:find("### Actions", 1, true)
	local to   = text:find("### Engine behaviors", from or 1, true)
	check("it has an Actions section that ends", from ~= nil and to ~= nil)
	local section = text:sub(from, to)

	local missing = {}
	for op in pairs(actions.ops()) do
		if not section:find("`" .. op, 1, true) then missing[#missing + 1] = op end
	end
	table.sort(missing)
	check("every action the engine runs is in the manual's table", #missing == 0,
		table.concat(missing, ", ") .. " — a verb nobody can look up may as well not exist")
end

function M.test_docs_no_retired_word_is_still_on_offer(check)
	-- Every shipped game, the schema they are held to, the generator that writes
	-- one of them, and the manual's examples — everything a game is copied from.
	local sources = {}
	local ls = io.popen("ls game/games/*.json tools/*.py 2>/dev/null")
	for path in ls:lines() do sources[path] = read(path) end
	ls:close()
	sources["SCHEMA.json"] = read("SCHEMA.json")
	-- The idea files too: they carry worked examples, and a worked example in a
	-- spelling the format has deleted is the same lie as one in the manual. They
	-- are also where somebody looks to find out how a thing was done.
	local ids = io.popen("ls ideas/*.md 2>/dev/null")
	for path in ids:lines() do sources[path] = read(path) end
	ids:close()
	for i, ex in ipairs(examples()) do
		sources[("AUTHORING.md example %d (%s)"):format(i, ex.title)] = ex.text
	end
	check("there is something to check", next(sources) ~= nil)

	for _, entry in ipairs(RETIRED) do
		local word, instead = entry[1], entry[2]
		local found = {}
		for path, text in pairs(sources) do
			-- Quoted whole, which is a key or a value; and quoted as the head of a
			-- colon-separated action, which is the only other way a game can be
			-- carrying one. Four of the words below are *verbs* — an action reads
			-- "gain_stat:gold:3", so looking for "gain_stat" with its closing quote
			-- never matched, and the guard could not fire for the entries it was
			-- most obviously written for.
			if text:find('"' .. word .. '"', 1, true) or text:find('"' .. word .. ':', 1, true) then
				found[#found + 1] = path
			end
		end
		table.sort(found)
		check("nothing still offers '" .. word .. "'", #found == 0,
			table.concat(found, ", ") .. " — write " .. instead .. " instead")
	end
end

-- The index at the top, against the headings it indexes.
--
-- Sixty-eight reference sections is a document you search rather than read, and
-- an index is what lets somebody search it who does not yet know the word to
-- search for. One that has fallen behind is worse than none: it says a section
-- is not there.
local function split(s, sep)
	local out, at = {}, 1
	while true do
		local i = s:find(sep, at, true)
		if not i then out[#out + 1] = s:sub(at); return out end
		out[#out + 1] = s:sub(at, i - 1)
		at = i + #sep
	end
end

function M.test_docs_the_index_lists_every_reference_heading(check)
	local text = read("AUTHORING.md")
	local from = text:find("## 5. Reference", 1, true)
	check("the reference section is there", from ~= nil)

	local heads, is_head = {}, {}
	for line in text:sub(from):gmatch("[^\n]+") do
		if line:match("^###") then
			local h = line:match("^#+%s+(.+)$")
			heads[#heads + 1] = h
			is_head[h] = true
		end
	end
	check("there are headings to index", #heads > 40, tostring(#heads))

	-- The index block alone: §3's list of rules that do not fit is bulleted the
	-- same way, and its entries are not headings of anything.
	local at = text:find("**The reference index.**", 1, true)
	check("the index is there", at ~= nil)
	local ends = text:find("\n---\n", at or 1, true)
	check("and it ends", ends ~= nil)

	local listed, seen = 0, {}
	for line in text:sub(at, ends):gmatch("[^\n]+") do
		local tail = line:match("^%- %*%*.-%*%* — (.+)$")
		for _, name in ipairs(tail and split(tail, " · ") or {}) do
			listed = listed + 1
			check("'" .. name .. "' is a real heading", is_head[name] == true)
			check("'" .. name .. "' is indexed once", seen[name] == nil)
			seen[name] = true
		end
	end
	for _, h in ipairs(heads) do check("'" .. h .. "' is in the index", seen[h] == true) end
	check("nothing is indexed twice or left out", listed == #heads,
		listed .. " listed against " .. #heads .. " headings")
end

-- The condition vocabulary, held the way the action table is.
--
-- Three closed sets — the measuring fns, the quantifiers, the owner words — and
-- after the field names they are the largest thing an author writes. Both
-- documents teach them and neither was tied to the engine, so a fourth
-- quantifier could have arrived and been written down nowhere. That is the hole
-- each_seat and the five net_ ops fell into, one vocabulary over.
--
-- Looked for as a whole word inside a code span, because these are words
-- ordinary prose uses too: "count the cards" is not documentation of `count:`.
local function whole_word(hay, w)
	for a, b in hay:gmatch("()" .. w .. "()") do
		local before = a > 1 and hay:sub(a - 1, a - 1) or " "
		local after  = hay:sub(b, b)
		if after == "" then after = " " end
		if not before:match("[%w_]") and not after:match("[%w_]") then return true end
	end
	return false
end

function M.test_docs_both_documents_teach_the_condition_vocabulary(check)
	local ticks = {}
	for span in read("AUTHORING.md"):gmatch("`([^`\n]+)`") do ticks[#ticks + 1] = span end
	local ticked = table.concat(ticks, " ")

	local prose = {}
	local function gather(t)
		for _, v in pairs(t) do
			if type(v) == "table" then gather(v) else prose[#prose + 1] = v end
		end
	end
	gather(json.decode(read("SCHEMA.json"))._conditions)
	local described = table.concat(prose, " ")
	check("both documents have something to say about conditions",
		#ticked > 1000 and #described > 1000)

	for kind, set in pairs(predicate.WORDS) do
		for word in pairs(set) do
			check("the manual writes '" .. word .. "' (" .. kind .. ")", whole_word(ticked, word))
			check("the schema describes '" .. word .. "'", whole_word(described, word))
		end
	end
end

-- Every fragment in the manual, held to the words the engine reads.
--
-- The whole-game examples above are validated outright, and that used to be the
-- end of it: a hundred-odd fragments — a card here, a phase there, the three
-- lines that make a shop — were read far more often than the whole files and
-- checked by nobody. "setup" carried a "player" map in the manual and in
-- SCHEMA.json that the engine has never read, and anyone copying the Setup
-- example got a validator complaint for their trouble.
--
-- A fragment cannot be run: it names zones, cards and stats it does not carry,
-- and always will. What it *can* be held to is its own vocabulary — every field
-- a word the engine reads for that shape, every action a verb the engine runs.
-- Both come off the tables the validator itself uses, so this cannot drift from
-- the engine the way prose does.
--
-- The shape is worked out rather than declared, by trying the fragment against
-- each field table and keeping the reading that fits. A fragment that fits none
-- has a word in it that nothing reads, which is the whole point.

-- A nested block's fields, where the name of the key and the name of the shape
-- differ only for "next".
local NESTED = { play = "play", activate = "activate", challenge = "challenge",
	receive = "receive", turn = "turn", chosen = "chosen", target = "target", next = "route" }
-- Keys holding a list of actions. "then" holds one only when it is a list: on a
-- routing entry it is a phase key.
local RUNS = { action = true, actions = true, pass = true, fail = true, ["then"] = true }
-- The two shapes the engine has no field table for. Named here rather than
-- passed over quietly, so a third cannot arrive without somebody deciding it
-- should: their verbs are held, their field names are held by nothing.
local NO_TABLE = { abilities = true, reactions = true }

local function walk(where, def, fields, found)
	if type(def) ~= "table" then return end
	for k, v in pairs(def) do
		if fields and type(k) == "string" then
			found.checked = found.checked + 1
			-- The one word every shape carries and none of them lists, exactly
			-- as check_fields exempts it: see validate.lua.
			if k ~= "comment" and not fields[k] then found[#found + 1] = where .. ": '" .. k .. "'" end
		end
		if RUNS[k] and type(v) == "table" then
			for _, str in ipairs(v) do
				local op = type(str) == "string" and str:match("^[^:]+")
				if op and not actions.ops()[op] then
					found[#found + 1] = where .. "." .. k .. ": '" .. op .. "' is no action"
				end
			end
		end
		local shape = type(k) == "string" and NESTED[k]
		if shape == "route" and type(v) == "table" then
			for i, e in ipairs(v) do walk(where .. ".next[" .. i .. "]", e, validate.FIELDS.route, found) end
		elseif shape then
			walk(where .. "." .. k, v, validate.FIELDS[shape], found)
		elseif NO_TABLE[k] and type(v) == "table" then
			for i, e in ipairs(v) do walk(where .. "." .. k .. "[" .. i .. "]", e, nil, found) end
		elseif k == "moves" and type(v) == "table" then
			for i, e in ipairs(v) do walk(where .. ".moves[" .. i .. "]", e, validate.SHAPES.move_rule, found) end
		end
	end
end

-- Every reading of a fragment worth trying, with the table each one holds it to.
local function readings(frag)
	local out = {}
	local function fits(t)
		for k in pairs(frag) do if k ~= "comment" and not t[k] then return false end end
		return next(frag) ~= nil
	end
	local function add(name, fn) out[#out + 1] = { name, fn } end

	if fits(declaration.KNOWN_SECTIONS) then
		add("sections", function(found)
			for sec, body in pairs(frag) do
				local t = validate.FIELDS[sec] or validate.SHAPES[sec]
				if sec == "setup" then
					walk("setup", body, validate.SHAPES.setup, found)
					for i, e in ipairs(type(body) == "table" and body.place or {}) do
						walk("setup.place[" .. i .. "]", e, validate.SHAPES.place, found)
					end
				elseif sec == "players" then
					for i, e in ipairs(type(body) == "table" and body or {}) do
						walk("player " .. i, e, validate.SHAPES.player, found)
					end
				elseif type(body) == "table" and t then
					if body[1] ~= nil then
						for i, e in ipairs(body) do walk(sec .. "[" .. i .. "]", e, t, found) end
					else
						for name, e in pairs(body) do walk(sec .. "." .. name, e, t, found) end
					end
				end
			end
		end)
	end
	-- A whole entry, or the handful of its fields a paragraph is about: a
	-- fragment showing what "next" looks like is a phase with one field written.
	for _, sec in ipairs({ "cards", "zones", "phases", "stats", "verbs", "adjusts" }) do
		local t = validate.FIELDS[sec]
		if fits(t) then
			add((frag.key and "a " or "the fields of a ") .. sec:sub(1, #sec - 1),
				function(found) walk(sec, frag, t, found) end)
		end
	end
	if fits(validate.SHAPES.setup) then
		add("the fields of setup", function(found)
			walk("setup", frag, validate.SHAPES.setup, found)
			for i, e in ipairs(type(frag.place) == "table" and frag.place or {}) do
				walk("setup.place[" .. i .. "]", e, validate.SHAPES.place, found)
			end
		end)
	end
	for _, shape in ipairs({ "target", "route", "play", "activate", "chosen", "challenge" }) do
		if fits(validate.FIELDS[shape]) then
			add("a " .. shape, function(found) walk(shape, frag, validate.FIELDS[shape], found) end)
		end
	end
	if fits(validate.SHAPES.place) then
		add("a setup.place entry", function(found) walk("place", frag, validate.SHAPES.place, found) end)
	end
	if fits(validate.SHAPES.move_rule) then
		add("a move rule", function(found) walk("move", frag, validate.SHAPES.move_rule, found) end)
	end
	-- An entry of an "abilities" or "reactions" list: verbs only, since the
	-- engine reads no field set for either.
	if frag.action ~= nil or frag.to ~= nil then
		add("an ability or a reaction", function(found)
			walk("ability", frag, nil, found)
			found.checked = found.checked + 1
		end)
	end
	-- The inside of a named-map section, written without its wrapper.
	for _, sec in ipairs({ "tags", "styles", "computed_tags", "patterns", "effects", "assets" }) do
		add("inside " .. sec, function(found)
			for name, e in pairs(frag) do walk(sec .. "." .. name, e, validate.FIELDS[sec], found) end
		end)
	end
	return out
end

-- The objects in one block: the whole of it, the whole of it wrapped in braces
-- (a fragment written as the fields it would sit among), or a run of top-level
-- objects side by side.
local function objects(body)
	local ok, d = pcall(json.decode, body)
	if ok and type(d) == "table" then return { d } end
	local ok2, d2 = pcall(json.decode, "{" .. body .. "}")
	if ok2 and type(d2) == "table" then return { d2 } end
	local out, depth, start, instr, esc = {}, 0, nil, false, false
	for i = 1, #body do
		local ch = body:sub(i, i)
		if instr then
			if esc then esc = false elseif ch == "\\" then esc = true elseif ch == '"' then instr = false end
		elseif ch == '"' then instr = true
		elseif ch == "{" then
			if depth == 0 then start = i end
			depth = depth + 1
		elseif ch == "}" then
			depth = depth - 1
			if depth == 0 and start then
				local o, d3 = pcall(json.decode, body:sub(start, i))
				if not o then return nil end
				out[#out + 1] = d3
				start = nil
			end
		end
	end
	return #out > 0 and out or nil
end

function M.test_docs_every_fragment_uses_words_the_engine_reads(check)
	local text = read("AUTHORING.md")
	local n, held, abridged = 0, 0, 0
	for body in text:gmatch("```json\n(.-)```") do
		n = n + 1
		local objs = objects(body)
		local whole = objs and #objs == 1 and objs[1].cards and objs[1].zones and objs[1].phases
		if whole then
			-- Already run through the validator entire, above.
		elseif not objs then
			-- A block with an ellipsis is abridged and says so; one with no
			-- object in it is a line of grammar rather than a thing to paste.
			local shown = body:find("…", 1, true) or body:find("...", 1, true)
			check("an unparseable block is marked abridged: " .. body:sub(1, 50):gsub("\\n", " "),
				shown ~= nil or not body:find("{", 1, true))
			abridged = abridged + 1
		else
			for _, frag in ipairs(objs) do
				local best, name
				for _, r in ipairs(readings(frag)) do
					local found = { checked = 0 }
					r[2](found)
					if found.checked == 0 then found[#found + 1] = "reads nothing" end
					if best == nil or #found < #best then best, name = found, r[1] end
				end
				local keys = {}
				for k in pairs(frag) do keys[#keys + 1] = tostring(k) end
				table.sort(keys)
				check("a fragment reading '" .. table.concat(keys, ",") .. "' is words the engine reads",
					best ~= nil and #best == 0,
					"best reading was " .. tostring(name) .. ": " .. table.concat(best or {}, ", "))
				held = held + 1
			end
		end
	end
	check("the manual is full of fragments and they are all held", held > 80,
		held .. " held, " .. abridged .. " abridged, out of " .. n .. " blocks")
end

return M
