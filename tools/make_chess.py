#!/usr/bin/env python3
"""Generate game/games/chess.json.

Thirty-two pieces on named starting squares is too many to hand-write, and the
engine has no notion of "an instance with parameters" — a card that starts in
play does so via `to_slot`, one template per square. So the file is generated
and the generator is checked in, the same answer Lost Cities reached
(ideas/01-boardgames.md, gap 3).

    python3 tools/make_chess.py

The interesting part is how little is here. Movement is six `patterns` entries
shared by both colours: a pattern's pair is a *direction*, walked up to `range`
times, so blocking, leaping and range are one loop rather than three rules, and
"forward" is oriented per seat so one pawn definition serves black and white
(ideas/08-grid-movement-notation.md).
"""

import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt

FILES = "abcdefgh"
BACK_RANK = ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]

# Row 1 is the top of the board and black's back rank; row 8 is white's. White
# is the first seat, so it faces row 1 and both colours call that "forward".
SEATS = [
    ("white", "White", 8, 7, [0.92, 0.92, 0.88], "silver"),
    ("black", "Black", 1, 2, [0.18, 0.18, 0.22], "slate"),
]

GLYPH = {"king": "K", "queen": "Q", "rook": "R", "bishop": "B", "knight": "N", "pawn": "P"}

# Vectors are directions, not destinations. "mirrored" negates each axis
# independently, so one pair stands for its whole family: [[1,0],[0,1]] is all
# four orthogonals and [[1,2],[2,1]] is the knight's eight.
PATTERNS = {
    "line_ortho": {"vectors": [[1, 0], [0, 1]], "class": ["ray", "mirrored"]},
    "line_diag":  {"vectors": [[1, 1]],         "class": ["ray", "mirrored"]},
    "adjacent":   {"vectors": [[1, 0], [0, 1], [1, 1]], "class": ["step", "mirrored"]},
    "knight_leap": {"vectors": [[1, 2], [2, 1]], "class": ["step", "mirrored"]},
    # A step of [0,1] has no square before it, so nothing can block it. The
    # opening run is a ray of two, which is why a piece directly in front stops
    # it — the same rule that stops a rook, not a special case for pawns.
    "pawn_step":   {"vectors": [[0, 1]],           "class": ["step"]},
    "pawn_run":    {"vectors": [[0, 1]],           "class": ["ray:2"]},
    "pawn_take":   {"vectors": [[1, 1], [-1, 1]],  "class": ["step"]},
}

# Castling has exactly four destinations and they never change, so they are
# named as squares rather than derived as directions. An absolute pattern's
# pairs are cells — [col, row], 1-based, row 1 at the *top* — which is why a
# board row and a chess rank are not the same number: white's back rank is row 8.
#
# Naming the squares this way is also what makes "and these cells must be empty"
# an ordinary condition: a pattern is a scope, so count:piece@w_castle_k_path
# reads what is standing on them.
CASTLE = []
for _seat, _label, _back, _pawn, _rgb, _pal in SEATS:
    # Queenside first, so the two buttons sit in board order: the long castle
    # on the left, where it happens, and the short castle on the right.
    for side, king_col, rook_file, rook_col, between in (
        ("q", 3, "a", 4, [2, 3, 4]),       # king e→c, rook a→d; b, c and d clear
        ("k", 7, "h", 6, [6, 7]),          # king e→g, rook h→f; f and g clear
    ):
        CASTLE.append({
            "seat": _seat, "label": _label, "side": side, "back": _back,
            "king_col": king_col, "rook_file": rook_file, "rook_col": rook_col,
            "path": [[c, _back] for c in between],
        })

# How each piece moves. A bare pattern name is a rule of its own and lands on
# anything that is not mine; only the pawn, whose three rules genuinely differ
# in what may be standing on the far square, needs the long form.
MOVES = {
    "rook":   ["line_ortho"],
    "bishop": ["line_diag"],
    "queen":  ["line_ortho", "line_diag"],
    "knight": ["knight_leap"],
    "king":   ["adjacent"],
    "pawn": [
        {"patterns": ["pawn_step"], "fill": "empty"},
        {"patterns": ["pawn_run"], "fill": "empty", "needs": {"rank@self": {"equals": 2}}},
        {"patterns": ["pawn_take"], "fill": "enemy"},
    ],
}

# Wikimedia's standard piece set: Chess_<piece><d|l>t60.png, d dark and l light.
# The picture is decoration that happens to agree with the rules — nothing reads
# it, and a piece is never a knight because it is drawn as one.
ART = {"king": "k", "queen": "q", "rook": "r", "bishop": "b", "knight": "n", "pawn": "p"}


def piece(seat, colour_label, kind, file_idx, row, palette):
    """One card: a piece. Where it starts is setup's business, not the card's."""
    key = f"{seat[0]}_{kind}_{FILES[file_idx]}"
    return {
        "key": key,
        "text": f"{colour_label} {kind.capitalize()}",
        "tooltip": f"{FILES[file_idx]}{9 - row} — {colour_label.lower()} {kind}",
        "asset": f"Chess_{ART[kind]}{'l' if seat == 'white' else 'd'}t60.png",
        # The seat's own key as a tag is what makes this piece that player's.
        # The board is one shared zone, so ownership cannot come from the zone.
        # Its own key is a tag too, so one piece can be named by another's
        # condition — which is how a castling gate asks about its rook.
        # The "piece" style is both of those: no title, because a knight
        # labelled "White Knight" is worse than one that just looks like a
        # knight and the label costs a quarter of a 64-cell board's height; and
        # no plate, so the PNG's transparency lets the square show through. The
        # name still shows in the tooltip.
        "tags": [seat, "piece", kind, key, "stays_ready"],
        # rank is stamped by the engine; moves_made is the piece's own count,
        # and is what "has this ever moved" reads.
        "card_stats": {"rank": 0, "moves_made": 0},
        # Moving is an activation, so everything about it lives in one block.
        # "taken" is where a captured piece goes: without that third argument an
        # occupied square refuses the move, which is what every non-board game
        # wants. Then hand over — a phase's `ends_after` counts cards *played*,
        # and a piece moving is an activation, so the move ends the turn itself.
        # `exhausts: false` for the same reason: what bounds a turn to one move
        # here is the handover, not the piece being spent until the round wraps.
        "activate": {
            "moves": MOVES[kind],
            "action": ["move_to:target:taken", "gain_stat:moves_made@self:1",
                       "next_phase"],
        },
    }


def castle_card(c):
    """Castling as a card, not a move.

    Its destinations are constants, so it needs no targeting at all — and a
    played card is gated by `needs`, which an activated one is not. Playing it
    marks the king as moved, which is what closes its own gate.
    """
    king, rook = f"{c['seat'][0]}_king_e", f"{c['seat'][0]}_rook_{c['rook_file']}"
    return {
        "key": f"{c['seat'][0]}_castle_{c['side']}",
        "text": f"Castle {'kingside' if c['side'] == 'k' else 'queenside'}",
        "tooltip": (
            "King and rook both still unmoved, and the squares between them "
            "empty. The king moves two toward the rook; the rook hops to its "
            "far side. Counts as your move."
        ),
        "asset": f"Chess_k{'l' if c['seat'] == 'white' else 'd'}t60.png",
        "tags": [c["seat"], "castling"],
        "play": {
            "needs": {
                # Neither piece may have moved. A captured piece carries no stat
                # at all, and a stat nobody carries is absent rather than zero,
                # so this also refuses a rook that was taken — no presence term.
                f"moves_made@{king}": {"equals": 0},
                f"moves_made@{rook}": {"equals": 0},
                # The squares between them, read as a scope over named cells.
                f"count:piece@{c['seat'][0]}_castle_{c['side']}_path": {"equals": 0},
            },
            "action": [
                f"place:{king}:{c['king_col']}:{c['back']}",
                f"place:{rook}:{c['rook_col']}:{c['back']}",
                f"gain_stat:moves_made@{king}:1",
                "next_phase",
            ],
        },
    }


# The rulebook, as a card, because that is where everything else in this engine
# lives. "phases": [] means it works in no phase, so it can never be played —
# it is a thing to read, not a move. "immutable" keeps it out of targeting, so
# no stray effect can eat the instructions.
HOW_TO_PLAY = {
    "key": "how_to_play",
    "text": "How to play",
    "tags": ["immutable"],
    "play": {"phases": []},
    "tooltip": (
        "Click one of your pieces to light up the squares it can reach, then "
        "click a square to move. Click an enemy piece to take it — its square "
        "lights up too.\n"
        "\n"
        "Castling: the two buttons beside your graveyard. Needs king and rook "
        "both unmoved, and the squares between them empty.\n"
        "\n"
        "Not implemented yet:\n"
        "- Check and checkmate. You win by capturing the king, and nothing "
        "stops you moving into check or castling through it.\n"
        "- En passant.\n"
        "- Pawn promotion. A pawn reaching the far rank just stops there.\n"
        "- Draws: stalemate, threefold repetition, the fifty-move rule.\n"
        "- Resigning and offering a draw."
    ),
}


def build():
    # The seat card is not the colour. Its key used to be "white", which is also
    # the tag every white piece carries — so `@white` meant the sixteen pieces
    # while `card:white` meant this one card. A name that means two things is the
    # mistake a game file should not be able to make, so the seat is named for
    # what it is, and the players section says which tag is its.
    templates = [
        {"key": "player_white", "text": "White"},
        {"key": "player_black", "text": "Black"},
        HOW_TO_PLAY,
    ]
    for seat, label, back, pawn_row, _rgb, palette in SEATS:
        for i, kind in enumerate(BACK_RANK):
            templates.append(piece(seat, label, kind, i, back, palette))
        for i in range(8):
            templates.append(piece(seat, label, "pawn", i, pawn_row, palette))
    templates.extend(castle_card(c) for c in CASTLE)

    patterns = dict(PATTERNS)
    for c in CASTLE:
        patterns[f"{c['seat'][0]}_castle_{c['side']}_path"] = {
            "vectors": c["path"], "class": ["absolute"], "zone": "board",
        }

    # Setup is the manual: which piece goes on which square, in reading order.
    # The cards above are what comes out of the box and say nothing about it.
    place = []
    for seat, _label, back, pawn_row, _rgb, _pal in SEATS:
        for i, kind in enumerate(BACK_RANK):
            place.append({"card": f"{seat[0]}_{kind}_{FILES[i]}", "zone": "board",
                          "slot": (back - 1) * 8 + i + 1})
        for i in range(8):
            place.append({"card": f"{seat[0]}_pawn_{FILES[i]}", "zone": "board",
                          "slot": (pawn_row - 1) * 8 + i + 1})

    return {
        "title": "Chess",
        "setup": {"place": place},
        # Two seats, said once. Everything that wants to know whether this game
        # can be played with somebody else reads this rather than counting tags.
        "players": [
            {"card": "player_white", "owns": "white"},
            {"card": "player_black", "owns": "black"},
        ],
        "styles": {
            # A piece is not a card: no title, no plate, and no frame drawn round it.
            "piece": {"title": False, "color": False, "border": False},
            "chessboard": {"fit": "fill", "ratio": "grid",
                           "chequer": ["#f0d9b5", "#b58863"], "cell_outline": False},
        },
        "patterns": patterns,
        "zones": [
            # Everything about how the board looks is one word. The squares are
            # painted, so the outline an empty cell gets by default would be a
            # rounded rectangle drawn inside a colour somebody chose — hence
            # cell_outline false. Eligibility during a move is still drawn.
            {"key": "board", "type": "grid", "grid": [8, 8],
             "pos": [0.28, 0.03, 0.72, 0.97], "tags": ["activate", "chessboard"]},
            # The right-hand column, top to bottom: black's graveyard, black's
            # castling buttons, the rules card, white's buttons, white's
            # graveyard. Each player's buttons sit against their own pile, so
            # the column reads as two halves with the help between them.
            {"key": "taken", "type": "pile", "tags": ["per_seat"],
             "pos": [[0.76, 0.65, 0.97, 0.95], [0.76, 0.05, 0.97, 0.35]]},
            # One zone per colour rather than one shared: contents belong to a
            # zone, so a per_seat zone would deal all four cards to both seats.
            {"key": "b_options", "type": "hand", "tags": ["optional"],
             "pos": [0.76, 0.36, 0.97, 0.44],
             "contents": [f"b_castle_{c['side']}:1" for c in CASTLE if c["seat"] == "black"]},
            # A pile rather than a hand: a hand dims whatever it cannot play,
            # and this card is never playable. A pile draws its top card's face
            # and adds no count badge, which is exactly one card sitting there.
            {"key": "rules", "type": "pile", "pos": [0.76, 0.45, 0.97, 0.55],
             "contents": ["how_to_play:1"]},
            {"key": "w_options", "type": "hand", "tags": ["optional"],
             "pos": [0.76, 0.56, 0.97, 0.64],
             "contents": [f"w_castle_{c['side']}:1" for c in CASTLE if c["seat"] == "white"]},
        ],
        "phases": [
            {"key": "white_move", "type": "player_input", "label": "White to move",
             "seat": "next"},
            {"key": "black_move", "type": "player_input", "label": "Black to move",
             "seat": "next"},
        ],
        # Capture the king: the honest first milestone. Check and checkmate need
        # move generation over a hypothetical board, which is its own project.
        "end_conditions": [
            {"stat": "card:w_king_e", "equals": 0, "then": ["load_game:menu.json"]},
            {"stat": "card:b_king_e", "equals": 0, "then": ["load_game:menu.json"]},
        ],
        "cards": templates,
    }


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "game", "games", "chess.json")
    with open(os.path.abspath(out), "w") as f:
        f.write(jsonfmt.dump(build()))
        f.write("\n")
    print(f"wrote {os.path.abspath(out)}")
