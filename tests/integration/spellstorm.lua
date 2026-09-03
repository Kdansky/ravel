-- Spellstorm, and the four rules its battle is made of.
--
-- None of them is a new engine word, and each is the kind of thing a rules
-- summary cannot confirm. Countering is one condition read across two battle
-- zones. Resolution order is set_active_seat pointed at a computed tag, which
-- matters because "mine" inside a card's own effect means whoever is up, so a
-- card resolved under the wrong seat heals the wrong player. Blast Scoring is
-- a subtraction that has to clamp at zero rather than go negative. And the
-- Power Track is six tokens becoming a Tier, which is the only arithmetic in
-- the game the action grammar cannot say in one line.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local function seat_card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if seat == nil or z.seat == seat then return z end
	end
end

local function find(def_key, zone_key)
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if e.def_key == def_key and z and (zone_key == nil or z.key == zone_key) then
			return e
		end
	end
end

-- Start a game and pick the two wizards named, in seat order. Everything below
-- runs after this, because nothing about a seat exists until it is chosen.
local function opening(seed, one, two)
	flow.init("spellstorm.json", seed)
	for _, name in ipairs({ one, two }) do
		local picked = false
		for _, id in ipairs(zones.find("options").cards) do
			if entity.get(id).def_key == "pick_" .. name then
				flow.play_card(id, {})
				picked = true
				break
			end
		end
		assert(picked, "no such wizard in the offer: " .. name)
	end
end

-- Put one named card into a seat's battle spot, whatever it was holding.
local function stage_battle(seat, def_key)
	local b = zone_of("battle", seat)
	for _, id in ipairs({ unpack(b.cards) }) do
		zones.move_card(id, zone_of("discard", seat).id)
	end
	local e = find(def_key)
	assert(e, "no " .. def_key .. " anywhere to stage")
	zones.move_card(e.id, b.id)
	-- A card reaches a battle spot by being played, which sets its owner along
	-- the way. Moved by hand it keeps whoever last held it, and "enemy.battle"
	-- would then not see it -- so hand it back to the zone it now lies in.
	e.stats.owner = nil
	return e
end

local function hand_of(seat) return zone_of("hand", seat) end

local function empty_hand(seat)
	local h = hand_of(seat)
	for _, id in ipairs({ unpack(h.cards) }) do
		zones.move_card(id, zone_of("deck", seat).id)
	end
end


-- "Resolve that card" means the card, not the first line of it.
--
-- `copy` used to run ability one and stop, which quietly dropped every rider
-- with an if in it and every question the card asks -- and a card that asks
-- keeps the asking in a later ability, so the offer opens after the rest of the
-- resolution has run. A copied Lapis drew and never offered its discard.
function M.test_spellstorm_a_copied_card_asks_what_it_would_have_asked(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	local lapis = stage_battle(one, "lapis")

	local keys = {}
	for _, a in ipairs(require("cards").abilities(lapis)) do keys[#keys + 1] = a.key end
	check("Lapis keeps its asking in a later ability, after the drawing",
		table.concat(keys, ",") == "cast,cast_ask", table.concat(keys, ","))

	local deck = #zone_of("deck", one).cards
	actions.execute("copy:target:activate", { card_id = lapis.id, targets = { lapis.id } })
	check("copying it drew, which is the deterministic half",
		#zone_of("deck", one).cards == deck - 1, #zone_of("deck", one).cards)
	check("and opened the question the card asks, which is the other half",
		phase.current().key == "options", phase.current().key)
	check("with the hand in it to choose from", #zones.find("options").cards > 0,
		#zones.find("options").cards)
end

-- The other half of the same rule: a discard effect is *not* part of resolving.
-- It is not an ability at all -- an ability is something the card does, and
-- every rule that runs abilities would then run this one. It is a `leaves`,
-- triggered by the card going from a hand to a discard, so no rule about
-- resolving has to know it exists and no card has to carry a condition saying
-- so on the off chance somebody copies it.
function M.test_spellstorm_a_copy_does_not_fire_a_discard_effect(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local seat = seat_card(one)

	-- Heart Gem heals 3 when resolved and costs 1 health when discarded, so the
	-- two halves pull opposite ways and the number tells which ran. Room to heal
	-- into first, or a full wizard hides the heal behind the cap.
	seat.stats.health = seat.stats.health - 5
	local hp = seat.stats.health
	local hg = stage_battle(one, "heartgem")
	actions.execute("copy:target:activate", { card_id = hg.id, targets = { hg.id } })
	check("the copy healed 3, so its cast ran", seat.stats.health == hp + 3,
		seat.stats.health .. " from " .. hp)

	-- And the same card, discarded out of the hand, pays the 1 it is printed
	-- with. Same card, same effect, and nothing about it says "unless".
	zones.move_card(hg.id, hand_of(one).id)
	hp = seat.stats.health
	zones.move_card(hg.id, zone_of("discard", one).id)
	check("discarded from hand, it costs the 1", seat.stats.health == hp - 1,
		seat.stats.health .. " from " .. hp)
end

-- VOIDing is not discarding, which the rulebook says once and the card now says
-- not at all: "into" already names the only landing that counts.
function M.test_spellstorm_voiding_a_card_is_not_discarding_it(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local seat = seat_card(one)
	seat.stats.health = seat.stats.health - 5

	local hg = find("heartgem")
	zones.move_card(hg.id, hand_of(one).id)
	local hp = seat.stats.health
	zones.move_card(hg.id, zones.find_id("void"))
	check("voided out of the hand, it costs nothing", seat.stats.health == hp,
		seat.stats.health .. " from " .. hp)
end

function M.test_spellstorm_the_box_is_the_published_one(check)
	flow.init("spellstorm.json", 1)
	local defs = require("declaration").G.card_defs
	local n = { wizard_card = 0, wizard_spell = 0, dragon = 0, weather = 0, essence = 0 }
	for _, def in pairs(defs) do
		for kind in pairs(n) do
			if (def.tags_set or {})[kind] then n[kind] = n[kind] + 1 end
		end
	end
	check("eight wizards", n.wizard_card == 8, tostring(n.wizard_card))
	check("two Wizard Spell Cards each", n.wizard_spell == 16, tostring(n.wizard_spell))
	check("five Dragons", n.dragon == 5, tostring(n.dragon))
	check("three Essence cards", n.essence == 3, tostring(n.essence))
	-- Nineteen designs rather than twenty-four cards: the print run doubles up
	-- four of the standard weather and one of the calm.
	check("nineteen weather designs", n.weather == 19, tostring(n.weather))

	-- The Essences start on the shelf, which is what the setup page says, and
	-- the shelf is filled to five from the deck before anybody acts.
	check("the Storm Cloud holds five", #zones.find("storm_cloud").cards == 5,
		tostring(#zones.find("storm_cloud").cards))
	local essences = 0
	for _, id in ipairs(zones.find("storm_cloud").cards) do
		if (entity.get(id).def_key or ""):find("essence$") then essences = essences + 1 end
	end
	check("three of them are the Essences", essences == 3, tostring(essences))

	-- Six ICE, six ASH, six CURSE. They are real stacks rather than a supply,
	-- so a pile that runs out really has run out.
	for _, k in ipairs({ "ice", "ash", "curse" }) do
		check("six " .. k, #zones.find(k .. "_pile").cards == 6,
			tostring(#zones.find(k .. "_pile").cards))
	end
end


function M.test_spellstorm_a_wizard_configures_the_seat(check)
	opening(5, "derby", "croh")
	local one, two = seat_card("seat_one"), seat_card("seat_two")
	check("Derby starts on 13 health", one.stats.health == 13, tostring(one.stats.health))
	check("Croh starts on 20", two.stats.health == 20, tostring(two.stats.health))

	-- Healing may not pass the wizard's starting health, and the ceiling is the
	-- only thing saying so -- a heal is written the same on every card.
	actions.execute("set_active_seat:seat_one", {})
	actions.execute("stat_gain:health@mine.player:10", {})
	check("Derby cannot heal past 13", one.stats.health == 13, tostring(one.stats.health))

	-- The lower Initiative rating begins with the tracker: Derby is 3, Croh 8.
	check("Derby holds the Initiative Tracker", one.stats.initiative == 1,
		tostring(one.stats.initiative))
	check("and Croh does not", two.stats.initiative == 0, tostring(two.stats.initiative))
	check("exactly one tracker exists",
		one.stats.initiative + two.stats.initiative == 1)

	-- Both wizards' spell cards are shuffled into their own starting deck, and
	-- neither is holding the other's.
	local mine = 0
	for _, where in ipairs({ "deck", "hand", "discard" }) do
		for _, id in ipairs(zone_of(where, "seat_one").cards) do
			local d = require("declaration").G.card_defs[entity.get(id).def_key]
			if (d.tags_set or {}).wizard_spell then mine = mine + 1 end
		end
	end
	check("Derby's two Wizard Spell Cards are shuffled into his own deck",
		mine == 2, tostring(mine))
end


function M.test_spellstorm_countering_draws_a_card(check)
	opening(5, "derby", "eve")
	-- Fire beats Earth, Earth beats Water, Water beats Fire. Countering the
	-- opponent draws you a card; being countered draws you nothing.
	local trials = {
		{ "fireball",   "twopower",   1, 0, "Fire counters Earth" },
		{ "twopower",   "block",      1, 0, "Earth counters Water" },
		{ "block",      "fireball",   1, 0, "Water counters Fire" },
		{ "fireball",   "magicdart",  0, 0, "Fire against Fire counters neither" },
	}
	for _, t in ipairs(trials) do
		local mine, theirs, want_one, want_two, why = t[1], t[2], t[3], t[4], t[5]
		stage_battle("seat_one", mine)
		stage_battle("seat_two", theirs)
		local h1, h2 = #hand_of("seat_one").cards, #hand_of("seat_two").cards
		actions.execute("each_seat:activate_zone:rules:by_column:check", {})
		check(why, #hand_of("seat_one").cards - h1 == want_one
			and #hand_of("seat_two").cards - h2 == want_two,
			("%+d / %+d"):format(#hand_of("seat_one").cards - h1,
				#hand_of("seat_two").cards - h2))
	end
end


function M.test_spellstorm_cards_resolve_in_initiative_order(check)
	opening(5, "derby", "eve")
	local one, two = seat_card("seat_one"), seat_card("seat_two")

	-- The whole reason resolution order is set by set_active_seat rather than
	-- walked both battle zones in turn: "mine" inside a card's own effect means
	-- whoever is up, so a card resolved under the wrong seat pays the wrong
	-- player. Magic Dart gains its caster a mana; run the pair and check the
	-- mana landed on the seat that played it.
	stage_battle("seat_two", "magicdart")
	stage_battle("seat_one", "sapphire")
	local m1, m2 = one.stats.mana, two.stats.mana
	local hp1 = one.stats.health

	actions.execute("set_active_seat:has_init", {})
	check("the seat with Initiative resolves first",
		zones.active_seat() == "seat_one", tostring(zones.active_seat()))
	actions.execute("activate_zone:mine.battle:by_column:cast", {})
	check("Sapphire's mana did not move", one.stats.mana == m1)
	actions.execute("set_active_seat:enemy.player", {})
	check("then the other seat", zones.active_seat() == "seat_two",
		tostring(zones.active_seat()))
	actions.execute("activate_zone:mine.battle:by_column:cast", {})
	check("Magic Dart's mana went to the seat that played it",
		two.stats.mana == m2 + 1 and one.stats.mana == m1,
		("%d / %d"):format(one.stats.mana, two.stats.mana))
	check("and Derby took no damage from it, having Initiative himself",
		one.stats.health == hp1, tostring(one.stats.health))
end


function M.test_spellstorm_blast_scoring(check)
	opening(5, "derby", "eve")
	local one, two = seat_card("seat_one"), seat_card("seat_two")

	-- The single highest Blast Score takes two Shards; a tie takes one each.
	local function score(a, b)
		empty_hand("seat_one"); empty_hand("seat_two")
		for i = 1, a do
			zones.move_card(find("moonstone", "spellstorm_deck")
				and find("moonstone", "spellstorm_deck").id
				or zone_of("deck", "seat_one").cards[1], hand_of("seat_one").id)
		end
		for i = 1, b do
			zones.move_card(zone_of("deck", "seat_two").cards[1], hand_of("seat_two").id)
		end
		actions.execute("each_seat:stat_set:ice_pen@mine.player:0", {})
		actions.execute("each_seat:activate_zone:rules:by_column:score", {})
		actions.execute("each_seat:activate_zone:rules:by_column:award_win", {})
		actions.execute("each_seat:activate_zone:rules:by_column:award_tie", {})
	end

	local s1, s2 = one.stats.shards, two.stats.shards
	score(3, 1)
	check("the higher Blast Score takes two Storm Shards",
		one.stats.shards == s1 + 2 and two.stats.shards == s2,
		("%d / %d"):format(one.stats.shards - s1, two.stats.shards - s2))

	s1, s2 = one.stats.shards, two.stats.shards
	score(2, 2)
	check("a tie takes one each",
		one.stats.shards == s1 + 1 and two.stats.shards == s2 + 1,
		("%d / %d"):format(one.stats.shards - s1, two.stats.shards - s2))

	-- Each ICE discarded in Regroup is -1, and a Blast Score never goes below
	-- nothing -- the stat's floor is what does the clamping.
	empty_hand("seat_one"); empty_hand("seat_two")
	zones.move_card(zone_of("deck", "seat_one").cards[1], hand_of("seat_one").id)
	actions.execute("set_active_seat:seat_one", {})
	actions.execute("stat_set:ice_pen@mine.player:5", {})
	actions.execute("activate_zone:rules:by_column:score", {})
	check("five ICE against one card is a Blast Score of nothing, not minus four",
		one.stats.blast == 0, tostring(one.stats.blast))
end


function M.test_spellstorm_the_power_track_becomes_a_tier(check)
	opening(5, "derby", "eve")
	local one = seat_card("seat_one")
	actions.execute("set_active_seat:seat_one", {})

	check("everyone starts at Tier I", one.stats.tier == 1, tostring(one.stats.tier))
	actions.execute("stat_set:power@mine.player:5", {})
	actions.execute("activate_zone:rules:by_column:tier_up", {})
	check("five tokens is not a Tier", one.stats.tier == 1 and one.stats.power == 5)

	-- Six fills the track: the Tier goes up and the six go back to the supply.
	-- The overflow is kept, which is why this is a subtraction and not a reset.
	actions.execute("stat_set:power@mine.player:8", {})
	actions.execute("activate_zone:rules:by_column:tier_up", {})
	check("a filled track is a Tier", one.stats.tier == 2, tostring(one.stats.tier))
	check("and the two spare tokens stay on it", one.stats.power == 2,
		tostring(one.stats.power))

	-- At Tier III a filled track is a Dragon instead.
	actions.execute("stat_set:tier@mine.player:3", {})
	actions.execute("stat_set:power@mine.player:6", {})
	local before = #hand_of("seat_one").cards
	actions.execute("activate_zone:rules:by_column:tier_gem", {})
	check("at Tier III a filled track gains a Dragon",
		#hand_of("seat_one").cards == before + 1, tostring(#hand_of("seat_one").cards - before))
	check("and the Tier does not go past III", one.stats.tier == 3, tostring(one.stats.tier))
	local top = entity.get(hand_of("seat_one").cards[#hand_of("seat_one").cards])
	check("what arrived is a Dragon",
		(require("declaration").G.card_defs[top.def_key].tags_set or {}).dragon == true,
		top.def_key)
end


function M.test_spellstorm_the_shelf_is_gated_by_tier(check)
	opening(5, "derby", "eve")
	actions.execute("set_active_seat:seat_one", {})
	-- Fireball II is Tier III. A Tier I wizard may look at it and not take it.
	local sc = zones.find("storm_cloud")
	for _, id in ipairs({ unpack(sc.cards) }) do
		zones.move_card(id, zones.find_id("spellstorm_deck"))
	end
	zones.move_card(find("fireball2").id, sc.id)
	zones.move_card(find("fireball").id, sc.id)
	local high, low = find("fireball2", "storm_cloud"), find("fireball", "storm_cloud")
	-- Taking a card off the shelf is an ability, and its "when" is the Tier gate.
	phase.push("gain_1")
	check("a Tier III card is out of reach at Tier I", not flow.can_activate(high.id))
	check("a Tier I card is not", flow.can_activate(low.id))
	actions.execute("stat_set:tier@mine.player:3", {})
	check("and at Tier III it is", flow.can_activate(high.id))

	-- ICE cannot be played out of a hand, ever -- it carries no play block at
	-- all, which is the whole of "this can't be played".
	local ice = zones.find("ice_pile").cards[1]
	zones.move_card(ice, hand_of("seat_one").id)
	check("ICE cannot be played from a hand", not flow.can_play(ice))
end


-- The face-down half of a simultaneous reveal. Worth its own test because it is
-- the one rule here that no action performs: a card is unreadable because of
-- where it lies, so the only proof is to ask the renderer's own question.
--
-- Asked through `as_seat` rather than by reading the turn, because that is what
-- the two cases really are: over the wire each client answers as the seat it
-- claimed, and in hot-seat the seat to play answers for the screen. One
-- function, both readings.
function M.test_spellstorm_a_played_card_is_face_down_until_the_showdown(check)
	opening(11, "derby", "eve")
	check("a round opens with the first seat playing", phase.current().key == "play_1",
		phase.current().key)

	local one = zones.active_seat()
	local played
	for _, id in ipairs(hand_of(one).cards) do
		if flow.can_play(id) then played = id; flow.play_card(id, {}); break end
	end
	assert(played, "seat one had nothing playable")
	local card = entity.get(played)

	check("the card went to the commit spot, not the battle spot",
		zone_of("commit", one).cards[1] == played,
		tostring(#zone_of("battle", one).cards))

	local mine, theirs
	zones.as_seat(one, function() mine = zones.visible(card) end)
	check("its own seat may read it", mine)

	-- The turn has passed by now, which is the whole of the question: the second
	-- player is choosing, and this is what they are choosing against.
	local two = zones.active_seat()
	check("the second seat is up", two ~= one and phase.current().key == "play_2",
		phase.current().key)
	zones.as_seat(two, function()
		theirs = zones.visible(card)
		check("nor may they look inside the zone holding it",
			not zones.peekable(zone_of("commit", one)))
	end)
	check("and the second seat cannot read the first card", not theirs)

	for _, id in ipairs(hand_of(two).cards) do
		if flow.can_play(id) then flow.play_card(id, {}); break end
	end

	-- Both cards down, and the rest of the round runs itself: showdown reveals,
	-- the two resolve steps fire, and round_end sweeps the battle spots into the
	-- discards. So the card is not caught standing in the battle zone -- what is
	-- worth checking is that it left the face-down zone and became readable.
	check("the commit spot is empty again", #zone_of("commit", one).cards == 0,
		tostring(#zone_of("commit", one).cards))
	zones.as_seat(two, function() theirs = zones.visible(card) end)
	check("and the card is in the open once the round has run", theirs)

	-- The reveal itself, pinned on its own: the showdown's first action is what
	-- turns the cards over, and everything after it reads `battle`.
	local staged = stage_battle(one, "magicdart")
	zones.move_card(staged.id, zone_of("commit", one).id)
	actions.execute("each_seat:move:mine.commit:mine.battle", {})
	check("the showdown's move is what puts a card in the battle spot",
		zone_of("battle", one).cards[1] == staged.id,
		tostring(#zone_of("commit", one).cards))
end

function M.test_spellstorm_a_battle_is_four_rounds_then_a_regroup(check)
	opening(7, "derby", "eve")
	-- Play the first playable card each time it is asked, take the first thing
	-- offered, and watch the shape of a battle rather than its content.
	local seen, guard = {}, 0
	while guard < 400 do
		guard = guard + 1
		local p = phase.current().key
		seen[p] = (seen[p] or 0) + 1
		if p == "reveal" then break end
		if p:find("^play") then
			local h, done = hand_of(zones.active_seat()), false
			for _, id in ipairs(h.cards) do
				if flow.can_play(id) then flow.play_card(id, {}); done = true; break end
			end
			if not done then
				-- A hand of nothing but ICE, ASH and CURSE. The board button is
				-- the rule for it, and a player has to press it.
				local btn
				for _, id in ipairs(zones.find("controls").cards) do
					if entity.get(id).def_key == "btn_unplayable" then btn = id end
				end
				if btn and flow.can_activate(btn) then flow.activate(btn, {}) else break end
			end
		elseif p:find("^gain") then
			local took = false
			for _, id in ipairs(zones.find("storm_cloud").cards) do
				if flow.can_activate(id) then flow.activate(id, {}); took = true; break end
			end
			if not took then
				local ip = zones.find("ice_pile")
				local top = ip.cards[#ip.cards]
				if top and flow.can_activate(top) then flow.activate(top, {}); took = true end
			end
			if not took then break end
		elseif p == "options" then
			-- An offer over an empty hand has nothing to pick, and declining is
			-- what a player does with it.
			local o = zones.find("options")
			if o.cards[1] then flow.play_card(o.cards[1], {})
			elseif not flow.dismiss_offer() then break end
		else
			break
		end
		if (seen.gain_2 or 0) >= 3 then break end
	end
	check("the battle ran its four rounds and regrouped, three times over",
		(seen.gain_2 or 0) >= 3, tostring(seen.gain_2))
	check("four plays per seat per battle",
		(seen.play_1 or 0) >= 12, tostring(seen.play_1))
	check("the Storm Cloud is still five deep after all of it",
		#zones.find("storm_cloud").cards == 5,
		tostring(#zones.find("storm_cloud").cards))
	check("nothing got stuck in the offer",
		#zones.find("options").cards == 0, tostring(#zones.find("options").cards))
end


function M.test_spellstorm_both_endings_are_reachable(check)
	opening(5, "derby", "eve")
	-- End conditions are asked when the game comes to rest, so a play is what
	-- makes it look. Any legal one will do.
	actions.execute("set_active_seat:seat_one", {})
	actions.execute("stat_set:shards@mine.player:8", {})
	for _, id in ipairs(hand_of("seat_one").cards) do
		if flow.can_play(id) then flow.play_card(id, {}) break end
	end
	check("eight Storm Shards ends the game",
		phase.current().key == "reveal" or #zones.find("reveal").cards > 0,
		phase.current().key)

	opening(5, "derby", "eve")
	actions.execute("set_active_seat:seat_two", {})
	actions.execute("stat_set:health@mine.player:0", {})
	actions.execute("set_active_seat:seat_one", {})
	for _, id in ipairs(hand_of("seat_one").cards) do
		if flow.can_play(id) then flow.play_card(id, {}) break end
	end
	check("nought health ends it too",
		phase.current().key == "reveal" or #zones.find("reveal").cards > 0,
		phase.current().key)
end

return M
