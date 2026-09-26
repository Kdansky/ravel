-- Ghost Stories: a village of nine tiles ringed by four boards, and the rules
-- that live in the geometry between them.
--
-- The thing this file exists to hold still is that geometry. Village and boards
-- are one 5x5 grid, so "the tile beside the one you stand on" and "the ghost
-- space in front of you" are two patterns and no arithmetic — a Taoist on a
-- corner tile faces two spaces and one on an edge tile faces one, because that
-- is what `orthogonal` answers there. And every pattern in the file names both
-- of its directions, because the engine turns `y` round for every seat but the
-- first: `vert1` is "the tile in front" read from the south edge *and* from the
-- north, and the direction that leaves the board names nothing.
--
-- The other two are the haunting cycle — a figure walks card, stone, stone, and
-- the third step turns the first *active* tile in front of the ghost over — and
-- what an exorcism is worth, which is the dice, the whites, and whatever tokens
-- the player commits after seeing the roll.

local entity = require("entity")
local zones = require("zones")
local cards = require("cards")
local phase = require("phase")
local flow = require("flow")
local tags = require("tags")
local actions = require("actions")
local declaration = require("declaration")

local unpack = table.unpack or unpack

local M = {}

local SEATS = { "south", "west", "north", "east" }

local function start(seed)
	flow.init("ghost_stories.json", seed or 9)
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function box(key, seat_key)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == seat_key then return z end
	end
	return zones.find(key)
end

local function card_in(z, def_key)
	for _, id in ipairs((z or {}).cards or {}) do
		local c = entity.get(id)
		if c.def_key == def_key then return c end
	end
end

local function on_table(def_key)
	return card_in(zones.find("table"), def_key)
end

local function monk_of(seat_key)
	for e in entity.each("card") do
		if e.def_key == "monk" and e.zone_id and tags.owner_of(e) == seat_key then return e end
	end
end

local function ability(card, key)
	for _, u in ipairs(flow.usable_abilities(card.id) or {}) do
		if u.rule.key == key then return u.index end
	end
end

local function slot_at(col, row)
	for _, sid in ipairs(zones.find("table").slots) do
		local s = entity.get(sid)
		if s.stats.col == col and s.stats.row == row then return sid end
	end
end

-- Put a ghost on a named square without going through a Yin phase, so a test
-- about haunting is not also a test about the shuffle.
local function put(def_key, col, row)
	local t = zones.find("table")
	local c = cards.create(def_key, t.id)
	zones.place_in_slot(c.id, slot_at(col, row))
	return c
end

local function take_places()
	for _ = 1, 4 do
		local m = monk_of(zones.active_seat())
		flow.activate(m.id, { on_table("t_temple").id }, ability(m, "station"))
	end
end

local function button(key, seat_key)
	return card_in(box("choices", seat_key or zones.active_seat()), key)
end

local function press(key)
	local c = button(key)
	return c ~= nil and flow.play_card(c.id, {})
end

-- The dice are three bags of six, so a roll is whichever face is lying in the
-- tray. A test that is about the arithmetic says what they show.
local function set_dice(...)
	local want = { ... }
	local tray = zones.find("dice")
	for _, id in ipairs({ unpack(tray.cards) }) do
		local c = entity.get(id)
		zones.move_card(id, zones.find("bag" .. c.def_key:sub(2, 2)).id)
	end
	for n, face in ipairs(want) do
		local bag = zones.find("bag" .. n)
		for _, id in ipairs({ unpack(bag.cards) }) do
			if entity.get(id).def_key == "f" .. n .. "_" .. face then
				zones.move_card(id, tray.id)
			end
		end
	end
end

-- Lay the named ghosts on top of the deck, nearest first, so the next Yin phase
-- draws a known card.
local function stack_deck(keys)
	local deck = zones.find("deck")
	for i = #keys, 1, -1 do
		for j, id in ipairs(deck.cards) do
			if entity.get(id).def_key == keys[i] then
				table.remove(deck.cards, j)
				deck.cards[#deck.cards + 1] = id
				break
			end
		end
	end
end

-- Twelve ghosts that do nothing on arrival and nothing each turn, laid on top
-- of the deck: three quiet rounds, for a test that is about something else.
-- None of them yellow, so the south board stays as the test left it: a yellow
-- ghost would be laid there and a third one would be an overrun, which is a Qi
-- off the seat these tests are usually counting.
local QUIET = { "g_abysmal_a", "g_abysmal_b", "g_rotten_a", "g_rotten_b",
                "g_blood_a", "g_blood_b", "g_liquid_horror", "g_green_abom",
                "g_flesh", "g_hound", "g_fungus", "g_reaper" }

-- One turn's worth of clicking, whatever the phase is asking for: lay the ghost
-- that arrived, do nothing with the Taoist, end the turn.
local function nudge()
	local k = phase.current().key
	if k == "station" then
		local m = monk_of(zones.active_seat())
		return flow.activate(m.id, { on_table("t_temple").id }, ability(m, "station"))
	elseif k == "yin_place" then
		local g = entity.get(zones.find("arriving").cards[1])
		for _, u in ipairs(flow.usable_abilities(g.id) or {}) do
			for _, sid in ipairs(zones.find("table").slots) do
				if not entity.get(sid).occupant and flow.activate(g.id, { sid }, u.index) then
					return true
				end
			end
		end
		return false
	elseif k == "yang_move" then
		return press("no_move")
	elseif k == "yang_act" then
		return press("no_act")
	elseif k == "yang_exorcise" then
		return press("give_up")
	elseif k == "pavilion" then
		for _, id in ipairs(zones.find("table").cards) do
			local g = entity.get(id)
			local i = g.def_key:sub(1, 2):match("[gi]_") and ability(g, "blown")
			if i then
				for _, sid in ipairs(zones.find("table").slots) do
					if not entity.get(sid).occupant and flow.activate(g.id, { sid }, i) then
						return true
					end
				end
			end
		end
		return false
	elseif k == "yang_buddha" then
		return press("no_buddha")
	elseif k == "boon" then
		return press("take_qi") or press("take_yy")
	elseif k == "spoils" or k == "prayer" then
		for _, id in ipairs(zones.find("box").cards) do
			local u = (flow.usable_abilities(id) or {})[1]
			if u and flow.activate(id, {}, u.index) then return true end
		end
		return false
	end
	return false
end

-- Play on until the named seat is about to move again, having left whatever
-- turn we were standing in: a test that rigs the board after the Yin phase has
-- already run has to wait for the next one.
local function next_turn_of(key)
	local left = false
	for _ = 1, 120 do
		local k, s = phase.current().key, zones.active_seat()
		if k == "reveal" or k == "over" then return false end
		if s ~= key then left = true end
		if left and k == "yang_move" and s == key then return true end
		if not nudge() then return false end
	end
	return false
end

-- Round the table until the next ghost is waiting to be laid.
local function until_arrival()
	for _ = 1, 120 do
		if not nudge() then return false end
		if phase.current().key == "yin_place" then return true end
	end
	return false
end

local function haunted_count()
	local n = 0
	for _, id in ipairs(zones.find("table").cards) do
		local c = entity.get(id)
		if c.def_key:sub(1, 2) == "t_" and (c.stats.haunted or 0) > 0 then n = n + 1 end
	end
	return n
end


function M.test_ghost_stories_the_table_is_a_village_ringed_by_four_boards(check)
	start()
	local t = zones.find("table")
	local tiles, plaques, free = 0, 0, 0
	for _, id in ipairs(t.cards) do
		local k = entity.get(id).def_key
		if k:sub(1, 2) == "t_" then tiles = tiles + 1 end
		if k:sub(1, 7) == "plaque_" then plaques = plaques + 1 end
	end
	for _, sid in ipairs(t.slots) do
		if not entity.get(sid).occupant then free = free + 1 end
	end
	check("nine village tiles", tiles == 9, tostring(tiles))
	check("a plaque in each corner", plaques == 4, tostring(plaques))
	check("twelve ghost spaces, all empty", free == 12, tostring(free))
	check("fifty-five ghosts in the deck", #zones.find("deck").cards == 55)
	check("ten incarnations in the urn", #zones.find("urn").cards == 10)
	check("four Qi and a Yin-Yang apiece",
		seat("south").stats.qi == 4 and seat("east").stats.yy == 1)
	check("two Buddhas at the temple", #zones.find("shrine").cards == 2)
end

function M.test_ghost_stories_the_taoists_take_the_central_tile_then_south_begins(check)
	start()
	check("the game opens asking the seats to take their places",
		phase.current().key == "station" and zones.active_seat() == "south")
	take_places()
	local centre = on_table("t_temple")
	local standing = 0
	for _, s in ipairs(SEATS) do
		if monk_of(s) and monk_of(s).parent_id == centre.id then standing = standing + 1 end
	end
	check("all four Taoists stand on the central tile", standing == 4, tostring(standing))
	check("and South's turn begins", zones.active_seat() == "south")
end

function M.test_ghost_stories_a_taoist_walks_to_a_tile_beside_the_one_it_stands_on(check)
	start()
	stack_deck(QUIET)
	take_places()
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	local step = ability(m, "step")
	check("from the middle every tile is a step away",
		step ~= nil and flow.activate(m.id, { on_table("t_cemetery").id }, step))
	check("and the Taoist is standing on it",
		m.parent_id == on_table("t_cemetery").id)

	-- Cemetery is the near-left corner tile; Tea House is the far corner.
	while phase.current().key ~= "yang_move" or zones.active_seat() ~= "south" do
		if not nudge() then break end
	end
	step = ability(m, "step")
	check("the opposite corner is not",
		not (step and flow.activate(m.id, { on_table("t_tea_house").id }, step)))
	check("the tile next along is", step ~= nil
		and flow.activate(m.id, { on_table("t_altar").id }, step),
		tostring(step) .. " " .. phase.current().key)
end

function M.test_ghost_stories_a_corner_tile_faces_two_spaces_and_an_edge_tile_one(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- A yellow ghost of resistance one on the south board, and another on the
	-- west board, either side of the near-left corner.
	local south_ghost = put("g_ghoul", 2, 1)
	local west_ghost = put("g_drowned_maiden", 1, 2)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "blue", "white")
	check("standing in the corner, the Taoist faces the south board",
		ability(south_ghost, "exorcise") ~= nil)
	check("and the west board too", ability(west_ghost, "exorcise") ~= nil)

	local far = put("g_creeping_one", 4, 1)
	check("but not a space three squares away", ability(far, "exorcise") == nil)
end

function M.test_ghost_stories_a_haunter_turns_a_tile_over_every_second_yin_phase(check)
	start()
	stack_deck(QUIET)
	take_places()
	local ghoul = put("g_ghoul", 2, 1)
	check("its haunting figure starts on the card", ghoul.stats.haunt == 0)
	check("and South comes round again", next_turn_of("south"))
	check("the figure has walked onto the board", ghoul.stats.haunt == 1, tostring(ghoul.stats.haunt))
	check("no tile is dark yet", haunted_count() == 0, tostring(haunted_count()))
	check("South comes round once more", next_turn_of("south"),
		phase.current().key .. "/" .. zones.active_seat())
	check("the figure goes back to the card", ghoul.stats.haunt == 0, tostring(ghoul.stats.haunt))
	check("and the tile in front of it is haunted",
		on_table("t_cemetery").stats.haunted == 1)
end

function M.test_ghost_stories_a_haunting_walks_up_the_column_as_tiles_go_dark(check)
	start()
	stack_deck(QUIET)
	take_places()
	local ghoul = put("g_ghoul", 2, 1)
	on_table("t_cemetery").stats.haunted = 1
	ghoul.stats.haunt = 1
	check("South comes round", next_turn_of("south"))
	check("the nearest tile was already dark, so the next one goes",
		on_table("t_sorcerer").stats.haunted == 1)
	check("and the one beyond it is still lit",
		on_table("t_circle_tile").stats.haunted == 0)
end

function M.test_ghost_stories_a_ghost_with_nowhere_left_to_haunt_loses_the_village(check)
	start()
	stack_deck(QUIET)
	take_places()
	local ghoul = put("g_ghoul", 2, 1)
	for _, k in ipairs({ "t_cemetery", "t_sorcerer", "t_circle_tile" }) do
		on_table(k).stats.haunted = 1
	end
	ghoul.stats.haunt = 1
	for _ = 1, 40 do
		if phase.current().key == "reveal" or phase.current().key == "over" then break end
		if not nudge() then break end
	end
	check("the whole column is dark, so the village falls",
		phase.current().key == "reveal" or phase.current().key == "over",
		phase.current().key)
end

function M.test_ghost_stories_a_ghost_is_laid_on_the_board_of_its_own_colour(check)
	start()
	stack_deck({ "g_drowned_maiden" })
	take_places()
	local g = entity.get(zones.find("arriving").cards[1])
	check("a blue ghost is drawn", g.def_key == "g_drowned_maiden", g.def_key)
	local home = ability(g, "place_home")
	check("it offers its own board", home ~= nil)
	check("it refuses a space on another board",
		not flow.activate(g.id, { slot_at(2, 1) }, home))
	check("and takes one on the blue board", flow.activate(g.id, { slot_at(1, 3) }, home))
	check("where it now stands", g.stats.col == 1 and g.stats.row == 3)
end

function M.test_ghost_stories_a_full_board_sends_a_ghost_anywhere_free(check)
	start()
	stack_deck({ "g_drowned_maiden" })
	take_places()
	put("g_ghoul", 1, 2)
	put("g_ghoul", 1, 3)
	put("g_ghoul", 1, 4)
	local g = entity.get(zones.find("arriving").cards[1])
	check("its own board is full, so it has no home to go to",
		ability(g, "place_home") == nil)
	local free = ability(g, "place_free_south")
	check("the seat that is playing offers it anywhere", free ~= nil)
	check("and it lands there", free and flow.activate(g.id, { slot_at(3, 5) }, free))
end

function M.test_ghost_stories_an_exorcism_counts_the_dice_the_whites_and_the_tokens(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- Hopping Vampire: yellow, resistance three.
	local ghost = put("g_hopping_a", 2, 1)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "white", "blue")
	check("two of three is not enough for a resistance of three",
		ability(ghost, "exorcise") == nil)

	local tray = box("tao", "south")
	local token = cards.create("tao_yellow", tray.id)
	flow.play_card(token.id, {})
	check("the token is committed", #box("spent", "south").cards == 1)
	check("and now the exorcism stands up", ability(ghost, "exorcise") ~= nil)
	flow.activate(ghost.id, {}, ability(ghost, "exorcise"))
	check("the ghost is sent to hell", card_in(zones.find("hell"), "g_hopping_a") ~= nil)
	check("and the committed token is spent", #box("spent", "south").cards == 0)
end

function M.test_ghost_stories_a_ghost_the_dice_cannot_touch_still_answers_to_tokens(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- Walking Corpse wears the die shield: yellow, resistance one, and the Tao
	-- dice do nothing to it.
	local ghost = put("g_walking_corpse", 2, 1)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "yellow", "yellow")
	check("three yellow faces do nothing", ability(ghost, "exorcise") == nil)
	local token = cards.create("tao_yellow", box("tao", "south").id)
	flow.play_card(token.id, {})
	check("one yellow token does it", ability(ghost, "exorcise") ~= nil)
end

function M.test_ghost_stories_the_incarnation_comes_off_the_urn_with_ten_cards_left(check)
	start()
	take_places()
	local deck = zones.find("deck")
	while #deck.cards > 10 do
		zones.move_card(deck.cards[#deck.cards], zones.find("hell").id)
	end
	check("the next ghost is drawn", until_arrival())
	local g = entity.get(zones.find("arriving").cards[1])
	check("the card that arrives is Wu-Feng", g.def_key:sub(1, 2) == "i_", g.def_key)
	check("and the deck still holds its last ten", #deck.cards == 10, tostring(#deck.cards))
	check("the urn keeps the nine that were not chosen", #zones.find("urn").cards == 9)
end

function M.test_ghost_stories_exorcising_the_incarnation_saves_the_village(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- Vampire Lord: yellow, resistance four, and nothing else.
	local wu = put("i_vampire", 2, 1)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "yellow", "white")
	local tray = box("tao", "south")
	flow.play_card(cards.create("tao_yellow", tray.id).id, {})
	check("three faces and a token make four", ability(wu, "exorcise") ~= nil)
	flow.activate(wu.id, {}, ability(wu, "exorcise"))
	check("the incarnation is in hell", card_in(zones.find("hell"), "i_vampire") ~= nil)
	check("and the game is over",
		phase.current().key == "reveal" or phase.current().key == "over",
		phase.current().key)
end

function M.test_ghost_stories_a_board_with_three_ghosts_costs_a_qi_and_no_arrival(check)
	start()
	stack_deck(QUIET)
	take_places()
	put("g_ghoul", 2, 1)
	put("g_ghoul", 3, 1)
	put("g_ghoul", 4, 1)
	check("South comes round", next_turn_of("south"))
	check("the overrun cost a Qi", seat("south").stats.qi == 3, tostring(seat("south").stats.qi))
	check("and the arrival was skipped", seat("south").stats.skip == 1,
		tostring(seat("south").stats.skip))
end

function M.test_ghost_stories_the_sorcerers_hut_discards_without_reward_and_costs_a_qi(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- Lich: yellow, resistance four, and a Qi or a Yin-Yang to whoever exorcises
	-- it. The Sorcerer gives neither.
	local lich = put("g_lich", 2, 1)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_sorcerer").id }, ability(m, "step"))
	local hut = on_table("t_sorcerer")
	local ask = ability(hut, "ask")
	check("the villager answers to whoever stands on the tile", ask ~= nil)
	flow.activate(hut.id, { lich.id }, ask)
	check("the ghost is gone from the board", on_table("g_lich") == nil)
	check("it is not in hell either, so nothing watched it die",
		card_in(zones.find("hell"), "g_lich") == nil)
	check("and the Sorcerer took his price", seat("south").stats.qi == 3,
		tostring(seat("south").stats.qi))
	check("with no reward owed", seat("south").stats.boons == 0)
end

function M.test_ghost_stories_a_buddha_eats_the_ghost_laid_on_it(check)
	start()
	stack_deck({ "g_ghoul" })
	local buddha = entity.get(zones.find("shrine").cards[1])
	zones.move_card(buddha.id, zones.find("table").id)
	zones.place_in_slot(buddha.id, slot_at(2, 1))
	take_places()
	local g = entity.get(zones.find("arriving").cards[1])
	local onto = ability(g, "place_buddha")
	check("a ghost may be laid on the trap", onto ~= nil)
	check("and it goes", onto and flow.activate(g.id, { buddha.id }, onto))
	check("straight out of the game", g.zone_id == nil)
	check("and the Buddha goes back to the temple", #zones.find("shrine").cards == 2)
end


-- Strip a bag down to one face, so a roll that a test cannot interrupt still
-- lands where the test needs it.
local function rig_bag(key, face)
	local bag = zones.find(key)
	for _, id in ipairs({ unpack(bag.cards) }) do
		if entity.get(id).def_key ~= face then zones.move_card(id, zones.find("hell").id) end
	end
end

-- Walk the active Taoist onto a named tile and ask the villager there.
local function ask_at(tile_key, targets)
	local m = monk_of(zones.active_seat())
	flow.activate(m.id, { on_table(tile_key).id }, ability(m, "step"))
	local tile = on_table(tile_key)
	local i = ability(tile, "ask")
	return i ~= nil and flow.activate(tile.id, targets or {}, i), i
end

function M.test_ghost_stories_the_herbalist_hands_over_the_colours_the_dice_show(check)
	start()
	stack_deck(QUIET)
	take_places()
	rig_bag("bag1", "f1_yellow")
	rig_bag("bag2", "f2_blue")
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	check("the shop answers", ask_at("t_herbalist"))
	local tray = box("tao", "south")
	local got = {}
	for _, id in ipairs(tray.cards) do got[#got + 1] = entity.get(id).def_key end
	table.sort(got)
	check("two rolled colours, two tokens", table.concat(got, " ") == "tao_blue tao_yellow",
		table.concat(got, " "))
	check("and two dice lie in the tray", #zones.find("dice").cards == 2, tostring(#zones.find("dice").cards))
end

function M.test_ghost_stories_the_circle_of_prayer_makes_one_colour_easier_for_everybody(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- Ooze Devil: blue, resistance three, on the west board in front of the
	-- Sorcerer's Hut, which is a step from the Circle of Prayer.
	local ghost = put("g_ooze_a", 1, 3)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	check("the Circle answers", ask_at("t_circle_tile"))
	check("and asks for a token", phase.current().key == "prayer", phase.current().key)
	local blue
	for _, id in ipairs(zones.find("box").cards) do
		if entity.get(id).def_key == "tao_blue" then blue = entity.get(id) end
	end
	flow.activate(blue.id, {}, ability(blue, "pray"))
	check("the token stands on the tile", #zones.find("circle").cards == 1)

	check("South comes round", next_turn_of("south"))
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_sorcerer").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("blue", "blue", "yellow")
	check("two blue faces and the Circle beat a resistance of three",
		ability(ghost, "exorcise") ~= nil)
end

function M.test_ghost_stories_a_tormentor_rolls_the_curse_die_in_its_own_yin_phase(check)
	start()
	stack_deck(QUIET)
	take_places()
	rig_bag("curse_bag", "c_qi")
	put("g_lich", 2, 1)
	check("South comes round", next_turn_of("south"))
	check("the Curse die took a Qi", seat("south").stats.qi == 3,
		tostring(seat("south").stats.qi))
	check("and the die is lying face up", #zones.find("curse").cards == 1)
end

function M.test_ghost_stories_a_ghost_that_shuts_the_tao_off_shuts_it_off(check)
	start()
	stack_deck(QUIET)
	take_places()
	local ghost = put("g_hopping_a", 2, 1)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "yellow", "blue")
	local token = cards.create("tao_yellow", box("tao", "south").id)
	check("a token may be committed while nothing forbids it", flow.play_card(token.id, {}))
	flow.play_card(button("give_up").id, {})

	-- Black Widow: while it lives, nobody may spend a Tao token.
	put("g_widow_a", 3, 1)
	check("South comes round", next_turn_of("south"))
	press("roll_dice")
	local second = cards.create("tao_yellow", box("tao", "south").id)
	check("and now none may be", not flow.play_card(second.id, {}))
end

function M.test_ghost_stories_the_yin_yang_turns_a_haunted_tile_back(check)
	start()
	stack_deck(QUIET)
	take_places()
	on_table("t_cemetery").stats.haunted = 1
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local c = button("use_yy")
	check("the Yin-Yang is there to spend", c ~= nil)
	check("and it turns the tile back", flow.play_card(c.id, { on_table("t_cemetery").id }))
	check("the villager is home", on_table("t_cemetery").stats.haunted == 0)
	check("and the token is gone", seat("south").stats.yy == 0)
end

function M.test_ghost_stories_the_altar_turns_a_tile_back_and_calls_a_ghost(check)
	start()
	stack_deck(QUIET)
	take_places()
	on_table("t_tea_house").stats.haunted = 1
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local before = #zones.find("deck").cards
	check("the Altar answers", ask_at("t_altar", { on_table("t_tea_house").id }))
	check("the tile is lit again", on_table("t_tea_house").stats.haunted == 0)
	check("and a ghost was called for", seat("south").stats.incoming >= 1
		or #zones.find("deck").cards < before)
end

-- From the corner tile beside the cemetery the south Taoist faces a space on
-- the south board and one on the west board, and one roll may serve both.
local function corner_roll(...)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice(...)
end

local function face(zone_key, colour)
	for _, id in ipairs(zones.find(zone_key).cards) do
		local c = entity.get(id)
		if c.def_key:match("_" .. colour .. "$") then return c end
	end
end

function M.test_ghost_stories_one_roll_from_a_corner_splits_between_two_ghosts(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- Ghoul: yellow, resistance one. Drowned Maiden: blue, resistance one.
	local ghoul = put("g_ghoul", 2, 1)
	local maiden = put("g_drowned_maiden", 1, 2)
	corner_roll("yellow", "blue", "red")
	check("the Taoist faces two ghosts", seat("south").stats.facing == 2,
		tostring(seat("south").stats.facing))
	local blue = face("dice", "blue")
	check("a die may be kept back", ability(blue, "keep_back") ~= nil)
	flow.activate(blue.id, {}, ability(blue, "keep_back"))
	check("and it waits aside", face("aside", "blue") ~= nil)
	check("the blue ghost cannot be had with it set aside", ability(maiden, "exorcise") == nil)
	flow.activate(ghoul.id, {}, ability(ghoul, "exorcise"))
	check("the first exorcism leaves the phase open", phase.current().key == "yang_exorcise",
		phase.current().key)
	check("the dice it took are spent", face("dice", "yellow") == nil and face("dice", "red") == nil)
	check("and what was kept back is the purse now", face("dice", "blue") ~= nil)
	check("the ghost already driven out is not offered twice", ability(ghoul, "exorcise") == nil)
	check("the second ghost stands up", ability(maiden, "exorcise") ~= nil)
	flow.activate(maiden.id, {}, ability(maiden, "exorcise"))
	check("both go to hell", card_in(zones.find("hell"), "g_ghoul") ~= nil
		and card_in(zones.find("hell"), "g_drowned_maiden") ~= nil)
end

function M.test_ghost_stories_a_die_spent_on_one_ghost_is_gone_for_the_other(check)
	start()
	stack_deck(QUIET)
	take_places()
	local ghoul = put("g_ghoul", 2, 1)
	local maiden = put("g_drowned_maiden", 1, 2)
	corner_roll("yellow", "white", "red")
	check("the white face would do for blue", ability(maiden, "exorcise") ~= nil)
	flow.activate(ghoul.id, {}, ability(ghoul, "exorcise"))
	check("but it went with the yellow ghost", ability(maiden, "exorcise") == nil)
	check("and the Taoist may walk away", press("give_up"))
	check("the blue ghost still stands", card_in(zones.find("table"), "g_drowned_maiden") ~= nil)
end

function M.test_ghost_stories_an_edge_tile_keeps_nothing_back(check)
	start()
	stack_deck(QUIET)
	take_places()
	-- The Sorcerer's Hut is mid-edge on the west side, facing one space.
	local ghoul = put("g_ghoul", 1, 3)
	while phase.current().key ~= "yang_move" do
		if not nudge() then break end
	end
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_sorcerer").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "blue", "red")
	check("one ghost faced, so no die is kept back", ability(face("dice", "blue"), "keep_back") == nil)
	flow.activate(ghoul.id, {}, ability(ghoul, "exorcise"))
	check("and the exorcism ends the phase", phase.current().key ~= "yang_exorcise", phase.current().key)
end

function M.test_ghost_stories_two_ghosts_dying_at_once_each_roll_their_own_curse(check)
	start()
	stack_deck(QUIET)
	take_places()
	rig_bag("curse_bag", "c_qi")
	-- Zombie: yellow, resistance two. Blood Drinker: red, resistance two. Both
	-- roll the Curse die as they go.
	local zombie = put("g_zombie_a", 2, 1)
	local drinker = put("g_blood_a", 1, 2)
	corner_roll("yellow", "yellow", "red")
	local red = face("dice", "red")
	flow.activate(red.id, {}, ability(red, "keep_back"))
	flow.activate(zombie.id, {}, ability(zombie, "exorcise"))
	flow.play_card(cards.create("tao_red", box("tao", "south").id).id, {})
	flow.activate(drinker.id, {}, ability(drinker, "exorcise"))
	check("two curses, two Qi", seat("south").stats.qi == 2, tostring(seat("south").stats.qi))
end


-- Each seat is dealt one side of its board at random, so a test about a power
-- hands the seat the one it is about and has every seat ask again.
local function give_power(seat_key, tag)
	local pz, sides = box("power", seat_key), zones.find("sides")
	for _, id in ipairs({ unpack(pz.cards) }) do zones.move_card(id, sides.id) end
	for e in entity.each("card") do
		if e.def_key == "p_" .. tag and e.zone_id then
			zones.move_card(e.id, pz.id)
			e.stats.owner = declaration.G.seat_index[seat_key]
		end
	end
	actions.execute("each_seat:settle_powers", {})
end

local function to_yang_move()
	while phase.current().key ~= "yang_move" do
		if not nudge() then return false end
	end
	return true
end

local BOARD = { south = { "pockets", "enfeeble" }, west = { "gust", "second_wind" },
                north = { "favour", "strength" }, east = { "spires", "twin_winds" } }

function M.test_ghost_stories_each_seat_is_dealt_one_side_of_its_own_board(check)
	start()
	take_places()
	for _, s in ipairs(SEATS) do
		local pz = box("power", s)
		local k = #pz.cards == 1 and entity.get(pz.cards[1]).def_key
		check(s .. " holds one power", k ~= false, tostring(#pz.cards))
		check(s .. "'s is one of its board's two",
			k == "p_" .. BOARD[s][1] or k == "p_" .. BOARD[s][2], tostring(k))
	end
	check("the other four sides stay in the box", #zones.find("sides").cards == 4)
end

function M.test_ghost_stories_bottomless_pockets_takes_a_token_before_the_move(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "pockets")
	local before = #box("tao", "south").cards
	local token = card_in(zones.find("box"), "tao_red")
	check("a token in the supply may be taken", ability(token, "pocket") ~= nil)
	flow.activate(token.id, {}, ability(token, "pocket"))
	check("it is in South's hand", #box("tao", "south").cards == before + 1)
	token = card_in(zones.find("box"), "tao_blue")
	check("but only one a turn", ability(token, "pocket") == nil)
end

function M.test_ghost_stories_a_ghost_on_the_board_switches_its_power_off(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "pockets")
	local token = card_in(zones.find("box"), "tao_red")
	check("the power works", ability(token, "pocket") ~= nil)

	local breakers = put("g_coffin_a", 3, 1)
	actions.execute("each_seat:settle_powers", {})
	check("Coffin Breakers on the south board switch it off", seat("south").stats.powered == 0)
	check("and there is nothing to take", ability(token, "pocket") == nil)
	check("the west board keeps its own", seat("west").stats.powered == 1)

	zones.move_card(breakers.id, zones.find("hell").id)
	actions.execute("each_seat:settle_powers", {})
	check("gone, and the power is back", ability(token, "pocket") ~= nil)

	put("i_forgotten", 1, 3)
	actions.execute("each_seat:settle_powers", {})
	local on = 0
	for _, s in ipairs(SEATS) do on = on + seat(s).stats.powered end
	check("the Forgotten Ones switch off every power", on == 0, tostring(on))
end

function M.test_ghost_stories_the_mantra_weakens_a_ghost_and_is_lost_with_the_power(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "enfeeble")
	local vampire = put("g_hopping_a", 2, 1)
	local card = card_in(box("power", "south"), "p_enfeeble")
	check("the Mantra goes on a ghost",
		flow.activate(card.id, { vampire.id }, ability(card, "chant")) and vampire.stats.mantra == 1)
	check("once a turn", ability(card, "chant") == nil)

	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	set_dice("yellow", "white", "blue")
	check("two yellows now beat a resistance of three", ability(vampire, "exorcise") ~= nil)
	press("give_up")

	put("g_coffin_a", 4, 1)
	actions.execute("each_seat:settle_powers", {})
	check("the power switched off takes the Mantra off the ghost", vampire.stats.mantra == 0)
	check("and out of the game", #box("power", "south").cards == 0)
end

function M.test_ghost_stories_the_dance_of_the_spires_flies_to_any_tile(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	check("South comes round", next_turn_of("south"))
	give_power("south", "spires")
	check("the far corner is no step",
		not flow.activate(m.id, { on_table("t_tea_house").id }, ability(m, "step") or 0))
	local fly = ability(m, "fly")
	check("a tile beside is not a flight",
		not (fly and flow.activate(m.id, { on_table("t_altar").id }, fly)))
	check("but the far corner is",
		fly ~= nil and flow.activate(m.id, { on_table("t_tea_house").id }, fly))
	check("and the Taoist stands there", m.parent_id == on_table("t_tea_house").id)
end

function M.test_ghost_stories_strength_of_a_mountain_rolls_four_and_never_curses(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "strength")
	local zombie = put("g_zombie_a", 2, 1)
	local m = monk_of("south")
	flow.activate(m.id, { on_table("t_cemetery").id }, ability(m, "step"))
	press("roll_dice")
	check("four dice", #zones.find("dice").cards == 4, tostring(#zones.find("dice").cards))
	set_dice("yellow", "yellow")
	flow.activate(zombie.id, {}, ability(zombie, "exorcise"))
	check("the Zombie is exorcised", card_in(zones.find("hell"), "g_zombie_a") ~= nil)
	check("and no Curse die was rolled", #zones.find("curse").cards == 0)
end

function M.test_ghost_stories_the_gods_favourite_rolls_a_die_once_more(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "favour")
	press("no_move")
	press("roll_dice")
	local face = entity.get(zones.find("dice").cards[1])
	local n = face.def_key:sub(2, 2)
	check("a die may be rolled again", flow.activate(face.id, {}, ability(face, "reroll")))
	local again
	for _, id in ipairs(zones.find("dice").cards) do
		local c = entity.get(id)
		if c.def_key:sub(2, 2) == n then again = c end
	end
	check("it is back in the tray", again ~= nil and #zones.find("dice").cards == 3)
	check("and may not be rolled a third time", again and ability(again, "reroll") == nil)
end

function M.test_ghost_stories_second_wind_acts_twice_of_one_kind(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "second_wind")
	press("no_move")
	press("roll_dice")
	press("give_up")
	check("after one exorcism the Taoist may act again", phase.current().key == "yang_act",
		phase.current().key)
	check("not with a villager", ability(on_table("t_temple"), "ask") == nil)
	check("but with a second roll", press("roll_dice"))
	press("give_up")
	check("and then the turn moves on", phase.current().key == "yang_buddha", phase.current().key)
end

function M.test_ghost_stories_heavenly_gust_asks_and_exorcises(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "gust")
	press("no_move")
	local temple = on_table("t_temple")
	check("the villager is asked", flow.activate(temple.id, {}, ability(temple, "ask")))
	check("the Taoist may act again", phase.current().key == "yang_act", phase.current().key)
	check("not with a second villager", ability(temple, "ask") == nil)
	check("but with an exorcism", press("roll_dice"))
	press("give_up")
	check("and then the turn moves on", phase.current().key == "yang_buddha", phase.current().key)
end


function M.test_ghost_stories_every_ghost_forgets_it_has_just_arrived(check)
	start()
	stack_deck(QUIET)
	take_places()
	check("round the table twice", next_turn_of("south") and next_turn_of("south"))
	local ghosts, fresh = 0, 0
	for _, id in ipairs(zones.find("table").cards) do
		local c = entity.get(id)
		if c.def_key:sub(1, 2) == "g_" then
			ghosts = ghosts + 1
			fresh = fresh + (c.stats.fresh or 0)
		end
	end
	check("several ghosts have arrived", ghosts >= 4, tostring(ghosts))
	-- A stat set on a zone without `each.` reaches its first card only, so every
	-- ghost after the first kept `fresh` and fired its arrival again.
	check("and none of them is still arriving", fresh == 0, tostring(fresh))
end


function M.test_ghost_stories_the_twin_winds_move_another_taoist_one_tile(check)
	start()
	stack_deck(QUIET)
	take_places()
	to_yang_move()
	give_power("south", "twin_winds")
	press("no_move")
	local card = card_in(box("power", "south"), "p_twin_winds")
	local lead = ability(card, "lead")
	check("South's own Taoist is not another",
		not (lead and flow.activate(card.id, { monk_of("south").id }, lead)))
	local west = monk_of("west")
	check("West's is", lead ~= nil and flow.activate(card.id, { west.id }, lead))
	check("and a tile is asked for", phase.current().key == "winds", phase.current().key)
	local altar = on_table("t_altar")
	check("a tile beside it takes it", flow.activate(card.id, { altar.id }, ability(card, "lead_to")))
	check("West's Taoist stands there", west.parent_id == altar.id)
	check("and is no longer being led", west.stats.guided == 0)
	check("South still has its action", phase.current().key == "yang_act", phase.current().key)
	check("and the winds blow once a turn", ability(card, "lead") == nil)
end

return M
