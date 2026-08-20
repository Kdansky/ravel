#!/usr/bin/env python3
"""Generate game/games/the_crew.json.

Forty playing cards and thirty-six task cards, each carrying the same eight
numbers, is data. What is not data lives here in one readable place: the trick
arithmetic, the phase walk that plays a trick, and the layout.

The rules are transcribed in ideas/the_crew/rules.md, from the KOSMOS rulebook
and mission logbook; nothing here invents one. Three seats, which is the
smallest real crew — the two-player game is the JARVIS variant and a different
thing.

    python3 tools/make_the_crew.py
"""

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt

# key, printed name, palette colour, suit number. Rocket is a suit like any
# other, because it is one: led first, it must be followed (rules.md §2 step 4).
SUITS = [
    ("pink",   "Pink",   "pink",   1),
    ("blue",   "Blue",   "blue",   2),
    ("green",  "Green",  "green",  3),
    ("yellow", "Yellow", "yellow", 4),
]
ROCKET = ("rocket", "Rocket", "silver", 5)

SEATS = [("north", "North"), ("east", "East"), ("south", "South")]
DECK = 40
# Three seats do not divide forty, so one crew member holds a fourteenth card
# that is never played: thirteen tricks and the deal is spent (rules.md §1).
TRICKS = DECK // len(SEATS)
MAX_TASKS = 5

# Every scratch number the trick arithmetic writes, and the bound that makes it
# arithmetic: **a floor of zero is what turns stat_damage into max(0, a - b)**,
# which is the only clamp the amount grammar has.
SCRATCH = ["suit", "value", "trump", "live", "over", "contend", "best", "gap"]


# --- the trick arithmetic ------------------------------------------------
#
# Every card in the trick answers one question with numbers: what would it take
# to win with. A card that did not follow suit and is not a rocket contends
# with nothing, and the rest contend with their value, plus a hundred for being
# a rocket — which is what "trump always wins, however low" is, written as a
# number instead of a branch.

def contend():
    return [
        # live = 1 exactly when this card's suit is the led one. Two clamped
        # subtractions, because |a - b| has no spelling and does not need one.
        "stat_set:live@self:1",
        "stat_set:gap@self:sum:suit@self",
        "stat_damage:gap@self:sum:led@plan",
        "stat_damage:live@self:sum:gap@self",
        "stat_set:gap@self:sum:led@plan",
        "stat_damage:gap@self:sum:suit@self",
        "stat_damage:live@self:sum:gap@self",
        # A rocket contends whether or not it followed, and a rocket *led* is
        # both — so the two flags add to two and have to come back to one.
        # min(a, k) is a - max(0, a - k): the same floor, used twice.
        "stat_gain:live@self:sum:trump@self",
        "stat_set:over@self:sum:live@self",
        "stat_damage:over@self:1",
        "stat_damage:live@self:sum:over@self",
        "stat_set:contend@self:sum:value@self",
        "stat_gain:contend@self:sum:trump@self:x:100",
        "stat_set:contend@self:sum:contend@self:x:sum:live@self",
        # How far short of the best this one is. Zero for exactly one card: the
        # led card always contends, so the best is never zero, and everything
        # that contends with nothing is short by all of it.
        "stat_set:gap@self:sum:best@self",
        "stat_damage:gap@self:sum:contend@self",
    ]


# --- cards ---------------------------------------------------------------

def seat_cards():
    return [{"key": k, "text": t, "tags": [k + "_side"],
             "card_stats": {"has_r4": 0, "tricks_won": 0}} for k, t in SEATS]


def playing_cards():
    out = []
    for key, name, colour, suit in SUITS + [ROCKET]:
        top = 4 if key == "rocket" else 9
        for v in range(1, top + 1):
            rocket = key == "rocket"
            stats = {"suit": suit, "value": v, "trump": 1 if rocket else 0,
                     "live": 0, "over": 0, "contend": 0, "best": 0, "gap": 0}
            card = {
                "key": f"{key}_{v}",
                "text": f"{name} {v}",
                "asset": f"stripes:{v}:{colour}",
                "tags": ["play_card", colour] + ([] if rocket else [f"c_{key}{v}"]),
                "card_stats": stats,
                # The whole of follow-suit, on every card in the game. Leading,
                # no card matches a led suit of zero, so flow's escape hatch
                # ("nothing else here is playable") opens the hand at once.
                "play": {"needs": ["suit@self == led@plan"],
                         "action": ["set_owner:self:mine", "move_to:trick"]},
            }
            if not rocket:
                # A card marks the task that wanted it, by the tag the two
                # share. Written per card because a scope cannot be named at run
                # time; it is one line each and the generator writes them.
                card["abilities"] = [{"key": "claim", "text": "Claim",
                                      "action": [f"stat_set:hit@each.c_{key}{v}:1"]}]
            out.append(card)
    return out


def task_cards():
    out = []
    for key, name, colour, _ in SUITS:
        for v in range(1, 10):
            out.append({
                "key": f"task_{key}_{v}",
                "text": f"Win {name.lower()} {v}",
                "tooltip": f"Fulfilled when its owner wins a trick holding the {name.lower()} {v}."
                           " If anyone else wins that trick, the mission is lost on the spot.",
                "asset": f"stripes:{v}:{colour}:slate",
                "tags": ["task", f"c_{key}{v}"],
                "card_stats": {"hit": 0},
                "play": {"action": ["set_owner:self:mine", "move_to:tasks"]},
            })
    return out


def mission_cards():
    words = ["One", "Two", "Three", "Four", "Five"]
    return [{"key": f"m_{n}", "text": f"{words[n - 1]} task" + ("" if n == 1 else "s"),
             "story": f"{words[n - 1]} task card{'' if n == 1 else 's'} is dealt to the crew."
                      " The commander picks first, then round the table until they are gone.",
             "asset": f"polygon:{n + 2}:teal",
             "play": {"action": [f"stat_set:want@plan:{n}"]}}
            for n in range(1, MAX_TASKS + 1)]


def other_cards():
    return [
        {"key": "flight_plan", "text": "Flight plan", "tags": ["plan", "immutable"],
         "card_stats": {"led": 0, "tricks": 0, "want": 1}},
        {"key": "how_to_play", "text": "How to play", "asset": "polygon:5:teal",
         "play": {"phases": []},
         "tooltip": "Cooperative trick-taking. Everyone plays one card; you must follow the suit that"
                    " was led if you hold it, and may play anything if you do not. The highest card of"
                    " the led suit wins the trick — except that any rocket beats every colour, however"
                    " low, and the highest rocket beats the rest.\n\nThe winner of a trick leads the"
                    " next one. Whoever was dealt the rocket 4 is the commander: they pick first from"
                    " the tasks on offer and lead the first trick.\n\nA task is done when its owner"
                    " wins a trick containing the card it names. If anybody else wins that card, the"
                    " mission is lost at once — there is no second chance at it. Win by finishing"
                    " every task before the thirteenth trick is over.\n\nYou may not say what is in"
                    " your hand."},
        {"key": "mission_complete", "text": "Mission complete",
         "story": "Every task is done and the ship is where it should be. Log the attempt and take"
                  " the next mission.",
         "play": {"action": ["load_game:menu.json"]}},
        {"key": "mission_lost", "text": "Mission failed",
         "story": "A card the crew needed went to the wrong hands, or the tricks ran out with work"
                  " left. Reshuffle and fly it again.",
         "play": {"action": ["load_game:menu.json"]}},
    ]


# --- zones ---------------------------------------------------------------

def zones():
    # Three seats stacked down the left, each with a hand, a task row and a
    # done pile; the trick, the offer and the two decks down the right, clear of
    # the top-right corner the HUD draws into.
    hands = [[0.010, 0.008, 0.755, 0.100],
             [0.010, 0.240, 0.755, 0.332],
             [0.010, 0.707, 0.755, 0.799]]
    tasks = [[0.010, 0.108, 0.470, 0.228],
             [0.010, 0.340, 0.470, 0.460],
             [0.010, 0.575, 0.470, 0.695]]
    done = [[0.482, 0.108, 0.600, 0.228],
            [0.482, 0.340, 0.600, 0.460],
            [0.482, 0.575, 0.600, 0.695]]
    return [
        {"key": "hand", "type": "hand", "tags": ["per_seat"], "pos": hands},
        {"key": "tasks", "label": "Tasks", "type": "grid", "grid": [MAX_TASKS, 1],
         "tags": ["per_seat"], "pos": tasks},
        {"key": "archive", "label": "Done", "type": "pile",
         "tags": ["per_seat", "stacked"], "pos": done},
        {"key": "trick", "label": "The trick", "type": "grid", "grid": [len(SEATS), 1],
         "applies": ["in_trick"], "pos": [0.612, 0.350, 0.990, 0.560]},
        {"key": "deck", "label": "Deck", "type": "deck", "tags": ["shuffle"],
         "pos": [0.770, 0.240, 0.875, 0.332],
         "tooltip": "Forty cards: four colours of nine, and four rockets.",
         "contents": [f"{s[0]}_{v}" for s in SUITS for v in range(1, 10)]
                     + [f"rocket_{v}" for v in range(1, 5)]},
        {"key": "task_deck", "label": "Tasks", "type": "deck", "tags": ["shuffle"],
         "pos": [0.885, 0.240, 0.990, 0.332],
         "tooltip": "One task card for every colour card. Rockets are never a task.",
         "contents": [f"task_{s[0]}_{v}" for s in SUITS for v in range(1, 10)]},
        {"key": "task_offer", "label": "On offer", "type": "grid", "grid": [MAX_TASKS, 1],
         "pos": [0.612, 0.572, 0.990, 0.695]},
        {"key": "won", "label": "Taken", "type": "pile", "tags": ["face_down"],
         "tooltip": "Tricks already taken, set aside face down.",
         "pos": [0.010, 0.472, 0.150, 0.563]},
        {"key": "rules", "type": "pile", "pos": [0.165, 0.472, 0.305, 0.563],
         "contents": ["how_to_play"]},
        {"key": "console", "type": "grid", "grid": [1, 1], "tags": ["hidden"]},
        {"key": "mission", "type": "hand", "tags": ["hidden", "no_peek"],
         "pos": [0.22, 0.24, 0.78, 0.76],
         "contents": [f"m_{n}" for n in range(1, MAX_TASKS + 1)]},
    ]


# --- phases --------------------------------------------------------------

def deal():
    """Deal, then find the commander, then hand them the table.

    Both halves walk the seats by name, because there is no word for "every
    seat in turn" outside a phase — and the second walk is the only way a card
    sitting in a hand can be asked about at all: a tag reaches grid zones only,
    so "who holds the rocket 4" has to be asked once per seat, of the seat that
    holds it. What it writes is an ordinary stat, and the commander is then a
    computed tag over it, which every later rule can name.
    """
    out = []
    for i, (key, _) in enumerate(SEATS):
        n = TRICKS + (1 if i < DECK % len(SEATS) else 0)
        out += [f"set_active_seat:{key}_side", f"draw_from:deck:mine.hand:{n}"]
    for key, _ in SEATS:
        out += [f"set_active_seat:{key}_side",
                "stat_set:has_r4@mine.player:card:rocket_4@mine.hand"]
    return out + ["set_active_seat:commander",
                  "draw_from:task_deck:task_offer:sum:want@plan"]


def phases():
    follow = [{"key": f"follow_{i}", "type": "player_input", "seat": "next",
               "zone": "hand", "ends_after": 1,
               "label": "Follow the suit that was led, if you can",
               "next": [{"then": f"follow_{i + 1}" if i < len(SEATS) - 1 else "resolve"}]}
              for i in range(1, len(SEATS))]
    return [
        {"key": "setup", "type": "automatic", "actions": ["push_phase:mission"],
         "next": [{"then": "deal"}]},
        {"key": "deal", "type": "automatic", "actions": deal(),
         "next": [{"then": "draft"}]},
        # The commander picks first, and is already the seat that is up; every
        # other pick is an ordinary handover, so the draft is two phases and no
        # rule about who starts.
        {"key": "draft", "type": "player_input", "zone": "task_offer", "ends_after": 1,
         "label": "Commander: take a task",
         "next": [{"zone_empty": ["task_offer"], "then": "first_lead"}, {"then": "draft_on"}]},
        {"key": "draft_on", "type": "player_input", "seat": "next", "zone": "task_offer",
         "ends_after": 1, "label": "Take a task",
         "next": [{"zone_empty": ["task_offer"], "then": "first_lead"}, {"then": "draft_on"}]},
        {"key": "first_lead", "type": "automatic", "actions": ["set_active_seat:commander"],
         "next": [{"then": "lead"}]},
        {"key": "lead", "type": "player_input", "zone": "hand", "ends_after": 1,
         "label": "Lead a card", "next": [{"then": "led"}]},
        # Once, between the lead and the follows. Written by any played card's
        # own actions it would be overwritten by the second player and the third
        # would follow the wrong suit — a rule that tests correct and is broken
        # on the third turn.
        {"key": "led", "type": "automatic", "actions": ["stat_set:led@plan:sum:suit@trick"],
         "next": [{"then": "follow_1"}]},
        {"key": "resolve", "type": "automatic",
         "actions": [
             "stat_set:hit@each.task:0",
             # Twice over the same zone, because the second pass needs a number
             # the first one produces: contend is a card's own business, best is
             # the trick's.
             "activate_zone:trick",
             "stat_set:best@each.trick:max:contend@trick",
             "activate_zone:trick",
             "set_active_seat:taker",
         ],
         "next": [{"when": "count:hit_now@enemy.tasks >= 1", "then": "failed"},
                  {"then": "collect"}]},
        {"key": "collect", "type": "automatic",
         "actions": ["move:mine.hit_now:archive", "move:trick:won", "stat_set:led@plan:0",
                     "stat_gain:tricks@plan:1", "stat_gain:tricks_won@mine.player:1"],
         "next": [{"when": "count:task@tasks == 0", "then": "complete"},
                  {"when": f"tricks@plan >= {TRICKS}", "then": "failed"},
                  {"then": "lead"}]},
        {"key": "complete", "type": "automatic",
         "actions": [f"stat_gain:won@{k}_side:1" for k, _ in SEATS] + ["reveal:mission_complete"],
         "next": [{"then": "over"}]},
        {"key": "failed", "type": "automatic", "actions": ["reveal:mission_lost"],
         "next": [{"then": "over"}]},
        {"key": "over", "type": "player_input", "label": "The mission is over",
         "next": [{"then": "over"}]},
        {"key": "mission", "type": "overlay", "zone": "mission"},
    ] + follow


def build():
    return {
        "title": "The Crew",
        "seed": 31,
        "players": [{"card": k} for k, _ in SEATS],
        "styles": {
            "stacked": {"fit": "fill", "fan": "right"},
        },
        "stats": [
            {"key": "tricks", "label": "Trick", "min": 0, "max": 99, "subject": "sum:tricks@plan"},
            {"key": "tricks_won", "label": "Tricks won", "min": 0, "max": 99,
             "subject": "tricks_won@mine.player"},
            {"key": "todo", "label": "Your tasks", "min": 0, "max": 99,
             "subject": "count:task@mine.tasks"},
            {"key": "led", "min": 0, "max": 99, "tags": ["hidden"]},
            {"key": "want", "min": 0, "max": 99, "tags": ["hidden"]},
            {"key": "has_r4", "min": 0, "max": 99, "tags": ["hidden"]},
            {"key": "hit", "min": 0, "max": 99, "tags": ["hidden"]},
        ] + [{"key": k, "min": 0, "max": 999, "tags": ["hidden"]} for k in SCRATCH],
        "computed_tags": {
            "commander": {"stat": "has_r4", "at_least": 1},
            # The one card in the trick that fell short of the best by nothing.
            "taker": {"stat": "gap", "equals": 0},
            "hit_now": {"stat": "hit", "at_least": 1},
        },
        "tags": {
            "play_card": {"tooltip": "Follow the led suit if you hold it. Rockets beat every colour."},
            # Never clicked: the trick is not tagged "activate", so this is
            # reachable only through activate_zone, which is ungated.
            "in_trick": {"abilities": [{"key": "weigh", "text": "Weigh", "action": contend()}]},
        },
        "zones": zones(),
        "phases": phases(),
        "end_conditions": [],
        "cards": (seat_cards() + other_cards() + mission_cards()
                  + playing_cards() + task_cards()),
        "setup": {"place": [{"card": "flight_plan", "zone": "console", "at": ["a1"]}]},
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "game", "games", "the_crew.json")
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
