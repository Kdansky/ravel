-- One game out of several files.
--
-- A file that includes another is the more specific of the two — a three-seat
-- module includes the two-seat game, a card set includes the sets before it —
-- and the merge happens on the raw JSON before anything is parsed. So the rest
-- of the engine never learns the word: what parse, the validator and the
-- network see is one game, and the merged table is itself an ordinary game file.
--
-- The rule that needs the tests is the collision. A key written in two files is
-- an error unless the including file says "replaces", because an override
-- nobody announced reads exactly like an accident.

local declaration = require("declaration")
local json = require("json")

local M = {}

local BASE = [==[{
  "title": "Base",
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "bag", "layout": "stack", "pos": [0.55, 0.80, 0.65, 0.95] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "alpha", "text": "Alpha" },
    { "key": "beta", "text": "Beta" }
  ],
  "tags": { "shiny": { "zone": "bag" } },
  "players": [{ "stats": { "hp": 3 } }]
}]==]

-- Files are written, parsed and removed together, so a failing case leaves
-- nothing behind for the next one to include by accident.
local function with(files, fn)
	local written = {}
	for name, text in pairs(files) do
		local path = "game/games/" .. name
		local f = assert(io.open(path, "w"))
		f:write(text)
		f:close()
		written[#written + 1] = path
	end
	local ok, err = pcall(fn)
	for _, path in ipairs(written) do os.remove(path) end
	if not ok then error(err, 0) end
end

local function said(G)
	return table.concat(G.parse_problems, "; ")
end

-- What the merge is for: the module writes what differs and inherits the rest.
function M.test_include_brings_the_other_file_along(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"cards": [{ "key": "gamma", "text": "Gamma" }]
	}]==] }, function()
		local G = declaration.parse("tmp_inc_mod.json")
		check("nothing went wrong", said(G) == "", said(G))
		check("the included cards are here", G.card_defs.alpha ~= nil and G.card_defs.beta ~= nil)
		check("and this file's own", G.card_defs.gamma ~= nil)
		check("the included zones came too", G.zone_defs.hand ~= nil and G.zone_defs.bag ~= nil)
		check("and its tags", G.tag_defs.shiny ~= nil)
		-- Included first, so the base's own order is untouched and the module's
		-- card lands after it — file order is what an unseeded setup deals from.
		check("in include order, this file last",
			table.concat(G.card_list, ","):find("alpha,beta,gamma", 1, true) ~= nil,
			table.concat(G.card_list, ","))
	end)
end

-- The top file names the game. An included game has a title of its own and it
-- would be the wrong one on the HUD.
function M.test_include_does_not_carry_the_title(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"]
	}]==] }, function()
		check("the title is this file's", declaration.parse("tmp_inc_mod.json").title == "Module")
	end)
end

-- The rule the whole design rests on: an override has to be announced.
function M.test_include_refuses_a_collision_nobody_announced(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"cards": [{ "key": "alpha", "text": "Not the same Alpha" }]
	}]==] }, function()
		local s = said(declaration.parse("tmp_inc_mod.json"))
		check("it says both files", s:find("tmp_inc_base.json", 1, true) and s:find("tmp_inc_mod.json", 1, true), s)
		check("and what to write instead", s:find('replaces: ["cards.alpha"]', 1, true), s)
	end)
end

-- Announced, it goes through — and lands where the entry it replaced stood.
function M.test_include_takes_over_a_named_entry(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"replaces": ["cards.alpha"],
		"cards": [{ "key": "alpha", "text": "Mine" }, { "key": "gamma", "text": "Gamma" }]
	}]==] }, function()
		local G = declaration.parse("tmp_inc_mod.json")
		check("nothing went wrong", said(G) == "", said(G))
		check("this file's version won", G.card_defs.alpha.text == "Mine")
		check("and it kept the position the one it replaced had",
			table.concat(G.card_list, ","):find("alpha,beta,gamma", 1, true) ~= nil, table.concat(G.card_list, ","))
	end)
end

-- A whole section, which is what a different player count wants: every per-seat
-- zone gains a rect and the shared ones move, so naming them one by one is a
-- list as long as the section.
function M.test_include_takes_over_a_whole_section(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"replaces": ["zones"],
		"zones": [{ "key": "hand", "layout": "row", "pos": [0.1, 0.1, 0.2, 0.2] }]
	}]==] }, function()
		local G = declaration.parse("tmp_inc_mod.json")
		check("nothing went wrong", said(G) == "", said(G))
		check("the section is this file's alone", G.zone_defs.bag == nil and G.zone_defs.hand ~= nil)
	end)
end

-- A section with nothing naming its entries can only be taken over whole, and
-- says so rather than concatenating two seat lists into a four-seat game.
function M.test_include_refuses_two_writers_of_an_unkeyed_section(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"players": [{ "stats": { "hp": 9 } }]
	}]==] }, function()
		local s = said(declaration.parse("tmp_inc_mod.json"))
		check("it says the section has no keys to merge by", s:find("no keys to merge by", 1, true), s)
	end)
end

function M.test_include_takes_over_an_unkeyed_section_when_told(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"replaces": ["players"],
		"players": [{ "stats": { "hp": 9 } }]
	}]==] }, function()
		local G = declaration.parse("tmp_inc_mod.json")
		check("nothing went wrong", said(G) == "", said(G))
		check("there is still one seat and it is this file's", #G.players == 1 and G.players[1].stats.hp == 9)
	end)
end

-- Two modules over one base. The base is read once however many paths reach it,
-- or its own cards would collide with themselves and a diamond would be illegal.
function M.test_include_reads_a_shared_file_once(check)
	with({ ["tmp_inc_base.json"] = BASE,
		["tmp_inc_left.json"]  = [==[{ "title": "L", "include": ["tmp_inc_base.json"], "cards": [{ "key": "l", "text": "L" }] }]==],
		["tmp_inc_right.json"] = [==[{ "title": "R", "include": ["tmp_inc_base.json"], "cards": [{ "key": "r", "text": "R" }] }]==],
		["tmp_inc_mod.json"]   = [==[{ "title": "M", "include": ["tmp_inc_left.json", "tmp_inc_right.json"] }]==] },
	function()
		local G = declaration.parse("tmp_inc_mod.json")
		check("the diamond is not a collision", said(G) == "", said(G))
		check("and every branch arrived", G.card_defs.alpha and G.card_defs.l and G.card_defs.r)
		check("with the shared file's cards appearing once",
			table.concat(G.card_list, ","):find("alpha,beta,l,r", 1, true) ~= nil, table.concat(G.card_list, ","))
	end)
end

-- Reported and cut. A loop is a mistake in the files, and hanging on it is the
-- one answer that tells the author nothing.
function M.test_include_cuts_a_cycle_and_says_so(check)
	with({ ["tmp_inc_a.json"] = [==[{ "title": "A", "include": ["tmp_inc_b.json"] }]==],
		["tmp_inc_b.json"] = [==[{ "title": "B", "include": ["tmp_inc_a.json"] }]==] },
	function()
		local s = said(declaration.parse("tmp_inc_a.json"))
		check("it says which file goes round", s:find("includes itself", 1, true), s)
		check("and names the way round", s:find("tmp_inc_a.json -> tmp_inc_b.json", 1, true), s)
	end)
end

function M.test_include_says_which_file_it_could_not_read(check)
	with({ ["tmp_inc_mod.json"] = [==[{ "title": "M", "include": ["tmp_inc_nothing.json"] }]==] }, function()
		local s = said(declaration.parse("tmp_inc_mod.json"))
		check("it names the file", s:find("tmp_inc_nothing.json", 1, true), s)
	end)
end

-- What goes over the wire is what this side is playing. A file naming two
-- others is no use to a peer holding neither, and a hash of it would cover one
-- game in three — two peers with different base files agreeing, then diverging.
function M.test_include_sends_the_merged_game_not_the_file(check)
	with({ ["tmp_inc_base.json"] = BASE, ["tmp_inc_mod.json"] = [==[{
		"title": "Module",
		"include": ["tmp_inc_base.json"],
		"cards": [{ "key": "gamma", "text": "Gamma" }]
	}]==] }, function()
		local net = require("net")
		local text = net.game_text("tmp_inc_mod.json")
		check("there is no include left in it", not text:find('"include"', 1, true), text:sub(1, 120))
		local flat = json.decode(text)
		check("it carries every card", #flat.cards == 3, #flat.cards)
		check("and it is a game file the engine reads back", flat.title == "Module")
	end)
end

return M
