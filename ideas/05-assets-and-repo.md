# 05 — Assets and what the repository carries

**Status:** gap 2 shipped, in a different shape than proposed (`ff55754`) ·
gaps 1 and 3 open · **Size:** small, and both unblock a thing that is wanted
now.

Three items that only make sense together: art can leave the repository once a
missing picture is harmless, and a missing picture is only harmless once the
engine stops guessing what an `asset` string was supposed to be.

---

## Gap 1 — A missing picture must produce a placeholder, not nothing

*Urgency: high (blocks gap 3) · Difficulty: low · Usefulness: high*

`cards.asset_image` (`game/cards.lua:533`) still ends with:

```lua
local ok, i = pcall(love.graphics.newImage, "games/assets/" .. asset)
img_cache[def_key] = ok and i or false
return img_cache[def_key] or nil
```

A file that isn't there fails the `pcall`, caches `false`, and the card draws
with **no image at all**. That is the only reason art cannot leave the
repository today.

One correction since this was written: it is no longer *silent*. `validate.lua`
now reports `its image 'x.jpg' is not in games/assets` at load time, so the
diagnosis exists. What is missing is only the picture — which is the half that
matters here, because gap 3 makes a missing file the **normal** state rather
than an error, and a validator that shouts about seventy of them is worse than
useless. So gap 1 is now two changes: draw the placeholder, **and** stop warning
when art is deliberately absent.

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

## Gap 2 — `asset` should say what it is, not be guessed — **shipped, differently**

*Shipped `ff55754`, as a top-level `assets` table rather than as scheme prefixes.
What remains is small enough to defer.*

**What shipped.** A picture may be named once and referenced by key, and the
name is anything with no source *in* it — no extension, no scheme, no shape
colon:

```json
"assets": { "archmage_tower": { "src": "https://i.imgur.com/0vnj0kx.jpeg", "max": 4092 } }
```

This was chosen over prefixes because it answers a question prefixes don't: a
picture needs **options** (`max`, and whatever comes after it), and those want
one home rather than one per call site. Naming also makes the name the cache
key, so twenty cards sharing a picture cost one download.

**It bought most of what the prefix proposal was for.** The old failure — a
typo landing in whichever branch its shape happened to match, and an error
message about the wrong thing entirely — is gone for the case that actually
happens, a bare word: it resolves against `assets` and the validator answers
`nothing is named 'x' in the assets section` with a did-you-mean.

**What is genuinely left**, and it is now the small half: **a filename and a
shape spec are still told apart by "does it contain a dot"**
(`game/cards.lua:522`). That holds until some shape name contains one, or some
file lacks an extension. Nothing in the repository is close to either.

*Recommendation: leave it.* The remaining ambiguity costs nothing today, the
migration edits every game file, and if it ever does bite, the cheap fix is to
require a *named* entry for anything that is not obviously a shape — the
machinery for which now exists. Reassess when an author outside this repository
hits it.

The rest of this section is the original proposal, kept because the reasoning
about guessing is still the reason the assets table exists.

---

Today `cards.asset_image` decides what an inline asset string means by
pattern-matching it, in this order:

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
git — all ten are tracked, and so is every art file:

```
castle.json  chess.json  demo.json  kingdom.json  lost_cities.json
menu.json    road.json   starter_cyoa.json  tower.json  vigil.json   → all tracked
game/games/assets/                     → 83 pictures, 3.1 MB on disk, tracked
```

So the work is not "add the JSON". It is **remove the art**, which is a
different and slightly more awkward job because the files are already in
history.

**The steps:**

1. Land gap 1, or every card in every shipped game loses its picture with
   nothing in its place. This ordering is not optional.
2. `git rm --cached game/games/assets/*.{jpg,png}` and extend `.gitignore`
   (it now exists, for `__pycache__` and the copied-in test inspiration). Keep
   `CREDITS.md` and `card_art.md` tracked — they are text, they are the record of
   where the art came from, and `DESIGN.md` already requires the first to stay
   accurate. **Art that is small and part of the rules stays** — decided, not
   left open: chess's 12 piece sprites are 60×60 PNGs, 25 KB for the set, and a
   chessboard drawn with generated placeholders is not chess. The rule this
   settles on is about weight and role, not about file type: a photograph
   dressing a card goes, a glyph the game is played with stays.
3. History stays. The pack is **2.83 MiB**, essentially all art. Removing files
   going forward does not shrink a clone; only `git filter-repo` does, and that
   invalidates every existing clone and any published hash to save two and a
   half megabytes. Recorded as a decision so nobody reopens it.
4. Say where art comes from instead. A `tools/fetch_assets.sh` reading
   `CREDITS.md`, or simply "run without art; placeholders are the default look".
   The second is more honest for a repository that is about the engine.

**What this buys beyond size:** the engine stops depending on binaries nobody
can review in a diff, and the placeholder path becomes the *tested* path rather
than the fallback nobody sees. That is the real argument for doing it.
