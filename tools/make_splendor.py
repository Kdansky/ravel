#!/usr/bin/env python3
"""Generate game/games/splendor.json.

Ninety development cards, each carrying fifteen numbers, is data — the same
answer Lost Cities got. What is *not* data lives here in one readable place:
the pricing arithmetic, the turn loop, and the layout.

The card table is transcribed from ideas/splendor/cards.md, which triangulates
three independent transcriptions of the physical deck; see that file for the
sourcing. Nothing here invents a number.

    python3 tools/make_splendor.py
"""

import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt
import guard

# key, label, one-letter shorthand, plate colour, HUD icon, icon colour.
# The icons are named by *shape*, not by meaning, so each gem gets a different
# silhouette in the row of six and none of them claims to be about money. The
# shapes carry colours of their own and five of them are wrong here — a blade is
# orange, and onyx is not — so each gem says what colour it is. "silver" rather
# than "white" for diamond and "grey" rather than "black" for onyx: both are
# drawn on a dark pill, where the true colour of either would not be there.
GEMS = [
    ("white", "Diamond", "W", [0.86, 0.86, 0.82], "diamond", "silver"),
    ("blue",  "Sapphire", "B", [0.22, 0.42, 0.78], "shield", "blue"),
    ("green", "Emerald",  "G", [0.20, 0.56, 0.32], "leaf", "green"),
    ("red",   "Ruby",     "R", [0.76, 0.24, 0.24], "heart", "red"),
    ("black", "Onyx",     "K", [0.22, 0.22, 0.26], "blade", "grey"),
]
KEYS = [g[0] for g in GEMS]

# 2-player supply: four of each gem, five gold. (3p is 5, 4p is 7; the gold
# stack never changes. See cards.md.)
SUPPLY = 4
GOLD_SUPPLY = 5
TARGET = 15         # prestige that ends the game
HAND_LIMIT = 10     # tokens held at the end of a turn


def cards_table(path):
    """The three tier tables out of cards.md, as (tier, bonus, vp, cost dict)."""
    rows, tier = [], None
    for line in open(path, encoding="utf-8"):
        m = line.strip()
        if m.startswith("### Tier "):
            tier = int(m.split()[2])
            continue
        if tier is None or not m.startswith("|"):
            continue
        cells = [c.strip() for c in m.strip("|").split("|")]
        if len(cells) != 7 or cells[0] in ("Bonus", "---") or cells[0].startswith("-"):
            continue
        bonus = cells[0].lower()
        if bonus not in KEYS:
            continue
        vp = 0 if cells[1] == "-" else int(cells[1])
        cost = {k: (0 if c == "-" else int(c)) for k, c in zip(KEYS, cells[2:])}
        rows.append((tier, bonus, vp, cost))
        if m.startswith("| Black | 1 |") and tier == 3:
            tier = None
    return rows


def nobles_table(path):
    """The ten noble tiles, as cost dicts. Every noble is worth 3."""
    out, seen_heading = [], False
    for line in open(path, encoding="utf-8"):
        m = line.strip()
        if m.startswith("## Noble tiles"):
            seen_heading = True
            continue
        if m.startswith("## ") and seen_heading and out:
            break
        if not (seen_heading and m.startswith("|")):
            continue
        cells = [c.strip() for c in m.strip("|").split("|")]
        if len(cells) != 3 or not cells[0].isdigit():
            continue
        cost = {k: 0 for k in KEYS}
        for part in cells[1].split("+"):
            n, colour = part.split()
            cost[colour.strip()] = int(n)
        out.append(cost)
    return out


# ---------------------------------------------------------------- the pricing

# What a development card costs *this* player, worked out on the card itself so
# that a condition can read one number and the buy action can spend it.
#
# **The whole of it is subtraction that stops at zero**, which is what
# stat_damage already does against a floor of 0 — there is no min() or max() in
# the amount grammar and none is needed:
#
#   due   = max(0, printed - bonus)      what the discounts leave to pay
#   short = max(0, due - tokens)         what gold has to cover, per colour
#   due  := due - short                  what the tokens themselves pay
#
# Summing the shorts gives the gold bill; "buyable" is 1 + gold - bill clamped
# at zero, which is 1 exactly when the gold covers it. A card the player cannot
# afford therefore reads buyable 0 and is dimmed by an ordinary needs.
def pricing():
    a = ["stat_set:gold_due@self:0"]
    for k in KEYS:
        a += [
            f"stat_set:due_{k}@self:sum:cost_{k}@self",
            f"stat_damage:due_{k}@self:sum:b_{k}@mine.player",
            f"stat_set:short@self:sum:due_{k}@self",
            f"stat_damage:short@self:sum:t_{k}@mine.player",
            "stat_gain:gold_due@self:sum:short@self",
            f"stat_damage:due_{k}@self:sum:short@self",
        ]
    a.append("stat_set:spent@self:sum:gold_due@self")
    a += [f"stat_gain:spent@self:sum:due_{k}@self" for k in KEYS]
    a += [
        "stat_set:buyable@self:1",
        "stat_gain:buyable@self:sum:t_gold@mine.player",
        "stat_damage:buyable@self:sum:gold_due@self",
    ]
    return a


# Buying: the numbers were worked out above, so this only moves them. The bank
# gets back exactly what the player spends, which is why the tokens are counted
# out per colour rather than as one total.
def buying():
    a = [f"stat_damage:t_{k}@mine.player:sum:due_{k}@self" for k in KEYS]
    a += ["stat_damage:t_gold@mine.player:sum:gold_due@self",
          "stat_damage:t_total@mine.player:sum:spent@self"]
    a += [f"stat_gain:stock@supply.pile_{k}:sum:due_{k}@self" for k in KEYS]
    a += [
        "stat_gain:stock@supply.pile_gold:sum:gold_due@self",
        "stat_gain:score@mine.player:sum:vp@self",
        "stat_gain:bought@mine.player:1",
    ]
    # A card grants one discount, and which one is a tag it wears — so counting
    # the tag on itself is the +1, and the same five lines serve all ninety.
    a += [f"stat_gain:b_{k}@mine.player:count:gives_{k}@self" for k in KEYS]
    a += [
        # Reserved cards free their slot when bought; ones taken off the row
        # never held one.
        "stat_gain:reserve_slots@mine.player:sum:reserved@self",
        "stat_set:reserved@self:0",
        # Nothing prices a card once it is bought, so this is what stops a
        # tableau card being bought again: it is no longer for sale.
        "stat_set:buyable@self:0",
        "set_owner:self:mine",
        "move_to:mine.tableau",
        "stat_set:done@mine.player:1",
        "next_phase",
    ]
    return a


# A noble arrives when the bonuses are all there. Same clamp, read the other
# way round: every colour short of its requirement subtracts from a 1, so "ok"
# survives only when nothing is missing.
def noble_check():
    a = ["stat_set:ok@self:1"]
    for k in KEYS:
        a += [
            f"stat_set:short@self:sum:n_{k}@self",
            f"stat_damage:short@self:sum:b_{k}@mine.player",
            "stat_damage:ok@self:sum:short@self",
        ]
    return a


# Taking a token is the only thing a gem pile does, and "at least four left"
# is a number rather than a condition so that an ability can be gated on it —
# an ability is gated by its cost and its phase, and by nothing else.
def plenty():
    out = []
    for k in KEYS:
        out += [f"stat_set:plenty@supply.pile_{k}:sum:stock@supply.pile_{k}",
                f"stat_damage:plenty@supply.pile_{k}:3"]
    return out


REPRICE = ["activate_zone:t1_row", "activate_zone:t2_row", "activate_zone:t3_row",
           "activate_zone:mine.reserve"]


# ------------------------------------------------------------------- the file

def stats():
    # The seven a player reads. Each is a number every seat holds, so the stat
    # says so itself rather than the seat cards each listing them.
    seat = {"on": ["player"], "start": 0}
    out = [{"key": "score", "label": "Prestige", "icon": "banner", "min": 0, "max": 99,
            "subject": "score@mine.player", **seat}]
    for k, label, _, _, icon, tint in GEMS:
        out.append({"key": f"t_{k}", "label": label, "icon": icon, "color": tint,
                    "min": 0, "max": 10, "subject": f"t_{k}@mine.player", **seat})
    out.append({"key": "t_gold", "label": "Gold", "icon": "coin", "min": 0, "max": 10,
                "subject": "t_gold@mine.player", **seat})
    # Everything below is arithmetic. It is declared so that it has a floor of
    # zero — the floor is what makes subtraction mean "and no further" — and
    # hidden so that the HUD stays the seven numbers a player actually reads.
    #
    # A stat also says *whose* number it is. Carrying one is how a card says it
    # takes part, so the scratch registers of the pricing used to be ten zeros
    # written on all ninety development cards; "on" and "start" say it once.
    # The ones with no "start" are the card's own to declare, and the validator
    # holds the generator to it — a development card without a white cost is a
    # bug in this file, not a card that costs nothing.
    scratch = {"short": ["development", "noble"], "gold_due": ["development"],
               "spent": ["development"], "buyable": ["development"],
               "reserved": ["development"], "ok": ["noble"],
               "vp": ["development", "noble"]}
    for k in KEYS:
        scratch[f"due_{k}"] = ["development"]
    printed = {"tier": ["development"]}
    for k in KEYS:
        printed[f"cost_{k}"] = ["development"]
        printed[f"n_{k}"] = ["noble"]
    # What every seat holds, said once instead of copied onto each seat card and
    # then copied again for a third player. "player" is the tag the engine stamps
    # from the players list, so a game never types it and every seat wears it.
    seat_start = {"t_total": 0, "takes": 0, "done": 0, "first_take": 1,
                  "reserve_slots": 3, "bought": 0, "ending": 0, "opens": 0}
    seat_start.update({f"b_{k}": 0 for k in KEYS})
    # "stock" is badged on the six token plates, whose plate colour and label
    # already say which gem they hold — so the count needs no shape beside it,
    # and the diamond it fell back to is the silhouette of a gem it is not.
    hidden = {"stock": {"icon": "none"}, "plenty": {}}
    for k, extra in sorted(hidden.items()):
        out.append({"key": k, **extra, "min": 0, "max": 99, "tags": ["hidden"]})
    for k in sorted(scratch):
        # Prestige is the number the game is won on, so on a card it wears the
        # same banner the seat's own score does rather than the anonymous
        # diamond every undeclared stat falls back to.
        icon = {"icon": "banner"} if k == "vp" else {}
        out.append({"key": k, **icon, "min": 0, "max": 99, "tags": ["hidden"],
                    "on": scratch[k], "start": 0})
    look = {}
    for k, _, _, _, icon, tint in GEMS:
        look[f"cost_{k}"] = (icon, tint)
        look[f"n_{k}"] = (icon, tint)
    for k in sorted(printed):
        # A printed cost wears the gem that pays it. "hidden" keeps a stat out
        # of the HUD; what a card shows on its face is the style's business, so
        # the two do not argue.
        gem = look.get(k)
        art = {"icon": gem[0], "color": gem[1]} if gem else {}
        out.append({"key": k, **art, "min": 0, "max": 99, "tags": ["hidden"], "on": printed[k]})
    for k in sorted(seat_start):
        out.append({"key": k, "min": 0, "max": 99, "tags": ["hidden"],
                    "on": ["player"], "start": seat_start[k]})
    return out


def styles():
    s = {f"plate_{k}": {"color": colour} for k, _, _, colour, _, _ in GEMS}
    s["plate_gold"] = {"color": [0.80, 0.66, 0.24]}
    s["plate_noble"] = {"color": [0.44, 0.34, 0.56]}
    s["market"] = {"fit": "card", "cell_outline": False}
    # A style is claimed by carrying a tag of its name, and a *card* claims its
    # own: badges named on the zone's style are read by nobody, which is where
    # the old "badges": ["vp"] on market went. Both of these are worn by the
    # cards, and both words already exist as behaviour tags — which is the whole
    # of "styles are tags too".
    #
    # The price runs down the side, in the gems it is priced in: five will not
    # go across a card and the zeros are most of them. Prestige leads, because
    # it is what the game is won on and it is top-left on the printed card.
    s["development"] = {"badges": ["vp"] + [f"cost_{k}" for k in KEYS],
                        "badge_run": "down", "badge_zeros": False}
    # A noble is the same card read the other way: a threshold rather than a
    # price, and worth three whatever it asks for. Untitled, because every one
    # of them is called "Noble": the word says nothing the plate colour has not
    # already said, and on a card two thirds the height of a market one it is
    # four requirements' worth of room.
    s["noble"] = {"badges": ["vp"] + [f"n_{k}" for k in KEYS],
                  "badge_run": "down", "badge_zeros": False, "title": False}
    s["tray"] = {"fit": "card", "cell_outline": False}
    # How many are left, on the pile itself: taking two of one colour needs four
    # still there, so it is a number a player has to be able to count.
    s["counter"] = {"badges": ["stock"]}
    return s


def zones(rows):
    tier = {t: [] for t in (1, 2, 3)}
    seen = {}
    for t, bonus, _, _ in rows:
        seen[t] = seen.get(t, 0) + 1
        tier[t].append(f"t{t}_{bonus}_{seen[t]:02d}")
    return [
        {"key": "tableau", "label": "Bought", "layout": "row", "visibility": "owner", "copies": "per_seat",
         "pos": [[0.02, 0.01, 0.55, 0.15], [0.02, 0.85, 0.55, 0.99]]},
        {"key": "reserve", "label": "Reserved", "layout": "row", "visibility": "owner", "copies": "per_seat",
         "pos": [[0.57, 0.01, 0.80, 0.15], [0.57, 0.85, 0.80, 0.99]]},
        {"key": "nobles", "label": "Nobles", "layout": "grid", "grid": [3, 1],
         "tags": ["optional", "market"], "pos": [0.02, 0.17, 0.40, 0.30]},
        {"key": "noble_deck", "layout": "stack", "visibility": "secret", "display": "offscreen", "tags": ["shuffle"],
         "pos": [0.42, 0.17, 0.50, 0.30],
         "contents": [f"noble_{i + 1}" for i in range(10)]},

        {"key": "t3_deck", "label": "III", "layout": "stack", "visibility": "secret", "use": "abilities", "tags": ["shuffle"],
         "pos": [0.02, 0.32, 0.11, 0.47],
         "tooltip": "Tier three. Click to reserve the top card without looking at it.",
         "contents": tier[3],
         "abilities": [{"phases": ["act"], "cost": {"reserve_slots": 1},
                      "action": ["draw_from:t3_deck:mine.reserve:1"] + RESERVE_GOLD}]},
        {"key": "t3_row", "layout": "grid", "grid": [4, 1], "tags": ["optional", "market"],
         "pos": [0.13, 0.32, 0.55, 0.47]},
        {"key": "t2_deck", "label": "II", "layout": "stack", "visibility": "secret", "use": "abilities", "tags": ["shuffle"],
         "pos": [0.02, 0.49, 0.11, 0.64],
         "tooltip": "Tier two. Click to reserve the top card without looking at it.",
         "contents": tier[2],
         "abilities": [{"phases": ["act"], "cost": {"reserve_slots": 1},
                      "action": ["draw_from:t2_deck:mine.reserve:1"] + RESERVE_GOLD}]},
        {"key": "t2_row", "layout": "grid", "grid": [4, 1], "tags": ["optional", "market"],
         "pos": [0.13, 0.49, 0.55, 0.64]},
        {"key": "t1_deck", "label": "I", "layout": "stack", "visibility": "secret", "use": "abilities", "tags": ["shuffle"],
         "pos": [0.02, 0.66, 0.11, 0.81],
         "tooltip": "Tier one. Click to reserve the top card without looking at it.",
         "contents": tier[1],
         "abilities": [{"phases": ["act"], "cost": {"reserve_slots": 1},
                      "action": ["draw_from:t1_deck:mine.reserve:1"] + RESERVE_GOLD}]},
        {"key": "t1_row", "layout": "grid", "grid": [4, 1], "tags": ["optional", "market"],
         "pos": [0.13, 0.66, 0.55, 0.81]},

        # Tall enough for its own name and for six gems that spell theirs out:
        # the plates are height-bound in a wide zone, so the band the label
        # takes off the top comes off their width, and "Diamond" was "D...".
        # A supply: the six plates *are* the tokens, and how many are left is
        # the stock the engine keeps on them. Nothing may point at one, which is
        # what a plate used to say for itself by wearing "immutable".
        {"key": "supply", "label": "The bank", "layout": "grid", "use": "abilities", "grid": [6, 1],
         "status": "supply", "tags": ["tray"], "pos": [0.57, 0.32, 0.98, 0.52],
         "contents": [f"pile_{k}:{SUPPLY}" for k in KEYS] + [f"pile_gold:{GOLD_SUPPLY}"]},
        {"key": "controls", "layout": "row", "tags": ["optional"],
         "pos": [0.57, 0.60, 0.98, 0.78],
         "contents": ["reserve_button", "done_button"]},
    ]


# Reserving pays a gold token, and only if the bank still has one — which is a
# yes/no the computed tag "has_gold" answers as a 1 or a 0, so it multiplies
# into the amount instead of needing a branch the format does not have.
RESERVE_GOLD = [
    "stat_gain:t_gold@mine.player:count:has_gold@supply.pile_gold",
    "stat_gain:t_total@mine.player:count:has_gold@supply.pile_gold",
    "stat_damage:stock@supply.pile_gold:count:has_gold@supply.pile_gold",
    "stat_set:done@mine.player:1",
    "next_phase",
]


def piles():
    out = []
    for k, label, _, _, _, _ in GEMS:
        out.append({
            "key": f"pile_{k}", "text": label,
            "tooltip": f"{label} tokens. Take one — up to three different colours a turn — "
                       "or take two of this colour alone, which needs four still here.",
            "tags": [f"pile_{k}", f"plate_{k}", "counter"],
            "card_stats": {"plenty": 0},
            "abilities": [
                {"key": f"take_{k}", "text": f"Take one {label.lower()}",
                 "phases": ["act"], "cost": {"exhaust": 1, "stock@self": 1},
                 "action": [f"stat_gain:t_{k}@mine.player:1",
                            "stat_gain:t_total@mine.player:1",
                            "stat_gain:takes@mine.player:1",
                            "stat_damage:first_take@mine.player:1",
                            "next_phase"]},
                {"key": f"take2_{k}", "text": f"Take two {label.lower()}",
                 "phases": ["act"],
                 "cost": {"exhaust": 1, "stock@self": 2, "plenty@self": 1,
                          "first_take@mine.player": 1},
                 "action": [f"stat_gain:t_{k}@mine.player:2",
                            "stat_gain:t_total@mine.player:2",
                            "stat_set:done@mine.player:1",
                            "next_phase"]},
                {"key": f"back_{k}", "text": f"Put back a {label.lower()}",
                 "phases": ["discard"], "cost": {f"t_{k}@mine.player": 1},
                 "action": ["stat_gain:stock@self:1",
                            "stat_damage:t_total@mine.player:1",
                            "next_phase"]},
            ],
        })
    out.append({
        "key": "pile_gold", "text": "Gold",
        "tooltip": "Gold is wild: it pays for any colour. It is never taken directly — "
                   "reserving a card is what earns one.",
        "tags": ["pile_gold", "plate_gold", "counter"],
        "card_stats": {"plenty": 0},
        "abilities": [
            {"key": "back_gold", "text": "Put back a gold",
             "phases": ["discard"], "cost": {"t_gold@mine.player": 1},
             "action": ["stat_gain:stock@self:1",
                        "stat_damage:t_total@mine.player:1",
                        "next_phase"]},
        ],
    })
    return out


def buttons():
    return [
        {"key": "reserve_button", "text": "Reserve a card",
         "asset": "square:slate",
         "tooltip": "Hold a face-up card for later, and take a gold token if any are left. "
                    "Three reserved cards at a time; buying one gives the slot back. "
                    "To reserve the top of a deck unseen, click the deck itself.",
         "tags": ["immutable"],
         "play": {"phases": ["act"], "cost": {"reserve_slots": 1},
                  "target": {"type": "card", "count": 1,
                             "zones": ["t1_row", "t2_row", "t3_row"]},
                  "action": ["set_owner:target:mine", "stat_set:reserved@target:1",
                             "move:target:mine.reserve"] + RESERVE_GOLD}},
        {"key": "done_button", "text": "Done taking",
         "asset": "circle:slate",
         "tooltip": "Stop after one or two tokens. Taking a third ends your turn on its own.",
         "tags": ["immutable"],
         "play": {"phases": ["act"], "needs": ["takes@mine.player >= 1"],
                  "action": ["stat_set:done@mine.player:1", "next_phase"]}},
    ]


def development(rows):
    SHAPE = {1: "circle", 2: "square", 3: "diamond"}
    ART = {"white": "silver", "blue": "blue", "green": "green",
           "red": "crimson", "black": "slate"}
    out, seen = [], {}
    for tier, bonus, vp, cost in rows:
        seen[tier] = seen.get(tier, 0) + 1
        words = ", ".join(f"{cost[k]} {dict((g[0], g[1].lower()) for g in GEMS)[k]}"
                          for k in KEYS if cost[k])
        # Only what is printed on this card. The scratch numbers the pricing
        # writes start at the same zero on all ninety, so the stats node grants
        # them, and buying is one sentence the "development" tag carries.
        stats = {f"cost_{k}": cost[k] for k in KEYS}
        stats["tier"] = tier
        if vp:
            stats["vp"] = vp
        out.append({
            "key": f"t{tier}_{bonus}_{seen[tier]:02d}",
            "text": dict((g[0], g[1]) for g in GEMS)[bonus],
            "tooltip": f"Costs {words}, less your discounts, "
                       f"with gold covering any shortfall. Gives a permanent {bonus} "
                       f"discount" + (f" and {vp} prestige." if vp else "."),
            "asset": f"{SHAPE[tier]}:{ART[bonus]}",
            "tags": ["development", f"gives_{bonus}", f"plate_{bonus}"],
            "card_stats": stats,
        })
    return out


def nobles(rows):
    out = []
    for i, cost in enumerate(rows):
        words = " + ".join(f"{cost[k]} {k}" for k in KEYS if cost[k])
        # Every noble is worth three and starts unmet, and arriving is the same
        # act for all ten; only the threshold is this card's. See the tag.
        stats = {f"n_{k}": cost[k] for k in KEYS}
        stats["vp"] = 3
        out.append({
            "key": f"noble_{i + 1}", "text": "Noble",
            "tooltip": f"Visits you for free once your discounts reach {words}. "
                       "Worth 3 prestige, and only one noble may arrive per turn.",
            "asset": "star:6:gold",
            "tags": ["noble", "plate_noble"],
            "card_stats": stats,
        })
    return out


# Every number a seat holds is granted by the stats node through on: ["player"],
# so a seat card carries only what makes it that seat. The one thing that does
# is who goes first — which is a fact about north, not about players.
def seat_cards():
    return [
        {"key": "north", "text": "North", "tags": ["north_side"], "card_stats": {"opens": 1}},
        {"key": "south", "text": "South", "tags": ["south_side"]},
    ]


def phases():
    # The last route leads back into the same phase with the seat held still:
    # a turn carries on until the player is done with it. What resets once per
    # turn is on_enter, what is recomputed after every take is actions.
    routes = [{"when": "done@mine.player >= 1", "then": "noble_check"},
              {"when": "takes@mine.player >= 3", "then": "noble_check"},
              {"then": "act", "seat": "same"}]
    turn_top = ["stat_set:takes@each.anyone.player:0",
                "stat_set:done@each.anyone.player:0",
                "stat_set:first_take@each.anyone.player:1",
                "ready:supply"]
    return [
        {"key": "setup", "type": "automatic",
         "actions": ["draw_from:noble_deck:nobles:3",
                     "draw_from:t1_deck:t1_row:4",
                     "draw_from:t2_deck:t2_row:4",
                     "draw_from:t3_deck:t3_row:4"],
         "next": [{"then": "act"}]},
        # The seat changes on entry and the actions run after it, so "mine" here
        # is already the player about to act — which is what lets one phase both
        # hand the turn over and price the market for whoever it handed it to.
        # Only a phase a player acts in is asked to hand over, which is why this
        # is the turn's first *input* rather than an automatic step before it.
        #
        # A token changes what is affordable, so the row is priced again between
        # one take and the next — every time round, where the counters reset on
        # arrival and nowhere else. That split used to be two phase keys, the
        # second a copy of the first with its first four lines and one word gone.
        {"key": "act", "type": "player_input", "seat": "next",
         "label": "Take tokens, buy a card, or reserve one",
         "on_enter": turn_top, "actions": plenty() + REPRICE, "next": routes},
        {"key": "noble_check", "type": "automatic", "actions": ["activate_zone:nobles"],
         "next": [{"when": "count:noble_ready >= 1", "then": "noble_pick"},
                  {"then": "cleanup"}]},
        {"key": "noble_pick", "type": "player_input", "zone": "nobles",
         "label": "A noble will visit you — choose which",
         "next": [{"then": "cleanup"}]},
        {"key": "cleanup", "type": "automatic",
         "actions": ["draw_from:t1_deck:t1_row:1",
                     "draw_from:t2_deck:t2_row:1",
                     "draw_from:t3_deck:t3_row:1"],
         "next": [{"when": f"t_total@mine.player >= {HAND_LIMIT + 1}", "then": "discard"},
                  {"when": f"score@mine.player >= {TARGET}", "then": "flag_end"},
                  {"then": "handover"}]},
        {"key": "discard", "type": "player_input", "zone": "supply",
         "label": "Put tokens back until you hold ten",
         "next": [{"when": f"t_total@mine.player >= {HAND_LIMIT + 1}", "then": "discard"},
                  {"when": f"score@mine.player >= {TARGET}", "then": "flag_end"},
                  {"then": "handover"}]},
        {"key": "flag_end", "type": "automatic",
         "actions": ["stat_set:ending@mine.player:1"],
         "next": [{"then": "handover"}]},
        # Reaching fifteen does not stop the game: everybody finishes the round,
        # so the two questions are asked one phase apart rather than as one
        # condition, which the grammar has no "and" for.
        {"key": "handover", "type": "automatic",
         "next": [{"when": "ending@anyone.player >= 1", "then": "maybe_end"},
                  {"then": "act"}]},
        # The seat that just played is still "mine" here, so the round is over
        # exactly when that seat is not the one that opens it.
        {"key": "maybe_end", "type": "automatic",
         "next": [{"when": "opens@mine.player == 0", "then": "finish"},
                  {"then": "act"}]},
        # Highest prestige, then fewest cards bought — efficiency over points.
        {"key": "finish", "type": "automatic",
         "next": [{"when": "score@north_side > score@south_side", "then": "north_won"},
                  {"when": "score@south_side > score@north_side", "then": "south_won"},
                  {"when": "bought@north_side < bought@south_side", "then": "north_won"},
                  {"when": "bought@south_side < bought@north_side", "then": "south_won"},
                  {"then": "drawn"}]},
        {"key": "north_won", "type": "automatic",
         "actions": ["stat_gain:won@north_side:1", "reveal:north_wins"],
         "next": [{"then": "over"}]},
        {"key": "south_won", "type": "automatic",
         "actions": ["stat_gain:won@south_side:1", "reveal:south_wins"],
         "next": [{"then": "over"}]},
        {"key": "drawn", "type": "automatic", "actions": ["reveal:a_draw"],
         "next": [{"then": "over"}]},
        # Nothing calls next_phase from here, so the routing never runs and the
        # board stays readable behind the banner.
        {"key": "over", "type": "player_input", "label": "The game is over",
         "next": [{"then": "over"}]},
    ]


def endings():
    return [
        {"key": "north_wins", "text": "North wins",
         "story": "North's merchants hold the richest houses of the city.",
         "play": {"action": ["load_game:menu.json"]}},
        {"key": "south_wins", "text": "South wins",
         "story": "South's merchants hold the richest houses of the city.",
         "play": {"action": ["load_game:menu.json"]}},
        {"key": "a_draw", "text": "A dead heat",
         "story": "Equal prestige, equal shops. The guild records both names.",
         "play": {"action": ["load_game:menu.json"]}},
    ]


def build(here):
    data = os.path.join(here, "..", "ideas", "splendor", "cards.md")
    rows, noble_rows = cards_table(data), nobles_table(data)
    if len(rows) != 90 or len(noble_rows) != 10:
        raise SystemExit(f"read {len(rows)} cards and {len(noble_rows)} nobles, expected 90 and 10")
    return {
        "title": "Splendor",
        "seed": 23,
        "players": [{"card": "north"}, {"card": "south"}],
        "styles": styles(),
        "stats": stats(),
        "computed_tags": {
            # Both are yes/no questions asked as a number, so an amount can
            # multiply by them: the engine has no branch and needs none.
            "noble_ready": {"stat": "ok", "at_least": 1},
            "has_gold": {"stat": "stock", "at_least": 1},
        },
        "tags": {
            # The ability is never clicked: neither zone is tagged "activate",
            # so it is reachable only through activate_zone, which is ungated.
            # Ninety cards, one sentence. Buying a development card is the same
            # act whatever it costs — the numbers it moves are all read off the
            # card — so the tag says it once instead of ninety templates each
            # carrying a copy for somebody to keep in step.
            "development": {
                "abilities": [{"key": "price", "text": "Price", "action": pricing()}],
                "play": {"phases": ["act"], "needs": ["buyable@self >= 1"],
                         "action": buying()},
            },
            "noble": {
                "abilities": [{"key": "check", "text": "Check", "action": noble_check()}],
                "play": {"phases": ["noble_pick"], "needs": ["ok@self >= 1"],
                         "action": ["stat_gain:score@mine.player:3", "destroy:self", "next_phase"]},
            },
        },
        "zones": zones(rows),
        "phases": phases(),
        "end_conditions": [],
        "cards": (seat_cards() + piles() + buttons()
                  + development(rows) + nobles(noble_rows) + endings()),
        "setup": {"place": []},
    }


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = guard.destination(os.path.join(here, "..", "game", "games", "splendor.json"))
    if out is None:
        sys.exit(1)
    with open(out, "w", encoding="utf-8") as f:
        f.write(jsonfmt.dump(build(here)))
    print("wrote", os.path.relpath(out, os.path.join(here, "..")))
