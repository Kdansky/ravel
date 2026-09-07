-- "@opponent" — *the* other seat, as against "@enemy", which is every seat but
-- mine.
--
-- The two say the same thing in a duel, which is why the corpus was written
-- entirely in `enemy` and nothing noticed. They part company the moment a third
-- player sits down, and they part company *silently*: a subject that meant one
-- player's health starts naming a pool of two, and the default quantifier picks
-- whichever of them the file declared first. So the pair is tested together, in
-- the same game, at two seats and at three — the difference is the whole reason
-- the word exists.

local entity = require("entity")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")

local M = {}

local NAMES = { "one", "two", "three" }

local function game(seats)
	local players, cards, place = {}, {}, {}
	for i = 1, seats do
		players[i] = '{ "card": "' .. NAMES[i] .. '" }'
		cards[i] = '{ "key": "' .. NAMES[i] .. '", "text": "' .. NAMES[i]
			.. '", "card_stats": { "health": 20 } }'
		place[i] = '{ "card": "' .. NAMES[i] .. '", "zone": "seat_box" }'
	end
	cards[#cards + 1] = '{ "key": "bolt", "text": "Bolt" }'
	place[#place + 1] = '{ "card": "bolt", "zone": "board" }'
	return [==[{
  "title": "Opponent",
  "players": []==] .. table.concat(players, ", ") .. [==[],
  "stats": [{ "key": "health", "min": 0, "label": "Health", "subject": "health@mine.player" }],
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [1, 1], "pos": [0.05, 0.10, 0.45, 0.30] },
    { "key": "seat_box", "status": "board", "layout": "row", "pos": [0.05, 0.60, 0.80, 0.90] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "next": [{ "then": "act" }] }],
  "cards": []==] .. table.concat(cards, ", ") .. [==[],
  "setup": { "place": []==] .. table.concat(place, ", ") .. [==[] }
}]==]
end

local function with_seats(n, fn)
	local path = "game/games/tmp_opponent.json"
	local f = assert(io.open(path, "w"))
	f:write(game(n))
	f:close()
	local ok, err = pcall(fn, "tmp_opponent.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- Every seat's health, in the order the file declared them.
local function healths()
	local out = {}
	for e in entity.each("card") do
		if e.stats and e.stats.health then out[#out + 1] = e.stats.health end
	end
	table.sort(out)
	return out
end

local function shows(t)
	return table.concat(t, ",")
end

function M.test_opponent_in_a_duel_is_the_other_seat(check)
	with_seats(2, function(name)
		flow.init(name, 3)
		check("mine reads the seat whose turn it is",
			predicate.total("health@mine.player", {}) == 20)
		actions.execute("stat_damage:health@opponent:2", {})
		check("the other seat took it and the acting seat did not",
			shows(healths()) == "18,20", shows(healths()))
	end)
end

-- Both words in one game, so the reading that changes is the only difference.
function M.test_opponent_and_enemy_agree_at_two_seats(check)
	with_seats(2, function(name)
		flow.init(name, 3)
		actions.execute("stat_damage:health@enemy.player:2", {})
		local by_enemy = shows(healths())
		flow.init(name, 3)
		actions.execute("stat_damage:health@opponent:2", {})
		check("with one opponent the two subjects do the same thing",
			by_enemy == shows(healths()), by_enemy .. " vs " .. shows(healths()))
	end)
end

-- The bug the word exists to make unwritable, and it is worse than the write-up
-- that asked for `opponent` guessed. `enemy` is honest — it always meant "not
-- me" — but the default quantifier is `any`, which lands on the *first* member
-- of a pool. So a duel's "deal 2 to your opponent" does not become a table-wide
-- effect when the table grows: it silently picks whichever opponent the file
-- declared first, and the other one is never touched. Written `each.enemy` it
-- would hit them all, which at least says so.
function M.test_opponent_at_three_seats_names_nobody_where_enemy_picks_one(check)
	with_seats(3, function(name)
		flow.init(name, 3)
		actions.execute("stat_damage:health@enemy.player:2", {})
		check("'enemy' silently picks whichever opponent comes first",
			shows(healths()) == "18,20,20", shows(healths()))
		flow.init(name, 3)
		actions.execute("stat_damage:health@each.enemy.player:2", {})
		check("and said with 'each' it hits both, which is the honest reading",
			shows(healths()) == "18,18,20", shows(healths()))

		flow.init(name, 3)
		actions.execute("stat_damage:health@opponent:2", {})
		check("'opponent' hits nobody rather than picking one or hitting all",
			shows(healths()) == "20,20,20", shows(healths()))
	end)
end

-- Failing closed is only half of it: silence at run time is no use to whoever
-- wrote the line. The validator is the half that says so — tested in
-- validator.lua, and named here because the two halves are one decision.
function M.test_opponent_a_read_is_absent_rather_than_wrong(check)
	with_seats(3, function(name)
		flow.init(name, 3)
		check("a comparison against it fails rather than reading somebody's number",
			predicate.meets_all({ "health@opponent >= 1" }, {}) == false)
		check("and so does the reverse, since absent is not zero",
			predicate.meets_all({ "health@opponent <= 1" }, {}) == false)
	end)
end

return M
