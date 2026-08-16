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
	{ "hp_max", 'card_stats written as a list: "hp": [4, 4] is [current, max]' },
}

local function read(path)
	local f = io.open(path)
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
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
