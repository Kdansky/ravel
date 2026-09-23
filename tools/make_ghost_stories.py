#!/usr/bin/env python3
"""Generate game/games/ghost_stories.json.

Sixty-five ghosts, each one a colour, a resistance and up to three icons, is
data — transcribed in ideas/ghost_stories/rules.md off the card scans. What is
not data lives here: the table's geometry, the haunting cycle, the dice, and the
turn.

**The geometry is the whole design.** Village and boards share one 5x5 grid: the
nine tiles sit in the middle, the twelve ghost spaces run along the four edges,
and the corners hold a plaque apiece. Everything the rulebook says about *where*
then falls out of two patterns. A Taoist may walk to a tile `adjacent` to the one
it stands on, diagonals included, which is exactly the rulebook's move. A Taoist
may exorcise a ghost `orthogonal` to its tile, which is exactly "the space in
front of you" — one from an edge tile, two from a corner, none from the middle,
without a word said about any of it.

Taoists **stand on** their tiles rather than beside them, so a tile holds four of
them if it must and the figure travels with the question: `mine.attached_to.
orthogonal` read from a ghost is "is one of my Taoists facing me".

**A pattern must be symmetric here**, and that is not decoration. The engine
turns `y` round for every seat but the first, so `[[0,1]]` read off an unowned
card means "up the board" on one player's turn and "down" on another's. Every
pattern below names both directions, and the far one falls off the board: `vert1`
from a ghost on the south edge names the tile above it and nothing else, and the
same pattern from the north edge names the tile below. One rule, four boards.

    python3 tools/make_ghost_stories.py
"""

import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt
import guard

# --------------------------------------------------------------------------
# The table

# Board key, the seat that sits behind it, its colour, the corner plaque that
# counts its three spaces, and the pattern that plaque uses. South is seat one,
# and the rest go round anticlockwise the way the rects below are laid out.
SIDES = [
    ("south", "yellow", 0, "a1", "row3"),
    ("west",  "blue",   1, "a5", "col3"),
    ("north", "green",  2, "e5", "row3"),
    ("east",  "red",    3, "e1", "col3"),
]

# Where each board's three ghost spaces are, so setup and `where` agree.
SPACES = {
    "south": ["b1", "c1", "d1"],
    "west":  ["a2", "a3", "a4"],
    "north": ["b5", "c5", "d5"],
    "east":  ["e2", "e3", "e4"],
}

# "row@target == 1" and its three siblings: which squares are a board's.
ON_BOARD = {
    "south": ["row@target == 1"],
    "west":  ["col@target == 1"],
    "north": ["row@target == 5"],
    "east":  ["col@target == 5"],
}

VILLAGE = ["b2", "c2", "d2", "b3", "c3", "d3", "b4", "c4", "d4"]
# The tiles are laid out in the order they are listed, so the fifth of them
# stands in the middle and is where the four Taoists begin.
CENTRE_TILE = "temple"

# Tao colours. Black is a Tao colour and not a board colour: black ghosts go to
# whoever is playing rather than to a board of their own.
TAO = [
    ("yellow", "Sticky rice", "gold"),
    ("green",  "Silver bell", "green"),
    ("red",    "Incense",     "crimson"),
    ("blue",   "Mirror",      "blue"),
    ("black",  "Coin",        "slate"),
]
TAO_KEYS = [t[0] for t in TAO]
DIE_FACES = TAO_KEYS + ["white"]

# The Curse die. Five effects over six faces, and the blank is the sixth: the
# rulebook prints five icons and the die has six sides, so one face repeats.
# Which one is a guess nobody's scan settles, so it is the blank — the reading
# that changes the game least.
CURSE = [
    ("blank", "No effect", 2),
    ("haunt", "The first active tile in front of the ghost is haunted", 1),
    ("ghost", "Bring a ghost into play", 1),
    ("tao",   "Discard all your Tao tokens", 1),
    ("qi",    "Lose 1 Qi", 1),
]

# --------------------------------------------------------------------------
# The ghosts, from ideas/ghost_stories/rules.md.
#
# (key, name, colour, resistance, left icons, middle icons, right icons)

G = [
    ("ghoul",         "Ghoul",              "yellow", 1, [], ["HAUNTER"], []),
    ("walking_corpse","Walking Corpse",     "yellow", 1, [], ["DICE_OFF"], []),
    ("coffin_a",      "Coffin Breakers",    "yellow", 1, ["G"], ["POWER_OFF"], []),
    ("coffin_b",      "Coffin Breakers",    "yellow", 1, ["G"], [], []),
    ("restless_dead", "Restless Dead",      "yellow", 2, [], ["HAUNTER"], []),
    ("zombie_a",      "Zombie",             "yellow", 2, [], [], ["CURSE"]),
    ("zombie_b",      "Zombie",             "yellow", 2, [], [], ["CURSE"]),
    ("hopping_a",     "Hopping Vampire",    "yellow", 3, [], ["HAUNTER"], []),
    ("hopping_b",     "Hopping Vampire",    "yellow", 3, [], ["HAUNTER"], []),
    ("yellow_plague", "Yellow Plague",      "yellow", 3, [], [], ["R_TAO2"]),
    ("lich",          "Lich",               "yellow", 4, [], ["CURSE"], ["R_QI"]),

    ("drowned_maiden","Drowned Maiden",     "blue", 1, [], ["HAUNTER"], []),
    ("hound",         "Hound of Depth",     "blue", 1, [], ["DICE_OFF"], []),
    ("nymph_a",       "Perfidious Nymph",   "blue", 1, ["G"], ["POWER_OFF"], []),
    ("nymph_b",       "Perfidious Nymph",   "blue", 1, ["G"], [], []),
    ("sticky_feet",   "Sticky Feet",        "blue", 2, [], ["HAUNTER"], []),
    ("abysmal_a",     "Abysmal",            "blue", 2, [], [], ["CURSE"]),
    ("abysmal_b",     "Abysmal",            "blue", 2, [], [], ["CURSE"]),
    ("ooze_a",        "Ooze Devil",         "blue", 3, [], ["HAUNTER"], []),
    ("ooze_b",        "Ooze Devil",         "blue", 3, [], ["HAUNTER"], []),
    ("liquid_horror", "Liquid Horror",      "blue", 4, [], [], ["R_TAO2"]),
    ("fury",          "Fury of Depth",      "blue", 4, [], ["CURSE"], ["R_QI"]),

    ("creeping_one",  "Creeping One",       "green", 1, [], ["HAUNTER"], []),
    ("fungus",        "Fungus Thing",       "green", 1, [], ["DICE_OFF"], []),
    ("fallen_a",      "Fallen Monks",       "green", 1, ["G"], ["POWER_OFF"], []),
    ("fallen_b",      "Fallen Monk",        "green", 1, ["G"], [], []),
    ("restless_spirit","Restless Spirit",   "green", 2, [], ["HAUNTER"], []),
    ("rotten_a",      "Rotten Soul",        "green", 2, [], [], ["CURSE"]),
    ("rotten_b",      "Rotten Soul",        "green", 2, [], [], ["CURSE"]),
    ("wicked_a",      "Wicked One",         "green", 3, [], ["HAUNTER"], []),
    ("wicked_b",      "Wicked One",         "green", 3, [], ["HAUNTER"], []),
    ("green_abom",    "Green Abomination",  "green", 4, [], [], ["R_TAO2"]),
    ("great_putrid",  "Great Putrid",       "green", 4, [], ["CURSE"], ["R_QI"]),

    ("skinner",       "Skinner",            "red", 1, [], ["HAUNTER"], []),
    ("reaper",        "Reaper",             "red", 1, [], ["DICE_OFF"], []),
    ("mistress_a",    "Sharp-Nailed Mistresses", "red", 1, ["G"], ["POWER_OFF"], []),
    ("mistress_b",    "Sharp-Nailed Mistresses", "red", 1, ["G"], [], []),
    ("bleeding_eyes", "Bleeding Eyes",      "red", 2, [], ["HAUNTER"], []),
    ("blood_a",       "Blood Drinker",      "red", 2, [], [], ["CURSE"]),
    ("blood_b",       "Blood Drinker",      "red", 2, [], [], ["CURSE"]),
    ("scarlet_a",     "Scarlet Evildoer",   "red", 3, [], ["HAUNTER"], []),
    ("scarlet_b",     "Scarlet Evildoer",   "red", 3, [], ["HAUNTER"], []),
    ("flesh",         "Flesh Devourer",     "red", 4, [], [], ["R_TAO2"]),
    ("raging_one",    "Raging One",         "red", 4, [], ["CURSE"], ["R_QI"]),

    ("gloomy",        "Gloomy Minion",      "black", 1, ["QUICK"], ["HAUNTER"], ["R_TAO"]),
    ("repellent",     "Repellent Beauty",   "black", 1, ["DIE_CAPTIVE"], ["DICE_OFF"], ["R_TAO"]),
    ("severed_a",     "Severed Heads",      "black", 1, ["DIE_CAPTIVE", "G"], [], ["R_TAO"]),
    ("severed_b",     "Severed Heads",      "black", 1, ["DIE_CAPTIVE", "G"], [], ["R_TAO"]),
    ("grave_walker",  "Grave Walker",       "black", 2, ["QI_LOSS"], ["HAUNTER"], ["R_QI"]),
    ("widow_a",       "Black Widow",        "black", 2, ["TAO_OFF"], [], ["CURSE", "R_QI"]),
    ("widow_b",       "Black Widow",        "black", 2, ["TAO_OFF"], [], ["CURSE", "R_QI"]),
    ("wraith_a",      "Dark Wraith",        "black", 3, ["QUICK"], ["HAUNTER"], ["R_QI"]),
    ("wraith_b",      "Dark Wraith",        "black", 3, ["QUICK"], ["HAUNTER"], ["R_QI"]),
    ("shapeless",     "Shapeless Evil",     "black", 2, ["H"], [], ["R_QI"]),
    ("soul_eater",    "Soul Eater",         "black", 2, ["GROUP_TAO"], ["CURSE"], ["R_QI"]),
]

# The ten incarnations. Colour and resistance as printed; what each one does
# beyond that is its own rule, written out in `incarnation_rules` below.
# Two incarnations print a resistance in several colours at once, so they ask
# several questions instead of one.
MULTI = {
    "hope": {"blue": 2, "red": 2, "green": 2, "yellow": 2},
    "nameless": {"blue": 1, "green": 1, "yellow": 1, "red": 1, "black": 1},
}

INC = [
    ("howling",   "Howling Nightmare", "black", 3, ["G"], [], []),
    ("uncatch",   "Uncatchable",       "black", 3, ["G"], [], []),
    ("hope",      "Hope Killer",       "multi", 2, [], [], ["CURSE"]),
    ("death_army","Death Army",        "black", 5, [], ["CURSE"], ["CURSE"]),
    ("forgotten", "Forgotten Ones",    "black", 3, ["POWER_ALL"], [], []),
    ("bone",      "Bone Cracker",      "red",   4, ["GROUP_TAO"], ["GROUP_TAO"], []),
    ("mistress",  "Dark Mistress",     "blue",  3, ["TAO_OFF"], [], []),
    ("horror",    "Creeping Horror",   "green", 4, ["DIE_CAPTIVE"], [], []),
    ("vampire",   "Vampire Lord",      "yellow",4, [], ["HAUNTER"], []),
    ("nameless",  "Nameless",          "multi", 1, ["CIRCLE_OFF"], [], []),
]

# The blurb under a ghost's name, one sentence per icon, so the card says what
# it does without the player learning sixteen pictures.
SAYS = {
    "G": "When it arrives, another ghost comes into play.",
    "H": "When it arrives, it haunts the first active tile in front of it.",
    "QI_LOSS": "When it arrives, you lose 1 Qi.",
    "HAUNTER": "Haunter: every second Yin phase it haunts the first active tile in front of it.",
    "QUICK": "Its haunting figure starts on the board, so it haunts at once.",
    "CURSE": "Roll the Curse die.",
    "R_QI": "Reward: 1 Qi, or your Yin-Yang back.",
    "R_TAO": "Reward: 1 Tao token of your choice.",
    "R_TAO2": "Reward: 2 Tao tokens of your choice.",
    "POWER_OFF": "While it lives, the board it stands on loses its power.",
    "DICE_OFF": "Tao dice do nothing to it. Tokens and the Circle of Prayer still do.",
    "TAO_OFF": "While it lives, nobody may spend Tao tokens.",
    "DIE_CAPTIVE": "While it lives, it holds one Tao die: exorcisms roll one die fewer.",
    "GROUP_TAO": "Every player discards a Tao token.",
    "POWER_ALL": "While it lives, no Taoist may use their power.",
    "CIRCLE_OFF": "When it arrives, the Tao token on the Circle of Prayer is discarded.",
}

# --------------------------------------------------------------------------
# The village

TILES = [
    ("cemetery", "Cemetery",
     "Bring a dead Taoist back with 2 Qi, then roll the Curse die."),
    ("altar", "Taoist Altar",
     "Turn one haunted tile back to its active side, then bring a ghost into play."),
    ("herbalist", "Herbalist's Shop",
     "Roll 2 Tao dice and take a token of each colour rolled; a white face is any colour."),
    ("sorcerer", "Sorcerer's Hut",
     "Discard any ghost in play, with neither its curse nor its reward. Lose 1 Qi."),
    ("temple", "Buddhist Temple",
     "Take a Buddha figurine. You may place it from your next turn on."),
    ("watchman", "Night Watchman's Beat",
     "Send every haunting figure on one board back onto its card."),
    ("circle_tile", "Circle of Prayer",
     "Put a Tao token here, or change the one there. Ghosts of that colour are one easier "
     "to exorcise, for everybody."),
    ("pavilion", "Pavilion of the Heavenly Wind",
     "Move one ghost to any free space, then move another Taoist to any tile."),
    ("tea_house", "Tea House",
     "Take a Tao token of your choice and 1 Qi, then bring a ghost into play."),
]


def colour_of(g):
    return g[2]


# --------------------------------------------------------------------------
# Patterns


def patterns():
    def both(dx, dy, n):
        return [[dx * n, dy * n], [-dx * n, -dy * n]]
    p = {
        "adjacent": {"vectors": [[1, 0], [-1, 0], [0, 1], [0, -1],
                                 [1, 1], [1, -1], [-1, 1], [-1, -1]]},
        "orthogonal": {"vectors": [[1, 0], [-1, 0], [0, 1], [0, -1]]},
        "row3": {"vectors": [[1, 0], [2, 0], [3, 0], [-1, 0], [-2, 0], [-3, 0]]},
        "col3": {"vectors": [[0, 1], [0, 2], [0, 3], [0, -1], [0, -2], [0, -3]]},
    }
    for n in (1, 2, 3, 4):
        p["vert%d" % n] = {"vectors": both(0, 1, n)}
        p["horiz%d" % n] = {"vectors": both(1, 0, n)}
    return p


# --------------------------------------------------------------------------
# Numbers


def stats():
    out = [
        {"key": "qi", "label": "Qi", "icon": "heart", "color": "crimson",
         "min": 0, "max": 20, "on": ["player"], "start": 4},
        {"key": "yy", "label": "Yin-Yang", "icon": "diamond", "color": "silver",
         "min": 0, "max": 1, "display": "nonzero", "on": ["player"], "start": 1},
        {"key": "owed", "label": "Tao owed", "icon": "coin", "color": "gold",
         "min": 0, "max": 9, "display": "nonzero", "on": ["player"], "start": 0},
        {"key": "boons", "label": "Rewards", "icon": "banner", "color": "sand",
         "min": 0, "max": 9, "display": "nonzero", "on": ["player"], "start": 0},
    ]
    seat_work = ["side", "incoming", "skip", "rolling", "acted", "moved",
                 "exorcising", "owed_c", "blowing", "in_yang"]
    for k in seat_work:
        out.append({"key": k, "min": 0, "max": 9, "display": "offscreen",
                    "on": ["player"], "start": 0})
    out += [
        {"key": "haunted", "label": "Haunted", "icon": "none",
         "min": 0, "max": 1, "display": "offscreen", "on": ["village"], "start": 0},
        {"key": "haunt", "label": "Haunting", "icon": "none",
         "min": 0, "max": 2, "display": "offscreen", "on": ["ghost"], "start": 0},
        # The Curse die is rolled by a ghost and, at a graveside, by the
        # Cemetery tile, so both kinds of card carry the flag that says
        # "that roll is mine to read".
        {"key": "rolls", "min": 0, "max": 1, "display": "offscreen",
         "on": ["ghost", "village"], "start": 0},
    ]
    ghost_work = ["board", "to_haunt", "mantra", "rolled", "dying", "fresh"]
    for k in ghost_work:
        out.append({"key": k, "min": 0, "max": 9, "display": "offscreen",
                    "on": ["ghost"], "start": 0})
    out.append({"key": "stock", "icon": "none", "min": 0, "max": 99, "display": "offscreen"})
    return out


def computes():
    """What an exorcism is worth, in each colour.

    One number per colour, because a condition compares two subjects and cannot
    add: the dice showing that colour, the whites (which are wild), the tokens
    this player has committed, the Circle of Prayer's standing token, and the
    Enfeeblement Mantra if it is on this ghost. `token_*` is the same sum with
    the dice left out, which is what a ghost the dice cannot touch is worth.
    """
    out = []
    for c in TAO_KEYS:
        dice = "count:%s@dice + count:white@dice" % c
        rest = "count:%s@mine.spent + count:%s@circle + mantra@self" % (c, c)
        out.append({"key": "power_" + c, "value": dice + " + " + rest,
                    "tooltip": "What this exorcism is worth in %s: the dice, the whites, "
                               "the tokens committed, the Circle of Prayer, and the Mantra." % c})
        out.append({"key": "token_" + c, "value": rest,
                    "tooltip": "The same sum without the dice, for a ghost the Tao dice "
                               "cannot touch."})
    return out


# --------------------------------------------------------------------------
# Zones


# Each seat sits at the side of the village its board is on, so the four make a ring round the table. The action tray is
# one zone down the left and not one per seat: the buttons are all about whoever is *up* — `mine.player` — and only one
# seat is ever up, so four copies would be thirty-two cards where eight say the same thing. The ghost arriving sits at
# the tray's foot rather than under the decks, because the corner below them is the undo button's.
def zones():
    z = [
        {"key": "table", "label": "The village and the four boards", "layout": "grid",
         "grid": [5, 5], "status": "board", "use": "abilities",
         "pos": [0.2725, 0.15, 0.6925, 0.85],
         "tooltip": "Nine village tiles in the middle, three ghost spaces along each edge, "
                    "and a plaque in each corner that counts the board beside it."},

        {"key": "deck", "label": "Ghosts", "layout": "stack", "visibility": "secret",
         "tags": ["shuffle"], "pos": [0.85, 0.02, 0.92, 0.18],
         "contents": ["g_" + g[0] for g in G],
         "tooltip": "Fifty-five ghosts. The incarnation of Wu-Feng comes off the urn "
                    "when ten are left, which is where the rulebook buries it."},
        {"key": "urn", "label": "Wu-Feng", "layout": "stack", "visibility": "secret",
         "tags": ["shuffle"], "pos": [0.925, 0.02, 0.995, 0.18],
         "contents": ["i_" + i[0] for i in INC],
         "tooltip": "Ten incarnations, one of which will be drawn when the deck is down "
                    "to its last ten cards. Which one is nobody's business until then."},
        {"key": "hell", "label": "Hell", "layout": "stack", "status": "grave", "use": "none",
         "pos": [0.85, 0.20, 0.92, 0.34]},
        {"key": "shrine", "label": "Buddhas", "layout": "row", "status": "board",
         "pos": [0.925, 0.20, 0.995, 0.34],
         "tooltip": "The two Buddha figurines live on the Buddhist Temple tile until "
                    "somebody asks for one."},

        {"key": "dice", "label": "Tao dice", "layout": "row", "status": "board", "use": "none",
         "pos": [0.85, 0.36, 0.995, 0.48]},
        {"key": "curse", "label": "Curse die", "layout": "row", "status": "board", "use": "none",
         "pos": [0.85, 0.50, 0.92, 0.64]},
        {"key": "circle", "label": "Circle of Prayer", "layout": "row", "status": "board",
         "use": "none", "pos": [0.925, 0.50, 0.995, 0.64],
         "tooltip": "The token standing on the Circle of Prayer makes every ghost of its "
                    "colour one easier to exorcise, for every Taoist."},

        {"key": "box", "label": "Tao tokens", "layout": "row", "status": "supply",
         "use": "abilities",
         "pos": [0.85, 0.66, 0.995, 0.82],
         "contents": ["tao_%s:4" % c for c in TAO_KEYS]},
        {"key": "arriving", "label": "Arriving", "layout": "row", "use": "abilities", "pos": [0.005, 0.80, 0.115, 0.98],
         "tooltip": "The ghost just drawn, waiting to be placed."},
    ]
    for n in (1, 2, 3):
        z.append({"key": "bag%d" % n, "layout": "stack", "display": "offscreen",
                  "tags": ["shuffle"], "use": "none",
                  "contents": ["f%d_%s" % (n, f) for f in DIE_FACES]})
    z.append({"key": "curse_bag", "layout": "stack", "display": "offscreen",
              "tags": ["shuffle"], "use": "none",
              "contents": ["c_%s:%d" % (k, n) for k, _, n in CURSE]})
    z.append({"key": "rules", "layout": "stack", "display": "offscreen"})

    z += [
        {"key": "seat_home", "label": "{owner}", "layout": "stack", "status": "board",
         "copies": "per_seat", "pos": []},
        {"key": "figure", "layout": "stack", "status": "board", "use": "abilities",
         "copies": "per_seat", "pos": [],
         "tooltip": "Your Taoist, before it takes its place on the central tile."},
        {"key": "tao", "label": "Tao", "layout": "row", "status": "board",
         "copies": "per_seat", "pos": []},
        {"key": "spent", "label": "Committed", "layout": "row", "status": "board",
         "use": "none", "copies": "per_seat", "pos": [],
         "tooltip": "Tokens put behind this exorcism. They come back if you "
                    "walk away from it."},
        {"key": "held", "label": "Held", "layout": "row", "status": "board",
         "use": "abilities", "copies": "per_seat", "pos": []},
    ]
    z.append({"key": "choices", "label": "{active} may", "layout": "row", "status": "board",
              "tags": ["optional"], "pos": [0.005, 0.02, 0.115, 0.78],
              "tooltip": "What the Taoist whose turn it is may do. One tray for the "
                         "table, because only one of them is ever up."})
    # One rect per seat, in the order the seats are declared.
    for zone in z:
        if zone.get("copies") == "per_seat":
            zone["pos"] = [_seat_rect(zone["key"], i) for i in range(4)]
    return z


# Five zones in a line along each side: across the top and bottom the whole middle is theirs, and down the sides the
# board's own height, so the side seats stack where the others sit abreast. Seats go south, west, north, east. Each
# zone's share of its line, across and then down: a pawn in a strip fifty pixels high needs more of the line than it
# does laid flat.
SEAT_ZONES = [("seat_home", 10, 20), ("figure", 9, 17), ("tao", 36, 23), ("spent", 22, 20), ("held", 23, 20)]


def _seat_rect(key, i):
    across = i % 2 == 0
    lo, hi = (0.12, 0.845) if across else (0.15, 0.85)
    at = lo
    for k, flat, tall in SEAT_ZONES:
        n = (hi - lo - 0.02) * (flat if across else tall) / 100
        if k == key:
            break
        at += n + 0.005
    a, b = round(at, 4), round(at + n, 4)
    if across:
        y0, y1 = (0.86, 0.98) if i == 0 else (0.02, 0.14)
        return [a, y0, b, y1]
    x0, x1 = (0.12, 0.2675) if i == 1 else (0.6975, 0.845)
    return [x0, a, x1, b]


# --------------------------------------------------------------------------
# Shared abilities, written once on a tag


def roll_tao():
    """Three dice, each out of its own bag, so two of a colour is possible.

    A pile does not answer `count:` by its top card alone, so a die is a bag of
    six faces and the face it shows is the one card lying in `dice` wearing that
    die's tag. Rolling is: send last turn's face home, shuffle, deal one.
    """
    out = []
    for n in (1, 2, 3):
        out.append("move:dice.d%d:bag%d" % (n, n))
    for n in (1, 2, 3):
        out += ["shuffle:bag%d" % n, "draw_from:bag%d:dice:1" % n]
    return out


def roll_curse():
    return ["move:curse:curse_bag", "shuffle:curse_bag", "draw_from:curse_bag:curse:1"]


def haunt_steps():
    """The six rules that turn "this ghost haunts" into a tile going dark.

    `to_haunt` is the whole interface: a haunting figure reaching the board, a
    Curse die, or a ghost's own arrival all set it, and this is the one place
    that reads it. Which tile is the first *active* one in front is three rules
    per axis — nearest first, each one asking that the ones before it are
    already dark — and a ghost with nowhere left to haunt keeps its `to_haunt`,
    which is how the village falls.
    """
    out = []
    for axis, pat, off in (("v", "vert", (1, 3)), ("h", "horiz", (0, 2))):
        for d in (1, 2, 3):
            needs = ["to_haunt@self >= 1",
                     "board@self != %d" % off[0], "board@self != %d" % off[1]]
            for near in range(1, d):
                needs.append("haunted@%s%d >= 1" % (pat, near))
            needs.append("haunted@%s%d == 0" % (pat, d))
            out.append({"key": "haunt_%s%d" % (axis, d), "needs": needs,
                        "action": ["stat_gain:haunted@%s%d:1" % (pat, d),
                                   "stat_set:to_haunt@self:0"]})
    return out


def tags():
    t = {}

    # Every ghost: which board it stands on, so a Yin phase can ask whether it
    # is the one being played. Four rules writing four numbers, because a
    # condition has no "or" and needs none here.
    stamp = []
    for name, _c, side, _p, _pat in SIDES:
        stamp.append({"key": "stamp_" + name, "needs": ON_BOARD[name][0].replace("@target", "@self"),
                      "action": ["stat_set:board@self:%d" % side]})
    t["ghost"] = {
        "abilities": stamp + haunt_steps() + [
            # The exorcism is two beats: the click marks the ghost, and the
            # aftermath phase does the rest, so a curse still has the ghost
            # standing there to be about.
            {"key": "death_go", "needs": ["dying@self >= 1"], "action": ["destroy:self"]},
        ],
    }

    t["haunter"] = {"abilities": [
        {"key": "haunt_step", "needs": ["board@self == side@mine.player", "haunt@self <= 1"],
         "action": ["stat_gain:haunt@self:1"]},
        {"key": "haunt_strike", "needs": ["board@self == side@mine.player", "haunt@self >= 2"],
         "action": ["stat_set:haunt@self:0", "stat_gain:to_haunt@self:1"]},
    ]}

    # A tormentor rolls the Curse die in its own Yin phase, one ghost at a time:
    # `rolling` on the seat is the baton, so three tormentors on one board are
    # three rolls rather than one shared between them.
    t["tormentor"] = {"abilities": [
        {"key": "curse_roll",
         "needs": ["board@self == side@mine.player", "rolled@self == 0",
                   "rolling@mine.player == 0"],
         "action": roll_curse() + ["stat_set:rolled@self:1", "stat_set:rolls@self:1",
                                   "stat_set:rolling@mine.player:1"]},
    ] + curse_effects("rolls")}

    t["dying_curse"] = {"abilities": [
        {"key": "death_roll", "needs": ["dying@self >= 1"],
         "action": roll_curse() + ["stat_set:rolls@self:1"]},
    ]}

    return t


def curse_effects(flag):
    """What the face lying in `curse` does, read by the ghost that rolled it."""
    return [
        {"key": "curse_qi", "needs": ["%s@self >= 1" % flag, "count:c_qi@curse >= 1"],
         "action": ["stat_damage:qi@mine.player:1"]},
        {"key": "curse_tao", "needs": ["%s@self >= 1" % flag, "count:c_tao@curse >= 1"],
         "action": ["purge:mine.tao"]},
        {"key": "curse_ghost", "needs": ["%s@self >= 1" % flag, "count:c_ghost@curse >= 1"],
         "action": ["stat_gain:incoming@mine.player:1"]},
        {"key": "curse_haunt", "needs": ["%s@self >= 1" % flag, "count:c_haunt@curse >= 1"],
         "action": ["stat_gain:to_haunt@self:1"]},
        {"key": "curse_done", "needs": ["%s@self >= 1" % flag],
         "action": ["stat_set:%s@self:0" % flag, "stat_set:rolling@mine.player:0"]},
    ]


# --------------------------------------------------------------------------
# Cards

STONE = {"L": 0, "M": 1, "R": 2}


def seat_cards():
    """The four Taoists as seats.

    Each one carries the handover, because an **automatic** phase does not turn
    the seat over: `seat: "next"` is read where a hand is dealt, and a phase
    that deals nothing never gets there. A Yin phase is the ghosts acting and
    asks the player nothing, so the turn has to be passed by an action, and the
    only action that names a seat is `set_active_seat`. Whom it names is the one
    thing a seat always knows, so each card says who follows it.
    """
    out = []
    order = [s[0] for s in SIDES]
    for i, (name, colour, side, _p, _pat) in enumerate(SIDES):
        after = order[(i + 1) % len(order)]
        out.append({
            "key": name, "text": name.capitalize(),
            "tags": [name + "_seat", "seat_plate"],
            "asset": "circle:" + _plate(colour),
            "card_stats": {"side": side},
            "tooltip": "The %s Taoist, guarding the %s board." % (name, colour),
            "abilities": [{"key": "handover", "action": ["set_active_seat:%s_seat" % after]}],
        })
    return out


def _plate(colour):
    return {"yellow": "gold", "blue": "blue", "green": "green", "red": "crimson"}[colour]


def monks():
    """One Taoist template, not four. A `per_seat` zone deals a card declared
    once into every seat's copy, and whose it is comes from the zone it lands
    in — so four figures, four owners, one card to read.
    """
    return [{
        "key": "monk", "text": "{owner}'s Taoist",
        "tags": ["taoist", "piece"], "asset": "taoist",
        "tooltip": "Your Taoist. It stands on a village tile, walks to any tile beside "
                   "that one, and exorcises the ghost space in front of it.",
        "abilities": [
            {"key": "station", "phases": ["station"],
             "target": {"type": "card", "count": 1, "tags": ["centre_tile"]},
             "action": ["attach_to_target", "end_phase"]},
            {"key": "step", "phases": ["yang_move"],
             "needs": ["moved@mine.player == 0"],
             "target": {"type": "card", "count": 1, "tags": ["village"],
                        "where": ["count:taoist@mine.attached_to.adjacent >= 1"]},
             "action": ["attach_to_target", "stat_set:moved@mine.player:1", "end_phase"]},
        ],
    }]


def plaques():
    out = []
    for name, colour, side, square, pat in SIDES:
        out.append({
            "key": "plaque_" + name, "text": name.capitalize() + " board",
            "tags": ["plaque"], "asset": "square:" + _plate(colour),
            "tooltip": "The %s board: the three ghost spaces beside this plaque. Ask the "
                       "Night Watchman here to send this board's haunting figures home." % colour,
            "abilities": [
                {"key": "overrun", "needs": ["count@mine.self >= 1", "count:ghost@%s >= 3" % pat],
                 "action": ["stat_damage:qi@mine.player:1", "stat_set:skip@mine.player:1"]},
                {"key": "watch", "phases": ["yang_act"],
                 "needs": ["count:taoist@mine.attached_to.watchman >= 1",
                           "haunted@watchman == 0", "acted@mine.player == 0"],
                 "action": ["stat_set:haunt@%s:0" % pat,
                            "spend_action"]},
            ],
        })
    return out


def _villager(key, needs, action, target=None):
    rule = {"key": "ask", "phases": ["yang_act"],
            "needs": ["count:taoist@mine.attached_to.self >= 1", "haunted@self == 0",
                      "acted@mine.player == 0"] + needs,
            "action": action + ["spend_action"]}
    if target:
        rule["target"] = target
    return rule


def village():
    """The nine tiles. Each one is a card standing on a square of the village,
    and asking its villager is an ability the tile offers to whoever is standing
    on it. A haunted tile offers nothing, which is the whole of turning it over.
    """
    powers = {
        "cemetery": _villager(
            "cemetery", [],
            ["stat_set:qi@target:2"] + roll_curse() + ["stat_set:rolls@self:1"],
            {"type": "card", "count": 1, "tags": ["player"], "where": ["qi@target == 0"]}),
        "altar": _villager(
            "altar", [],
            ["stat_set:haunted@target:0", "stat_gain:incoming@mine.player:1"],
            {"type": "card", "count": 1, "tags": ["village"], "where": ["haunted@target >= 1"]}),
        "herbalist": _villager(
            "herbalist", [],
            ["move:dice.d3:bag3"] + roll_tao()[3:5] + ["draw_from:bag1:dice:1",
                                                       "shuffle:bag2", "draw_from:bag2:dice:1",
                                                       "stat_set:rolls@self:1"]),
        "sorcerer": _villager(
            "sorcerer", [],
            ["purge:target", "stat_damage:qi@mine.player:1"],
            {"type": "card", "count": 1, "tags": ["ghost"], "zones": ["table"]}),
        "temple": _villager(
            "temple", ["count@shrine >= 1"], ["move:shrine:mine.held:1"]),
        "watchman": None,
        "circle_tile": _villager(
            "circle_tile", [], ["purge:circle", "stat_gain:owed_c@mine.player:1"]),
        "pavilion": _villager(
            "pavilion", ["count:ghost@table >= 1"], ["stat_set:blowing@mine.player:1"]),
        "tea_house": _villager(
            "tea_house", [], ["stat_gain:owed@mine.player:1", "stat_gain:qi@mine.player:1",
                              "stat_gain:incoming@mine.player:1"]),
    }
    out = []
    for key, name, text in TILES:
        tags = ["village", key]
        if key == CENTRE_TILE:
            tags.append("centre_tile")
        card = {"key": "t_" + key, "text": name, "tags": tags,
                "asset": "t_" + key, "story": text, "tooltip": text}
        rules = []
        if powers[key]:
            rules.append(powers[key])
        if key == "cemetery":
            # The Curse die rolled at a graveside is about the graveside: a
            # haunting face turns this very tile over, which is the one place
            # the die is not about a ghost.
            rules += [
                {"key": "curse_qi", "needs": ["rolls@self >= 1", "count:c_qi@curse >= 1"],
                 "action": ["stat_damage:qi@mine.player:1"]},
                {"key": "curse_tao", "needs": ["rolls@self >= 1", "count:c_tao@curse >= 1"],
                 "action": ["purge:mine.tao"]},
                {"key": "curse_ghost", "needs": ["rolls@self >= 1", "count:c_ghost@curse >= 1"],
                 "action": ["stat_gain:incoming@mine.player:1"]},
                {"key": "curse_haunt", "needs": ["rolls@self >= 1", "count:c_haunt@curse >= 1"],
                 "action": ["stat_gain:haunted@self:1"]},
                {"key": "curse_done", "needs": ["rolls@self >= 1"],
                 "action": ["stat_set:rolls@self:0"]},
            ]
        if key == "herbalist":
            for c in TAO_KEYS:
                rules.append({"key": "herb_" + c,
                              "needs": ["rolls@self >= 1", "count:%s@dice >= 1" % c],
                              "action": ["take:box.%s:mine.tao:1" % c]})
            rules.append({"key": "herb_white",
                          "needs": ["rolls@self >= 1", "count:white@dice >= 1"],
                          "action": ["stat_gain:owed@mine.player:count:white@dice"]})
            rules.append({"key": "herb_done", "needs": ["rolls@self >= 1"],
                          "action": ["stat_set:rolls@self:0"]})
        if rules:
            card["abilities"] = rules
        out.append(card)
    return out


def ghost_card(key, name, colour, res, left, mid, right, incarnation=False):
    """One ghost. Its colour and its resistance are printed into the one
    condition that matters — what an exorcism has to be worth — because a
    condition cannot be handed a number off the card it is about.
    """
    tags = ["ghost", colour + "_ghost"]
    if incarnation:
        tags.append("incarnation")
    icons = left + mid + right
    if "HAUNTER" in mid:
        tags.append("haunter")
    if "CURSE" in mid:
        tags.append("tormentor")
    if "CURSE" in right:
        tags.append("dying_curse")
    for icon, tag in (("DICE_OFF", "dice_off"), ("POWER_OFF", "power_off"),
                      ("TAO_OFF", "tao_off"), ("DIE_CAPTIVE", "die_captive")):
        if icon in icons:
            tags.append(tag)

    prefix = "token_" if "DICE_OFF" in icons else "power_"
    if colour == "multi":
        want = MULTI[key]
        powers = [prefix + c for c in TAO_KEYS if c in want]
        needs = ["%s%s >= %d" % (prefix, c, n) for c, n in want.items()]
    else:
        powers = [prefix + colour]
        needs = ["%s%s >= %d" % (prefix, colour, res)]
    # Howling Nightmare may only be exorcised while the space facing it across
    # the village is empty. The pattern for the other axis names nothing from
    # where it stands, so both may be asked and only one of them is about it.
    if key == "howling":
        needs += ["count:ghost@vert4 == 0", "count:ghost@horiz4 == 0"]
    rules = [{
        "key": "exorcise", "phases": ["yang_exorcise"], "compute": powers,
        "needs": ["count:taoist@mine.attached_to.orthogonal >= 1"] + needs,
        "action": ["drive_out"],
    }]

    arrive = []
    if "G" in left:
        arrive.append("stat_gain:incoming@mine.player:1")
    if "H" in left:
        arrive.append("stat_gain:to_haunt@self:1")
    if "QI_LOSS" in left:
        arrive.append("stat_damage:qi@mine.player:1")
    if "GROUP_TAO" in left:
        arrive.append("each_seat:purge:random.mine.tao:1")
    if "CIRCLE_OFF" in left:
        arrive.append("purge:circle")
    if arrive:
        rules.append({"key": "arrive", "needs": ["fresh@self >= 1"], "action": arrive})

    reward = []
    if "R_QI" in right:
        reward.append("stat_gain:boons@mine.player:1")
    if "R_TAO" in right:
        reward.append("stat_gain:owed@mine.player:1")
    if "R_TAO2" in right:
        reward.append("stat_gain:owed@mine.player:2")
    if incarnation:
        reward += ["stat_gain:qi@mine.player:1", "stat_set:yy@mine.player:1"]
    if reward:
        rules.append({"key": "reward", "needs": ["dying@self >= 1"], "action": reward})

    if "GROUP_TAO" in mid:
        rules.append({"key": "yin_tithe", "needs": ["board@self == side@mine.player"],
                      "action": ["each_seat:purge:random.mine.tao:1"]})

    card = {
        "key": ("i_" if incarnation else "g_") + key,
        "text": name, "tags": tags,
        "asset": ("i_" + key) if incarnation else _slug(name),
        # `col` and `row` are the engine's to write and the card's to opt into,
        # and a ghost cannot say which board it stands on without them.
        "card_stats": dict({"col": 0, "row": 0}, **({"haunt": 1} if "QUICK" in left else {})),
        "story": _ghost_text(colour, res, icons),
        "tooltip": _ghost_text(colour, res, icons),
        "abilities": rules,
    }
    return card


# --------------------------------------------------------------------------
# The art

# Every picture is a public-domain Chinese painting from Wikimedia Commons, held
# in game/games/assets and credited there. The file a card wears is its name and
# nothing else — `gs_<ghost>.jpg`, `gs_i_<incarnation>.jpg`, `gs_t_<tile>.jpg` —
# so there is no table here to fall out of step with the directory.
#
# **Which painting a ghost wears is arbitrary.** Forty-one named ghosts cannot be
# matched one to one against a Ming scroll, so they are dealt out of one coherent
# set (the Water-Land ritual paintings of Baoning Temple) in the order the cards
# are printed. The incarnations get the Ten Kings of Hell, the Taoists get Zhong
# Kui the demon-queller (Shoki in Japanese hands), and the nine village tiles get
# details of the town in *Along the River During the Qingming Festival*, each
# chosen for the nearest scene.
#
# **The colour plate stays at the end of every list.** A game that arrives over
# the network carries the JSON and not the assets folder, and a red ghost drawn
# as a generated squiggle has lost the one thing about it a player reads first.


def _slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def assets():
    out = {}
    for _key, name, colour, *_rest in G:
        out[_slug(name)] = {"src": ["gs_%s.jpg" % _slug(name), "square:" + _ghost_plate(colour)]}
    for key, _name, colour, *_rest in INC:
        out["i_" + key] = {"src": ["gs_i_%s.jpg" % key, "square:" + _ghost_plate(colour)]}
    for key, _name, _text in TILES:
        out["t_" + key] = {"src": ["gs_t_%s.jpg" % key, "square:sand"]}
    # One name, four pictures: the Taoist card is declared once and dealt into
    # every seat, so whose it is has to pick the painting.
    out["taoist"] = {"per_player": [["gs_taoist_%s.jpg" % s[0], "triangle:sand"] for s in SIDES]}
    return out


def _ghost_plate(colour):
    return {"yellow": "gold", "blue": "blue", "green": "green",
            "red": "crimson", "black": "slate", "multi": "violet"}[colour]


def _ghost_text(colour, res, icons):
    head = "%s, resistance %d." % (colour.capitalize(), res)
    return " ".join([head] + [SAYS[i] for i in icons if i in SAYS])


def ghosts():
    return [ghost_card(*g) for g in G] + [ghost_card(*g, incarnation=True) for g in INC]


def placement():
    """Where a ghost may be laid. Its own colour's board if a space is free,
    and anywhere free if not — which is `aims:`, asked of the first rule by the
    second, so the fallback needs no second copy of "is that board full".
    """
    t = {}
    for name, colour, side, _p, _pat in SIDES:
        t[colour + "_ghost"] = {"abilities": [
            {"key": "place_home", "phases": ["yin_place"],
             "target": {"type": "slot", "count": 1, "zones": ["table"], "fill": "empty",
                        "where": ON_BOARD[name]},
             "action": ["place_ghost"]},
        ]}
    # A black ghost goes to whoever is playing, so its home board is whichever
    # one the active seat sits behind: four rules, one per seat, and only one of
    # them ever has a seat to be about.
    black = []
    for name, _c, side, _p, _pat in SIDES:
        black.append({"key": "place_home_" + name, "phases": ["yin_place"],
                      "needs": ["side@mine.player == %d" % side],
                      "target": {"type": "slot", "count": 1, "zones": ["table"],
                                 "fill": "empty", "where": ON_BOARD[name]},
                      "action": ["place_ghost"]})
    t["black_ghost"] = {"abilities": black}
    t["multi_ghost"] = {"abilities": [dict(b, key=b["key"]) for b in black]}
    return t


def anywhere_rules():
    """The fallback: nowhere free on the board this ghost belongs to, so
    anywhere free will do.

    One rule per seat, because `aims:` is asked of a target spec and not of the
    `needs` that gates it — so a black ghost carrying four placement rules would
    otherwise be told that *somebody else's* board has room. Naming the seat is
    what makes "the board this ghost belongs to" a single question again: a
    coloured ghost carries `place_home` and none of the four, a black one
    carries the four and no `place_home`, and an ability a card does not carry
    answers nought.
    """
    out = []
    for name, _c, side, _p, _pat in SIDES:
        out.append({
            "key": "place_free_" + name, "phases": ["yin_place"],
            "needs": ["side@mine.player == %d" % side, "aims:place_home == 0",
                      "aims:place_home_%s == 0" % name],
            "target": {"type": "slot", "count": 1, "zones": ["table"], "fill": "empty"},
            "action": ["place_ghost"]})
    out += [
        # A Buddha standing on the space eats whatever is laid on it, and goes
        # back to the temple having done its one job.
        {"key": "place_buddha", "phases": ["yin_place"],
         "target": {"type": "card", "count": 1, "tags": ["buddha"], "zones": ["table"]},
         "action": ["move:target:shrine", "purge:self", "end_phase"]},
        # Standing anywhere, a ghost is also what the Pavilion of the Heavenly
        # Wind blows about.
        {"key": "blown", "phases": ["pavilion"],
         "target": {"type": "slot", "count": 1, "zones": ["table"], "fill": "empty"},
         "action": ["move_to:target", "stat_set:blowing@mine.player:0", "end_phase"]},
    ]
    return out


def pieces():
    out = []
    for n in (1, 2, 3):
        for f in DIE_FACES:
            out.append({"key": "f%d_%s" % (n, f), "text": f.capitalize(),
                        "tags": [f, "d%d" % n, "face"],
                        "asset": "circle:" + _face_plate(f)})
    for key, text, _n in CURSE:
        out.append({"key": "c_" + key, "text": text, "tags": ["c_" + key, "curse_face"],
                    "asset": "square:slate", "tooltip": text})
    for key, label, colour in TAO:
        out.append({
            "key": "tao_" + key, "text": label, "tags": [key, "token"],
            "asset": "circle:" + colour,
            "tooltip": "A %s Tao token. Commit it to an exorcism against a %s ghost."
                       % (key, key),
            "play": {"phases": ["yang_exorcise"], "needs": ["count:tao_off@table == 0"],
                     "action": ["move_to:mine.spent"]},
            "abilities": [
                {"key": "take", "phases": ["spoils"], "needs": ["owed@mine.player >= 1"],
                 "action": ["take:self:mine.tao:1", "stat_damage:owed@mine.player:1"]},
                {"key": "pray", "phases": ["prayer"], "needs": ["owed_c@mine.player >= 1"],
                 "action": ["take:self:circle:1", "stat_damage:owed_c@mine.player:1"]},
            ],
        })
    out.append({"key": "buddha", "text": "Buddha", "tags": ["buddha", "piece"],
                "asset": "circle:sand",
                "tooltip": "A mystical trap. Placed on an empty ghost space, it sends "
                           "whatever is laid there straight to hell and goes home.",
                "abilities": [
                    {"key": "set", "phases": ["yang_buddha"],
                     "target": {"type": "slot", "count": 1, "zones": ["table"], "fill": "empty",
                                "where": ["row@target >= 1"]},
                     "action": ["move_to:target", "end_phase"]},
                ]})
    return out


def _face_plate(f):
    return {"yellow": "gold", "green": "green", "red": "crimson", "blue": "blue",
            "black": "slate", "white": "white"}[f]


def buttons():
    def btn(key, text, rule, tip=None):
        c = {"key": key, "text": text, "tags": ["button"], "asset": "square:slate"}
        if tip:
            c["tooltip"] = tip
        c["play"] = rule
        return c
    return [
        btn("no_move", "Stay where you are",
            {"phases": ["yang_move"], "action": ["end_phase"]}),
        btn("no_act", "Do nothing this turn",
            {"phases": ["yang_act"], "action": ["end_phase"]}),
        btn("no_buddha", "End your turn",
            {"phases": ["yang_buddha"], "action": ["end_phase"]}),
        btn("roll_dice", "Attempt an exorcism",
            {"phases": ["yang_act"], "needs": ["acted@mine.player == 0"],
             "action": roll_tao() + ["stat_set:exorcising@mine.player:1",
                                     "spend_action"]},
            "Roll the three Tao dice, then commit tokens and name a ghost you face."),
        btn("give_up", "Leave it be",
            {"phases": ["yang_exorcise"],
             "action": ["move:mine.spent:mine.tao", "stat_set:exorcising@mine.player:0",
                        "end_phase"]},
            "Take back every token you committed and let the ghost stand."),
        btn("use_yy", "Spend your Yin-Yang",
            {"phases": ["yang_move", "yang_act"], "needs": ["yy@mine.player >= 1"],
             "target": {"type": "card", "count": 1, "tags": ["village"],
                        "where": ["haunted@target >= 1"]},
             "action": ["stat_set:haunted@target:0", "stat_damage:yy@mine.player:1"]},
            "Turn one haunted tile back to its active side. The villager comes home."),
        btn("take_qi", "Take 1 Qi",
            {"phases": ["boon"], "action": ["stat_gain:qi@mine.player:1",
                                            "stat_damage:boons@mine.player:1"]}),
        btn("take_yy", "Take your Yin-Yang back",
            {"phases": ["boon"], "needs": ["yy@mine.player == 0"],
             "action": ["stat_set:yy@mine.player:1", "stat_damage:boons@mine.player:1"]}),
    ]


def endings():
    return [
        {"key": "win_page", "text": "Wu-Feng is sent back to hell", "tags": ["page"],
         "story": "The incarnation is exorcised, the urn stays buried, and the village "
                  "wakes to an ordinary morning. The Taoists have won."},
        {"key": "lose_haunt", "text": "The village falls", "tags": ["page"],
         "story": "A fourth location goes dark. The ghosts have Wu-Feng's funerary urn, "
                  "and the world of the living does not exist any more."},
        {"key": "lose_dead", "text": "No one is left to watch", "tags": ["page"],
         "story": "The last Taoist is dead. The village lies quiet under the assault of "
                  "the ghosts."},
        {"key": "lose_deck", "text": "The night never ends", "tags": ["page"],
         "story": "The last ghost card is laid and Wu-Feng is still walking. The village "
                  "will never see daylight again."},
        {"key": "rules_card", "text": "Not in this file yet", "tags": ["page"],
         "story": "Left out of this telling: the two-ghost exorcism from a corner tile; "
                  "Tao tokens lent between Taoists standing on the same tile; the eight "
                  "Taoist powers, and with them the ghosts that switch a power off; "
                  "neutral boards for fewer than four players; the second half of the "
                  "Pavilion of the Heavenly Wind, which moves another Taoist; the "
                  "Yin-Yang spent to ask a distant villager; and the Tao die a ghost "
                  "holds captive. Two incarnations bend rather than break: the "
                  "Uncatchable is exorcised like any other, since a Buddha here eats "
                  "whatever is laid on it, and the Nameless does not stop the white dice "
                  "counting as wild. A resistance printed in several colours spends the "
                  "same white face on each of them. The village tiles are laid out in a "
                  "fixed order rather than shuffled."},
    ]


# --------------------------------------------------------------------------
# The turn

def phases():
    stamps = ["activate_zone:table:by_column:stamp_" + s[0] for s in SIDES]
    hauntings = ["activate_zone:table:by_column:haunt_%s%d" % (a, d)
                 for a in ("v", "h") for d in (1, 2, 3)]
    curses = []
    for _ in range(3):
        curses += ["activate_zone:table:by_column:" + k for k in
                   ("curse_roll", "curse_qi", "curse_tao", "curse_ghost",
                    "curse_haunt", "curse_done")]
    fell = {"when": "max:to_haunt@ghost >= 1", "then": "lost_village"}

    return [
        {"key": "station", "type": "player_input", "zone": "figure", "seat": "next",
         "label": "Take your place on the central tile",
         "ends_when": "count@mine.figure == 0",
         "next": [{"when": "count:taoist@anyone.figure == 0", "then": "turn_end"},
                  {"then": "station", "seat": "next"}]},

        {"key": "yin_stamp", "type": "automatic", "label": "Yin — the ghosts",
         "actions": ["stat_set:moved@mine.player:0", "stat_set:acted@mine.player:0",
                     "stat_set:skip@mine.player:0", "stat_set:incoming@mine.player:0",
                     "stat_set:rolling@mine.player:0", "stat_set:in_yang@mine.player:0",
                     "stat_set:rolled@table.ghost:0"] + stamps,
         "next": [{"then": "yin_ghosts"}]},

        {"key": "yin_ghosts", "type": "automatic", "label": "The ghosts stir",
         "actions": ["activate_zone:table:by_column:haunt_step",
                     "activate_zone:table:by_column:haunt_strike",
                     "activate_zone:table:by_column:yin_tithe"] + curses + hauntings,
         "next": [fell, {"then": "yin_overrun"}]},

        {"key": "yin_overrun", "type": "automatic",
         "actions": ["activate_zone:table:by_column:overrun"],
         "next": [{"when": "qi@mine.player == 0", "then": "turn_end"},
                  {"when": "skip@mine.player >= 1", "then": "yang_move"},
                  {"then": "yin_draw"}]},

        {"key": "yin_draw", "type": "automatic",
         "next": [{"when": "count@deck == 0", "then": "lost_deck"},
                  {"when": "count:ghost@table >= 12", "then": "yin_full"},
                  {"when": "count@deck == 10", "then": "yin_draw_urn"},
                  {"then": "yin_draw_deck"}]},
        {"key": "yin_full", "type": "automatic", "label": "Nowhere left to stand",
         "actions": ["stat_damage:qi@mine.player:1"],
         "next": [{"then": "yang_move"}]},
        {"key": "yin_draw_deck", "type": "automatic",
         "actions": ["draw_from:deck:arriving:1"], "next": [{"then": "yin_place"}]},
        {"key": "yin_draw_urn", "type": "automatic", "label": "Wu-Feng walks",
         "actions": ["draw_from:urn:arriving:1"], "next": [{"then": "yin_place"}]},

        {"key": "yin_place", "type": "player_input", "zone": "arriving",
         "label": "Lay the ghost on a free space",
         "ends_when": "count@arriving == 0",
         "next": [{"then": "yin_arrived"}]},

        {"key": "yin_arrived", "type": "automatic",
         "actions": stamps + ["activate_zone:table:by_column:arrive",
                              "stat_set:fresh@table.ghost:0"] + hauntings,
         "next": [fell,
                  {"when": "incoming@mine.player >= 1", "then": "yin_again"},
                  {"when": "in_yang@mine.player >= 1", "then": "aftermath"},
                  {"then": "yang_move"}]},
        {"key": "yin_again", "type": "automatic",
         "actions": ["stat_damage:incoming@mine.player:1"],
         "next": [{"then": "yin_draw"}]},

        {"key": "yang_move", "type": "player_input", "label": "Yang — move, or stay",
         "zone": ["choices", "table"],
         "actions": ["stat_set:in_yang@mine.player:1"],
         "next": [{"then": "yang_act"}]},

        {"key": "yang_act", "type": "player_input",
         "label": "Ask a villager, or attempt an exorcism",
         "zone": ["choices", "table"],
         "next": [{"when": "exorcising@mine.player >= 1", "then": "yang_exorcise"},
                  {"then": "aftermath"}]},

        {"key": "yang_exorcise", "type": "player_input",
         "label": "Commit Tao tokens, then name the ghost",
         "zone": ["choices", "tao", "table"],
         "next": [{"then": "aftermath"}]},

        {"key": "aftermath", "type": "automatic", "label": "What the ghost leaves behind",
         "actions": ["activate_zone:table:by_column:death_roll",
                     "activate_zone:table:by_column:curse_qi",
                     "activate_zone:table:by_column:curse_tao",
                     "activate_zone:table:by_column:curse_ghost",
                     "activate_zone:table:by_column:curse_haunt",
                     "activate_zone:table:by_column:curse_done"]
                    + ["activate_zone:table:by_column:herb_" + c for c in TAO_KEYS]
                    + ["activate_zone:table:by_column:herb_white",
                       "activate_zone:table:by_column:herb_done",
                       "activate_zone:table:by_column:reward",
                       "activate_zone:table:by_column:death_go",
                       "purge:mine.spent",
                       "stat_set:exorcising@mine.player:0"] + hauntings,
         "next": [fell,
                  {"when": "blowing@mine.player >= 1", "then": "pavilion"},
                  {"when": "owed@mine.player >= 1", "then": "spoils"},
                  {"when": "owed_c@mine.player >= 1", "then": "prayer"},
                  {"when": "boons@mine.player >= 1", "then": "boon"},
                  {"when": "incoming@mine.player >= 1", "then": "yin_again"},
                  {"then": "yang_buddha"}]},

        {"key": "pavilion", "type": "player_input", "zone": "table",
         "label": "Blow a ghost to a free space",
         "ends_when": "blowing@mine.player == 0", "next": [{"then": "aftermath"}]},
        {"key": "spoils", "type": "player_input", "zone": "box",
         "label": "Take your Tao tokens",
         "ends_when": "owed@mine.player == 0", "next": [{"then": "aftermath"}]},
        {"key": "prayer", "type": "player_input", "zone": "box",
         "label": "Put a token on the Circle of Prayer",
         "ends_when": "owed_c@mine.player == 0", "next": [{"then": "aftermath"}]},
        {"key": "boon", "type": "player_input", "zone": "choices",
         "label": "Qi, or your Yin-Yang back",
         "ends_when": "boons@mine.player == 0", "next": [{"then": "aftermath"}]},

        {"key": "yang_buddha", "type": "player_input",
         "label": "Place a Buddha, or end your turn",
         "zone": ["choices", "held", "table"],
         "next": [{"then": "turn_end"}]},

        {"key": "turn_end", "type": "automatic",
         "actions": ["stat_set:in_yang@mine.player:0",
                     "activate_zone:mine.seat_home:by_column:handover"],
         "next": [{"then": "yin_stamp", "ends_round": True}]},

        {"key": "lost_village", "type": "automatic", "actions": ["reveal:lose_haunt"],
         "next": [{"then": "over"}]},
        {"key": "lost_deck", "type": "automatic", "actions": ["reveal:lose_deck"],
         "next": [{"then": "over"}]},
        {"key": "lost_dead", "type": "automatic", "actions": ["reveal:lose_dead"],
         "next": [{"then": "over"}]},
        {"key": "won", "type": "automatic", "actions": ["reveal:win_page"],
         "next": [{"then": "over"}]},
        {"key": "over", "type": "player_input", "label": "The night is over",
         "next": [{"then": "over"}]},
    ]


def setup():
    place = [{"card": s[0], "zone": "seat_home"} for s in SIDES]
    place.append({"card": "monk", "zone": "figure"})
    for (key, _n, _t), square in zip(TILES, VILLAGE):
        place.append({"card": "t_" + key, "zone": "table", "at": square})
    for name, _c, _s, square, _pat in SIDES:
        place.append({"card": "plaque_" + name, "owner": name, "zone": "table", "at": square})
    for key in ("no_move", "no_act", "roll_dice", "use_yy", "give_up",
                "take_qi", "take_yy", "no_buddha"):
        place.append({"card": key, "zone": "choices"})
    place.append({"card": "buddha", "zone": "shrine"})
    place.append({"card": "buddha", "zone": "shrine"})
    place.append({"card": "rules_card", "zone": "rules"})
    return {"place": place}


# The game's own actions, each written once.
VERBS = [
    # Marked rather than removed: the sweep after the exorcism resolves the dead.
    {"key": "drive_out", "tooltip": "This ghost is exorcised.",
     "action": ["stat_set:dying@self:1", "end_phase"]},
    {"key": "place_ghost", "tooltip": "The ghost takes the chosen space, and has only just arrived.",
     "action": ["move_to:target", "stat_set:fresh@self:1", "end_phase"]},
    {"key": "spend_action", "tooltip": "The Taoist has used their action for this Yang phase.",
     "action": ["stat_set:acted@mine.player:1", "end_phase"]},
]


def build():
    t = tags()
    t.update(placement())
    t["ghost"]["abilities"] = t["ghost"]["abilities"] + anywhere_rules()
    return {
        "title": "Ghost Stories",
        "seed": 9,
        "verbs": VERBS,
        "comment": "Antoine Bauza's cooperative game, four seats at Initiation level. "
                   "The village and the four player boards are one 5x5 grid, which is "
                   "what makes 'the space in front of your tile' a pattern rather than a "
                   "table of coordinates, and every pattern here names both directions "
                   "because the engine turns y round for every seat but the first. "
                   "What the file does not say yet is on the 'Not in this file yet' card.",
        "players": [{"card": s[0]} for s in SIDES],
        "styles": {
            "seat_plate": {"badges": ["qi", "yy"]},
            "piece": {"hide": ["title", "border", "plate"]},
            "face": {"hide": ["title"]},
        },
        "assets": assets(),
        "patterns": patterns(),
        "computes": computes(),
        "stats": stats(),
        "tags": t,
        "zones": zones(),
        "phases": phases(),
        "end_conditions": [
            {"when": "count:incarnation@hell >= 1", "then": ["push_phase:won"]},
            {"when": "max:qi@player <= 0", "then": ["push_phase:lost_dead"]},
            {"when": "sum:haunted@village >= 4", "then": ["push_phase:lost_village"]},
        ],
        "cards": (seat_cards() + monks() + plaques() + village() + ghosts()
                  + pieces() + buttons() + endings()),
        "setup": setup(),
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = guard.destination(os.path.join(here, "..", "game", "games", "ghost_stories.json"))
    if out is None:
        sys.exit(1)
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
