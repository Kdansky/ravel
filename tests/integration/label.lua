-- What a player-visible string may say about the thing it is written on.
--
-- Three labels used to be read off the engine instead of printed --
-- `current_phase`, `current_player`, `owning_player` -- and each was the whole
-- string, so a zone could say "whose deck" or "Deck" and never both. The brace
-- is the same idea with room around it, and it reaches the fields as well:
-- "{owner}'s deck", "{stats.health} left".
--
-- Only the drawing substitutes. A name is a caption, never an identity, so the
-- log and every condition still call the thing what the file called it.

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local flow        = require("flow")
local phase       = require("phase")
local label       = require("label")
local validate    = require("validate")

local M = {}

local GAME = [==[{
  "title": "Captions",
  "players": [{ "card": "one" }, { "card": "two" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "label": "{owner}'s hand",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "bag", "layout": "stack", "label": "{key} ({phase})",
      "pos": [0.55, 0.80, 0.65, 0.95] },
    { "key": "board", "layout": "grid", "grid": [1, 1], "label": "{active} to move",
      "pos": [0.55, 0.40, 0.65, 0.55] }
  ],
  "phases": [
    { "key": "act", "label": "Acting", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "Ada" },
    { "key": "two", "text": "Grace" },
    { "key": "torch", "text": "{stats.fuel} left", "tooltip": "A torch of {def_key}.",
      "card_stats": { "fuel": 3 } },
    { "key": "plain", "text": "Nothing to say" }
  ],
  "setup": { "place": [{ "card": "torch", "zone": "bag" }] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_label.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_label.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if not seat or z.seat == seat then return z end
	end
end

-- The one this was built for: two hands facing each other, each saying which.
function M.test_label_a_per_seat_zone_names_its_own_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the first hand is the first seat's",
			label.fill(zone_of("hand", "one").label, zone_of("hand", "one")) == "Ada's hand",
			label.fill(zone_of("hand", "one").label, zone_of("hand", "one")))
		check("and the second is the second's",
			label.fill(zone_of("hand", "two").label, zone_of("hand", "two")) == "Grace's hand",
			label.fill(zone_of("hand", "two").label, zone_of("hand", "two")))
	end)
end

-- The seat *card's* text, not the key the file spells it with. A player reads
-- "Ada"; "one" is a spelling.
function M.test_label_a_seat_is_named_not_keyed(check)
	with_game(function(name)
		flow.init(name, 3)
		local z = zone_of("board")
		check("the moment names whoever is up", label.fill(z.label, z) == "Ada to move",
			label.fill(z.label, z))
	end)
end

-- Two names in one string, which is the whole of what whole-string matching
-- could not do.
function M.test_label_reads_more_than_one_name_in_a_string(check)
	with_game(function(name)
		flow.init(name, 3)
		local z = zone_of("bag")
		check("a field and a moment side by side", label.fill(z.label, z) == "bag (Acting)",
			label.fill(z.label, z))
	end)
end

-- A card's own numbers, which move. The entity is asked before its definition,
-- because the entity is the current answer.
function M.test_label_reads_a_stat_off_the_card_it_is_on(check)
	with_game(function(name)
		flow.init(name, 3)
		local torch
		for e in entity.each("card") do if e.def_key == "torch" then torch = e end end
		local def = declaration.G.card_defs.torch
		check("the number it is carrying now", label.fill(def.text, torch) == "3 left",
			label.fill(def.text, torch))
		torch.stats.fuel = 1
		check("and again when it changes", label.fill(def.text, torch) == "1 left",
			label.fill(def.text, torch))
		check("a runtime field answers too", label.fill(def.tooltip, torch) == "A torch of torch.",
			label.fill(def.tooltip, torch))
	end)
end

-- 3, not 3.0. A count has no decimal point unless the game put one there.
function M.test_label_prints_a_whole_number_whole(check)
	with_game(function(name)
		flow.init(name, 3)
		local torch
		for e in entity.each("card") do if e.def_key == "torch" then torch = e end end
		torch.stats.fuel = 2.0
		check("no decimal point on a whole number",
			label.fill("{stats.fuel}", torch) == "2", label.fill("{stats.fuel}", torch))
		torch.stats.fuel = 2.5
		check("and one where the number really has it",
			label.fill("{stats.fuel}", torch):find("2.5", 1, true) ~= nil,
			label.fill("{stats.fuel}", torch))
	end)
end

-- Left standing rather than blanked. "{ownr}'s hand" says where the typo is;
-- "'s hand" says a name went missing and not which.
function M.test_label_leaves_a_name_nothing_answers_visible(check)
	with_game(function(name)
		flow.init(name, 3)
		local z = zone_of("bag")
		check("the braces stay", label.fill("{ownr} of {key}", z) == "{ownr} of bag",
			label.fill("{ownr} of {key}", z))
		check("and so does a field holding a list",
			label.fill("{cards}", z) == "{cards}", label.fill("{cards}", z))
	end)
end

-- Substituted once. A seat whose own text said "{owner}" would otherwise be a
-- label that resolves for ever.
function M.test_label_does_not_read_its_own_answer(check)
	with_game(function(name)
		flow.init(name, 3)
		local z = zone_of("bag")
		z.label = "{key}"
		z.key = "{active}"
		check("the answer is printed, not re-read", label.fill(z.label, z) == "{active}",
			label.fill(z.label, z))
	end)
end

-- A string with no brace in it is the common case and must cost nothing, so it
-- comes back as the very same string rather than a copy.
function M.test_label_leaves_ordinary_prose_alone(check)
	with_game(function(name)
		flow.init(name, 3)
		local s = "Nothing to say"
		check("untouched", label.fill(s, nil) == s)
		check("and a brace that is not a name is prose",
			label.fill("{ two words }", nil) == "{ two words }")
	end)
end

-- The engine's three words answer with no entity at all, because they are about
-- the moment rather than about the thing wearing the label.
function M.test_label_the_moment_needs_nothing_to_be_about(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the phase", label.fill("{phase}", nil) == "Acting", label.fill("{phase}", nil))
		check("and whoever is up", label.fill("{active}", nil) == "Ada", label.fill("{active}", nil))
		check("but not an owner, which needs something to own it",
			label.fill("{owner}", nil) == "{owner}")
	end)
end

-- The validator cannot say what a name will read, and does not try. What it can
-- say is that nothing will ever answer it.
function M.test_label_the_validator_names_a_name_nothing_answers(check)
	local said = {}
	local bad = GAME:gsub('"label": "{key} %({phase}%)"', '"label": "{kye} ({phase})"')
	local path = "game/games/tmp_label_bad.json"
	local f = assert(io.open(path, "w")); f:write(bad); f:close()
	local G = declaration.parse("tmp_label_bad.json")
	for _, p in ipairs(validate.check(G)) do said[#said + 1] = p end
	os.remove(path)
	local s = table.concat(said, "; ")
	check("it says which name and where", s:find("{kye}", 1, true) and s:find("zone 'bag'", 1, true), s)
	check("and that the good one beside it is fine", not s:find("{phase}", 1, true), s)
end

-- The engine prints the phase in the top-right corner because most games leave
-- it unsaid, and a corner is the only place no layout has claimed. A game that
-- writes "{phase}" of its own has claimed one, so the corner goes quiet rather
-- than saying the same words twice in two places.
function M.test_label_a_game_that_names_the_phase_is_not_told_it_twice(check)
	check("a game that never says it is told", declaration.parse("chess.json").shows_phase == false)
	local G = declaration.parse("spellstorm.json")
	check("and one that writes it on a zone is not", G.shows_phase == true)
	check("which is the zone it wrote it on", G.zone_defs.announce.label == "{phase}",
		G.zone_defs.announce.label)
end

return M
