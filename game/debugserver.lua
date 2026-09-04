-- Line-based TCP test/debug API on localhost, enabled by the RAVEL_DEBUG env
-- variable (native runs only — love.js has no sockets, so start() is a no-op
-- there). One command per connection, JSON reply. Drive it with netcat:
--
--   RAVEL_DEBUG=1 love game
--   echo "stats"          | nc 127.0.0.1 5757
--   echo "play farm slot:8" | nc 127.0.0.1 5757
--   echo "eval stat_gain:gold:5" | nc 127.0.0.1 5757

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local flow        = require("flow")
local log         = require("log")
local json        = require("json")
local predicate   = require("predicate")
local stage       = require("stage")

local M = {}

local server = nil

function M.start(port)
	local ok, socket = pcall(require, "socket")
	if not ok then
		print("debugserver: luasocket unavailable, not starting")
		return
	end
	server = socket.bind("127.0.0.1", port or 5757)
	if server then
		server:settimeout(0)
		print("debugserver: listening on 127.0.0.1:" .. (port or 5757))
	end
end

-- Resolve a command token to an entity ID: numeric ID, "slot:N" (grid slot),
-- or a card def_key (first match outside decks).
local function resolve(token)
	local id = tonumber(token)
	if id then return id end
	local slot_idx = token:match("^slot:(%d+)$")
	if slot_idx then
		for z in entity.each("zone") do
			if z.layout == "grid" then return z.slots[tonumber(slot_idx)] end
		end
		return nil
	end
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if e.def_key == token and z and z.use ~= "none" then return e.id end
	end
end

-- Compact game summary: current phase, stat totals, cards per zone.
local function summary()
	local cur   = phase.current()
	local stats = {}
	for _, key in ipairs(declaration.G.stat_defs_list) do
		local def  = declaration.G.stat_defs[key]
		stats[key] = predicate.total(def and def.subject or key)
	end
	local zone_counts = {}
	for z in entity.each("zone") do zone_counts[z.key] = #z.cards end
	return { title = declaration.G.title, phase = cur and cur.key,
		stats = stats, zones = zone_counts }
end

local COMMANDS = {}

COMMANDS["state"] = function()
	local s = summary()
	s.entities = entity.snapshot()
	return s
end

COMMANDS["stats"] = summary

COMMANDS["load"] = function(args)
	-- load <file> [seed]
	flow.init(args[1], tonumber(args[2]))
	return summary()
end

COMMANDS["log"] = function(args)
	return { log = log.tail(tonumber(args[1]) or 20) }
end

COMMANDS["play"] = function(args)
	local cid = resolve(args[1])
	local targets = {}
	for i = 2, #args do targets[#targets + 1] = resolve(args[i]) end
	local ok = cid and flow.play_card(cid, targets) or false
	local s = summary(); s.ok = ok; return s
end

-- activate <card> [targets...]  — and with several abilities, "activate <card>
-- #<n> [targets...]" says which. Without the index flow refuses to guess, which
-- is right and left every card written as an "abilities" list unusable from here.
COMMANDS["activate"] = function(args)
	local cid = resolve(args[1])
	local targets, index = {}, nil
	for i = 2, #args do
		local n = tostring(args[i]):match("^#(%d+)$")
		if n then index = tonumber(n) else targets[#targets + 1] = resolve(args[i]) end
	end
	local ok = cid and flow.activate(cid, targets, index) or false
	local s = summary(); s.ok = ok; return s
end

COMMANDS["pick"] = function(args)
	local cid = resolve(args[1])
	local ok  = cid and flow.play_card(cid, {}) or false
	local s = summary(); s.ok = ok; return s
end

-- click <zone> [#<n>]  — a place offering two things is picked between the same
-- way a card's abilities are, and for the same reason: there is no player here
-- to open a chooser for.
COMMANDS["click"] = function(args)
	local zid = zones.find_id(args[1])
	local n   = args[2] and tostring(args[2]):match("^#(%d+)$")
	local ok  = zid and flow.activate_zone(zid, n and tonumber(n)) or false
	local s = summary(); s.ok = ok; return s
end

-- react <card> [#<n>] [targets...]  — answer what is announced, out of turn.
-- Named apart from "play" for the same reason the CLI names it apart: the card
-- answers the top of the stack rather than being played, and which of its
-- reactions is meant is part of the choice.
COMMANDS["react"] = function(args)
	local cid = resolve(args[1])
	local targets, index = {}, nil
	for i = 2, #args do
		local n = tostring(args[i]):match("^#(%d+)$")
		if n then index = tonumber(n) else targets[#targets + 1] = resolve(args[i]) end
	end
	local sole = cid and flow.sole_reaction(cid)
	local ok = cid and flow.react(cid, index or (sole and sole.index) or 1, targets) or false
	local s = summary(); s.ok = ok; return s
end

COMMANDS["pass"] = function()
	local ok = flow.pass_react()
	local s = summary(); s.ok = ok; return s
end

-- What is waiting to be answered and who may answer it with what — the one
-- thing a summary cannot show, because a window moves neither turn nor phase.
COMMANDS["pending"] = function()
	local top = flow.pending_event()
	if not top then return { pending = false } end
	local subject = {}
	for _, id in ipairs(top.re_subject) do
		local c = entity.get(id)
		if c then subject[#subject + 1] = c.def_key end
	end
	local answers = {}
	for _, u in ipairs(flow.usable_reactions()) do
		answers[#answers + 1] = { card = entity.get(u.card).def_key, index = u.index }
	end
	return { pending = true, verb = top.re_verb, subject = subject,
		seat = zones.active_seat(), answers = answers }
end

COMMANDS["eval"] = function(args)
	actions.execute(table.concat(args, " "), {})
	flow.settle()
	return summary()
end

COMMANDS["undo"] = function()
	local ok = flow.undo()
	local s = summary(); s.ok = ok; return s
end

COMMANDS["edit"] = function(args, rest)
	local key, field, raw = rest:match("^(%S+)%s+(%S+)%s+(.*)$")
	if not key then return { error = "usage: edit <card> <field> <json>" } end
	local ok, err = cards.edit(key, field, raw)
	if not ok then return { error = err } end
	return { ok = true, def = cards.template(key) }
end

COMMANDS["dump"] = function(args)
	local def, err = cards.template(args[1] or "")
	return def or { error = err }
end

COMMANDS["reload"] = function()
	local ok, err = cards.reload()
	if not ok then return { error = err } end
	local s = summary(); s.ok = true; return s
end

-- A picture of the window, so a change to the drawing can be checked from a
-- terminal. LÖVE hands the pixels over a frame later, so this answers where the
-- file will be rather than waiting for it: the save directory, beside the saves.
COMMANDS["screenshot"] = function(args)
	local name = (args[1] or "shot") .. ".png"
	love.graphics.captureScreenshot(function(img) img:encode("png", name) end)
	return { file = love.filesystem.getSaveDirectory() .. "/" .. name }
end

COMMANDS["help"] = function()
	local names = {}
	for k in pairs(COMMANDS) do names[#names + 1] = k end
	table.sort(names)
	return { commands = names }
end

local function handle(line)
	local cmd, rest = line:match("^%s*(%S+)%s*(.*)$")
	local fn = cmd and COMMANDS[cmd]
	if not fn then return json.encode({ error = "unknown command: " .. tostring(cmd) }) end
	local args = {}
	for w in rest:gmatch("%S+") do args[#args + 1] = w end
	-- A command is an input like any other, so what it sets off is one run and
	-- plays like one. Without this the only way to watch a sequence would be to
	-- click, and the screenshot command below would always catch the aftermath.
	stage.arm()
	local ok, result = pcall(fn, args, rest)
	stage.seal()
	if not ok then return json.encode({ error = tostring(result) }) end
	return json.encode(result)
end

function M.update()
	if not server then return end
	while true do
		local client = server:accept()
		if not client then return end
		client:settimeout(0.2)
		local line = client:receive("*l")
		if line then client:send(handle(line) .. "\n") end
		client:close()
	end
end

return M
