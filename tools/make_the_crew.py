#!/usr/bin/env python3
"""Generate game/games/the_crew.json.

Forty playing cards and thirty-six task cards, each carrying the same eight
numbers, is data. What is not data lives here in one readable place: the trick
arithmetic, the phase walk that plays a trick, and the layout.

The rules are transcribed in ideas/the_crew/rules.md, from the KOSMOS rulebook
and mission logbook; nothing here invents one. Four seats, which divides forty
evenly — ten each and ten tricks, with no odd card left in a hand.

    python3 tools/make_the_crew.py
"""

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt
import guard

# key, printed name, palette colour, suit number. Rocket is a suit like any
# other, because it is one: led first, it must be followed (rules.md §2 step 4).
SUITS = [
    ("pink",   "Pink",   "pink",   1),
    ("blue",   "Blue",   "blue",   2),
    ("green",  "Green",  "green",  3),
    ("yellow", "Yellow", "yellow", 4),
]
ROCKET = ("rocket", "Rocket", "silver", 5)

# Clockwise round a rectangular table: the first half of the list sits along the
# top edge left to right, the rest along the bottom edge right to left. Four
# divides forty, so every crew member gets ten and no card goes unplayed.
SEATS = [("north", "North"), ("east", "East"), ("south", "South"), ("west", "West")]
DECK = 40
# Whatever is left over after an even deal is a card its holder never plays, so
# the mission is over when the smallest hand is (rules.md §1).
TRICKS = DECK // len(SEATS)
MAX_TASKS = 5

# Every scratch number the trick arithmetic writes, and the bound that makes it
# arithmetic: **a floor of zero is what turns stat_damage into max(0, a - b)**,
# which is the only clamp the amount grammar has.
SCRATCH = ["suit", "value", "trump", "contend", "best", "gap"]
# suit and value are this card's own and every playing card says them; the rest
# start at zero on all forty, so the stats section says that once.


# --- the trick arithmetic ------------------------------------------------
#
# Every card in the trick answers one question with numbers: what would it take
# to win with. A card that did not follow suit and is not a rocket contends
# with nothing, and the rest contend with their value, plus a hundred for being
# a rocket — which is what "trump always wins, however low" is, written as a
# number instead of a branch.
#
# **"Or" is two abilities**, which is the grammar's own answer and is what this
# used to spell as arithmetic: following and trumping are two ways to be in the
# running, so they are two `when`s rather than two clamped subtractions standing
# in for an equality and a third pair standing in for min(a, 1). A rocket led is
# both, and the trump pass runs second, so it wins by overwriting.

COMPUTES = [
    {"key": "trump_rank", "from": "value@self + 100",
     "tooltip": "What a rocket is worth in the running: above every colour card however low it is."},
    {"key": "behind", "from": "best@self - contend@self",
     "tooltip": "How far short of the trick's best this card falls. Zero for exactly one card."},
]


def in_trick():
    return [
        {"key": "follows", "text": "Weigh",
         "when": ["suit@self == led@plan"],
         "action": ["stat_set:contend@self:sum:value@self"]},
        {"key": "trumps", "text": "Weigh", "compute": ["trump_rank"],
         "when": ["trump@self >= 1"],
         "action": ["stat_set:contend@self:trump_rank"]},
        # The led card always contends, so the best is never zero and exactly one
        # card is short by nothing. Its own pass, because it needs a number the
        # trick produces rather than one this card knows.
        {"key": "measure", "compute": ["behind"],
         "action": ["stat_set:gap@self:behind"]},
    ]


# --- the radio -----------------------------------------------------------
#
# One token a mission, spent to lay a card face up saying it is the highest, the
# lowest or the only one of its colour you hold. Nothing else may be said.
#
# Twelve abilities on one button rather than three on each of forty cards,
# because a target's `where` can pick the card out of the player's own hand:
# only the cards carrying `v_<colour>` are that colour, so `max:` and `min:`
# over the hand answer "highest" and "lowest" without a scope that could name a
# tag inside a hand — which there is no such thing as.

# "Only" is the two others agreeing: if the highest card of a colour I hold is
# also the lowest, I hold exactly one. An ability takes no `needs` — only a
# card's play moment does — so this had to be a comparison between two subjects,
# and it turned out to be the better sentence anyway.
POSITIONS = [
    ("high", "highest", "{c}@target >= max:{c}@mine.hand"),
    ("only", "only", "max:{c}@mine.hand <= min:{c}@mine.hand"),
    ("low", "lowest", "{c}@target <= min:{c}@mine.hand"),
]


def radio_card():
    abilities = []
    for key, name, colour, _ in SUITS:
        v = f"v_{key}"
        for pos, word, where in POSITIONS:
            abilities.append({
                "key": f"say_{pos}_{key}",
                "text": f"My {word} {name.lower()}",
                "tooltip": f"Lay a {name.lower()} card face up, saying it is the {word}"
                           f" {name.lower()} in your hand. One card, once a mission, and it stays"
                           " where you put it even after it stops being true.",
                "cost": {"radio@mine.player": 1},
                "target": {"type": "card", "count": 1, "zones": ["hand"],
                           "where": [f"{v}@target >= 1", where.format(c=v)]},
                "action": ["move_target_to:open"],
            })
    return {"key": "radio", "text": "Radio", "asset": "circle:teal",
            "tags": ["immutable"],
            "tooltip": "Say one thing about one card, once a mission: lay a colour card face up"
                       " and call it your highest, your lowest, or your only one of that colour."
                       " Rockets can never be communicated, and nothing else may be said at all.",
            "abilities": abilities}


# --- cards ---------------------------------------------------------------

# Everything a crew member holds is granted by the stats node through
# on: ["player"], so a seat is its name and the tag other rules find it by. A
# five-seat variant is then a longer SEATS list and nothing else.
def seat_cards():
    return [{"key": k, "text": t, "tags": [k + "_side"]} for k, t in SEATS]


def playing_cards():
    out = []
    for key, name, colour, suit in SUITS + [ROCKET]:
        top = 4 if key == "rocket" else 9
        for v in range(1, top + 1):
            rocket = key == "rocket"
            # Only what is true of *this* card. The scratch numbers the trick
            # arithmetic writes are the same zero on all forty, so the play_card
            # tag carries them instead — see the tags block.
            stats = {"suit": suit, "value": v}
            if rocket:
                stats["trump"] = 1
            else:
                # Its value, under a name only its own colour carries — so max:
                # and min: over a hand answer "the highest pink I hold" and "the
                # lowest", which no scope can ask, because a tag reaches grid
                # zones only. Rockets get none: a rocket is never communicated.
                stats[f"v_{key}"] = v
            card = {
                "key": f"{key}_{v}",
                "text": f"{name} {v}",
                "asset": f"stripes:{v}:{colour}",
                "tags": ["play_card", colour] + ([] if rocket else [f"c_{key}{v}"]),
                "card_stats": stats,
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
                    " every task before the last trick is played.\n\nYou may not say what is in"
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
    """Four crew members round a rectangular table, and the play area between them.

    Two hands along the top edge and two along the bottom, in clockwise order, so
    the seat that follows you is the one to your left on screen. The middle band
    is the play area, with the decks and everybody's tasks down the right and the
    offer and the small piles down the left. Two corners are the engine's and
    nothing reaches into either: the HUD writes into the top right, and the event
    log into the bottom left.
    """
    half = (len(SEATS) + 1) // 2

    # A seat's own strip: its closed hand, and its open one beside it — the card
    # it has laid face up for everybody, which is where the radio puts things.
    def row(keys, y1, y2, reverse):
        """Split the full width between these seats, with a gutter between."""
        n = len(keys)
        w = (0.98 - 0.01 * (n - 1)) / n
        out = {}
        for i, k in enumerate(keys):
            x = 0.01 + (n - 1 - i if reverse else i) * (w + 0.01)
            out[k] = ([round(x, 3), y1, round(x + w - 0.10, 3), y2],
                      [round(x + w - 0.09, 3), y1, round(x + w, 3), y2])
        return out

    order = [k for k, _ in SEATS]
    seats = row(order[:half], 0.195, 0.325, False)
    seats.update(row(order[half:], 0.755, 0.895, True))
    hands = [seats[k][0] for k in order]
    opens = [seats[k][1] for k in order]

    # One task row per seat, stacked under the decks. They hold very few cards
    # in practice, so they are the smallest thing on the table.
    top, step = 0.455, 0.290 / len(SEATS)
    tasks = [[0.805, round(top + i * step, 3), 0.995, round(top + (i + 1) * step - 0.008, 3)]
             for i in range(len(SEATS))]

    return [
        {"key": "hand", "type": "hand", "tags": ["per_seat"], "pos": hands},
        # Face up, so it is everybody's to read — which is the whole point of
        # saying something, and what the tag has always claimed to mean.
        {"key": "open", "label": "Said", "type": "hand", "tags": ["per_seat", "face_up"],
         "pos": opens},
        {"key": "controls", "type": "grid", "grid": [1, 1], "tags": ["activate", "optional"],
         "pos": [0.685, 0.335, 0.790, 0.445]},
        {"key": "tasks", "label": "Tasks", "type": "grid", "grid": [MAX_TASKS, 1],
         "tags": ["per_seat"], "pos": tasks},
        {"key": "trick", "label": "Play area", "type": "grid", "grid": [len(SEATS), 1],
         "applies": ["in_trick"], "pos": [0.330, 0.395, 0.670, 0.700]},
        {"key": "deck", "label": "Deck", "type": "deck", "tags": ["shuffle"],
         "pos": [0.805, 0.335, 0.895, 0.445],
         "tooltip": "Forty cards: four colours of nine, and four rockets.",
         "contents": [f"{s[0]}_{v}" for s in SUITS for v in range(1, 10)]
                     + [f"rocket_{v}" for v in range(1, 5)]},
        {"key": "task_deck", "label": "Tasks", "type": "deck", "tags": ["shuffle"],
         "pos": [0.905, 0.335, 0.995, 0.445],
         "tooltip": "One task card for every colour card. Rockets are never a task.",
         "contents": [f"task_{s[0]}_{v}" for s in SUITS for v in range(1, 10)]},
        {"key": "task_offer", "label": "On offer", "type": "grid", "grid": [MAX_TASKS, 1],
         "pos": [0.010, 0.480, 0.320, 0.620]},
        {"key": "archive", "label": "Done", "type": "pile",
         "tooltip": "Tasks the crew has already fulfilled.",
         "pos": [0.220, 0.340, 0.320, 0.460]},
        {"key": "won", "label": "Taken", "type": "pile", "tags": ["face_down"],
         "tooltip": "Tricks already taken, set aside face down.",
         "pos": [0.115, 0.340, 0.215, 0.460]},
        {"key": "rules", "type": "pile", "pos": [0.010, 0.340, 0.110, 0.460],
         "contents": ["how_to_play"]},
        {"key": "console", "type": "grid", "grid": [1, 1], "tags": ["hidden"]},
        {"key": "mission", "type": "hand", "tags": ["hidden"],
         "pos": [0.22, 0.24, 0.78, 0.76],
         "contents": [f"m_{n}" for n in range(1, MAX_TASKS + 1)]},
    ]


# --- phases --------------------------------------------------------------

def deal():
    """Deal, then find the commander, then hand them the table.

    "each_seat" is what says "every seat in turn", so neither half writes the
    seat count out. The second half is the only way a card sitting in a hand can
    be asked about at all: a tag reaches grid zones only, so "who holds the
    rocket 4" has to be asked once per seat, of the seat that holds it. What it
    writes is an ordinary stat, and the commander is then a computed tag over it
    that every later rule can name.
    """
    if DECK % len(SEATS):
        # An uneven deal is the one thing each_seat cannot say — it runs the
        # same action for everybody — so a deck that does not divide goes back
        # to naming the seats, and only that half of it does.
        out = []
        for i, (key, _) in enumerate(SEATS):
            n = TRICKS + (1 if i < DECK % len(SEATS) else 0)
            out += [f"set_active_seat:{key}_side", f"draw_from:deck:mine.hand:{n}"]
    else:
        out = [f"each_seat:draw_from:deck:mine.hand:{TRICKS}"]
    return out + ["each_seat:stat_set:has_r4@mine.player:card:rocket_4@mine.hand",
                  "set_active_seat:commander",
                  "draw_from:task_deck:task_offer:sum:want@plan"]


def phases():
    # A turn ends when a card reaches the middle, not when a card is played:
    # everything else a crew member may do — the radio, and whatever comes after
    # it — leaves the trick alone and so leaves the turn alone.
    follow = [{"key": f"follow_{i}", "type": "player_input", "seat": "next",
               "zone": ["hand", "open"], "ends_when": f"count:play_card@trick >= {i + 1}",
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
        {"key": "lead", "type": "player_input", "zone": ["hand", "open"],
         "ends_when": "count:play_card@trick >= 1",
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
             # A pass per part of the resolution, named. The last one needs a
             # number the first two produce: contend is a card's own business,
             # best is the trick's.
             "stat_set:contend@each.trick:0",
             "activate_zone:trick:by_column:follows",
             "activate_zone:trick:by_column:trumps",
             "stat_set:best@each.trick:max:contend@trick",
             "activate_zone:trick:by_column:measure",
             # Each card marks the task that wanted it. Its own pass because it
             # is the card's own ability rather than the zone's, and a named pass
             # runs only what answers to the name.
             "activate_zone:trick:by_column:claim",
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
        "stats": [
            {"key": "tricks", "label": "Trick", "min": 0, "max": 99, "subject": "sum:tricks@plan"},
            {"key": "tricks_won", "label": "Tricks won", "min": 0, "max": 99,
             "subject": "tricks_won@mine.player", "on": ["player"], "start": 0},
            {"key": "todo", "label": "Your tasks", "min": 0, "max": 99,
             "subject": "count:task@mine.tasks"},
            {"key": "led", "min": 0, "max": 99, "tags": ["hidden"]},
            {"key": "want", "min": 0, "max": 99, "tags": ["hidden"]},
            {"key": "has_r4", "min": 0, "max": 99, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            # Whose number each of these is, said once instead of on every card.
            # A task starts unclaimed; a playing card says its own suit and value
            # and starts the trick arithmetic at zero.
            {"key": "hit", "min": 0, "max": 99, "tags": ["hidden"], "on": ["task"], "start": 0},
            # One thing may be said per player per mission, which is a fact about
            # being a player rather than about being north.
            {"key": "radio", "label": "Radio", "icon": "banner", "min": 0, "max": 1,
             "subject": "radio@mine.player", "on": ["player"], "start": 1},
        # A colour card's value under a name only its own colour carries, which
        # is what lets max: and min: over a hand answer "my highest pink". Every
        # card of the colour must say it, so the stat says so and the validator
        # holds the generator to it.
        ] + [{"key": f"v_{s[0]}", "min": 0, "max": 99, "tags": ["hidden"], "on": [s[0]]}
             for s in SUITS]
        + [{"key": k, "min": 0, "max": 999, "tags": ["hidden"], "on": ["play_card"]}
           for k in ("suit", "value")]
        + [{"key": k, "min": 0, "max": 999, "tags": ["hidden"], "on": ["play_card"], "start": 0}
           for k in SCRATCH if k not in ("suit", "value")],
        "computes": COMPUTES,
        "computed_tags": {
            "commander": {"stat": "has_r4", "at_least": 1},
            # The one card in the trick that fell short of the best by nothing.
            "taker": {"stat": "gap", "equals": 0},
            "hit_now": {"stat": "hit", "at_least": 1},
        },
        "tags": {
            # The whole of follow-suit, said once for all forty cards. Leading,
            # no card matches a led suit of zero, so flow's escape hatch
            # ("nothing else here is playable") opens the hand at once.
            "play_card": {
                "tooltip": "Follow the led suit if you hold it. Rockets beat every colour.",
                "play": {"needs": ["suit@self == led@plan"],
                         "action": ["set_owner:self:mine", "move_to:trick"]},
            },
            # Taking a task is one act; which card it wants is the tag it shares
            # with that card, and nothing about picking it up depends on which.
            "task": {"play": {"action": ["set_owner:self:mine", "move_to:tasks"]}},
            # Never clicked: the trick is not tagged "activate", so this is
            # reachable only through activate_zone, which is ungated.
            "in_trick": {"abilities": in_trick()},
        },
        "zones": zones(),
        "phases": phases(),
        "end_conditions": [],
        "cards": (seat_cards() + other_cards() + mission_cards() + [radio_card()]
                  + playing_cards() + task_cards()),
        "setup": {"place": [{"card": "flight_plan", "zone": "console", "at": ["a1"]},
                            {"card": "radio", "zone": "controls", "at": ["a1"]}]},
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = guard.destination(os.path.join(here, "..", "game", "games", "the_crew.json"))
    if out is None:
        sys.exit(1)
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
