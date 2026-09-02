#!/usr/bin/env python3
"""Copy the Spellstorm card art into game/games/assets as ss_*.jpg.

The extraction in ideas/spellstorm/ keeps each card at its full **print bleed**
size -- 825x1125 at 300 dpi, which is 69.85 x 95.25 mm, where the card itself is
63 x 88 mm. On a card whose art runs to the edge nobody notices the extra 3 mm.
On the eighteen cards with a *discard effect*, whose printed frame is white, the
bleed is white too, so the card arrives with a thick white margin around it that
looks like a mistake rather than a border.

So everything is cropped to the trim line first. That leaves those eighteen
still wearing the white frame the printer gave them, which reads as a mistake
here rather than as a border: the engine draws its own coloured plate behind
every card, so a white rectangle inside it looks like the art is the wrong size.
The frame comes off too. Nothing is lost by it -- a discard effect is legible
from the card's own text, and the game file marks those cards `has_discard`
either way.

The engine only loads a bare filename out of games/assets (game/cards.lua), so
the art cannot live in a subdirectory of its own; the ss_ prefix is what keeps
it together instead.

    python3 tools/spellstorm_art.py
"""

import os, shutil, subprocess, sys

from PIL import Image

SRC = "ideas/spellstorm/images"
DST = "game/games/assets"

# The folders worth copying. Card backs, the boards, Robot Boy's deck and Omar's
# traps are extracted in ideas/ but nothing in the game file points at them, and
# an asset nothing references is weight with no reader.
FOLDERS = ["spells", "special", "weather", "weather-calm", "wizards", "large",
           "oren-potions"]

# Anything the game does not draw. Robot Boy is a mode this build does not have
# (ideas/spellstorm/09-engine-gaps.md); the rest are backs and player boards.
SKIP = {"spells-back", "special-spells-back", "wizards-back", "largecards-back",
        "weather-beforethestorm-back", "oren-back", "traps-back",
        "abra-journal", "oren-chemistry", "robotboy", "roboy-boy2"}

# 300 dpi. The card is 63 x 88 mm inside a 69.85 x 95.25 mm bleed, so the trim
# takes an even margin off every side.
BLEED_W, BLEED_H = 825, 1125
TRIM_W, TRIM_H = 744, 1039
OFF_X, OFF_Y = (BLEED_W - TRIM_W) // 2, (BLEED_H - TRIM_H) // 2

# The wizard cards are the same stock at a larger size, so the ratio holds.
LARGE_W, LARGE_H = 1125, 1725


def white_frame(path, thresh=246):
    """How wide the white border is on each side, in pixels.

    Measured along the middle of each side rather than from a corner: the frame
    is a rounded rectangle, so a corner is white well past where the edge stops
    being, and the bottom panel of some cards runs flush to the edge with no
    frame at all. A side with no band measures nought and is left alone.
    """
    im = Image.open(path).convert("L")
    w, h = im.size
    px = im.load()
    mid_y, mid_x = h // 3, w // 2       # a third of the way down is inside the art
    left = 0
    while left < w // 4 and px[left, mid_y] >= thresh: left += 1
    right = 0
    while right < w // 4 and px[w - 1 - right, mid_y] >= thresh: right += 1
    top = 0
    while top < h // 4 and px[mid_x, top] >= thresh: top += 1
    bottom = 0
    while bottom < h // 4 and px[mid_x, h - 1 - bottom] >= thresh: bottom += 1
    return left, top, right, bottom, w, h


def corner_bite(path, thresh=246):
    """How far the frame's rounded corners still reach along each edge.

    A straight cut through a rounded rectangle leaves four white wedges. This
    measures the longest of them, so the second cut can take them off.
    """
    im = Image.open(path).convert("L")
    w, h = im.size
    px = im.load()
    runs = []
    for y in (0, h - 1):
        for step, x0 in ((1, 0), (-1, w - 1)):
            n = 0
            while n < w // 6 and px[x0 + step * n, y] >= thresh: n += 1
            runs.append(n)
    for x in (0, w - 1):
        for step, y0 in ((1, 0), (-1, h - 1)):
            n = 0
            while n < h // 6 and px[x, y0 + step * n] >= thresh: n += 1
            runs.append(n)
    return max(runs)


def strip_frame(path):
    """Take the printed white border off, if there is one. Answers whether it did."""
    l, t, r, b, w, h = white_frame(path)
    if max(l, t, r, b) < 4:
        return False
    subprocess.run(["magick", path, "-crop",
                    "%dx%d+%d+%d" % (w - l - r, h - t - b, l, t),
                    "+repage", "-quality", "92", path], check=True)
    # The frame was a rounded rectangle and the cut above was square, so four
    # white wedges are left in the corners. Take an even bite off all four sides
    # rather than a per-side one: an uneven crop moves the art off centre, and a
    # couple of percent is cheaper than that.
    bite = corner_bite(path)
    if bite > 0:
        w, h = Image.open(path).size
        subprocess.run(["magick", path, "-crop",
                        "%dx%d+%d+%d" % (w - 2 * bite, h - 2 * bite, bite, bite),
                        "+repage", "-quality", "92", path], check=True)
    return True


def crop(src, dst):
    """Crop one card to its trim line, whatever size stock it was printed on."""
    w, h = [int(v) for v in subprocess.run(
        ["magick", "identify", "-format", "%w %h", src],
        capture_output=True, text=True, check=True).stdout.split()]
    if (w, h) == (BLEED_W, BLEED_H):
        box = "%dx%d+%d+%d" % (TRIM_W, TRIM_H, OFF_X, OFF_Y)
    elif (w, h) == (LARGE_H, LARGE_W) or (w, h) == (BLEED_H, BLEED_W):
        # Weather cards are landscape: the same trim, turned on its side.
        box = "%dx%d+%d+%d" % (TRIM_H, TRIM_W, OFF_Y, OFF_X)
    elif (w, h) == (LARGE_W, LARGE_H):
        sx, sy = LARGE_W / BLEED_W, LARGE_H / BLEED_H
        box = "%dx%d+%d+%d" % (round(TRIM_W * sx), round(TRIM_H * sy),
                              round(OFF_X * sx), round(OFF_Y * sy))
    else:
        # A size nobody planned for: copy it rather than crop it blind.
        shutil.copy2(src, dst)
        return "as-is %dx%d" % (w, h)
    subprocess.run(["magick", src, "-crop", box, "+repage", "-quality", "92", dst],
                   check=True)
    return box


def main():
    if not os.path.isdir(SRC):
        sys.exit("run me from the repository root: %s is not here" % SRC)
    n, framed = 0, 0
    for folder in FOLDERS:
        d = os.path.join(SRC, folder)
        for f in sorted(os.listdir(d)):
            stem, ext = os.path.splitext(f)
            if ext != ".jpg" or stem in SKIP or stem.startswith("robot-boy"):
                continue
            out = os.path.join(DST, "ss_" + stem.replace("-", "_") + ".jpg")
            crop(os.path.join(d, f), out)
            if strip_frame(out):
                framed += 1
            n += 1
    print("%d card faces cropped to the trim line into %s, %d of them with a "
          "printed white frame taken off" % (n, DST, framed))


if __name__ == "__main__":
    main()
