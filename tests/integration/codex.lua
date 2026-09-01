-- Codex, and the three things about it that had to be proved rather than argued.
--
-- **Combat is a zone walked in steps**, so a keyword can speak between the blow
-- and the damage; **who may be attacked** is a `when` over computes
-- rather than a rule in the engine; and **the draw** is min(hand + 2, 5), which
-- is the floor used twice. Those are what these tests are pointed at.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")
local declaration = require("declaration")
local tags    = require("tags")

local M = {}

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- "enemy.base" the way a game file writes it, since half of what these tests
-- look at is on the other side of the table.
local function find_zone(zone_key)
	local owner, name = zone_key:match("^(%a+)%.(.+)$")
	return zones.find(name or zone_key, owner)
end

local function in_zone(zone_key, def_key)
	for _, cid in ipairs((find_zone(zone_key) or {}).cards or {}) do
		local c = entity.get(cid)
		if def_key == nil or c.def_key == def_key then return c end
	end
end

local function count_in(zone_key)
	return #((find_zone(zone_key) or {}).cards or {})
end

local function use(card, key, targets)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.ability.key == key then return flow.activate(card.id, targets or {}, u.index) end
	end
	return false
end

local function offers(card, key)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.ability.key == key then return true end
	end
	return false
end

-- Both seats pick a hero and the deal runs, which is the ordinary way in. The
-- picks are cards in an offer, so this plays them where a player would click.
local function start(south_hero, north_hero)
	flow.init("codex.json", 7)
	for _, want in ipairs({ south_hero, north_hero }) do
		local pick = in_zone("options", want)
		flow.play_card(pick.id, {})
		flow.settle()
	end
	flow.settle()
end

-- A patroller in a named post. The patrol zone is one row of five squares now,
-- so a test that wants the squad leader has to say which square, and stamp what
-- taking the post would have stamped.
local function post(def_key, owner, n)
	local z = zones.find("patrol", owner)
	local c = require("cards").create(def_key, z.id)
	zones.place_in_slot(c.id, z.slots[n])
	c.stats.ready_since, c.stats.slot = 1, n
	if n == 1 then c.stats.guard = 1 end
	-- The elite post's point of attack is not stamped here any more: "at_elite"
	-- buffs it for as long as the unit stands on square two, so setting the slot
	-- is the whole of taking the post.
	return c
end

-- Put a card straight onto the table, past its cost and its tech gate: these
-- tests are about what happens next, not about paying for it.
local function summon(def_key, zone_key)
	local owner, name = zone_key:match("^(%a+)%.(.+)$")
	local zid = zones.find_id(name or zone_key, owner)
	local c = require("cards").create(def_key, zid)
	c.stats.ready_since = 1
	return c
end

function M.test_codex_setup(check)
	start("pick_zane", "pick_argagarg")

	check("south holds its ten starting cards", count_in("hand") + count_in("deck") == 10,
		tostring(count_in("hand") + count_in("deck")))
	check("and five of them are in hand", count_in("hand") == 5, tostring(count_in("hand")))
	check("the codex is twenty-four cards", count_in("codex") == 24, tostring(count_in("codex")))
	check("the base stands at twenty", in_zone("base").stats.integrity == 20,
		tostring(in_zone("base").stats.integrity))
	check("the hero waits in the command zone", in_zone("command", "zane") ~= nil)
	check("south got four gold from four workers", seat("south").stats.gold == 4,
		tostring(seat("south").stats.gold))
	check("the turn opened in the main phase", phase.current().key == "main", phase.current().key)
end

-- A worker is a card turned face down, and it is the one cost paid in cards
-- rather than numbers that the game asks for every single turn.
function M.test_codex_worker(check)
	start("pick_zane", "pick_argagarg")
	local button = in_zone("controls", "hire_worker")
	local card   = entity.get(zones.find("hand").cards[1])

	check("hiring is offered", offers(button, "hire"))
	use(button, "hire", { card.id })
	check("the worker went face down", count_in("workers") == 1, tostring(count_in("workers")))
	check("and it is counted", seat("south").stats.workers == 5, tostring(seat("south").stats.workers))
	check("only one a turn", not offers(button, "hire"))
end

-- The whole of the combat rule, in one exchange: he deals his attack, she deals
-- hers back, and the dead are swept to their owners' discard piles by the rules
-- zone the action list ends on.
function M.test_codex_combat(check)
	start("pick_zane", "pick_argagarg")
	local mine  = summon("mad_man", "army")                 -- 1/1
	local yours = post("tiger_cub", "enemy", 1)  -- 2/2, and 1 armor as leader
	
	check("only the squad leader may be struck", offers(mine, "strike_lead"))
	check("nothing else is on offer", not offers(mine, "strike_free"))

	use(mine, "strike_lead", { yours.id })
	flow.settle()

	check("the leader's armor ate the point", yours.stats.guard == 0, tostring(yours.stats.guard))
	check("so the cub is untouched", yours.stats.hp == 2, tostring(yours.stats.hp))
	check("and the mad man is dead", mine.zone_id == nil or entity.get(mine.id).stats.hp == nil
		or zones.find("discard").id == mine.zone_id, tostring(mine.zone_id))
	check("he landed in his own discard", count_in("discard") == 1, tostring(count_in("discard")))
end

-- The patrol rule is a condition over computes, not a branch in the engine: a
-- ground unit may not reach a flier, so a flying squad leader is one it walks
-- past rather than one it is stuck on.
function M.test_codex_patrol_rules(check)
	start("pick_zane", "pick_argagarg")
	local ground = summon("mad_man", "army")
	local flier  = post("shoddy_glider", "enemy", 1)

	check("a ground unit cannot strike a flying leader", not offers(ground, "strike_lead"))
	check("but it may walk past one", offers(ground, "strike_free"))

	local hawk = summon("huntress", "army")   -- anti-air
	check("anti-air can reach the flier", offers(hawk, "strike_lead"))
	check("and so must not go past it", not offers(hawk, "strike_free"))
	flier.stats.alt = 0
	check("grounded, the leader stops the ground unit too", not offers(ground, "strike_free"))
	check("which is then the only thing it may hit", offers(ground, "strike_lead"))
end

-- The fight happens somewhere. Both sides step into the duel zone, the steps
-- run, and "origin" puts each of them back where it stood — which for a
-- patroller is its own slot and not the army.
function M.test_codex_combat_happens_in_a_zone(check)
	start("pick_zane", "pick_argagarg")
	local mine  = summon("tiger_cub", "army")               -- 2/2
	local yours = post("mad_man", "enemy", 3)   -- 1/1, and the scavenger post lends nothing

	check("the duel zone starts empty", count_in("duel") == 0)
	use(mine, "strike_patrol", { yours.id })
	flow.settle()

	check("and is empty again", count_in("duel") == 0, tostring(count_in("duel")))
	check("the survivor went back to the army", in_zone("army", "tiger_cub") ~= nil)
	check("the dead patroller was swept from its own slot", count_in("enemy.patrol") == 0)
	check("into its owner's discard", count_in("enemy.discard") == 1, tostring(count_in("enemy.discard")))
end

-- A patroller that survives keeps its post. Under the old action list the
-- attacker was posted to the army whatever it had been doing.
function M.test_codex_a_patroller_keeps_its_slot(check)
	start("pick_zane", "pick_argagarg")
	local mine  = summon("mad_man", "army")                -- 1/1
	local yours = post("bombaster", "enemy", 3) -- survives a 1
	yours.stats.slot = 3

	use(mine, "strike_patrol", { yours.id })
	flow.settle()
	check("it is still in the scavenger slot", count_in("enemy.patrol") == 1,
		tostring(count_in("enemy.patrol")))
end

-- Overpower: what the blow had left over goes past the patroller to the base.
-- It needs a step, because there is nothing left over until the blow has landed.
function M.test_codex_overpower(check)
	start("pick_zane", "pick_argagarg")
	local ram   = summon("crashbarrow", "army")           -- 6/2, overpower
	local guard = post("mad_man", "enemy", 1)  -- 1/1
	guard.stats.slot = 1
	local base  = in_zone("enemy.base")

	use(ram, "strike_lead", { guard.id })
	flow.settle()
	check("the leader's armor ate one and four went past it", base.stats.integrity == 16,
		tostring(base.stats.integrity))
end

-- Overpower is only for patrollers, so a unit standing in the army soaks it all.
function M.test_codex_overpower_stops_at_the_army(check)
	start("pick_zane", "pick_argagarg")
	local ram  = summon("crashbarrow", "army")
	local prey = summon("mad_man", "enemy.army")
	local base = in_zone("enemy.base")

	use(ram, "strike_free", { prey.id })
	flow.settle()
	check("the base is untouched", base.stats.integrity == 20, tostring(base.stats.integrity))
end

-- Deathtouch kills whatever it scratches, which is a rule about the *victim*
-- reading the card across it — a sentence an action list on the attacker had
-- nowhere to put.
function M.test_codex_deathtouch(check)
	start("pick_zane", "pick_argagarg")
	local snake = summon("tiny_basilisk", "army")        -- 1/2, deathtouch
	local ogre  = summon("bloodrage_ogre", "enemy.army") -- 3/2

	use(snake, "strike_free", { ogre.id })
	flow.settle()
	check("one point of deathtouch killed it", count_in("enemy.discard") == 1,
		tostring(count_in("enemy.discard")))
end

-- Long-range: the defender never gets to swing back.
function M.test_codex_long_range(check)
	start("pick_zane", "pick_argagarg")
	local ship = summon("doubleshot_archer", "army")  -- 4/3, long-range
	local prey = summon("bloodrage_ogre", "enemy.army")  -- 3/2

	use(ship, "strike_free", { prey.id })
	flow.settle()
	check("the archer took nothing back", entity.get(ship.id).stats.hp == 3,
		tostring(entity.get(ship.id).stats.hp))
	check("and the ogre is dead", count_in("enemy.discard") == 1)
end

-- Frenzy is +1 ATK on your turn, and it is added to a per-combat number rather
-- than to the printed one, so nothing has to be put back afterwards.
function M.test_codex_frenzy(check)
	start("pick_zane", "pick_argagarg")
	local dog  = summon("nautical_dog", "army")       -- 1/1, frenzy 1
	local prey = summon("tiger_cub", "enemy.army")    -- 2/2

	use(dog, "strike_free", { prey.id })
	flow.settle()
	check("it hit for two, not one", count_in("enemy.discard") == 1, tostring(count_in("enemy.discard")))
	check("and its printed attack is untouched", entity.get(dog.id).stats.atk == 1,
		tostring(entity.get(dog.id).stats.atk))
end

-- "Attacks:" is an ability at the aim step, which is the whole reason the steps
-- exist: it has to run after the target is chosen and before the damage lands.
function M.test_codex_attacks_trigger(check)
	start("pick_zane", "pick_argagarg")
	local archer = summon("doubleshot_archer", "army")
	local prey   = summon("tiger_cub", "enemy.army")
	local base   = in_zone("enemy.base")

	use(archer, "strike_free", { prey.id })
	flow.settle()
	check("three damage went to the base as it swung", base.stats.integrity == 17,
		tostring(base.stats.integrity))
end

-- A trigger that fires on the far side of the damage, which needs the step
-- after "land" and cannot be written before it.
function M.test_codex_kills_trigger(check)
	start("pick_zane", "pick_argagarg")
	local man   = summon("gunpoint_taxman", "army")       -- 3/3
	local guard = post("mad_man", "enemy", 1)  -- 1/1
	guard.stats.slot = 1
	seat("north").stats.gold = 3
	local gold, theirs = seat("south").stats.gold, seat("north").stats.gold

	use(man, "strike_lead", { guard.id })
	flow.settle()
	check("a gold was stolen", seat("south").stats.gold == gold + 1, tostring(seat("south").stats.gold))
	check("from the other player", seat("north").stats.gold == theirs - 1,
		tostring(seat("north").stats.gold))
end

-- "+4 ATK when attacking buildings" — nothing could ask what a strike was
-- aimed at until the target stood in the same zone as the attacker.
function M.test_codex_siege_bonus(check)
	start("pick_zane", "pick_argagarg")
	local tank = summon("steam_tank", "army")   -- 3/6
	local base = in_zone("enemy.base")

	use(tank, "strike_free", { base.id })
	flow.settle()
	check("it hit the base for seven", base.stats.integrity == 13, tostring(base.stats.integrity))
end

-- A ground defender with no anti-air cannot touch a flier, even the one that is
-- hitting it. The same condition reads on both sides of the fight.
function M.test_codex_a_flier_takes_nothing_back(check)
	start("pick_zane", "pick_argagarg")
	local bird = summon("shoddy_glider", "army")           -- 3/1, flying
	local prey = summon("bloodrage_ogre", "enemy.army")    -- 3/2, ground

	use(bird, "strike_free", { prey.id })
	flow.settle()
	check("the flier is unhurt", entity.get(bird.id).stats.hp == 1, tostring(entity.get(bird.id).stats.hp))
	check("though it would have died to the blow it never took", count_in("enemy.discard") == 1)
end

-- The squad leader's armor is spent by the first blow and does not come back
-- when it walks home from the duel. Only the upkeep refreshes it.
function M.test_codex_the_leaders_armor_is_spent_once(check)
	start("pick_zane", "pick_argagarg")
	local first  = summon("mad_man", "army")
	local second = summon("mad_man", "army")
	local lead   = post("tiger_cub", "enemy", 1)
	lead.stats.guard, lead.stats.slot = 1, 1

	use(first, "strike_lead", { lead.id })
	flow.settle()
	check("the armor took the first point", entity.get(lead.id).stats.hp == 2,
		tostring(entity.get(lead.id).stats.hp))
	check("and is gone", entity.get(lead.id).stats.guard == 0, tostring(entity.get(lead.id).stats.guard))

	use(second, "strike_lead", { lead.id })
	flow.settle()
	check("so the second blow lands", entity.get(lead.id).stats.hp == 1,
		tostring(entity.get(lead.id).stats.hp))
end

-- Sparkshot: 1 damage to a patroller beside the one struck. Adjacency is the
-- reason the five patrol zones became one row — a pattern needs squares, and
-- five zones of one square each have no neighbours. The row is asked before
-- anybody moves, because the defender leaves it the moment the fight starts.
function M.test_codex_sparkshot(check)
	start("pick_zane", "pick_argagarg")
	local hawk  = summon("huntress", "army")          -- 3/3, sparkshot
	local left  = post("bombaster", "enemy", 2)       -- 2/2 + the elite point
	local mid   = post("bombaster", "enemy", 3)
	local right = post("bombaster", "enemy", 4)
	local far   = post("bombaster", "enemy", 5)

	use(hawk, "strike_patrol", { mid.id })
	flow.settle()
	check("the neighbour on one side was sparked", entity.get(left.id).stats.hp == 1,
		tostring(entity.get(left.id).stats.hp))
	check("and the one on the other", entity.get(right.id).stats.hp == 1,
		tostring(entity.get(right.id).stats.hp))
	check("two posts along is not beside", entity.get(far.id).stats.hp == 2,
		tostring(entity.get(far.id).stats.hp))
	check("the one it actually hit took the whole blow", count_in("enemy.patrol") == 3,
		tostring(count_in("enemy.patrol")))
end

-- A gap in the row breaks adjacency, which is the rulebook's own wording and
-- something the pattern gets for nothing.
function M.test_codex_sparkshot_skips_a_gap(check)
	start("pick_zane", "pick_argagarg")
	local hawk = summon("huntress", "army")
	local mid  = post("bombaster", "enemy", 3)
	local gap  = post("bombaster", "enemy", 5)

	use(hawk, "strike_patrol", { mid.id })
	flow.settle()
	check("the post two along is untouched", entity.get(gap.id).stats.hp == 2,
		tostring(entity.get(gap.id).stats.hp))
end

-- Arrival fatigue is a stat the turn's opening sets, not a rule the engine
-- knows: a unit played this turn has not been readied yet.
function M.test_codex_arrival(check)
	start("pick_zane", "pick_argagarg")
	summon("tiger_cub", "enemy.army")
	local fresh = summon("mad_man", "army")
	fresh.stats.ready_since = 0
	check("a unit that just arrived cannot attack", not offers(fresh, "strike_free"))
	fresh.stats.ready_since = 1
	check("next turn it can", offers(fresh, "strike_free"))
end

-- Discard the hand, draw that many plus two, stop at five. The cap is
-- max(0, a - b) used once, which is the only arithmetic the grammar has.
function M.test_codex_draw(check)
	for _, case in ipairs({ { 0, 2 }, { 1, 3 }, { 2, 4 }, { 3, 5 }, { 5, 5 } }) do
		start("pick_zane", "pick_argagarg")
		local hand = zones.find("hand")
		while #hand.cards > case[1] do
			zones.move_card(hand.cards[#hand.cards], zones.find("discard").id)
		end
		flow.activate(in_zone("controls", "end_turn").id, {})
		flow.settle()
		check(("discarding %d draws %d"):format(case[1], case[2]),
			count_in("hand") == case[2], tostring(count_in("hand")))
	end
end

-- A tech building is raised into a site and finishes at the start of the next
-- turn, which is what "it doesn't finish until the end of your turn" costs.
function M.test_codex_tech(check)
	start("pick_zane", "pick_argagarg")
	local build = in_zone("controls", "build_t1")
	check("six workers are needed", not offers(build, "raise"))
	seat("south").stats.workers = 6
	check("with six it may be raised", offers(build, "raise"))
	use(build, "raise")
	check("it goes to the site first", count_in("site") == 1, tostring(count_in("site")))
	check("and is not yet a tech building", count_in("tech") == 0, tostring(count_in("tech")))
	check("the second one is free", seat("south").stats.t1_ever == 1)
end

-- Teching is the deckbuilding, and it is a `show:` of the codex answered by the
-- button's own `chosen` block: the real card moves, face down, into the discard.
function M.test_codex_teching(check)
	start("pick_zane", "pick_argagarg")
	flow.activate(in_zone("controls", "end_turn").id, {})
	flow.settle()
	check("the tech phase came round", phase.current().key == "tech", phase.current().key)
	check("with two picks owed", seat("south").stats.teched == 2, tostring(seat("south").stats.teched))

	local before = count_in("codex")
	flow.activate(in_zone("controls", "tech_button").id, {})
	flow.settle()
	local picked = entity.get(zones.find("options").cards[1])
	flow.play_card(picked.id, {})
	flow.settle()
	check("a codex card left the codex", count_in("codex") == before - 1, tostring(count_in("codex")))
	check("and one pick is left", seat("south").stats.teched == 1, tostring(seat("south").stats.teched))
end

-- Nothing about this game is in the engine, so the file has to say it. These
-- check the words it says rather than what they do.
function M.test_codex_shape(check)
	local G = declaration.G
	flow.init("codex.json", 7)

	check("two seats", #G.seat_list == 2, tostring(#G.seat_list))
	check("a hero is a fighter, so it fights like a unit",
		G.card_defs.zane.tags_set.fighter == true)
	check("and it dies to its own number, not a unit's",
		G.card_defs.zane.card_stats.life ~= nil and G.card_defs.zane.card_stats.hp == nil)
	check("a building dies to a third",
		G.card_defs.home_base.card_stats.integrity ~= nil)
	for _, key in ipairs({ "dead", "fallen", "rubble" }) do
		check("'" .. key .. "' is a computed tag", G.computed_tags[key] ~= nil)
	end
	local n = 0
	for key, def in pairs(G.card_defs) do
		if def.tags_set and def.tags_set.deck_card then n = n + 1 end
	end
	check("the box holds ninety-two printed cards", n == 92, tostring(n))
end

-- The hero waits in a zone that is not in play, which is what lets "do I have a
-- hero" be one condition and the summon be an ability on the hero itself.
function M.test_codex_hero(check)
	start("pick_zane", "pick_argagarg")
	local hero = in_zone("command", "zane")
	check("a hero in the command zone is not in play", not offers(hero, "lvl2"))
	check("but it may be summoned", offers(hero, "summon"))

	use(hero, "summon")
	flow.settle()
	check("it arrived on the table", in_zone("army", "zane") ~= nil)
	check("for two gold", seat("south").stats.gold == 2, tostring(seat("south").stats.gold))
	check("and cannot be summoned twice", not offers(hero, "summon"))

	check("levelling is now on offer", offers(hero, "lvl2"))
	seat("south").stats.gold = 9
	use(hero, "lvl2"); use(hero, "lvl3"); use(hero, "lvl4")
	check("level four heals and grows him", hero.stats.level == 4 and hero.stats.atk == 3
		and hero.stats.life == 3, hero.stats.level .. "/" .. hero.stats.atk .. "/" .. hero.stats.life)
	check("the max-level ability is still out of reach", not offers(hero, "shove"))
end

-- One turn each way: the seat changes, the building finishes, and the gold
-- arrives — all of it written on the phase rather than known by the engine.
function M.test_codex_turn(check)
	start("pick_zane", "pick_argagarg")
	seat("south").stats.workers = 6
	use(in_zone("controls", "build_t1"), "raise")

	flow.activate(in_zone("controls", "end_turn").id, {})
	flow.settle()
	seat("south").stats.teched = 0
	flow.settle()
	check("the turn passed to north", zones.active_seat() == "north", tostring(zones.active_seat()))
	check("and north is in their main phase", phase.current().key == "main", phase.current().key)

	flow.activate(in_zone("controls", "end_turn").id, {})
	flow.settle()
	seat("north").stats.teched = 0
	flow.settle()
	check("south is up again", zones.active_seat() == "south", tostring(zones.active_seat()))
	check("the tech building has finished", count_in("tech") == 1, tostring(count_in("tech")))
	check("and the site is clear", count_in("site") == 0, tostring(count_in("site")))
	check("six workers paid six gold", seat("south").stats.gold == 9, tostring(seat("south").stats.gold))
end

-- One patrol ability and five squares. Which post a card took is read off the
-- square it stands on and kept as a mark of its own, because the fight takes it
-- out of the row and the square stops answering.
function M.test_codex_slots(check)
	start("pick_zane", "pick_argagarg")
	local posts = zones.find("patrol", "mine")
	local unit  = summon("tiger_cub", "army")
	check("it starts at its printed attack", unit.stats.atk == 2, tostring(unit.stats.atk))

	use(unit, "go_patrol", { posts.slots[2] })
	check("the elite square lends it a point", tags.stat(unit, "atk") == 3, tostring(tags.stat(unit, "atk")))
	check("without writing on the card", unit.stats.atk == 2, tostring(unit.stats.atk))
	check("and it knows which post it took", unit.stats.slot == 2, tostring(unit.stats.slot))
	zones.move_card(unit.id, zones.find_id("army", "mine"))
	check("leaving takes both back", tags.stat(unit, "atk") == 2 and unit.stats.slot == 0,
		tostring(unit.stats.atk) .. "/" .. tostring(unit.stats.slot))

	local lead = summon("mad_man", "army")
	use(lead, "go_patrol", { posts.slots[1] })
	check("the squad leader is given its armor", lead.stats.guard == 1, tostring(lead.stats.guard))
	local look = summon("mad_man", "army")
	use(look, "go_patrol", { posts.slots[5] })
	check("the lookout gets neither", look.stats.guard == 0 and look.stats.atk == 1)
end

-- Burning the base down is the only way to win, and it is an end condition
-- rather than anything the combat knows about.
function M.test_codex_ending(check)
	start("pick_zane", "pick_argagarg")
	local base = entity.get(zones.find_id("base", "enemy")).cards[1]
	entity.get(base).stats.integrity = 2
	local ram = summon("crashbarrow", "army")   -- 6 attack

	check("with nothing patrolling, anything may be struck", offers(ram, "strike_free"))
	use(ram, "strike_free", { base })
	flow.settle()
	check("the base is down", entity.get(base).stats.integrity == 0,
		tostring(entity.get(base).stats.integrity))
	check("south is recorded as the winner", seat("south").stats.won == 1,
		tostring(seat("south").stats.won))
	check("and the game is over", phase.current().key == "game_over", phase.current().key)
end

-- A spell needs a hero and lands in the discard however it ends, which is what
-- `spent` is for: no action list has to remember to put its own card away.
function M.test_codex_spell(check)
	start("pick_jaina", "pick_argagarg")
	local hero = in_zone("command", "jaina")
	local spell = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local prey  = summon("tiger_cub", "enemy.army")

	check("no hero, no spell", not flow.can_play(spell.id))
	use(hero, "summon")
	flow.settle()
	seat("south").stats.gold = 9
	check("with the fire hero out it may be cast", flow.can_play(spell.id))

	flow.play_card(spell.id, { prey.id })
	flow.settle()
	check("three damage killed the cub", count_in("enemy.army") == 0 or prey.zone_id == nil
		or entity.get(prey.id).zone_id ~= zones.find_id("army", "enemy"))
	check("and the dart is in the discard", in_zone("discard", "fire_dart") ~= nil)
end

-- Three of the format's own idioms, put to work: a search is `show:` over the
-- codex narrowed by `chosen.where`, "choose one" is an `options:` list of two
-- cards, and a coin flip is a two-card deck read from the top.
function M.test_codex_search(check)
	start("pick_calamandra", "pick_argagarg")
	local hero = in_zone("command", "calamandra")
	use(hero, "summon")
	flow.settle()
	hero.stats.level = 5
	seat("south").stats.gold = 9

	check("the search is offered at max level", offers(hero, "call_tiger"))
	use(hero, "call_tiger")
	flow.settle()
	check("the whole codex comes up", count_in("options") == 24, tostring(count_in("options")))

	local tiger
	for _, cid in ipairs(zones.find("options").cards) do
		local c = entity.get(cid)
		if declaration.G.card_defs[c.def_key].tags_set.tiger then tiger = c end
	end
	check("and a tiger is among them", tiger ~= nil)
	local key = tiger and tiger.def_key
	flow.play_card(tiger.id, {})
	flow.settle()
	check("the tiger walked out of the codex onto the table",
		in_zone("army", key) ~= nil, tostring(key))
	check("and the rest went home", count_in("codex") == 23, tostring(count_in("codex")))
end

function M.test_codex_options(check)
	start("pick_calamandra", "pick_argagarg")
	local hero = in_zone("command", "calamandra")
	use(hero, "summon")
	flow.settle()
	seat("south").stats.gold = 9
	local spell = require("cards").create("murkwood_allies", zones.find_id("hand", "mine"))
	flow.play_card(spell.id, {})
	flow.settle()
	check("two shapes are offered", count_in("options") == 2, tostring(count_in("options")))
	flow.play_card(in_zone("options", "ma_frogs").id, {})
	flow.settle()
	check("four frogs joined the hero", count_in("army") == 5, tostring(count_in("army")))
	check("and the spell is spent", in_zone("discard", "murkwood_allies") ~= nil)
end

function M.test_codex_coin(check)
	start("pick_drakk", "pick_argagarg")
	local mine = summon("rickety_mine", "structures")
	seat("south").stats.gold = 0
	flow.activate(mine.id, {})
	flow.settle()
	check("the mine paid out", seat("south").stats.gold == 3, tostring(seat("south").stats.gold))
	check("and a coin came up", phase.current().key == "reveal", phase.current().key)
end

-- Knocking a tech building down costs its owner two off the base, which the
-- death sweep reads off the zone rather than off the card.
function M.test_codex_tech_falls(check)
	start("pick_zane", "pick_argagarg")
	local theirs = summon("tech_1", "enemy.tech")
	local ram = summon("crashbarrow", "army")   -- 6 attack, tech I has 5
	local base = entity.get(entity.get(zones.find_id("base", "enemy")).cards[1])

	use(ram, "strike_free", { theirs.id })
	flow.settle()
	check("the tech building is gone",
		#entity.get(zones.find_id("tech", "enemy")).cards == 0,
		tostring(#entity.get(zones.find_id("tech", "enemy")).cards))
	check("and their base took two for it", base.stats.integrity == 18,
		tostring(base.stats.integrity))
end

-- A cost amount may be a subject rather than a number, which is the only way
-- one play block can charge ninety cards ninety different prices. Everything
-- that spends one has always measured it; what showed one printed the string,
-- so every card in this game wore "price@self" where its price belonged.
function M.test_codex_measured_cost_reads_as_a_number(check)
	start("pick_zane", "pick_argagarg")
	local dog = require("cards").create("nautical_dog", zones.find_id("hand", "mine"))
	local def = declaration.G.card_defs.nautical_dog

	check("the cost is written as a measurement", def.cost["gold@mine.player"] == "price@self",
		tostring(def.cost["gold@mine.player"]))
	check("and it comes to what is printed on the card",
		require("cards").cost_amount(def.cost["gold@mine.player"], dog.id) == 1,
		tostring(require("cards").cost_amount(def.cost["gold@mine.player"], dog.id)))
	check("so the tooltip reads it as a price",
		require("cards").cost_text(def.cost, dog.id) == "1 gold@mine.player",
		require("cards").cost_text(def.cost, dog.id))
	check("with no card to ask, the expression is all there is to say",
		require("cards").cost_text(def.cost) == "price@self gold@mine.player",
		require("cards").cost_text(def.cost))
end

-- "Dies: do X" — the `leaves` moment, which fires on the way out of a board zone
-- and names the place it landed in, so death, exile and bounce are one sentence
-- pointed at three zones. `@self` is the departing card, which is the thing a
-- reaction cannot give: an emit names the emitter.
function M.test_codex_dies_moment(check)
	start("pick_drakk", "pick_argagarg")
	local bomber = post("crash_bomber", "enemy", 1)   -- 2/2, theirs
	local ram    = summon("crashbarrow", "army")                 -- 6 attack, mine
	local mybase = entity.get(entity.get(zones.find_id("base", "mine")).cards[1])

	use(ram, "strike_lead", { bomber.id })
	flow.settle()

	check("their bomber died", #entity.get(zones.find_id("patrol", "enemy")).cards == 0,
		tostring(#entity.get(zones.find_id("patrol", "enemy")).cards))
	check("and it went off in the face of whoever killed it",
		mybase.stats.integrity == 19, tostring(mybase.stats.integrity))
	check("landing in its owner's discard all the same",
		#entity.get(zones.find_id("discard", "enemy")).cards == 1,
		tostring(#entity.get(zones.find_id("discard", "enemy")).cards))
end

-- Nobody calls it. The bomber dies to a spell rather than to combat, down a
-- code path that knows nothing about deaths, and its rule still runs — which is
-- the whole reason this is a moment the engine fires rather than a zone a rules
-- card remembers to walk.
function M.test_codex_dies_on_every_route_out(check)
	start("pick_jaina", "pick_argagarg")
	local hero = in_zone("command", "jaina")
	use(hero, "summon")
	flow.settle()
	seat("south").stats.gold = 9
	local bomber = summon("crash_bomber", "enemy.army")
	local mybase = entity.get(entity.get(zones.find_id("base", "mine")).cards[1])
	local dart   = require("cards").create("fire_dart", zones.find_id("hand", "mine"))

	flow.play_card(dart.id, { bomber.id })
	flow.settle()
	check("three damage killed it", #entity.get(zones.find_id("army", "enemy")).cards == 0,
		tostring(#entity.get(zones.find_id("army", "enemy")).cards))
	check("and it still went off", mybase.stats.integrity == 19, tostring(mybase.stats.integrity))
end

-- The witness half. A unit's death is announced once, on the `unit` tag, so a
-- card watching from the board answers an ordinary reaction and no unit in the
-- game knows anything about being watched.
function M.test_codex_a_witness_answers_a_death(check)
	start("pick_drakk", "pick_argagarg")
	local watcher = summon("captured_bugblatter", "army")        -- 4/2, watching only
	local ox      = summon("land_octopus", "army")               -- 8/7, does the killing
	local prey    = post("tiger_cub", "enemy", 1)     -- 2/2
	prey.stats.guard = 0
	local mybase = entity.get(entity.get(zones.find_id("base", "mine")).cards[1])

	use(ox, "strike_lead", { prey.id })
	flow.settle()
	check("the cub died", #entity.get(zones.find_id("patrol", "enemy")).cards == 0,
		tostring(#entity.get(zones.find_id("patrol", "enemy")).cards))
	check("the octopus lived through it", entity.get(watcher.id).zone_id ~= nil
		and entity.get(ox.id).stats.hp == 5, tostring(entity.get(ox.id).stats.hp))
	check("and the bugblatter answered an announcement no unit knew it was making",
		mybase.stats.integrity == 19, tostring(mybase.stats.integrity))
end

-- Bounce is the same word pointed somewhere else, and a card that names the
-- discard says nothing at all about being returned to a hand.
function M.test_codex_leaves_only_where_it_says(check)
	start("pick_drakk", "pick_argagarg")
	local bomber = summon("crash_bomber", "army")
	local mybase = entity.get(entity.get(zones.find_id("base", "mine")).cards[1])

	zones.move_card(bomber.id, zones.find_id("hand", "mine"))
	check("bounced to hand, the death rule stayed quiet",
		mybase.stats.integrity == 20, tostring(mybase.stats.integrity))

	zones.move_card(bomber.id, zones.find_id("army", "mine"))
	zones.move_card(bomber.id, zones.find_id("patrol_lead", "mine"))
	check("and walking between two board zones is not leaving anything",
		mybase.stats.integrity == 20, tostring(mybase.stats.integrity))

	zones.move_card(bomber.id, zones.find_id("discard", "mine"))
	check("into the discard, it goes off", mybase.stats.integrity == 19,
		tostring(mybase.stats.integrity))
end

return M
