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

SEATS = [("north", "North"), ("south", "South")]
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
     "Defensive disruption: wounds that clog an opponent's bag, and a ward that taxes every combine at the table.",
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
     "A gambler who is happiest near the edge — the fuller your gem pile, the more you draw.",
     ["living_on_the_edge", "pandas_bargain", "jackpot"]),
]


# --- layout ---------------------------------------------------------------
#
# The bank is one grid rather than eighteen stacked zones: eighteen rects would
# be eighteen numbers to keep in step, and a grid lays its own cells out.
def zones():
    z = [
        {"key": "bank", "label": "Bank", "type": "grid", "grid": [9, 2],
         "tags": ["activate"], "pos": [0.02, 0.02, 0.98, 0.24],
         "tooltip": "Every chip you may buy. A stack says how many are left; when stacks run dry the ante grows."},
        # The band this sits in is the draft's, and after the draft it is empty
        # on purpose: it is the only strip of screen neither seat owns.
        {"key": "roster", "type": "hand", "tags": ["optional"], "pos": [0.02, 0.52, 0.86, 0.66]},
        {"key": "controls", "type": "grid", "grid": [1, 2], "tags": ["activate"],
         "pos": [0.88, 0.52, 0.98, 0.66]},
        {"key": "box", "type": "deck", "tags": ["hidden"]},
        {"key": "void", "type": "deck", "tags": ["hidden"]},
        # A grid, not a deck: a tag scope only searches grids, and every rule
        # about the ante reads this card's number.
        {"key": "sys", "type": "grid", "grid": [1, 1], "tags": ["hidden"]},
    ]
    # Each rule family is its own hidden zone rather than one zone walked with a
    # step word: a step needs an order named beside it, and these are decks with
    # no columns to order by. One zone per question is cheaper and reads better.
    for key in ("rules_ante", "rules_combine", "rules_upgrade", "rules_height"):
        z.append({"key": key, "type": "deck", "tags": ["hidden"]})
    # Two seats facing each other: the far one under the bank, the near one
    # along the bottom, and the draft band between them.
    rects = {
        "gem_pile": [[0.02, 0.26, 0.36, 0.38], [0.02, 0.68, 0.36, 0.80]],
        "ongoing":  [[0.38, 0.26, 0.62, 0.38], [0.38, 0.68, 0.62, 0.80]],
        "table":    [[0.02, 0.39, 0.62, 0.50], [0.02, 0.81, 0.62, 0.92]],
        "hand":     [[0.64, 0.26, 0.87, 0.50], [0.64, 0.68, 0.87, 0.97]],
        "bag":      [[0.89, 0.26, 0.945, 0.37], [0.89, 0.68, 0.945, 0.79]],
        "discard":  [[0.89, 0.38, 0.945, 0.50], [0.89, 0.80, 0.945, 0.92]],
    }
    z += [
        # The gem pile is a grid for the same reason: `sum:value@mine.gem_pile`
        # is the loss condition, the height bonus and half the crash rules,
        # and a scope cannot see a hand.
        {"key": "gem_pile", "label": "Gem pile", "type": "grid", "grid": [10, 2],
         "tags": ["per_seat", "face_up"],
         "pos": rects["gem_pile"],
         "tooltip": "The gems that will end you. Ten or more at the end of your own turn and you lose."},
        {"key": "ongoing", "label": "In play", "type": "hand", "tags": ["per_seat", "face_up"],
         "pos": rects["ongoing"]},
        {"key": "table", "label": "Played this turn", "type": "hand", "tags": ["per_seat", "face_up"],
         "pos": rects["table"]},
        {"key": "hand", "type": "hand", "tags": ["per_seat"], "pos": rects["hand"]},
        {"key": "bag", "label": "Bag", "type": "deck", "tags": ["per_seat", "hidden"], "pos": rects["bag"],
         "tooltip": "Your draw pile. When it runs out mid-draw the discard goes back in and is shaken."},
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
        # On the chips rather than on a seat: a gem says what it is worth, a
        # bank plate says how many are left, and neither is a HUD row.
        {"key": "value", "min": 0, "max": 4, "icon": "none", "color": "green", "tags": ["hidden"]},
        {"key": "price", "min": 0, "max": 20, "icon": "coin", "color": "gold", "tags": ["hidden"]},
        {"key": "stock", "min": 0, "max": 99, "icon": "none", "tags": ["hidden"]},
        {"key": "panic", "min": 0, "max": 9, "tags": ["hidden"]},
    ]


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
    return [
        # Argagarg
        {"key": "hex_of_murkwood", "text": "Hex of Murkwood", "tags": ["chip", "character", "red"],
         "asset": "polygon:7:teal",
         "tooltip": "Each opponent gains a wound or discards two wounds. Here they gain one: choosing for them is the opponent's decision, and there is no way to ask yet.",
         "play": act(["stat_gain:acts@mine.player:1"] + gain_wound("enemy"))},
        {"key": "bubble_shield", "text": "Bubble Shield", "tags": ["chip", "character", "blue"],
         "asset": "circle:cyan",
         "tooltip": "Ongoing: negate a gem sent to you, then discard this chip. Reactions are not built yet, so laying it out does nothing but say you have it.",
         "play": ongoing()},
        {"key": "protective_ward", "text": "Protective Ward", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:teal",
         "tooltip": "Ongoing: nobody may combine without discarding a Puzzle chip first. The tax is not built; the action it gives back is.",
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
    # Risky Move's other half: the gem you gain is one bigger than the one you buried.
    for n in (2, 3, 4):
        rule("rules_upgrade", "up_%d" % n, ["combined@mine.player == %d" % (n - 1)],
             take(n, "mine.discard"))
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
    for c in gem_cards() + purple_cards() + puzzle_cards():
        words[c["key"]] = c.get("tooltip", "")
    out = []

    def plate(chip, name, cost, stock, asset):
        buy = {"phases": ["buy"],
               "cost": {"buys@mine.player": 1, "stock@self": 1},
               "action": ["fill:mine.discard:%s:1" % chip, "stat_gain:bought@mine.player:1"]}
        if cost > 0:
            buy["cost"]["money@mine.player"] = cost
        out.append({"key": stack_key(chip), "text": name,
                    "tags": ["stack", stack_key(chip), "immutable"],
                    "asset": asset, "tooltip": words.get(chip, ""),
                    "card_stats": {"price": cost, "stock": stock},
                    "activate": buy})

    for n, cost, stock in GEMS:
        plate(gem_key(n), "%d-gem" % n, cost, stock, "diamond:green")
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
                    "play": {"action": deal + ["set_owner:self:mine", "move_to:mine.ongoing"]}})
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


def phases():
    return [
        {"key": "setup", "type": "automatic", "next": [{"then": "pick_1"}]},
        # One question per seat over one shared roster, and the pick is what
        # deals the deck: nothing about a character exists until it is chosen.
        # `seat: "next"` on the *first* pick as well, because the turn counter
        # starts at nobody — the first handover is what selects seat one.
        {"key": "pick_1", "type": "player_input", "seat": "next", "zone": "roster", "ends_after": 1,
         "label": "Choose your character", "next": [{"then": "pick_2"}]},
        {"key": "pick_2", "type": "player_input", "seat": "next", "zone": "roster", "ends_after": 1,
         "label": "Choose your character", "next": [{"then": "deal"}]},
        {"key": "deal", "type": "automatic",
         "actions": ["move:roster:box",
                     "each_seat:shuffle:mine.bag",
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
        {"key": "cleanup", "type": "automatic",
         "actions": ["move:mine.table:mine.discard",
                     "move:mine.hand:mine.discard",
                     "stat_set:to_draw@mine.player:%d" % HAND,
                     "activate_zone:rules_height"],
         "next": [{"when": "sum:value@mine.gem_pile >= %d" % LOSE_AT, "then": "defeat"},
                  {"then": "draw_step"}]},
        # The reshuffle the rulebook actually describes: when the bag runs out
        # mid-draw the discard goes back in and the draw carries on. It is a
        # loop rather than one action because an action list cannot branch.
        {"key": "draw_step", "type": "automatic",
         "next": [{"when": "to_draw@mine.player == 0", "then": "handover"},
                  {"zone_empty": ["bag"], "then": "reshuffle"},
                  {"then": "draw_one"}]},
        {"key": "draw_one", "type": "automatic",
         "actions": ["draw_from:mine.bag:mine.hand:1", "stat_damage:to_draw@mine.player:1"],
         "next": [{"then": "draw_step"}]},
        {"key": "reshuffle", "type": "automatic",
         "actions": ["return_to:mine.discard:mine.bag", "shuffle:mine.bag"],
         "next": [{"zone_empty": ["bag"], "then": "handover"},
                  {"then": "draw_step"}]},
        {"key": "handover", "type": "automatic",
         "next": [{"then": "action", "ends_round": True}]},
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
        # A stack nobody can buy from any more is what drives the ante up, and
        # it is the plate's own number read as a word.
        "computed_tags": {"spent": {"stat": "stock", "less_than": 1}},
        "zones": zones(),
        "phases": phases(),
        "players": [{"card": k} for k, _ in SEATS],
        "cards": (seat_cards() + other_cards() + button_cards() + bank_cards()
                  + gem_cards() + purple_cards() + puzzle_cards() + character_chips()
                  + character_cards() + [c for _, c in rule_cards()]),
        "setup": {"place": [{"card": "clock", "zone": "sys"},
                            {"card": "done_acting", "zone": "controls", "at": ["a1"]},
                            {"card": "end_turn", "zone": "controls", "at": ["a2"]}]
                           + [{"card": stack_key(gem_key(n)), "zone": "bank"} for n, _, _ in GEMS]
                           + [{"card": stack_key(k), "zone": "bank"} for k, _, _, _ in PURPLES]
                           + [{"card": "stack_wound", "zone": "bank"}]
                           + [{"card": stack_key(k), "zone": "bank"} for k, _, _, _ in PUZZLE]
                           + [{"card": "char_" + k, "zone": "roster"} for k, _, _, _, _ in CHARACTERS]
                           + [{"card": c["key"], "zone": z} for z, c in rule_cards()]},
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "game", "games", "puzzle_strike.json")
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
