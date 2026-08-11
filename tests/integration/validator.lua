-- Every message the validator can print, fired exactly once.
--
-- One case per distinct message: mutate a freshly parsed (clean) tower
-- definition, run the validator, require the message. A case that stops firing
-- means the check silently died — which is the failure mode a validator has,
-- since a check that never runs looks exactly like a file with no problems.

local declaration = require("declaration")
local validate    = require("validate")
local actions     = require("actions")

local M = {}

local function has_problem(list, needle)
	for _, p in ipairs(list) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

local CASES = {
	-- condition subjects
	{ "an unknown tag in a count", "counts the tag 'dragons'",
		function(g) g.card_defs.c_flee.needs = { ["count:dragons"] = 1 } end },
	{ "a card check for a missing template", "checks for the card 'excalibur'",
		function(g) g.card_defs.c_flee.requires = { ["card:excalibur"] = 1 } end },
	{ "an unknown stat in routing", "uses the stat 'mana'",
		function(g) g.phase_by_key.story.next = { { stat = "mana", at_least = 1, ["then"] = "story" } } end },
	{ "a zone_empty that isn't a list", "zone_empty should be a list",
		function(g) g.end_conditions[2] = { zone_empty = "hand", ["then"] = {} } end },
	{ "a zone_empty watching a missing zone", "watches zone 'vault'",
		function(g) g.end_conditions[2] = { zone_empty = { "vault" }, ["then"] = {} } end },
	{ "an art spec the engine can't draw", "isn't a shape the engine can draw",
		function(g) g.card_defs.c_flee.asset = "hexagram:red" end },
	{ "a comparison against a bare word", "is a bare word",
		function(g) g.end_conditions[2] = { stat = "hp", at_least = "lots", ["then"] = {} } end },
	{ "a condition with no comparison", "no comparison",
		function(g) g.end_conditions[2] = { stat = "hp", ["then"] = {} } end },
	{ "an end condition with no then", "has no 'then'",
		function(g) g.end_conditions[2] = { stat = "hp", equals = 3 } end },
	-- maps and shapes
	{ "a cost that isn't a map", 'should be written like { "gold"',
		function(g) g.card_defs.c_flee.cost = "2 gold" end },
	{ "an unknown stat in a cost", "uses the stat 'mana'",
		function(g) g.card_defs.c_flee.cost = { mana = 1 } end },
	{ "a pos with the wrong count", "pos should be a list of 4 numbers",
		function(g) g.zone_defs.hand.pos = { 0, 0, 1 } end },
	{ "a pos with a non-number", "pos should contain only numbers",
		function(g) g.zone_defs.hand.pos = { 0, 0, 1, "x" } end },
	{ "a color with the wrong count", "color should be a list of 3 numbers",
		function(g) g.card_defs.c_flee.color = { 1, 2 } end },
	-- actions
	{ "an unknown action with a suggestion", "'moove_to' is not an action",
		function(g) g.card_defs.c_flee.on_play = { "moove_to:board" } end },
	{ "an action pointing at a missing zone", "points at zone 'vault'",
		function(g) g.card_defs.c_flee.on_play = { "draw_from:vault:hand:1" } end },
	{ "a gain of a missing card", "names the card 'excalibur'",
		function(g) g.card_defs.c_flee.on_play = { "gain:excalibur:1" } end },
	{ "a push_phase to a missing phase", "points at phase 'finale'",
		function(g) g.card_defs.c_flee.on_play = { "push_phase:finale" } end },
	{ "a load_game path-traversal attempt", "no folders or '..' are allowed",
		function(g) g.card_defs.c_flee.on_play = { "load_game:../../../etc/passwd" } end },
	{ "a load_game target that doesn't exist", "doesn't exist",
		function(g) g.card_defs.c_flee.on_play = { "load_game:no_such_game.json" } end },
	{ "an action missing its argument", "'reveal' is missing its card argument",
		function(g) g.card_defs.c_flee.on_play = { "reveal" } end },
	{ "an unknown tag in an action amount", "counts the tag 'dragons'",
		function(g) g.card_defs.c_flee.on_play = { "gain_stat:hp:count:dragons" } end },
	{ "a missing card in an action amount", "checks for the card 'excalibur'",
		function(g) g.card_defs.c_flee.on_play = { "gain_stat:hp:card:excalibur" } end },
	{ "a return_to draining a refilling zone", "refills itself when empty",
		function(g)
			g.zone_defs.chest_deck.tags_set.refill_when_empty = true
			g.card_defs.c_flee.on_play = { "return_to:chest_deck:hand" }
		end },
	{ "a non-string in an action list", "every action must be a text string",
		function(g) g.card_defs.c_flee.on_play = { 5 } end },
	-- stats
	{ "min/max on an engine-managed stat", "managed by the engine",
		function(g) g.stat_defs.round = { key = "round", min = 0 } end },
	{ "a stat with min above max", "greater than max",
		function(g) g.stat_defs.hp.min = 9 end },
	-- tag behaviour
	{ "a tag definition that isn't a map", 'should be written like { "zone"',
		function(g) g.tag_defs.keepsake = "board" end },
	{ "a tag homed in a missing zone", "sends cards to zone 'vault'",
		function(g) g.tag_defs.keepsake = { zone = "vault" } end },
	{ "a tag that is also computed", "defined under both",
		function(g) g.computed_tags.keepsake = { stat = "hp", equals = "0" } end },
	{ "a tag with behaviour nobody carries", "no card carries this tag",
		function(g) g.tag_defs.ghost = { zone = "board" } end },
	-- computed tags
	{ "a computed tag that isn't a map", 'should be written like { "stat"',
		function(g) g.computed_tags.ruined = 5 end },
	{ "a computed tag reading a missing card stat", "reads the card stat 'durability'",
		function(g) g.computed_tags.ruined = { stat = "durability", equals = "0" } end },
	-- cards
	{ "card tags that aren't a list", "tags should be a list",
		function(g) g.card_defs.c_flee.tags = "keepsake" end },
	{ "card_stats that aren't a map", "card_stats should be written like",
		function(g) g.card_defs.c_flee.card_stats = 3 end },
	{ "a non-number card stat", "the value of 'hp' should be a number",
		function(g) g.card_defs.c_flee.card_stats = { hp = "3" } end },
	{ "a target of an unknown type", "type should be 'card', 'slot' or 'zone'",
		function(g) g.card_defs.c_flee.target = { type = "hand", max = 1 } end },
	{ "a zone target naming no zones", "targets a zone but names none",
		function(g) g.card_defs.c_flee.target = { type = "zone", count = 1 } end },
	{ "a zone target filtering by tag", "zones are named, not tagged",
		function(g) g.card_defs.c_flee.target =
			{ type = "zone", count = 1, zones = { "board" }, tags = { "keepsake" } } end },
	{ "a card limited to a phase that does not exist", "no phase has that key",
		function(g) g.card_defs.c_flee.phases = { "nowhere" } end },
	{ "a zone handing out a tag nothing defines", "which nothing defines or reads",
		function(g) g.zone_defs.board.applies = { "flurble" } end },
	{ "a target looking for a missing tag", "looks for the tag 'dragons'",
		function(g) g.card_defs.c_flee.target = { type = "card", max = 1, tags = { "dragons" } } end },
	{ "a target searching a missing zone", "searches zone 'vault'",
		function(g) g.card_defs.c_flee.target = { type = "card", max = 1, zones = { "vault" } } end },
	{ "a bare move_to with no board at all", "no board zone to put it on",
		function(g)
			g.zone_defs.board = nil
			g.card_defs.c_flee.on_play = { "move_to" }
		end },
	{ "an auto_play into a missing zone", "starts in play, but its zone 'vault'",
		function(g)
			g.card_defs.c_flee.auto_play = true
			g.card_defs.c_flee.to_zone = "vault"
		end },
	-- zones
	{ "a board without grid dimensions", 'a board needs "grid"',
		function(g) g.zone_defs.board.grid = nil end },
	{ "grid dimensions with the wrong count", "grid should be a list of 2 numbers",
		function(g) g.zone_defs.board.grid = { 4 } end },
	{ "contents naming a missing card", "starts with the card 'excalibur'",
		function(g) g.zone_defs.chest_deck.contents = { "excalibur" } end },
	{ "a malformed contents entry", "should look like 'card' or 'card:3'",
		function(g) g.zone_defs.chest_deck.contents = { "p_chest_pearl:" } end },
	{ "contents that aren't a list", "contents should be a list",
		function(g) g.zone_defs.chest_deck.contents = "p_chest_pearl" end },
	-- phases
	{ "a phase with no type", "has no type",
		function(g) g.phase_by_key.story.type = nil end },
	{ "a phase drawing from a missing deck", "draws from 'vault'",
		function(g) g.phase_by_key.story.deck = "vault" end },
	{ "a phase dealing into a missing zone", "deals into 'vault'",
		function(g) g.phase_by_key.story.zone = "vault" end },
	{ "a draw that isn't a number", "draw should be a number",
		function(g) g.phase_by_key.story.draw = "two" end },
	{ "a pass card with no template", "its pass card 'excalibur'",
		function(g) g.phase_by_key.story.pass_card = "excalibur" end },
	{ "a forced-play phase without a pass card", "forces a play every turn",
		function(g) g.phase_by_key.story.type = "draw_and_play" end },
	{ "actions on a non-automatic phase", "only automatic phases run them",
		function(g) g.phase_by_key.story.actions = { "shuffle:chest_deck" } end },
	{ "a phase field that no longer exists", "the engine doesn't read",
		function(g) g.phase_by_key.story.on_pick = { "destroy:hand" } end },
	{ "routing that isn't a list", "next should be a list of routes",
		function(g) g.phase_by_key.story.next = "story" end },
	{ "routing on an overlay", "overlays pop back",
		function(g) g.phase_by_key.reveal.next = { { ["then"] = "story" } } end },
	{ "an unreachable route", "can never be reached",
		function(g) g.phase_by_key.story.next = { { ["then"] = "intro" }, { ["then"] = "story" } } end },
	{ "a route into an overlay", "which is an overlay",
		function(g) g.phase_by_key.story.next = { { ["then"] = "reveal" } } end },
	{ "automatic phases running in a circle", "in a circle",
		function(g) g.phase_by_key.intro.next = { { ["then"] = "intro" } } end },
	-- setup
	{ "an unknown setup section", "did you mean 'player'",
		function(g) g.setup.playr = {} end },
	{ "a non-number starting value", "the starting value of 'hp'",
		function(g) g.setup.player.hp = "six" end },
	-- persona-audit additions
	{ "a negative cost", "'gold' is negative",
		function(g) g.card_defs.c_flee.cost = { gold = -5 } end },
	{ "a sacrifice of an uncarried tag", "sacrifices the tag 'dragons'",
		function(g) g.card_defs.c_flee.cost = { ["sacrifice:dragons"] = 1 } end },
	{ "a sacrifice outside a cost", "belongs in cost or activate_cost",
		function(g) g.card_defs.c_flee.needs = { ["sacrifice:keepsake"] = 1 } end },
	{ "a missing image file", "is not in games/assets",
		function(g) g.card_defs.c_flee.asset = "no_such_file.png" end },
	{ "a web asset URL with characters that could break out of generated JS",
		"characters that aren't valid in a URL",
		function(g) g.card_defs.c_flee.asset = 'https://evil.example.com/x".onerror=alert;//' end },
	{ "a zone squatting on the UI corner", "lower-left corner",
		function(g) g.zone_defs.hand.pos = { 0.00, 0.60, 0.97, 0.97 } end },
	{ "a non-number ends_after", "ends_after should be a number",
		function(g) g.phase_by_key.story.ends_after = "two" end },
	{ "ends_after on an automatic phase", "only phases where cards are played",
		function(g) g.phase_by_key.intro.ends_after = 1 end },
	{ "discard_hand on an overlay", "overlays pop back — it never fires",
		function(g) g.phase_by_key.reveal.discard_hand = true end },
	{ "a misspelled outcome", "outcome should be 'victory' or 'defeat'",
		function(g) g.card_defs.e_pearl.outcome = "vctory" end },
	{ "an unknown base effect", "is not a base effect",
		function(g) g.effect_defs.oops = { base = "sparkles" } end },
	{ "an effect the game never defines", "defines no such effect",
		function(g) g.card_defs.c_flee.on_play = { "effect:big_boom" } end },
	{ "a non-number effect size", "size should be a number",
		function(g) g.effect_defs.bell_toll.size = "big" end },
	{ "contents beyond the board's capacity", "only has 5 slots",
		function(g) g.zone_defs.board.contents = { "pearl:9" } end },
	{ "an automatic phase that can stall", "when none matches, the game stalls",
		function(g) g.phase_by_key.intro.next = { { stat = "hp", at_least = 99, ["then"] = "story" } } end },
	{ "half of the reveal pair replaced", "define both or neither",
		function(g) g.zone_defs.reveal.injected = nil end },
	{ "an uncarried tag near a carried one", "did you mean 'keepsake'",
		function(g) g.tag_defs.keepsakes = { zone = "board" } end },
	{ "an activate_target with no ability", "no ability for it to target",
		function(g) g.card_defs.c_flee.activate_target = { type = "card", count = 1 } end },
	{ "a non-boolean exhausts", "exhausts should be true or false",
		function(g) g.card_defs.c_flee.exhausts = "no" end },
	{ "an unknown fill word", "fill should be 'empty', 'enemy', 'open' or 'any'",
		function(g) g.card_defs.c_flee.target = { type = "slot", count = 1, fill = "friendly" } end },
	{ "a pattern that isn't a list of pairs", "should be a list of [x, y] pairs",
		function(g) g.raw_patterns = { hop = { vectors = "north" } } end },
	{ "a direction that isn't a pair", "every direction is a pair of whole numbers",
		function(g) g.raw_patterns = { hop = { { 1, 2, 3 } } } end },
	{ "a direction that goes nowhere", "[0,0] is not a direction",
		function(g) g.raw_patterns = { hop = { { 0, 0 } } } end },
	{ "a class list that isn't a list", "\"class\" should be a list",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, class = "ray" } } end },
	{ "an unknown way of walking a pattern", "is not a way of walking a pattern",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, class = { "slide" } } } end },
	{ "a distance on something that is not a ray", "only 'ray' takes a distance",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, class = { "step:2" } } } end },
	{ "a piece moving by a pattern nobody declared", "but none is declared under",
		function(g)
			g.card_defs.c_flee.move_rules = { { patterns = { "line_ortho" }, fill = "open" } }
		end },
	{ "a move with an unknown fill", "a move's fill should be",
		function(g)
			g.raw_patterns = { hop = { { 1, 0 } } }
			g.pattern_defs.hop = { vectors = { { 1, 0 } }, range = 1 }
			g.card_defs.c_flee.move_rules = { { patterns = { "hop" }, fill = "friendly" } }
		end },
	{ "a piece that moves but does nothing on arrival", "no on_activate",
		function(g) g.card_defs.c_flee.moves = { "hop" }; g.card_defs.c_flee.on_activate = nil end },
	{ "a walking word on an absolute pattern", "has no path to describe",
		function(g)
			g.raw_patterns = { home = { vectors = { { 1, 1 } }, class = { "absolute", "ray" },
				zone = "board" } }
		end },
	{ "a zone named by a pattern of directions", "only an absolute pattern names a",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, zone = "board" } } end },
	{ "an absolute pattern pointing at no such zone", "no zone has that key",
		function(g)
			g.raw_patterns = { home = { vectors = { { 1, 1 } }, class = { "absolute" },
				zone = "vault" } }
		end },
	{ "fill on something that isn't a square", "only applies to \"type\": \"slot\"",
		function(g) g.card_defs.c_flee.target = { type = "card", count = 1, fill = "empty" } end },
	{ "a move_to that names no such tray", "happens to a piece already standing there",
		function(g) g.card_defs.c_flee.on_play = { "move_to:target:vault" } end },
	{ "an unknown fit in a style", "fit should be 'card' or 'fill'",
		function(g) g.style_defs = { tiled = { fit = "stretch" } } end },
	{ "a checker that isn't a pair of colours", "checker should be two colours",
		function(g) g.style_defs = { tiled = { checker = { "cream" } } } end },
	{ "a checker colour that isn't one", "is not a colour",
		function(g) g.style_defs = { tiled = { checker = { "cream", "octarine" } } } end },
	{ "painting squares no pattern names", "no pattern has that name",
		function(g) g.style_defs = { tiled = { paint = { throne = "gold" } } } end },
	{ "painting by a pattern of directions", "only an absolute pattern names squares",
		function(g)
			g.raw_patterns = { hop = { { 1, 0 } } }
			g.pattern_defs.hop = { vectors = { { 1, 0 } }, range = 1 }
			g.style_defs = { tiled = { paint = { hop = "gold" } } }
		end },
	{ "a style named after a zone", "a name may mean only one thing",
		function(g) g.style_defs = { board = { color = { 1, 0, 0 } } } end },
	{ "a tag and a zone sharing a name", "both a zone and a tag",
		function(g) g.tag_defs.board = { zone = "board" } end },
	{ "a tag claiming a reserved scope name", "reserves for conditions",
		function(g) g.tag_defs.self = { zone = "board" } end },
	{ "a zone claiming a reserved scope name", "reserves for conditions",
		function(g) g.zone_defs.all = { key = "all", type = "hand" } end },
	{ "a scope that names nothing", "neither a zone nor a tag",
		function(g) g.card_defs.c_flee.needs = { ["hp@nowhere"] = 1 } end },
	{ "a scope with a typo suggests the right one", "did you mean 'keepsake'",
		function(g) g.card_defs.c_flee.needs = { ["hp@keepsakes"] = 1 } end },
	{ "a measuring fn used as a cost", "cannot be a cost",
		function(g) g.card_defs.c_flee.cost = { ["count:keepsake"] = 1 } end },
	{ "two zones drawn on top of each other", "overlaps zone",
		function(g) g.zone_defs.board.pos = { 0.2, 0.2, 0.9, 0.9 }
			g.zone_defs.hand.pos = { 0.3, 0.3, 0.8, 0.8 } end },
}

function M.test_validator_names_every_problem_it_knows(check)
	for _, c in ipairs(CASES) do
		local g = declaration.parse("tower.json")
		c[3](g)
		check("validator flags " .. c[1], has_problem(validate.check(g), c[2]))
	end
end

-- The validator derives its checks from each op's declared shape: every
-- handler must declare one, or new actions silently skip validation.
function M.test_every_action_declares_its_argument_shape(check)
	local unspecced = {}
	for op in pairs(actions.ops()) do
		if not actions.spec(op) then unspecced[#unspecced + 1] = op end
	end
	check("every action declares its argument shape", #unspecced == 0,
		table.concat(unspecced, ", "))
end

return M
