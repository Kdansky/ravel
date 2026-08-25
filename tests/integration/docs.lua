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
	for i, ex in ipairs(examples()) do
		sources[("AUTHORING.md example %d (%s)"):format(i, ex.title)] = ex.text
	end
	check("there is something to check", next(sources) ~= nil)

	for _, entry in ipairs(RETIRED) do
		local word, instead = entry[1], entry[2]
		local found = {}
		for path, text in pairs(sources) do
			if text:find('"' .. word .. '"', 1, true) then found[#found + 1] = path end
		end
		table.sort(found)
		check("nothing still offers '" .. word .. "'", #found == 0,
			table.concat(found, ", ") .. " — write " .. instead .. " instead")
	end
end

return M
