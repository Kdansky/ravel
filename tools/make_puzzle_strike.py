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
import guard

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

# Every Puzzle chip ever printed: twenty-four in the base game, twenty-four in
# Shadows, three promotional. Transcribed in chips.md from the owner's own set;
# nothing here is invented and nothing is left out, so a chip whose rule the
# engine cannot say yet is present and says so rather than being quietly missing.
#
# **Ten of them go into the bank in any one game** (rules.md §3) and the rest
# stay in the box — which is what the bank draft at the start is for, and why
# this is a catalogue rather than a bank.
#
# key, printed name, cost, banner. A banner of "" is the grey banner Option
# Select wears: no arrow colour restricts it, so it costs a plain action.
PUZZLE_BASE = [
    ("chip_damage",        "Chip Damage",       3, "red"),
    ("combos_are_hard",    "Combos Are Hard",   6, "brown"),
    ("draw_three",         "Draw Three",        3, "brown"),
    ("gem_essence",        "Gem Essence",       3, "brown"),
    ("gems_to_gemonade",   "Gems to Gemonade",  4, "purple"),
    ("its_a_trap",         "It's a Trap",       2, "brown"),
    ("combo_time",         "It's Combo Time",   8, "brown"),
    ("iron_defense",       "Iron Defense",      4, "brown"),
    ("knockdown",          "Knockdown",         2, "red"),
    ("master_puzzler",     "Master Puzzler",   12, "brown"),
    ("mix_master",         "Mix-Master",        4, "red"),
    ("one_of_each",        "One of Each",       5, "brown"),
    ("one_two_punch",      "One-Two Punch",     4, "brown"),
    ("really_annoying",    "Really Annoying",   1, "red"),
    ("recklessness",       "Recklessness",      3, "brown"),
    ("risky_move",         "Risky Move",        1, "brown"),
    ("roundhouse",         "Roundhouse",        6, "brown"),
    ("sale_prices",        "Sale Prices",       2, "brown"),
    ("secret_move",        "Secret Move",       1, "brown"),
    ("self_improvement",   "Self-Improvement",  4, "blue"),
    ("sneak_attack",       "Sneak Attack",      3, "red"),
    ("stolen_purples",     "Stolen Purples",    4, "red"),
    ("thinking_ahead",     "Thinking Ahead",    2, "blue"),
    ("training_day",       "Training Day",      2, "brown"),
]
PUZZLE_SHADOWS = [
    ("axe_kick",           "Axe Kick",              5, "brown"),
    ("bang_then_fizzle",   "Bang then Fizzle",      2, "brown"),
    ("blues_are_good",     "Blues Are Good",        3, "blue"),
    ("button_mashing",     "Button Mashing",        3, "brown"),
    ("chips_for_free",     "Chips for Free",        4, "brown"),
    ("color_panic",        "Color Panic",           3, "red"),
    ("degenerate_trasher", "Degenerate Trasher",    8, "brown"),
    ("ebb_or_flow",        "Ebb or Flow",           2, "blue"),
    ("hundred_fist",       "Hundred-Fist Frenzy",   4, "brown"),
    ("improvisation",      "Improvisation",         4, "blue"),
    ("just_a_scratch",     "Just a Scratch",        1, "red"),
    ("money_for_nothing",  "Money for Nothing",     2, "blue"),
    ("now_or_later",       "Now or Later",          2, "brown"),
    ("one_true_style",     "One True Style",        3, "purple"),
    ("option_select",      "Option Select",         6, ""),
    ("ouch",               "Ouch!",                 4, "red"),
    ("pick_your_poison",   "Pick Your Poison",      4, "red"),
    ("punch_punch_kick",   "Punch, Punch, Kick",    6, "brown"),
    ("repeated_jabs",      "Repeated Jabs",         2, "red"),
    ("risk_to_riskonade",  "Risk to Riskonade",     3, "brown"),
    ("safe_keeping",       "Safe Keeping",          1, "brown"),
    ("signature_move",     "Signature Move",        5, "brown"),
    ("the_hammer",         "The Hammer",           12, "brown"),
    ("x_copy",             "X-Copy",                6, "brown"),
]
PUZZLE_PROMO = [
    ("combinatorics",      "Combinatorics",         4, "purple"),
    ("custom_combo",       "Custom Combo",          7, "brown"),
    ("dashing_strike",     "Dashing Strike",        4, "red"),
]
PUZZLE_ALL = PUZZLE_BASE + PUZZLE_SHADOWS + PUZZLE_PROMO

# The ten the bank starts with when nobody drafts one: the base-game chips this
# game was built and tested against. The draft replaces them, one pick at a time.
DEFAULT_BANK = ["risky_move", "really_annoying", "draw_three", "recklessness",
                "sneak_attack", "gem_essence", "one_two_punch", "one_of_each",
                "roundhouse", "combo_time"]
PUZZLE = [c for c in PUZZLE_ALL if c[0] in DEFAULT_BANK]
PUZZLE_STOCK = 5

BANNER = {"brown": "tan", "red": "red", "blue": "blue", "purple": "magenta"}

# The four banner colours, plus the one that is not a colour. An arrow is an
# extra action play; a **black** arrow will pay for any chip, a coloured one
# only for a chip whose own banner matches it (rules.md §2). So an arrow is a
# pool on the player card, one per colour, and a chip costs one arrow of its own
# colour — flatly, with no alternative written on it. That the plain arrow will
# do instead is a fact about the plain arrow, said once where it lives:
# `acts` declares `pays_for`, and the engine spends the restricted pool first
# because it is the one that is worth less anywhere else.
COLOURS = ["brown", "red", "blue", "purple"]


def arrow(colour):
    """The pool a chip of that colour is paid from. Black is the plain arrow —
    it is `acts`, which every game before this called the action count, because
    an unrestricted action is exactly what it always was."""
    return "acts@mine.player" if colour == "black" else "act_%s@mine.player" % colour


def act_cost(colour):
    return {arrow(colour): 1}


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
     "Speed: more actions, more chips, and a chip kept back for next turn.",
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
     None,
     {'hits': 1, 'react': 1}),
    "draw_three": ("+3 chips", None, {"plus_draw": 3}),
    "recklessness": ("+4 actions. Gain a wound.", None, {"plus_act": 4}),
    "sneak_attack": ("+1 red action. Ante a 1-gem into each opposing gem pile.", None,
                     {"plus_act": 1, "hits": 1}),
    "gem_essence": ("Trash a gem from your hand. If you do, +1 brown action, +1 purple action, +1 red action, +1 blue action.",
                    None, {"plus_act": 4}),
    "one_two_punch": ("+2 actions", None, {"plus_act": 2}),
    "one_of_each": ("+1 action, piggy bank, +$1, +1 chip", None,
                    {"plus_act": 1, "plus_piggy": 1, "plus_pow": 1, "plus_draw": 1}),
    "roundhouse": ("+1 action, +2 chips", None, {"plus_act": 1, "plus_draw": 2}),
    "combo_time": ("Put a 1-gem from your hand in your gem pile. If you do, +4 chips, +1 action.",
                   None, {"plus_act": 1, "plus_draw": 4}),

    # --- the rest of the base game's twenty-four ---------------------------
    "chip_damage": ("+1 red action. You may put a chip from your discard pile on your bag. Each opponent discards a purple or two chips.",
     "the action and the chip off the discard pile are built. \"A purple or two chips\" is their choice between two things, and only one of the two can be narrowed — handing them the choice is sayable now, and is not yet written.",
     {'plus_act': 1, 'hits': 1}),
    "combos_are_hard": ("If this is the only action you play this turn, gain any two different non-Puzzle "
                        "chips from the bank, end your action phase, then trash this chip.",
                        "it ends your action phase and trashes itself. \"The only action you play this turn\" "
                        "cannot be asked \u2014 nothing counts the actions a player has played \u2014 so the two chips are not given.",
                        {}),
    "gems_to_gemonade": ("Main: +2 chips. Reaction: Negate up to three gems sent to a player. "
                         "He gets +$1 for each one during his next buy phase.",
                         "both halves fire; the +$1 per gem is owed in a later phase, and nothing defers a payment.",
                         {"plus_draw": 2, "react": 1}),
    "its_a_trap": ("+1 action. Put a trap token on a stack in the bank, then trash this chip. "
                   "Each token gives a wound to each player who buys from that stack.",
                   "the action is built and the chip trashes itself. A token that sits on a bank stack and "
                   "changes what buying from it does is a rule on somebody else's card, which nothing writes.",
                   {"plus_act": 1}),
    "iron_defense": ("Put a Crash Gem from the bank into your gem pile. You may play it later as if from your hand.",
                     "the Crash Gem arrives in your gem pile. Playing a card out of a gem pile is not built \u2014 "
                     "a zone can grant what lying in it lets a card do, and this one does not.",
                     {}),
    "knockdown": ("+1 purple action. Chosen opponent discards a chip and can't play purple shield reactions "
                  "this turn \u2014 his own crashes are untouched.",
                  "the action and their discard are built, and the discard really is their pick: priority goes "
                  "to them while the offer is up. Barring an announcement from being answered has no spelling.",
                  {"plus_act": 1, "hits": 1}),
    "master_puzzler": ("Choose any number of different non-gem, non-Puzzle chips in the bank. "
                       "Play them, gain them, then end your action phase.",
                       "it ends your action phase and trashes itself. \"Play them\" would be copy:, but the bank "
                       "holds plates rather than chips and there is no instance to copy.",
                       {}),
    "mix_master": ("Split the largest gem in each opposing gem pile into that many 1-gems, then combine two "
                   "gems in your gem pile.",
                   "the combine is built. \"The largest gem\" needs a pick chosen by a number rather than by a "
                   "player, which no scope says.",
                   {"plus_act": 1}),
    "sale_prices": ("+$1. Chips in the bank cost 1 less this turn, to a minimum of 1.",
                    "the gem power is built. A cost is a fixed number in this engine \u2014 no measure may stand in "
                    "one \u2014 so nothing can make the bank cheaper for a turn.",
                    {"plus_pow": 1}),
    "secret_move": ("+1 action. Ongoing: piggy bank each turn. Discard this when you buy a purple.",
     None,
     {'plus_act': 1, 'plus_piggy': 1}),
    "self_improvement": ("Main: Trash a chip from your hand or discard pile. Reaction: After you're red-attacked, +3 chips.",
                         "both halves are built; the trash reaches your hand only, and reaching the discard pile "
                         "as well is content work \u2014 show:mine.discard opens its real cards.",
                         {"plus_draw": 3, "react": 1}),
    "stolen_purples": ("Chosen opponent reveals his hand and discards all purples. Steal one of those purples (to your discard pile). If you do, trash this chip.",
     "you take one purple out of their revealed hand. The rest of their purples are not discarded, which would want a scope that reaches inside a hand.",
     {'hits': 1}),
    "thinking_ahead": ("Main: +$1. You may put any chips you buy this turn on top of your bag. Reaction: Trash this chip to become immune to a red chip.",
     "the gem power and the immunity are built. Redirecting what you buy onto your bag is answerable now, but the event names the *plate*, not the chip it dealt into your discard, so there is nothing to move.",
     {'plus_pow': 1, 'react': 1}),
    "training_day": ("Piggy bank. Trash a non-purple-orb chip from your hand, then put a bank chip costing "
                     "up to 2 more than the trashed chip into your hand.",
                     "built whole. The allowance is handed over as money and the ordinary price of every pile "
                     "does the gating, so \"up to 2 more\" needed nothing new.",
                     {"plus_piggy": 1}),

    # --- Shadows ------------------------------------------------------------
    "axe_kick": ("+1 brown action, +2 chips", None, {"plus_act": 1, "plus_draw": 2}),
    "bang_then_fizzle": ("If your gem pile totals 4 or fewer, +2 actions, +2 chips. Once-per-turn.",
                         "the gem-pile gate is built. Once-per-turn is not: nothing marks a chip as already "
                         "used this turn.",
                         {"plus_act": 2, "plus_draw": 2}),
    "blues_are_good": ("Main: +1 blue action. Search your bag for a blue-banner chip and put it in your hand. Reaction: Become immune to a red chip.",
     None,
     {'plus_act': 1, 'react': 1}),
    "button_mashing": ("+2 actions, then trash this chip.", None, {"plus_act": 2}),
    "chips_for_free": ("+2 chips. Trash a chip from your hand. If you do, gain a chip costing up to 2 more "
                       "than the trashed chip.",
                       "built whole, the same way Training Day is: the allowance is money and the piles price "
                       "themselves.",
                       {"plus_draw": 2}),
    "color_panic": ("+1 red action. Choose blue, red, purple or brown. Each opponent discards a chip of that "
                    "banner colour, or reveals his hand if he can't. If any can't, +1 action.",
                    "the action is built. The discard is narrowed by a colour the player picks as the chip "
                    "runs, and neither the narrowing nor a branch on whether they could is sayable.",
                    {"plus_act": 1, "hits": 1}),
    "degenerate_trasher": ("+1 action. Trash up to two chips from your hand. (Character chips can't be trashed.)",
                           None, {"plus_act": 1}),
    "ebb_or_flow": ("Main or Reaction: Choose one: all players trash a 1-gem from their gem piles "
                    "\u2014 OR \u2014 you ante a 2-gem.",
                    None, {"react": 1}),
    "hundred_fist": ("Ongoing: After you red-attack, you may crash a gem in your gem pile. Discard if an opponent skips his action phase.",
     "the crash after your own attack is built. \"Discard if an opponent skips his action phase\" is not: a phase *going by* announces its own beginning and end, not what somebody declined to do inside it.",
     {}),
    "improvisation": ("Main: +2 chips. Discard 2 drawn and play the other drawn chips. "
                      "Reaction: After you're red-attacked, you may play a chip as if it were your turn.",
                      "the two chips are drawn. \"The other drawn chips\" needs the set a draw just produced, "
                      "which nothing keeps.",
                      {"plus_draw": 2, "react": 1}),
    "just_a_scratch": ("Choose one: each opponent gains a wound \u2014 OR \u2014 trash a wound from your hand or "
                       "discard pile and +1 red action.",
                       "built, with the trash reaching your hand rather than the discard pile.",
                       {"hits": 1}),
    "money_for_nothing": ("Main: Put a 2-gem from the bank into your hand. You may trash this chip. "
                          "Reaction: Put a gem from the bank into your hand.",
                          "both halves are built; the chip is not offered the choice of trashing itself.",
                          {"react": 1}),
    "now_or_later": ("Choose one: +2 chips \u2014 OR \u2014 trash a gem, a wound, or both from your hand / discard pile.",
                     "built, with the trash reaching your hand rather than the discard pile.", {}),
    "one_true_style": ("+1 brown action, +1 red action, +1 blue action. Combine two 1-gems in your gem pile.",
                       "the three actions are built; the combine is not, since it would want its own pair of "
                       "targets alongside them.",
                       {"plus_act": 3}),
    "option_select": ("Play this as if it were any bank chip of cost 5 or less, then trash this chip.",
                      "not playable. copy: runs a card's action list, and the bank holds plates rather than "
                      "chips \u2014 there is no instance of the thing being copied.",
                      {}),
    "ouch": ("Ante a 1-gem into each opposing gem pile. Then each opponent trashes a Combine from his discard "
             "pile, discards a chip, and gains a wound. Once-per-turn.",
             "the ante and the wound are built. Trashing a named chip out of their discard needs a pick "
             "narrowed to one card, and once-per-turn is not marked.",
             {"hits": 1}),
    "pick_your_poison": ("+1 red action, +1 chip, piggy bank. Each opponent chooses one: he antes a 1-gem "
                         "\u2014 OR \u2014 he discards two chips.",
                         "built whole, and the choice really is theirs: priority goes across while the offer "
                         "is up and comes home when it closes.",
                         {"plus_act": 1, "plus_draw": 1, "plus_piggy": 1, "hits": 1}),
    "punch_punch_kick": ("+2 actions, +1 chip", None, {"plus_act": 2, "plus_draw": 1}),
    "repeated_jabs": ("Ante a 1-gem into each opposing gem pile. You may put this chip on top of your bag.",
                      "it always goes back on top of your bag rather than to the table. \"You may\" would be "
                      "an offer of two landings, and where a chip lands is one word.",
                      {"hits": 1}),
    "risk_to_riskonade": ("Ante a 3-gem. All players draw two chips. You may trash this chip.",
                          "the ante and the draw are built; the chip is not offered the choice of trashing itself.",
                          {"plus_draw": 2}),
    "safe_keeping": ("+1 action, piggy bank. You may put a 1-gem from your gem pile into your bag.",
                     None, {"plus_act": 1, "plus_piggy": 1}),
    "signature_move": ("Search your bag or discard pile for a character chip and put it in your hand. You may play a character chip.",
     "the search is built and narrowed to a character chip. Playing one for free afterwards is not: nothing plays a card without its cost.",
     {}),
    "the_hammer": ("Ante up to three gems. +1 action and +1 chip as you ante each one.", None,
                   {"plus_act": 1, "plus_draw": 1}),
    "x_copy": ("Choose a Puzzle chip, Crash Gem, or Double Crash Gem in your hand and play it twice.",
               "built with copy:, which runs the chosen chip's play twice without playing the chip. Nothing "
               "narrows the pick to those three kinds.",
               {}),

    # --- promotional --------------------------------------------------------
    "combinatorics": ("+1 brown action. Ongoing: Whenever you play a Combine, you may combine again and −$1. Discard when your gem pile totals 5 or less.",
     "the action is built and laying it out says you have it. Nothing announces a Combine being played, so there is no verb for the ongoing half to answer; the gem-pile discard clause is a state rather than an event.",
     {'plus_act': 1}),
    "custom_combo": ("A burst of five multi-arrow bonuses and no words.",
                     "not playable, and not transcribed: chips.md reports the arrow rows are legible as "
                     "shapes and not as amounts, so what this chip gives is unknown. Guessing it would be "
                     "the one invented chip in the box.",
                     {}),
    "dashing_strike": ("+1 brown action. Trash a 1-gem from your gem pile. If you do, chosen opponent "
                       "antes a 1-gem.",
                       None, {"plus_act": 1, "hits": 1}),

    "hex_of_murkwood": ("+1 blue action. Each opponent gains a wound or discards two wounds.",
     "they gain one. Asking them is now sayable — a mandatory reaction on their own board card opens the offer for them — and is not yet written.",
     {'plus_act': 1, 'hits': 1}),
    "bubble_shield_up": ("Ongoing: Negate a gem sent to you, then discard this chip.",
                         "what Bubble Shield becomes once it is out. A separate card because the two halves "
                         "answer from different zones, and one card cannot say which of its reactions belongs to which.",
                         {"react": 1}),
    "bubble_shield": ("Ongoing: Negate a gem sent to you, then discard this chip. Reaction: Become immune to a red chip.",
     "laying it out turns it into the ongoing half, which is a card of its own. Answering from hand instead cancels the attack outright, which is the two-player reading of immunity.",
     {'react': 1}),
    "protective_ward": ("+1 blue action. Ongoing: Players can't combine gems unless they discard a Puzzle chip first. "
                        "Discard this at the end of your next action phase.",
                        "the tax on combining is not built; the action it gives is.",
                        {"plus_act": 1}),

    "playing_with_fire": ("Ante a 1-gem. +1 brown action, +1 red action, +1 chip.", None,
                          {"plus_act": 2, "plus_draw": 1}),
    "burning_vigor": ("Trash a wound from your hand or discard pile. If you do, +1 action and ante a 1-gem into each opposing gem pile.",
     None,
     {'plus_act': 1, 'hits': 1}),
    "unstable_power": ("Main or Reaction: Play this as if it were a Double Crash Gem, then gain two wounds.",
                       "the main half only. A chip played out of turn is what \"reactions\" is for now, "
                       "so the other half is a second entry waiting to be written.",
                       {"plus_pow": 2, "react": 1}),

    "dragon_form": ("Ongoing: Each ante phase, ante a gem of 1 higher than usual, or discard this chip. Your purples can't be reacted to. You can't buy purples.",
     "the bigger ante is built. Nothing can say an announcement may not be answered, and nothing can bar a pile from being bought, so the other two clauses have no spelling.",
     {}),
    "rigorous_training": ("Reaction: When an opponent buys a purple chip, trash a non-purple chip from your hand then gain a chip costing up to 2 more than the trashed chip.",
     "the allowance is handed over as money, so the ordinary price of every pile does the gating and nothing new had to be invented. A chip nobody can buy carries no price, so trashing a character chip allows 2.",
     {'react': 1}),
    "purge_bad_habits": ("Trash a chip from your hand. Put a 2-gem from the bank into your hand. "
                         "(Character chips can't be trashed.)", None, {}),

    "double_take": ("Choose a non-Puzzle chip in your hand or discard pile. Play it twice, trash it, then end your action phase.",
     "not written yet, and now sayable: \"copy:target:play:2\" runs the chosen chip's play twice without playing the chip, then \"destroy:target\" trashes it.",
     {'plus_act': 2}),
    "bag_of_tricks": ("+1 brown action, piggy bank, +1 chip", None,
                      {"plus_act": 1, "plus_piggy": 1, "plus_draw": 1}),
    "speed_of_the_fox": ("+2 brown actions, +1 chip", None,
                         {"plus_act": 2, "plus_draw": 1}),

    "reversal": ("Main: +2 chips. Reaction: Break a gem to counter-crash. The smaller of the two crashes "
                 "cancels the larger; the remainder arrives. A broken 4-gem cannot be countered at all.",
     None,
     {'plus_draw': 2, 'react': 1}),
    "martial_mastery": ("+1 action. Trash a non-purple chip from your hand then gain a chip costing exactly 2 more.",
                        "comparing two chips' prices is not built, so this trashes and gives the action.",
                        {"plus_act": 1}),
    "versatile_style": ("Choose one: +1 action and piggy bank \u2014 or \u2014 +$2 \u2014 or \u2014 +2 chips.", None, {}),

    "stone_wall": ("Main: +1 chip, piggy bank. Reaction: Reflect any gems sent to a player to the bank. (Just trash them.)",
     None,
     {'plus_draw': 1, 'plus_piggy': 1, 'react': 1}),
    "big_rocks": ("Trash a gem from your hand, then take a gem of 1 higher value and put it in your hand.", None, {}),
    "strength_of_earth": ("+1 brown action. Combine a 1-gem from the bank with a gem in your gem pile.", None,
                          {"plus_act": 1}),

    "pilebunker": ("+1 chip. Opponents reveal their hands, trash their largest gem, then gain that many 1-gems.",
     "built whole. Their whole hand is revealed — that is half the printed rule — and \"chosen.where\" is what says only the largest gem may be taken out of it.",
     {'plus_draw': 1, 'hits': 1}),
    "no_more_lies": ("+1 red action. Trash up to two chips from your hand. (Character chips can't be trashed.)",
                     None, {"plus_act": 1, "hits": 1}),
    "troublesome_rhetoric": ("Chosen opponent chooses your benefit: +1 action and +1 chip — OR — +$2 and piggy bank.",
     "at one screen, hand it over. Handing the choice to them is now sayable — a mandatory reaction on their own board card — and is not yet written.",
     {}),

    "burst_of_speed": ("Trash this chip, then take an extra turn after this one.", None, {}),
    "chromatic_orb": ("+1 chip. Crash a 1-gem in your gem pile.", None, {"plus_draw": 1}),
    "creative_thoughts": ("Choose any different two: +1 action / piggy bank / +$1 / +1 chip.", None, {}),

    "research_development": ("+1 action. Exchange a chip in your hand with a purple from your bag.",
     "the bag opens and a purple comes out of it. The chip you give back in exchange is not asked for.",
     {'plus_act': 1}),
    "future_sight": ("+2 chips. Put two chips from your hand on top of your bag in any order.",
     "not written yet, and now sayable: targets arrive in the order they were picked and \"move_target_to:mine.bag:top\" puts them back in that order, so the order really is the player's.",
     {'plus_draw': 2}),
    "its_time_for_the_past": ("+1 action. Put a non-Puzzle chip from your discard pile into your hand.",
     None,
     {'plus_act': 1}),

    "living_on_the_edge": ("If your gem pile totals at least 10, +3 chips, +1 action.", None,
                           {"plus_act": 1, "plus_draw": 3}),
    "pandas_bargain": ("Ongoing: At the end of any turn you bought a Puzzle chip, +1 chip. Discard this when you buy a purple.",
     None,
     {'plus_draw': 1}),
    "jackpot": ("Reveal two chips at random from chosen opponent's hand. If any are gems, +$1 and +1 action. If both are purples, play and gain a purple from the bank.",
     "pays the gem half unconditionally. A random reveal is built now (\"show:random.enemy.hand\"), but it shows one card and nothing branches on what came up, which is the rest of the chip.",
     {'plus_act': 1, 'plus_pow': 1}),
}


def by_colour(cards):
    """A chip costs one arrow of its own banner colour.

    Nothing here says the plain arrow will do instead — `acts` says that itself,
    with `pays_for`, once for the whole game. Written here rather than on forty
    cards because the colour is already a tag, and a cost copied beside it is a
    cost that drifts."""
    for c in cards:
        play = c.get("play")
        if not isinstance(play, dict) or play.get("cost", {}).get("acts@mine.player") != 1:
            continue
        colour = next((t for t in c.get("tags", []) if t in COLOURS), None)
        if colour:
            play["cost"] = dict(play["cost"], **act_cost(colour))
            del play["cost"]["acts@mine.player"]
    return cards


def lands(cards):
    """A play's trailing move becomes its `spent`.

    Where a card goes once its play is over is not the last line of the action
    list any more: a countered chip never runs its list and still has to land
    somewhere, so `spent` says it once and says it however the play ends. Only
    the play block migrates — a challenge's `pass` is an ordinary action list
    that happens to end in a move, and moving it would say the card lands there
    even when the challenge failed."""
    for c in cards:
        play = c.get("play")
        if not isinstance(play, dict):
            continue
        acts = play.get("action") or []
        if acts and acts[-1].startswith("move_to:"):
            play["action"] = acts[:-1]
            play["spent"] = acts[-1].split(":", 1)[1]
    return cards


def priced(cards):
    """A bank chip carries what it costs, on the chip.

    The plate already knows the price; the chip did not, and a rule that reads
    one — "gain a chip costing up to 2 more than the one you trashed" — reads it
    off the card in a hand, not off the plate it came from. A chip nobody can
    buy carries no price at all, which is the honest answer for a character chip
    and is what makes trashing one worth the bare allowance."""
    prices = {gem_key(n): cost for n, cost, _ in GEMS}
    prices.update({k: cost for k, _, cost, _ in PURPLES})
    prices.update({k: cost for k, _, cost, _ in PUZZLE_ALL})
    prices["wound"] = 0
    for c in cards:
        if c["key"] in prices:
            c.setdefault("card_stats", {})["price"] = prices[c["key"]]
    return cards


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
        {"key": "bank", "label": "Bank", "type": "grid", "grid": [3, 6],
         "tags": ["activate"], "applies": ["buyable"], "pos": [0.005, 0.095, 0.225, 0.7],
         "tooltip": "Every chip you may buy. A stack says how many are left; when stacks run dry the ante grows."},
        # The two buttons sit on the middle line between the gem piles, where
        # they belong to whoever is up rather than to either side of the table.
        {"key": "controls", "type": "grid", "grid": [5, 1], "tags": ["activate"],
         "pos": [0.808, 0.463, 0.995, 0.537]},
        # The roster is the injected offer, positioned rather than declared: ten
        # characters wants more of the screen than a choice between two.
        {"key": "options", "type": "options", "pos": [0.06, 0.30, 0.94, 0.70]},
        {"key": "box", "type": "deck", "tags": ["hidden"]},
        # Every Puzzle chip plate that is not in the bank. Hidden, because it is
        # forty-one plates and nobody needs them on the table \u2014 the draft opens
        # them face up in the offer, which is what an offer is for.
        {"key": "chip_box", "type": "deck", "tags": ["hidden"]},
        {"key": "void", "type": "deck", "tags": ["hidden"]},
        # A grid, not a deck: a tag scope only searches grids, and every rule
        # about the ante reads this card's number.
        {"key": "sys", "type": "grid", "grid": [1, 1], "tags": ["hidden"]},
    ]
    # Each rule family is its own hidden zone rather than one zone walked with a
    # step word: a step needs an order named beside it, and these are decks with
    # no columns to order by. One zone per question is cheaper and reads better.
    for key in ("rules_ante", "rules_combine", "rules_upgrade", "rules_upgrade_hand",
                "rules_upgrade_pile", "rules_height", "rules_piggy"):
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
        "ongoing":  [[0.235, 0.505, 0.700, 0.612], [0.235, 0.388, 0.700, 0.495]],
        "stash":    [[0.708, 0.505, 0.800, 0.612], [0.708, 0.388, 0.800, 0.495]],
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
        {"key": "ongoing", "label": "In play", "type": "hand", "status": "board", "tags": ["per_seat", "face_up"],
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
        # Where an announcement waits. It holds records, never chips, so it sits
        # under the bank rather than beside either player: a crash that has been
        # said out loud and not yet answered belongs to neither of them.
        {"key": "pending", "label": "Announced", "type": "pile", "tags": ["stack", "face_up"],
         "pos": [0.005, 0.712, 0.225, 0.818],
         "tooltip": "A crash that has been announced and not yet answered. It sits under the bank because it belongs to neither player."},
        # The piggy bank's shelf: one chip kept out of the cleanup discard, face
        # down until it comes back at the start of the next turn.
        {"key": "stash", "label": "Kept back", "type": "deck",
         "tags": ["per_seat", "face_down"], "pos": rects["stash"],
         "tooltip": "A chip you kept out of the discard. It returns to your hand at the start of your next turn."},
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
        # One black arrow a turn, and whatever a chip adds. A coloured arrow is
        # its own pool because it can only pay for its own colour, and a pool
        # that could be spent on anything would not be that.
        dict(player("acts", "Actions", "arrow", "silver"),
             pays_for=["act_%s" % c for c in COLOURS]),
        player("act_brown", "Brown", "arrow", "tan"),
        player("act_red", "Red", "arrow", "red"),
        player("act_blue", "Blue", "arrow", "blue"),
        player("act_purple", "Purple", "arrow", "magenta"),
        # Not a second buy — there is no such thing in this game. The piggy bank
        # keeps one unplayed chip through cleanup, at the cost of drawing one
        # fewer (rules.md §4).
        player("piggy", "Piggy bank", "pot", "pink"),
        player("buys", None, None, hidden=True),
        player("bought", None, None, hidden=True),
        player("to_draw", None, None, hidden=True),
        player("crashed", None, None, hidden=True),
        # The largest gem broken, kept apart from how many were sent: a 4-gem
        # cannot be countered and four 1-gems can, so "how big" and "how many"
        # are two questions and one number cannot answer both.
        player("broke", None, None, hidden=True),
        player("sent", None, None, hidden=True),
        player("combined", None, None, hidden=True),
        player("extra", None, None, hidden=True),
        player("picked", None, None, hidden=True),
        player("owed", None, None, hidden=True),
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
        {"key": "plus_piggy", "min": 0, "max": 9, "icon": "pot", "color": "pink", "number": False, "tags": ["hidden"]},
        {"key": "plus_draw", "min": 0, "max": 9, "icon": "card", "tags": ["hidden"]},
        {"key": "plus_pow", "min": 0, "max": 9, "icon": "coin", "color": "green", "tags": ["hidden"]},
        # A banner shape, not a quantity: the chip either has a reaction half or
        # it does not, and "shield 1" would be a number about nothing.
        {"key": "react", "min": 0, "max": 1, "icon": "shield", "number": False, "tags": ["hidden"]},
        {"key": "hits", "min": 0, "max": 1, "icon": "fist", "number": False, "tags": ["hidden"]},
        {"key": "panic", "min": 0, "max": 9, "tags": ["hidden"]},
        # How many Puzzle chips the bank is still short. Floored at zero, which
        # is what makes "ten less however many are already there" one subtraction
        # rather than a branch.
        {"key": "to_pick", "min": 0, "max": 10, "tags": ["hidden"]},
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
    out["chip"] = {"badges": ["value", "plus_pow", "plus_act", "plus_draw", "plus_piggy", "hits", "react"],
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
# Two numbers, not one. "crashed" is how many 1-gems are on their way and
# "broke" is the largest gem that was broken to send them — a counter-crash may
# answer four 1-gems and may not answer one 4-gem, and a single total cannot
# tell those apart.
#
# It ends with an announcement rather than with the gems arriving, and the two
# lines are the same line: emit puts the crash up to be answered, and if nobody
# answers it, it simply happened. A game with no counter-crash in it pays
# nothing for the word being there.
def crash_action(n_targets, bonus):
    return [
        "stat_set:crashed@mine.player:sum:value@target",
        "stat_set:broke@mine.player:max:value@target",
        "move_target_to:void",
        "fill:enemy.gem_pile:gem_1:sum:crashed@mine.player",
        "stat_damage:stock@stack_gem_1:sum:crashed@mine.player",
        "stat_gain:money@mine.player:%d" % bonus,
        "emit:crash",
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
                  "action": crash_action(1, 1), "spent": "mine.table"}},
        {"key": "double_crash", "text": "Double Crash Gem", "tags": ["chip", "trashable", "purple"],
         "asset": "dots:2:magenta",
         "tooltip": "As a Crash Gem, but up to two of your gems at once.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(own_gems, min=1, max=2),
                  "action": crash_action(2, 2), "spent": "mine.table"}},
        # No `play` at all, which is what makes it useless: it can be drawn,
        # it fills a hand slot, and there is nothing to do with it.
        {"key": "wound", "text": "Wound", "tags": ["chip", "trashable", "wound"],
         "asset": "circle:crimson",
         "tooltip": "This chip does nothing. It is free, and it is the only thing you can always afford: you must buy something every turn, and this is what is left when nothing else is in reach."},
    ]


# What a reaction to a crash is allowed to answer. There has to be a crash on
# the way, and the *largest gem broken to send it* has to be under a four — the
# rulebook's one exception, and the reason "broke" is a second number rather
# than the same one read twice.
ANSWERABLE = ["crashed@enemy.player >= 1", "broke@enemy.player <= 3"]


# A wound is gained rather than bought when a chip inflicts one, and both go to
# the discard: taking one out of the bank is the same two lines everywhere.
def gain_wound(who="mine"):
    return ["fill:%s.discard:wound:1" % who, "stat_damage:stock@stack_wound:1"]


# The names, banners and pictures of a Puzzle chip, which are the same three
# facts for all fifty-one of them. A banner of None is the grey one Option
# Select wears: no colour tag, so by_colour leaves its cost a plain action.
PUZZLE_NAMES = {k: name for k, name, _, _ in PUZZLE_ALL}


def shape(key, banner):
    tags = ["chip", "trashable", "puzzle"] + ([banner] if banner else [])
    return {"text": PUZZLE_NAMES[key], "tags": tags,
            "asset": "polygon:6:%s" % (BANNER[banner] if banner else "slate")}


def puzzle_cards():
    hand_gem = {"type": "card", "tags": ["gem"], "zones": ["hand"], "count": 1, "owner": "anyone"}
    hand_chip = {"type": "card", "tags": ["chip"], "zones": ["hand"], "count": 1, "owner": "anyone"}
    own_gems = {"type": "card", "tags": ["gem"], "zones": ["gem_pile"], "owner": "anyone"}
    act = lambda extra: {"phases": ["action"], "cost": {"acts@mine.player": 1}, "action": extra + ["move_to:mine.table"]}
    ongoing_play = lambda: {"phases": ["action"], "cost": {"acts@mine.player": 1},
                            "action": [], "spent": "mine.ongoing"}

    # "Trash a chip, then gain one costing up to N more" — three chips say it and
    # none of them needed a new verb. The allowance is handed over as *money*, so
    # the ordinary price of every pile does the gating, and the borrowed buy phase
    # is where it gets spent. A chip nobody can buy carries no price, so trashing
    # a character chip allows exactly N.
    def allowance(more):
        return ["stat_set:money@mine.player:sum:price@target",
                "stat_gain:money@mine.player:%d" % more,
                "stat_set:buys@mine.player:1",
                "move_target_to:void",
                "push_phase:react_buy"]

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
         "play": act(gain_wound("enemy")),
         "reactions": [{"to": "attack", "text": "Wound the attacker",
                        "action": gain_wound("enemy"), "spent": "mine.discard"}]},
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
         "play": act(["stat_gain:act_red@mine.player:1",
                      "fill:enemy.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1"])},
        {"key": "gem_essence", "text": "Gem Essence", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Trash a gem out of your hand and take four actions for it.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": hand_gem,
                  "action": ["move_target_to:void"]
                            + ["stat_gain:%s:1" % arrow(c) for c in COLOURS]
                            + ["move_to:mine.table"]}},
        {"key": "one_two_punch", "text": "One-Two Punch", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Two actions.",
         "play": act(["stat_gain:acts@mine.player:2"])},
        {"key": "one_of_each", "text": "One of Each", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "An action, a buy, a gem power and a chip — one of each of the four things a chip can give you.",
         "play": act(["stat_gain:acts@mine.player:1", "stat_gain:piggy@mine.player:1",
                      "stat_gain:money@mine.player:1", "draw_from:mine.bag:mine.hand:1"])},
        {"key": "roundhouse", "text": "Roundhouse", "tags": ["chip", "trashable", "puzzle", "brown"],
         "asset": "polygon:6:tan",
         "tooltip": "Keep your action and draw two chips.",
         "play": act(["stat_gain:acts@mine.player:1", "draw_from:mine.bag:mine.hand:2"])},
        # --- the rest of the base game -------------------------------------
        {"key": "chip_damage", **shape("chip_damage", "red"),
         "play": act(["stat_gain:act_red@mine.player:1", "show:mine.discard:optional"]),
         "chosen": {"action": ["move_target_to:mine.bag:top"]}},
        {"key": "combos_are_hard", **shape("combos_are_hard", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["next_phase"], "spent": "void"}},
        {"key": "gems_to_gemonade", **shape("gems_to_gemonade", "purple"),
         "play": act(["draw_from:mine.bag:mine.hand:2"]),
         "reactions": [{"to": "crash", "text": "Negate the gems", "when": ANSWERABLE,
                        "action": ["destroy:mine.gem_1:sum:crashed@enemy.player",
                                   "stat_gain:stock@stack_gem_1:sum:crashed@enemy.player"],
                        "spent": "mine.discard"}]},
        {"key": "its_a_trap", **shape("its_a_trap", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:acts@mine.player:1"], "spent": "void"}},
        {"key": "iron_defense", **shape("iron_defense", "brown"),
         "play": act(["fill:mine.gem_pile:crash_gem:1", "stat_damage:stock@stack_crash_gem:1"])},
        # Their discard, chosen by them: priority crosses the table while the
        # offer is up, so "mine.hand" in here is the opponent's own hand.
        {"key": "knockdown", **shape("knockdown", "red"),
         "play": act(["stat_gain:act_purple@mine.player:1",
                      "set_priority:enemy.player", "show:mine.hand"]),
         "chosen": {"action": ["move_target_to:mine.discard", "clear_priority"]}},
        {"key": "master_puzzler", **shape("master_puzzler", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["next_phase"], "spent": "void"}},
        {"key": "mix_master", **shape("mix_master", "red"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(own_gems, count=2),
                  "action": ["resolve_challenge"], "spent": "mine.table"},
         "challenge": {"needs": ["sum:value@target <= 4"],
                       "pass": ["stat_set:combined@mine.player:sum:value@target",
                                "move_target_to:void",
                                "activate_zone:rules_combine",
                                "stat_gain:act_red@mine.player:1"],
                       "fail": ["stat_gain:act_red@mine.player:1"]}},
        {"key": "sale_prices", **shape("sale_prices", "brown"),
         "play": act(["stat_gain:money@mine.player:1"])},
        {"key": "secret_move", **shape("secret_move", "brown"),
         "abilities": [{"key": "upkeep", "text": "Secret Move",
                        "action": ["stat_gain:piggy@mine.player:1"]}],
         # It watches its *own* controller, which is what "whose": "mine" is for.
         "reactions": [{"to": "buy", "whose": "mine", "forced": "mandatory", "from": "board",
                        "where": ["tagged:purple@event >= 1"],
                        "action": [], "spent": "mine.discard"}],
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:acts@mine.player:1"], "spent": "mine.ongoing"}},
        {"key": "self_improvement", **shape("self_improvement", "blue"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"]),
                  "action": ["move_target_to:void"], "spent": "mine.table"},
         "reactions": [{"to": "attack", "text": "+3 chips",
                        "action": ["draw_from:mine.bag:mine.hand:3"], "spent": "mine.discard"}]},
        {"key": "stolen_purples", **shape("stolen_purples", "red"),
         "play": act(["show:enemy.hand:optional"]),
         "chosen": {"where": ["tagged:purple@target >= 1"],
                    "action": ["move_target_to:mine.discard"]}},
        {"key": "thinking_ahead", **shape("thinking_ahead", "blue"),
         "play": act(["stat_gain:money@mine.player:1"]),
         "reactions": [{"to": "attack", "text": "Become immune",
                        "action": ["counterspell"], "spent": "void"}]},
        # "Up to 2 more" is money, and the piles price themselves. The borrowed
        # buy phase is what lets the shopping happen inside an action.
        {"key": "training_day", **shape("training_day", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"]),
                  "action": ["stat_gain:piggy@mine.player:1"] + allowance(2),
                  "spent": "mine.table"}},

        # --- Shadows --------------------------------------------------------
        {"key": "axe_kick", **shape("axe_kick", "brown"),
         "play": act(["stat_gain:act_brown@mine.player:1", "draw_from:mine.bag:mine.hand:2"])},
        {"key": "bang_then_fizzle", **shape("bang_then_fizzle", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "needs": ["sum:value@mine.gem_pile <= 4"],
                  "action": ["stat_gain:acts@mine.player:2", "draw_from:mine.bag:mine.hand:2"],
                  "spent": "mine.table"}},
        {"key": "blues_are_good", **shape("blues_are_good", "blue"),
         "play": act(["stat_gain:act_blue@mine.player:1", "show:mine.bag:optional"]),
         "chosen": {"where": ["tagged:blue@target >= 1"],
                    "action": ["move_target_to:mine.hand"]},
         "reactions": [{"to": "attack", "text": "Become immune",
                        "action": ["counterspell"], "spent": "mine.discard"}]},
        {"key": "button_mashing", **shape("button_mashing", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:acts@mine.player:2"], "spent": "void"}},
        {"key": "chips_for_free", **shape("chips_for_free", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"]),
                  "action": ["draw_from:mine.bag:mine.hand:2"] + allowance(2),
                  "spent": "mine.table"}},
        {"key": "color_panic", **shape("color_panic", "red"),
         "play": act(["stat_gain:act_red@mine.player:1"])},
        {"key": "degenerate_trasher", **shape("degenerate_trasher", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"], min=0, max=2),
                  "action": ["move_target_to:void", "stat_gain:acts@mine.player:1"],
                  "spent": "mine.table"}},
        {"key": "ebb_or_flow", **shape("ebb_or_flow", "blue"),
         "play": act(["options:ef_trash,ef_ante"]),
         "reactions": [{"to": "attack", "text": "Choose one",
                        "action": ["options:ef_trash,ef_ante"], "spent": "mine.discard"}]},
        {"key": "hundred_fist", **shape("hundred_fist", "brown"), "play": ongoing_play(),
         "reactions": [{"to": "attack", "whose": "mine", "from": "board",
                        "text": "Crash a gem of your own",
                        "target": {"type": "card", "tags": ["gem"], "zones": ["gem_pile"],
                                   "owner": "mine", "count": 1},
                        "action": crash_action(1, 0)}]},
        {"key": "improvisation", **shape("improvisation", "blue"),
         "play": act(["draw_from:mine.bag:mine.hand:2"])},
        {"key": "just_a_scratch", **shape("just_a_scratch", "red"),
         "play": act(["options:js_wound,js_trash"])},
        {"key": "money_for_nothing", **shape("money_for_nothing", "blue"),
         "play": act(["fill:mine.hand:gem_2:1", "stat_damage:stock@stack_gem_2:1"]),
         "reactions": [{"to": "attack", "text": "Take a gem from the bank",
                        "action": ["fill:mine.hand:gem_1:1", "stat_damage:stock@stack_gem_1:1"],
                        "spent": "mine.discard"}]},
        {"key": "now_or_later", **shape("now_or_later", "brown"),
         "play": act(["options:nl_chips,nl_trash"])},
        {"key": "one_true_style", **shape("one_true_style", "purple"),
         "play": act(["stat_gain:act_brown@mine.player:1", "stat_gain:act_red@mine.player:1",
                      "stat_gain:act_blue@mine.player:1"])},
        # No play at all, and that is the honest shape: copy: needs a card to
        # copy and the bank holds plates. A chip you cannot pick up is exactly
        # what Wound is, and this says why in its tooltip.
        {"key": "option_select", **shape("option_select", None)},
        {"key": "ouch", **shape("ouch", "red"),
         "play": act(["fill:enemy.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1"]
                     + gain_wound("enemy"))},
        # The offer opens for them, and each branch hands priority back.
        {"key": "pick_your_poison", **shape("pick_your_poison", "red"),
         "play": act(["stat_gain:act_red@mine.player:1", "draw_from:mine.bag:mine.hand:1",
                      "stat_gain:piggy@mine.player:1",
                      "set_priority:enemy.player", "options:pp_ante,pp_discard"])},
        {"key": "punch_punch_kick", **shape("punch_punch_kick", "brown"),
         "play": act(["stat_gain:acts@mine.player:2", "draw_from:mine.bag:mine.hand:1"])},
        {"key": "repeated_jabs", **shape("repeated_jabs", "red"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["fill:enemy.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1"],
                  "spent": "mine.bag"}},
        {"key": "risk_to_riskonade", **shape("risk_to_riskonade", "brown"),
         "play": act(["fill:mine.gem_pile:gem_3:1", "stat_damage:stock@stack_gem_3:1",
                      "each_seat:draw_from:mine.bag:mine.hand:2"])},
        {"key": "safe_keeping", **shape("safe_keeping", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": {"type": "card", "tags": ["gem_1"], "zones": ["gem_pile"],
                             "owner": "mine", "min": 0, "max": 1},
                  "action": ["stat_gain:acts@mine.player:1", "stat_gain:piggy@mine.player:1",
                             "move_target_to:mine.bag"],
                  "spent": "mine.table"}},
        {"key": "signature_move", **shape("signature_move", "brown"),
         "play": act(["show:mine.bag:optional"]),
         "chosen": {"where": ["tagged:character@target >= 1"],
                    "action": ["move_target_to:mine.hand"]}},
        {"key": "the_hammer", **shape("the_hammer", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_gem, min=0, max=3),
                  "action": ["move_target_to:mine.gem_pile",
                             "stat_gain:acts@mine.player:count:gem@target",
                             "draw_from:mine.bag:mine.hand:count:gem@target"],
                  "spent": "mine.table"}},
        {"key": "x_copy", **shape("x_copy", "brown"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"]),
                  "action": ["copy:target:play:2"], "spent": "mine.table"}},

        # --- promotional -----------------------------------------------------
        {"key": "combinatorics", **shape("combinatorics", "purple"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:act_brown@mine.player:1"], "spent": "mine.ongoing"}},
        {"key": "custom_combo", **shape("custom_combo", "brown")},
        {"key": "dashing_strike", **shape("dashing_strike", "red"),
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": {"type": "card", "tags": ["gem_1"], "zones": ["gem_pile"],
                             "owner": "mine", "count": 1},
                  "action": ["stat_gain:act_brown@mine.player:1", "move_target_to:void",
                             "stat_gain:stock@stack_gem_1:1",
                             "fill:enemy.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1"],
                  "spent": "mine.table"}},
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
         "play": act(["stat_gain:act_blue@mine.player:1"] + gain_wound("enemy"))},
        # Two cards. Laying it out turns it into the ongoing half; answering
        # from hand instead cancels the attack outright, which is what immunity
        # means with two players at the table.
        {"key": "bubble_shield", "text": "Bubble Shield", "tags": ["chip", "character", "blue"],
         "asset": "circle:cyan",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["move_to:mine.ongoing", "transform:self:bubble_shield_up"]},
         "reactions": [{"to": "attack", "text": "Become immune",
                        "action": ["counterspell"], "spent": "mine.discard"}]},
        {"key": "bubble_shield_up", "text": "Bubble Shield", "tags": ["chip", "character", "blue"],
         "asset": "circle:cyan",
         "reactions": [{"to": "crash", "when": ANSWERABLE,
                        "action": ["destroy:mine.gem_1:1", "stat_gain:stock@stack_gem_1:1",
                                   "move_to:mine.discard", "transform:self:bubble_shield"]}]},
        {"key": "protective_ward", "text": "Protective Ward", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:teal",
         "tooltip": "+1 blue action. Ongoing: nobody may combine without discarding a Puzzle chip first. The tax is not built; the action it gives back is.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "action": ["stat_gain:act_blue@mine.player:1", "move_to:mine.ongoing"]}},
        # Jaina
        {"key": "playing_with_fire", "text": "Playing with Fire", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:crimson",
         "tooltip": "Ante a 1-gem into your own pile, then take two actions and a chip for it.",
         "play": act(["fill:mine.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1",
                      "stat_gain:act_brown@mine.player:1", "stat_gain:act_red@mine.player:1",
                      "draw_from:mine.bag:mine.hand:1"])},
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
                  "action": crash_action(2, 2)[:-1] + ["move_to:mine.table"]
                            + gain_wound() + gain_wound() + ["emit:crash"]}},
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
        # "Costing up to 2 more" is handed over as *money*, so the ordinary price
        # of every pile does the gating and nothing had to be invented for it.
        # The borrowed buy phase is what lets them spend it out of turn.
        {"key": "rigorous_training", "text": "Rigorous Training", "tags": ["chip", "character", "blue"],
         "asset": "circle:green",
         "reactions": [{"to": "buy", "text": "Trash a chip and gain a better one",
                        "where": ["tagged:purple@event >= 1"],
                        "target": {"type": "card", "zones": ["hand"], "owner": "mine", "count": 1,
                                   "where": ["tagged:purple@target < 1"]},
                        "action": ["stat_set:money@mine.player:sum:price@target",
                                   "stat_gain:money@mine.player:2",
                                   "stat_set:buys@mine.player:1",
                                   "move_target_to:void",
                                   "push_phase:react_buy"],
                        "spent": "mine.discard"}]},
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
         "play": act(["stat_gain:act_brown@mine.player:1", "stat_gain:piggy@mine.player:1",
                      "draw_from:mine.bag:mine.hand:1"])},
        {"key": "speed_of_the_fox", "text": "Speed of the Fox", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:amber",
         "tooltip": "Two actions and a chip.",
         "play": act(["stat_gain:act_brown@mine.player:2", "draw_from:mine.bag:mine.hand:1"])},
        # Grave
        {"key": "reversal", "text": "Reversal", "tags": ["chip", "character", "purple"],
         "asset": "circle:navy",
         "play": act(["draw_from:mine.bag:mine.hand:2"]),
         "reactions": [{"to": "crash", "text": "Counter-crash", "when": ANSWERABLE,
                        "target": {"type": "card", "tags": ["gem"], "zones": ["gem_pile"],
                                   "owner": "mine", "count": 1},
                        "action": ["stat_set:crashed@mine.player:sum:value@target",
                                   "stat_set:broke@mine.player:max:value@target",
                                   "move_target_to:void",
                                   # Cancel, then send what is left of each. "sent"
                                   # holds our side while theirs is being reduced,
                                   # because both numbers are needed at once and a
                                   # stat cannot be read after it has been changed.
                                   "destroy:mine.gem_1:sum:crashed@enemy.player",
                                   "stat_gain:stock@stack_gem_1:sum:crashed@enemy.player",
                                   "stat_set:sent@mine.player:sum:crashed@mine.player",
                                   "stat_damage:sent@mine.player:sum:crashed@enemy.player",
                                   "stat_damage:crashed@enemy.player:sum:crashed@mine.player",
                                   "stat_set:crashed@mine.player:sum:sent@mine.player",
                                   "fill:mine.gem_pile:gem_1:sum:crashed@enemy.player",
                                   "stat_damage:stock@stack_gem_1:sum:crashed@enemy.player",
                                   "fill:enemy.gem_pile:gem_1:sum:crashed@mine.player",
                                   "stat_damage:stock@stack_gem_1:sum:crashed@mine.player",
                                   "emit:crash"],
                        "spent": "mine.discard"}]},
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
         "play": act(["draw_from:mine.bag:mine.hand:1", "stat_gain:piggy@mine.player:1"]),
         "reactions": [{"to": "crash", "text": "Send the gems back to the bank",
                        "when": ANSWERABLE,
                        "action": ["destroy:mine.gem_1:sum:crashed@enemy.player",
                                   "stat_gain:stock@stack_gem_1:sum:crashed@enemy.player"],
                        "spent": "mine.discard"}]},
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
                             "stat_gain:act_brown@mine.player:1",
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
         # The whole hand comes up — revealing it is half the printed rule — and
         # only their largest gem may be taken out of it. "Largest" is a
         # comparison between the candidate and the pile it is in, which is what
         # a condition over a scope has always been able to say.
         "chosen": {"where": ["tagged:gem@target >= 1",
                              "sum:value@target >= max:value@options"],
                    "action": ["stat_set:crashed@mine.player:sum:value@target",
                               "stat_set:broke@mine.player:max:value@target",
                               "move_target_to:void",
                               "fill:enemy.discard:gem_1:sum:crashed@mine.player",
                               "stat_damage:stock@stack_gem_1:sum:crashed@mine.player",
                               "emit:crash"]}},
        {"key": "no_more_lies", "text": "No More Lies", "tags": ["chip", "character", "red"],
         "asset": "polygon:7:pink",
         "tooltip": "Trash up to two chips out of your hand. Character chips cannot be trashed.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, tags=["trashable"], min=0, max=2),
                  "action": ["move_target_to:void", "stat_gain:act_red@mine.player:1",
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
                  "action": ["draw_from:mine.bag:mine.hand:1"] + crash_action(1, 0),
                  "spent": "mine.table"}},
        {"key": "creative_thoughts", "text": "Creative Thoughts", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:cyan",
         "tooltip": "Any different two of: an action, a buy, a gem power, a chip.",
         "play": act(["options:ct_ab,ct_am,ct_ac,ct_bm,ct_bc,ct_mc"])},
        # Geiger
        {"key": "research_development", "text": "Research & Development",
         "tags": ["chip", "character", "brown"], "asset": "polygon:7:yellow",
         "play": act(["stat_gain:acts@mine.player:1", "show:mine.bag:optional"]),
         "chosen": {"where": ["tagged:purple@target >= 1"],
                    "action": ["move_target_to:mine.hand"]}},
        {"key": "future_sight", "text": "Future Sight", "tags": ["chip", "character", "brown"],
         "asset": "polygon:7:yellow",
         "tooltip": "Two chips, then put up to two out of your hand back on the bag. Which order they go back in is not yours to say here.",
         "play": {"phases": ["action"], "cost": {"acts@mine.player": 1},
                  "target": dict(hand_chip, min=0, max=2),
                  "action": ["draw_from:mine.bag:mine.hand:2",
                             "move_target_to:mine.bag", "move_to:mine.table"]}},
        {"key": "its_time_for_the_past", "text": "It's Time for the Past",
         "tags": ["chip", "character", "brown"], "asset": "polygon:7:yellow",
         "play": act(["stat_gain:acts@mine.player:1", "show:mine.discard:optional"]),
         "chosen": {"where": ["not_tagged:puzzle@target >= 1"],
                    "action": ["move_target_to:mine.hand"]}},
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
         # It watches its own controller buying, which "whose": "mine" is for. The
         # chip comes as the purchase is made rather than at the end of the turn:
         # a turn ending announces nothing, so there is no later moment to hang it on.
         # Two halves, and they are two reactions: the buy is what it watches for
         # and the turn ending is when it pays. A stat carries the answer from one
         # to the other, because an event knows what it is and not what came before.
         "play": ongoing(),
         "reactions": [{"to": "buy", "whose": "mine", "forced": "mandatory", "from": "board",
                        "where": ["tagged:puzzle_stack@event >= 1"],
                        "action": ["stat_set:owed@mine.player:1"]},
                       {"to": "turn_end", "whose": "mine", "forced": "mandatory", "from": "board",
                        "when": ["owed@mine.player >= 1"],
                        "action": ["draw_from:mine.bag:mine.hand:1",
                                   "stat_set:owed@mine.player:0"]}]},
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
    P = "stat_gain:piggy@mine.player:1"
    Mo = "stat_gain:money@mine.player:1"
    C = "draw_from:mine.bag:mine.hand:1"
    return [
        choice("vs_tempo", "An action and a piggy bank", [A, P]),
        choice("vs_money", "Two gem power", ["stat_gain:money@mine.player:2"]),
        choice("vs_chips", "Two chips", ["draw_from:mine.bag:mine.hand:2"]),
        choice("tr_tempo", "An action and a chip", [A, C]),
        choice("tr_money", "Two gem power and a piggy bank", ["stat_gain:money@mine.player:2", P]),
        choice("ct_ab", "An action and a piggy bank", [A, P]),
        choice("ct_am", "An action and a gem power", [A, Mo]),
        choice("ct_ac", "An action and a chip", [A, C]),
        choice("ct_bm", "A piggy bank and a gem power", [P, Mo]),
        choice("ct_bc", "A piggy bank and a chip", [P, C]),
        choice("ct_mc", "A gem power and a chip", [Mo, C]),
        choice("ef_trash", "Everybody trashes a 1-gem",
               ["each_seat:destroy:mine.gem_1:1", "stat_gain:stock@stack_gem_1:%d" % len(SEATS)]),
        choice("ef_ante", "You ante a 2-gem",
               ["fill:mine.gem_pile:gem_2:1", "stat_damage:stock@stack_gem_2:1"]),
        choice("js_wound", "Each opponent gains a wound", gain_wound("enemy")),
        choice("js_trash", "Trash a wound and take a red action",
               ["destroy:mine.hand:1", "stat_gain:stock@stack_wound:1",
                "stat_gain:act_red@mine.player:1"]),
        choice("nl_chips", "Two chips", ["draw_from:mine.bag:mine.hand:2"]),
        choice("nl_trash", "Trash a gem and a wound from your hand",
               ["destroy:mine.hand:2"]),
        # Both of Pick Your Poison's branches hand priority back, because the
        # seat reading them is the one who was given it.
        choice("pp_ante", "Ante a 1-gem",
               ["fill:mine.gem_pile:gem_1:1", "stat_damage:stock@stack_gem_1:1",
                "clear_priority"]),
        choice("pp_discard", "Discard two chips",
               ["move:mine.hand:mine.discard", "clear_priority"]),
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
    # The piggy bank: your own hand comes up in the offer and you may keep one
    # chip out of the discard, drawing one fewer for it. Declinable, because
    # keeping nothing is the usual answer — and a `chosen` block rather than an
    # action list, because what happens depends on which chip.
    out.append(("rules_piggy", {
        "key": "piggy_bank", "text": "Piggy bank", "tags": ["immutable"],
        "abilities": [{"key": "piggy_bank", "text": "Piggy bank",
                       "when": ["piggy@mine.player >= 1"],
                       "action": ["show:mine.hand:optional"]}],
        "chosen": {"action": ["move_target_to:mine.stash",
                              "stat_damage:to_draw@mine.player:1"]}}))
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

    def plate(chip, name, cost, stock, asset, value=None, banner=None, puzzle=False):
        # "react_buy" beside "buy": a reaction that hands somebody an allowance
        # pushes that phase, and a plate that only worked in the turn owner's
        # own buy phase would leave them holding money and nothing to spend it
        # on. The cost is unchanged, so nothing is cheaper for being borrowed.
        buy = {"phases": ["buy", "react_buy"],
               "cost": {"buys@mine.player": 1, "stock@self": 1},
               "action": ["fill:mine.discard:%s:1" % chip, "stat_gain:bought@mine.player:1"]}
        if cost > 0:
            buy["cost"]["money@mine.player"] = cost
        # A plate wears the banner colour of what it sells only where a rule
        # reads it: buying is an event, and a reaction to a purple being bought
        # asks the plate, since the chip itself is still in the box.
        tags = ["stack", stack_key(chip), "immutable"] + ([banner] if banner else [])
        # What the bank draft counts. Eight plates are always in the bank and
        # ten Puzzle chips join them, so "is the bank full" is one number and
        # the basics never enter into it.
        if puzzle:
            tags.append("puzzle_stack")
        out.append({"key": stack_key(chip), "text": name,
                    "tags": tags,
                    "asset": asset, "tooltip": words.get(chip, ""),
                    "card_stats": dict({"price": cost, "stock": stock},
                                       **({"value": value} if value else {})),
                    "activate": buy})

    for n, cost, stock in GEMS:
        plate(gem_key(n), "%d-gem" % n, cost, stock, "diamond:green", value=n)
    for key, name, cost, stock in PURPLES:
        plate(key, name, cost, stock, "circle:magenta", banner="purple")
    plate("wound", "Wound", 0, 24, "circle:crimson")
    for key, name, cost, banner in PUZZLE_ALL:
        plate(key, name, cost, PUZZLE_STOCK,
              "polygon:6:%s" % (BANNER[banner] if banner else "slate"),
              puzzle=True)
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
                                              "set_owner:self:mine"],
                             "spent": "mine.fighter"}})
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
        # The bank draft. Two buttons and no new engine anything: one opens the
        # box face up and takes what is picked, the other shuffles what is left
        # and deals the shortfall. Ten Puzzle chips is the bank (rules.md \u00a73),
        # and the eight that are always there never enter the count.
        {"key": "pick_chip", "text": "Choose a chip", "tags": ["immutable"],
         "asset": "square:teal",
         "tooltip": "Open the box and put one Puzzle chip into the bank. Ten of them make a game.",
         "activate": {"phases": ["build_bank"], "action": ["show:chip_box:optional"]},
         "chosen": {"action": ["move_target_to:bank"]}},
        {"key": "randomize_bank", "text": "Randomise the rest", "tags": ["immutable"],
         "asset": "square:amber",
         "tooltip": "Fill whatever is left of the bank at random. Press it first for a random bank, or after "
                    "choosing a few to leave the rest to chance.",
         "activate": {"phases": ["build_bank"],
                      "action": ["shuffle:chip_box",
                                 "stat_set:to_pick@clock:10",
                                 "stat_damage:to_pick@clock:count:puzzle_stack@bank",
                                 "draw_from:chip_box:bank:sum:to_pick@clock"]}},
        # The way out of a borrowed buy phase. No cost: buying at least one chip
        # is a rule about your own turn, and this is not one.
        {"key": "finish_shopping", "text": "Done", "tags": ["immutable"],
         "asset": "square:slate",
         "tooltip": "Finish the shopping you were handed and give the turn back. Whatever you did not spend goes back with it.",
         "activate": {"phases": ["react_buy"],
                      "action": ["stat_set:money@mine.player:0",
                                 "stat_set:buys@mine.player:0",
                                 "pop_phase"]}},
        {"key": "end_turn", "text": "End turn", "tags": ["immutable"],
         "asset": "square:slate",
         "tooltip": "End your turn. You must have bought at least one chip — a Wound is free, and that is the point.",
         "activate": {"phases": ["buy"], "cost": {"bought@mine.player": 1},
                      "action": ["next_phase"]}},
    ]


def other_cards():
    return [
        {"key": "clock", "text": "The bank", "tags": ["clock", "immutable"],
         "card_stats": {"panic": 0, "to_pick": 0}},
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
         "ends_when": "picked@mine.player >= 1", "next": [{"then": "build_bank"}]},
        # The bank is drafted, not printed. Ten Puzzle chips out of fifty-one is
        # what a game of Puzzle Strike is, and which ten is the first decision at
        # the table \u2014 so it is a phase, with two buttons and no hurry.
        {"key": "build_bank", "type": "player_input", "zone": "hand",
         "label": "Build the bank: ten Puzzle chips, chosen or at random",
         "ends_when": "count:puzzle_stack@bank >= 10", "next": [{"then": "deal"}]},
        {"key": "deal", "type": "automatic",
         "actions": ["each_seat:shuffle:mine.bag",
                     "each_seat:draw_from:mine.bag:mine.hand:%d" % HAND],
         "next": [{"then": "action"}]},
        # The ante is the action phase's own business rather than a phase before
        # it, because only a phase a player acts in can hand the turn over: an
        # automatic one has nobody to hand it to. So everything a turn resets,
        # then the ongoing chips, then the ante, all on the way in.
        #
        # No `ends_when`. It used to be "no actions left", which cannot be asked
        # once an arrow has four colours — a condition is one comparison, and a
        # player holding a red arrow and no black one has actions left. It is
        # also the wrong question: the rulebook says play *up to* one chip, so
        # declining to spend an arrow is a move. The Done acting button is the
        # answer to both.
        {"key": "action", "type": "player_input", "seat": "next", "zone": "hand",
         "label": "Play an action chip",
         "actions": ["stat_set:money@mine.player:0",
                     "stat_set:acts@mine.player:1"]
                    + ["stat_set:%s:0" % arrow(c) for c in COLOURS]
                    + ["stat_set:piggy@mine.player:0",
                       "stat_set:buys@mine.player:1",
                       "stat_set:bought@mine.player:0",
                       "stat_set:panic@clock:count:spent@bank",
                       # Whatever was kept back last cleanup, back in hand — the
                       # other half of the piggy bank, and the reason the stash
                       # is a zone rather than a flag on a chip.
                       "move:mine.stash:mine.hand",
                       "activate_zone:mine.ongoing",
                       "activate_zone:rules_ante"],
         "next": [{"then": "buy"}]},
        {"key": "buy", "type": "player_input", "zone": "hand",
         "label": "Play gems for money, then buy",
         "next": [{"then": "cleanup"}]},
        # Shopping somebody else handed you. A reaction that gives an allowance
        # pushes this over whatever was happening, so the reactor spends and
        # buys with the turn still where it was; the Done button pops it and
        # takes back whatever was not spent. It routes to itself because a phase
        # that is popped never asks where to go next.
        {"key": "react_buy", "type": "player_input", "zone": "hand",
         "label": "Spend what you were given, then finish",
         "next": [{"then": "react_buy"}]},
        # The bag refills itself from the discard the moment it empties, so the
        # draw is one line and the height bonus can simply add to it. This was
        # three phases in a loop, because an action list cannot branch and the
        # reshuffle had to happen between two draws; the zone knowing its own
        # discard deletes the loop and — the point — makes it work inside a
        # chip's action list too, where no phase could reach.
        # Two phases, because the piggy bank asks a question in the middle of
        # one. An offer opens over the phase that ran it and the rest of that
        # phase's actions have already run by then, so anything that must happen
        # *after* the answer belongs to the next phase — here, discarding the
        # hand the chip was kept out of.
        {"key": "cleanup", "type": "automatic",
         "actions": ["move:mine.table:mine.discard",
                     "stat_set:to_draw@mine.player:%d" % HAND,
                     "activate_zone:rules_height",
                     "activate_zone:rules_piggy"],
         "next": [{"then": "cleanup_draw"}]},
        # The last thing a turn does, so this is the moment "at the end of your
        # turn" means. It announces on the way out rather than on the way in,
        # because a chip that pays out then is owed it once the hand is redrawn.
        {"key": "cleanup_draw", "type": "automatic", "emits": {"end": "turn_end"},
         "actions": ["move:mine.hand:mine.discard",
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
        # Two words the whole game answers to, said once each rather than on
        # ninety chips. A red chip announces an attack when it is played, so a
        # shield names "attack" and never has to list what might carry one; the
        # bank hands "buyable" to whatever lies in it through `applies`, so
        # *buying* announces itself without a single plate knowing.
        "tags": {"red": {"emits": {"play": "attack"}},
                 "buyable": {"emits": {"activate": "buy"}}},
        "zones": zones(),
        "phases": phases(),
        "players": [{"card": k} for k, _ in SEATS],
        "cards": (seat_cards() + other_cards() + button_cards() + bank_cards()
                  + by_colour(priced(lands(say(gem_cards() + purple_cards() + puzzle_cards()
                                                 + character_chips()))))
                  + character_cards() + [c for _, c in rule_cards()]),
        "setup": {"place": [{"card": "clock", "zone": "sys"},
                            {"card": "done_acting", "zone": "controls", "at": ["a1"]},
                            {"card": "end_turn", "zone": "controls", "at": ["b1"]},
                            {"card": "finish_shopping", "zone": "controls", "at": ["c1"]},
                            {"card": "pick_chip", "zone": "controls", "at": ["d1"]},
                            {"card": "randomize_bank", "zone": "controls", "at": ["e1"]}]
                           + [{"card": stack_key(gem_key(n)), "zone": "bank"} for n, _, _ in GEMS]
                           + [{"card": stack_key(k), "zone": "bank"} for k, _, _, _ in PURPLES]
                           + [{"card": "stack_wound", "zone": "bank"}]
                           + [{"card": stack_key(k), "zone": "chip_box"} for k, _, _, _ in PUZZLE_ALL]
                           + [{"card": c["key"], "zone": z} for z, c in rule_cards()]},
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = guard.destination(os.path.join(here, "..", "game", "games", "puzzle_strike.json"))
    if out is None:
        sys.exit(1)
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
