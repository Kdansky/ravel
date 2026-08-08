#!/usr/bin/env python3
"""Generate game/games/lost_cities.json.

Sixty templates is too many to hand-write and far too many to keep consistent
by hand, so they are generated and the generator is checked in — the same
answer any future deck-of-cards game wants (ideas/01-boardgames.md, gap 3).
Everything structural lives here in one readable place; the output is data.

    python3 tools/make_lost_cities.py
"""

import json, os

# The fourth entry is the placeholder-art palette name. Note that the art is
# *decoration that happens to agree* with the rules — the engine reads
# card_stats.value and the "<colour>_dest" tags, never the picture. A card is
# never red because it is drawn red.
COLOURS = [
    ("red",    "Red",    [0.85, 0.25, 0.25], "crimson"),
    ("green",  "Green",  [0.30, 0.70, 0.35], "green"),
    ("blue",   "Blue",   [0.30, 0.50, 0.90], "blue"),
    ("white",  "White",  [0.85, 0.85, 0.80], "silver"),
    ("yellow", "Yellow", [0.90, 0.75, 0.25], "gold"),
]
VALUES = list(range(2, 11))
WAGERS = 3

# Two rows of expeditions, one per seat, with the shared discards between them.
EXPEDITION_POS = {  # colour index -> [north rect, south rect]
    i: [[0.02 + i * 0.152, 0.04, 0.15 + i * 0.152, 0.24],
        [0.02 + i * 0.152, 0.52, 0.15 + i * 0.152, 0.72]]
    for i in range(len(COLOURS))
}
DISCARD_POS = {i: [0.02 + i * 0.152, 0.27, 0.15 + i * 0.152, 0.49]
               for i in range(len(COLOURS))}


def templates():
    out = []
    # The two seats. Each holds its own score; nothing else distinguishes them.
    for key, text in (("north", "North"), ("south", "South")):
        out.append({"key": key, "text": text, "tags": ["player", key + "_side"],
                    "card_stats": {"score": 0}})

    # A destination marker sits in every expedition and every discard pile, so
    # "where does this card go" is an ordinary card target even when the place
    # is empty. Markers never move and are never counted as expedition cards.
    for i, (c, label, col, art) in enumerate(COLOURS):
        # The route marker is the expedition's legality: it accepts only a card
        # worth at least what is already there, which is exactly the ascending
        # rule (wagers are worth 0, so they fit only before any number). It is
        # also tagged "wager", which makes count:wager the multiplier 1 + wagers
        # without the engine needing to add one.
        out.append({"key": c + "_route", "text": label + " route", "color": col,
                    "asset": "polygon:6:" + art,
                    "tooltip": "Advance the " + label.lower() + " expedition. Cards must ascend.",
                    "tags": ["marker", "wager", c + "_dest"],
                    "accepts": {"value@target": {"at_least": "max:value@mine." + c}},
                    "auto_play": True, "to_zone": c})
        # The discard takes anything, which is what having no "accepts" means.
        out.append({"key": c + "_tip", "text": label + " discard", "color": col,
                    "asset": "cross:" + art,
                    "tooltip": "Discard a " + label.lower() + " card.",
                    "tags": ["marker", c + "_dest"],
                    "auto_play": True, "to_zone": c + "_discard"})

    for i, (c, label, col, art) in enumerate(COLOURS):
        # A card may only be played onto a lower one. Wagers count as zero, so
        # they must come before every number — which the same rule already says.
        def card(key, text, value, tooltip, extra_tags=()):
            return {
                "key": key, "text": text, "color": col,
                # Stripes count the value, so a card reads at a glance without
                # a single image file; wagers get a star instead.
                "asset": ("star:5:" + art) if value == 0 else ("stripes:%d:%s" % (value, art)),
                "tooltip": tooltip,
                "tags": ["expedition", *extra_tags],
                "card_stats": {"value": value},
                "target": {"type": "card", "tags": [c + "_dest"], "count": 1,
                           "zones": [c, c + "_discard"]},
                "on_play": ["move_to:target"],
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
    for c, label, col, art in COLOURS:
        out.append({
            "key": c + "_score", "text": "Score " + label, "color": col,
            "tooltip": "Total the " + label.lower() + " expedition.",
            "tags": ["scoring", "token"],
            "needs": {("count:expedition@mine." + c): 1},
            "on_play": [
                "gain_stat:score@mine.player:sum:value@mine." + c + ":x:count:wager@mine." + c,
                "lose_stat:score@mine.player:20:x:count:wager@mine." + c,
                "destroy_self",
            ],
        })
        out.append({
            "key": c + "_bonus", "text": label + " bonus", "color": col,
            "tooltip": "An expedition of eight cards or more is worth 20 more.",
            "tags": ["scoring", "token"],
            "needs": {("count:expedition@mine." + c): 8},
            "on_play": ["gain_stat:score@mine.player:20", "destroy_self"],
        })

    out.append({"key": "mode_local", "text": "Both sides, here",
                "tooltip": "Hot-seat: take both players' turns on this machine.",
                "tags": ["token"], "on_pick": ["destroy:mode"]})
    out.append({"key": "mode_online", "text": "With a friend, online",
                "tooltip": "Sit as North and invite someone to play South. They do not "
                           "need this game — it travels with the invite.",
                "tags": ["token"],
                "on_pick": ["destroy:mode", "net_seat:north", "net_invite"]})
    out.append({"key": "done_scoring", "text": "Done", "tooltip": "Finish tallying.",
                "tags": ["token"], "on_play": ["destroy_self", "next_phase"]})
    for seat, other in (("north", "South"), ("south", "North")):
        out.append({"key": seat + "_wins", "text": seat.title() + " wins",
                    "story": seat.title() + " comes home with the better haul. "
                             + other + " should have hedged.",
                    "on_pick": ["load_game:menu.json"]})
    return out


def zones():
    out = [{"key": "deck", "label": "Expedition Deck", "type": "deck",
            "pos": [0.80, 0.30, 0.97, 0.52], "tags": ["shuffle"],
            "contents": ["%s_w%d" % (c, w) for c, _, _, _ in COLOURS for w in range(1, WAGERS + 1)]
                        + ["%s_%d" % (c, v) for c, _, _, _ in COLOURS for v in VALUES]},
           {"key": "hand", "type": "hand", "per_seat": True,
            "pos": [[0.02, 0.75, 0.78, 0.87], [0.02, 0.88, 0.78, 0.99]]},
           # Under the draw column, not across the hands. It used to span
           # [0.20, 0.75, 0.97, 0.99], which is most of both players' hands —
           # a zone's background is drawn whether or not it holds anything, so
           # an empty tally sat on top of the cards you were trying to play.
           # The opening question, as an overlay of its own. Hidden, so it costs
           # no board space and the layout check ignores it, but an overlay
           # phase draws its zone over the dim regardless. Deliberately *not*
           # the built-in "reveal" pair: that one is page-mode at the zone, so
           # every card fills the whole panel and two choices would stack.
           # Here the page flag lives on the phase instead — which is what makes
           # each card's own on_pick run — while the zone lays them side by side.
           {"key": "mode", "type": "hand", "pos": [0.30, 0.24, 0.70, 0.76],
            "tags": ["hidden", "no_peek"]},
           {"key": "tally", "label": "Tally", "type": "hand",
            "pos": [0.80, 0.75, 0.97, 0.99]},
           # Declaring a phase's zone also bounds what may be played from it,
           # which is how the draw step stays a draw step: only the token below
           # lives here, so a hand card cannot be dumped instead.
           {"key": "draw_choice", "label": "Draw", "type": "hand",
            "pos": [0.80, 0.55, 0.97, 0.72]}]
    for i, (c, label, _, _) in enumerate(COLOURS):
        out.append({"key": c, "label": label, "type": "grid", "per_seat": True,
                    "grid": [1, 12], "fit": "fill", "pos": EXPEDITION_POS[i]})
        out.append({"key": c + "_discard", "label": label + " discard", "type": "pile",
                    "pos": DISCARD_POS[i],
                    "on_click": ["draw_from:" + c + "_discard:hand:1", "next_phase"]})
    return out


SCORING_CARDS = [c + suffix for suffix in ("_score", "_bonus") for c, _, _, _ in COLOURS]


def phases():
    # Setup deals both hands once and is never returned to: the turn loop is a
    # cycle of its own, closed by south_draw routing back to north_play.
    out = [{"key": "setup", "type": "automatic",
            "actions": ["draw_from:deck:mine.hand:8", "draw_from:deck:enemy.hand:8",
                        "fill:mode:mode_local:1", "fill:mode:mode_online:1",
                        "push_phase:mode"]}]

    # A turn is play-then-draw. "seat": "next" hands over on entering the play
    # phase, so the draw that follows belongs to the same player. Drawing from a
    # discard is that pile's own click, which advances the phase itself; the
    # deck is the fallback offered in hand.
    for seat in ("north", "south"):
        out += [
            {"key": seat + "_play", "type": "player_input", "zone": "hand",
             "label": seat.title() + " — play or discard", "seat": "next", "ends_after": 1},
            {"key": seat + "_draw", "type": "player_input",
             "label": seat.title() + " — draw from the deck or a discard",
             "zone": "draw_choice", "pass_card": "draw_deck"},
        ]

    # The expedition deck running out ends the game, mid-round or not.
    out[1]["next"] = [{"then": "north_draw"}]
    out[2]["next"] = [{"zone_empty": ["deck"], "then": "tally_one"}, {"then": "south_play"}]
    out[3]["next"] = [{"then": "south_draw"}]
    out[4]["next"] = [{"zone_empty": ["deck"], "then": "tally_one"}, {"then": "north_play"}]

    # Each seat tallies its own expeditions; the scoring cards gate themselves
    # on having started one, and remove themselves as they are played.
    # Both seats tally, in the order the handover happens to give them; the
    # cards gate themselves on having started the expedition they total.
    for i, key in enumerate(("tally_one", "tally_two")):
        out.append({"key": key, "type": "player_input", "label": "Tally",
                    "seat": "next", "zone": "tally",
                    "pass_card": SCORING_CARDS + ["done_scoring"],
                    "next": [{"then": "tally_two" if i == 0 else "ending"}]})

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
    out.append({"key": "mode", "type": "overlay", "zone": "mode", "page": True})
    return out


def build():
    tpl = templates()
    tpl.append({"key": "draw_deck", "text": "Draw from the deck",
                "tooltip": "Take the top card of the expedition deck.",
                "tags": ["token"],
                "on_play": ["draw_from:deck:hand:1", "destroy_self", "next_phase"]})
    z = zones()
    return {
        "title": "Lost Cities",
        "seed": 11,
        "stats": [{"key": "score", "label": "Your score", "subject": "score@mine.player"},
                  {"key": "round", "label": "Round"}],
        "zones": z,
        "templates": tpl,
        "phases": phases(),
        "end_conditions": [],
    }


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    path = os.path.join(root, "game", "games", "lost_cities.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(build(), f, indent=2)
        f.write("\n")
    print("wrote", os.path.relpath(path, root))
