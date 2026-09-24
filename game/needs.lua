-- **A `needs` is written by what failing it does.** One block of conditions per
-- ability, keyed by kind:
--
--   req     — not offered, not playable; a phase running it skips it
--   where   — asked of each candidate, which is @target; one failing is not offered
--   fizzle  — the ability is used, and its action does nothing
--   event   — a reaction's question about what it answers, read from the event's side
--   <name>  — a gate: only the lines written "<name>? action" are behind it, and
--             "!<name>? action" is the other branch, reading the same answer
--
-- Three structures used to say this — `needs`, a `where` on whatever offered the
-- candidates, and an if nested in the action list — and they were one vocabulary
-- asked at different moments. The kind says the moment, so the file has one
-- place to look.
--
-- The engine keeps its flat names. This runs once, on the cleaned copy of the
-- file, and writes each kind where the engine already reads it: `req` stays in
-- `needs` as a list, `where` goes to the target (or the move rule, or the reveal),
-- `event` to a reaction's own `where`, and a gated line becomes a table naming its
-- gates, which `actions.run` answers. Everything downstream is unchanged.

local shape = require("shape")

local M = {}

-- The kinds the engine owns. Any other key is a gate, and has to be used.
local KINDS = { req = true, where = true, fizzle = true, event = true }

-- What each block may say, and where its `where` lands: on its target, on itself, or nowhere.
local ACTING = { req = true, fizzle = true, gates = true, where = "target" }
local BLOCKS = {
	ability = ACTING,
	play = ACTING,
	reaction = { req = true, fizzle = true, gates = true, where = "target", event = true },
	move = { req = true, where = "self" },
	chosen = { where = "self" },
	plain = { req = true },
	verb = { gates = true, refuses = "a verb takes gates only: it runs inside the caller's list, which has already started" },
}

local MOMENT_BLOCK = { play = "play", chosen = "chosen" }

local function listed(v)
	return type(v) == "string" and { v } or v
end

local function conds_ok(v)
	if type(v) == "string" then return true end
	if type(v) ~= "table" or (next(v) ~= nil and v[1] == nil) then return false end
	for _, s in ipairs(v) do if type(s) ~= "string" then return false end end
	return true
end

-- A gated line is a table: the action it stands for, and every gate it is behind.
local function gate_lines(b, gates, fizzle, what, pp)
	local used = {}
	for i, line in ipairs(type(b.action) == "table" and b.action or {}) do
		if type(line) == "string" then
			local no, name, rest = line:match("^(!?)([%w_]+)%?%s+(.+)$")
			local gs = {}
			if fizzle then gs[1] = { name = "fizzle", when = fizzle, holds = true } end
			if name and gates[name] then
				used[name] = true
				gs[#gs + 1] = { name = name, when = gates[name], holds = no == "" }
			elseif name then
				pp[#pp + 1] = ('%s: "%s" is behind "%s", which its needs does not name'):format(what, line, name)
				rest = nil
			end
			if #gs > 0 then b.action[i] = { line = rest or line, gates = gs } end
		end
	end
	for name in pairs(gates) do
		if not used[name] then
			pp[#pp + 1] = ('%s: needs names "%s", and no line is behind it — a gated line is written "%s? <action>". '
				.. 'The kinds a needs takes are req, where, fizzle and event'):format(what, name, name)
		end
	end
end

local function unfold(b, what, takes, pp)
	if type(b) ~= "table" then return end
	-- The old spellings, refused by name: each would otherwise keep working beside the new one.
	if b.where ~= nil then
		pp[#pp + 1] = ('%s: "where" goes inside "needs" now, as { "where": [...] }'):format(what)
		b.where = nil
	end
	if type(b.target) == "table" and b.target.where ~= nil then
		pp[#pp + 1] = ('%s: the target\'s "where" goes in the ability\'s "needs" now, as { "where": [...] }'):format(what)
		b.target.where = nil
	end
	local n = b.needs
	b.needs = nil
	if n == nil then
		if takes.gates then gate_lines(b, {}, nil, what, pp) end
		return
	end
	if type(n) ~= "table" or n[1] ~= nil then
		pp[#pp + 1] = ('%s: needs says what failing it does, like { "req": ["gold >= 3"] } — "req" for a '
			.. 'condition that must hold before it is offered'):format(what)
		return
	end
	local gates = {}
	for k, v in pairs(n) do
		if not conds_ok(v) then
			pp[#pp + 1] = ('%s: needs "%s" should be a condition or a list of them'):format(what, tostring(k))
		elseif KINDS[k] and not takes[k] then
			pp[#pp + 1] = ('%s: needs takes no "%s" here%s'):format(what, k, takes.refuses and " — " .. takes.refuses or "")
		elseif not KINDS[k] then
			if takes.gates then
				gates[k] = listed(v)
			else
				pp[#pp + 1] = ('%s: needs takes no "%s" here — only %s'):format(what, tostring(k),
					takes.where and "req and where" or takes.req and "req" or "where")
			end
		end
	end
	if takes.req and n.req ~= nil and conds_ok(n.req) then
		b.needs = n.req
		-- Nothing is chosen when req is asked, so @target in it can only be a candidate.
		if takes.where == "target" then
			for _, s in ipairs(listed(n.req)) do
				if s:find("@target%f[^%w_]") then
					pp[#pp + 1] = ('%s: req "%s" asks about @target, and nothing is chosen when req is asked — '
						.. 'a question about each candidate goes in "where"'):format(what, s)
				end
			end
		end
	end
	if takes.where and n.where ~= nil and conds_ok(n.where) then
		if takes.where == "self" then
			b.where = n.where
		elseif type(b.target) == "table" then
			b.target.where = n.where
		else
			pp[#pp + 1] = ('%s: needs says "where", which asks about each candidate, and nothing here has a target'):format(what)
		end
	end
	if takes.event and n.event ~= nil and conds_ok(n.event) then b.where = n.event end
	local fizzle = takes.fizzle and n.fizzle ~= nil and conds_ok(n.fizzle) and listed(n.fizzle) or nil
	if fizzle and type(b.phases) == "table" and #b.phases == 0 then
		pp[#pp + 1] = ('%s: needs says "fizzle" on an ability no player uses, where failing it is skipping it — '
			.. 'write "req"'):format(what)
	end
	if takes.gates then gate_lines(b, gates, fizzle, what, pp) end
end

-- Move rules sit on a target, or straight on the ability or reaction that moves.
local function moves_of(b, what, pp)
	for _, holder in ipairs({ b, type(b) == "table" and b.target or nil }) do
		if type(holder) == "table" and type(holder.moves) == "table" then
			for i, rule in ipairs(holder.moves) do unfold(rule, what .. " move rule " .. i, BLOCKS.move, pp) end
		end
	end
end

local function each_block(def, what, pp)
	if type(def) ~= "table" then return end
	for moment in pairs(shape.MOMENTS) do
		local b = def[moment]
		if type(b) == "table" then
			local at = what .. " " .. moment
			moves_of(b, at, pp)
			unfold(b, at, BLOCKS[MOMENT_BLOCK[moment] or "plain"], pp)
		end
	end
	for i, ab in ipairs(type(def.abilities) == "table" and def.abilities or {}) do
		local at = what .. " ability '" .. tostring(type(ab) == "table" and ab.key or i) .. "'"
		moves_of(ab, at, pp)
		unfold(ab, at, BLOCKS.ability, pp)
	end
	for i, r in ipairs(type(def.reactions) == "table" and def.reactions or {}) do
		local at = what .. " reaction '" .. tostring(type(r) == "table" and r.key or i) .. "'"
		moves_of(r, at, pp)
		unfold(r, at, BLOCKS.reaction, pp)
	end
	for i, ad in ipairs(type(def.adjusts) == "table" and def.adjusts or {}) do
		unfold(ad, what .. " adjusts " .. i, BLOCKS.plain, pp)
	end
end

-- In place, on the copy shape.clean made. Problems go to `pp`, as shape's do.
function M.unfold(file, pp)
	for _, c in ipairs(type(file.cards) == "table" and file.cards or {}) do
		each_block(c, "card '" .. tostring(type(c) == "table" and c.key) .. "'", pp)
	end
	for _, z in ipairs(type(file.zones) == "table" and file.zones or {}) do
		each_block(z, "zone '" .. tostring(type(z) == "table" and z.key) .. "'", pp)
	end
	for name, t in pairs(type(file.tags) == "table" and file.tags or {}) do
		each_block(t, "tag '" .. tostring(name) .. "'", pp)
	end
	for name, ct in pairs(type(file.computed_tags) == "table" and file.computed_tags or {}) do
		unfold(ct, "computed tag '" .. tostring(name) .. "'", BLOCKS.plain, pp)
	end
	for _, vd in ipairs(type(file.verbs) == "table" and file.verbs or {}) do
		if type(vd) == "table" then unfold(vd, "verb '" .. tostring(vd.key) .. "'", BLOCKS.verb, pp) end
	end
	return file
end

return M
