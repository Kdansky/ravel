"""Readable JSON for game files: key order preserved, and anything that fits on
one line stays there. Python's json.dump breaks every array and object across
lines, which turns a "pos" into six of them and a game file into something
nobody wants to read. Shared by both generators and by any migration script, so
a regenerated file and a hand-edited one look the same.
"""

import json

WIDTH = 96

def _one(v):
    """Single-line rendering, or None if it contains something that must break."""
    if isinstance(v, dict):
        if not v: return "{}"
        parts = []
        for k, x in v.items():
            s = _one(x)
            if s is None: return None
            parts.append(f'{json.dumps(k, ensure_ascii=False)}: {s}')
        return "{ " + ", ".join(parts) + " }"
    if isinstance(v, list):
        if not v: return "[]"
        parts = []
        for x in v:
            s = _one(x)
            if s is None: return None
            parts.append(s)
        return "[" + ", ".join(parts) + "]"
    return json.dumps(v, ensure_ascii=False)

def emit(v, ind=0):
    """Readable JSON: key order preserved, and anything that fits stays on one line."""
    pad, pin = "  " * ind, "  " * (ind + 1)
    flat = _one(v)
    if flat is not None and len(flat) + len(pad) <= WIDTH:
        return flat
    if isinstance(v, dict):
        items = [f'{pin}{json.dumps(k, ensure_ascii=False)}: {emit(x, ind + 1)}' for k, x in v.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(v, list):
        return "[\n" + ",\n".join(pin + emit(x, ind + 1) for x in v) + "\n" + pad + "]"
    return json.dumps(v, ensure_ascii=False)

def dump(d): return emit(d, 0) + "\n"
