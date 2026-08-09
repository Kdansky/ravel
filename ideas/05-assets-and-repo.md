# 05 — Assets and what the repository carries

**Status:** not started · **Size:** small, and the first two items unblock a
thing that is wanted now.

Three items that only make sense together: art can leave the repository once a
missing picture is harmless, and a missing picture is only harmless once the
engine stops guessing what an `asset` string was supposed to be.

---

## Gap 1 — A missing picture must produce a placeholder, not nothing

*Urgency: high (blocks gap 3) · Difficulty: low · Usefulness: high*

`cards.image` (`game/cards.lua:350`) ends with:

```lua
local ok, i = pcall(love.graphics.newImage, "games/assets/" .. asset)
img_cache[def_key] = ok and i or false
return img_cache[def_key] or nil
```

A file that isn't there fails the `pcall`, caches `false`, and the card draws
with **no image at all** — silently. That is the only reason art cannot leave
the repository today.

**Most of the machinery already exists.** `art.auto(key)` (`game/art.lua:107`)
hashes a string with djb2 and derives a shape, a count and an HSL hue from it,
returning an ordinary shape spec:

```lua
function M.auto(key)
	local h = 5381
	for i = 1, #tostring(key) do h = (h * 33 + tostring(key):byte(i)) % 4294967296 end
	...
end
```

It is reachable two ways — `"asset": "auto"` on one card, or
`"placeholder_art": true` for a whole game — and neither fires when a *named*
file is absent. The change is one branch: when the load fails, fall through to
`art.render(art.auto(...))` instead of caching `false`.

**Decide what gets hashed.** `art.auto` hashes the **def key**; the request was
to hash the card's **text**. They differ in a way worth choosing deliberately
rather than by accident:

| hashed | consequence |
|---|---|
| `def_key` (today) | stable for the life of the card; renaming the card's display text keeps the same placeholder |
| `text` | retitling a card gives it a new placeholder, which reads as "this is a different card" — good while authoring, jarring in a saved game |

Recommendation: keep hashing the key, because the key is the identity and the
text is presentation — but the choice belongs in `DESIGN.md` either way.

**Log it once.** A placeholder standing in for a file the author expected is a
content error, and this engine's rule is that content errors warn and play on.
It should say the filename once (not per frame — `img_cache` already gives the
once-ness for free).

---

## Gap 2 — `asset` should say what it is, not be guessed

*Urgency: medium · Difficulty: low, but it edits every game file ·
Usefulness: medium-high*

Today `cards.image` decides what an asset string means by pattern-matching it,
in this order:

1. `"auto"` → generated placeholder
2. `^https?://` → remote fetch (through `url_is_safe`, shared with the validator)
3. `^[%w_%-]+%.[%w]+$` → a bare filename under `games/assets/`
4. anything else → a shape spec, parsed by `art.parse`

The comment at step 3 admits the fragility out loud: *"Filenames carry an
extension and shape specs never do, so the two can't be confused."* That holds
only as long as no shape name ever contains a dot and no filename ever omits its
extension. A typo lands in whichever branch its shape happens to match, and the
error message is then about the wrong thing entirely — `game/cards.lua:379`
exists purely to guess which of two complaints to print.

**Proposal:** an explicit scheme prefix.

```json
"asset": "file:castle_hill.jpg"
"asset": "url:https://example.com/art.png"
"asset": "shape:polygon:5:crimson"
"asset": "auto"
```

`auto` stays bare — it names no resource. The parse becomes a `match("^(%w+):")`
and a table of handlers, the two "which error did you mean" branches disappear,
and the validator can check each form against its own rule instead of
re-deriving the guess.

**Migration:** ~40 `asset` values across nine game files plus
`tools/make_lost_cities.py`, mechanical. Accept the bare forms for one release
with a validator warning naming the prefixed form, or don't — the games are all
in this repository and a script rewrites them in a minute. Prefer the clean
break; a compatibility path here buys nothing and keeps the guessing code alive,
which is the thing being removed.

**Refuse:** a general URI scheme. Three prefixes, closed set, no `data:`, no
relative paths, no scheme the engine does not implement. The path-traversal rule
at `game/cards.lua:372` must survive the rewrite unchanged — a `file:` value is
still a bare filename under `games/assets/`, never a path.

---

## Gap 3 — Art out of the repository, JSON in

*Urgency: high (wanted now) · Difficulty: low, with one judgement call ·
Usefulness: high*

**First, a correction to the premise.** The game files are *not* missing from
git — all nine are tracked, and so are all 73 art files:

```
castle.json  demo.json  kingdom.json  lost_cities.json  menu.json
road.json    starter_cyoa.json  tower.json  vigil.json      → all tracked
game/games/assets/                          → 73 files, 3.1 MB on disk, tracked
```

So the work is not "add the JSON". It is **remove the art**, which is a
different and slightly more awkward job because the files are already in
history.

**The steps:**

1. Land gap 1, or every card in every shipped game loses its picture with
   nothing in its place. This ordering is not optional.
2. `git rm --cached game/games/assets/*.{jpg,png}` and add a `.gitignore`
   (there is none today). Keep `CREDITS.md` and `card_art.md` tracked — they are
   text, they are the record of where the art came from, and `DESIGN.md` already
   requires the first to stay accurate.
3. Decide about history. The pack is **2.83 MiB**, essentially all art. Removing
   the files going forward does not shrink a clone; only a history rewrite
   (`git filter-repo`) does, and that invalidates every existing clone and any
   published hash. For a repository this size the honest answer is probably
   **leave history alone** — 2.83 MiB is not a problem worth a rewrite — but it
   is a decision, not an oversight, and should be recorded as one.
4. Say where art comes from instead. A `tools/fetch_assets.sh` reading
   `CREDITS.md`, or simply "run without art; placeholders are the default look".
   The second is more honest for a repository that is about the engine.

**What this buys beyond size:** the engine stops depending on binaries nobody
can review in a diff, and the placeholder path becomes the *tested* path rather
than the fallback nobody sees. That is the real argument for doing it.
