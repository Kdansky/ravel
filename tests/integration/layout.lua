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
local BOARD = '{ "key": "board", "layout": "grid", "grid": [8, 8], "pos": [0.2, 0, 1, 0.9], "tags": ["shaped"] }'

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
-- them. An offer parked over the middle of the board swallowed every click that
-- landed in its rectangle: a pawn could step to e3 and never to e4, and the
-- targeting session it left open ate everything after it.
--
-- An `options` zone now holds nothing until it is asked for, which removes the
-- cards there were to click. The rule still has to hold, because a game may
-- put cards in any hidden zone it likes.
function M.test_layout_a_hidden_offer_swallows_no_clicks(check)
	flow.init("chess.json", 1)
	zones.resize()
	local board = zones.find("board")
	local e4    = entity.get(geometry.slot_named(board, "e4"))
	local cx    = e4.place.x + e4.place.w * 0.5
	local cy    = e4.place.y + e4.place.h * 0.5

	local offer = zones.find("options")
	check("the offer lies over the middle of the board, as an offer must",
		zones.contains(offer.place, cx, cy))
	check("but holds nothing at all until something asks", #offer.cards == 0)

	-- Ask, so there is something there to be wrongly clickable.
	require("actions").execute("options:to_queen,to_rook,to_bishop,to_knight",
		{ card_id = entity.get(board.cards[1]).id })
	check("and holds the choices once asked", #offer.cards == 4)
	-- Cards are given places by the renderer; this is the shape of what it gives
	-- them, and the point is that they have one at all.
	for _, id in ipairs(offer.cards) do entity.get(id).place = offer.place end

	check("a square under a closed offer is still that square",
		zones.slot_at(cx, cy) == e4.id)
	check("and nothing in the offer is clickable through it",
		zones.card_at(cx, cy) == nil)
	check("the offer being open is the one thing that makes it reachable",
		zones.card_at(cx, cy, offer.id) == offer.cards[#offer.cards])
	check("and the board beneath still answers for its own squares",
		zones.slot_at(cx, cy, offer.id) == e4.id)
end

-- A board's first colour goes on a1, and nothing else decides it. The rule used
-- to be "a1 is dark", which is true of a chessboard and of nothing else — it
-- made every other board's colours depend on a convention its author had to
-- know, and it cost a paragraph in `zones.lua` explaining which parity was
-- which. A designer who disagrees swaps two strings.
function M.test_layout_the_first_colour_goes_on_a1(check)
	flow.init("chess.json", 1)
	local board = zones.find("board")
	local function shade(name)
		return zones.chequer_index(entity.get(geometry.slot_named(board, name)))
	end
	check("chess names its dark colour first, because a1 is dark",
		board.style.chequer[1] == "#b58863" and board.style.chequer[2] == "#f0d9b5",
		table.concat(board.style.chequer, " "))
	check("a1 takes it, and h1 beside it takes the other", shade("a1") == 1 and shade("h1") == 2)
	check("and the far corners answer the other way", shade("a8") == 2 and shade("h8") == 1)
	check("a square with no coordinates cannot pick a colour and says so",
		zones.chequer_index(nil) == 1 and zones.chequer_index({}) == 1)
end

-- A named grid keeps its name clear of its cards, which a hand has done since
-- the text pass and a grid could not: its cells come from `cell_rect`, and that
-- is also what hit-testing reads, so the band has to come off there or the
-- picture moves and the target does not follow it.
--
-- The band is measured by the renderer and written onto `zones` — this module
-- has no font — so headless it is zero and every rect is what it always was.
-- Setting it here is what the renderer does, one frame earlier.
function M.test_layout_a_named_grid_keeps_its_name_clear(check)
	flow.init("lor.json", 1)
	at(1600, 900, function()
		-- The bench is named, the lanes it feeds are not: one game, both cases.
		local bench, lanes = zones.all_with_key("bench")[1], zones.find("battle")
		zones.resize()
		local bare, lanes_bare = zones.cell_rect(bench, 1, 0), zones.cell_rect(lanes, 1, 0)
		zones.label_h = 20
		zones.resize()
		local head, lanes_head = zones.cell_rect(bench, 1, 0), zones.cell_rect(lanes, 1, 0)
		zones.label_h = 0
		check("the cells of a named grid start below the band",
			math.abs(head.y - bare.y - 20) < 0.01, ("%.2f vs %.2f"):format(head.y, bare.y))
		check("and give up its height rather than overflowing",
			math.abs((bare.h - head.h) - 20) < 0.01, ("%.2f vs %.2f"):format(head.h, bare.h))
		check("a grid with no name is untouched, which is every chessboard",
			lanes_head.y == lanes_bare.y and lanes_head.h == lanes_bare.h)
	end)
end

return M
