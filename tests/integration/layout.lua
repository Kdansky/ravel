-- Where zones land on screen, which is arithmetic and so belongs headless.
--
-- `pos` is fractions of the window, so a zone's pixel rect takes the window's
-- shape unless it says otherwise. `ratio` is how it says otherwise, and a
-- chessboard is the case: 64 cells divided out of a rhombus are 64 rhombuses.

local declaration = require("declaration")
local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local validate = require("validate")
local geometry = require("geometry")

local M = {}

-- The stub love.graphics is fixed at 960x540; every check here needs two
-- window shapes to say anything, so swap it for the call and put it back.
local function at(w, h, f)
	local was = love.graphics.getDimensions
	love.graphics.getDimensions = function() return w, h end
	local ok, err = pcall(f)
	love.graphics.getDimensions = was
	if not ok then error(err, 2) end
end

local function board_rect(w, h)
	local p
	at(w, h, function()
		zones.resize()
		p = zones.find("board").place
	end)
	return p
end

function M.test_layout_a_ratio_survives_the_window(check)
	flow.init("chess.json", 1)
	local wide = board_rect(1600, 900)
	local tall = board_rect(600, 1000)
	check("square on a wide window", math.abs(wide.w - wide.h) < 0.01,
		("%.2fx%.2f"):format(wide.w, wide.h))
	check("square on a tall one", math.abs(tall.w - tall.h) < 0.01,
		("%.2fx%.2f"):format(tall.w, tall.h))
	check("and the two are different sizes", math.abs(wide.w - tall.w) > 1)
end

function M.test_layout_the_slack_is_centred(check)
	flow.init("chess.json", 1)
	local z = zones.find("board")
	local p = z.pos
	at(1600, 900, function()
		zones.resize()
		local r = z.place
		local left = r.x - p[1] * 1600
		local right = (p[3] * 1600) - (r.x + r.w)
		check("equal slack on both sides", math.abs(left - right) < 0.01,
			("left %.2f right %.2f"):format(left, right))
		check("and it never grows past what pos allotted",
			r.w <= (p[3] - p[1]) * 1600 + 0.01 and r.h <= (p[4] - p[2]) * 900 + 0.01)
	end)
end

-- The cells are cut out of the corrected rect, not the allotted one — which is
-- the whole point, since a stretched board is 64 stretched squares.
function M.test_layout_the_cells_follow(check)
	flow.init("chess.json", 1)
	at(1600, 900, function()
		zones.resize()
		local z = zones.find("board")
		local cell = zones.cell_rect(z, 1, 0)
		check("a square board has square cells", math.abs(cell.w - cell.h) < 0.01,
			("%.2fx%.2f"):format(cell.w, cell.h))
		local slot = entity.get(z.slots[1])
		check("and the slot entity got the same rect", slot and slot.place.x == cell.x + 4)
	end)
end

-- A zone that says nothing keeps the old behaviour exactly: this is the
-- regression that matters, because every shipped layout was drawn against it.
function M.test_layout_without_a_ratio_nothing_changes(check)
	flow.init("lost_cities.json", 1)
	at(1600, 900, function()
		zones.resize()
		local z = zones.find("hand")
		local p = z.pos
		check("the rect is still pos times the window",
			math.abs(z.place.w - (p[3] - p[1]) * 1600) < 0.01
			and math.abs(z.place.h - (p[4] - p[2]) * 900) < 0.01)
	end)
end

local function fixture(zone, style)
	local path = "game/games/tmp_layout_test.json"
	local f = assert(io.open(path, "w"))
	f:write(([[{
		"title": "Layout",
		"styles": { "shaped": %s },
		"zones": [%s],
		"cards": [{ "key": "hero", "text": "Hero" }],
		"phases": [{ "key": "play", "type": "player_input" }]
	}]]):format(style or "{}", zone))
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_layout_test.json")
	os.remove(path)
	if not ok then error(G, 2) end
	return validate.check(G)
end

local function has(problems, needle)
	for _, p in ipairs(problems) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

-- The shape is a style the zone tags, so what is checked is the style.
local BOARD = '{ "key": "board", "type": "grid", "grid": [8, 8], "pos": [0.2, 0, 1, 0.9], "tags": ["shaped"] }'

function M.test_layout_a_ratio_is_checked(check)
	check("a number passes", #fixture(BOARD, '{ "ratio": 1.5 }') == 0)
	check('so does "grid"', #fixture(BOARD, '{ "ratio": "grid" }') == 0)
	check("a word is refused",
		has(fixture(BOARD, '{ "ratio": "square" }'), "ratio should be a positive number"))
	check("so is a negative one",
		has(fixture(BOARD, '{ "ratio": -2 }'), "ratio should be a positive number"))
	check("and a style may not carry a rule",
		has(fixture(BOARD, '{ "ratio": 1, "cost": { "gold": 1 } }'), "the engine doesn't read"))
end

-- What is drawn is what may be clicked. A hidden zone is not drawn, and
-- `zone_at` has always refused to return one — but the card and slot hit tests
-- did not, and their cards keep their places whether or not anyone can see
-- them. Chess's promotion offer sits over the middle of the board, so every
-- click in that band hit an invisible card instead of the square underneath:
-- a pawn could step to e3 and never to e4, and the targeting session it left
-- open swallowed everything after it.
--
-- Lost Cities dodged this for a year by destroying its offer's cards when one
-- is chosen, leaving the zone empty. Chess keeps its four for the whole game.
function M.test_layout_a_hidden_offer_swallows_no_clicks(check)
	flow.init("chess.json", 1)
	zones.resize()
	local board = zones.find("board")
	local e4    = entity.get(geometry.slot_at(board, 5, 5))
	local cx    = e4.place.x + e4.place.w * 0.5
	local cy    = e4.place.y + e4.place.h * 0.5

	local offer = zones.find("promote")
	check("the promotion offer really does lie over the middle of the board",
		zones.contains(offer.place, cx, cy))

	-- Cards are given places by the renderer; this is the shape of what it gives
	-- them, and the point is that they have one at all.
	for _, id in ipairs(offer.cards) do entity.get(id).place = offer.place end

	check("a square under a closed offer is still that square",
		zones.slot_at(cx, cy) == e4.id)
	check("and nothing in the offer is clickable through it",
		zones.card_at(cx, cy) == nil)
	check("the offer being open is the one thing that makes it reachable",
		zones.card_at(cx, cy, offer.id) == offer.cards[#offer.cards])
	check("and then it is the offer that answers, not the board beneath",
		zones.slot_at(cx, cy, offer.id) == e4.id)
end

return M
