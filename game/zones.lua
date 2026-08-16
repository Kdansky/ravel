local entity      = require("entity")
local cards       = require("cards")
local declaration = require("declaration")
local geometry    = require("geometry")
local tags        = require("tags")
local rng         = require("rng")
local log         = require("log")

local M = {}
local key_map  = {}  -- zone key → entity ID (shared zones)
local seat_map = {}  -- zone key → seat name → entity ID (per_seat zones)

function M.reset()
	key_map, seat_map = {}, {}
end

function M.contains(p, x, y)
	return x >= p.x and x <= p.x + p.w and y >= p.y and y <= p.y + p.h
end

-- Reading the board as somebody else. "Mine" is answered from the turn, which is
-- right for a rule and wrong for a readout: the HUD row says *Your score* on a
-- machine whose player is not the one to move, and shows the opponent's number.
-- Every consumer of "mine" — subjects, zone lookups, ownership — asks
-- active_seat, so one override answers for all of them at once.
--
-- **Reads only.** An action run inside this would act as the wrong seat, which
-- is why it is scoped and restored even when the body raises: the alternative is
-- an engine that quietly stays somebody else for the rest of the session.
local as_if = nil

function M.as_seat(seat, fn)
	local prev = as_if
	as_if = seat
	local ok, err = pcall(fn)
	as_if = prev
	if not ok then error(err, 0) end
end

-- The seat an unqualified zone key means. Derived from the system card's
-- "turn" rather than cached, so undo restores it along with everything else.
-- One-seat games — every shipped game — never look past the first line.
function M.active_seat()
	if as_if then return as_if end
	local seats = declaration.G.seat_list or {}
	if #seats < 2 then return seats[1] end
	for e in entity.each("card") do
		if e.def_key == "system" and e.zone_id then
			-- turn 0 is "nobody has taken one yet", which reads as the first
			-- seat: a game that never hands over still has somebody playing.
			return seats[e.stats.turn or 0] or seats[1]
		end
	end
	return seats[1]
end

-- The seat in front of *this* screen, which is a different question from whose
-- turn it is. They are the same in hot-seat — one screen, one person, and both
-- swap at the handover — and they come apart the moment two machines are
-- playing: your opponent's turn is still your screen.
--
-- Written from outside rather than read out of net, because no engine module
-- requires net (net.lua's first line) and that is worth keeping for one string.
-- Client-side display state: it must never reach the snapshot, since two
-- machines watching one game hold different values on purpose.
M.viewer = nil

-- The claim, once it has been checked against the game actually loaded, and nil
-- when nobody at this screen is playing. A viewer naming no seat in *this* game
-- is no viewer at all: claiming a seat and then loading a game that never heard
-- of it would otherwise hide every hand on the table, including the one you are
-- holding.
--
-- Nil is an answer rather than a gap, which is why the fallback to the turn sits
-- at the two call sites below instead of in here. Hiding a hand has to name
-- somebody and hot-seat means the seat to play; an ending screen has nobody to
-- congratulate and says so (flow.outcome).
function M.watching()
	local seats = declaration.G.seat_set
	if M.viewer and seats and seats[M.viewer] then return M.viewer end
end

local function build(def, seat, pos)
	local e = {
		kind      = "zone",
		key       = def.key,
		seat      = seat,   -- nil for a shared zone: its cards have no owner
		label     = def.label,
		zone_type = def.type or "pile",
		tags      = def.tags_set or {},
		grid      = def.grid,
		-- How this zone looks, merged from the styles its tags name: the shape it
		-- keeps, how a card sits in a cell, what the cells are painted with.
		style     = def.style or {},
		asset     = def.asset,     -- a picture behind the whole zone
		cards     = {},
		slots     = {},   -- slot_idx → slot entity ID (grid zones only)
		contents  = def.contents,
		pos       = pos,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		tooltip   = def.tooltip,   -- what it says when hovered
		-- The zone's own ability, flattened out of its "activate" block by the
		-- same table a card's is. A deck that can be drawn from says so here.
		on_activate      = def.on_activate,
		activate_phases  = def.activate_phases,
		activate_cost    = def.activate_cost,
		applies   = def.applies,   -- tags this zone grants to whatever sits in it
	}
	entity.register(e)
	if seat then
		seat_map[e.key] = seat_map[e.key] or {}
		seat_map[e.key][seat] = e.id
	else
		key_map[e.key] = e.id
	end

	if e.zone_type == "grid" and e.grid then
		local cols, rows = e.grid[1], e.grid[2]
		for idx = 1, cols * rows do
			local slot = {
				kind     = "slot",
				zone_id  = e.id,
				slot_idx = idx,
				occupant = nil,
				-- Where on the board this is, as ordinary stats, so a condition
				-- reads it with the vocabulary it already has ("row@target")
				-- rather than the engine growing a second way to ask for a
				-- number. Same row-major arithmetic as cell_rect below.
				-- Counted from the bottom-left, like every other coordinate an
				-- author writes: "row" is a rank, and a1 is row 1. The index
				-- above still runs top-down, because that is how the cells are
				-- laid out on a screen; the two meet here and nowhere else.
				stats    = { col = (idx - 1) % cols + 1,
					row = rows - math.floor((idx - 1) / cols) },
				place    = { x = 0, y = 0, w = 0, h = 0 },
			}
			entity.register(slot)
			e.slots[idx] = slot.id
		end
	end

	M.refill(e)
	return e
end

-- A per_seat zone exists once per seat, each instance with its own rect from
-- the def's list of positions. Everything downstream sees ordinary zones that
-- happen to carry a seat, so only the lookup below has to know the difference.
function M.create(def)
	if not (def.tags_set and def.tags_set.per_seat) then return build(def, nil, def.pos) end
	-- One rect per seat: "pos" is a list of rects here, not the single rect a
	-- shared zone declares. Two seats sharing one rect would draw on top of
	-- each other, so the author names both — the validator insists.
	local many = type(def.pos) == "table" and type(def.pos[1]) == "table"
	local first
	for i, seat in ipairs(declaration.G.seat_list or {}) do
		local e = build(def, seat, many and def.pos[i] or def.pos)
		first = first or e
	end
	return first
end

-- Create a card into a zone and give it a slot, or return nil when a grid is
-- full. move_card guards arrivals, but creation bypasses it entirely, so the
-- capacity bound lives here rather than being restated at every creation site.
function M.add(z, def_key)
	if not z or not M.has_room(z) then return nil end
	local e = cards.create(def_key, z.id)
	M.auto_slot(e.id)
	return e
end

-- Create the zone's declared contents ("card_key" or "card_key:count" strings),
-- shuffled if the zone is tagged. Also runs when a refill_when_empty zone empties.
function M.refill(z)
	for _, entry in ipairs(z.contents or {}) do
		local key, n = entry:match("^([^:]+):?(%d*)$")
		for _ = 1, tonumber(n) or 1 do
			if not M.add(z, key) then break end
		end
	end
	if z.tags.shuffle then M.shuffle(z.id) end
end

-- A zone key, optionally qualified by whose it is: "arena" is the active
-- seat's, "enemy.arena" the other's. A destination has to resolve to exactly
-- one zone — a set can be wide, a place to put a card cannot — so "anyone"
-- and "enemy" pick the first matching seat rather than all of them.
function M.find_id(key, owner)
	local seats = seat_map[key]
	if not seats then return key_map[key] end
	local active = M.active_seat()
	if owner == nil or owner == "mine" then return seats[active] end
	for _, seat in ipairs(declaration.G.seat_list or {}) do
		if owner == "anyone" or seat ~= active then
			if seats[seat] then return seats[seat] end
		end
	end
end

function M.find(key, owner)
	local id = M.find_id(key, owner)
	return id and entity.get(id)
end

-- Every instance of a zone key, in seat order. Shared zones have exactly one.
function M.all_with_key(key)
	local out = {}
	if key_map[key] then out[1] = entity.get(key_map[key]) end
	for _, seat in ipairs(declaration.G.seat_list or {}) do
		local id = seat_map[key] and seat_map[key][seat]
		if id then out[#out + 1] = entity.get(id) end
	end
	return out
end

-- Whether the player at the keyboard may look at this card.
--
-- One rule, deliberately: a card in a *hand* belongs to whoever that hand
-- belongs to, and nobody else sees its face. Decks already draw a back, piles
-- are face-up because that is what a discard is, and a board is public.
--
-- A hand with no seat is nobody's in particular — a one-player game, or a
-- shared tray — and stays visible, so every game written before seats existed
-- is unchanged.
--
-- **This hides, it does not protect.** The whole state is in memory and travels
-- over the wire, so a determined player can still read an opponent's hand; what
-- this stops is the accidental version — two people at one screen where the
-- game shows both hands at once, and a networked client drawing the opponent's
-- hand while they think. Trust is a referee's job and the engine has never
-- claimed to be one (DESIGN.md, *Trust*).
function M.visible(c)
	if not c then return false end
	local z = c.zone_id and entity.get(c.zone_id)
	if not z or z.zone_type ~= "hand" or not z.seat then return true end
	return z.seat == (M.watching() or M.active_seat())
end

-- The order a browser should show a zone's cards in. **A face-down stack's
-- order is its secret, not its contents** — you may know what is in the market
-- deck, and must not know what comes next — so it is sorted by name and tells
-- you nothing. Anything whose order is already on the table is shown as it is.
--
-- Lives here rather than in the renderer because it is a rule about what a zone
-- reveals, which is the same question `visible` answers, and because a renderer
-- is a bad place to keep a promise.
function M.browse_order(z)
	local out = {}
	for i, cid in ipairs(z and z.cards or {}) do out[i] = cid end
	if not (z and z.zone_type == "deck" and not z.tags.face_up) then return out end
	local function name(id)
		local e = entity.get(id)
		local d = declaration.G.card_defs[e.def_key]
		return ((d and d.text) or e.def_key), e.def_key
	end
	table.sort(out, function(a, b)
		local na, ka = name(a)
		local nb, kb = name(b)
		if na ~= nb then return na < nb end
		return ka < kb
	end)
	return out
end

-- The same rule asked of the container: may the seat watching look inside this
-- zone at all? A hand belonging to somebody else is the case that matters. Its
-- cards already draw as backs, and every path that *reads* a card — the
-- browser, the card detail, the ctrl+hover inspector — has to ask this too, or
-- one of them quietly undoes the other.
function M.peekable(z)
	if not z or z.tags.no_peek then return false end
	if z.zone_type ~= "hand" or not z.seat then return true end
	return z.seat == (M.watching() or M.active_seat())
end

function M.move_top(from_id, to_id)
	local from = entity.get(from_id)
	if not from or #from.cards == 0 then return false end
	return M.move_card(from.cards[#from.cards], to_id)
end

-- True when a card can take a place in the zone: grids are bounded by their
-- free slots, every other zone type is unbounded.
function M.has_room(z)
	if not z or z.zone_type ~= "grid" then return true end
	for _, sid in ipairs(z.slots) do
		local s = entity.get(sid)
		if s and not s.occupant then return true end
	end
	return false
end

-- What a zone does when something lands in it — the other half of `receive`,
-- whose `needs` already says what it will take. Set by actions.lua at load,
-- because actions requires this file and the dependency may not run both ways.
M.run_actions = nil

-- Bounded, and the bound is the point: a receive action may move the card on,
-- and that lands it in another zone which may do the same. Eight is far past
-- anything a game needs and far short of a stack overflow, and the same
-- discipline as settle's step budget — a rule that runs away says so instead of
-- taking the process with it.
local receiving = 0

local function fire_receive(to, card_id)
	local def = to and declaration.G.zone_defs[to.key]
	if not (def and def.on_receive and M.run_actions) then return end
	if receiving >= 8 then
		local msg = "! receive: '" .. tostring(to.key) .. "' is passing cards round in a circle — stopped"
		log.add(msg)
		print(msg)
		return
	end
	receiving = receiving + 1
	-- Put the depth back even when the body raises, for the same reason
	-- zones.as_seat and predicate's reach latch are written this way: a counter
	-- left standing answers "too deep" to every later arrival, and a zone that
	-- quietly stopped responding is worse than the error that caused it.
	local ok, err = pcall(M.run_actions, def.on_receive,
		{ card_id = to.id, zone_id = to.id, targets = { card_id } })
	receiving = receiving - 1
	if not ok then error(err, 0) end
end

function M.move_card(card_id, to_id)
	local c  = entity.get(card_id)
	local to = entity.get(to_id)
	-- A full board refuses new arrivals (checked before any mutation, so a
	-- refused move leaves the card exactly where it was).
	if not c or not to or not M.has_room(to) then return false end

	-- Clear slot occupancy when card leaves its slot.
	if c.slot_id then
		local slot = entity.get(c.slot_id)
		if slot and slot.occupant == card_id then slot.occupant = nil end
		c.slot_id = nil
	end

	local from = entity.get(c.zone_id)
	if from then
		for i, id in ipairs(from.cards) do
			if id == card_id then table.remove(from.cards, i); break end
		end
		if #from.cards == 0 and from.tags.refill_when_empty then
			M.refill(from)
		end
	end

	table.insert(to.cards, card_id)
	c.zone_id = to_id
	M.auto_slot(card_id)
	fire_receive(to, card_id)
	return true
end

-- A piece knows where it stands, as its own stats: "col" and "row" straight off
-- the square, and "rank" counted from its owner's own side so that a pawn's
-- home is rank 2 whichever colour it is. Conditions and computed tags then read
-- a piece's position with the vocabulary they already have — "promoting" is
-- { "stat": "rank", "at_least": 8 } and needs nothing new at all.
--
-- Only stamped on cards that already carry the stat, following the same rule as
-- every other stat change: a board game declares them in card_stats, and a card
-- game that never asks where anything is stays untouched.
local function stamp_position(card_id)
	local c    = entity.get(card_id)
	local slot = c and c.slot_id and entity.get(c.slot_id)
	local z    = slot and entity.get(slot.zone_id)
	if not (z and z.grid and c.stats) then return end
	local facing = geometry.facing(tags.owner_of(c), declaration.G.seat_list or {})
	if c.stats.col  then c.stats.col  = slot.stats.col end
	if c.stats.row  then c.stats.row  = slot.stats.row end
	if c.stats.rank then c.stats.rank = geometry.rank(z, slot.stats.row, facing) end
end

-- A card in a grid zone without a chosen slot takes the first free one, so
-- cards can be placed friction-free (creation, drafts) or precisely
-- (slot targeting overrides this in place_in_slot).
function M.auto_slot(card_id)
	local c = entity.get(card_id)
	local z = c and entity.get(c.zone_id)
	if not z or z.zone_type ~= "grid" or c.slot_id then return end
	for _, sid in ipairs(z.slots) do
		local s = entity.get(sid)
		if s and not s.occupant then
			s.occupant = card_id
			c.slot_id  = sid
			stamp_position(card_id)
			return
		end
	end
end

-- Remove a card from play. The flat array keeps the husk (IDs stay valid) but
-- it belongs to no zone and holds no stats, so nothing renders, targets or
-- counts it. Unlike move_card this never triggers refill: destroying is not
-- drawing, and that also rules out refill loops.
function M.destroy_card(card_id)
	local c = entity.get(card_id)
	if not c then return end
	if c.slot_id then
		local slot = entity.get(c.slot_id)
		if slot and slot.occupant == card_id then slot.occupant = nil end
		c.slot_id = nil
	end
	local z = entity.get(c.zone_id)
	if z then
		for i, id in ipairs(z.cards) do
			if id == card_id then table.remove(z.cards, i); break end
		end
	end
	c.zone_id = nil
	c.stats   = {}
end

-- Place a card into a specific slot on a grid zone. What happens to a slot that
-- is already taken is the caller's to say: refusing is the default and what
-- every game before board movement assumed, but a piece taking another piece is
-- a move onto an occupied square and nothing else. The occupant leaves before
-- the arrival is attempted, so a capture onto a full board still has a free
-- square to land on, and a tray with no room refuses the whole move rather than
-- destroying a piece it could not store.
function M.place_in_slot(card_id, slot_id, on_occupied)
	local slot = entity.get(slot_id)
	if not slot then return false end
	local held = slot.occupant
	if held ~= nil and held ~= card_id then
		if on_occupied == nil or on_occupied == "refuse" then return false end
		if on_occupied == "destroy" then
			M.destroy_card(held)
		else
			local to = M.find_id(on_occupied)
			if not (to and M.move_card(held, to)) then return false end
		end
	end
	M.move_card(card_id, slot.zone_id)
	local card = entity.get(card_id)
	-- The zone may have answered the arrival by sending the card somewhere else,
	-- and binding it to a square it no longer stands on would leave the slot
	-- pointing at a card in another zone.
	if card.zone_id ~= slot.zone_id then return false end
	-- release whatever slot move_card auto-assigned on grid entry
	if card.slot_id and card.slot_id ~= slot_id then
		local old = entity.get(card.slot_id)
		if old and old.occupant == card_id then old.occupant = nil end
	end
	card.slot_id  = slot_id
	slot.occupant = card_id
	stamp_position(card_id)
	return true
end

-- The only board, when there is exactly one — what a coordinate means when
-- nothing said which grid it was on. Hidden grids (the engine's own) are not
-- boards: nothing can be placed on one nobody can see.
function M.sole_grid()
	local found
	for z in entity.each("zone") do
		if z.zone_type == "grid" and not z.tags.hidden then
			if found then return nil end
			found = z
		end
	end
	return found
end

function M.shuffle(zone_id)
	local z = entity.get(zone_id)
	if not z then return end
	rng.shuffle(z.cards)
end

-- Which of a chequered board's two colours a square takes, 1 or 2.
--
-- A fact about the board rather than about drawing, which is why it is here and
-- not in the renderer: **a1 is dark**, and that is the one square anybody can
-- check against a real chessboard. `row` is a rank counted from the bottom, so
-- a1 is (1,1) and *even* — reading the parity the other way round inverts every
-- board with an even number of rows, which is what happened when row flipped to
-- count upwards and this sum stayed where it was.
function M.chequer_index(slot)
	local s = slot and slot.stats
	if not (s and s.col and s.row) then return 1 end
	return (s.col + s.row) % 2 == 1 and 1 or 2
end

-- The pixel rect of cell `idx` in a grid zone, 1-based and row-major. Shared
-- with the renderer, which needs the same cell for a card that has no slot.
-- `pad` is the gap that keeps cards from touching; pass 0 for the square
-- itself, which on a chessboard has to tile edge to edge.
function M.cell_rect(z, idx, pad)
	local g    = z.grid or { 4, 3 }
	local cols = g[1]
	pad        = pad or 4
	local cw   = z.place.w / cols
	local ch   = z.place.h / (g[2] or 3)
	local col  = (idx - 1) % cols
	local row  = math.floor((idx - 1) / cols)
	return {
		x = z.place.x + col * cw + pad,
		y = z.place.y + row * ch + pad,
		w = cw - pad * 2,
		h = ch - pad * 2,
	}
end

-- A zone whose contents have a shape of their own — a chessboard, a hex map, a
-- picture — has to keep it whatever the window does. `pos` is fractions of the
-- window, so without this a board is only square at one window aspect and a
-- rhombus at every other, and `cell_rect` stretches all 64 squares to match.
--
-- `ratio` is width over height, and claims the largest rect of that shape inside
-- the space `pos` allotted. The slack is centred and nothing else moves: a board
-- that shrinks leaves a gap rather than pushing the hands around, because the
-- other zones' fractions are their own business. A layout where that gap matters
-- wanted a different `pos`.
--
-- It is a **field and not a tag** on purpose. A tag is a word — good for a
-- quality a zone either has or hasn't, which is what `cell_outline: false` says
-- — and a ratio is a number, of which there are infinitely many. Encoding it
-- as a tag means either a closed set of words that is always missing somebody's
-- aspect, or numbers parsed out of tag strings, which is a field in a tag's
-- clothes. One field also keeps one question in one place: `"grid"` reads the
-- cell count, and any later source of a shape is another word here rather than
-- another tag that must never appear beside the first.
local function keep_ratio(z)
	local r
	local ratio = z.style.ratio
	if ratio == "grid" then
		r = z.grid and z.grid[2] and z.grid[1] / z.grid[2]
	else
		r = tonumber(ratio)
	end
	if not r or r <= 0 then return end
	local p = z.place
	local w = math.min(p.w, p.h * r)
	local h = w / r
	p.x, p.y = p.x + (p.w - w) / 2, p.y + (p.h - h) / 2
	p.w, p.h = w, h
end

-- Recompute pixel rects for all zones and their slots.
function M.resize()
	local W, H = love.graphics.getDimensions()
	for z in entity.each("zone") do
		local p = z.pos
		z.place = {
			x = p[1] * W,
			y = p[2] * H,
			w = (p[3] - p[1]) * W,
			h = (p[4] - p[2]) * H,
		}
		keep_ratio(z)
		if z.zone_type == "grid" and z.grid and next(z.slots) then
			for idx, slot_id in pairs(z.slots) do
				local slot = entity.get(slot_id)
				if slot then slot.place = M.cell_rect(z, idx) end
			end
		end
	end
end

-- The zone under a point. Hidden zones are skipped: they are never drawn, so
-- nothing the player can see is there to click. The engine's own "reveal" panel
-- is hidden and covers most of the screen, so without this it answers for the
-- whole board and every zone underneath becomes unclickable.
function M.zone_at(x, y)
	local result = nil
	for z in entity.each("zone") do
		if not z.tags.hidden and M.contains(z.place, x, y) then result = z.id end
	end
	return result
end

-- What is drawn is what may be clicked, and the three hit tests have to agree
-- about that or the board grows places where clicks disappear.
--
-- A hidden zone is not drawn, so it is not clickable — `zone_at` above has
-- always said so, and these two did not. Their cards and slots still have
-- places, so an offer zone parked over the middle of the board swallowed every
-- click that landed in its rectangle while showing nothing. `open_id` is the
-- one exception: an overlay draws its own zone over the dim, and that zone is
-- clickable exactly while it is.
--
-- A hidden zone with no `pos` sits off-screen (declaration's DEFAULT_POS), which
-- is why this went unnoticed: only a zone that overrides that — an overlay,
-- which must be somewhere visible when it opens — can cover anything.
local function reachable(z, open_id)
	return not z.tags.hidden or z.id == open_id
end

function M.card_at(x, y, open_id)
	local result
	for z in entity.each("zone") do
		if z.zone_type ~= "deck" and reachable(z, open_id) and M.contains(z.place, x, y) then
			-- Last match wins, and a fan is drawn in order, so a click in the
			-- overlap lands on the card actually showing there.
			local list = z.zone_type == "pile" and not z.style.fan
				and { z.cards[#z.cards] } or z.cards
			for _, cid in ipairs(list) do
				local c = entity.get(cid)
				if c and c.place and M.contains(c.place, x, y) then result = cid end
			end
		end
	end
	return result
end

function M.slot_at(x, y, open_id)
	for e in entity.each("slot") do
		local z = e.zone_id and entity.get(e.zone_id)
		if z and reachable(z, open_id) and M.contains(e.place, x, y) then return e.id end
	end
end

return M
