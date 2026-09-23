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
local stats       = require("stats")

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

-- The codex is a box: twelve shelves two deep rather than twenty-four cards, so
-- what a test asks it is the stock written on the shelves.
local function stock_in(zone_key)
	local n = 0
	for _, cid in ipairs((find_zone(zone_key) or {}).cards or {}) do
		n = n + ((entity.get(cid).stats or {}).stock or 0)
	end
	return n
end

local function use(card, key, targets)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.rule.key == key then return flow.activate(card.id, targets or {}, u.index) end
	end
	return false
end

local function offers(card, key)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.rule.key == key then return true end
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
	start("pick_red", "pick_green")

	check("south holds its ten starting cards", count_in("hand") + count_in("deck") == 10,
		tostring(count_in("hand") + count_in("deck")))
	check("and five of them are in hand", count_in("hand") == 5, tostring(count_in("hand")))
	check("the codex is three specs of twelve kinds", count_in("codex") == 36, tostring(count_in("codex")))
	check("two copies of each", stock_in("codex") == 72, tostring(stock_in("codex")))
	check("the base stands at twenty", in_zone("base").stats.integrity == 20,
		tostring(in_zone("base").stats.integrity))
	check("all three heroes wait in the command zone", in_zone("command", "zane") and in_zone("command", "drakk")
		and in_zone("command", "jaina") and count_in("command") == 3)
	check("south got four gold from four workers", seat("south").stats.gold == 4,
		tostring(seat("south").stats.gold))
	check("the turn opened in the main phase", phase.current().key == "main", phase.current().key)
end

-- A worker is a card turned face down, and it is the one cost paid in cards
-- rather than numbers that the game asks for every single turn.
function M.test_codex_worker(check)
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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

-- **Unattackable by tech 0 units**, which is the other half and a different shape:
-- "t0" and "open_t0" are two numbers compared in the attack's own where, exactly
-- as "alt" and "aa" are. Walking past falls out of it — the tech 0 attacker finds
-- nothing to aim at in the leader post, so `aims:strike_lead` is zero and it is
-- free to go round without a compute anywhere saying why.
function M.test_codex_unattackable_by_tech_0(check)
	start("pick_green", "pick_green")
	local cub  = summon("tiger_cub", "mine.army")          -- tech 0
	local bear = summon("barkcoat_bear", "mine.army")      -- tech 2
	local snake = post("tiny_basilisk", "enemy", 1)

	check("a tech 0 unit cannot strike it", not offers(cub, "strike_lead"))
	check("but a tech 2 one can", offers(bear, "strike_lead"))
	check("and the tech 0 unit may go round it", offers(cub, "strike_free"))
	check("while the tech 2 one is held", not offers(bear, "strike_free"))

	-- A spell is a different aim and the ward is not on one: the basilisk's rule
	-- lives in what an attack may point at, so casting is untouched.
	zones.purge_card(snake.id)
	local free = summon("tiny_basilisk", "enemy.army")
	seat("south").stats.gold = 20
	use(in_zone("command", "calamandra"), "summon")
	flow.settle()
	local dart = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local targeting = require("targeting")
	local hit = false
	for _, id in ipairs(targeting.candidates(dart.id, require("cards").def(entity.get(dart.id)).play.target)) do
		if id == free.id then hit = true end
	end
	check("a spell may still be aimed at it", hit)
end

-- **Unstoppable by tech 0 units.** Two more terms on the two skip computes, and
-- nothing in the engine learned a word: who may be walked past has always been a
-- count of reasons, and "their patroller is tech 0 and I ignore those" is one more.
function M.test_codex_unstoppable_by_tech_0(check)
	start("pick_red", "pick_green")
	local ground = summon("mad_man", "army")
	local tiger  = summon("predator_tiger", "army")
	local lead   = post("nautical_dog", "enemy", 1)   -- tech 0

	check("a tech 0 leader stops an ordinary attacker", not offers(ground, "strike_free"))
	check("but not one that ignores them", offers(tiger, "strike_free"))

	zones.purge_card(lead.id)
	post("centaur", "enemy", 1)                       -- tech 1
	check("a tech 1 leader stops it like anything else", not offers(tiger, "strike_free"))
	check("and is still the thing it may hit", offers(tiger, "strike_lead"))
end

-- The other four posts are the same rule said again, and they are a *count*
-- rather than a yes/no: two tech 0 patrollers are two walked past.
function M.test_codex_unstoppable_counts_the_other_posts(check)
	start("pick_red", "pick_green")
	local ground = summon("mad_man", "army")
	local tiger  = summon("predator_tiger", "army")
	post("nautical_dog", "enemy", 3)
	post("mad_man", "enemy", 4)

	check("two tech 0 patrollers stop an ordinary attacker", not offers(ground, "strike_free"))
	check("and neither stops the tiger", offers(tiger, "strike_free"))

	post("centaur", "enemy", 5)
	check("one tech 1 among them is enough to stop it", not offers(tiger, "strike_free"))
end

-- The fight happens somewhere. Both sides step into the duel zone, the steps
-- run, and "origin" puts each of them back where it stood — which for a
-- patroller is its own slot and not the army.
function M.test_codex_combat_happens_in_a_zone(check)
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
	local snake = summon("tiny_basilisk", "army")        -- 1/2, deathtouch
	local ogre  = summon("bloodrage_ogre", "enemy.army") -- 3/2

	use(snake, "strike_free", { ogre.id })
	flow.settle()
	check("one point of deathtouch killed it", count_in("enemy.discard") == 1,
		tostring(count_in("enemy.discard")))
end

-- Long-range: the defender never gets to swing back.
function M.test_codex_long_range(check)
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
	local tank = summon("steam_tank", "army")   -- 3/6
	local base = in_zone("enemy.base")

	use(tank, "strike_free", { base.id })
	flow.settle()
	check("it hit the base for seven", base.stats.integrity == 13, tostring(base.stats.integrity))
end

-- A ground defender with no anti-air cannot touch a flier, even the one that is
-- hitting it. The same condition reads on both sides of the fight.
function M.test_codex_a_flier_takes_nothing_back(check)
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
	summon("tiger_cub", "enemy.army")
	local fresh = summon("mad_man", "army")
	fresh.stats.ready_since = 0
	check("a unit that just arrived cannot attack", not offers(fresh, "strike_free"))
	fresh.stats.ready_since = 1
	check("next turn it can", offers(fresh, "strike_free"))
end

-- Ephemeral is a death, not a trash. Crashbarrow and Shoddy Glider are codex
-- cards and Sanatorium lends units out of your hand, so all three have to land
-- in the discard and cycle back; only a token leaves the game, and it leaves by
-- the death sweep that already sweeps tokens rather than by a word of its own.
function M.test_codex_ephemeral_dies(check)
	start("pick_red", "pick_green")
	summon("crashbarrow", "army")
	summon("shark", "army")
	summon("steam_tank", "army").stats.fleeting = 1
	flow.activate(in_zone("controls", "end_turn").id, {})
	flow.settle()
	check("the ephemeral unit went to the discard", in_zone("discard", "crashbarrow") ~= nil)
	check("and so did the one lent out of a hand", in_zone("discard", "steam_tank") ~= nil)
	check("neither is still in play", count_in("army") == 0, tostring(count_in("army")))
	check("the token left the game", in_zone("discard", "shark") == nil)
end

-- Discard the hand, draw that many plus two, stop at five. The cap is
-- max(0, a - b) used once, which is the only arithmetic the grammar has.
function M.test_codex_draw(check)
	for _, case in ipairs({ { 0, 2 }, { 1, 3 }, { 2, 4 }, { 3, 5 }, { 5, 5 } }) do
		start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
	flow.activate(in_zone("controls", "end_turn").id, {})
	flow.settle()
	check("the tech phase came round", phase.current().key == "tech", phase.current().key)
	check("with two picks owed", seat("south").stats.teched == 2, tostring(seat("south").stats.teched))

	local before = stock_in("codex")
	flow.activate(in_zone("controls", "tech_button").id, {})
	flow.settle()
	local picked = entity.get(zones.find("options").cards[1])
	flow.play_card(picked.id, {})
	flow.settle()
	check("a codex card left the codex", stock_in("codex") == before - 1, tostring(stock_in("codex")))
	check("and one pick is left", seat("south").stats.teched == 1, tostring(seat("south").stats.teched))
end

-- What the box buys. A shelf is spent by `take` and refilled by `purge`, so a
-- trash — which is what the rulebook means and never the discard pile — needs no
-- rule naming the codex at the site that does it. That is the whole of Rambasa
-- Twin's "return this to your codex", and of a trashed worker going nowhere.
function M.test_codex_a_trash_goes_home_to_the_box(check)
	start("pick_red", "pick_green")
	local function shelf(key)
		local c = in_zone("codex", key)
		return c and (c.stats or {}).stock or 0
	end
	check("Chameleon Lizzo starts two deep", shelf("chameleon_lizzo") == 2, tostring(shelf("chameleon_lizzo")))

	actions.run({ "take:mine.codex.chameleon_lizzo:mine.army:1" }, {})
	check("taking one spends the shelf", shelf("chameleon_lizzo") == 1, tostring(shelf("chameleon_lizzo")))
	check("and a real card stands on the table", in_zone("army", "chameleon_lizzo") ~= nil)

	actions.run({ "purge:mine.army.chameleon_lizzo" }, {})
	check("trashing it puts it back on the shelf", shelf("chameleon_lizzo") == 2, tostring(shelf("chameleon_lizzo")))
	check("and it is off the table", in_zone("army", "chameleon_lizzo") == nil)

	-- A death is not a trash: it goes to the grave and stays out of the box.
	actions.run({ "take:mine.codex.chameleon_lizzo:mine.army:1", "destroy:mine.army.chameleon_lizzo" }, {})
	check("a death leaves the shelf spent", shelf("chameleon_lizzo") == 1, tostring(shelf("chameleon_lizzo")))
	check("and the card in the discard", in_zone("discard", "chameleon_lizzo") ~= nil)
end

-- A building is a deck card, so rubble is a death and not a trash: Codex spells
-- Dies as "put into your discard pile from play", and only workers and the
-- tokens are trashed. A tech building is not a deck card and stays a trash.
function M.test_codex_a_wrecked_building_is_discarded(check)
	start("pick_red", "pick_green")
	local mine = summon("rickety_mine", "structures")
	mine.stats.integrity = 0
	actions.run({ "activate_zone:rules_death" }, {})
	flow.settle()
	check("the wreck went to its owner's discard", in_zone("discard", "rickety_mine") ~= nil)
	check("and is off the table", count_in("structures") == 0, tostring(count_in("structures")))

	seat("south").stats.workers = 6
	use(in_zone("controls", "build_t1"), "raise")
	flow.settle()
	local tech = in_zone("site")
	zones.move_card(tech.id, zones.find_id("tech", "mine"))
	tech.stats.integrity = 0
	actions.run({ "activate_zone:rules_death" }, {})
	flow.settle()
	check("a tech building leaves the game instead", in_zone("discard", "tech_1") == nil)
	check("and costs the base two", in_zone("base").stats.integrity == 18,
		tostring(in_zone("base").stats.integrity))
end

-- An add-on is a mini-card and never a deck card, so scrapping one is a trash
-- and not a death — the same answer the rubble rule already gives it. Sent to a
-- grave it would land in the discard and be drawn as if it were a spell.
function M.test_codex_a_scrapped_addon_leaves_the_game(check)
	start("pick_red", "pick_green")
	require("cards").create("tower", zones.find_id("addon", "mine"))
	flow.activate(in_zone("controls", "sacrifice_addon").id, {})
	flow.settle()
	check("the add-on is off the base", count_in("addon") == 0, tostring(count_in("addon")))
	check("and did not land in the deck's discard", in_zone("discard", "tower") == nil)
	check("scrapping costs the base two", in_zone("base").stats.integrity == 18,
		tostring(in_zone("base").stats.integrity))
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
	-- Two counts, because half the box is scaffolding: cards printed for their
	-- numbers and their text so that a survey has something to survey, with none
	-- of what they *say* running. They are not inert — the tag-level play and the
	-- fighter abilities reach them like anything else, so a scaffolded unit is a
	-- vanilla one of the right size. The tag and the word in the tooltip go
	-- together, so a card cannot quietly become finished.
	local live, held = 0, 0
	for _, def in pairs(G.card_defs) do
		if def.tags_set and def.tags_set.deck_card then
			if def.tags_set.scaffold then held = held + 1 else live = live + 1 end
		end
		if def.tags_set and def.tags_set.scaffold then
			check("the scaffold '" .. (def.text or "?") .. "' says that it is one",
				type(def.tooltip) == "string" and def.tooltip:find("SCAFFOLD", 1, true) ~= nil)
		end
	end
	check("two hundred and seventy-six printed cards are played", live == 276, tostring(live))
	check("and thirty-four more are only printed", held == 34, tostring(held))
end

-- The hero waits in a zone that is not in play, which is what lets "do I have a
-- hero" be one condition and the summon be an ability on the hero itself.
function M.test_codex_hero(check)
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
	local posts = zones.find("patrol", "mine")
	local unit  = summon("tiger_cub", "army")
	check("it starts at its printed attack", unit.stats.atk == 2, tostring(unit.stats.atk))

	use(unit, "go_patrol", { posts.slots[2] })
	check("the elite square lends it a point", stats.current(unit, "atk") == 3, tostring(stats.current(unit, "atk")))
	check("without writing on the card", unit.stats.atk == 2, tostring(unit.stats.atk))
	check("and it knows which post it took", unit.stats.slot == 2, tostring(unit.stats.slot))
	zones.move_card(unit.id, zones.find_id("army", "mine"))
	check("leaving takes both back", stats.current(unit, "atk") == 2 and unit.stats.slot == 0,
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_green", "pick_green")
	local hero = in_zone("command", "calamandra")
	use(hero, "summon")
	flow.settle()
	hero.stats.level = 5
	seat("south").stats.gold = 9

	check("the search is offered at max level", offers(hero, "call_tiger"))
	use(hero, "call_tiger")
	flow.settle()
	check("the whole codex comes up", count_in("options") == 36, tostring(count_in("options")))

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
	check("and the rest went home", stock_in("codex") == 71, tostring(stock_in("codex")))
end

function M.test_codex_options(check)
	start("pick_green", "pick_green")
	local hero = in_zone("command", "calamandra")
	use(hero, "summon")
	flow.settle()
	seat("south").stats.gold = 9
	local spell = require("cards").create("murkwood_allies", zones.find_id("hand", "mine"))
	flow.play_card(spell.id, {})
	flow.settle()
	check("three shapes are offered", count_in("options") == 3, tostring(count_in("options")))
	check("and the boosted one among them", in_zone("options", "ma_both") ~= nil)
	flow.play_card(in_zone("options", "ma_frogs").id, {})
	flow.settle()
	check("four frogs joined the hero", count_in("army") == 5, tostring(count_in("army")))
	check("the plain half cost nothing extra", seat("south").stats.gold == 4,
		tostring(seat("south").stats.gold))
	check("and the spell is spent", in_zone("discard", "murkwood_allies") ~= nil)
end

-- **An answer may have a price, and it says so itself.** A card the offer dealt
-- is what runs when it is taken, so the cost written on it is the cost of that
-- answer — no word beside "cost", and the dearer half is simply not on the table
-- until it can be paid for.
function M.test_codex_an_answer_may_have_a_price(check)
	start("pick_green", "pick_green")
	use(in_zone("command", "calamandra"), "summon")
	flow.settle()
	seat("south").stats.gold = 5
	local spell = require("cards").create("murkwood_allies", zones.find_id("hand", "mine"))
	flow.play_card(spell.id, {})
	flow.settle()
	check("the free halves are takeable", flow.can_play(in_zone("options", "ma_beast").id))
	check("the dear one is not, with nothing left over",
		not flow.can_play(in_zone("options", "ma_both").id))

	seat("south").stats.gold = 9
	check("and is once it can be paid for", flow.can_play(in_zone("options", "ma_both").id))
	flow.play_card(in_zone("options", "ma_both").id, {})
	flow.settle()
	check("four more gold went", seat("south").stats.gold == 5, tostring(seat("south").stats.gold))
	check("and both halves arrived", count_in("army") == 6, tostring(count_in("army")))
end

function M.test_codex_coin(check)
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
	start("pick_red", "pick_green")
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
-- game knows anything about being watched. The watcher is theirs, so the point
-- it deals lands on the base its own side is not standing in front of.
function M.test_codex_a_witness_answers_a_death(check)
	start("pick_red", "pick_green")
	local watcher = summon("captured_bugblatter", "enemy.army")  -- 4/2, watching only
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
-- discard says nothing at all about being returned to a hand. The bomber is
-- theirs, because its own owner's turn is the half it stays quiet for.
function M.test_codex_leaves_only_where_it_says(check)
	start("pick_red", "pick_green")
	local bomber = summon("crash_bomber", "enemy.army")
	local mybase = entity.get(entity.get(zones.find_id("base", "mine")).cards[1])

	zones.move_card(bomber.id, zones.find_id("hand", "enemy"))
	check("bounced to hand, the death rule stayed quiet",
		mybase.stats.integrity == 20, tostring(mybase.stats.integrity))

	zones.move_card(bomber.id, zones.find_id("army", "enemy"))
	zones.move_card(bomber.id, zones.find_id("patrol_lead", "enemy"))
	check("and walking between two board zones is not leaving anything",
		mybase.stats.integrity == 20, tostring(mybase.stats.integrity))

	zones.move_card(bomber.id, zones.find_id("discard", "enemy"))
	check("into the discard, it goes off", mybase.stats.integrity == 19,
		tostring(mybase.stats.integrity))
end

-- What a stat reads, buffs and all. Half of what follows is a number nothing
-- ever wrote down, so asking the card its own stat would answer the wrong thing.
local function read(c, key) return stats.current(entity.get(c.id), key) end

-- Readiness is its own word rather than a tag, so a test asks it the way a card
-- would: through a condition.
local function spent(id)
	return require("predicate").holds("exhausted@self", { card_id = id })
end

local function base_of(owner)
	return entity.get(entity.get(zones.find_id("base", owner)).cards[1])
end

-- Summon a hero the ordinary way, since a hero in play is what every spell in
-- Codex is gated on.
local function take_the_field(hero_key)
	seat("south").stats.gold = 20
	use(in_zone("command", hero_key), "summon")
	flow.settle()
end

-- "This turn" is a stat that records what was lent and an endturn column that
-- hands it back. The alternative — undoing the gain wherever a unit can leave
-- by — is the bookkeeping `buffs` exists to avoid, and it cannot be used here
-- because a buff's amount is a plain number and these are four different ones.
function M.test_codex_a_bonus_that_lasts_the_turn(check)
	start("pick_red", "pick_green")
	take_the_field("zane")
	local dog = summon("mad_man", "mine.army")
	local charge = require("cards").create("charge", zones.find_id("hand", "mine"))

	flow.play_card(charge.id, { dog.id })
	flow.settle()
	check("the attack went up", read(dog, "atk") == 2, tostring(read(dog, "atk")))
	check("and the file remembers whose it was", dog.stats.lent == 1, tostring(dog.stats.lent))

	actions.run({ "activate_zone:mine.army:by_column:endturn" }, {})
	check("the end of the turn hands it back", read(dog, "atk") == 1, tostring(read(dog, "atk")))
	check("and asks for it only once", dog.stats.lent == 0, tostring(dog.stats.lent))
end

-- Ironbark Treant is what a computed tag with `buffs` is for, and where the line
-- between a buff and a stamped stat runs. The lost attack is a buff: nothing
-- spends it, so it can arrive and leave with the post. The armour is not, because
-- absorbing a blow *writes* to the card's own number — under a buff that write
-- goes negative, and the debt would follow the treant off the post.
function M.test_codex_a_post_that_changes_the_card(check)
	start("pick_red", "pick_green")
	local tree = summon("ironbark_treant", "mine.army")

	check("in the army it reads what is printed",
		read(tree, "atk") == 3 and tree.stats.guard == 0, tostring(read(tree, "atk")))
	tree.stats.slot = 3
	check("on a post it gives up two attack", read(tree, "atk") == 1, tostring(read(tree, "atk")))

	tree.stats.slot = 0
	use(tree, "go_patrol", { zones.find("patrol", "mine").slots[3] })
	check("and taking the post stamps two armour", tree.stats.guard == 2, tostring(tree.stats.guard))
end

-- **A lend that outlives the turn it was made in.** Every other bonus the endturn
-- column hands back is cleared outright; armor piercing is counted down from two,
-- so it survives one turn-end and goes at the next. Both seats end their turn
-- through the same column, which is what puts the second one at the caster's own
-- upkeep — "until your next upkeep" without a word for a duration.
function M.test_codex_ferocity_lasts_until_the_next_upkeep(check)
	start("pick_green", "pick_green")
	take_the_field("calamandra")
	local cub = summon("tiger_cub", "mine.army")
	local roar = require("cards").create("ferocity", zones.find_id("hand", "mine"))

	flow.play_card(roar.id, { })
	flow.settle()
	check("the cub is piercing", read(cub, "pierce") == 2, tostring(read(cub, "pierce")))

	actions.run({ "activate_zone:mine.army:by_column:endturn" }, {})
	check("its own turn ending does not take it", read(cub, "pierce") == 1,
		tostring(read(cub, "pierce")))
	actions.run({ "activate_zone:mine.army:by_column:endturn" }, {})
	check("the opponent's turn ending does", read(cub, "pierce") == 0,
		tostring(read(cub, "pierce")))
end

-- The elephant's first attack each turn is free of its readiness, and its second
-- is not. "romp" is the one look, spent in the duel's own kills column.
function M.test_codex_rampaging_elephant(check)
	start("pick_green", "pick_green")
	take_the_field("calamandra")
	local bull = summon("rampaging_elephant", "mine.army")
	actions.run({ "activate_zone:mine.army:by_column:upkeep" }, {})
	post("mad_man", "enemy", 1)

	use(bull, "strike_lead", { in_zone("enemy.patrol").id })
	flow.settle()
	check("the first attack leaves it ready", not entity.get(bull.id).exhausted)
	check("and the look is spent", read(bull, "romp") == 0, tostring(read(bull, "romp")))

	post("mad_man", "enemy", 1)
	use(bull, "strike_lead", { in_zone("enemy.patrol").id })
	flow.settle()
	check("the second costs it", entity.get(bull.id).exhausted == true)
end

-- **Disable**, which is two words and a stat. `exhaust:` spends somebody else's
-- readiness; `disabled` keeps it spent past the next ready step, because the
-- upkeep readies what is *rousable* rather than every kind of card it can name.
function M.test_codex_disable(check)
	start("pick_blue", "pick_green")
	take_the_field("bigby")
	local prey = post("tiger_cub", "enemy", 1)
	local cuffs = require("cards").create("arrest", zones.find_id("hand", "mine"))
	seat("south").stats.gold = 20

	flow.play_card(cuffs.id, { prey.id })
	flow.settle()
	local p = entity.get(prey.id)
	check("the patroller is spent", spent(prey.id))
	check("and left its post", p.stats.slot == 0, tostring(p.stats.slot))
	check("and is not roused by an ordinary readying",
		not tags.entity_has(entity.get(prey.id), "rousable"))

	actions.run({ "ready:enemy.rousable" }, {})
	check("so their upkeep leaves it spent", spent(prey.id))
	actions.run({ "stat_damage:disabled@each.enemy.fighter:1", "ready:enemy.rousable" }, {})
	check("but the one after that gives it back", not spent(prey.id))
end

-- One line where four stood: the scope names what is spent rather than every kind
-- of card that can be, so printing a fifth kind needs no fifth line.
function M.test_codex_the_upkeep_readies_what_is_spent(check)
	start("pick_blue", "pick_green")
	local unit = summon("tiger_cub", "mine.army")
	local hall = require("cards").create("flagstone_garrison", zones.find_id("structures", "mine"))
	actions.run({ "exhaust:mine.exhaustable" }, {})
	check("a unit and a building are both spent",
		spent(unit.id) and spent(hall.id))
	actions.run({ "ready:mine.rousable" }, {})
	check("and one line gives both back",
		not spent(unit.id) and not spent(hall.id))
end

-- **A card in an offer is chosen, not played.** The engine seat used to build
-- targets for everything it could play, and a card lying in a codex offer has a
-- target spec that will never be filled — flow skips the check for a choice and
-- hands it the asker instead. So a seat sat in front of a question it could have
-- answered, and the game stopped with a legal move on the table.
function M.test_codex_the_engine_seat_can_answer_an_unaimable_offer(check)
	local opponent = require("opponent")
	start("pick_purple", "pick_green")
	-- The codex holds Assimilate, which aims at a building or an ongoing spell.
	-- Nothing of theirs is on the table, so it can point at nothing at all.
	actions.run({ "show:mine.codex" }, {})
	flow.settle()
	check("the codex is on the table", count_in("options") > 0, tostring(count_in("options")))

	local aimless = in_zone("options", "assimilate")
	check("and it is holding a card that can aim at nothing", aimless ~= nil)
	if aimless then
		check("which flow will take as a choice rather than a play",
			flow.is_choosing(aimless.id))
		check("so it needs no targets to be answered", flow.play_card(aimless.id, {}))
	end

	opponent.seats = {}
	opponent.take(zones.active_seat())
	check("and the seat is never left with none", #opponent.legal() > 0,
		tostring(#opponent.legal()))
end

-- A rune lent for the turn, recorded the way every other lending already is:
-- what was given is remembered on its own stat and handed back at the turn's end.
function M.test_codex_a_rune_may_be_lent_for_a_turn(check)
	start("pick_black", "pick_green")
	take_the_field("orpal")
	local prey = summon("gigadon", "enemy.army")
	local spell = require("cards").create("deteriorate", zones.find_id("hand", "mine"))
	seat("south").stats.gold = 20
	local was = read(prey, "atk")

	flow.play_card(spell.id, { prey.id })
	flow.settle()
	check("it is a point smaller", read(prey, "atk") == was - 1, tostring(read(prey, "atk")))
	check("and the file remembers the rune was lent", prey.stats.sank == 1,
		tostring(prey.stats.sank))

	actions.run({ "activate_zone:enemy.army:by_column:endturn" }, {})
	check("the end of the turn takes it back", read(prey, "atk") == was,
		tostring(read(prey, "atk")))
	check("and the rune with it", (entity.get(prey.id).stats.minus or 0) == 0,
		tostring(entity.get(prey.id).stats.minus))
end

-- **Obliterate, which is the sorting quantifier and a number on a tag.** Tech
-- level is a tag on 213 cards and was never a number; it is one now because the
-- tag says what it is worth, the way a counter does — so "the four lowest tech
-- units" is destroy's own count over a pool put in order.
function M.test_codex_tech_level_is_a_number_the_tag_carries(check)
	start("pick_red", "pick_green")
	local cub  = summon("tiger_cub", "mine.army")        -- tech 0
	local horse = summon("centaur", "mine.army")         -- tech 1
	local tiger = summon("stalking_tiger", "mine.army")  -- tech 2
	check("a tech 0 card reads nought", read(cub, "tech_level") == 0, tostring(read(cub, "tech_level")))
	check("a tech 1 card reads one", read(horse, "tech_level") == 1, tostring(read(horse, "tech_level")))
	check("a tech 2 card reads two", read(tiger, "tech_level") == 2, tostring(read(tiger, "tech_level")))
	check("and nothing was written on any of them", cub.stats.tech_level == 0
		and horse.stats.tech_level == 0, tostring(horse.stats.tech_level))
end

function M.test_codex_obliterate_takes_the_lowest_tech(check)
	start("pick_red", "pick_green")
	local gun = summon("pirate_gunship", "mine.army")    -- obliterate 2
	summon("stalking_tiger", "enemy.army")               -- tech 2, should survive
	summon("tiger_cub", "enemy.army")                    -- tech 0, should go
	summon("centaur", "enemy.army")                      -- tech 1, should go
	check("three of theirs are standing", count_in("enemy.army") == 3,
		tostring(count_in("enemy.army")))

	actions.run({ "purge:lowest:tech_level.enemy.army:2", "activate_zone:rules_death" },
		{ card_id = gun.id })
	flow.settle()
	check("two went", count_in("enemy.army") == 1, tostring(count_in("enemy.army")))
	check("and it is the tech 2 one that is left",
		in_zone("enemy.army", "stalking_tiger") ~= nil)
end

-- **Purple is two clocks, and both are the counter plus a place.** Forecast is a
-- card played into a zone that is not in play, losing a rune each upkeep and
-- arriving when the last goes. Fading is the same clock on the table, and what
-- happens at nought is a death rather than an arrival. Neither wanted a word.
function M.test_codex_forecast_arrives_when_its_clock_runs_out(check)
	start("pick_purple", "pick_green")
	seat("south").stats.gold = 20
	local card = require("cards").create("plasmodium", zones.find_id("hand", "mine"))
	flow.play_card(card.id, {})
	flow.settle()
	local function where()
		local e = entity.get(card.id)
		local z = e and e.zone_id and entity.get(e.zone_id)
		return z and z.key or "nowhere"
	end
	check("it went to the future rather than the table", where() == "soon", where())
	check("with three runes on it", entity.get(card.id).stats.time == 3,
		tostring(entity.get(card.id).stats.time))

	for _ = 1, 2 do actions.run({ "activate_zone:rules_upkeep" }, {}) end
	check("two upkeeps later it is still waiting", where() == "soon", where())
	check("and the clock has run down", entity.get(card.id).stats.time == 1,
		tostring(entity.get(card.id).stats.time))

	actions.run({ "activate_zone:rules_upkeep" }, {})
	check("the third brings it in", where() == "army", where())
end

function M.test_codex_fading_leaves_when_its_clock_runs_out(check)
	start("pick_purple", "pick_green")
	seat("south").stats.gold = 20
	local card = require("cards").create("fading_argonaut", zones.find_id("hand", "mine"))
	flow.play_card(card.id, {})
	flow.settle()
	check("it arrives on the table", in_zone("army", "fading_argonaut") ~= nil)
	check("carrying three runes", entity.get(card.id).stats.time == 3,
		tostring(entity.get(card.id).stats.time))

	for _ = 1, 2 do actions.run({ "activate_zone:rules_upkeep" }, {}) end
	check("two upkeeps and it is still standing", in_zone("army", "fading_argonaut") ~= nil)
	actions.run({ "activate_zone:rules_upkeep" }, {})
	check("the third takes it", in_zone("army", "fading_argonaut") == nil)
end

-- White leans on words the file gained this week rather than on new ones of its
-- own: a rune put on by an exhausting ability, a disable written into a spell,
-- and a ward lent by a unit standing on the table.
function M.test_codex_white_sparring_partner(check)
	start("pick_white", "pick_green")
	local coach = summon("sparring_partner", "mine.army")
	local cub   = summon("tiger_cub", "mine.army")
	for _, u in ipairs(flow.usable_abilities(coach.id)) do
		if u.rule.key == "train" then flow.activate(coach.id, { cub.id }, u.index) end
	end
	flow.settle()
	check("the cub took a rune", read(cub, "atk") == 3, tostring(read(cub, "atk")))
	check("and the coach spent itself for it", spent(coach.id))
end

-- Reversal is three damage and a disable in one spell, which is the pair of words
-- exhaust: and "disabled" working together where neither alone would do.
function M.test_codex_white_reversal(check)
	start("pick_white", "pick_green")
	take_the_field("grave")
	local prey = post("ironbark_treant", "enemy", 3)
	local spell = require("cards").create("reversal", zones.find_id("hand", "mine"))
	seat("south").stats.gold = 20
	flow.play_card(spell.id, { prey.id })
	flow.settle()
	local p = entity.get(prey.id)
	check("it is spent", p and spent(prey.id))
	check("and stays spent through a readying", p and (p.stats.disabled or 0) >= 1,
		p and tostring(p.stats.disabled) or "gone")
	check("and left its post", p and p.stats.slot == 0, p and tostring(p.stats.slot) or "gone")
end

-- A ward that is not printed on the card wearing it: the Monk stands, and every
-- unit on its side refuses a spell for as long as it does.
function M.test_codex_white_mindparry(check)
	start("pick_white", "pick_green")
	local cub = summon("tiger_cub", "mine.army")
	check("ordinarily a spell may aim at it", not tags.entity_has(entity.get(cub.id), "parried"))
	summon("mindparry_monk", "mine.army")
	check("with the Monk out it may not", tags.entity_has(entity.get(cub.id), "parried"))
end

-- Black, whose whole idea is a counter that subtracts. "minus" declares what one
-- of it is worth and the rest is arithmetic: a rune put on is a unit read lower,
-- and enough of them is a unit that is dead without anything having killed it.
function M.test_codex_black_runes_subtract(check)
	start("pick_black", "pick_green")
	local prey = summon("tiger_cub", "enemy.army")          -- 2/2
	actions.run({ "stat_gain:minus@self:1" }, { card_id = prey.id })
	check("one rune is -1/-1", read(prey, "atk") == 1 and read(prey, "hp") == 1,
		read(prey, "atk") .. "/" .. read(prey, "hp"))
	actions.run({ "stat_gain:minus@self:1" }, { card_id = prey.id })
	check("two is dead without a blow struck", tags.entity_has(entity.get(prey.id), "dead"))
end

-- The hero writes it, and so does anything that says its damage lands as runes.
function M.test_codex_orpal_damages_in_runes(check)
	start("pick_black", "pick_green")
	take_the_field("orpal")
	local hero = in_zone("army", "orpal")
	hero.stats.ready_since = 1                         -- past the turn it arrived
	-- The scavenger post lends no armour, so the blow lands and there is a
	-- survivor to read: Orpal is 1 ATK and the cub is a 2/2.
	local prey = post("tiger_cub", "enemy", 3)
	use(hero, "strike_patrol", { prey.id })
	flow.settle()
	local p = entity.get(prey.id)
	check("the fight left a rune behind it", p and (p.stats.minus or 0) >= 1,
		p and tostring(p.stats.minus) or "gone")
end

-- An anthem that subtracts, written as every other anthem is: a computed tag that
-- asks about the rest of the board, and "others" is what keeps it off itself.
function M.test_codex_abomination_shrinks_everyone_else(check)
	start("pick_black", "pick_green")
	local cub  = summon("tiger_cub", "mine.army")
	local abom = summon("abomination", "mine.army")
	check("everything else is a point smaller", read(cub, "atk") == 1, tostring(read(cub, "atk")))
	check("but not the Abomination itself", read(abom, "atk") == 6, tostring(read(abom, "atk")))
end

-- Blue, and the four of its rules that are not a keyword something already had.
-- A death replacement said twice (Brave Knight's hand, the Juggernaut's second
-- life), a keyword a card only sometimes has, and a walk-past reason keyed on a
-- number rather than a tag.
function M.test_codex_blue_deals(check)
	start("pick_blue", "pick_blue")
	check("the blue starter is ten cards", count_in("hand") + count_in("deck") == 10,
		tostring(count_in("hand") + count_in("deck")))
	check("and the codex is seventy-two", stock_in("codex") == 72, tostring(stock_in("codex")))
	check("Bigby is in command", in_zone("command", "bigby") ~= nil)
end

function M.test_codex_blue_arrivals(check)
	start("pick_blue", "pick_blue")
	take_the_field("bigby")
	local scribe = require("cards").create("scribe", zones.find_id("hand", "mine"))
	local held = count_in("hand")
	require("cards").create("tech_1", zones.find_id("tech", "mine"))
	seat("south").stats.gold = 20
	flow.play_card(scribe.id, {})
	flow.settle()
	check("the scribe drew as it arrived", count_in("hand") == held, tostring(count_in("hand")))

	local gold = seat("south").stats.gold
	seat("north").stats.gold = 5
	local theirs = seat("north").stats.gold
	local tax = require("cards").create("tax_collector", zones.find_id("hand", "mine"))
	flow.play_card(tax.id, {})
	flow.settle()
	check("the tax collector took a gold off them",
		seat("north").stats.gold == theirs - 1, tostring(seat("north").stats.gold))
	check("and put it in its own purse", seat("south").stats.gold == gold - 2 + 1,
		tostring(seat("south").stats.gold))
end

-- Two deaths that are not deaths, both written as a rules_death column that runs
-- before the sweep — which is the only place a card can be caught on its way out.
function M.test_codex_blue_second_chances(check)
	start("pick_blue", "pick_green")
	local knight = summon("brave_knight", "mine.army")
	knight.stats.hp = 0
	actions.run({ "activate_zone:rules_death" }, {})
	check("the knight went back to hand instead of dying",
		in_zone("hand", "brave_knight") ~= nil)
	check("and is whole again", read(entity.get(knight.id), "hp") == 3,
		tostring(read(entity.get(knight.id), "hp")))

	local bull = summon("justice_juggernaut", "mine.army")
	bull.stats.hp = 0
	actions.run({ "activate_zone:rules_death" }, {})
	check("the juggernaut healed rather than died", read(bull, "hp") == 6, tostring(read(bull, "hp")))
	check("and is crumbling now", bull.stats.lives >= 2, tostring(bull.stats.lives))
	bull.stats.hp = 0
	actions.run({ "activate_zone:rules_death" }, {})
	check("so the second death is a real one", entity.get(bull.id) == nil
		or entity.get(bull.id).zone_id ~= zones.find_id("army", "mine"))
end

-- A keyword a card has only while a number holds, and one that reads a number on
-- the *other* side. Both are computed tags, which is what makes them free.
function M.test_codex_blue_conditional_keywords(check)
	start("pick_blue", "pick_green")
	local shot = summon("bluecoat_musketeer", "mine.army")
	check("at one attack it is long-range", tags.entity_has(entity.get(shot.id), "ranged"))
	shot.stats.atk = 2
	check("buffed past one it is not", not tags.entity_has(entity.get(shot.id), "ranged"))

	local bird = summon("patriot_gryphon", "mine.army")
	post("tiger_cub", "enemy", 1)                     -- 2 ATK, and so too weak to hold it
	check("a weak leader does not stop the gryphon", offers(bird, "strike_free"))
	local ground = summon("mad_man", "mine.army")
	check("but it stops anything else", not offers(ground, "strike_free"))
end

-- Hotter Fire is the reason "harm" is a verb. Combat damage stays plain
-- `stat_damage` and is therefore unreachable; a spell says `harm`, and an
-- `adjusts` on the upgrade answers it.
function M.test_codex_a_named_damage_can_be_answered(check)
	start("pick_red", "pick_green")
	take_the_field("jaina")
	local beef = summon("gigadon", "enemy.army")
	local dart = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local before = read(beef, "hp")

	flow.play_card(dart.id, { beef.id })
	flow.settle()
	check("a dart is three", before - read(beef, "hp") == 3,
		before .. "->" .. read(beef, "hp"))

	start("pick_red", "pick_green")
	take_the_field("jaina")
	require("cards").create("hotter_fire", zones.find_id("ongoing", "mine"))
	local beef2 = summon("gigadon", "enemy.army")
	local dart2 = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local was = read(beef2, "hp")

	flow.play_card(dart2.id, { beef2.id })
	flow.settle()
	check("and four with Hotter Fire out", was - read(beef2, "hp") == 4,
		was .. "->" .. read(beef2, "hp"))
end

-- An anthem is a computed tag whose condition names the active seat, because
-- nothing else can say "the side this card is on". That reads right for every
-- Codex anthem, since all of them are about attacking.
function M.test_codex_an_anthem_reads_from_the_seat_that_is_up(check)
	start("pick_green", "pick_green")
	local cub = summon("tiger_cub", "mine.army")
	check("no stealth before the spell", read(cub, "sneak") == 0, tostring(read(cub, "sneak")))
	require("cards").create("behind_the_ferns", zones.find_id("ongoing", "mine"))
	check("and stealth once it is down", read(cub, "sneak") == 1, tostring(read(cub, "sneak")))

	start("pick_red", "pick_green")
	take_the_field("drakk")
	local ogre = summon("bloodrage_ogre", "mine.army")
	check("no frenzy from a first-level Drakk", read(ogre, "rage") == 0, tostring(read(ogre, "rage")))
	in_zone("mine.army", "drakk").stats.level = 4
	check("frenzy 1 from his second band", read(ogre, "rage") == 1, tostring(read(ogre, "rage")))
end

-- **A counter says what one of it is worth.** The rune used to be two facts —
-- a number recording it and a shift paying for it — written four lines apart, and
-- nothing took the shift back off. It is one fact now, and the bonus is a reading
-- of it, so moving a rune is a thing a card can say.
function M.test_codex_a_rune_is_worth_its_points(check)
	start("pick_green", "pick_green")
	local cub = summon("tiger_cub", "mine.army")           -- 2/2
	actions.run({ "stat_gain:plus@self:2" }, { card_id = cub.id })
	check("two runes are +2/+2", read(cub, "atk") == 4 and read(cub, "hp") == 4,
		read(cub, "atk") .. "/" .. read(cub, "hp"))
	check("and the ceiling came with them", stats.ceiling(entity.get(cub.id), "hp") == 4,
		tostring(stats.ceiling(entity.get(cub.id), "hp")))

	actions.run({ "stat_damage:plus@self:1" }, { card_id = cub.id })
	check("taking one off takes its point with it",
		read(cub, "atk") == 3 and read(cub, "hp") == 3, read(cub, "atk") .. "/" .. read(cub, "hp"))
	check("and nothing was written on the card", cub.stats.atk == 2, tostring(cub.stats.atk))
end

-- The wound is what is left. A 2/2 under two runes that takes three is standing at
-- 1 of 4; move a rune off and the ceiling drops under the damage, which is the
-- rulebook's answer and was unreachable while the shift was a stored number.
function M.test_codex_a_rune_removed_can_kill(check)
	start("pick_green", "pick_green")
	local cub = summon("tiger_cub", "mine.army")
	actions.run({ "stat_gain:plus@self:2", "stat_damage:hp@self:3" }, { card_id = cub.id })
	check("hurt but standing", read(cub, "hp") == 1, tostring(read(cub, "hp")))
	check("and not dead", not tags.entity_has(entity.get(cub.id), "dead"))

	actions.run({ "stat_damage:plus@self:1" }, { card_id = cub.id })
	check("a rune off drops it under its own damage", read(cub, "hp") == 0,
		tostring(read(cub, "hp")))
	check("which is dead", tags.entity_has(entity.get(cub.id), "dead"))
end

-- Two cards were waiting on exactly that: both move a rune rather than make one.
function M.test_codex_a_rune_may_be_moved(check)
	start("pick_green", "pick_green")
	take_the_field("argagarg")
	local shambler = summon("spore_shambler", "mine.army")
	local cub      = summon("tiger_cub", "mine.army")
	actions.run({ "stat_gain:plus@self:2" }, { card_id = shambler.id })
	check("the shambler carries two", read(shambler, "atk") == 2, tostring(read(shambler, "atk")))

	for _, u in ipairs(flow.usable_abilities(shambler.id)) do
		flow.activate(shambler.id, { cub.id }, u.index); break
	end
	flow.settle()
	check("one moved to the cub", read(cub, "atk") == 3, tostring(read(cub, "atk")))
	check("and left the shambler", read(shambler, "atk") == 1, tostring(read(shambler, "atk")))
end

-- A counter that means something needs no tag to say so: "feathered" was a
-- computed tag whose whole job was turning a number into a shift.
function M.test_codex_a_feather_is_a_counter(check)
	start("pick_green", "pick_green")
	local cub = summon("tiger_cub", "mine.army")
	check("grounded", read(cub, "alt") == 0, tostring(read(cub, "alt")))
	actions.run({ "stat_gain:feather@self:1" }, { card_id = cub.id })
	check("a feather rune flies it", read(cub, "alt") == 1, tostring(read(cub, "alt")))
	check("and no tag was needed to say so",
		require("declaration").G.computed_tags.feathered == nil)
end

-- A rune is a number on the unit now rather than an attack point with a story.
-- Two cards were waiting on that: one asks whether there is a rune already, and
-- one hands out overpower to whatever is wearing one.
function M.test_codex_runes_are_a_number(check)
	start("pick_green", "pick_green")
	take_the_field("argagarg")
	local cub = summon("tiger_cub", "mine.army")
	local favour = require("cards").create("forests_favor", zones.find_id("hand", "mine"))

	flow.play_card(favour.id, { cub.id })
	flow.settle()
	check("the rune is recorded", cub.stats.plus == 1, tostring(cub.stats.plus))
	check("and it is worth a point", read(cub, "atk") == 3, tostring(read(cub, "atk")))

	local again = require("cards").create("forests_favor", zones.find_id("hand", "mine"))
	local named = {}
	for _, id in ipairs(require("targeting").candidates(again.id,
		require("cards").def(entity.get(again.id)).target)) do
		named[entity.get(id).def_key] = true
	end
	check("a runed unit is not offered a second one", not named.tiger_cub)

	summon("blooming_elm", "mine.structures")
	check("and the elm sees it as overpowering",
		tags.entity_has(entity.get(cub.id), "runed"))
end

-- Control that lasts a turn is given back at the *victim's* upkeep, not at the
-- taker's end of turn: "set_owner" names a seat or "mine", and only the seat
-- getting the unit back can say "mine" about it.
function M.test_codex_a_kidnapping_ends(check)
	start("pick_red", "pick_green")
	take_the_field("drakk")
	local theirs = summon("tiger_cub", "enemy.army")
	local kidnap = require("cards").create("kidnapping", zones.find_id("hand", "mine"))

	flow.play_card(kidnap.id, { theirs.id })
	flow.settle()
	check("it came over", tags.owner_of(entity.get(theirs.id)) == "south",
		tostring(tags.owner_of(entity.get(theirs.id))))
	check("and is marked as borrowed", theirs.stats.taken == 1, tostring(theirs.stats.taken))

	actions.run({ "activate_zone:rules_upkeep" }, {})
	check("the taker's own upkeep does not hand it back", theirs.stats.taken == 1,
		tostring(theirs.stats.taken))
end

-- A trigger on the card an ongoing spell is standing on. The spell is in the
-- ongoing row and never enters the duel, so the rule is asked of the fighter
-- and reaches back through "attached_to".
function M.test_codex_an_attachment_speaks_in_combat(check)
	start("pick_green", "pick_green")
	take_the_field("argagarg")
	local bear   = summon("barkcoat_bear", "mine.army")
	local spirit = require("cards").create("spirit_of_the_panda", zones.find_id("hand", "mine"))
	flow.play_card(spirit.id, { bear.id })
	flow.settle()
	post("mad_man", "enemy", 1)

	local gold = seat("south").stats.gold
	use(bear, "strike_lead", { in_zone("enemy.patrol").id })
	flow.settle()
	check("attacking paid a gold", seat("south").stats.gold == gold + 1,
		tostring(seat("south").stats.gold - gold))
end

-- Upkeep rules that read the whole table. The horselord asks only whether it
-- should join *this* seat, so each player's own upkeep decides it and neither
-- has to name the other's chair.
function M.test_codex_the_horselord_walks(check)
	start("pick_green", "pick_green")
	local horse = summon("dothram_horselord", "enemy.army")
	summon("gigadon", "mine.army")

	actions.run({ "activate_zone:rules_upkeep" }, {})
	check("it joined the bigger army", tags.owner_of(entity.get(horse.id)) == "south",
		tostring(tags.owner_of(entity.get(horse.id))))
end

-- The drums are beaten once, at upkeep, and what they lend is handed back with
-- everything else at the end of the turn. A continuous count is not sayable;
-- a count taken at a moment is, and the moment the card is about is the attack.
function M.test_codex_war_drums_beat_at_upkeep(check)
	start("pick_red", "pick_green")
	take_the_field("drakk")
	require("cards").create("war_drums", zones.find_id("ongoing", "mine"))
	local dog = summon("mad_man", "mine.army")
	summon("tiger_cub", "mine.army")

	actions.run({ "activate_zone:rules_upkeep" }, {})
	check("two units, so two more attack", read(dog, "atk") == 3, tostring(read(dog, "atk")))
	actions.run({ "activate_zone:mine.army:by_column:endturn" }, {})
	check("and the turn takes it back", read(dog, "atk") == 1, tostring(read(dog, "atk")))
end

-- Nothing in the engine records who did a killing, and a reaction to "died"
-- names the corpse rather than the killer. So the killer marks what it aimed at
-- and asks afterwards whether the mark is still standing — the same "mark" the
-- sparkshot column uses, cleared on the way out.
function M.test_codex_a_kill_can_be_answered(check)
	start("pick_red", "pick_green")
	seat("south").stats.gold = 20
	local house = require("cards").create("firehouse", zones.find_id("structures", "mine"))
	local weak  = require("cards").create("wisp", zones.find_id("army", "enemy"))

	flow.activate(house.id, { weak.id }, 1)
	flow.settle()
	check("a kill leaves the firehouse ready", not entity.get(house.id).exhausted,
		tostring(entity.get(house.id).exhausted))

	local tough = require("cards").create("gigadon", zones.find_id("army", "enemy"))
	flow.activate(house.id, { tough.id }, 1)
	flow.settle()
	check("a survivor does not", entity.get(house.id).exhausted == true,
		tostring(entity.get(house.id).exhausted))
	check("and no mark is left lying about", entity.get(tough.id).stats.mark == 0,
		tostring(entity.get(tough.id).stats.mark))
end

-- Paying more for the better half is a question with two answers, and the dearer
-- one carries its own cost. Declining is the offer's own "No choice" button,
-- since the plain half of this card is doing nothing.
function M.test_codex_a_dearer_half_is_offered_only_when_it_can_be_paid(check)
	start("pick_red", "pick_green")
	require("cards").create("tech_2", zones.find_id("tech", "mine"))
	local me, them = seat("south"), seat("north")
	me.stats.gold = 4
	local raider = require("cards").create("marauder", zones.find_id("hand", "mine"))

	flow.play_card(raider.id, {})
	flow.settle()
	check("the offer opened", phase.current().key == "options", phase.current().key)
	check("the boost is refused with one gold left",
		not flow.can_play(in_zone("options", "mr_boost").id))

	me.stats.gold = 9
	check("and offered once it is affordable", flow.can_play(in_zone("options", "mr_boost").id))
	local workers = them.stats.workers
	flow.play_card(in_zone("options", "mr_boost").id, {})
	flow.settle()
	check("three more gold went", me.stats.gold == 6, tostring(me.stats.gold))
	check("and a worker of theirs with it", them.stats.workers == workers - 1,
		tostring(them.stats.workers))
end

-- "leaves" carries a "needs" like every other block, and this is the shape that
-- wanted it: one departure with two answers, told apart by something that is not
-- a place. On its owner's turn the bomber is quiet; on anybody else's it goes off
-- in the face of whoever is up.
function M.test_codex_a_departure_may_ask_a_question(check)
	start("pick_red", "pick_green")
	local mine   = summon("crash_bomber", "mine.army")
	local mybase = base_of("mine")

	zones.move_card(mine.id, zones.find_id("discard", "mine"))
	flow.settle()
	check("dying on its own owner's turn, it spares that base",
		mybase.stats.integrity == 20, tostring(mybase.stats.integrity))

	local theirs = summon("crash_bomber", "enemy.army")
	zones.move_card(theirs.id, zones.find_id("discard", "enemy"))
	flow.settle()
	check("theirs going off on this turn takes a point off the base of whoever is up",
		mybase.stats.integrity == 19, tostring(mybase.stats.integrity))
end

-- "3 damage divided as you choose" is three picks, not three targets. The share
-- is how many times a card was pointed at, so nothing carries an amount beside
-- the list — "@target" already means every pick, in the order they were made.
function M.test_codex_damage_divides_by_being_aimed_twice(check)
	start("pick_red", "pick_green")
	take_the_field("jaina")
	local z = zones.find("patrol", "enemy")
	local a = require("cards").create("gigadon", z.id)
	local b = require("cards").create("gigadon", z.id)
	zones.place_in_slot(a.id, z.slots[1]); a.stats.slot = 1
	zones.place_in_slot(b.id, z.slots[2]); b.stats.slot = 2

	seat("south").stats.gold = 20
	local sparks = require("cards").create("ember_sparks", zones.find_id("hand", "mine"))
	flow.play_card(sparks.id, { a.id, a.id, a.id })
	flow.settle()
	check("all three points went onto the one it was aimed at three times",
		read(a, "hp") == 5, tostring(read(a, "hp")))
	check("and none onto the other", read(b, "hp") == 8, tostring(read(b, "hp")))

	seat("south").stats.gold = 20
	local again = require("cards").create("ember_sparks", zones.find_id("hand", "mine"))
	flow.play_card(again.id, { b.id, b.id, a.id })
	flow.settle()
	check("two and one lands two and one", read(a, "hp") == 4 and read(b, "hp") == 6,
		read(a, "hp") .. "/" .. read(b, "hp"))
end

-- The click path is the whole of the difference, and which word said how many
-- picks there are is what decides it: an aim written with a count refuses a card
-- it already holds, because "up to two units" means two different ones.
function M.test_codex_only_a_spread_aim_takes_a_card_twice(check)
	local targeting = require("targeting")
	start("pick_red", "pick_green")
	take_the_field("jaina")
	local prey = summon("gigadon", "enemy.army")
	seat("south").stats.gold = 20

	local volley = require("cards").create("burning_volley", zones.find_id("hand", "mine"))
	in_zone("mine.army", "jaina").stats.ripe = 7
	targeting.start(volley.id, require("cards").def(entity.get(volley.id)).target)
	check("the first point goes on", targeting.add(prey.id))
	check("and so does the second", targeting.add(prey.id))
	check("the share is counted", targeting.share(prey.id) == 2,
		tostring(targeting.share(prey.id)))
	targeting.clear()

	local lust = require("cards").create("bloodlust", zones.find_id("hand", "mine"))
	local mine = summon("mad_man", "mine.army")
	targeting.start(lust.id, require("cards").def(entity.get(lust.id)).target)
	check("an ordinary aim takes it once", targeting.add(mine.id))
	check("and refuses it twice", not targeting.add(mine.id))
	targeting.clear()
end

-- A keyword is granted by saying once what it does, under a name, and letting a
-- condition decide who is wearing it. Overpower is an ability, so the computed
-- tag carries "abilities" — it joins the card's own and its zone's in one list.
function M.test_codex_a_keyword_can_be_lent(check)
	start("pick_green", "pick_green")
	local runner = summon("tiger_cub", "mine.army")
	runner.stats.plus = 1
	check("a rune alone is not the grant", not tags.entity_has(entity.get(runner.id), "runed"))

	local before = #require("cards").abilities(entity.get(runner.id))
	summon("blooming_elm", "mine.structures")
	check("the elm is what lends it", tags.entity_has(entity.get(runner.id), "runed"))
	check("and the ability comes with the word",
		#require("cards").abilities(entity.get(runner.id)) == before + 1,
		tostring(#require("cards").abilities(entity.get(runner.id))))

	local lent = {}
	for _, kw in ipairs(require("cards").keywords(entity.get(runner.id))) do
		if kw.granted then lent[#lent + 1] = kw.tag end
	end
	check("the panel says it was lent rather than printed", lent[1] == "runed",
		table.concat(lent, ","))

	local weak = post("wisp", "enemy", 1)
	weak.stats.guard = 0
	local base = base_of("enemy").stats.integrity
	use(runner, "strike_lead", { weak.id })
	flow.settle()
	check("and it overpowers", base_of("enemy").stats.integrity < base,
		base .. "->" .. base_of("enemy").stats.integrity)
end

-- "others." is what makes a rule about the rest of the board sayable. Without it
-- the mimic's borrowed flight is the flier it is looking for, which is a question
-- that needs its own answer — and the validator refuses that shape outright.
function M.test_codex_a_card_reads_the_rest_of_the_board(check)
	start("pick_green", "pick_green")
	local mimic = summon("wandering_mimic", "mine.army")
	check("alone it is grounded", read(mimic, "alt") == 0, tostring(read(mimic, "alt")))
	check("and unseen", read(mimic, "sneak") == 0, tostring(read(mimic, "sneak")))

	local flier = summon("shoddy_glider", "enemy.army")
	local tiger = summon("stalking_tiger", "enemy.army")
	check("another flier lends it flight and the anti-air to use it",
		read(mimic, "alt") == 1 and read(mimic, "aa") == 1,
		read(mimic, "alt") .. "/" .. read(mimic, "aa"))
	check("a stealthy card lends it stealth", read(mimic, "sneak") == 1,
		tostring(read(mimic, "sneak")))

	zones.move_card(flier.id, zones.find_id("discard", "enemy"))
	zones.move_card(tiger.id, zones.find_id("discard", "enemy"))
	check("and both go when they do", read(mimic, "alt") == 0 and read(mimic, "sneak") == 0,
		read(mimic, "alt") .. "/" .. read(mimic, "sneak"))
end

-- A keyword with no number under it is copied the same way: ask whether anybody
-- else carries the tag, and wear one that grants what the tag grants. Nothing
-- has to be counted into a stat first.
function M.test_codex_a_keyword_with_no_number_is_copied_too(check)
	start("pick_green", "pick_green")
	local mimic = summon("wandering_mimic", "mine.army")
	local before = #require("cards").abilities(entity.get(mimic.id))
	check("nobody to copy", not tags.entity_has(entity.get(mimic.id), "mimic_over"))

	summon("dothram_horselord", "enemy.army")
	check("an overpowering card lends it the word",
		tags.entity_has(entity.get(mimic.id), "mimic_over"))
	check("and the ability with it",
		#require("cards").abilities(entity.get(mimic.id)) == before + 1,
		tostring(#require("cards").abilities(entity.get(mimic.id))))

	local weak = post("wisp", "enemy", 1)
	weak.stats.guard = 0
	local base = base_of("enemy").stats.integrity
	use(mimic, "strike_lead", { weak.id })
	flow.settle()
	check("so the excess reaches the base", base_of("enemy").stats.integrity < base,
		base .. "->" .. base_of("enemy").stats.integrity)
end

-- Haste is read once, as the card lands, so a granted one has to be worn by
-- then. "hasty" is the union every play block asks about now — the printed word
-- or the copied one — and an ordinary hasty card notices nothing.
function M.test_codex_haste_is_asked_as_a_union(check)
	start("pick_green", "pick_green")
	seat("south").stats.gold = 20
	require("cards").create("tech_2", zones.find_id("tech", "mine"))

	local slow = require("cards").create("wandering_mimic", zones.find_id("hand", "mine"))
	flow.play_card(slow.id, {})
	flow.settle()
	check("with nothing hasty about, the mimic waits a turn",
		slow.stats.ready_since == 0, tostring(slow.stats.ready_since))

	summon("mad_man", "enemy.army")
	seat("south").stats.gold = 20
	local quick = require("cards").create("wandering_mimic", zones.find_id("hand", "mine"))
	flow.play_card(quick.id, {})
	flow.settle()
	check("with a hasty card out there, it attacks at once",
		quick.stats.ready_since == 1, tostring(quick.stats.ready_since))

	start("pick_red", "pick_green")
	seat("south").stats.gold = 20
	local dog = require("cards").create("mad_man", zones.find_id("hand", "mine"))
	flow.play_card(dog.id, {})
	flow.settle()
	check("and a printed haste still arrives ready", dog.stats.ready_since == 1,
		tostring(dog.stats.ready_since))
end

-- A ward is a keyword far more often than it is one card, and "accepts" is read
-- through behaviour now, so it comes from the same four places everything else
-- about a card does. Untargetable is one line on the tag rather than one per
-- card that has the word — and being grantable falls out of that for free.
function M.test_codex_a_ward_is_a_keyword(check)
	local targeting = require("targeting")
	local function aimable(card_id, spec)
		local seen = {}
		for _, id in ipairs(targeting.candidates(card_id, spec)) do
			seen[entity.get(id).def_key] = true
		end
		return seen
	end

	start("pick_red", "pick_green")
	take_the_field("jaina")
	summon("moss_ancient", "enemy.army")
	summon("gigadon", "enemy.army")
	local dart = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local can  = aimable(dart.id, require("cards").def(entity.get(dart.id)).target)
	check("an ordinary unit may be darted", can.gigadon == true)
	check("one wearing the word may not", can.moss_ancient == nil)

	start("pick_green", "pick_green")
	take_the_field("midori")
	local mimic = summon("wandering_mimic", "enemy.army")
	local blast = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local spec  = require("cards").def(entity.get(blast.id)).target
	check("with nobody to copy, the mimic is fair game",
		aimable(blast.id, spec).wandering_mimic == true)

	summon("potent_basilisk", "enemy.army")
	check("a warded card out there lends it the ward",
		aimable(blast.id, spec).wandering_mimic == nil)
	check("and the basilisk still guards itself",
		aimable(blast.id, spec).potent_basilisk == nil)

	local striker, hit = summon("gigadon", "mine.army"), {}
	for _, u in ipairs(flow.usable_abilities(striker.id)) do
		if u.rule.key == "strike_free" then
			for _, id in ipairs(targeting.candidates(striker.id, u.rule.target)) do
				hit[entity.get(id).def_key] = true
			end
		end
	end
	check("an attack is not a cast, so it still lands", hit.wandering_mimic == true)
end

-- A price with arithmetic in it is a compute the block named, and flow.plan has
-- always read a cost amount through the same total() a condition uses. Two places
-- had not been told: the validator refused the shape, and the tooltip quoted the
-- number with nothing bound, so a hand said nought and the pile took seven.
function M.test_codex_a_price_may_be_worked_out(check)
	start("pick_green", "pick_green")
	require("cards").create("tech_2", zones.find_id("tech", "mine"))
	seat("south").stats.gold = 20
	local beast = require("cards").create("gigadon", zones.find_id("hand", "mine"))
	local cost  = require("cards").def(entity.get(beast.id)).cost

	check("printed nine with nothing green out",
		require("cards").cost_text(cost, beast.id) == "9 gold@mine.player",
		require("cards").cost_text(cost, beast.id))
	summon("tiger_cub", "mine.army")
	summon("tiger_cub", "mine.army")
	check("seven with two of them",
		require("cards").cost_text(cost, beast.id) == "7 gold@mine.player",
		require("cards").cost_text(cost, beast.id))

	local purse = seat("south").stats.gold
	flow.play_card(beast.id, {})
	flow.settle()
	check("and seven is what the pile took", purse - seat("south").stats.gold == 7,
		tostring(purse - seat("south").stats.gold))
end

-- Overpower for one turn: the keyword's ability under a computed tag, worn while
-- a stat says so and handed back where every other lent thing is.
function M.test_codex_overpower_can_be_lent_for_a_turn(check)
	start("pick_green", "pick_green")
	take_the_field("argagarg")
	local cub = summon("tiger_cub", "mine.army")
	check("it does not rampage on its own", not tags.entity_has(entity.get(cub.id), "rampaging"))

	in_zone("mine.army", "argagarg").stats.ripe = 5
	seat("south").stats.gold = 20
	local herd = require("cards").create("stampede", zones.find_id("hand", "mine"))
	flow.play_card(herd.id, {})
	flow.settle()
	check("the stampede lends it", tags.entity_has(entity.get(cub.id), "rampaging"))

	local weak = post("wisp", "enemy", 1)
	weak.stats.guard = 0
	local base = base_of("enemy").stats.integrity
	use(cub, "strike_lead", { weak.id })
	flow.settle()
	check("so the excess reaches the base", base_of("enemy").stats.integrity < base,
		base .. "->" .. base_of("enemy").stats.integrity)

	actions.run({ "activate_zone:mine.army:by_column:endturn" }, {})
	check("and the turn takes it back", not tags.entity_has(entity.get(cub.id), "rampaging"))
end

-- Armour piercing is not a number on the attacker, it is the armour step not
-- happening: the column asks whether the thing across it goes straight through.
function M.test_codex_armour_can_be_pierced(check)
	start("pick_green", "pick_green")
	take_the_field("calamandra")
	local tree = post("ironbark_treant", "enemy", 1)
	tree.stats.guard = 3
	local cub = summon("tiger_cub", "mine.army")
	local hp = read(tree, "hp")
	use(cub, "strike_lead", { tree.id })
	flow.settle()
	check("armour eats it first", read(tree, "hp") == hp, tostring(read(tree, "hp")))

	start("pick_green", "pick_green")
	take_the_field("calamandra")
	local tree2 = post("ironbark_treant", "enemy", 1)
	tree2.stats.guard = 3
	local cub2 = summon("tiger_cub", "mine.army")
	seat("south").stats.gold = 20
	local rage = require("cards").create("ferocity", zones.find_id("hand", "mine"))
	flow.play_card(rage.id, {})
	flow.settle()
	check("ferocity marks your units", cub2.stats.pierce == 2, tostring(cub2.stats.pierce))

	local hp2 = read(tree2, "hp")
	use(cub2, "strike_lead", { tree2.id })
	flow.settle()
	check("and the armour is stepped over", read(tree2, "hp") < hp2,
		hp2 .. "->" .. read(tree2, "hp"))
end

-- Invisible is a ward with a condition on the aimer: only a player holding a
-- detector may point at it. A "receive" on a computed tag says exactly that, and
-- taking a post is what gives it up.
function M.test_codex_invisible_is_a_ward_with_a_condition(check)
	local targeting = require("targeting")
	start("pick_red", "pick_green")
	take_the_field("jaina")
	local tiger = summon("stalking_tiger", "enemy.army")
	local dart  = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local spec  = require("cards").def(entity.get(dart.id)).target
	local function aimable()
		local seen = {}
		for _, id in ipairs(targeting.candidates(dart.id, spec)) do
			seen[entity.get(id).def_key] = true
		end
		return seen
	end

	check("with no Feral hero it is fair game", aimable().stalking_tiger == true)
	require("cards").create("calamandra", zones.find_id("army", "north"))
	check("with one, nothing may point at it", aimable().stalking_tiger == nil)
	tiger.stats.slot = 1
	check("a post gives the hiding up", aimable().stalking_tiger == true)

	tiger.stats.slot = 0
	require("cards").create("tower", zones.find_id("addon", "mine"))
	check("and a tower sees it anyway", aimable().stalking_tiger == true)
end

-- **The ward is one-sided, and the word says so.** Codex prints Invisible as "to
-- opponents without a detector, this is untargetable", and Sirlin's ruling is
-- explicit that you may point at your own invisible things with no detector at
-- all. Written as a condition that would need an "or" the grammar has not got —
-- a detector, *or* the aimer is its owner — so the side is "whose" on the block.
--
-- It was carried before by "count@enemy.self" inside the computed tag, which
-- worked only because a tag was read as whoever was up; anchored to the card's
-- own owner that sentence names nobody, and the rule had to move to the ward.
function M.test_codex_invisible_does_not_hide_from_its_owner(check)
	local targeting = require("targeting")
	start("pick_green", "pick_green")
	take_the_field("calamandra")
	local tiger = summon("stalking_tiger", "mine.army")
	local dart  = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local spec  = require("cards").def(entity.get(dart.id)).target
	local function mine_aimable()
		for _, id in ipairs(targeting.candidates(dart.id, spec)) do
			if id == tiger.id then return true end
		end
		return false
	end

	check("it is hiding", tags.entity_has(entity.get(tiger.id), "hidden"))
	check("and its own side may point at it with no detector", mine_aimable())
end

-- Mindparry Monk prints "Opponents can't aim spells or abilities at your units
-- or heroes", and the ward said "nothing may aim a spell at this" — so it
-- refused its own side and let the other through, which is the card backwards.
function M.test_codex_mindparry_stops_the_opponent_and_not_its_own_side(check)
	local targeting = require("targeting")
	start("pick_white", "pick_green")
	local cub  = summon("tiger_cub", "mine.army")
	summon("mindparry_monk", "mine.army")
	local dart = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local spec = require("cards").def(entity.get(dart.id)).target
	local function aimable_by_mine()
		for _, id in ipairs(targeting.candidates(dart.id, spec)) do
			if id == cub.id then return true end
		end
		return false
	end

	check("the Monk parries it", tags.entity_has(entity.get(cub.id), "parried"))
	check("and its own side may still aim a spell at it", aimable_by_mine())
end

-- "Put up to two units from your hand into play if you have tech buildings of
-- the same tech level as them" is four questions with one answer, which is what
-- a union of computed tags is for: each tier asks its own, "buildable" says any.
function M.test_codex_a_tier_gate_is_a_union(check)
	local targeting = require("targeting")
	start("pick_green", "pick_green")
	take_the_field("calamandra")
	in_zone("mine.army", "calamandra").stats.ripe = 5
	seat("south").stats.gold = 20

	local cub   = require("cards").create("tiger_cub", zones.find_id("hand", "mine"))
	local tiger = require("cards").create("stalking_tiger", zones.find_id("hand", "mine"))
	local blow  = require("cards").create("feral_strike", zones.find_id("hand", "mine"))
	local spec  = require("cards").def(entity.get(blow.id)).target
	local function pool()
		local seen = {}
		for _, id in ipairs(targeting.candidates(blow.id, spec)) do
			seen[entity.get(id).def_key] = true
		end
		return seen
	end

	check("a tech 0 unit needs no building", pool().tiger_cub == true)
	check("a tech 2 one does", pool().stalking_tiger == nil)
	require("cards").create("tech_1", zones.find_id("tech", "mine"))
	require("cards").create("tech_2", zones.find_id("tech", "mine"))
	check("and is offered once it stands", pool().stalking_tiger == true)

	flow.play_card(blow.id, { cub.id, tiger.id })
	flow.settle()
	check("both walked onto the table", in_zone("mine.army", "tiger_cub") ~= nil
		and in_zone("mine.army", "stalking_tiger") ~= nil)
	check("with the arrival fatigue they came with",
		entity.get(cub.id).stats.ready_since == 0, tostring(entity.get(cub.id).stats.ready_since))
end

-- **Killing a unit is a death, not an erasure.** Every obliterate in the box used
-- to reach for the verb that removes a card from the game, so Gorgon's "Dies:
-- draw a card" went off when damage killed it and said nothing when Zarramonde
-- did — one rule, two roads, and only one of them worked.
function M.test_codex_an_effect_kills_the_same_way_damage_does(check)
	start("pick_red", "pick_green")
	actions.execute("create:mine.deck:nautical_dog:6", {})
	local before = count_in("mine.hand")
	summon("gorgon", "mine.army")
	actions.execute("destroy:mine.army.unit", {})
	check("the gorgon is lying in the discard", in_zone("mine.discard", "gorgon") ~= nil)
	check("and its Dies trigger drew the card", count_in("mine.hand") == before + 1,
		count_in("mine.hand") .. " vs " .. before)
end

-- A hero is the case that needed the grave to be answered per kind: it goes back
-- to its own command zone to wait, not to the discard the units go to. And the
-- wait is the *hero's* own, not its seat's: with three heroes a side, one death
-- must not lock the other two out of being summoned.
function M.test_codex_a_killed_hero_goes_home_to_wait(check)
	start("pick_red", "pick_green")
	local them = in_zone("enemy.command", "midori")
	zones.move_card(them.id, zones.find_id("army", "north"))
	actions.execute("destroy:enemy.army.hero", {})
	check("the hero fell back to their command zone", in_zone("enemy.command", "midori") ~= nil)
	check("and the clock is on the hero that died", them.stats.hero_wait == 2, tostring(them.stats.hero_wait))
	check("not on the heroes beside it", in_zone("enemy.command", "argagarg").stats.hero_wait == 0)
	check("nor on whoever killed it", in_zone("command", "zane").stats.hero_wait == 0)
end

-- The death column used to say every rule twice, once as "mine" and once as
-- "theirs", because a rule read from the seat that is up and only one side's
-- death was that seat's. `each_seat:` wraps the *action* rather than the zone,
-- so the card keeps its place in the column and both sides are answered before
-- the next rule starts — which is the whole reason the halves could go.
function M.test_codex_the_death_column_answers_both_sides(check)
	start("pick_red", "pick_green")
	post("nautical_dog", "mine", 3).stats.hp = 0
	post("nautical_dog", "enemy", 3).stats.hp = 0
	post("nautical_dog", "mine", 4).stats.hp = 0
	post("nautical_dog", "enemy", 4).stats.hp = 0
	local gold_s, gold_n = seat("south").stats.gold, seat("north").stats.gold
	local hand_s, hand_n = count_in("hand"), count_in("enemy.hand")

	actions.execute("activate_zone:rules_death", {})
	flow.settle()

	check("the scavenger post paid its own side", seat("south").stats.gold == gold_s + 1,
		tostring(seat("south").stats.gold - gold_s))
	check("and paid the other side too", seat("north").stats.gold == gold_n + 1,
		tostring(seat("north").stats.gold - gold_n))
	check("the technician post drew for its own side", count_in("hand") == hand_s + 1,
		tostring(count_in("hand") - hand_s))
	check("and drew for the other side too", count_in("enemy.hand") == hand_n + 1,
		tostring(count_in("enemy.hand") - hand_n))
end

-- Two conditions over one card, said as a tag on the card rather than as a
-- "max:" over the scope: the halves went because a per-card question is one the
-- count can ask, and "the highest level among my blood heroes is at most three"
-- was only ever a way of saying "this one is".
function M.test_codex_drakk_falls_low(check)
	start("pick_red", "pick_green")
	local him = summon("drakk", "army")
	him.stats.life, him.stats.level = 0, 2
	local theirs = entity.get(entity.get(zones.find_id("base", "enemy")).cards[1])

	actions.execute("activate_zone:rules_death", {})
	flow.settle()
	check("falling before level four cost them one", theirs.stats.integrity == 19,
		tostring(theirs.stats.integrity))

	start("pick_red", "pick_green")
	local grown = summon("drakk", "army")
	grown.stats.life, grown.stats.level = 0, 4
	theirs = entity.get(entity.get(zones.find_id("base", "enemy")).cards[1])

	actions.execute("activate_zone:rules_death", {})
	flow.settle()
	check("falling at four cost them nothing", theirs.stats.integrity == 20,
		tostring(theirs.stats.integrity))
end

-- The gold was always per claim and the draw was not, which no reading of the
-- card supports. Folding the halves made the two agree.
function M.test_codex_every_claim_is_paid(check)
	start("pick_red", "pick_green")
	for _ = 1, 2 do
		local c = summon("nautical_dog", "army")
		c.stats.hp, c.stats.insured = 0, 1
	end
	local gold, hand = seat("south").stats.gold, count_in("hand")

	actions.execute("activate_zone:rules_death", {})
	flow.settle()

	check("both claims paid their price", seat("south").stats.gold == gold + 2,
		tostring(seat("south").stats.gold - gold))
	check("and both drew a card", count_in("hand") == hand + 2,
		tostring(count_in("hand") - hand))
end

-- **"If you do" is not a cost.** Circle of Life read as one, so a board with no
-- green unit made the spell unplayable, where the box casts it and fizzles only
-- the consequence. The sacrifice is an offer now — the same shape Marauder's
-- Boost 3 already uses, a rules card whose own cost decides whether it may be
-- taken — so the spell always casts and the giving is a question asked after.
function M.test_codex_a_sacrifice_you_cannot_make_still_casts(check)
	start("pick_green", "pick_green")
	summon("midori", "army")
	actions.run({ "create:mine.hand:circle_of_life:1" }, {})
	local spell = in_zone("hand", "circle_of_life")

	check("with nothing to give, the spell is still playable", flow.can_play(spell.id) == true)
	local gold = seat("south").stats.gold
	flow.play_card(spell.id, {})
	flow.settle()
	check("it went to the discard", in_zone("discard", "circle_of_life") ~= nil)
	check("and it was paid for", seat("south").stats.gold == gold - 3,
		tostring(seat("south").stats.gold - gold))
	local ask = in_zone("options", "col_give")
	check("the giving was asked", ask ~= nil)
	check("but cannot be taken", flow.can_play(ask.id) == false)
	check("and the question has a way out", zones.find("options").dismissable == true)
end

-- The other half: with a unit to give, the offer is payable, the sacrifice asks
-- as a sacrifice always does, and the codex opens off the rules card rather than
-- off the spell — "show:" runs the asker's own "chosen", and the asker is the
-- card standing in the offer.
function M.test_codex_the_sacrifice_pays_and_opens_the_codex(check)
	start("pick_green", "pick_green")
	summon("midori", "army")
	local victim = summon("wisp", "army")
	actions.run({ "create:mine.hand:circle_of_life:1" }, {})

	flow.play_card(in_zone("hand", "circle_of_life").id, {})
	flow.settle()
	local ask = in_zone("options", "col_give")
	check("the giving is payable now", flow.can_play(ask.id) == true)
	flow.play_card(ask.id, {})
	flow.settle()
	check("the green unit was given up", entity.get(victim.id).zone_id == nil)
	check("the rules card is gone with it", in_zone("options", "col_give") == nil)
	check("and the codex is standing in the offer", count_in("options") > 0,
		tostring(count_in("options")))
end

-- The Truth spec, whose whole keyword is one line on a tag now. An Illusion is
-- targetable by everything and dies only to what *aims* at it with a spell or an
-- ability, which is why the write half needed a "when" of its own: "needs" would
-- have refused the aim instead of answering it, and Codex aims with "attack" too.
function M.test_codex_an_illusion_dies_of_being_aimed_at(check)
	start("pick_red", "pick_green")
	local hero  = in_zone("command", "jaina")
	local spell = require("cards").create("fire_dart", zones.find_id("hand", "mine"))
	local aven  = summon("spectral_aven", "enemy.army")

	use(hero, "summon")
	flow.settle()
	seat("south").stats.gold = 9
	flow.play_card(spell.id, { aven.id })
	flow.settle()
	check("the aven died of the aim", entity.get(aven.id).zone_id ~= zones.find_id("army", "enemy"))
	-- Not of the three damage: it has 2 hp and a corpse at nought would read the
	-- same, so the untouched stat is what says which of the two killed it.
	check("and not of the dart", entity.get(aven.id).stats.hp == 2,
		tostring(entity.get(aven.id).stats.hp))
end

-- And being attacked is not being aimed at, which is the half the keyword would
-- have got wrong if the write half answered every aim: Codex's combat is a
-- target spec too.
function M.test_codex_an_illusion_survives_being_attacked(check)
	start("pick_red", "pick_green")
	local tiger = summon("spectral_tiger", "enemy.army")   -- 5/5
	local cub   = summon("tiger_cub", "army")              -- 2/2
	use(cub, "strike_free", { tiger.id })
	flow.settle()
	check("the tiger is still on the board", entity.get(tiger.id).zone_id == zones.find_id("army", "enemy"),
		tostring(entity.get(tiger.id).zone_id))
	check("and took the fight rather than the keyword",
		entity.get(tiger.id).stats.hp == 3, tostring(entity.get(tiger.id).stats.hp))
end

-- The rulebook's own game: three heroes of one colour. Each hero is its own
-- clock and its own level, and how many may stand at once is the tech built.
function M.test_codex_three_heroes_a_side(check)
	start("pick_red", "pick_green")
	seat("south").stats.gold = 20
	seat("south").stats.xp = 9
	local zane, drakk = in_zone("command", "zane"), in_zone("command", "drakk")
	use(zane, "summon")
	flow.settle()
	check("one hero may be summoned at the start", in_zone("army", "zane") ~= nil)
	check("but not a second without tech II", not offers(drakk, "summon"))
	check("a hero in command cannot level", not offers(drakk, "lvl2"))
	check("though the one in play can", offers(zane, "lvl2"))

	require("cards").create("tech_2", zones.find_id("tech"))
	check("tech II lets a second stand", offers(drakk, "summon"))
	use(drakk, "summon")
	flow.settle()
	check("and it does", in_zone("army", "drakk") ~= nil)
	check("a third waits on tech III", not offers(in_zone("command", "jaina"), "summon"))

	zane.stats.level = 6
	actions.execute("activate_zone:mine.army:by_column:upkeep", {})
	check("ripe is each hero's own level", zane.stats.ripe == 6 and drakk.stats.ripe == 1,
		zane.stats.ripe .. " and " .. drakk.stats.ripe)

	local jaina = in_zone("command", "jaina")
	jaina.stats.hero_wait = 2
	actions.execute("stat_damage:hero_wait@each.mine.command:1", {})
	check("a hero's wait ticks where it waits", jaina.stats.hero_wait == 1, tostring(jaina.stats.hero_wait))
	check("and holds it back meanwhile", not offers(jaina, "summon"))
end

return M
