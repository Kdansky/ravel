-- Line-based TCP test/debug API on localhost, enabled by the RAVEL_DEBUG env
-- variable (native runs only — love.js has no sockets, so start() is a no-op
-- there). One command per connection, JSON reply. Drive it with netcat:
--
--   RAVEL_DEBUG=1 love game
--   echo "stats"          | nc 127.0.0.1 5757
--   echo "play farm slot:8" | nc 127.0.0.1 5757
--   echo "eval gain_stat:gold:5" | nc 127.0.0.1 5757

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local flow        = require("flow")
local log         = require("log")
local json        = require("json")

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
			if z.zone_type == "grid" then return z.slots[tonumber(slot_idx)] end
		end
		return nil
	end
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if e.def_key == token and z and z.zone_type ~= "deck" then return e.id end
	end
end

-- Compact game summary: current phase, stat totals, cards per zone.
local function summary()
	local cur   = phase.current()
	local stats = {}
	for _, key in ipairs(declaration.G.stat_defs_list) do
		stats[key] = entity.sum_stat(key)
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

COMMANDS["activate"] = function(args)
	local cid = resolve(args[1])
	local targets = {}
	for i = 2, #args do targets[#targets + 1] = resolve(args[i]) end
	local ok = cid and flow.activate(cid, targets) or false
	local s = summary(); s.ok = ok; return s
end

COMMANDS["pick"] = function(args)
	local cid = resolve(args[1])
	local ok  = cid and flow.pick(cid) or false
	local s = summary(); s.ok = ok; return s
end

COMMANDS["click"] = function(args)
	local zid = zones.find_id(args[1])
	local ok  = zid and flow.zone_click(zid) or false
	local s = summary(); s.ok = ok; return s
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
	local ok, result = pcall(fn, args, rest)
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
