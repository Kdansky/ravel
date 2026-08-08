# Idea 03 — Procedural Placeholder Art

> *Better basic placeholders are needed […] so that we don't need to reference a
> jpg, but can just do something like "polygon:5 ; green" and have that work
> reasonably well for prototyping.* — `IDEAS.md`

**Status:** shipped · **Size:** small (~200 LOC, one new module)

The only idea in the file with **zero dependencies on anything else**. It can be
built today, in parallel with everything, by someone who never touches
`flow.lua`. It is also the one that most improves the day-to-day of authoring
games, because right now a new card is either a jpg someone has to make or a
grey rectangle.

---

## Where it plugs in

`cards.image(def_key)` (`game/cards.lua:289`) resolves `def.asset` to a
`love.graphics.Image` or nil, with a cache. `draw_card_face`
(`game/render.lua:280`) branches on whether that returned an image: with one it
draws the art band plus a text band, without one it centres the title on a flat
colour.

**The key design decision: render the shape once into a canvas, cache it as an
Image, and return it from `cards.image` unchanged.**

That means `render.lua` needs no changes at all, animation and the detail view
and the tooltip all get the art for free, and the module boundary stays exactly
where ARCHITECTURE invariant 4 puts it (`cards.image` is the one deliberate
presentation exception; this doesn't add a second one). The alternative — a
draw-callback threaded through the renderer — is more flexible and much worse.

Cost of the canvas approach: a fixed resolution. Render at 256×256; placeholders
upscaled on a large card look like placeholders, which is the point.

## Grammar

Match the engine's existing `op:param:param` style (DESIGN.md: no nested arrays,
no code-like expressions). The `;` in the sketch becomes a `:` for consistency:

```json
"asset": "polygon:5:green"          // pentagon
"asset": "circle:crimson:navy"      // crimson disc on navy
"asset": "star:6:gold"
"asset": "stripes:4:red:white"
"asset": "checker:8:black:white"
"asset": "auto"                     // ← the important one
```

- **Shapes:** `circle`, `square`, `triangle`, `diamond`, `polygon:<n>`,
  `star:<n>`, `cross`, `stripes:<n>`, `checker:<n>`, `dots:<n>`
- **Colours:** a fixed named palette (~20 entries: the CSS basics plus the
  muted tones the existing card art uses) or `#rrggbb`
- **Form:** `<shape>[:<n>]:<fg>[:<bg>]`. Background defaults to a darkened
  `fg`, so one-colour specs look deliberate.

Detection: anything that isn't a bare filename or an `http(s)://` URL is tried
as a procedural spec. The existing filename check (`game/cards.lua:310`) already
rejects non-filenames — that branch becomes "try the shape parser, then fall
back to text-only".

### `auto` is the feature that actually matters

`"asset": "auto"` hashes the card **key** into a shape, a sides count and a hue,
deterministically. Every card in a new game instantly has distinct, stable,
recognisable art with zero authoring effort, and it never changes between runs
so you learn to recognise cards by their shape.

Better still: make it the **default when `asset` is absent**, behind a
per-game opt-in (`"placeholder_art": true` in the game file) so shipped games
keep their current look. A brand-new game written from scratch then has real
visual differentiation from the first save.

## Module

New `game/art.lua`, presentation layer, below `render` and beside nothing:

```
art.parse(spec)   -> { shape, n, fg, bg } or nil          -- pure, testable headless
art.render(spec)  -> love.graphics.Image or nil           -- canvas, pcall-guarded
```

`parse` must be pure and have no `love` dependency at all, so `validate.lua`
can call it at load time to warn on a typo'd spec, and so `tests/run.lua` can
test the grammar without a graphics stub. `render` is the only part that touches
`love.graphics`, and every call is `pcall`-wrapped so the headless shim
(`headless.lua`, which has no `newCanvas`) returns nil cleanly — same contract
`cards.image` already honours.

## Work plan

1. `art.parse` + palette + its tests. No graphics.
2. `art.render` — canvas, shapes, `pcall` guards.
3. `cards.image` — route non-filename, non-URL assets to `art.render`; cache
   result in the existing `img_cache`. Invalidate on `cards.edit` of the asset
   field (`game/cards.lua:115` already does this).
4. `art.auto(key)` — hash → spec. Wire `"asset": "auto"` and the
   `placeholder_art` game flag.
5. `validate.lua` — a warning for an unparseable spec, plus its `CASES` entry
   (`tests/run.lua:791`).
6. `tests/render_smoke.lua` — drive every shape through the draw path.
7. `AUTHORING.md` — the grammar table and the palette.

## The trap: art colour is not game data

`IDEAS.md`'s second bullet — *graphics stay independent of the game engine* — is
already an invariant, and this feature is the most likely thing to break it.

The moment a card is `"asset": "circle:red"`, it is tempting for a solitaire
rule to ask "is this card red". **It must not.** Colour that the rules care
about is a tag or a stat (`"tags": ["red"]`, `"card_stats": {"rank": 7}`); the
asset spec is decoration that happens to agree with it. `art.parse` output must
never be reachable from `predicate.lua` or `actions.lua` — enforce it by keeping
`art.lua` unrequired by anything below the presentation line, which the module
map (ARCHITECTURE) makes visible at a glance.

Same trap, smaller: don't let `def.color` (already used by `draw_card_face`,
`game/render.lua:282`) drift into rules either.

## Done when

- A game file with no `assets/` directory at all looks good enough to playtest.
- `luajit tests/render_smoke.lua` covers every shape.
- The existing games are pixel-identical (they all specify real assets).

---

## Shipped later: the readback is gone

`art.render` used to finish with `newImage(canvas:newImageData())`. That bought
nothing — a Canvas is already a drawable texture, and `getDimensions` is the
only thing anyone asks of one — while costing a full GPU readback per card
(256×256 RGBA each, so about 22 MB of it for a game the size of Lost Cities,
every one of them stalling the pipeline).

It also broke the feature in Brave. `newImageData` is a *pixel read*, and pixel
reads are exactly what browser fingerprinting protection perturbs: Brave adds
noise to canvas and WebGL reads by default, so every generated card came back
speckled while the JPEGs — never read back — were perfect. The report was "the
generated graphics are broken but the pictures are fine", which is that
distinction exactly.

Drawing the canvas directly never reads a pixel, so there is nothing left to
farble, and it is faster besides. Worth remembering as a general rule for this
codebase: **a readback is a fingerprinting surface, and in a browser that means
it is a correctness surface.**
