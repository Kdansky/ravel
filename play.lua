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
local validate    = require("validate")
local rng         = require("rng")
-- Optional: the networking prototype is additive, and play.lua keeps working
-- with both files deleted.
local ok_net, net = pcall(require, "net")
local netlink     = ok_net and require("netlink") or nil

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
	local bits = { def.text or e.def_key }
	if def.cost and next(def.cost) then bits[#bits + 1] = "(" .. cards.cost_text(def.cost) .. ")" end
	if e.stats.hp then bits[#bits + 1] = e.stats.hp .. "/" .. ((e.stat_max or {}).hp or e.stats.hp) .. "hp" end
	if def.tooltip then bits[#bits + 1] = "- " .. def.tooltip end
	return table.concat(bits, " ")
end

-- The hand the player at this prompt is holding. Asked of zones rather than
-- walked for, because a per-seat hand has one instance per seat and walking
-- found the *first* — so a two-seat game showed north's cards whoever was to
-- play, and every command after a handover was aimed at somebody else's hand.
local function hand_zone()
	local cur = phase.current()
	local z   = zones.find(cur and cur.zone or "hand")
	if z and z.zone_type == "hand" and not z.tags.hidden then return z end
	if cur and cur.type == "overlay" then return z end
	for zz in entity.each("zone") do
		if zz.zone_type == "hand" and not zz.tags.hidden and zz.seat == nil then return zz end
	end
	return z
end

local function show()
	local G   = declaration.G
	local cur = phase.current()
	print("")
	print("== " .. G.title .. " ==  phase: " .. (cur and (cur.label or cur.key) or "-"))

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
		if not (def and def.hidden) then
			stats[#stats + 1] = (def.label or key) .. ": " .. predicate.total(def.subject or key)
		end
	end
	if #stats > 0 then print(table.concat(stats, "   ")) end

	for z in entity.each("zone") do
		if z.zone_type == "grid" and not z.tags.hidden then
			print((z.label or "Board") .. " ('a <slot>' activates, ~ = exhausted):")
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
		if (z.zone_type == "deck" or z.zone_type == "pile") and not z.tags.hidden then
			counts[#counts + 1] = (z.label or z.key) .. "(" .. #z.cards .. ")"
		end
	end
	if #counts > 0 then print(table.concat(counts, "  ")) end

	local h = hand_zone()
	if h and cur and cur.page then
		for i, cid in ipairs(h.cards) do
			local def = cards.def(entity.get(cid))
			print("")
			print("~~~ " .. (def.text or "") .. " ~~~")
			for _, l in ipairs(wrap(def.story or def.tooltip or "", 70)) do
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
		print("  [" .. i .. "] " .. (t.kind == "slot" and ("slot " .. t.slot_idx) or card_line(t)))
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
			local targets = {}
			if select(2, targeting.bounds(choice.ability.target)) > 0 then
				targets = prompt_targets(entity.get(choice.source), choice.ability.target)
				if not targets then return end
			end
			if not flow.activate(choice.source, targets, choice.index) then
				print("Can't use that ability.")
			end
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
		print("Can't play " .. (def.text or c.def_key) .. " (" .. why .. ").")
		return
	end
	local targets = {}
	local spec = def.target
	if select(2, targeting.bounds(spec)) > 0 then
		targets = prompt_targets(c, spec)
		if not targets then return end
	end
	if not flow.play_card(cid, targets) then print("Can't play that.") end
end

-- Which grid holds the piece meant by "a <slot>". Every per-seat grid has the
-- same slot numbers, so the first one found is not the one meant: it used to
-- stop at whichever grid came first and report "empty" for a square that was
-- occupied on the other seat's copy, which made a two-seat board unplayable
-- from here. Prefer a piece the player may actually act on, then any piece.
local function slot_owner_zone(idx)
	local fallback
	for z in entity.each("zone") do
		if z.zone_type == "grid" and z.slots[idx] and entity.get(z.slots[idx]).occupant then
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
					print("  [" .. i .. "] " .. (u.ability.text or u.ability.key))
				end
				local n = tonumber((io.read() or ""):match("%d+"))
				pick = n and usable[n]
				if not pick then print("Not one of those."); return end
			end
			local targets = {}
			if select(2, targeting.bounds(pick.ability.target)) > 0 then
				targets = prompt_targets(entity.get(occ), pick.ability.target)
				if not targets then return end
			end
			if not flow.activate(occ, targets, pick.index) then
				print("Can't use that ability.")
			end
			return
		end
	end
	print("No such slot.")
end

local function inspect(n)
	local h   = hand_zone()
	local cid = h and h.cards[n]
	if not cid then print("No card [" .. n .. "]."); return end
	local c   = entity.get(cid)
	local def = cards.def(c)
	print(def.text or c.def_key)
	if def.cost and next(def.cost) then print("  cost: " .. cards.cost_text(def.cost)) end
	if def.tooltip then print("  " .. def.tooltip) end
	if def.story then
		for _, l in ipairs(wrap(def.story, 70)) do print("  " .. l) end
	end
	for k, v in pairs(c.stats) do print("  " .. k .. ": " .. v) end
	if def.tags then print("  tags: " .. table.concat(def.tags, ", ")) end
end

local HELP = [[
  <n>          play (or pick) card n
  a <slot>     activate the board card in that slot
  i <n>        inspect card n
  u            undo
  e <action>   run a raw action string, e.g. "e stat_gain:gold:5"
  edit <card> <field> <json>   edit a template live, e.g. edit farm cost {"gold":2}
  dump <card>  print a template as JSON (paste back into the game file)
  reload       re-read templates from the game file, keep playing
  load <file>  load a game json
  n ...        networked play (n help)
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
	elseif cmd == "n" then
		net_command(rest)
	elseif cmd == "h" then
		print(HELP)
	else
		print("? (h for help)")
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
