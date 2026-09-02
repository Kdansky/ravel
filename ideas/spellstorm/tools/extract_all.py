#!/usr/bin/env python3
import os, sys, re, hashlib, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_card import extract

SRC = "/home/kdansky/code/ravel/ideas/PDFS"
DST = "/home/kdansky/code/ravel/ideas/spellstorm/images"

def slug(s):
    s = re.sub(r"\.pdf$", "", s, flags=re.I)
    s = re.sub(r"\s*-\s*Copy(\s*\(\d+\))?", "", s, flags=re.I)
    s = re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-").lower()
    return s

def run(subdir, outdir, dpi=300):
    src = os.path.join(SRC, subdir)
    out = os.path.join(DST, outdir)
    os.makedirs(out, exist_ok=True)
    seen = {}
    report = []
    for f in sorted(os.listdir(src)):
        if not f.lower().endswith(".pdf"): continue
        name = slug(f)
        target = os.path.join(out, name + ".jpg")
        if os.path.exists(target):
            report.append((f, name, "exists")); continue
        tmp = target + ".tmp.jpg"
        try:
            extract(os.path.join(src, f), tmp)
        except Exception as e:
            report.append((f, name, "FAIL %s" % e)); continue
        h = hashlib.sha1(open(tmp, "rb").read()).hexdigest()
        if h in seen:
            os.remove(tmp)
            report.append((f, name, "dup of " + seen[h]))
        else:
            os.rename(tmp, target)
            seen[h] = name
            report.append((f, name, "ok"))
    for r in report: print("%-40s %-30s %s" % r)

if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2])
