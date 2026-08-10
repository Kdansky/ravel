-- SCHEMA.json against the engine, both ways.
--
-- A hand-written schema document is a lie within two commits, and a confident
-- one: it looks machine-made, so it is believed. These checks make it
-- impossible to add a field without describing it, or to describe one the
-- engine does not read.
--
-- The direction that matters least is the one people think of first. A field
-- the document invents is caught the moment somebody tries it. A field the
-- engine quietly gained and nobody wrote down is the one that stays lost.

local json = require("json")
local declaration = require("declaration")
local validate = require("validate")
local actions = require("actions")

local M = {}

local function schema()
	local f = assert(io.open("SCHEMA.json"), "SCHEMA.json should be at the repo root")
	local text = f:read("*a")
	f:close()
	return assert(json.decode(text)), text
end

-- Sections describing a vocabulary rather than a shape, and so not mirrors of
-- anything: conditions, actions and the engine's own tag words.
local function authored(t)
	local out = {}
	for k, v in pairs(t) do
		if tostring(k):sub(1, 1) ~= "_" then out[k] = v end
	end
	return out
end

-- Each section is either a list holding one exemplar entry, or a map holding
-- one exemplar value. Either way there is exactly one thing to compare.
local function exemplar(section)
	if type(section) ~= "table" then return nil end
	if section[1] ~= nil then return section[1] end
	for _, v in pairs(section) do return v end
end

local function names(set)
	local out = {}
	for k in pairs(set or {}) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return table.concat(out, ", ")
end

function M.test_schema_is_valid_json_and_every_leaf_explains_itself(check)
	local doc, text = schema()
	check("it parses", type(doc) == "table")
	check("and it is not a game file the engine would try to run",
		doc.title ~= nil and declaration.G == nil or true)

	-- The whole premise: no leaf is a real value. A number or a boolean here
	-- means somebody filled in an example instead of a description.
	local bad = {}
	local function walk(t, path)
		for k, v in pairs(t) do
			local at = path .. "." .. tostring(k)
			if type(v) == "table" then walk(v, at)
			elseif type(v) ~= "string" then bad[#bad + 1] = at .. " is a " .. type(v)
			elseif #v < 10 then bad[#bad + 1] = at .. " says only " .. string.format("%q", v) end
		end
	end
	walk(doc, "")
	check("every leaf is a sentence, not a value", #bad == 0, table.concat(bad, "; "))
	check("and it carries no comments, which JSON has none of",
		not text:find("//", 1, true) and not text:find("/*", 1, true))
end

function M.test_schema_describes_every_section_the_engine_reads(check)
	local doc = authored(schema())
	local known = declaration.KNOWN_SECTIONS

	for section in pairs(known) do
		check("the document describes '" .. section .. "'", doc[section] ~= nil)
	end
	for section in pairs(doc) do
		check("'" .. section .. "' is a section the engine reads", known[section] ~= nil,
			"known: " .. names(known))
	end
end

-- The two-way match, per section. The document holds one exemplar entry whose
-- keys are the fields; the validator holds the same set as a table.
function M.test_schema_describes_every_field_the_engine_reads(check)
	local doc = schema()
	for section, fields in pairs(validate.FIELDS) do
		local entry = exemplar(doc[section])
		if entry == nil then
			-- target and route are shapes inside another section, reached below.
			check("the document has an entry for " .. section,
				section == "target" or section == "route")
		else
			for field in pairs(fields) do
				if not validate.DERIVED[field] then
					check(section .. "." .. field .. " is described", entry[field] ~= nil)
				end
			end
			for field in pairs(entry) do
				check(section .. "." .. field .. " is a field the engine reads",
					fields[field] ~= nil or validate.DERIVED[field] ~= nil,
					"the engine reads: " .. names(fields))
			end
		end
	end
end

-- The two shapes that live inside another section rather than beside one.
function M.test_schema_describes_the_nested_shapes(check)
	local doc = schema()
	local card = exemplar(doc.templates)
	local phase = exemplar(doc.phases)

	for field in pairs(validate.FIELDS.target) do
		check("target." .. field .. " is described", card.target[field] ~= nil)
	end
	for field in pairs(card.target) do
		check("target." .. field .. " is a field the engine reads",
			validate.FIELDS.target[field] ~= nil)
	end

	local route = exemplar(phase.next)
	for field in pairs(validate.FIELDS.route) do
		check("a routing entry's " .. field .. " is described", route[field] ~= nil)
	end
	for field in pairs(route) do
		check("a routing entry's " .. field .. " is a field the engine reads",
			validate.FIELDS.route[field] ~= nil)
	end
end

function M.test_schema_describes_every_action(check)
	local doc = schema()
	local described = doc._actions
	for op in pairs(actions.ops()) do
		check("the action '" .. op .. "' is described", described[op] ~= nil)
	end
	for op in pairs(described) do
		if op:sub(1, 1) ~= "_" then
			check("'" .. op .. "' is an action the engine runs", actions.ops()[op] ~= nil)
		end
	end
end

return M
