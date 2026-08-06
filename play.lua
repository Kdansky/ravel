-- Interactive CLI player for quick testing, no LÖVE needed. From the repo root:
--   luajit play.lua                 (starts at the menu)
--   luajit play.lua castle.json     (jumps straight into a game)
--   luajit play.lua castle.json 42  (with a fixed RNG seed)

require("headless")
math.randomseed(os.time())

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local targeting   = require("targeting")
local flow        = require("flow")
local log         = require("log")
local validate    = require("validate")

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
	if e.stats.hp then bits[#bits + 1] = e.stats.hp .. "/" .. (e.stats.hp_max or e.stats.hp) .. "hp" end
	if def.tooltip then bits[#bits + 1] = "- " .. def.tooltip end
	return table.concat(bits, " ")
end

-- The zone the numbered choices refer to: the overlay's offer zone when one
-- is open, otherwise the first visible hand.
local function hand_zone()
	local cur = phase.current()
	if cur and cur.type == "overlay" then return zones.find(cur.zone or "hand") end
	for z in entity.each("zone") do
		if z.zone_type == "hand" and not z.tags.hidden then return z end
	end
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
			stats[#stats + 1] = (def.label or key) .. ": " .. entity.sum_stat(key)
		end
	end
	if #stats > 0 then print(table.concat(stats, "   ")) end

	for z in entity.each("zone") do
		if z.zone_type == "grid" then
			print((z.label or "Board") .. " ('a <slot>' activates, ~ = exhausted):")
			local row = {}
			for idx, slot_id in ipairs(z.slots) do
				local occ = entity.get(slot_id).occupant
				if occ then
					local c    = entity.get(occ)
					local hp   = c.stats.hp and (" " .. c.stats.hp .. "/" .. (c.stats.hp_max or "?")) or ""
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
	if phase.is_overlay() then flow.pick(cid); return end

	local c   = entity.get(cid)
	local def = cards.def(c)
	if not flow.can_play(cid) then
		local why = not cards.can_afford(def.cost)
			and ("costs " .. cards.cost_text(def.cost))
			or ("needs " .. cards.cost_text(def.needs))
		print("Can't play " .. (def.text or c.def_key) .. " (" .. why .. ").")
		return
	end
	local targets = {}
	local spec = def.target
	if spec and (spec.count or spec.max or 0) > 0 then
		targets = prompt_targets(c, spec)
		if not targets then return end
	end
	if not flow.play_card(cid, targets) then print("Can't play that.") end
end

local function activate_slot(idx)
	for z in entity.each("zone") do
		if z.zone_type == "grid" and z.slots[idx] then
			local occ = entity.get(z.slots[idx]).occupant
			if not occ then print("Slot " .. idx .. " is empty."); return end
			local targets = {}
			local spec    = cards.def(entity.get(occ)).activate_target
			if spec and (spec.count or spec.max or 0) > 0 and flow.can_activate(occ) then
				targets = prompt_targets(entity.get(occ), spec)
				if not targets then return end
			end
			if not flow.activate(occ, targets) then print("No ability, or can't afford it.") end
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
  e <action>   run a raw action string, e.g. "e gain_stat:gold:5"
  edit <card> <field> <json>   edit a template live, e.g. edit farm cost {"gold":2}
  dump <card>  print a template as JSON (paste back into the game file)
  reload       re-read templates from the game file, keep playing
  load <file>  load a game json
  q            quit]]

-- Echo log lines written since the last command: the play-by-play record.
local log_seen = 0
local function echo_log()
	local new = log.count() - log_seen
	if new > 0 then
		for _, line in ipairs(log.tail(new)) do print("  | " .. line) end
	end
	log_seen = log.count()
end

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
	elseif cmd == "h" then
		print(HELP)
	else
		print("? (h for help)")
	end
	echo_log()
	show()
end
