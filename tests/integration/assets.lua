-- Named pictures: the `assets` table, and what a card's `asset` field means.
--
-- A card can spell a source out inline — a filename, a URL, a shape — or name
-- an entry here. Naming one is what buys options, and what lets two cards share
-- one download, because the name becomes the cache key.

local declaration = require("declaration")
local validate = require("validate")

local M = {}

local function fixture(assets, asset_field)
	local path = "game/games/tmp_assets_test.json"
	local f = assert(io.open(path, "w"))
	f:write(([[{
		"title": "Assets",
		"assets": %s,
		"zones": [{ "key": "hand", "layout": "row", "pos": [0.2, 0, 1, 0.9] }],
		"cards": [{ "key": "hero", "text": "Hero", "asset": %s }],
		"phases": [{ "key": "play", "type": "player_input" }]
	}]]):format(assets, asset_field))
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_assets_test.json")
	os.remove(path)
	if not ok then error(G, 2) end
	return G, validate.check(G)
end

local function has(problems, needle)
	for _, p in ipairs(problems) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

function M.test_assets_a_name_resolves_to_a_source_and_its_options(check)
	local G, problems = fixture(
		'{ "portrait": { "src": "https://example.com/a.png", "max": 512 } }', '"portrait"')
	check("the entry parses", G.asset_defs.portrait ~= nil)
	check("its source is kept", G.asset_defs.portrait.src == "https://example.com/a.png")
	check("so is its size", G.asset_defs.portrait.max == 512)
	check("and a card naming it validates clean", #problems == 0, table.concat(problems, "; "))
end

function M.test_assets_the_bare_form_is_a_source_on_its_own(check)
	local G, problems = fixture('{ "portrait": "crown_royal.jpg" }', '"portrait"')
	check("a bare string is the source", G.asset_defs.portrait.src == "crown_royal.jpg")
	check("with no size of its own", G.asset_defs.portrait.max == nil)
	check("and it validates", #problems == 0, table.concat(problems, "; "))
end

-- The point of naming one: the cache key stops being the card. Two cards drawn
-- from one picture used to mean two downloads and two textures.
function M.test_assets_two_cards_naming_one_picture_share_it(check)
	local path = "game/games/tmp_assets_share.json"
	local f = assert(io.open(path, "w"))
	f:write([[{
		"title": "Shared",
		"assets": { "shared": "crown_royal.jpg" },
		"zones": [{ "key": "hand", "layout": "row", "pos": [0.2, 0, 1, 0.9] }],
		"cards": [
			{ "key": "a", "text": "A", "asset": "shared" },
			{ "key": "b", "text": "B", "asset": "shared" }
		],
		"phases": [{ "key": "play", "type": "player_input" }]
	}]])
	f:close()
	local flow = require("flow")
	local ok, err = pcall(flow.init, "tmp_assets_share.json", 1)
	os.remove(path)
	if not ok then error(err, 2) end
	-- Headless has no love.graphics, so the image itself never loads; what is
	-- being asserted is which key the two lookups land on, and that is decided
	-- before any pixel is read.
	check("both cards name one picture",
		declaration.G.card_defs.a.asset == "shared" and declaration.G.card_defs.b.asset == "shared")
	check("which the engine knows as an entry, not a filename",
		declaration.G.asset_defs.shared.src == "crown_royal.jpg")
end

function M.test_assets_a_name_that_matches_nothing_is_a_problem(check)
	local _, problems = fixture('{ "portrait": "crown_royal.jpg" }', '"portrat"')
	check("a misspelled name is caught", has(problems, "nothing is named 'portrat'"))
	check("and the right one is suggested", has(problems, "portrait"))
end

function M.test_assets_a_broken_entry_says_what_is_wrong(check)
	local _, missing_src = fixture('{ "portrait": { "max": 512 } }', '"portrait"')
	check("an entry with no source is caught", has(missing_src, 'needs a "src"'))

	local _, huge = fixture('{ "portrait": { "src": "a.png", "max": 99999 } }', '"portrait"')
	check("a size past the ceiling is caught", has(huge, "between 1 and 4092"))

	local _, typo = fixture('{ "portrait": { "src": "a.png", "maxx": 512 } }', '"portrait"')
	check("a typo'd option is caught", has(typo, "maxx"))

	local _, nonsense = fixture('{ "portrait": "not a picture" }', '"portrait"')
	check("a source that names no picture is caught", has(nonsense, "names no picture"))
end

-- Spelling a source out inline still works, and is still checked as before.
function M.test_assets_inline_sources_are_unchanged(check)
	local _, url = fixture('{}', '"https://example.com/a.png"')
	check("an inline URL is fine", #url == 0, table.concat(url, "; "))

	local _, shape = fixture('{}', '"circle:teal"')
	check("an inline shape is fine", #shape == 0, table.concat(shape, "; "))

	local _, bad_shape = fixture('{}', '"hexagram:red"')
	check("an inline shape that does not exist is caught", has(bad_shape, "isn't a shape"))

	local _, missing_file = fixture('{}', '"no_such_file.jpg"')
	check("an inline filename that is not there is caught", has(missing_file, "not in games/assets"))
end

function M.test_assets_the_shipped_game_uses_one(check)
	local G = declaration.parse("kingdom.json")
	check("Coronation names the archmage's tower", G.asset_defs.archmage_tower ~= nil)
	check("...at full size", G.asset_defs.archmage_tower.max == 4092)
	check("...and the card refers to it by name", G.card_defs.archmage.asset == "archmage_tower")
	check("kingdom still validates", #validate.check(G) == 0)
end

return M
