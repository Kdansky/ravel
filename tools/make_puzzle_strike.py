#!/usr/bin/env python3
"""Generate game/games/puzzle_strike.json.

Puzzle Strike is two decks per player, not one: a bag/hand/discard cycle that
buys and builds, and a gem pile that never shuffles and holds the whole loss
condition. Everything here is that shape — the bank as a grid of counted
stacks, six zones per seat, and a turn that antes, acts, buys and cleans up.

The rules are transcribed in ideas/puzzle_strike/rules.md and the components in
ideas/puzzle_strike/chips.md, both from the owner's third-edition set; nothing
here invents a chip. Two seats, which is the mode the rulebook itself calls the
tournament default.

    python3 tools/make_puzzle_strike.py
"""

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt

# **South first, and south is the near edge.** A per-seat zone takes one rect
# per seat in seat order, so seat one's rect is the first in every list below —
# and seat one is who the game hands the first turn to. At one screen that is
# the person sitting in front of it, which is the bottom of the board. Written
# the other way round, the opening pick is made for the player across the table
# and everything after it reads inside out.
SEATS = [("south", "South"), ("north", "North")]
HAND = 5
LOSE_AT = 10

# --- the bank -------------------------------------------------------------
#
# A stack is one plate carrying how many are left, and buying is the plate's
# own ability: it spends money, a buy and one of the stock, and creates the
# chip in the buyer's discard. Splendor's token piles are the same idiom, and
# it is what makes Panic Time free — an empty stack is a computed tag.
#
# key, printed name, cost, stock in the box, asset.
GEMS = [(1, 1, 64), (2, 3, 20), (3, 5, 16), (4, 7, 12)]
PURPLES = [
    ("combine",      "Combine",          4, 20),
    ("crash_gem",    "Crash Gem",        5, 16),
    ("double_crash", "Double Crash Gem", 9, 10),
]

# Ten of the twenty-four Puzzle chip designs go into the bank in any one game
# (rules.md §3), and this is the ten. Each is transcribed in chips.md; the
# comment after one says what its printed text asks for that is not built yet.
PUZZLE = [
    ("risky_move",      "Risky Move",      1, "brown"),
    ("really_annoying", "Really Annoying", 1, "red"),
    ("draw_three",      "Draw Three",      3, "brown"),
    ("recklessness",    "Recklessness",    3, "brown"),
    ("sneak_attack",    "Sneak Attack",    3, "red"),
    ("gem_essence",     "Gem Essence",     3, "brown"),
    ("one_two_punch",   "One-Two Punch",   4, "brown"),
    ("one_of_each",     "One of Each",     5, "brown"),
    ("roundhouse",      "Roundhouse",      6, "brown"),
    ("combo_time",      "It's Combo Time", 8, "brown"),
]
PUZZLE_STOCK = 5

BANNER = {"brown": "tan", "red": "red", "blue": "blue", "purple": "magenta"}


def gem_key(n):
    return "gem_%d" % n


def stack_key(chip):
    return "stack_" + chip


# --- characters -----------------------------------------------------------
#
# Every starting deck is the same ten chips but three: 3 character chips, a
# Crash Gem and six 1-gems (rules.md §4). Only the three change, which is why
# choosing one is a draft over a shared roster rather than five game files.
#
# Five of the ten base characters have all three chips photographed; the other
# five are listed in chips.md under *Incomplete* and are not offered here.
CHARACTERS = [
    ("argagarg", "Argagarg", "teal",
     "Defensive disruption: wounds that clog an opponent's bag, and a ward that taxes the whole table.",
     ["hex_of_murkwood", "bubble_shield", "protective_ward"]),
    ("jaina", "Jaina", "crimson",
     "Rushdown: burn your own wounds for tempo, ante gems at the other side, and finish with an uncounterable double crash.",
     ["playing_with_fire", "burning_vigor", "unstable_power"]),
    ("midori", "Midori", "green",
     "An economy engine: trash the chips you have outgrown and buy bigger gems into your hand.",
     ["dragon_form", "rigorous_training", "purge_bad_habits"]),
    ("setsuki", "Setsuki", "amber",
     "Speed: more actions, more buys, more chips, every turn.",
     ["double_take", "bag_of_tricks", "speed_of_the_fox"]),
    ("lum", "Lum", "white",
     "A gambler happiest near the edge — the fuller your gem pile, the more you draw.",
     ["living_on_the_edge", "pandas_bargain", "jackpot"]),
    ("grave", "Grave", "navy",
     "A generalist who takes whatever the turn needs, and answers a crash with a crash.",
     ["reversal", "martial_mastery", "versatile_style"]),
    ("rook", "Rook", "ash",
     "Stone: turn small gems into big ones and hand the incoming ones straight back.",
     ["stone_wall", "big_rocks", "strength_of_earth"]),
    ("degrey", "DeGrey", "pink",
     "A talker: thin your own deck, make the other player answer questions, and take what falls out.",
     ["pilebunker", "no_more_lies", "troublesome_rhetoric"]),
    ("valerie", "Valerie", "cyan",
     "A painter of options — every chip is a choice, and one of them is another whole turn.",
     ["burst_of_speed", "chromatic_orb", "creative_thoughts"]),
    ("geiger", "Geiger", "yellow",
     "Time: put the chips you want back where you will draw them, and pull the ones you need out of the past.",
     ["research_development", "future_sight", "its_time_for_the_past"]),
]


# --- what the chips say ---------------------------------------------------
#
# Printed text, verbatim from ideas/puzzle_strike/chips.md, which is the owner's
# third-edition set. Keeping it word for word matters more than it looks: a
# paraphrase reads fine until somebody compares it with the chip in their hand
# and cannot tell whether the difference is a typo or a rule.
#
# The second entry is the **DEV note**, and it is the only thing here that is
# not on the physical chip. It goes at the end after a blank line, so the
# printed words are never interrupted by ours — an aside in the middle of a
# rule is the fastest way to make a rule unreadable.
#
# The third is what the chip wears on its face. A printed chip says what it
# gives in symbols and reads at arm's length; a paragraph in a forty-pixel band
# does not. These are those symbols.
TEXT = {
    "gem_1": ("A gem worth 1.", None, {}),
    "gem_2": ("A gem worth 2.", None, {}),
    "gem_3": ("A gem worth 3.", None, {}),
    "gem_4": ("A gem worth 4.", None, {}),

    "combine": ("Combine two gems in your gem pile into one, if the total is 4 or less. \u2212$1. +1 action",
                None, {"plus_act": 1}),
    "crash_gem": ("Break one gem in your gem pile and send that many 1-gems to a chosen opponent. +$1",
                  None, {"plus_pow": 1}),
    "double_crash": ("As Crash Gem, up to two gems. +$2", None, {"plus_pow": 2}),
    "wound": ("This chip does nothing.",
              "it is free, and it is the only thing you can always afford: you must buy something every turn.",
              {}),

    "risky_move": ("Put a gem from your hand into your gem pile. If you do, gain a gem of 1 higher value and +$3.",
                   None, {"plus_pow": 3}),
    "really_annoying": ("Main: Each opponent gains a wound. Reaction: The player who red-attacked you gains a wound.",
                        "the reaction half needs a chip played out of turn, which the engine refuses. Only the main half is built.",
                        {"hits": 1, "react": 1}),
    "draw_three": ("+3 chips", None, {"plus_draw": 3}),
    "recklessness": ("+4 actions. Gain a wound.", None, {"plus_act": 4}),
    "sneak_attack": ("+1 red action. Ante a 1-gem into each opposing gem pile.",
                     "an action restricted to a colour is not built; the red action arrives as a plain one.",
                     {"plus_act": 1, "hits": 1}),
    "gem_essence": ("Trash a gem from your hand. If you do, +1 yellow action, +1 purple action, +1 red action, +1 blue action.",
                    "actions restricted to a colour are not built; the four arrive as four plain actions.",
                    {"plus_act": 4}),
    "one_two_punch": ("+2 actions", None, {"plus_act": 2}),
    "one_of_each": ("+1 action, +1 buy, +$1, +1 chip", None,
                    {"plus_act": 1, "plus_buy": 1, "plus_pow": 1, "plus_draw": 1}),
    "roundhouse": ("+1 action, +2 chips", None, {"plus_act": 1, "plus_draw": 2}),
    "combo_time": ("Put a 1-gem from your hand in your gem pile. If you do, +4 chips, +1 action.",
                   None, {"plus_act": 1, "plus_draw": 4}),

    "hex_of_murkwood": ("+1 blue action. Each opponent gains a wound or discards two wounds.",
                        "which of the two is the opponent's choice and there is no way to ask them yet, so they gain one.",
                        {"plus_act": 1, "hits": 1}),
    "bubble_shield": ("Ongoing: Negate a gem sent to you, then discard this chip. Reaction: Become immune to a red chip.",
                      "both halves are reactions, which need a chip played out of turn. Laying it out says you have it and nothing more.",
                      {"react": 1}),
    "protective_ward": ("+1 blue action. Ongoing: Players can't combine gems unless they discard a Puzzle chip first. "
                        "Discard this at the end of your next action phase.",
                        "the tax on combining is not built; the action it gives is.",
                        {"plus_act": 1}),

    "playing_with_fire": ("Ante a 1-gem. +1 yellow action, +1 red action, +1 chip.",
                          "actions restricted to a colour are not built; the two arrive as two plain ones.",
                          {"plus_act": 2, "plus_draw": 1}),
    "burning_vigor": ("Trash a wound from your hand or discard pile. If you do, +1 action and ante a 1-gem into each opposing gem pile.",
                      "only a wound in hand can be trashed \u2014 a pile is reached from the top.",
                      {"plus_act": 1, "hits": 1}),
    "unstable_power": ("Main or Reaction: Play this as if it were a Double Crash Gem, then gain two wounds.",
                       "the reaction half needs a chip played out of turn, which the engine refuses.",
                       {"plus_pow": 2, "react": 1}),

    "dragon_form": ("Ongoing: Each ante phase, ante a gem of 1 higher than usual, or discard this chip. "
                    "Your purples can't be reacted to. You can't buy purples.",
                    "the bigger ante is built; the other two clauses need reactions, which are not.",
                    {}),
    "rigorous_training": ("Reaction: When an opponent buys a 4-cost or more chip, trash a non-purple chip from your hand "
                          "then gain a chip costing up to 2 more than the trashed chip.",
                          "reactions are not built.",
                          {"react": 1}),
    "purge_bad_habits": ("Trash a chip from your hand. Put a 2-gem from the bank into your hand. "
                         "(Character chips can't be trashed.)", None, {}),

    "double_take": ("Choose a non-Puzzle chip in your hand or discard pile. Play it twice, trash it, then end your action phase.",
                    "playing a chip twice is not built; this gives two actions instead.",
                    {"plus_act": 2}),
    "bag_of_tricks": ("+1 yellow action, +1 buy, +1 chip",
                      "an action restricted to a colour is not built.",
                      {"plus_act": 1, "plus_buy": 1, "plus_draw": 1}),
    "speed_of_the_fox": ("+2 yellow actions, +1 chip",
                         "actions restricted to a colour are not built.",
                         {"plus_act": 2, "plus_draw": 1}),

    "reversal": ("Main: +2 chips. Reaction: Play this as a Crash Gem to counter gems sent to you.",
                 "the reaction needs a chip played out of turn, which the engine refuses.",
                 {"plus_draw": 2, "react": 1}),
    "martial_mastery": ("+1 action. Trash a non-purple chip from your hand then gain a chip costing exactly 2 more.",
                        "comparing two chips' prices is not built, so this trashes and gives the action.",
                        {"plus_act": 1}),
    "versatile_style": ("Choose one: +1 action and +1 buy \u2014 or \u2014 +$2 \u2014 or \u2014 +2 chips.", None, {}),

    "stone_wall": ("Main: +1 chip, +1 buy. Reaction: Reflect any gems sent to a player to the bank. (Just trash them.)",
                   "the reaction needs a chip played out of turn, which the engine refuses.",
                   {"plus_draw": 1, "plus_buy": 1, "react": 1}),
    "big_rocks": ("Trash a gem from your hand, then take a gem of 1 higher value and put it in your hand.", None, {}),
    "strength_of_earth": ("+1 yellow action. Combine a 1-gem from the bank with a gem in your gem pile.",
                          "an action restricted to a colour is not built.",
                          {"plus_act": 1}),

    "pilebunker": ("+1 chip. Opponents reveal their hands, trash their largest gem, then gain that many 1-gems.",
                   "the hand opens and you pick the chip to trash; nothing enforces that it is the largest, "
                   "and nothing stops you picking something that is not a gem, which trashes it for no gems back.",
                   {"plus_draw": 1, "hits": 1}),
    "no_more_lies": ("+1 red action. Trash up to two chips from your hand. (Character chips can't be trashed.)",
                     "an action restricted to a colour is not built.",
                     {"plus_act": 1, "hits": 1}),
    "troublesome_rhetoric": ("Chosen opponent chooses your benefit: +1 action and +1 chip \u2014 OR \u2014 +$2 and +1 buy.",
                             "nothing makes the opponent press the button \u2014 at one screen, hand it over.",
                             {}),

    "burst_of_speed": ("Trash this chip, then take an extra turn after this one.", None, {}),
    "chromatic_orb": ("+1 chip. Crash a 1-gem in your gem pile.", None, {"plus_draw": 1}),
    "creative_thoughts": ("Choose any different two: +1 action / +1 buy / +$1 / +1 chip.", None, {}),

    "research_development": ("+1 action. Exchange a chip in your hand with a purple from your bag.",
                             "searching a shaken bag is not built, so this gives the action and nothing else.",
                             {"plus_act": 1}),
    "future_sight": ("+2 chips. Put two chips from your hand on top of your bag in any order.",
                     "which order they go back in is not yours to say here.",
                     {"plus_draw": 2}),
    "its_time_for_the_past": ("+1 action. Put a non-Puzzle chip from your discard pile into your hand.",
                              "a pile is reached from the top, so this takes the last chip you threw away.",
                              {"plus_act": 1}),

    "living_on_the_edge": ("If your gem pile totals at least 10, +3 chips, +1 action.", None,
                           {"plus_act": 1, "plus_draw": 3}),
    "pandas_bargain": ("Ongoing: At the end of any turn you bought a Puzzle chip, +1 chip. Discard this when you buy a purple.",
                       "the condition is not built; laying it out draws the chip once.",
                       {"plus_draw": 1}),
    "jackpot": ("Reveal two chips at random from chosen opponent's hand. If any are gems, +$1 and +1 action. "
                "If both are purples, play and gain a purple from the bank.",
                "a random reveal is not built and neither is the purple clause; this pays the gem half unconditionally.",
                {"plus_act": 1, "plus_pow": 1}),
}


def say(cards):
    """Put the printed words and the badges onto the cards TEXT names."""
    for c in cards:
        entry = TEXT.get(c["key"])
        if not entry:
            continue
        printed, dev, badges = entry
        c["tooltip"] = printed + ("\n\nDEV: " + dev if dev else "")
        if badges:
            c.setdefault("card_stats", {}).update(badges)
    return cards


# --- layout ---------------------------------------------------------------
#
# One column down the left for everything the table shares, and the rest split
# in half with nothing between: the two players face each other across the
# middle, and each half is the other one upside down.
#
# The bank is a two-wide column rather than a wide strip because a chip is
# taller than it is wide — a row of eighteen plates gives each one a sliver, a
# column of nine pairs gives each one a card shape.
def zones():
    z = [
        # Two readouts nothing else can give: a board shows what is where and
        # says nothing about whose turn it is or which part of it this is.
        {"key": "whose_turn", "label": "current_player", "type": "grid", "grid": [1, 1],
         "pos": [0.005, 0.005, 0.225, 0.045]},
        {"key": "what_now", "label": "current_phase", "type": "grid", "grid": [1, 1],
         "pos": [0.005, 0.049, 0.225, 0.089]},
        # Stopping at 0.82: the lower-left corner is the undo button's and the
        # log's, which is why this column ends above it rather than at the floor.
        {"key": "bank", "label": "Bank", "type": "grid", "grid": [2, 9],
         "tags": ["activate"], "pos": [0.005, 0.095, 0.225, 0.818],
         "tooltip": "Every chip you may buy. A stack says how many are left; when stacks run dry the ante grows."},
        # The two buttons sit on the middle line between the gem piles, where
        # they belong to whoever is up rather than to either side of the table.
        {"key": "controls", "type": "grid", "grid": [2, 1], "tags": ["activate"],
         "pos": [0.808, 0.463, 0.995, 0.537]},
        # The roster is the injected offer, positioned rather than declared: ten
        # characters wants more of the screen than a choice between two.
        {"key": "options", "type": "options", "pos": [0.06, 0.30, 0.94, 0.70]},
        {"key": "box", "type": "deck", "tags": ["hidden"]},
        {"key": "void", "type": "deck", "tags": ["hidden"]},
        # A grid, not a deck: a tag scope only searches grids, and every rule
        # about the ante reads this card's number.
        {"key": "sys", "type": "grid", "grid": [1, 1], "tags": ["hidden"]},
    ]
    # Each rule family is its own hidden zone rather than one zone walked with a
    # step word: a step needs an order named beside it, and these are decks with
    # no columns to order by. One zone per question is cheaper and reads better.
    for key in ("rules_ante", "rules_combine", "rules_upgrade", "rules_upgrade_hand",
                "rules_upgrade_pile", "rules_height"):
        z.append({"key": key, "type": "deck", "tags": ["hidden"]})
    # South below, north above, mirrored through the middle line — and south's
    # rect is first in every pair because south is seat one. Read from the
    # outside in, each seat has: its hand along the outer edge with the discard,
    # the bag and its fighter beside it, then what it played this turn, then
    # what it has standing — and the gem pile down the far side, where the
    # number that ends the game is never covered by anything.
    rects = {
        "hand":     [[0.235, 0.830, 0.560, 0.995], [0.235, 0.005, 0.560, 0.170]],
        "discard":  [[0.568, 0.830, 0.648, 0.995], [0.568, 0.005, 0.648, 0.170]],
        "bag":      [[0.656, 0.830, 0.724, 0.995], [0.656, 0.005, 0.724, 0.170]],
        "fighter":  [[0.732, 0.830, 0.800, 0.995], [0.732, 0.005, 0.800, 0.170]],
        "table":    [[0.235, 0.620, 0.800, 0.822], [0.235, 0.178, 0.800, 0.380]],
        "ongoing":  [[0.235, 0.505, 0.800, 0.612], [0.235, 0.388, 0.800, 0.495]],
        "gem_pile": [[0.808, 0.545, 0.995, 0.995], [0.808, 0.005, 0.995, 0.455]],
    }
    z += [
        # The gem pile is a grid for the same reason the clock is:
        # `sum:value@mine.gem_pile` is the loss condition, the height bonus and
        # half the crash rules, and a scope cannot see a hand.
        {"key": "gem_pile", "label": "Gem pile", "type": "grid", "grid": [4, 5],
         "tags": ["per_seat", "face_up"],
         "pos": rects["gem_pile"],
         "tooltip": "The gems that will end you. Ten or more at the end of your own turn and you lose."},
        # Who you are, which is not something you played: it sits beside your bag
        # rather than in the middle of the table, where it kept claiming the
        # room a chip left standing would need.
        {"key": "fighter", "type": "grid", "grid": [1, 1], "tags": ["per_seat", "face_up"],
         "pos": rects["fighter"]},
        # Chips that stay out after they are played, which is a short list — most
        # turns this is empty, and it is a thin strip for that reason.
        {"key": "ongoing", "label": "In play", "type": "hand", "tags": ["per_seat", "face_up"],
         "pos": rects["ongoing"],
         "tooltip": "Chips that keep working after the turn they were played."},
        {"key": "table", "label": "Played this turn", "type": "hand", "tags": ["per_seat", "face_up"],
         "pos": rects["table"]},
        {"key": "hand", "type": "hand", "tags": ["per_seat"], "pos": rects["hand"]},
        # face_down rather than hidden: a bag you cannot see is a bag you cannot
        # count, and how many chips somebody has left to draw is public.
        {"key": "bag", "label": "Bag", "type": "deck", "tags": ["per_seat", "face_down"],
         "pos": rects["bag"], "refill_from": "discard",
         "tooltip": "Your draw pile. The moment it runs out your discard goes back in and is shaken \u2014 mid-draw, mid-chip, wherever it happens."},
        {"key": "discard", "label": "Discard", "type": "pile", "tags": ["per_seat"], "pos": rects["discard"]},
    ]
    return z


# --- stats ----------------------------------------------------------------
def stats():
    def player(key, label, icon, colour=None, hidden=False, start=0, mx=99):
        s = {"key": key, "min": 0, "max": mx, "on": ["player"], "start": start}
        if hidden:
            s["tags"] = ["hidden"]
        else:
            s["label"] = label
            s["icon"] = icon
            s["subject"] = "%s@mine.player" % key
            if colour:
                s["color"] = colour
        return s

    return [
        # The number the whole game is about, and nothing carries it: it is the
        # gem pile read out loud.
        {"key": "pile", "label": "Gem pile", "icon": "diamond", "color": "green",
         "min": 0, "max": 99, "subject": "sum:value@mine.gem_pile"},
        player("money", "Gem power", "coin", "gold"),
        player("acts", "Actions", "blade", "silver"),
        player("buys", "Buys", "banner", "amber"),
        player("bought", None, None, hidden=True),
        player("to_draw", None, None, hidden=True),
        player("crashed", None, None, hidden=True),
        player("combined", None, None, hidden=True),
        player("extra", None, None, hidden=True),
        player("picked", None, None, hidden=True),
        # On the chips rather than on a seat: a gem says what it is worth, a
        # bank plate says how many are left, and neither is a HUD row.
        #
        # **These are what a chip says in pictures**, and they are stats so the
        # card can wear them. A printed chip tells you what it gives in four
        # symbols and a colour, and reads at arm's length; a paragraph of
        # English in a 40-pixel band does not. The paragraph stays in the
        # tooltip, where the exact words belong.
        {"key": "value", "min": 0, "max": 4, "icon": "diamond", "color": "green", "tags": ["hidden"]},
        {"key": "price", "min": 0, "max": 20, "icon": "coin", "color": "gold", "tags": ["hidden"]},
        {"key": "stock", "min": 0, "max": 99, "icon": "card", "tags": ["hidden"]},
        {"key": "plus_act", "min": 0, "max": 9, "icon": "arrow", "tags": ["hidden"]},
        {"key": "plus_buy", "min": 0, "max": 9, "icon": "banner", "color": "amber", "tags": ["hidden"]},
        {"key": "plus_draw", "min": 0, "max": 9, "icon": "card", "tags": ["hidden"]},
        {"key": "plus_pow", "min": 0, "max": 9, "icon": "coin", "color": "green", "tags": ["hidden"]},
        # A banner shape, not a quantity: the chip either has a reaction half or
        # it does not, and "shield 1" would be a number about nothing.
        {"key": "react", "min": 0, "max": 1, "icon": "shield", "number": False, "tags": ["hidden"]},
        {"key": "hits", "min": 0, "max": 1, "icon": "fist", "number": False, "tags": ["hidden"]},
        {"key": "panic", "min": 0, "max": 9, "tags": ["hidden"]},
    ]


# --- how a chip looks -----------------------------------------------------
#
# A style per banner colour and one for the numbers, keyed by the tags the
# chips already carry. They touch different fields, so a red chip is the red
# plate and the chip badges both without either style knowing about the other.
def styles():
    banner = {"brown": [0.42, 0.33, 0.24], "red": [0.62, 0.22, 0.20],
              "blue": [0.20, 0.36, 0.62], "purple": [0.44, 0.24, 0.56]}
    out = {name: {"color": rgb} for name, rgb in banner.items()}
    out["gem"] = {"color": [0.18, 0.46, 0.34]}
    out["wound"] = {"color": [0.34, 0.14, 0.14]}
    out["chip"] = {"badges": ["value", "plus_pow", "plus_act", "plus_buy", "plus_draw", "hits", "react"],
                   "badge_zeros": False}
    out["stack"] = {"badges": ["price", "stock"], "badge_run": "down", "badge_zeros": False}
    out["character_card"] = {"color": [0.24, 0.26, 0.36]}
    return out


# --- the chips themselves -------------------------------------------------
#
# A gem is money when played out of hand and a millstone when it lands in the
# gem pile, and it is the same chip either way — which is why `value` is a stat
# on the card rather than four different cards' worth of behaviour.
def gem_cards():
    out = []
    for n, cost, _stock in GEMS:
        tags = ["chip", "trashable", "gem", "gem_%d" % n]
        if n < 4:
            tags.append("upgradable")
        out.append({
            "key": gem_key(n), "text": "%d-gem" % n, "tags": tags,
            "asset": "diamond:green",
            "tooltip": "Worth %d. Play it in your buy phase for %d gem power, or let it sit in a gem pile counting against whoever owns it." % (n, n),
            "card_stats": {"value": n},
            "play": {"phases": ["buy"],
                     "action": ["stat_gain:money@mine.player:sum:value@self", "move_to:mine.table"]},
        })
    return out


# Crashing is one rule whatever the gem's size, because the size is a number
# the action reads rather than four actions that each know one: set it, send
# the gem away, then create that many 1-gems in the other pile.
def crash_action(n_targets, bonus):
    return [
        "stat_set:crashed@mine.player:sum:value@target",
        "move_target_to:void",
        "fill:enemy.gem_pile:gem_1:sum:crashed@mine.player",
        "stat_damage:stock@stack_gem_1:sum:crashed@mine.player",
        "stat_gain:money@mine.player:%d" % bonus,
        "move_to:mine.table",
    ]


def purple_cards():
    own_gems = {"type": "card", "tags": ["gem"], "zones": ["gem_pile"], "owner": "anyone"}
    return [
        # "If the total is 4 or less" is a fact about the *pair*, and a `needs`
        # is asked before there is a pair to ask about — so it is a challenge,
        # which is the one condition that sees the targets. Failing it costs
        # nothing: the chip stays in hand and the action comes back.
        {"key": "combine", "text": "Combine", "tags": ["chip", "trashable", "purple"],
         "asset": "diamond:magenta",
         "tooltip": "Merge two gems in your own pile into one, if they total 4 or less. Costs you a gem power, and gives you back the action you spent.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(own_gems, count=2),
                  "action": ["resolve_challenge"]},
         "challenge": {"needs": ["sum:value@target <= 4"],
                       "pass": ["stat_set:combined@mine.player:sum:value@target",
                                "move_target_to:void",
                                "activate_zone:rules_combine",
                                "stat_damage:money@mine.player:1",
                                "stat_gain:acts@mine.player:1",
                                "move_to:mine.table"],
                       "fail": ["stat_gain:acts@mine.player:1"]}},
        {"key": "crash_gem", "text": "Crash Gem", "tags": ["chip", "trashable", "purple"],
         "asset": "circle:magenta",
         "tooltip": "Break one gem in your own pile and send that many 1-gems across the table. A 3-gem becomes three 1-gems in their pile.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(own_gems, count=1),
                  "action": crash_action(1, 1)}},
        {"key": "double_crash", "text": "Double Crash Gem", "tags": ["chip", "trashable", "purple"],
         "asset": "dots:2:magenta",
         "tooltip": "As a Crash Gem, but up to two of your gems at once.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(own_gems, min=1, max=2),
                  "action": crash_action(2, 2)}},
        # No `play` at all, which is what makes it useless: it can be drawn,
        # it fills a hand slot, and there is nothing to do with it.
        {"key": "wound", "text": "Wound", "tags": ["chip", "trashable", "wound"],
         "asset": "circle:crimson",
         "tooltip": "This chip does nothing. It is free, and it is the only thing you can always afford: you must buy something every turn, and this is what is left when nothing else is in reach."},
    ]


# A wound is gained rather than bought when a chip inflicts one, and both go to
# the discard: taking one out of the bank is the same two lines everywhere.
def gain_wound(who="mine"):
    return ["fill:%s.discard:wound:1" % who, "stat_damage:stock@stack_wound:1"]


def puzzle_cards():
    hand_gem = {"type": "card", "tags": ["gem"], "zones": ["hand"], "count": 1, "owner": "anyone"}
    act = lambda extra: {"phases": ["action"], "cost": {"acts@mine.player": 1}, "action": extra + ["move_to:mine.table"]}
    return [
        {"key": "risky_move", "text": "Risky Move", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Put a gem from your hand into your own gem pile — which is the wrong direction — and take a bigger one plus three gem power for the trouble.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_gem, tags=["upgradable"]),
                  "action": ["stat_set:combined@mine.player:sum:value@target",
                             "move_target_to:mine.gem_pile",
                             "activate_zone:rules_upgrade",
                             "stat_gain:money@mine.player:3",
                             "move_to:mine.table"]}},
        {"key": "really_annoying", "text": "Really Annoying", "tags": ["chip", "trashable", "puzzle", "red"],
         "asset": "polygon:6:red",
         "tooltip": "Each opponent gains a wound. (Its reaction half needs playing out of turn, which the engine does not allow yet.)",
         "play": act(gain_wound("enemy"))},
        {"key": "draw_three", "text": "Draw Three", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Draw three chips.",
         "play": act(["draw_from:mine.bag:mine.hand:3"])},
        {"key": "recklessness", "text": "Recklessness", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Four actions, and a wound to pay for them.",
         "play": act(["stat_gain:acts@mine.player:4"] + gain_wound())},
        {"key": "sneak_attack", "text": "Sneak Attack", "tags": ["chip", "trashable", "puzzle", "red"],
         "asset": "polygon:6:red",
         "tooltip": "Ante a 1-gem into each opposing gem pile, and keep your action.",
         "play": act(["stat_gain:acts@mine.player:1",
                      "fill:enemy.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1"])},
        {"key": "gem_essence", "text": "Gem Essence", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Trash a gem out of your hand and take four actions for it.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": hand_gem,
                  "action": ["move_target_to:void", "stat_gain:acts@mine.player:4", "move_to:mine.table"]}},
        {"key": "one_two_punch", "text": "One-Two Punch", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Two actions.",
         "play": act(["stat_gain:acts@mine.player:2"])},
        {"key": "one_of_each", "text": "One of Each", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "An action, a buy, a gem power and a chip — one of each of the four things a chip can give you.",
         "play": act(["stat_gain:acts@mine.player:1", "stat_gain:buys@mine.player:1",
                      "stat_gain:money@mine.player:1", "draw_from:mine.bag:mine.hand:1"])},
        {"key": "roundhouse", "text": "Roundhouse", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Keep your action and draw two chips.",
         "play": act(["stat_gain:acts@mine.player:1", "draw_from:mine.bag:mine.hand:2"])},
        {"key": "combo_time", "text": "It's Combo Time", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Put a 1-gem from your hand into your own gem pile, and it pays for itself: four chips and your action back.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_gem, tags=["gem_1"]),
                  "action": ["move_target_to:mine.gem_pile",
                             "draw_from:mine.bag:mine.hand:4",
                             "stat_gain:acts@mine.player:1",
                             "move_to:mine.table"]}},
    ]


# --- character chips ------------------------------------------------------
#
# Printed text is in chips.md. Where a chip's rule needs something the engine
# cannot say yet — a reaction played out of turn, an ongoing that changes an
# opponent's rules — the buildable half is built and the tooltip says the whole
# printed text, so what is missing is visible at the table rather than only here.
def character_chips():
    act = lambda extra: {"phases": ["action"], "cost": {"acts@mine.player": 1},
                         "action": extra + ["move_to:mine.table"]}
    ongoing = lambda: {"phases": ["action"], "cost": {"acts@mine.player": 1},
                       "action": ["move_to:mine.ongoing"]}
    hand_chip = {"type": "card", "tags": ["chip"], "zones": ["hand"], "count": 1, "owner": "anyone"}
    hand_gem = {"type": "card", "tags": ["gem"], "zones": ["hand"], "count": 1, "owner": "anyone"}
    return [
        # Argagarg
        {"key": "hex_of_murkwood", "text": "Hex of Murkwood", "tags": ["chip", "character", "red"],
         "asset": "polygon:7:teal",
         "tooltip": "+1 blue action. Each opponent gains a wound or discards two wounds. Here they gain one: choosing for them is the opponent's decision, and there is no way to ask yet.",
         "play": act(["stat_gain:acts@mine.player:1"] + gain_wound("enemy"))},
        {"key": "bubble_shield", "text": "Bubble Shield", "tags": ["chip", "character", "blue"],
         "asset": "circle:cyan",
         "tooltip": "Ongoing: negate a gem sent to you, then discard this chip. Reactions are not built yet, so laying it out does nothing but say you have it.",
         "play": ongoing()},
        {"key": "protective_ward", "text": "Protective Ward", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:teal",
         "tooltip": "+1 blue action. Ongoing: nobody may combine without discarding a Puzzle chip first. The tax is not built; the action it gives back is.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:acts@mine.player:1", "move_to:mine.ongoing"]}},
        # Jaina
        {"key": "playing_with_fire", "text": "Playing with Fire", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:crimson",
         "tooltip": "Ante a 1-gem into your own pile, then take two actions and a chip for it.",
         "play": act(["fill:mine.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1",
                      "stat_gain:acts@mine.player:2", "draw_from:mine.bag:mine.hand:1"])},
        {"key": "burning_vigor", "text": "Burning Vigor", "tags": ["chip", "character", "red"],
         "asset": "polygon:7:crimson",
         "tooltip": "Trash a wound out of your hand, and it turns into an action and a gem in every opposing pile.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["wound"]),
                  "action": ["move_target_to:void", "stat_gain:acts@mine.player:1",
                             "fill:enemy.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1",
                             "move_to:mine.table"]}},
        {"key": "unstable_power", "text": "Unstable Power", "tags": ["chip", "character", "purple"],
         "asset": "dots:2:crimson",
         "tooltip": "A Double Crash Gem that costs you two wounds. Its reaction half needs playing out of turn, which is not built.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": {"type": "card", "tags": ["gem"], "zones": ["gem_pile"],
                             "owner": "anyone", "min": 1, "max": 2},
                  "action": crash_action(2, 2) + gain_wound() + gain_wound()}},
        # Midori
        # The panic level is recomputed at the start of every ante, so a seat
        # nudging it after that reads only on its own ante — which is exactly
        # what "each ante phase, ante a gem of 1 higher than usual" means.
        {"key": "dragon_form", "text": "Dragon Form", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:green",
         "tooltip": "Ongoing: ante a gem one higher than usual, your crashes cannot be reacted to, and you cannot buy purples. The bigger ante is built; the other two clauses need reactions, which are not.",
         "abilities": [{"key": "upkeep", "text": "Dragon Form",
                        "action": ["stat_gain:panic@clock:1"]}],
         "play": ongoing()},
        {"key": "rigorous_training", "text": "Rigorous Training", "tags": ["chip", "character", "blue"],
         "asset": "circle:green",
         "tooltip": "Reaction: when an opponent buys a 4-cost chip or more, trade a chip out of your hand for a better one. Reactions are not built yet.",
         "play": ongoing()},
        {"key": "purge_bad_habits", "text": "Purge Bad Habits", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:green",
         "tooltip": "Trash a chip out of your hand and take a 2-gem from the bank straight into it. Character chips cannot be trashed.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"]),
                  "action": ["move_target_to:void",
                             "fill:mine.hand:gem_2:1", "stat_damage:stock@stack_gem_2:1",
                             "move_to:mine.table"]}},
        # Setsuki
        {"key": "double_take", "text": "Double-take", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:amber",
         "tooltip": "Choose a non-Puzzle chip in your hand or discard, play it twice, trash it, then end your action phase. Playing a chip twice is not built; the extra actions are.",
         "play": act(["stat_gain:acts@mine.player:2"])},
        {"key": "bag_of_tricks", "text": "Bag of Tricks", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:amber",
         "tooltip": "An action, a buy and a chip.",
         "play": act(["stat_gain:acts@mine.player:1", "stat_gain:buys@mine.player:1",
                      "draw_from:mine.bag:mine.hand:1"])},
        {"key": "speed_of_the_fox", "text": "Speed of the Fox", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:amber",
         "tooltip": "Two actions and a chip.",
         "play": act(["stat_gain:acts@mine.player:2", "draw_from:mine.bag:mine.hand:1"])},
        # Grave
        {"key": "reversal", "text": "Reversal", "tags": ["chip", "character", "purple"],
         "asset": "circle:navy",
         "tooltip": "Main: two chips. Reaction: play this as a Crash Gem to counter gems sent to you — the reaction needs playing out of turn, which is not built.",
         "play": act(["draw_from:mine.bag:mine.hand:2"])},
        {"key": "martial_mastery", "text": "Martial Mastery", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:navy",
         "tooltip": "Trash a non-purple chip from your hand then gain a chip costing exactly 2 more. Comparing two chips' prices is not built, so this trashes and gives the action back.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": hand_chip,
                  "action": ["move_target_to:void", "stat_gain:acts@mine.player:1",
                             "move_to:mine.table"]}},
        {"key": "versatile_style", "text": "Versatile Style", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:navy",
         "tooltip": "Choose one: an action and a buy, or two gem power, or two chips.",
         "play": act(["options:vs_tempo,vs_money,vs_chips"])},
        # Rook
        {"key": "stone_wall", "text": "Stone Wall", "tags": ["chip", "character", "purple"],
         "asset": "circle:ash",
         "tooltip": "Main: a chip and a buy. Reaction: reflect any gems sent to a player back to the bank — the reaction needs playing out of turn, which is not built.",
         "play": act(["draw_from:mine.bag:mine.hand:1", "stat_gain:buys@mine.player:1"])},
        {"key": "big_rocks", "text": "Big Rocks", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:ash",
         "tooltip": "Trash a gem out of your hand and take one worth a point more straight back into it.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_gem, tags=["upgradable"]),
                  "action": ["stat_set:combined@mine.player:sum:value@target",
                             "move_target_to:void",
                             "activate_zone:rules_upgrade_hand",
                             "move_to:mine.table"]}},
        {"key": "strength_of_earth", "text": "Strength of Earth", "tags": ["chip", "character", "purple"],
         "asset": "polygon:7:ash",
         "tooltip": "Combine a 1-gem out of the bank with a gem already in your pile — which makes your pile heavier, and is the point: bigger gems crash harder.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": {"type": "card", "tags": ["upgradable"], "zones": ["gem_pile"],
                             "owner": "anyone", "count": 1},
                  "action": ["stat_set:combined@mine.player:sum:value@target",
                             "move_target_to:void",
                             "activate_zone:rules_upgrade_pile",
                             "stat_damage:stock@stack_gem_1:1",
                             "stat_gain:acts@mine.player:1",
                             "move_to:mine.table"]}},
        # DeGrey
        # The chip that asked for `show:`. The opponent's hand comes up face up
        # in the offer, the pick is trashed, and they take that many 1-gems back
        # — which is the printed rule with the "largest" left to the reader.
        # Declinable, because a hand with no gem in it has nothing to trash and
        # forcing a pick would trash something the chip never names.
        {"key": "pilebunker", "text": "Pilebunker", "tags": ["chip", "character", "red"],
         "asset": "polygon:7:pink",
         "play": act(["draw_from:mine.bag:mine.hand:1", "show:enemy.hand:optional"]),
         "chosen": {"action": ["stat_set:crashed@mine.player:sum:value@target",
                               "move_target_to:void",
                               "fill:enemy.discard:gem_1:sum:crashed@mine.player",
                               "stat_damage:stock@stack_gem_1:sum:crashed@mine.player"]}},
        {"key": "no_more_lies", "text": "No More Lies", "tags": ["chip", "character", "red"],
         "asset": "polygon:7:pink",
         "tooltip": "Trash up to two chips out of your hand. Character chips cannot be trashed.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"], min=0, max=2),
                  "action": ["move_target_to:void", "stat_gain:acts@mine.player:1",
                             "move_to:mine.table"]}},
        {"key": "troublesome_rhetoric", "text": "Troublesome Rhetoric",
         "tags": ["chip", "character", "brown"], "asset": "polygon:7:pink",
         "tooltip": "Your opponent chooses which of the two you get: an action and a chip, or two gem power and a buy. Nothing makes them press the button — at one screen, hand it over.",
         "play": act(["options:tr_tempo,tr_money"])},
        # Valerie
        {"key": "burst_of_speed", "text": "Burst of Speed", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:cyan",
         "tooltip": "Trash this chip and take another whole turn after this one.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:extra@mine.player:1", "move_to:void"]}},
        {"key": "chromatic_orb", "text": "Chromatic Orb", "tags": ["chip", "character", "purple"],
         "asset": "circle:cyan",
         "tooltip": "A chip, and a 1-gem out of your pile and into theirs.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": {"type": "card", "tags": ["gem_1"], "zones": ["gem_pile"],
                             "owner": "anyone", "count": 1},
                  "action": ["draw_from:mine.bag:mine.hand:1"] + crash_action(1, 0)}},
        {"key": "creative_thoughts", "text": "Creative Thoughts", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:cyan",
         "tooltip": "Any different two of: an action, a buy, a gem power, a chip.",
         "play": act(["options:ct_ab,ct_am,ct_ac,ct_bm,ct_bc,ct_mc"])},
        # Geiger
        {"key": "research_development", "text": "Research & Development",
         "tags": ["chip", "character", "brown"], "asset": "polygon:7:yellow",
         "tooltip": "Printed: exchange a chip in your hand with a purple from your bag. Searching a shaken bag is not built, so this gives the action back and nothing else.",
         "play": act(["stat_gain:acts@mine.player:1"])},
        {"key": "future_sight", "text": "Future Sight", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:yellow",
         "tooltip": "Two chips, then put up to two out of your hand back on the bag. Which order they go back in is not yours to say here.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, min=0, max=2),
                  "action": ["draw_from:mine.bag:mine.hand:2",
                             "move_target_to:mine.bag", "move_to:mine.table"]}},
        {"key": "its_time_for_the_past", "text": "It's Time for the Past",
         "tags": ["chip", "character", "brown"], "asset": "polygon:7:yellow",
         "tooltip": "Take the top chip of your discard pile back into your hand. Printed, you may choose which — a pile is reached from the top, so this takes the last one you threw away.",
         "play": act(["stat_gain:acts@mine.player:1", "draw_from:mine.discard:mine.hand:1"])},
        # Lum
        {"key": "living_on_the_edge", "text": "Living on the Edge", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:white",
         "tooltip": "Three chips and an action — but only while your own gem pile is at ten or more, which is to say only while you are already losing.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "needs": ["sum:value@mine.gem_pile >= 10"],
                  "action": ["draw_from:mine.bag:mine.hand:3",
                             "stat_gain:acts@mine.player:1", "move_to:mine.table"]}},
        {"key": "pandas_bargain", "text": "Panda's Bargain", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:white",
         "tooltip": "Ongoing: a chip at the end of any turn you bought a Puzzle chip. The condition is not built; laying it out draws you the chip once.",
         "play": ongoing()},
        {"key": "jackpot", "text": "Jackpot", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:white",
         "tooltip": "Reveal two chips at random from a chosen opponent's hand and take what they turn out to be worth. Reading somebody else's hand is not built.",
         "play": act(["stat_gain:money@mine.player:1", "stat_gain:acts@mine.player:1"])},
    ] + choice_cards()


# A "choose one" is an `options:` offer and a card per branch: the offer deals
# them, clicking one plays it, and everything left is swept. Six cards for
# "any different two of four" is the whole exhaustive set, which is cheaper to
# read than two questions in a row would be to write.
def choice_cards():
    def choice(key, text, action):
        return {"key": key, "text": text, "tags": ["token", "immutable"],
                "asset": "square:slate", "play": {"action": action}}

    A = "stat_gain:acts@mine.player:1"
    B = "stat_gain:buys@mine.player:1"
    Mo = "stat_gain:money@mine.player:1"
    C = "draw_from:mine.bag:mine.hand:1"
    return [
        choice("vs_tempo", "An action and a buy", [A, B]),
        choice("vs_money", "Two gem power", ["stat_gain:money@mine.player:2"]),
        choice("vs_chips", "Two chips", ["draw_from:mine.bag:mine.hand:2"]),
        choice("tr_tempo", "An action and a chip", [A, C]),
        choice("tr_money", "Two gem power and a buy", ["stat_gain:money@mine.player:2", B]),
        choice("ct_ab", "An action and a buy", [A, B]),
        choice("ct_am", "An action and a gem power", [A, Mo]),
        choice("ct_ac", "An action and a chip", [A, C]),
        choice("ct_bm", "A buy and a gem power", [B, Mo]),
        choice("ct_bc", "A buy and a chip", [B, C]),
        choice("ct_mc", "A gem power and a chip", [Mo, C]),
    ]


# --- the rules zone -------------------------------------------------------
#
# Four rules in this game turn on a number the action list has just written and
# choose a *card* from it, which no amount grammar can do: which gem an ante
# puts down, what two combined gems become, what a gem upgrades to, and how much
# a full pile draws. Each is one card in a hidden zone with one `when`, walked
# by activate_zone — which is ungated for permission and still honours the if.
def rule_cards():
    """(zone, card) for each. A rule that has to choose a *card* from a number
    the action list just wrote cannot be an amount — no grammar turns 3 into
    `gem_3` — so it is one card with one `when`, walked by activate_zone."""
    out = []

    def rule(zone, key, when, action):
        out.append((zone, {"key": key, "text": key, "tags": ["immutable"],
                           "abilities": [{"key": key, "text": key, "when": when, "action": action}]}))

    def take(n, where):
        return ["fill:%s:%s:1" % (where, gem_key(n)), "stat_damage:stock@%s:1" % stack_key(gem_key(n))]

    # The ante grows as the bank empties: Panic, Danger and Deadly Time, at one
    # empty stack per player and then two and three more (rules.md §9).
    for n, lo, hi in [(1, None, 1), (2, 2, 2), (3, 3, 3), (4, 4, None)]:
        when = []
        if lo is not None:
            when.append("panic@clock >= %d" % lo)
        if hi is not None:
            when.append("panic@clock <= %d" % hi)
        rule("rules_ante", "ante_%d" % n, when, take(n, "mine.gem_pile"))
    # Two gems out, one gem in, and their sum is what says which.
    for n in (2, 3, 4):
        rule("rules_combine", "comb_%d" % n, ["combined@mine.player == %d" % n],
             take(n, "mine.gem_pile"))
    # A gem one bigger than the one you gave up — Risky Move's other half, Big
    # Rocks', and Strength of Earth's. Same question, three different places
    # for the answer to land.
    for where, zone, suffix in [("rules_upgrade", "mine.discard", ""),
                                ("rules_upgrade_hand", "mine.hand", "h"),
                                ("rules_upgrade_pile", "mine.gem_pile", "p")]:
        for n in (2, 3, 4):
            rule(where, "up%s_%d" % (suffix, n), ["combined@mine.player == %d" % (n - 1)],
                 take(n, zone))
    # The height bonus is cumulative, so three separate ifs add up to +1/+2/+3.
    for n in (3, 6, 9):
        rule("rules_height", "height_%d" % n, ["sum:value@mine.gem_pile >= %d" % n],
             ["stat_gain:to_draw@mine.player:1"])
    return out


def bank_cards():
    """One plate per stack: what it costs, how many are left, and the buy.

    The plate says what the chip says, because a player deciding whether to buy
    one cannot pick the chip up and read it."""
    words = {}
    for c in say(gem_cards() + purple_cards() + puzzle_cards()):
        words[c["key"]] = c.get("tooltip", "")
    out = []

    def plate(chip, name, cost, stock, asset, value=None):
        buy = {"phases": ["buy"],
               "cost": {"buys@mine.player": 1, "stock@self": 1},
               "action": ["fill:mine.discard:%s:1" % chip, "stat_gain:bought@mine.player:1"]}
        if cost > 0:
            buy["cost"]["money@mine.player"] = cost
        out.append({"key": stack_key(chip), "text": name,
                    "tags": ["stack", stack_key(chip), "immutable"],
                    "asset": asset, "tooltip": words.get(chip, ""),
                    "card_stats": dict({"price": cost, "stock": stock},
                                       **({"value": value} if value else {})),
                    "activate": buy})

    for n, cost, stock in GEMS:
        plate(gem_key(n), "%d-gem" % n, cost, stock, "diamond:green", value=n)
    for key, name, cost, stock in PURPLES:
        plate(key, name, cost, stock, "circle:magenta")
    plate("wound", "Wound", 0, 24, "circle:crimson")
    for key, name, cost, banner in PUZZLE:
        plate(key, name, cost, PUZZLE_STOCK, "polygon:6:%s" % BANNER[banner])
    return out


def character_cards():
    """The roster. Picking one is what deals your starting ten."""
    out = []
    for key, name, colour, tip, chips in CHARACTERS:
        deal = ["fill:mine.bag:%s:1" % c for c in chips]
        deal.append("fill:mine.bag:crash_gem:1")
        deal.append("fill:mine.bag:gem_1:6")
        deal.append("stat_damage:stock@stack_crash_gem:1")
        deal.append("stat_damage:stock@stack_gem_1:6")
        out.append({"key": "char_" + key, "text": name, "tags": ["character_card", "immutable"],
                    "asset": "star:6:%s" % colour, "tooltip": tip,
                    "play": {"action": deal + ["stat_gain:picked@mine.player:1",
                                              "set_owner:self:mine", "move_to:mine.fighter"]}})
    return out


def button_cards():
    return [
        {"key": "done_acting", "text": "Done acting", "tags": ["immutable"],
         "asset": "triangle:silver",
         "tooltip": "Finish your action phase and go on to buying. Any actions you have left are lost.",
         "activate": {"phases": ["action"], "action": ["next_phase"]}},
        # The cost is the rule: you must buy at least one chip a turn, and the
        # counter is reset on the way into the next one, so spending it here
        # costs nothing that is not about to be thrown away.
        {"key": "end_turn", "text": "End turn", "tags": ["immutable"],
         "asset": "square:slate",
         "tooltip": "End your turn. You must have bought at least one chip — a Wound is free, and that is the point.",
         "activate": {"phases": ["buy"], "cost": {"bought@mine.player": 1},
                      "action": ["next_phase"]}},
    ]


def other_cards():
    return [
        {"key": "clock", "text": "The bank", "tags": ["clock", "immutable"],
         "card_stats": {"panic": 0}},
        {"key": "game_over", "text": "The gem pile filled up",
         "story": "A gem pile reached ten at the end of its owner's turn, and that is the game. "
                  "Whoever kept theirs lower wins.",
         "play": {"action": ["load_game:menu.json"]}},
    ]


def seat_cards():
    return [{"key": k, "text": name, "tags": [k + "_side"]} for k, name in SEATS]


def roster_offer():
    return "options:" + ",".join("char_" + k for k, _, _, _, _ in CHARACTERS)


def phases():
    return [
        {"key": "setup", "type": "automatic", "next": [{"then": "pick_1"}]},
        # One question per seat, asked as an offer rather than as a zone on the
        # board: a roster is only looked at once, and a strip of screen kept
        # empty for the rest of the game is the most expensive kind of strip.
        # The offer is drawn over a dimmed board and takes the middle of it.
        #
        # `seat: "next"` on the *first* pick as well, because the turn counter
        # starts at nobody — the first handover is what selects seat one. The
        # phase ends on the flag the chosen character sets, not on a play
        # counter: choosing out of an overlay is deliberately not a play.
        {"key": "pick_1", "type": "player_input", "seat": "next", "zone": "hand",
         "label": "Choose your character", "actions": [roster_offer()],
         "ends_when": "picked@mine.player >= 1", "next": [{"then": "pick_2"}]},
        {"key": "pick_2", "type": "player_input", "seat": "next", "zone": "hand",
         "label": "Choose your character", "actions": [roster_offer()],
         "ends_when": "picked@mine.player >= 1", "next": [{"then": "deal"}]},
        {"key": "deal", "type": "automatic",
         "actions": ["each_seat:shuffle:mine.bag",
                     "each_seat:draw_from:mine.bag:mine.hand:%d" % HAND],
         "next": [{"then": "action"}]},
        # The ante is the action phase's own business rather than a phase before
        # it, because only a phase a player acts in can hand the turn over: an
        # automatic one has nobody to hand it to. So everything a turn resets,
        # then the ongoing chips, then the ante, all on the way in.
        {"key": "action", "type": "player_input", "seat": "next", "zone": "hand",
         "label": "Play an action chip", "ends_when": "acts@mine.player == 0",
         "actions": ["stat_set:money@mine.player:0",
                     "stat_set:acts@mine.player:1",
                     "stat_set:buys@mine.player:1",
                     "stat_set:bought@mine.player:0",
                     "stat_set:panic@clock:count:spent@bank",
                     "activate_zone:mine.ongoing",
                     "activate_zone:rules_ante"],
         "next": [{"then": "buy"}]},
        {"key": "buy", "type": "player_input", "zone": "hand",
         "label": "Play gems for money, then buy",
         "next": [{"then": "cleanup"}]},
        # The bag refills itself from the discard the moment it empties, so the
        # draw is one line and the height bonus can simply add to it. This was
        # three phases in a loop, because an action list cannot branch and the
        # reshuffle had to happen between two draws; the zone knowing its own
        # discard deletes the loop and — the point — makes it work inside a
        # chip's action list too, where no phase could reach.
        {"key": "cleanup", "type": "automatic",
         "actions": ["move:mine.table:mine.discard",
                     "move:mine.hand:mine.discard",
                     "stat_set:to_draw@mine.player:%d" % HAND,
                     "activate_zone:rules_height",
                     "draw_from:mine.bag:mine.hand:sum:to_draw@mine.player"],
         "next": [{"when": "sum:value@mine.gem_pile >= %d" % LOSE_AT, "then": "defeat"},
                  {"then": "handover"}]},
        # An extra turn is one flag read at the handover: the route overrules the
        # phase about the seat, which is the whole of "again, same player".
        {"key": "handover", "type": "automatic",
         "next": [{"when": "extra@mine.player >= 1", "then": "again"},
                  {"then": "action", "ends_round": True}]},
        {"key": "again", "type": "automatic",
         "actions": ["stat_damage:extra@mine.player:1"],
         "next": [{"then": "action", "seat": "same"}]},
        {"key": "defeat", "type": "automatic",
         "actions": ["stat_gain:won@each.enemy.player:1", "reveal:game_over"],
         "next": [{"then": "over"}]},
        {"key": "over", "type": "player_input", "label": "The game is over",
         "next": [{"then": "over"}]},
    ]


def build():
    return {
        "title": "Puzzle Strike",
        "stats": stats(),
        "styles": styles(),
        # A stack nobody can buy from any more is what drives the ante up, and
        # it is the plate's own number read as a word.
        "computed_tags": {"spent": {"stat": "stock", "less_than": 1}},
        "zones": zones(),
        "phases": phases(),
        "players": [{"card": k} for k, _ in SEATS],
        "cards": (seat_cards() + other_cards() + button_cards() + bank_cards()
                  + say(gem_cards() + purple_cards() + puzzle_cards() + character_chips())
                  + character_cards() + [c for _, c in rule_cards()]),
        "setup": {"place": [{"card": "clock", "zone": "sys"},
                            {"card": "done_acting", "zone": "controls", "at": ["a1"]},
                            {"card": "end_turn", "zone": "controls", "at": ["b1"]}]
                           + [{"card": stack_key(gem_key(n)), "zone": "bank"} for n, _, _ in GEMS]
                           + [{"card": stack_key(k), "zone": "bank"} for k, _, _, _ in PURPLES]
                           + [{"card": "stack_wound", "zone": "bank"}]
                           + [{"card": stack_key(k), "zone": "bank"} for k, _, _, _ in PUZZLE]
                           + [{"card": c["key"], "zone": z} for z, c in rule_cards()]},
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "game", "games", "puzzle_strike.json")
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
