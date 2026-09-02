-- A game file that never shipped, played anyway.
--
-- The engine has always been able to run a game handed to it as text — that is
-- how a network invite carries its rules to somebody who has never seen the
-- file — so opening one from the player's own machine is only the asking, and
-- the asking is what these tests do not have. What they hold is the door:
-- whatever comes through it is a stranger's file, and a stranger's file must
-- either run or land the player back on the menu.

local declaration = require("declaration")
local openfile    = require("openfile")

local M = {}

local GAME = [==[{
  "title": "A Game From Elsewhere",
  "players": [{ "card": "one" }],
  "cards": [{ "key": "one", "text": "One", "tags": ["immutable"] }],
  "phases": [{ "key": "wait", "type": "player_input" }]
}]==]

function M.test_openfile_a_file_never_installed_becomes_the_running_game(check)
	check("it opens", openfile.take("elsewhere.json", GAME))
	check("and it is what is playing", declaration.G.title == "A Game From Elsewhere",
		tostring(declaration.G.title))
	check("under the name it arrived with", declaration.filename == "elsewhere.json",
		tostring(declaration.filename))
end

-- The name is an identity and not a path: the file watcher builds one out of it
-- and the net layer hashes games by it, so a name somebody typed on their own
-- machine has to survive being used as one.
function M.test_openfile_a_name_from_someones_desktop_is_made_safe(check)
	openfile.take("/home/somebody/My Game (2).JSON", GAME)
	check("the folders are gone and the spaces with them",
		declaration.filename == "My_Game__2_.json", tostring(declaration.filename))
	openfile.take("../../etc/passwd", GAME)
	check("and a name trying to be a path is just its last word",
		declaration.filename == "passwd.json", tostring(declaration.filename))
end

function M.test_openfile_a_file_that_is_not_a_game_lands_on_the_menu(check)
	check("it refuses", openfile.take("junk.json", "{ this is not JSON") == false)
	check("and the menu is what is playing", declaration.filename == "menu.json",
		tostring(declaration.filename))
end

-- The browser hands its answer back through a bridge that was only ever fed
-- base64, and a game file is neither single-line nor ASCII: a raw newline cuts
-- the reply off where it sits, and one em-dash in one tooltip walks the chunk
-- offsets out of step, because they count Lua bytes against a JavaScript
-- length. Both are invisible until somebody opens a real file, so the encoding
-- that answers them is held here against a real one.
function M.test_openfile_a_real_game_file_survives_the_browser_bridge(check)
	local f = assert(io.open("game/games/chess.json"))
	local want = f:read("*a")
	f:close()
	check("the file it is held against has both hazards in it",
		want:find("\n", 1, true) ~= nil and want:find("[\128-\255]") ~= nil)

	-- What encodeURIComponent leaves alone, spelled as the set it keeps.
	local encoded = want:gsub("[^A-Za-z0-9%-_%.!~%*'%(%)]", function(c)
		return ("%%%02X"):format(c:byte())
	end)
	check("what crosses is one line of ASCII",
		encoded:find("\n", 1, true) == nil and encoded:find("[\128-\255]") == nil)
	check("and it comes back the file it was", openfile.decoded(encoded) == want)

	check("so it opens", openfile.take("chess.json", openfile.decoded(encoded)))
	check("and Chess is what is playing", declaration.G.title == "Chess",
		tostring(declaration.G.title))
end

function M.test_openfile_an_empty_file_changes_nothing(check)
	openfile.take("good.json", GAME)
	check("it refuses", openfile.take("empty.json", "") == false)
	check("and the game that was running still is", declaration.filename == "good.json",
		tostring(declaration.filename))
end

return M
