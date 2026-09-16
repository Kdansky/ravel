-- Interactive CLI player for quick testing, no LÖVE needed. From the repo root:
--   luajit play.lua                 (starts at the menu)
--   luajit play.lua castle.json     (jumps straight into a game)
--   luajit play.lua castle.json 42  (with a fixed RNG seed)

require("headless")

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local targeting   = require("targeting")
local flow        = require("flow")
local log         = require("log")
local predicate   = require("predicate")
local label       = require("label")
local validate    = require("validate")
local rng         = require("rng")
-- A terminal has one face, so the marks a card sets its text in come off here.
local rich        = require("richtext")
-- Optional: the networking prototype is additive, and play.lua keeps working
-- with both files deleted.
local ok_net, net = pcall(require, "net")
local netlink     = ok_net and require("netlink") or nil
-- Optional for net's reason, and it requires net: an engine-played seat is this
-- machine acting, which is a thing the turn gate has to be told.
local ok_bot, bot = pcall(require, "opponent")
pcall(require, "save")   -- likewise: loading it is what makes the save ops work

local function wrap(text, width)
	local out, line = {}, ""
	for word in tostring(text):gmatch("%S+") do
		if #line > 0 and #line + #word + 1 > width then
			out[#out + 1] = line
			line = word
		else
			line = #line > 0 and (line .. " " .. word) or word
		end
	end
	if #line > 0 then out[#out + 1] = line end
	return out
end

local function card_line(e)
	local def  = cards.def(e)
	local bits = { label.fill(def.text or e.def_key, e) }
	if def.cost and next(def.cost) then bits[#bits + 1] = "(" .. cards.cost_text(def.cost) .. ")" end
	if e.stats.hp then bits[#bits + 1] = e.stats.hp .. "/" .. ((e.stat_max or {}).hp or e.stats.hp) .. "hp" end
	if def.tooltip then bits[#bits + 1] = "- " .. rich.strip(label.fill(def.tooltip, e)) end
	return table.concat(bits, " ")
end

-- What a hand *is*, now that a zone is its parts: a row of cards somebody holds,
-- which is any row that is not in play. It was one word — `zone_type == "hand"`
-- — until [28] split the word into seven, and the two reads here were left
-- behind and have quietly been false ever since.
local function a_hand(z)
	-- The system column is a row of cards nobody is holding: Save and Menu sit
	-- outside the game, which is what is_system_card is for.
	if z.cards[1] and flow.is_system_card(z.cards[1]) then return false end
	return z.layout == "row" and z.status ~= "board" and z.display ~= "offscreen" and not z.tags.hidden
end

-- The hand the player at this prompt is holding. Asked of zones rather than
-- walked for, because a per-seat hand has one instance per seat and walking
-- found the *first* — so a two-seat game showed north's cards whoever was to
-- play, and every command after a handover was aimed at somebody else's hand.
local function hand_zone()
	local cur = phase.current()
	local z   = zones.find(cur and cur.zone or "hand")
	if z and a_hand(z) then return z end
	if cur and cur.type == "overlay" then return z end
	for zz in entity.each("zone") do
		if a_hand(zz) and zz.seat == nil then return zz end
	end
	return z
end

-- Every place that can be used right now, in a stable order, so the number the
-- board printed is the number the command means. The CLI had no way to reach a
-- zone's abilities at all — which is how a deck is drawn from and a bank bought
-- out of, so half the corpus could not finish a turn from this prompt.
local function usable_places()
	local out = {}
	for z in entity.each("zone") do
		if z.display ~= "offscreen" then
			for _, u in ipairs(flow.usable_zone_abilities(z.id)) do
				out[#out + 1] = { zone = z.id, index = u.index, rule = u.rule,
					text = label.fill(z.label or z.key, z) .. (u.rule.text and (" — " .. u.rule.text) or "") }
			end
		end
	end
	return out
end

local function show()
	local G   = declaration.G
	local cur = phase.current()
	print("")
	print("== " .. G.title .. " ==  phase: " .. (cur and label.fill(cur.label or cur.key, cur) or "-"))

	local outcome = flow.outcome()
	if outcome then
		print("")
		print("========  " .. outcome:upper() .. "  ========")
		local summary = table.concat(flow.summary(), "   ")
		if summary ~= "" then print("  " .. summary) end
	end

	local stats = {}
	for _, key in ipairs(G.stat_defs_list) do
		local def = G.stat_defs[key]
		local v = predicate.total(def.subject or key)
		if declaration.stat_shown(key, v) then
			stats[#stats + 1] = label.fill(def.label or key, def) .. ": " .. v
		end
	end
	if #stats > 0 then print(table.concat(stats, "   ")) end

	for z in entity.each("zone") do
		if z.layout == "grid" and z.display ~= "offscreen" and not z.tags.hidden then
			print(label.fill(z.label or "Board", z) .. " ('a <slot>' activates, ~ = exhausted):")
			local row = {}
			for idx, slot_id in ipairs(z.slots) do
				local occ = entity.get(slot_id).occupant
				if occ then
					local c    = entity.get(occ)
					local hp   = c.stats.hp and (" " .. c.stats.hp .. "/" .. ((c.stat_max or {}).hp or "?")) or ""
					local mark = c.exhausted and "~" or ">"
					row[#row + 1] = string.format("%2d%s%-14s", idx, mark,
						(cards.def(c).text or c.def_key):sub(1, 9) .. hp)
				else
					row[#row + 1] = string.format("%2d %-14s", idx, ".")
				end
				if #row == z.grid[1] then print("  " .. table.concat(row, " ")); row = {} end
			end
		end
	end

	local counts = {}
	for z in entity.each("zone") do
		if z.layout == "stack" and z.display ~= "offscreen" and not z.tags.hidden then
			counts[#counts + 1] = label.fill(z.label or z.key, z) .. "(" .. #z.cards .. ")"
		end
	end
	if #counts > 0 then print(table.concat(counts, "  ")) end

	local places = usable_places()
	if #places > 0 then
		print("Places ('z <n>'):")
		for i, u in ipairs(places) do print("  [" .. i .. "] " .. u.text) end
	end

	-- A response window looks like nothing from the outside — the turn has not
	-- moved and the phase is the same one — so it is said out loud, above the
	-- hand, or the prompt is indistinguishable from the turn player's own.
	local top = flow.pending_event()
	if top then
		local names = {}
		for _, id in ipairs(top.re_subject) do
			local c = entity.get(id)
			if c then names[#names + 1] = cards.def(c).text or c.def_key end
		end
		print("")
		print("!! " .. table.concat(names, ", ") .. ": " .. top.re_verb
			.. " — " .. tostring(zones.active_seat()) .. " may answer")
		for i, u in ipairs(flow.usable_reactions()) do
			local c = entity.get(u.card)
			print("  [r " .. i .. "] " .. (cards.def(c).text or c.def_key)
				.. (u.reaction.text and (" - " .. u.reaction.text) or ""))
		end
		print("  [p] pass")
	end

	local h = hand_zone()
	if h and cur and cur.page then
		for i, cid in ipairs(h.cards) do
			local e   = entity.get(cid)
			local def = cards.def(e)
			print("")
			print("~~~ " .. label.fill(def.text or "", e) .. " ~~~")
			for _, l in ipairs(wrap(rich.strip(label.fill(def.story or def.tooltip or "", e)), 70)) do
				print("  " .. l)
			end
			print("  [" .. i .. "] continue")
		end
	elseif h then
		print(phase.is_overlay() and "Pick one:" or "Hand:")
		for i, cid in ipairs(h.cards) do
			print("  [" .. i .. "] " .. card_line(entity.get(cid)))
		end
	end
end

-- Ask for targets using the same eligibility rules as the GUI.
-- Returns a list of entity IDs, {} for a valid empty pick, or nil on cancel.
local function prompt_targets(card_e, spec)
	targeting.start(card_e.id, spec)
	local eligible = targeting.eligible
	local min, max = targeting.spec.min, targeting.spec.max
	if #eligible == 0 then
		targeting.clear()
		if min == 0 then return {} end
		print("No eligible targets.")
		return nil
	end
	print("Targets for " .. (cards.def(card_e).text or card_e.def_key) .. ":")
	for i, id in ipairs(eligible) do
		local t = entity.get(id)
		-- A spec may name a place rather than a thing: a square is a slot and an
		-- expedition is a zone, and neither has a card's definition to print.
		-- Printing one through card_line crashed the prompt outright.
		print("  [" .. i .. "] " .. (t.kind == "card" and card_line(t)
			or t.kind == "slot" and ("slot " .. t.slot_idx)
			or (t.label or t.key)))
	end
	io.write(string.format("choose %d-%d (space-separated, c=cancel)> ", min, max))
	local line = io.read("*l")
	targeting.clear()
	if not line or line == "c" then return nil end
	local ids = {}
	for w in line:gmatch("%S+") do
		local id = eligible[tonumber(w) or -1]
		if id then ids[#ids + 1] = id end
	end
	if #ids < min or #ids > max then
		print("Need " .. min .. "-" .. max .. " targets.")
		return nil
	end
	return ids
end

-- Which cards settle a cost that has more than one answer. The same shape as
-- picking targets, because it is the same gesture: what may be pointed at, one
-- pick at a time, until the price is covered.
--
-- Returns the plan to pay with, or false when the player backed out. nil is a
-- real answer and means nobody had a choice to make.
local function prompt_payment(ways, cid, intent, targs)
	if not targeting.begin_payment(ways, cid, intent, targs) then return ways[1] end
	local owed = targeting.spec.min
	while targeting.payment() == nil do
		local eligible = targeting.eligible
		if #eligible == 0 then
			targeting.clear()
			print("Nothing left to pay with.")
			return false
		end
		print("Pay " .. owed .. ", out of:")
		for i, id in ipairs(eligible) do
			local e = entity.get(id)
			print("  [" .. i .. "] " .. (e.kind == "card" and card_line(e) or (e.label or e.key)))
		end
		io.write(string.format("pay (%d left, c=cancel)> ", owed - #targeting.targets))
		local line = io.read("*l")
		if not line or line == "c" then
			targeting.clear()
			return false
		end
		local id = eligible[tonumber(line) or -1]
		if id then targeting.add(id) else print("No such option.") end
	end
	local plan = targeting.payment()
	targeting.clear()
	return plan
end

local function play_index(n)
	local h   = hand_zone()
	local cid = h and h.cards[n]
	if not cid then print("No card [" .. n .. "]."); return end
	-- Playing a card out of an overlay's zone *is* choosing it — flow works that
	-- out from the card's zone, so there is no separate verb for it. Unless the
	-- entry is a chooser's: those stand for an ability on some other card, and
	-- playing one as a card destroys the offer and runs nothing.
	if phase.is_overlay() then
		local choice = flow.menu_choice(cid)
		if choice then
			flow.close_offer()
			local spec = choice.rule.target
			local targets = {}
			if select(2, targeting.bounds(spec)) > 0 then
				targets = prompt_targets(entity.get(choice.source), spec)
				if not targets then return end
			end
			local intent = choice.reaction and "react" or "activate"
			local pay = prompt_payment(flow.intent_payments(intent, choice.source, targets, choice.index),
				choice.source, intent, targets)
			if pay == false then return end
			local ok = choice.reaction and flow.react(choice.source, choice.index, targets, pay)
				or (not choice.reaction and flow.activate(choice.source, targets, choice.index, pay))
			if not ok then print(choice.reaction and "Can't answer with that." or "Can't use that ability.") end
			return
		end
		flow.play_card(cid)
		return
	end

	local c   = entity.get(cid)
	local def = cards.def(c)
	if not flow.can_play(cid) then
		local why = not flow.can_afford(def.cost)
			and ("costs " .. cards.cost_text(def.cost))
			or ("needs " .. cards.cost_text(def.needs))
		print("Can't play " .. label.fill(def.text or c.def_key, c) .. " (" .. why .. ").")
		return
	end
	local targets = {}
	local spec = def.target
	if select(2, targeting.bounds(spec)) > 0 then
		targets = prompt_targets(c, spec)
		if not targets then return end
	end
	local pay = prompt_payment(flow.play_payments(cid, targets), cid, "play", targets)
	if pay == false then return end
	if not flow.play_card(cid, targets, pay) then print("Can't play that.") end
end

-- Which grid holds the piece meant by "a <slot>". Every per-seat grid has the
-- same slot numbers, so the first one found is not the one meant: it used to
-- stop at whichever grid came first and report "empty" for a square that was
-- occupied on the other seat's copy, which made a two-seat board unplayable
-- from here. Prefer a piece the player may actually act on, then any piece.
local function slot_owner_zone(idx)
	local fallback
	for z in entity.each("zone") do
		if z.layout == "grid" and z.slots[idx] and entity.get(z.slots[idx]).occupant then
			local occ = entity.get(z.slots[idx]).occupant
			if flow.can_activate(occ) then return z end
			fallback = fallback or z
		end
	end
	return fallback
end

local function activate_slot(idx)
	local only = slot_owner_zone(idx)
	for z in entity.each("zone") do
		if z == only then
			local occ = entity.get(z.slots[idx]).occupant
			if not occ then print("Slot " .. idx .. " is empty."); return end
			-- What this piece can do *right now*, which is its own abilities plus
			-- any its zone hands out. Reading the flat activate_target instead
			-- meant every card written as an "abilities" list — chess's whole
			-- board — offered no targets and refused to act.
			local usable = flow.usable_abilities(occ)
			if #usable == 0 then print("No ability, or can't afford it."); return end
			local pick = usable[1]
			if #usable > 1 then
				print("Which?")
				for i, u in ipairs(usable) do
					print("  [" .. i .. "] " .. (u.rule.text or u.rule.key))
				end
				local n = tonumber((io.read() or ""):match("%d+"))
				pick = n and usable[n]
				if not pick then print("Not one of those."); return end
			end
			local targets = {}
			if select(2, targeting.bounds(pick.rule.target)) > 0 then
				targets = prompt_targets(entity.get(occ), pick.rule.target)
				if not targets then return end
			end
			local pay = prompt_payment(flow.rule_payments(occ, pick.rule, targets),
				occ, "activate", targets)
			if pay == false then return end
			if not flow.activate(occ, targets, pick.index, pay) then
				print("Can't use that ability.")
			end
			return
		end
	end
	print("No such slot.")
end

-- Answer what is announced with reaction n, out of turn. Named separately from
-- playing a card because it is a different act: the card answers the top of the
-- stack rather than being played, and which of its reactions is meant is part of
-- the choice — the same reason activating names an ability.
local function react_index(n)
	local pick = flow.usable_reactions()[n]
	if not pick then print("No reaction [" .. n .. "]."); return end
	local targets = {}
	if select(2, targeting.bounds(pick.reaction.target)) > 0 then
		targets = prompt_targets(entity.get(pick.card), pick.reaction.target)
		if not targets then return end
	end
	local pay = prompt_payment(flow.rule_payments(pick.card, pick.reaction, targets),
		pick.card, "react", targets)
	if pay == false then return end
	if not flow.react(pick.card, pick.index, targets, pay) then print("Can't answer with that.") end
end

local function inspect(n)
	local h   = hand_zone()
	local cid = h and h.cards[n]
	if not cid then print("No card [" .. n .. "]."); return end
	local c   = entity.get(cid)
	local def = cards.def(c)
	print(label.fill(def.text or c.def_key, c))
	if def.cost and next(def.cost) then print("  cost: " .. cards.cost_text(def.cost)) end
	if def.tooltip then print("  " .. rich.strip(label.fill(def.tooltip, c))) end
	if def.story then
		for _, l in ipairs(wrap(rich.strip(label.fill(def.story, c)), 70)) do print("  " .. l) end
	end
	for k, v in pairs(c.stats) do print("  " .. k .. ": " .. v) end
	if def.tags then print("  tags: " .. table.concat(def.tags, ", ")) end
end

local HELP = [[
  <n>          play (or pick) card n
  a <slot>     activate the board card in that slot
  z <n>        use place n — a deck to draw from, a bank to buy from
  r <n>        answer what is announced with reaction n
  p            pass on answering it
  i <n>        inspect card n
  u            undo
  e <action>   run a raw action string, e.g. "e stat_gain:gold:5"
  edit <card> <field> <json>   edit a template live, e.g. edit farm cost {"gold":2}
  dump <card>  print a template as JSON (paste back into the game file)
  reload       re-read templates from the game file, keep playing
  load <file>  load a game json
  n ...        networked play (n help)
  bot <seat>   let the engine play that seat ("bot off" hands them all back)
  q            quit]]

local NET_HELP = [[
  n                     connection status
  n host <file> [seed]  start a game and print the invite to send your opponent
  n join <invite>       start the same game from an invite string
  n seat <name|off>     play only this seat (n seat with no name lists them)
  n send                print the state to paste to your opponent
  n recv <string>       apply a state they pasted to you
  n folder <dir> <me> <them>   trade through files in a shared directory
  n poll                check the folder now (also happens after every move)
  n resync              ask them to send the whole game (use when out of sync)
  n off                 disconnect]]

-- One dispatcher, because networking is one experiment and should be one thing
-- to delete. Everything it can do is also reachable from the module directly.
local function net_command(rest)
	if not net then print("networking is not installed"); return end
	local sub, args = rest:match("^(%S*)%s*(.*)$")

	if sub == "" then
		print("net: " .. net.status() .. "   seat: " .. tostring(net.seat or "any")
			.. "   state: " .. net.state_hash() .. "   " .. net.marker())
		if net.desync then print("  OUT OF SYNC: " .. net.desync .. "  ('n resync' to fix)") end
		if net.linked() and not net.last_heard then
			print("  nothing heard from the other side yet.")
		end
	elseif sub == "help" then
		print(NET_HELP)
	elseif sub == "host" then
		local file, seed = args:match("^(%S+)%s*(%-?%d*)$")
		seed = tonumber(seed) or os.time() % 100000
		local ok, err = net.begin(file or "lost_cities.json", seed)
		if ok then
			net.take_role("host")
			print("send this to your opponent:")
			print("  " .. net.invite(seed))
		else
			print(err)
		end
	elseif sub == "join" then
		local ok, err = net.accept(args)
		print(ok and "joined." or tostring(err))
	elseif sub == "seat" then
		if args == "" then
			print("seats: " .. table.concat(net.seats(), ", "))
		elseif args == "off" then
			net.claim_seat(nil)
			print("playing any seat")
		else
			net.claim_seat(args)
			print("playing as " .. args)
		end
	elseif sub == "send" then
		print(net.export())
	elseif sub == "recv" then
		local ok, err = net.import(args)
		print(ok and "applied." or ("rejected: " .. tostring(err)))
	elseif sub == "folder" then
		local dir, me, them = args:match("^(%S+)%s+(%S+)%s+(%S+)$")
		if not dir then print("usage: n folder <dir> <me> <them>"); return end
		net.link(netlink.folder(dir, me, them))
		print(net.status())
	elseif sub == "resync" then
		local ok, err = net.request_resync()
		print(ok and "asked them for the whole game." or ("cannot: " .. tostring(err)))
	elseif sub == "poll" then
		print(net.poll() and "applied their move." or "nothing new.")
	elseif sub == "off" then
		net.unlink()
	else
		print("? (n help)")
	end
end

-- Which seats the engine plays. Naming the other seat of a two-player game is
-- the whole of single player; "off" hands them all back.
local function bot_command(rest)
	if not ok_bot then print("this build has no opponent module"); return end
	local name = rest:match("^%S+")
	if not name then
		for _, k in ipairs(declaration.G.seat_list or {}) do
			print("  " .. k .. (bot.seats[k] and "   (engine)" or ""))
		end
	elseif name == "off" then
		bot.leave()
		print("every seat is yours again")
	elseif not (declaration.G.seat_set or {})[name] then
		print("no seat called '" .. name .. "' in this game")
	else
		bot.take(name)
		print("the engine plays " .. name)
	end
end

-- Echo log lines written since the last command: the play-by-play record.
local log_seen = 0
local function echo_log()
	local new = log.count() - log_seen
	if new > 0 then
		for _, line in ipairs(log.tail(new)) do print("  | " .. line) end
	end
	log_seen = log.count()
end

math.randomseed(os.time())   -- presentation only; the game uses rng.lua
rng.seed(os.time())

actions.on_effect = function(name) print("  * " .. name .. " *") end
flow.default_seed = tonumber(arg[2] or "")
flow.init(arg[1] or "menu.json")
echo_log()
show()

while true do
	io.write("> ")
	local line = io.read("*l")
	if not line or line == "q" then break end
	local cmd, rest = line:match("^(%S+)%s*(.*)$")

	if not cmd then
		-- empty line: just redraw
	elseif tonumber(cmd) then
		play_index(tonumber(cmd))
	elseif cmd == "a" and tonumber(rest) then
		activate_slot(tonumber(rest))
	elseif cmd == "z" and tonumber(rest) then
		local u = usable_places()[tonumber(rest)]
		if u then
			local pay = prompt_payment(flow.rule_payments(u.zone, u.rule), u.zone, "activate_zone", {})
			if pay ~= false then flow.activate_zone(u.zone, u.index, pay) end
		else
			print("No place [" .. rest .. "].")
		end
	elseif cmd == "r" and tonumber(rest) then
		react_index(tonumber(rest))
	elseif cmd == "p" then
		if not flow.pass_react() then print("Nothing is waiting to be answered.") end
	elseif cmd == "i" and tonumber(rest) then
		inspect(tonumber(rest))
	elseif cmd == "u" then
		if not flow.undo() then print("Nothing to undo.") end
	elseif cmd == "e" then
		local ok, err = pcall(actions.execute, rest, {})
		if ok then flow.settle() else print(err) end
	elseif cmd == "edit" then
		local key, field, raw = rest:match("^(%S+)%s+(%S+)%s+(.*)$")
		if key then
			local ok, err = cards.edit(key, field, raw)
			if not ok then print(err) end
		else
			print('usage: edit <card> <field> <json>, e.g. edit farm cost {"gold":2}')
		end
	elseif cmd == "dump" then
		local s, err = cards.dump(rest)
		print(s or err)
	elseif cmd == "reload" then
		local ok, err = cards.reload()
		if not ok then
			print(err)
		else
			for _, p in ipairs(validate.check(declaration.G)) do print("  ! " .. p) end
		end
	elseif cmd == "load" then
		local ok, err = pcall(flow.init, rest)
		if not ok then print(err); flow.init("menu.json") end
	elseif cmd == "bot" then
		bot_command(rest)
	elseif cmd == "n" then
		net_command(rest)
	elseif cmd == "h" then
		print(HELP)
	else
		print("? (h for help)")
	end
	-- The engine takes its seats before the board is drawn again, so the prompt
	-- comes back when it is the player's turn and not once per bot move. Capped
	-- rather than looped to exhaustion: two engine seats would otherwise play
	-- the whole game at the prompt, and a stuck one would never give it back.
	if ok_bot then
		for _ = 1, 200 do
			if not bot.act() then break end
		end
	end
	-- A linked transport is checked after every command, so an opponent's move
	-- lands without anyone having to ask for it.
	if net and net.linked() and net.poll() then print("  | (their move arrived)") end
	if net and net.desync then
		print("  !! OUT OF SYNC: " .. net.desync)
		print("  !! 'n resync' asks them for the whole game.")
	end
	echo_log()
	show()
end
