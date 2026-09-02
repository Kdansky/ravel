#!/usr/bin/env python3
"""Pull the visible card art out of a Spellstorm print-template PDF.

Each PDF from the print pack is one card placed on a spec sheet, with every previously
exported card left behind as a stacked layer. The last image drawn is the one on top, so
we parse its placement rectangle from the content stream, render the page, and crop to it.
"""
import re, subprocess, sys, os, tempfile, zlib

def content_streams(pdf):
    with tempfile.TemporaryDirectory() as td:
        q = os.path.join(td, "q.pdf")
        # qpdf exits 3 on recoverable warnings; the repaired file is still written
        r = subprocess.run(["qpdf", "--qdf", "--object-streams=disable", pdf, q], capture_output=True)
        if r.returncode not in (0, 3) or not os.path.exists(q): raise RuntimeError(r.stderr.decode()[:200])
        d = open(q, "rb").read()
    out = []
    for m in re.finditer(rb"stream\r?\n", d):
        s = m.end()
        e = d.find(b"endstream", s)
        if e < 0: continue
        chunk = d[s:e]
        try: chunk = zlib.decompress(chunk)
        except Exception: pass
        if b" Do" in chunk and b" cm" in chunk:
            out.append(chunk)
    return out

PLACE = re.compile(rb"([-\d.]+) 0 0 ([-\d.]+) ([-\d.]+) ([-\d.]+) cm\s*/(\w+) Do")

def last_placement(pdf):
    """The biggest image drawn, latest wins on a tie -- that is the artwork, not a logo or a stray layer."""
    best, area = None, -1
    for c in content_streams(pdf):
        for m in PLACE.finditer(c):
            w, h, x, y = (float(m.group(i)) for i in (1, 2, 3, 4))
            # a negative extent means the image is placed flipped; the origin is then the far corner
            if w < 0: x, w = x + w, -w
            if h < 0: y, h = y + h, -h
            if w * h >= area:
                best, area = (x, y, w, h), w * h
    return best

def page_height(pdf):
    info = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
    m = re.search(r"Page size:\s+([\d.]+) x ([\d.]+)", info)
    return float(m.group(1)), float(m.group(2))

def extract(pdf, out, dpi=300, maxpx=2000):
    place = last_placement(pdf)
    pw, ph = page_height(pdf)
    with tempfile.TemporaryDirectory() as td:
        base = os.path.join(td, "p")
        subprocess.run(["pdftoppm", "-png", "-r", str(dpi), "-f", "1", "-l", "1", pdf, base], check=True)
        png = [os.path.join(td, f) for f in sorted(os.listdir(td)) if f.endswith(".png")][0]
        s = dpi / 72.0
        cmd = ["magick", png]
        if place:
            x, y, w, h = place
            cmd += ["-crop", "%dx%d+%d+%d" % (round(w*s), round(h*s), round(x*s), round((ph-y-h)*s)), "+repage"]
        cmd += ["-resize", "%dx%d>" % (maxpx, maxpx), "-quality", "88", out]
        subprocess.run(cmd, check=True)
    return place

if __name__ == "__main__":
    print(extract(sys.argv[1], sys.argv[2], *(int(a) for a in sys.argv[3:])))
