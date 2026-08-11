#!/usr/bin/env python3
"""Generate game/games/lost_cities.json.

Sixty templates is too many to hand-write and far too many to keep consistent
by hand, so they are generated and the generator is checked in — the same
answer any future deck-of-cards game wants (ideas/01-boardgames.md, gap 3).
Everything structural lives here in one readable place; the output is data.

    python3 tools/make_lost_cities.py
"""

import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt

# The fourth entry is the placeholder-art palette name. Note that the art is
# *decoration that happens to agree* with the rules — the engine reads
# card_stats.value and the "<colour>_dest" tags, never the picture. A card is
# never red because it is drawn red.
# key, label, style, art palette. The style is a *look* with its own name,
# because "red" is already this colour's zone and one name means one thing — so
# fourteen cards claim a colour by tagging `crimson` rather than repeating three
# numbers each.
COLOURS = [
    ("red",    "Red",    "crimson", "crimson"),
    ("green",  "Green",  "jade",    "green"),
    ("blue",   "Blue",   "azure",   "blue"),
    ("white",  "White",  "ivory",   "silver"),
    ("yellow", "Yellow", "amber",   "gold"),
]
STYLES = {
    "crimson": {"color": [0.85, 0.25, 0.25]},
    "jade":    {"color": [0.30, 0.70, 0.35]},
    "azure":   {"color": [0.30, 0.50, 0.90]},
    "ivory":   {"color": [0.85, 0.85, 0.80]},
    "amber":   {"color": [0.90, 0.75, 0.25]},
    # An expedition is a column of tiles, not of cards with margins.
    "tiled":   {"fit": "fill"},
}
VALUES = list(range(2, 11))
WAGERS = 3

# Seated across the table from each other: North's hand along the top edge,
# South's along the bottom, and the board between them — each player's own
# expeditions on their side of the shared discards. Five colour columns of
# 0.13 on a 0.152 stride, all left-aligned on 0.06 so hands, board and tray
# share one centre line.
COL = lambda i: (0.06 + i * 0.152, 0.19 + i * 0.152)

EXPEDITION_POS = {  # colour index -> [north rect, south rect]
    i: [[COL(i)[0], 0.155, COL(i)[1], 0.345],
        [COL(i)[0], 0.525, COL(i)[1], 0.715]]
    for i in range(len(COLOURS))
}
DISCARD_POS = {i: [COL(i)[0], 0.365, COL(i)[1], 0.505]
               for i in range(len(COLOURS))}
HAND_POS    = [[0.06, 0.015, 0.798, 0.135],    # north, top edge
               [0.06, 0.735, 0.798, 0.855]]    # south, above the tray
# The tray sits below South's hand and starts at x 0.19: the lower-left corner
# belongs to the undo button and the event log, which are drawn over
# everything and would otherwise sit on top of the cards.
CHOICE_POS  = [0.19, 0.875, 0.97, 0.995]
DECK_POS    = [0.815, 0.365, 0.975, 0.505]     # beside the discards it feeds


def templates():
    out = []
    # The two seats. Each holds its own score; nothing else distinguishes them.
    for key, text in (("north", "North"), ("south", "South")):
        out.append({"key": key, "text": text, "tags": [key + "_side"],
                    "card_stats": {"score": 0, "tallied": 0}})

    # There are no destination markers. Playing a card points at a *place* — the
    # expedition or the discard — and a place is a zone, so the zone is the
    # target. Standing a marker card in each one to be pointed at instead is
    # what the first version did, and it failed the moment anything covered the
    # marker: a pile draws and hit-tests only its top card, so after the first
    # discard the marker was eligible forever and reachable never, and that
    # colour could not be discarded to again for the rest of the game.

    for i, (c, label, look, art) in enumerate(COLOURS):
        # A card may only be played onto a lower one. Wagers count as zero, so
        # they must come before every number — which the same rule already says.
        def card(key, text, value, tooltip, extra_tags=()):
            return {
                "key": key, "text": text,
                # Stripes count the value, so a card reads at a glance without
                # a single image file; wagers get a star instead.
                "asset": ("star:5:" + art) if value == 0 else ("stripes:%d:%s" % (value, art)),
                "tooltip": tooltip,
                "tags": ["expedition", look, *extra_tags],
                "card_stats": {"value": value},
                # Two places it may go, and the player picks one. The
                # expedition refuses a card worth less than what is already
                # there; the discard refuses nothing.
                "play": {
                    "target": {"type": "zone", "count": 1, "zones": [c, c + "_discard"]},
                    "action": ["move_to:target"],
                },
            }

        for w in range(1, WAGERS + 1):
            out.append(card(
                "%s_w%d" % (c, w), label + " wager", 0,
                "Doubles this expedition's score, for better or worse. "
                "Must be played before any number.",
                ("wager",)))
        for v in VALUES:
            out.append(card("%s_%d" % (c, v), "%s %d" % (label, v), v,
                            "Advance the " + label.lower() + " expedition to " + str(v) + "."))

    # Scoring runs once per expedition at the end, as an ordinary card each
    # seat plays through: (sum - 20) x wagers, distributed so it needs no
    # nested arithmetic, plus the 20-card bonus for a long expedition.
    for c, label, look, art in COLOURS:
        out.append({
            "key": c + "_score", "text": "Score " + label,
            "tooltip": "Total the " + label.lower() + " expedition.",
            "tags": ["scoring", "token", look],
            "play": {
                "needs": {("count:expedition@mine." + c): 1},
                # (sum - 20) x (1 + wagers), distributed as (sum - 20) plus
                # (sum - 20) x wagers, because a product cannot add one inside
                # itself. The route marker used to carry the "wager" tag so that
                # count:wager *was* 1 + wagers; there is no marker any more, so
                # the one is written out instead of smuggled in.
                "action": [
                    "gain_stat:score@mine.player:sum:value@mine." + c,
                    "lose_stat:score@mine.player:20",
                    "gain_stat:score@mine.player:sum:value@mine." + c + ":x:count:wager@mine." + c,
                    "lose_stat:score@mine.player:20:x:count:wager@mine." + c,
                    "destroy_self",
                ],
            },
        })
        out.append({
            "key": c + "_bonus", "text": label + " bonus",
            "tooltip": "An expedition of eight cards or more is worth 20 more.",
            "tags": ["scoring", "token", look],
            "play": {
                "needs": {("count:expedition@mine." + c): 8},
                "action": ["gain_stat:score@mine.player:20", "destroy_self"],
            },
        })

    out.append({"key": "mode_local", "text": "Both sides, here",
                "tooltip": "Hot-seat: take both players' turns on this machine.",
                "tags": ["token"], "play": {"action": ["destroy:mode"]}})
    out.append({"key": "mode_online", "text": "With a friend, online",
                "tooltip": "Sit as North and invite someone to play South. They do not "
                           "need this game — it travels with the invite.",
                "tags": ["token"],
                "play": {"action": ["destroy:mode", "net_seat:north", "net_invite"]}})
    out.append({"key": "done_scoring", "text": "Done", "tooltip": "Finish tallying.",
                "tags": ["token"],
                "play": {"action": ["gain_stat:tallied@mine.player:1", "destroy_self", "next_phase"]}})
    for seat, other in (("north", "South"), ("south", "North")):
        out.append({"key": seat + "_wins", "text": seat.title() + " wins",
                    "story": seat.title() + " comes home with the better haul. "
                             + other + " should have hedged.",
                    "play": {"action": ["load_game:menu.json"]}})
    return out


def zones():
    out = [{"key": "deck", "label": "Expedition Deck", "type": "deck",
            "pos": DECK_POS, "tags": ["shuffle"],
            "tooltip": "Take the top card. Ends your turn.",
            # The box answers, not the card on top of it. A deck has no
            # clickable cards, which is also why nothing has to hide the face
            # of the one you are about to draw.
            "activate": {"phases": ["draw"],
                         "action": ["draw_from:deck:hand:1", "next_phase"]},
            "contents": ["%s_w%d" % (c, w) for c, _, _, _ in COLOURS for w in range(1, WAGERS + 1)]
                        + ["%s_%d" % (c, v) for c, _, _, _ in COLOURS for v in VALUES]},
           {"key": "hand", "type": "hand", "tags": ["per_seat"], "pos": HAND_POS},
           # The opening question, as an overlay of its own. Hidden, so it costs
           # no board space and the layout check ignores it, but an overlay
           # phase draws its zone over the dim regardless. Deliberately *not*
           # the built-in "reveal" pair: that one is page-mode at the zone, so
           # every card fills the whole panel and two choices would stack.
           # Here the page flag lives on the phase instead — which is what makes
           # each card's own on_pick run — while the zone lays them side by side.
           {"key": "mode", "type": "hand", "pos": [0.30, 0.24, 0.70, 0.76],
            "tags": ["hidden", "no_peek"]},
           # Where every choice that is not a card in your hand is made: the six
           # ways to draw, and later the eleven scoring cards. One zone, because
           # the two steps are never live at once, and a wide one, because a hand
           # lays its cards out in a single row and shrinks them to fit — the
           # tally used to be a 163px column and drew its eleven cards 10px wide,
           # smaller than the text on them. The room comes from the hands, which
           # have eight cards to its eleven and were never using it.
           #
           # Declaring a phase's zone also bounds what may be played from it,
           # which is the whole reason the draw options live here rather than on
           # the discard piles: a draw step stays a draw step because your hand
           # is not in this zone, and a play step stays a play step because these
           # tokens are not in your hand. No engine gate is needed for either.
           {"key": "choice", "type": "hand", "pos": CHOICE_POS}]
    for i, (c, label, _, _) in enumerate(COLOURS):
        # Thirteen, not twelve: an expedition can hold all three wagers and all
        # nine numbers, and the route marker that gives them somewhere to land
        # takes a slot of its own. A full board refuses arrivals silently, so
        # one slot short meant the last card of a completed expedition stayed
        # in hand while the turn was spent on it.
        # The expedition's own legality, asked of it when a card is aimed here:
        # worth at least what is already on it, which is the ascending rule.
        # Wagers are worth 0, so the same line puts them before every number.
        out.append({"key": c, "label": label, "type": "grid",
                    "grid": [1, 12], "tags": ["tiled", "per_seat"], "pos": EXPEDITION_POS[i],
                    "receive": {"needs": {"value@target": {"at_least": "max:value@mine." + c}}}})
        # A pile takes anything, which is what having no "receive" means, and
        # hands "takeable" to whatever lands on it — so its top card can be
        # picked up during the draw step without any card knowing about piles.
        # "activate" is the zone's own say-so that abilities work here. A pile
        # is not automatically a place you may take from — an MTG graveyard is
        # the same shape and must not be — so the zone declares it.
        out.append({"key": c + "_discard", "label": label + " discard", "type": "pile",
                    "pos": DISCARD_POS[i], "tags": ["activate"],
                    "applies": ["takeable", "stays_ready"]})
    return out


SCORING_CARDS = [c + suffix for suffix in ("_score", "_bonus") for c, _, _, _ in COLOURS]


# The one rule the discard piles hand to their contents. A tag is a mixin: the
# pile says "whatever lies on me can be taken", the engine reaches only the top
# of a stack, and "phases" keeps it to the draw step — which is the whole reason
# a card-side phase restriction had to exist before a pickup could be safe.
# exhausts is false because Lost Cities never wraps a round, so a card exhausted
# once would never ready again and could never be taken from a pile twice.
TAG_DEFS = {
    "takeable": {
        "activate": {
            "action": ["move_to:hand", "next_phase"],
            "phases": ["draw"],

        },
        "tooltip": "Take this card into your hand.",
    },
}


def phases():
    # Setup deals both hands once and is never returned to: the turn loop is a
    # cycle of its own, closed by south_draw routing back to north_play.
    out = [{"key": "setup", "type": "automatic",
            "actions": ["draw_from:deck:mine.hand:8", "draw_from:deck:enemy.hand:8",
                        "fill:mode:mode_local:1", "fill:mode:mode_online:1",
                        "push_phase:mode"]}]

    # A turn is play-then-draw, and there is exactly one of each. Both seats
    # share them: "seat": "next" hands over on entering the play phase, so the
    # draw that follows belongs to the same player and the loop closes on
    # itself. Naming them north_play/south_play instead would double every rule
    # that ever wants to mention a phase — the "takeable" tag would have to list
    # two draw steps, and a third seat would make it three.
    out += [
        {"key": "play", "type": "player_input", "zone": "hand",
         "label": "Play or discard", "seat": "next", "ends_after": 1,
         "next": [{"then": "draw"}]},
        # The expedition deck running out ends the game, mid-round or not.
        {"key": "draw", "type": "player_input", "zone": "choice",
         "label": "Draw from the deck, or take the top of a discard",
         "tags": ["discard_hand"],
         "next": [{"zone_empty": ["deck"], "then": "tally"}, {"then": "play"}]},
        # One tally phase, entered once per seat. It counts itself: each seat
        # marks its own card as it finishes, and the sum across both is how the
        # routing knows the second one is done.
        {"key": "tally", "type": "player_input", "label": "Tally",
         "seat": "next", "zone": "choice", "tags": ["discard_hand"],
         "pass_card": SCORING_CARDS + ["done_scoring"],
         "next": [{"stat": "tallied@player", "at_least": 2, "then": "ending"},
                  {"then": "tally"}]},
    ]

    # The winner is decided by comparing one seat's score against the other's —
    # a comparison whose bound is a subject rather than a number.
    out.append({"key": "ending", "type": "automatic", "actions": [],
                "next": [{"stat": "score@north_side", "at_least": "score@south_side",
                          "then": "north_end"},
                         {"then": "south_end"}]})
    for seat in ("north", "south"):
        out.append({"key": seat + "_end", "type": "automatic",
                    "actions": ["reveal:" + seat + "_wins"]})
    # Last, so nothing reaches it by falling off the end of the list: it is
    # only ever pushed, and popped by answering it.
    out.append({"key": "mode", "type": "overlay", "zone": "mode"})
    return out


def build():
    tpl = templates()
    z = zones()
    return {
        "title": "Lost Cities",
        # Two seats, facing each other across the table.
        "players": [{"card": "north"}, {"card": "south"}],
        "styles": STYLES,
        "seed": 11,
        # No "round": the turn loop is a routing cycle and nothing declares
        # ends_round, so the counter never moves. A stat that always reads 1 is
        # noise in the HUD, not information.
        "stats": [{"key": "score", "label": "Your score", "subject": "score@mine.player"}],
        "tags": TAG_DEFS,
        "zones": z,
        "cards": tpl,
        "phases": phases(),
        "end_conditions": [],
    }


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    path = os.path.join(root, "game", "games", "lost_cities.json")
    with open(path, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build()))
        f.write("\n")
    print("wrote", os.path.relpath(path, root))
