-- A card standing on another card.
--
-- The link existed before this and survived nothing: `parent_id` had one write
-- and no reader, so a host that moved left its riders behind still claiming it,
-- a destroyed host took them with it, and an attached card on a grid quietly
-- took a free cell of its own — two pieces drawn for one.
--
-- What it is for: a shared space records that it is taken and never by whom.
-- A figure standing on the space says both, because a figure is a card and
-- cards have owners.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local geometry = require("geometry")

local M = {}

local GAME = [==[{
  "title": "Attachment",
  "players": [{ "card": "south" }, { "card": "north" }],
  "stats": [
    { "key": "side", "min": 0, "max": 9, "on": ["player"], "start": 0, "tags": ["hidden"] },
    { "key": "guard", "min": 0, "max": 1, "on": ["site"], "start": 0, "tags": ["hidden"] }
  ],
  "zones": [
    { "key": "island", "layout": "grid", "use": "abilities", "grid": [3, 1], "pos": [0.05, 0.05, 0.80, 0.30] },
    { "key": "south_row", "layout": "row", "pos": [0.05, 0.35, 0.80, 0.55] },
    { "key": "north_row", "layout": "row", "pos": [0.05, 0.60, 0.80, 0.78] },
    { "key": "tray", "layout": "row", "pos": [0.05, 0.82, 0.80, 0.95] },
    { "key": "guard_deck", "layout": "stack", "display": "offscreen", "contents": ["guardian", "guardian"] },
    { "key": "box", "layout": "stack", "status": "supply", "display": "offscreen", "contents": ["guardian:4"] }
  ],
  "phases": [
    { "key": "turn", "type": "player_input", "next": [{ "then": "turn" }] }
  ],
  "cards": [
    { "key": "south", "text": "South", "card_stats": { "side": 1 } },
    { "key": "north", "text": "North", "card_stats": { "side": 2 } },
    { "key": "site", "text": "A site", "tags": ["site"], "card_stats": { "guard": 1 } },
    { "key": "guardian", "text": "A guardian", "tags": ["guardian"] },
    { "key": "meeple", "text": "A figure", "tags": ["meeple"],
      "abilities": [
        { "key": "stand", "text": "Stand here", "phases": ["turn"],
          "target": { "count": 1, "tags": ["site"], "zones": ["island"] },
          "action": ["attach_to_target"] }
      ] }
  ],
  "setup": {
    "place": [
      { "card": "site", "zone": "island", "at": ["a1", "b1"] },
      { "card": "meeple", "owner": "south", "zone": "south_row" },
      { "card": "meeple", "owner": "north", "zone": "north_row" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_attachment.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_attachment.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- The site standing on a square, by its algebraic name.
local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("island"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

local function meeple(zone_key)
	local zid = zones.find_id(zone_key)
	for e in entity.each("card") do
		if e.def_key == "meeple" and e.zone_id == zid then return e end
	end
end

function M.test_attachment_a_figure_stands_on_a_site(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		local home = fig.zone_id

		check("it attached", zones.attach(fig.id, site.id))
		check("into the host's zone", entity.get(fig.id).zone_id == site.zone_id)
		check("with no square of its own", entity.get(fig.id).slot_id == nil)
		check("and the site did not lose its own", entity.get(site.id).slot_id ~= nil)
		check("the link is written both ways",
			entity.get(fig.id).parent_id == site.id and entity.get(site.id).attached[1] == fig.id)
		check("and it remembers the row it left", entity.get(fig.id).origin_zone_id == home)
	end)
end

-- The whole point: the space says both that it is taken and by whom.
function M.test_attachment_a_scope_reaches_across_the_link(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		zones.attach(fig.id, site.id)
		local ctx = { card_id = site.id }

		check("the site counts what stands on it",
			predicate.total("count:meeple@attached_to.self", ctx) == 1,
			tostring(predicate.total("count:meeple@attached_to.self", ctx)))
		check("and whose it is", predicate.total("sum:side@owner_of.attached_to.self", ctx) == 1,
			tostring(predicate.total("sum:side@owner_of.attached_to.self", ctx)))
		check("the figure reads the tile it stands on",
			predicate.total("guard@host_of.self", { card_id = fig.id }) == 1)
		check("an empty site counts nobody",
			predicate.total("count:meeple@attached_to.self", { card_id = at("b1").id }) == 0)
	end)
end

-- The owner word sits beside what it is about, as it does on `owner_of`: before
-- the prefix it narrows the riders, not the hosts.
function M.test_attachment_the_owner_word_narrows_the_riders(check)
	with_game(function(name)
		flow.init(name, 3)
		local site = at("a1")
		zones.attach(meeple("south_row").id, site.id)
		zones.attach(meeple("north_row").id, site.id)
		local ctx = { card_id = site.id }

		check("both are standing there", predicate.total("count:meeple@attached_to.self", ctx) == 2,
			tostring(predicate.total("count:meeple@attached_to.self", ctx)))
		check("one of them is mine", predicate.total("count:meeple@mine.attached_to.self", ctx) == 1,
			tostring(predicate.total("count:meeple@mine.attached_to.self", ctx)))
		check("and one is not", predicate.total("count:meeple@enemy.attached_to.self", ctx) == 1)
	end)
end

function M.test_attachment_a_rider_that_moves_gets_off(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		zones.attach(fig.id, site.id)

		zones.move_card(fig.id, zones.find_id("tray"))
		check("it is in the tray", entity.get(fig.id).zone_id == zones.find_id("tray"))
		check("and no longer standing on anything", entity.get(fig.id).parent_id == nil)
		check("the site knows it left", #entity.get(site.id).attached == 0)
	end)
end

-- Without this the rider is orphaned in the zone the host walked out of, still
-- claiming a host that is somewhere else.
function M.test_attachment_a_host_that_moves_takes_its_riders(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		zones.attach(fig.id, site.id)

		zones.move_card(site.id, zones.find_id("tray"))
		check("the host moved", entity.get(site.id).zone_id == zones.find_id("tray"))
		check("and the rider came along", entity.get(fig.id).zone_id == zones.find_id("tray"))
		check("still standing on it", entity.get(fig.id).parent_id == site.id)
		check("counted once, not twice", #entity.get(site.id).attached == 1)
	end)
end

-- A site tile swept off the board must not take the figure standing on it.
function M.test_attachment_a_destroyed_host_sends_its_riders_home(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		local home = fig.zone_id
		zones.attach(fig.id, site.id)

		zones.destroy_card(site.id)
		check("the figure survived", entity.get(fig.id) ~= nil and entity.get(fig.id).zone_id ~= nil)
		check("and went back to the row it came from", entity.get(fig.id).zone_id == home)
		check("standing on nothing", entity.get(fig.id).parent_id == nil)
	end)
end

-- Sending every figure home wanted no word of its own: `move` already takes a
-- scope and already understands `origin`, and `origin` restores the square too.
function M.test_attachment_every_figure_goes_home_at_once(check)
	with_game(function(name)
		flow.init(name, 3)
		local south, north = meeple("south_row"), meeple("north_row")
		local south_home, north_home = south.zone_id, north.zone_id
		zones.attach(south.id, at("a1").id)
		zones.attach(north.id, at("b1").id)

		actions.execute("move:each.meeple:origin", {})
		check("south's figure is back in its own row", entity.get(south.id).zone_id == south_home)
		check("north's in its own", entity.get(north.id).zone_id == north_home)
		check("and neither is standing on anything",
			entity.get(south.id).parent_id == nil and entity.get(north.id).parent_id == nil)
		check("the sites are clear", #entity.get(at("a1").id).attached == 0)
	end)
end

-- It took a free cell of the same grid before, so the board showed two pieces
-- for one and the tile it was meant to be on had nothing on it.
function M.test_attachment_a_rider_claims_no_square(check)
	with_game(function(name)
		flow.init(name, 3)
		local island = zones.find("island")
		local taken = 0
		for _, sid in ipairs(island.slots) do
			if entity.get(sid).occupant then taken = taken + 1 end
		end
		check("two sites, two squares", taken == 2, tostring(taken))

		zones.attach(meeple("south_row").id, at("a1").id)
		local after = 0
		for _, sid in ipairs(island.slots) do
			if entity.get(sid).occupant then after = after + 1 end
		end
		check("and the figure took none of the third", after == 2, tostring(after))
	end)
end

-- The case that matters on a board: a site a figure can be sent to is by
-- definition a cell that is already taken, so a full grid must still let a
-- rider on. It refused before, and the whole feature was unreachable on the one
-- board it was built for.
function M.test_attachment_a_full_board_still_has_room_for_a_rider(check)
	with_game(function(name)
		flow.init(name, 3)
		local island = zones.find("island")
		local third = zones.add(island, "site")
		zones.place_in_slot(third.id, island.slots[3])
		check("every cell is taken", zones.has_room(island) == false)

		local fig = meeple("south_row")
		check("the figure still gets on", zones.attach(fig.id, at("a1").id))
		check("standing on the site", entity.get(fig.id).parent_id == at("a1").id)
		check("and an ordinary arrival is still refused",
			zones.move_card(meeple("north_row").id, island.id) == false)
	end)
end

-- The word the guardian deck was waiting on, and it turned out not to be a word:
-- a destination is already a scope expression, so one that names a card names a
-- host. Every op that takes a destination understands it at once.
function M.test_attachment_a_destination_may_be_a_card(check)
	with_game(function(name)
		flow.init(name, 3)
		local site = at("a1")
		local ctx = { targets = { site.id } }

		actions.execute("draw_from:guard_deck:target:1", ctx)
		check("the deal landed on the site", #entity.get(site.id).attached == 1,
			tostring(#entity.get(site.id).attached))
		check("and it is the card that was dealt",
			entity.get(entity.get(site.id).attached[1]).def_key == "guardian")

		actions.execute("create:target:guardian:1", ctx)
		check("a fill lands there too", #entity.get(site.id).attached == 2,
			tostring(#entity.get(site.id).attached))

		actions.execute("take:box:target:1", ctx)
		check("and so does a take out of a supply", #entity.get(site.id).attached == 3,
			tostring(#entity.get(site.id).attached))

		actions.execute("move:south_row:target", ctx)
		check("a move sends a whole scope to stand on it",
			predicate.total("count:meeple@attached_to.self", { card_id = site.id }) == 1,
			tostring(predicate.total("count:meeple@attached_to.self", { card_id = site.id })))
		check("the site still holds its own square", entity.get(site.id).slot_id ~= nil)
	end)
end

-- A cycle is not a rule any game means, and it is a carry that never ends.
function M.test_attachment_nothing_stands_on_what_stands_on_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		zones.attach(fig.id, site.id)
		check("the host may not climb onto its own rider", zones.attach(site.id, fig.id) == false)
		check("nor a card onto itself", zones.attach(fig.id, fig.id) == false)
		check("and the first link is untouched", entity.get(fig.id).parent_id == site.id)
	end)
end

-- The op is the file's way in, and it goes through the same door.
function M.test_attachment_the_action_word_stands_a_figure_up(check)
	with_game(function(name)
		flow.init(name, 3)
		local fig, site = meeple("south_row"), at("a1")
		actions.execute("attach_to_target", { card_id = fig.id, targets = { site.id } })
		check("it is standing on the site", entity.get(fig.id).parent_id == site.id)
		check("in the site's zone, with no square", entity.get(fig.id).zone_id == site.zone_id
			and entity.get(fig.id).slot_id == nil)
	end)
end

return M
