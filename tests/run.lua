-- Headless engine tests. Run from the repo root:
--   luajit tests/run.lua      (LuaJIT = LÖVE's interpreter)
--   lua tests/run.lua

require("headless")

math.randomseed(7)

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local targeting   = require("targeting")
local flow        = require("flow")
local log         = require("log")
local json        = require("json")
local validate    = require("validate")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. name)
	end
end

local function find_card(def_key, zone_key)
	local zid = zone_key and zones.find_id(zone_key)
	for e in entity.each("card") do
		if e.def_key == def_key and (not zid or e.zone_id == zid) then return e end
	end
end

local function zone_count(key)
	local z = zones.find(key)
	return z and #z.cards or -1
end

local function empty_slot()
	for e in entity.each("slot") do
		if not e.occupant then return e.id end
	end
end

local function board_hp()
	local total = 0
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if z and z.zone_type == "grid" then total = total + (e.stats.hp or 0) end
	end
	return total
end

-- Run a single action then settle, like the debug server's `eval`.
local function eval(str)
	actions.execute(str, {})
	flow.settle()
end

-- === json ===
local t  = { a = 1, b = { 1, 2, 3 }, c = 'x"y\n', d = { nested = true } }
local rt = json.decode(json.encode(t))
check("json round trip",
	rt.a == 1 and rt.b[3] == 3 and rt.c == 'x"y\n' and rt.d.nested == true)

-- === menu ===
flow.init("menu.json")
check("menu loads", declaration.G.title == "Ravel")
check("menu shows four games", zone_count("menu") == 4)
check("menu phase is waiting", phase.current().key == "waiting")

-- === demo: basics ===
flow.play_card(find_card("play_demo").id, {})
check("menu card loads demo", declaration.G.title == "The Wandering Road")
check("demo starts with 1 hand card", zone_count("hand") == 1)
check("road holds the other 10 cards", zone_count("road") == 10)
check("player starts at 5 hp", entity.sum_stat("hp") == 5)

eval("fill:hand:storm:1")
local storm = find_card("storm", "hand")
local hp0   = entity.sum_stat("hp")
flow.play_card(storm.id, {})
check("demo card applies its effect", entity.sum_stat("hp") == hp0 - 1)
check("played card goes to past", zone_count("past") == 1)
check("a new card was drawn", zone_count("hand") == 2)

eval("set_stat:hp:10")
eval("gain_stat:hp:3")
check("hp clamps at declared max", entity.sum_stat("hp") == 10)

-- === demo: undo (state and log together) ===
local hp_before   = entity.sum_stat("hp")
local hand_before = zones.find("hand").cards[1]
local log_before  = log.count()
flow.play_card(hand_before, {})
check("plays write log lines", log.count() > log_before)
check("undo works", flow.undo())
check("undo restores hp and hand",
	entity.sum_stat("hp") == hp_before and zones.find("hand").cards[1] == hand_before)
check("undo erases the undone log lines", log.count() == log_before)

-- === demo: defeat ===
eval("set_stat:hp:0")
check("defeat overlay pushed at 0 hp", phase.current().key == "defeat")
check("fate card dealt to offer", zone_count("offer") == 1)
flow.pick(zones.find("offer").cards[1])
check("picking the fate card returns to menu", declaration.G.title == "Ravel")

-- === demo: victory (picking through any crossroads choice on the way) ===
flow.play_card(find_card("play_demo").id, {})
for _ = 1, 30 do
	local key = phase.current().key
	if key == "victory" or key == "defeat" then break end
	if phase.is_overlay() then
		flow.pick(zones.find("offer").cards[1])
	else
		eval("set_stat:hp:5")
		local h = zones.find("hand")
		if #h.cards == 0 then break end
		flow.play_card(h.cards[1], {})
	end
end
check("victory overlay after surviving the road", phase.current().key == "victory")
flow.pick(zones.find("offer").cards[1])
check("victory returns to menu", declaration.G.title == "Ravel")

-- === demo: outcomes wait while a choice is open ===
flow.init("demo.json")
eval("push_phase:path_choice")
check("path options dealt from their deck", zone_count("offer") == 3 and zone_count("paths") == 0)
eval("destroy:road")
eval("destroy:hand")
check("no victory while the choice is open", phase.current().key == "path_choice")
flow.pick(zones.find("offer").cards[1])
check("picked path lands in hand", zone_count("hand") == 1)
check("unpicked paths return to their deck", zone_count("paths") == 2)
flow.play_card(zones.find("hand").cards[1], {})
check("victory once the path resolves", phase.current().key == "victory")

-- === seeded RNG ===
flow.init("demo.json", 42)
local seq_a = {}
for _, cid in ipairs(zones.find("road").cards) do seq_a[#seq_a + 1] = entity.get(cid).def_key end
flow.init("demo.json", 42)
local seq_b = {}
for _, cid in ipairs(zones.find("road").cards) do seq_b[#seq_b + 1] = entity.get(cid).def_key end
check("seeded loads shuffle identically", table.concat(seq_a, ",") == table.concat(seq_b, ","))

-- === castle: setup ===
flow.init("castle.json")
local G = declaration.G
check("castle loads", G.title == "Castle Lord")
check("castle starts in build1", phase.current().key == "build1")
check("hand dealt 3 plus the pass card", zone_count("hand") == 4)
check("throne auto-played to board", find_card("throne_room", "board") ~= nil)
check("throne sits in its slot", entity.get(find_card("throne_room").slot_id).slot_idx == 13)
check("starting gold is 20", entity.sum_stat("gold") == 20)
check("round counter starts at 1", entity.sum_stat("round") == 1)
check("build deck has 15 minus 3 dealt", zone_count("build_deck") == 12)
for _, key in ipairs(G.phase_list) do
	check("overlay phase not in sequence: " .. key, G.phase_by_key[key].type ~= "overlay")
end

-- === castle: the pass card, the forced-play escape hatch ===
local pass_id
for _, cid in ipairs(zones.find("hand").cards) do
	if entity.get(cid).def_key == "pass" then pass_id = cid end
end
check("pass card dealt with the hand", pass_id ~= nil)
flow.play_card(pass_id, {})
check("pass advances the phase", phase.current().key == "build2")
check("pass vanishes instead of joining the discard", zone_count("graveyard") == 3)
flow.undo()
check("undo returns to build1 with the pass in hand", phase.current().key == "build1"
	and entity.get(pass_id).zone_id == zones.find_id("hand"))

-- === castle: activation cost ===
local throne = find_card("throne_room")
eval("set_stat:gold:0")
check("cannot inspire without gold", flow.activate(throne.id) == false)
eval("set_stat:gold:3")
local morale0 = entity.sum_stat("morale")
check("inspire succeeds with gold", flow.activate(throne.id))
check("morale +1 and gold -2",
	entity.sum_stat("morale") == morale0 + 1 and entity.sum_stat("gold") == 1)
check("activation exhausts the throne", throne.exhausted == true)
check("exhausted cards cannot activate again", flow.activate(throne.id) == false)

-- === castle: play cost gating ===
eval("set_stat:gold:0")
eval("fill:hand:mercenaries:1")
check("cannot afford mercenaries at 0 gold",
	flow.play_card(find_card("mercenaries", "hand").id, {}) == false)

-- === castle: slot targeting ===
eval("set_stat:gold:5")
eval("fill:hand:farm:1")
local farm  = find_card("farm", "hand")
local slot  = empty_slot()
local gold0 = entity.sum_stat("gold")
flow.play_card(farm.id, { slot })
check("farm placed on board", farm.zone_id == zones.find_id("board"))
check("farm occupies the chosen slot", entity.get(slot).occupant == farm.id)
check("farm cost 1 gold", entity.sum_stat("gold") == gold0 - 1)
check("turn ended into build2", phase.current().key == "build2")
check("hand redealt with 3 plus the pass card", zone_count("hand") == 4)

-- === castle: stat clamping on cards (overheal fix) ===
actions.execute("lose_target_stat:hp:2", { targets = { farm.id } })
check("farm damaged to 1 hp", farm.stats.hp == 1)
actions.execute("gain_target_stat:hp:9", { targets = { farm.id } })
check("healing clamps at hp_max", farm.stats.hp == 3)

-- === castle: computed-tag targeting ===
actions.execute("lose_target_stat:hp:1", { targets = { farm.id } })
eval("fill:hand:repair:1")
local rep = find_card("repair", "hand")
targeting.start(rep.id, cards.def(rep).target)
check("damaged farm eligible for repair", targeting.is_eligible(farm.id))
check("undamaged throne not eligible", not targeting.is_eligible(throne.id))
targeting.clear()
actions.execute("gain_target_stat:hp:1", { targets = { farm.id } })

-- === castle: draft overlay via architect ===
eval("set_stat:gold:5")
eval("fill:hand:architect:1")
local deck0 = zone_count("build_deck")
local hand0 = zone_count("hand")
flow.play_card(find_card("architect", "hand").id, {})
check("draft overlay active", phase.current().key == "draft")
check("3 cards offered", zone_count("offer") == 3)
local pick_id = zones.find("offer").cards[1]
flow.pick(pick_id)
check("picked card lands in hand", entity.get(pick_id).zone_id == zones.find_id("hand"))
check("offer cleared", zone_count("offer") == 0)
check("unpicked cards returned to deck", zone_count("build_deck") == deck0 - 1)
check("draft resumes build2 without redealing", phase.current().key == "build2")
check("hand kept its size (architect out, pick in)", zone_count("hand") == hand0)

-- === castle: sub-card choice via an internal deck (royal decree) ===
eval("set_stat:gold:9")
eval("fill:hand:royal_decree:1")
flow.play_card(find_card("royal_decree", "hand").id, {})
check("decree opens the edict overlay", phase.current().key == "decree")
check("three edicts offered from their deck",
	zone_count("offer") == 3 and zone_count("edicts") == 0)
check("decree cost was paid", entity.sum_stat("gold") == 7)

flow.undo()
check("undo backs out of the whole choice",
	phase.current().key == "build2" and zone_count("offer") == 0
	and zone_count("edicts") == 3
	and find_card("royal_decree", "hand") ~= nil and entity.sum_stat("gold") == 9)

flow.play_card(find_card("royal_decree", "hand").id, {})
local pick
for _, cid in ipairs(zones.find("offer").cards) do
	if entity.get(cid).def_key == "tax_levy" then pick = cid end
end
flow.pick(pick)
check("picked edict lands in hand", entity.get(pick).zone_id == zones.find_id("hand"))
check("unpicked edicts return to their deck",
	zone_count("edicts") == 2 and zone_count("offer") == 0)
check("choice resumes build2", phase.current().key == "build2")

local gold1 = entity.sum_stat("gold")
flow.play_card(pick, {})
check("tax levy grants 3 gold", entity.sum_stat("gold") == gold1 + 3)
check("played edict recycles into its deck", zone_count("edicts") == 3)
check("playing the edict ended the turn", phase.current().key == "challenge")

-- === castle: on_turn income on round wrap ===
local expected_income = 0
for e in entity.each("card") do
	local z = entity.get(e.zone_id)
	if z and z.zone_type == "grid" and (e.stats.hp or 1) > 0 then
		for _, a in ipairs(cards.def(e).on_turn or {}) do
			local n = a:match("^gain_stat:gold:(%d+)$")
			if n then expected_income = expected_income + tonumber(n) end
		end
	end
end

local challenge_card
for _, cid in ipairs(zones.find("hand").cards) do
	local k = entity.get(cid).def_key
	if k ~= "merchant" and k ~= "pass" then challenge_card = cid end
end
local gold_before = entity.sum_stat("gold")
flow.play_card(challenge_card, {})
check("round wrapped back to build1", phase.current().key == "build1")
check("on_turn gold income applied", entity.sum_stat("gold") == gold_before + expected_income)
check("round counter advanced", entity.sum_stat("round") == 2)
-- re-fetch by ID: undo replaced the entity tables, old references are stale
check("the new round readies exhausted cards", entity.get(throne.id).exhausted == nil)

-- === castle: refill_when_empty ===
local bd = zones.find("build_deck")
eval("draw_from:build_deck:graveyard:" .. #bd.cards)
check("emptied build deck refills from contents", #bd.cards == 15)

-- === castle: damage_random ===
local hp_before_dmg = board_hp()
eval("damage_random:building:hp:2")
check("a random building took 2 damage", board_hp() == hp_before_dmg - 2)

-- === castle: end conditions ===
eval("set_stat:morale:0")
check("castle defeat at 0 morale", phase.current().key == "defeat")
flow.pick(zones.find("offer").cards[1])
check("castle defeat returns to menu", declaration.G.title == "Ravel")

flow.init("castle.json")
eval("set_stat:morale:10")
check("castle victory at 10 morale", phase.current().key == "victory")
flow.pick(zones.find("offer").cards[1])
check("castle victory returns to menu", declaration.G.title == "Ravel")

-- === template editing ===
flow.init("castle.json")
local fdef = declaration.G.card_defs["farm"]
check("edit: plain string value",
	cards.edit("farm", "tooltip", "Test tooltip") and fdef.tooltip == "Test tooltip")
check("edit: json value",
	cards.edit("farm", "cost", '{"gold": 7}') and fdef.cost.gold == 7)

eval("set_stat:gold:3")
eval("fill:hand:farm:1")
check("edited cost gates play immediately",
	flow.play_card(find_card("farm", "hand").id, {}) == false)

check("edit: tags rebuild tags_set",
	cards.edit("farm", "tags", '["shiny"]') and fdef.tags_set.shiny and not fdef.tags_set.building)

local inst = find_card("farm", "hand")
cards.edit("farm", "card_stats", '{"hp": 9, "hp_max": 9}')
check("edit: card_stats re-stamps instances", inst.stats.hp == 9)

check("edit: null clears a field", cards.edit("farm", "cost", "null") and fdef.cost == nil)
check("edit: unknown card fails", cards.edit("bogus", "cost", "1") == false)

local dump = cards.dump("farm")
check("dump omits derived tags_set", not dump:find("tags_set"))
check("dump round-trips", json.decode(dump).card_stats.hp == 9)

check("reload succeeds", cards.reload())
local fdef2 = declaration.G.card_defs["farm"]
check("reload restores template from disk",
	fdef2.cost.gold == 1 and fdef2.tags_set.building and fdef2.tooltip ~= "Test tooltip")
check("reload re-stamps changed instances", inst.stats.hp == 3)

-- === content validation ===
for _, f in ipairs({ "menu.json", "demo.json", "castle.json", "kingdom.json", "tower.json" }) do
	local problems = validate.check(declaration.parse(f))
	check(f .. " validates clean", #problems == 0)
	for _, p in ipairs(problems) do print("  " .. f .. ": " .. p) end
end

local bad = declaration.parse("castle.json")
bad.phase_by_key.build1.next = { { ["then"] = "nope" } }
check("validator catches unknown routing target", #validate.check(bad) > 0)

-- === kingdom: creation drafting and routing ===
flow.init("kingdom.json", 5)
check("kingdom loads at the origin", phase.current().key == "origin")
check("all three origins offered plus decline", zone_count("hand") == 4)

flow.play_card(find_card("warlord", "hand").id, {})
check("origin grants its stats", entity.sum_stat("might") == 3 and entity.sum_stat("progress") == 3)
check("origin auto-slotted onto the board", find_card("warlord", "board").slot_id ~= nil)
check("routing entered the market", phase.current().key == "market_visit")
check("ends_round advanced the round", entity.sum_stat("round") == 2)
check("market hand: 4 cards plus 3 routers", zone_count("hand") == 7)

local function hand_router(key)
	for _, cid in ipairs(zones.find("hand").cards) do
		if entity.get(cid).def_key == key then return cid end
	end
end
check("router gated until something is played", flow.can_play(hand_router("to_barracks")) == false)

local first_play
for _, cid in ipairs(zones.find("hand").cards) do
	local d = cards.def(entity.get(cid))
	if not (d.tags_set and d.tags_set.token) and flow.can_play(cid) then first_play = cid; break end
end
flow.play_card(first_play, {})
check("router unlocks after one play", flow.can_play(hand_router("to_barracks")) == true)
flow.play_card(hand_router("to_barracks"), {})
check("router chose the barracks", phase.current().key == "barracks_visit")

-- === kingdom: counting synergies ===
eval("fill:hand:homestead:2")
flow.play_card(find_card("homestead", "hand").id, {})
flow.play_card(find_card("homestead", "hand").id, {})
-- count board farms independently (the random market play may have added one)
local farms = 0
for e in entity.each("card") do
	local z = entity.get(e.zone_id)
	local d = cards.def(e)
	if z and z.zone_type == "grid" and d.tags_set and d.tags_set.farm then
		farms = farms + 1
	end
end
local food0 = entity.sum_stat("food")
eval("gain_stat:food:count:farm")
check("count amounts resolve board tags",
	farms >= 2 and entity.sum_stat("food") == food0 + farms)

eval("fill:hand:rally_banner:1")
check("count-needs gate blocks below threshold",
	flow.can_play(find_card("rally_banner", "hand").id) == false)
eval("fill:hand:militia:1")
flow.play_card(find_card("militia", "hand").id, {})
check("count-needs gate opens at threshold",
	flow.can_play(find_card("rally_banner", "hand").id) == true)

-- === kingdom: trials via progress routing ===
eval("set_stat:progress:15")
eval("set_stat:plays:1")
flow.play_card(hand_router("to_market"), {})
check("progress routed into tier-2 trials", phase.current().key == "trial2")
check("trial hand: 2 trials plus rest, tokens swept", zone_count("hand") == 3)

local rest_id = hand_router("rest")
check("rest gated until both trials faced", flow.can_play(rest_id) == false)
-- snapshot first: playing mutates the hand array under iteration
local trial_cards = {}
for _, cid in ipairs(zones.find("hand").cards) do
	local d = cards.def(entity.get(cid))
	if not (d.tags_set and d.tags_set.token) then trial_cards[#trial_cards + 1] = cid end
end
for _, cid in ipairs(trial_cards) do flow.play_card(cid, {}) end
check("rest unlocks after both trials", flow.can_play(rest_id) == true)
local round0 = entity.sum_stat("round")
flow.play_card(rest_id, {})
check("rest loops back through the gate", phase.current().key == "trial2")
check("each trial pair is a round", entity.sum_stat("round") == round0 + 1)

-- === kingdom: the three endings ===
eval("set_stat:stability:0")
check("stability 0 collapses the realm", phase.current().key == "collapse")
flow.pick(zones.find("offer").cards[1])
check("collapse returns to menu", declaration.G.title == "Ravel")

flow.init("kingdom.json", 5)
eval("set_stat:progress:24")
check("progress 24 crowns you", phase.current().key == "coronation")

flow.init("kingdom.json", 5)
eval("set_stat:round:20")
check("round 20 fades to twilight", phase.current().key == "twilight_years")

-- === tower: classical CYOA — reveal pages, secret gates, irreversible ===
local function top_page()
	local r = zones.find("reveal")
	return r and r.cards[#r.cards] and entity.get(r.cards[#r.cards]).def_key
end

flow.init("tower.json", 3)
check("tower opens on a page overlay", phase.is_overlay() and phase.current().page == true)
check("the opening page is the shore", top_page() == "p_shore")

flow.pick(zones.find("reveal").cards[1])
check("the intro advanced once the page closed", phase.current().key == "story")
check("the shore offers three choices", zone_count("hand") == 3)
check("the read page vanished", zone_count("reveal") == 0)

flow.play_card(find_card("c_search", "hand").id, {})
check("searching revealed the beach", top_page() == "p_beach")
flow.undo()
check("undo closed the page again",
	not phase.is_overlay() and zone_count("hand") == 3 and zone_count("reveal") == 0)

flow.play_card(find_card("c_door", "hand").id, {})
check("the door without the key reveals the locked page", top_page() == "p_door_locked")
flow.pick(zones.find("reveal").cards[1])
check("the locked door keeps the hand for another try", zone_count("hand") == 3)

flow.play_card(find_card("c_search", "hand").id, {})
flow.pick(zones.find("reveal").cards[1])
check("the beach puts keepsakes on the board", zone_count("board") == 2)
check("keepsakes occupy board slots", find_card("rusty_key", "board").slot_id ~= nil)
check("the beach trims the choices", zone_count("hand") == 2)

local hp_lantern = entity.sum_stat("hp")
eval("gain_stat:hp:card:lantern")
check("card amounts resolve template presence", entity.sum_stat("hp") == hp_lantern + 1)

flow.play_card(find_card("c_door", "hand").id, {})
check("the door with the key reveals the hall", top_page() == "p_hall")
flow.pick(zones.find("reveal").cards[1])

local chest0 = zone_count("chest_deck")
flow.play_card(find_card("c_chest", "hand").id, {})
local secret = top_page()
check("the chest reveals one of its two secrets",
	secret == "p_chest_pearl" or secret == "p_chest_mimic")
check("the other secret stays face-down", zone_count("chest_deck") == chest0 - 1)
flow.pick(zones.find("reveal").cards[1])

flow.play_card(find_card("c_descend", "hand").id, {})
check("the lantern lights the stair", top_page() == "p_stair_lit")
flow.pick(zones.find("reveal").cards[1])
check("the bell room offers the finale", find_card("c_bell", "hand") ~= nil)

eval("fill:board:pearl:1")
check("undo is available before the bell", flow.can_undo() == true)
flow.play_card(find_card("c_bell", "hand").id, {})
check("the pearl earns the good ending", top_page() == "e_pearl")
check("irreversible cleared the undo stack", flow.can_undo() == false)
flow.pick(zones.find("reveal").cards[1])
check("the ending returns to the menu", declaration.G.title == "Ravel")

flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("lose_stat:hp:99")
check("death fires the collapse page", phase.is_overlay() and top_page() == "e_collapse")

-- === placement: tag homes and the single-board fallback ===
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("gain:pearl:1")
check("gain places a homed card on its board", find_card("pearl", "board") ~= nil)
check("gained card takes a slot", find_card("pearl", "board").slot_id ~= nil)
eval("gain:c_flee:1")
check("gain without a home goes to hand", find_card("c_flee", "hand") ~= nil)
actions.execute("move_to", { card_id = find_card("c_search", "hand").id, targets = {} })
flow.settle()
check("bare move_to falls back to the only board", find_card("c_search", "board") ~= nil)

-- === validator: conflicts, ambiguity, and friendly messages ===
local function has_problem(list, needle)
	for _, p in ipairs(list) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

local vg = declaration.parse("tower.json")
vg.zone_defs.battlefield = { key = "battlefield", type = "grid",
	grid = { 3, 1 }, pos = { 0, 0, 1, 1 }, tags_set = {} }
vg.card_defs.c_flee.on_play = { "move_to" }
local vp = validate.check(vg)
check("ambiguous placement across two boards is flagged",
	has_problem(vp, "card 'c_flee'") and has_problem(vp, "boards"))

vg.tag_defs.relic = { zone = "battlefield" }
vg.card_defs.pearl.tags = { "keepsake", "relic" }
vg.card_defs.pearl.tags_set = { keepsake = true, relic = true }
vp = validate.check(vg)
check("tags that disagree about a card's home are flagged", has_problem(vp, "disagree"))

local bad_file = "game/games/tmp_bad_test.json"
local bf = io.open(bad_file, "w")
bf:write([[{
  "title": "Broken",
  "templats": [],
  "stats": [ { "key": "gold" }, { "key": "gold" } ],
  "zones": [
    { "key": "board", "type": "gird", "pos": [0, 0, 1, 1], "grid": [3, 1] },
    { "key": "hand", "type": "hand", "pos": [0, 0, 1, 1] }
  ],
  "templates": [
    { "key": "sword", "onplay": ["destroy_self"], "cost": { "gold": "2" },
      "on_play": ["gain_stat:gld:1"] },
    { "key": "axe", "on_activate": "gain_stat:gold:1" },
    { "key": "dagger" },
    { "key": "dagger" }
  ],
  "phases": [ { "key": "start", "type": "playerinput" } ]
}]])
bf:close()
local bp = validate.check(declaration.parse("tmp_bad_test.json"))
os.remove(bad_file)
check("a typo'd section name is reported", has_problem(bp, "templats"))
check("duplicate keys are reported as conflicts", has_problem(bp, "share the key 'dagger'") and has_problem(bp, "share the key 'gold'"))
check("an unknown card field suggests the right one", has_problem(bp, "did you mean 'on_play'"))
check("an unknown stat suggests the right one", has_problem(bp, "did you mean 'gold'"))
check("a non-number cost value is explained", has_problem(bp, "'gold' should be a number"))
check("a lone string instead of an action list is explained", has_problem(bp, "list of actions"))
check("unknown zone and phase types suggest the right ones",
	has_problem(bp, "did you mean 'grid'") and has_problem(bp, "did you mean 'player_input'"))

-- === validator: every error message, once ===
-- One case per distinct message: mutate a freshly parsed (clean) tower
-- definition, run the validator, require the message. A case that stops
-- firing means the check silently died.
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
	{ "a comparison that isn't a number", "at_least should be a number",
		function(g) g.end_conditions[2] = { stat = "hp", at_least = "3", ["then"] = {} } end },
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
	{ "a push_phase to a missing phase", "push_phase to 'finale'",
		function(g) g.card_defs.c_flee.on_play = { "push_phase:finale" } end },
	{ "a target stat no card carries", "no card carries that stat",
		function(g) g.card_defs.c_flee.on_play = { "gain_target_stat:armor:1" } end },
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
	{ "a target of an unknown type", "type should be 'card' or 'slot'",
		function(g) g.card_defs.c_flee.target = { type = "zone", max = 1 } end },
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
	{ "on_pick outside an overlay", "only overlay phases use it",
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
}
for _, c in ipairs(CASES) do
	local g = declaration.parse("tower.json")
	c[3](g)
	check("validator flags " .. c[1], has_problem(validate.check(g), c[2]))
end

-- Parse-level messages need real files: entries with no key, duplicate
-- zone/phase keys, and a section written as an object instead of a list.
local bf2 = io.open("game/games/tmp_bad_keys.json", "w")
bf2:write([[{
  "templates": [ { "text": "No Key" } ],
  "zones": [
    { "type": "hand", "pos": [0, 0, 1, 1] },
    { "key": "dup", "type": "hand", "pos": [0, 0, 1, 1] },
    { "key": "dup", "type": "hand", "pos": [0, 0, 1, 1] }
  ],
  "stats": [ { "label": "No Key" } ],
  "phases": [
    { "type": "automatic" },
    { "key": "p", "type": "player_input" },
    { "key": "p", "type": "player_input" }
  ]
}]])
bf2:close()
local kp = validate.check(declaration.parse("tmp_bad_keys.json"))
os.remove("game/games/tmp_bad_keys.json")
check("entries without keys are reported for every kind",
	has_problem(kp, "a template has no") and has_problem(kp, "a zone has no")
	and has_problem(kp, "a stat has no") and has_problem(kp, "a phase has no"))
check("duplicate zone and phase keys are conflicts",
	has_problem(kp, "two zones share the key 'dup'")
	and has_problem(kp, "two phases share the key 'p'"))

local bf3 = io.open("game/games/tmp_bad_shape.json", "w")
bf3:write('{ "templates": { "key": "x" } }')
bf3:close()
local sp = validate.check(declaration.parse("tmp_bad_shape.json"))
os.remove("game/games/tmp_bad_shape.json")
check("a section that isn't a list is explained",
	has_problem(sp, "the 'templates' section should be a list"))

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
