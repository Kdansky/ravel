# What is already built

**Read this before reading code.** Every idea in this folder that has shipped is
recorded here: what it does, which files it lives in, the decisions that are
load-bearing, and the traps that cost real time the first time round. The
per-idea design documents for shipped work have been folded in and deleted —
this file replaces them.

**If you last read a game file before the syntax pass, read that section first**
— a card is written differently now, and nothing else in this document will
parse the way you remember.

Still open, in their own files: [01](01-boardgames.md) (board games past Lost
Cities), [04](04-simulation-games.md) (Cultist Simulator) and
[09](09-composition.md) (one game out of several files).

The three reference documents remain the source of truth for detail:
`DESIGN.md` (directives), `AUTHORING.md` (content manual), `ARCHITECTURE.md`
(engine internals and invariants).

---

# Working in this repo

## Commands

```sh
luajit tests/run.lua              # logic suite — also run it under lua5.4
lua5.4 tests/run.lua              # both must pass, and produce identical goldens
luajit tests/render_smoke.lua     # draw-path crash test (LuaJIT only)
luajit play.lua [game.json [seed]]# interactive CLI
luajit check.lua game.json        # validate a file without running it
luajit packet.lua '<blob>'        # decode a network packet into readable text
RAVEL_GOLDEN=write luajit tests/run.lua   # re-record golden traces, deliberately
```

## The browser build

`docker compose up -d` serves the game on **localhost:9009**. The entrypoint
zips `game/` into `game.love` and re-packs about a second after any file
changes. If a change does not appear, check the watcher is alive
(`docker compose exec ravel ps -o pid,args`) — it died silently for the life of
every container before `691da84`.

## Driving the browser from a test

Nothing in the repo does this, but most of the networking was verified this way
and it is by far the fastest way to check anything visual or browser-specific:

```sh
npm install playwright-core          # in a scratch dir, not the repo
npx playwright-core install chromium firefox
```

```js
const { chromium } = require('playwright-core');
const br = await chromium.launch({ args: ['--use-gl=swiftshader','--enable-unsafe-swiftshader'] });
const ctx = await br.newContext();          // ONE context = one browser profile
const A = await ctx.newPage(), B = await ctx.newPage();   // two tabs that can see each other
```

Four things that will waste an hour otherwise:

- **`browser.newPage()` creates a new context each time.** Two pages made that
  way are two *profiles* — no shared `BroadcastChannel`, no shared storage. Use
  `ctx.newPage()` twice for two tabs, and separate `launch()` calls for two
  genuinely separate browsers.
- **Lua `print()` reaches the JS console**, so `page.on('console', …)` is your
  log. A Lua error shows as LÖVE's error screen, not a JS exception.
- **`waitForSelector` waits for *visible*.** The networking panel starts
  `display:none`, so it needs `{ state: 'attached' }`.
- **Canvas clicks are pixel coordinates** and the layout moves when card counts
  change. Screenshot first, read the coordinates off the image, and prefer
  "click each candidate until the state hash changes" over a fixed guess.

## Traps that are not obvious

- `find_card(key)` in the test suite matches **destroyed** entities too — a
  destroyed card is still in the entity array. Pass the zone to scope it.
- Lua 5.4 allows **200 live locals in the main chunk**; `tests/run.lua` is at
  the limit. Wrap new top-level fixtures in `do … end`.
- A `local function` called *above* its declaration resolves as a nil global and
  fails at runtime, not at load. `tests/run.lua` greps every module for this.

---

# 00 — Stats live on cards · shipped (`4b1a96f` and before)

**What it does.** There is no player entity. There are three entity kinds —
`zone`, `slot`, `card` — and the player is a card tagged `player`.
`declaration.parse` injects two cards into a hidden `system` zone: a **player
card** holding `setup.player`'s stats and `plays`, and a **system card** (key
`system`) holding `round` and `turn`. A game that wants a visible hero just tags
a board card `player` and inherits stats, targeting, rendering and undo.

**Why it mattered.** Stats used to be global in two ways that disagreed: reads
summed every entity, writes went to whichever entity held the stat first. That
made hot-seat, chess and Cultist Simulator each *impossible* rather than merely
hard. Everything since has been vocabulary rather than special cases.

**The vocabulary it created.** A subject is `[<fn>:]<arg>[@<scope expression>]`,
where a scope expression is `[<quant>.][<owner>.]<zone-or-tag>`:

```
hp@each.enemy.creature       every creature an opponent owns
sum:value@mine.red           my red expedition's score
destroy:each.enemy.creature  a board wipe that spares your own
move_to:enemy.arena          a destination must be one zone, so this is theirs
```

`predicate.parse_subject` is the only place that grammar is decided and
`predicate.entities_in_scope` the only place a scope becomes entities, so
conditions, costs and effects can never disagree about who `@player` is.

**Seats.** Every card tagged `player` is a seat, in `G.seat_list` (file) order,
named by its own key. A zone declaring `per_seat` is built once per seat;
`zones.find` resolves a bare key against the active seat, derived from the
system card's `turn` rather than cached — so undo restores whose turn it is.
**A card's owner is the seat of its zone**, which is why ownership needs no
per-card state. A card in a shared zone has no owner.

**Bare means "anyone", deliberately.** An unqualified scope filters by nothing,
so every game written before seats existed changed by zero bytes. Real card text
reads this way too: "destroy all creatures" destroys yours, and it is the
*narrowing* that gets a word.

---

# 05 — The engine owns its randomness · shipped (`5d4091d`)

**What it does.** `game/rng.lua` is the engine's generator. Nothing below the
presentation line calls `math.random`; a test greps for it.

**Which generator, and why that one.** Lehmer/MINSTD, `x = 48271 * x mod
(2^31-1)` — what C++ standardised as `std::minstd_rand`, chosen so the test can
assert **the standard's own published vector** (seed 1, 10000 draws →
399268537) rather than assert that the generator agrees with itself. Integer
only; the widest intermediate is exact in both a double and a 64-bit integer, so
5.1, LuaJIT and 5.4 produce one sequence with no bit operations.

**Why it existed.** `math.random` is Tausworthe in LuaJIT and xoshiro256\*\* in
PUC 5.4. One seed meant a different first card on each, so the golden traces
could only ever run under one interpreter — a hole in the regression net that
was silently disabling the suite's strongest test.

**State.** One integer. That is what lets it join `flow.checkpoint` in two lines
(undo across a shuffle replays *that* shuffle) and ride in the network snapshot
for free.

**Seeding.** Precedence is explicit argument > `flow.default_seed` (CLI/env) >
the game file's `"seed"`. **With none of those it does not reseed at all** — the
generator carries on from wherever the process seeded it. Reseeding from the
clock here instead made the whole test suite clock-dependent, because
`tests/run.lua` seeds once at the top and relies on that governing unseeded
loads. Entry points (`main.lua`, `play.lua`, both suites) each seed once.

**`fx.lua` keeps `math.random` on purpose.** Particle jitter is presentation,
must not be reproducible, and must not consume draws the rules depend on.

---

# 03 — Procedural placeholder art · shipped (`2d0f194`, `0f5350f`)

**What it does.** A card's `asset` may be a shape spec instead of a filename —
`"circle:teal"`, `"polygon:5:green"`, `"star:5:amber"`, `"checker:8:black:white"`
— drawn by `game/art.lua`. A card tagged `generate_art` gets one derived from
its key without naming an asset, so a brand-new file has visual differentiation
from its first save. That was a game-wide `placeholder_art` boolean until it
became a tag: a field could only ever be set for the whole file, which is no use
when six cards want shapes among thirty-five photographs.

**Where.** `art.lua` is above the presentation line. Its `parse` is pure and
shared with `validate.lua`, so the validator's suggestions and the renderer
cannot drift. A test asserts no module below the presentation line requires it.

**The trap, recorded because it bit twice.** Art colour is *not* game data.
A red card is not "a red card" to any rule; scopes and conditions must never
read it.

**`art.render` returns a Canvas, not an Image.** It used to finish with
`newImage(canvas:newImageData())`, which bought nothing — a Canvas is already a
drawable texture and `getDimensions` is all anyone asks of one — while costing a
full GPU readback per card (~22 MB for a game the size of Lost Cities, each one
stalling the pipeline). It also **broke the feature in Brave**: `newImageData`
is a pixel read, and pixel reads are what browser fingerprinting protection
perturbs, so generated cards came back speckled while JPEGs were perfect.

> **General rule this bought:** a readback is a fingerprinting surface, and in a
> browser that makes it a **correctness** surface. `newImageData`,
> `getImageData`, `readPixels` — avoid all of them. There are none left.

---

# 01 (part) — Lost Cities · shipped (`b606810`)

The rest of [01](01-boardgames.md) — checkers, chess, solitaire, triggers — is
still open. What Knizia's game needed and got:

- **Comparisons in either direction and against another subject**, not just a
  constant (`{"max:value@mine.red": {"at_most": 6}}`). This bent DESIGN.md's
  no-expressions rule deliberately; the bend is recorded there and is bounded —
  a comparison has three possible keys and no nesting.
- **Products in numeric slots**, because `(sum − 20) × wagers` cannot be reached
  by repeated addition.
- **`accepts` on a destination**: relational legality, asked of each candidate
  with the arriving card bound as `@target`. "A card may only go on a higher
  one" is one line.

**The file is generated.** `tools/make_lost_cities.py` is the source;
`game/games/lost_cities.json` is output. Edit the generator and re-run it —
never the JSON. Past ~20 templates this is the rule, not the exception.

---

# 02 — Multiplayer · all three stages shipped

## Stage A — hot-seat

Seats are cards (see 00). A phase declaring `"seat": "next"` rotates on entry.
`turn` starts at **0**, not 1 — zero means "nobody yet" and reads as the first
seat; starting at 1 made games begin on seat two. Flow refuses a card in an
inactive seat's zone and a card played from outside the phase's declared zone,
and clears the undo history at every handover (undoing across one would either
leak information or rewrite somebody else's decision).

**Closed.** Hidden hands shipped: a hand is visible to its seat and to nobody
else, and a seatless hand — a one-player game, a shared tray — stays visible,
which is what leaves every game written before seats existed untouched.

**The nameplate and the pass-the-device overlay are refused, deliberately.**
Hot-seat is a *testing* mode: two seats on one machine is how a two-player game
gets played through without a second person, and the real multiplayer story is
the networked path, which is built. A handover screen would be a ceremony
between two seats being driven by the same person.

Worth writing down because the code makes it look like a bug and it is not.
`zones.visible` reads `zones.active_seat()` directly and nothing pauses, so the
moment `turn` advances the incoming seat's hand appears while whoever is at the
keyboard is still sitting there. **On a network that cannot happen** — each
machine has its own active seat and only ever draws its own hand — so the leak
is confined to the mode where both hands belong to the same person anyway. If
hot-seat ever stops being for testing, this is the first thing it needs.

## Stages B and C — networked play

Four additive files. The engine's whole share of it is: `flow.forget_history`,
`declaration.provide` (a game file handed to us at runtime, checked before the
filesystem), the `net_*` words in `actions.lua` with their `actions.on_net`
hook, and three lines in `main.lua`. Delete the four files and all of that
stays behind as inert, harmless surface.

| file | role |
|---|---|
| `game/net.lua` | the protocol: snapshot, delta, hashes, transports, flow wrapping |
| `game/netpack.lua` | base64 and an LZSS compressor |
| `game/netlink.lua` | transports: loopback, folder, browser tabs, WebRTC |
| `game/netpanel.lua` | the browser's controls, as injected HTML |

### It ships state, not moves

A move is smaller, but applying one asks the far machine to re-derive the same
result. A state has nothing left to re-derive, so it cannot desync. The first
message is a whole state; every message after it is the **difference from the
state both sides last agreed on** — 273 bytes for a Lost Cities turn against
25 KB for the state it describes.

Better still, both players can start the same file at the same seed (now that
rng.lua makes a seed mean one deck everywhere) and skip the full state entirely.
The invite is then 34 characters: `RAVEL1I:lost_cities.json:4242`.

### Wire format

```
RAVEL1:<label>:<game>:<seq>:<kind><enc>:<base64>
  label  init · t<round>p<seat> · resync · hello · game
  kind   F full · D delta · R "send a full state" · H "I am here"
         Q "I do not have that game" · G the game file itself
  enc    x base64(lzss(json)) · j base64(json), when lzss found nothing
```

The header is plain text and deliberately first, so a blob pasted into a bug
report says what it is. The label is descriptive and **nothing branches on it**.
Whitespace is stripped before parsing, so a chat client that hard-wraps a long
line does no damage. The header is written from the payload and cross-checked
against it on arrival.

### Three hashes, three questions

- **`gh` — the game file.** *Are we playing the same game?* Hashed from the raw
  file bytes. A mismatch is refused at the door naming both hashes, and is the
  one refusal that does **not** trigger a resync — resending cannot fix two
  different files.
- **`prev` — the state this follows.** *Did we start from the same place?* A
  delta that does not fit is refused rather than applied to the wrong thing.
- **`post` — the state this produces.** *Did we end up in the same place?*
  Checked after applying, so divergence surfaces when it happens rather than as
  a rejected delta three turns later.

djb2, not a cryptographic hash — see the trust section below for why that is the
right call rather than a shortcut. The current state's hash is cached beside the
state; the publishing wrappers invalidate it, because they are the only things
that see every mutation (**including when offline** — skipping that left a stale
hash for whoever linked later).

**State hashing is canonical because `json.encode` sorts map keys.** That sort
is load-bearing for the protocol, not just for readable diffs, and its
comparator breaks ties by type first — `tostring` alone is not a total order,
and a tie makes 5.1 depend on insertion order and makes 5.4 raise. `"%.14g"`
was checked to agree byte-for-byte across LuaJIT and 5.4.

### Compression

LZSS, deliberately not deflate. A Lua deflate with its Huffman stage is several
hundred lines and a long time spent not trusting it; LZSS does nearly all the
work here because a game state is the same twenty key names over and over.
**about 19 KB → 4.4 KB, 4.4×, in 2 ms**, against deflate's 6.5×. Taking 68% of the
ratio for 80 portable lines is right when the alternative is a format only half
the clients can read: `love.data` has deflate *and* base64, and the headless
shim has neither. A message is compressed only if it actually came out shorter.

### Getting data out of a browser

**There is no `love.js.eval` in the 2dengine runtime this repo serves** —
`cards.lua` still assumes there is, which is why its browser asset path has
never worked. The bridge that does work is 2dengine's documented one:

- `player.js` overrides `window.open`, so `love.system.openURL("javascript:…")`
  is eval'd and its result parked in `window._output`;
- it also overrides `window.prompt`, which is what emscripten's stdin calls — so
  `io.read("*l")` returns that result.

Three constraints, all measured:

- **Inbound is quadratic.** Emscripten's tty returns stdin one byte at a time
  via `Array.shift()`. 40 KB costs **41 ms** whole and **2.2 ms** in 8 KB
  chunks. Outbound is one call; inbound is always chunked.
- **Never return `null`.** A null reply reaches Lua as end-of-file, and a closed
  stdin never reopens. Every snippet is wrapped so it always yields a string.
- **Check `love.system.getOS() == "Web"` first.** On desktop, `openURL` launches
  a real browser and `io.read` blocks on a real stdin.

Every `eval` is a fresh parse, so the hot paths are installed once as named
functions (`__rvn`, `__rvc`, `__rvs`) and called with a few characters, and
polling runs at 10 Hz rather than per frame. Idle went from ~60 bridge calls/s
to 9, and from tens of KB/s of JavaScript parsed to 0.2.

### Transports

| | |
|---|---|
| `loopback` | two ends in one process, for tests |
| `folder` | one file per side, **appended, one message per line**. Any synced folder is then a cross-machine transport. It was last-write-wins on one file until a `hello` overwrote a `send me the game` and both sides waited politely forever — **a transport may not lose messages**, whatever the protocol above it tolerates today. |
| `browser` | `BroadcastChannel`, scoped to **one browser profile**. Not across browsers, not between a private and a normal window. |
| `webrtc` | two computers, peer to peer, signalled by copy/paste |

### Peer to peer without a signalling server

WebRTC's reputation for needing a server is really a reputation for needing
*signalling*, and a chat window is signalling — so the paste box that carries
game states carries the handshake. **Offer 1328 chars, answer 960**, both inside
a single Discord message; after the second blob nothing is ever pasted again.
**No port forwarding** — that is what ICE is for.

- STUN is a third party. `netlink.stun` is a list you can change or empty (empty
  works on a LAN).
- **Symmetric NAT defeats hole-punching** (common on mobile and some ISPs). The
  usual answer is a TURN relay, which is the server this project declined. The
  fallback is copy/paste, which never fails.
- **The offer blob contains your IP addresses.** That is what it is for. It
  looks like opaque base64 and gives no hint; send it in a DM.
- Outbound is **queued in JS and flushed on `onopen`**. `setRemoteDescription`
  returns long before ICE finishes, so the host's opening state was going into a
  channel still in state `connecting` and being dropped — both sides then looked
  connected while quietly disagreeing.

### The invite carries the game

`Q` asks for a game, `G` carries it. A receiver that refuses a state because it
lacks that file asks once and gets the rules, then the position — so somebody
who has never seen the file can be dealt into it. `declaration.provide` is the
whole engine-side cost, checked *before* the filesystem so a shared game beats a
stale local copy of the same name. Not folded into the invite, which has to stay
pasteable: Lost Cities is 53 KB of JSON, 12.5 KB compressed, against 1.3 KB for
the handshake.

**What does not travel** is anything the file only points at. A game naming
local image files renders as text on the far side; `placeholder_art` looks
identical, because it is generated.

### Networking is something a card does

The engine knows the **words**; `net.lua` supplies the **meaning**.
`actions.lua` declares `net_invite`, `net_join`, `net_panel`, `net_seat` and
`net_offline` in the same `SPEC` table as `draw_from`, each a no-op that calls
`actions.on_net` if anything assigned it. `net.lua` assigns it on require.
**Delete `net.lua` and the words survive as silent no-ops** — better for a build
without networking than a validator warning.

None of them change game state; they ask the interface to show something, the
shape `actions.on_effect` already had. That is why they are safe to play before
anything is connected, which is exactly when you need them.

So the panel is opened by a card and by nothing else. A solitaire game shows no
networking widget and no code asks whether it should. `menu.json` carries *Join
a friend* (`net_join`); Lost Cities opens by asking **Both sides, here** /
**With a friend, online**, the second being `["destroy:mode", "net_seat:north",
"net_invite"]`.

**What could not move into cards:** the paste box. A 1.3 KB blob has to land
somewhere, LÖVE has no text input here, and SDL's emscripten clipboard is an
internal buffer rather than the browser's.

**How that overlay is built, because the obvious route is wrong.** The built-in
`reveal` pair is page-mode **at the zone**, so every card fills the panel and two
choices stack; overriding half of it is refused by the validator, and overriding
both puts `reveal` into the phase rotation. Lost Cities declares its own pair: a
**hidden `mode` zone** (no board space, ignored by the overlap check, still drawn
by an overlay phase over the dim) and a `mode` phase carrying `page: true`.
**The page flag on the phase makes each card's own `on_pick` run; the page tag
on the zone is only layout.** The phase sits last in the list, where nothing
falls through to it.

### Out of sync, and saying so

`net.desync` is set when a delta does not fit or a message lands somewhere the
sender did not, and stays set until a whole state clears it. Both interfaces
show it and offer `net.request_resync`. The automatic request is not enough on
its own: a lost message means the request was lost too.

`net.last_heard` exists because **attaching a transport always succeeds** — a
broadcast channel with nobody on it is a perfectly healthy channel. Clicking
"Link tabs" in two different browsers reported success on both sides and
connected nothing. After four seconds of silence the panel says so. And the peer
that links *second* is heard but hears nothing back, which is why first contact
is answered with a **hello** (kind `H`), exactly once — deliberately a hello and
not a state, because we may have just *refused* what they sent, and answering
that by overwriting them turns a clear error into a silent one.

### Trust: cheating is not handled

Two separate things are missing, and neither is a hole to be plugged.

1. **Both players hold the entire state**, hidden zones included. A hand is
   hidden by the renderer, not by the protocol.
2. **A client applies whatever state arrives.** The hashes check that a message
   *follows* the state we agreed on; they never check that the new state is
   *reachable* from it by a legal move. A modified client can hand you any
   position, and the fingerprints will agree afterwards because both sides then
   hold the same lie.

The hashes exist to catch **accidents**. A fix needs an authoritative referee
that takes **moves** rather than states, validates each, owns the result, and
sends each player only their part. Three of those four are new work. The piece
that carries over is real: `flow` already re-derives legality for local input
(ARCHITECTURE invariant 2) — a referee would run that same check on somebody
else's move.

### Debugging a packet

`luajit packet.lua '<blob>'` prints the header, sizes, compression ratio, the
three hashes with a verdict on your copy of the game file, and — for a delta —
every changed entity resolved to a name:

```
    #44   card white_2 (White 2)    slot_id=149  zone_id=147
    #62   zone hand@north           cards=[7 ids]
```

Names come from loading the game the packet names, which works because entity
IDs are handed out in file order and mean the same thing on every client
whatever the seed. It also decodes invites and WebRTC blobs, and prints the IP
addresses an offer contains.

---

# 01 (part) — Stacks, destinations and mixins · shipped (`7b524de`)

Lost Cities could be discarded to exactly once per colour, and the three rules
that fixed it are all engine-wide.

- **A stack is reached from the top.** `flow` and `targeting` now say what the
  renderer always did: the top card of a deck or pile is the playable,
  activatable and targetable one, and nothing under it is. Before this a script,
  the debug API or a network peer could name any card in a pile.
- **A place to put a card is a zone**, not a marker card standing in one.
  `"target": {"type": "zone"}` points at the expedition or the discard, and
  `accepts` sits on the zone as naturally as on a card. Ten marker cards
  disappeared, and with them the failure mode where a destination stops working
  because something covered it up.
- **Tags are mixins, and a zone may grant them.** A tag def carries card
  behaviour; a zone hands its tags to its contents with `applies`. "You may take
  the top card of a discard pile" is the pile saying what lying on it means,
  with no card in the game knowing piles exist. The zone answers first, the card
  answers where the zone is silent, and there is deliberately **no card-wins
  precedence** — an overlap is an authoring conflict the validator reports.

---

# 08 (core) — Pieces that move · shipped (`5c1875e`)

**Chess plays**, castling included, and the engine never learns what a bishop
is. Movement is six `patterns` entries shared by both colours: a pattern is a
list of `[dx, dy]` pairs read as *directions* applied up to `range` times, so
blocking, leaping and limited range are one loop bound and one break rather than
three rules. `geometry.lua` holds the arithmetic, pure and headless.

Five notations were drafted against the same five pieces before this one won.
**[08](08-grid-movement-notation.md) is still the live document** — it carries
the comparison, the build order with each step's status, and what each step
taught. Read it rather than duplicating it here. In brief, also shipped:
absolute patterns and `place:` (castling's fixed destinations), patterns as
scopes (`count:piece@adjacent`), ownership by seat tag (`tags.owner_of`, so one
shared board holds pieces that are not shared), `fill` on slot targets, capture
via `place_in_slot`'s `on_occupied`, and zone art — `asset`, `checker`, `paint`.

Left: the scope anchor word, check and checkmate, promotion, en passant.

Two rules with reach beyond chess came out of it: **a stat nobody carries is
absent, not zero** (`equals: 0` was true of a rook captured twenty moves ago),
and **you are not among the things you own** — `owner_of` and `seat_of` are
different questions, and a party game with four `player` cards needs all four
clickable on one turn.

---

# 05 (part) — Named assets, and pictures in the browser · shipped (`ff55754`)

A picture may be **named once in a top-level `assets` table** and referenced by
key: `"asset": "archmage_tower"`. A name is anything with no source in it — no
extension, no scheme, no shape colon — so it can never be confused with the
inline forms, and it is the only place a picture carries options. There is one
option, `max` (longest edge, 1–4092); anything inline gets 1024. The name is
also the cache key, so twenty cards drawn from one picture are one download and
one texture.

**Remote images work in the browser build.** This is load-bearing, not a
convenience: a game file must be able to name pictures somebody else hosts, or
sharing a game means sending binaries. The browser fetches the URL itself and
hands the bytes to Lua, and the page decodes first — so a remote WebP, AVIF or
progressive JPEG works even though LÖVE reads only what stb_image reads. Repeat
visits are free with no code: it is an ordinary `fetch`, so a host sending
`Cache-Control` is answered from the browser's own disk cache.

**Four failures stacked on top of each other here, all silent**, and they are
the reason this took a day rather than an hour:

| What broke | Why |
|---|---|
| Every web asset crashed on its first frame | `cond and browser(...) or desktop(...)` **ran both**: the browser fetch's unfinished answers are falsy — nil in flight, false on failure — so `or` ran the desktop path, which asked for a thread channel that did not exist. A platform choice is `if`/`else`, never `and`/`or`. |
| `NetworkError`, on every public host | `credentials: "include"` asks for cookies, and the fetch spec **refuses a credentialed response whose `Access-Control-Allow-Origin` is `*`** — which is what every image host answers with. Nothing in the error said the request had been the wrong shape. |
| The tab hung on anything over ~1 MB | love.js hands JS values back to Lua **one byte at a time** through `io.read`, and Emscripten's default `stdin` `Array.shift()`s per byte. Quadratic: fine for a clipboard line, billions of element moves for 3 MB of base64. `index.html` supplies the same contract with an index instead. |
| A 4K photo decoded to nothing | player.js sizes the wasm heap as `min(4 × game.love + 20 MB, deviceMemory)`, Firefox reports no `deviceMemory`, and this build has **no `ALLOW_MEMORY_GROWTH`** — 33 MB, for a single photo that is 36 MB of RGBA. `index.html` now puts a 256 MB floor under whatever player.js works out. Raise that before raising `max`. |

Plus one shim difference worth knowing: **`love.filesystem.newFileData` returns
nil under 2dengine's love.js**, where `love.data.newByteData` works. Try the
latter first, fall back to the former.

The lesson under all four: every one of these paths returned `nil` and said
nothing, because `nil` also means "still fetching". A path that can fail must
report *which step* failed — that change is what turned four days of guessing
into four readable console lines.

---

# Tooling — the inspector and the test harness · shipped (`e198dbb`, `1a03c9d`)

**Ctrl+hover shows a thing's JSON.** Point at a card, a slot or a zone with ctrl
held and `inspect.lua` prints its template, its live entity, and what the engine
*derived* — owner, and the effective tag set after the zone's `applies` and the
computed tags are folded in. That last block is the point: the derived view
answers "why is this card behaving like that" without a print statement.
Ctrl+C copies the panel, the wheel scrolls it, and clicks are swallowed while
ctrl is down so inspecting never plays a card.

**A test is a function in a folder.** `tests/integration/*.lua` export `test*()`
functions; `tests/harness.lua` loads every file in the directory, sorts, and runs
each under `xpcall`, so one blowing up does not take the suite with it.
`tests/run.lua` runs them all, or `luajit tests/run.lua <name>` runs one.
`tests/run.lua` lost 680 lines to this and the assertion count did not move —
which was the point of counting them.

This also has a practical cause: Lua allows **200 locals per function**, and
`run.lua` hit the ceiling. A `do ... end` block hands them back, and a file per
subject avoids the question.

---

# The syntax pass — shipped (`60c4654` … `790b549`)

The format had grown synonyms, and [10](10-schema-document.md) measured which
ones actually hurt before anything was changed. What a game file says now:

**A card is what it is, then the moments it has.** `key`, `text`, `tooltip`,
`story`, `asset`, `tags`, `owns`, `card_stats`, `outcome` — then `play`,
`activate`, `challenge`, `receive`, `turn`, `start`, each holding the vocabulary
of that moment. `cost`/`activate_cost`, `target`/`activate_target`,
`on_play`/`on_activate` were three pairs spelled as a naming convention nothing
documented; position says it now. **One word, `needs`, is a gate everywhere**,
and the block says what it gates.

**How a thing looks is a style it tags.** `color`, `fit`, `ratio`, `checker`,
`paint` and three engine-known tags all became properties of a named `styles`
entry, for zones as well as cards. Chess's whole board is one word. `color:
false` replaced `transparent_background` — a field and a tag deciding the same
thing. And a style that is *also* a computed tag makes a look follow the
numbers, with nothing in the drawing code that knows what `wounded` means.

**Who is playing is declared.** A seat used to be any card carrying the `player`
tag, so "is this a two-player game" was a scan and a game that wanted an invite
card had to know its own seat count without ever stating it. `players` says it,
one entry per seat in seat order, and a seat is still a card — it has stats, it
can be targeted and destroyed, and castle's throne room is a building that
happens to be the player. An entry naming no card gets the invisible stat bag a
solitaire game always had. The engine stamps the `player` tag onto the cards the
section names, so all 27 `@mine.player` scopes are untouched.

Offering an invite stays a *card's* decision — invariant 7, a question about
content answered by content — but the fact is now readable, so the validator
warns when a one-seat game deals an invite that could never hand over.

**Setup is the manual, not the cards.** `start` was the last block, and it went
the same way `pick` did: the `cards` section is what comes out of the box, and
`setup.place` is the page that arranges it — which card, which zone, which cell,
in order. A card may be placed twice, which is what lets a template be a *kind*
rather than a piece on a square ([14](14-kinds-and-placements.md)). The engine
places its own first and a game never writes those down: the `system` card, an
injected `player`, and any seat that named no place, because a seat has to exist
before it can act.

**Two blocks turned out not to be moments**, and the difference is worth
keeping. `challenge` is a named *test* any action list reaches with
`resolve_challenge`, which is why kingdom's crises can be asked from `play` and
`activate` both. And `pick` was simply `play`: an overlay is a pending choice,
a choice is resolved by playing something, and the phase's `zone` already bounds
what may be played. Deleting `flow.pick` also deleted the `page`/non-page split
that decided *whose* actions ran — a footgun where a card's own actions were
silently ignored.

## Rules that came out of it

- **A quality is a tag; a value is a field.** `no_undo` and
  `invisible_slot_outlines` are words a thing either carries or doesn't. A ratio
  is a number and there are infinitely many, so it is a field — and then a style
  property, because presentation belongs in one named place.
- **A name may repeat unless a *scope* has to resolve it.** Keys are unique
  within their kind; the scope namespace (patterns, then zones, then tags) may
  not collide. Everything else is free, and two repeats are load-bearing: a
  chess piece is a card key *and* a tag so another piece's condition can name
  it, and a style sharing a computed tag's name is the dynamic-look mechanism.
- **No old syntax, and no migration aids.** Every game is in this repository, so
  the flat name is an *error* once its moment has moved — otherwise it keeps
  working by accident, which is the alias being removed.
- **The document becomes engine data at `declaration.parse`, and nowhere else.**
  One table maps authored blocks to the flat names the engine already read, so
  all 38 read sites were untouched by a change to what an author writes.

## What made it safe

**The golden traces.** `castle.log` and `kingdom.log` cover the two densest
games, and every step had to leave them byte-identical. They earned it once:
folding `pick` into `play` made castle's draft charge a building's *build cost*
to choose it, and the transcript diverged at line 51 with a stray
`Throne Room -1 gold`. Every unit test passed.

**`SCHEMA.json` and its two-way test**, which fails the moment the document and
the engine disagree about a single field — exactly what a rename this wide gets
wrong.

**And, added at the end of it, `tests/integration/docs.lua`**: AUTHORING's two
walkthroughs are parsed out of the markdown and validated. Both had quietly
stopped working — one pushed a phase it never declared and put its hand under
the undo button, the other still spoke a vocabulary the engine had dropped —
because a document cannot fail a test until somebody makes it able to.

Two traps worth knowing, because both were hit: **the generators emit the format
too**, and running one would have silently undone a migration; and `json.dump`
explodes every scalar array onto its own line, so `tools/jsonfmt.py` exists to
keep key order and inline what fits.

---

# 07 (part) — The text pass · shipped (`19b0788`, `89cf0be`, `b24f601`)

**A card is its picture, with its name over it.** The face used to be a
stamp-sized image above a slab of colour holding the title; the picture now
fills the card and the words float on it, light on a dark outline over a
gradient. That is where the height went — and it settles contrast by
construction rather than by palette, which matters because the *game* picks the
card colour: fixed light text over a green expedition was unreadable and no
choice of colours could have fixed it.

**A title is fitted, never cut.** Largest size that holds it on one line; then
two lines, but only where there is a space to break at; then smaller; and only
then an ellipsis. Lost Cities rendered "Score Green" as `S...`.

**A tooltip is a list of blocks**, measured then drawn: a title, prose, a
hairline, label/value rows that read down a column, and a click hint in green or
amber. It was one string built by concatenation and handed to a single `printf`
— and it never said the card's name.

## What only a screenshot would tell you

None of this was visible to the test suite, which is exactly why the suite is
green through all of it. It was done against a scratch LÖVE harness rendering
each game to a PNG between edits, and every one of these came out of looking:

- **`getWrap` splits a word it cannot fit.** "Yellow 9" comes back as `Yello` /
  `w 9` — passes a width check, reads as nonsense. Rejoining the lines and
  comparing against the original is what tells a real break from a broken word.
- **The hp badge sits bottom-left, which is where the title now is.** Throne
  Room rendered as "one Room" until the title learned to start clear of it.
- **The tooltip was showing `round`, `plays` and `turn`** — bookkeeping the
  engine keeps on whichever card happens to be the seat, reading as two more of
  the throne room's statistics.
- **Text was blurry**, and for two reasons: every position was fractional (a
  zone's rect is a fraction of the window), and the default filter is linear,
  which is right for card art and wrong for a glyph atlas rasterised at exactly
  the size it will be drawn.

**Check it at a size where the scale is not 1.** At 960×540 the scale is exactly
1 and most positions land on whole numbers anyway, so the blur fix looks like it
did nothing. 1100×620 gives 1.146.

**Harness note:** `love.graphics.captureScreenshot` is asynchronous and writes
nothing if you quit the same frame. A canvas created with `stencil = true` — the
card face stencils its art to the rounded shape — plus a synchronous
`newImageData():encode("png", name)` is what works.

---

# Being spent is a cost

`"cost": { "exhaust": 1 }` in an `activate` block is MTG's tap symbol: the
ability spends the card *being ready*, a card already spent cannot pay it, and
that is the whole of "once a round". An ability that does not charge it stays
available.

**It used to be a consequence.** Activating exhausted the card, full stop, and
`stays_ready` was the opt-out. Two reasons the cost is the right end of it:

- The round-long cooldown is **the card's rule, not the engine's**. Chess pieces
  wore `stays_ready` to say "I am not that kind of card", which is a game
  apologising for a default it never asked for. They now say nothing.
- **Once a card may carry several abilities, "activating exhausts it" has no
  answer to *which* ability did.** Only the one whose cost says so. So this is a
  prerequisite for the ability chooser, not a tidy-up beside it.

`stays_ready` is gone. 28 cards across five games gained the cost, 7 dropped the
tag, and five Lost Cities discards stopped granting it.

**The golden traces are what made this safe**: castle and kingdom hold 15 of
those 28 cards, and a migration that put the cost on the wrong card would have
moved a transcript. They did not move.

**One real bug it surfaced, in the test harness rather than the engine.**
`legal_moves` asked `flow.can_afford(def.activate_cost)` with no context — "can
this be paid for?" without saying by whom. Nothing depended on the asker until a
cost was paid *with the card*, and then every card looked unaffordable and
castle stopped terminating. Costs are asked of somebody now.

Refused for now: `"exhaust:<tag>": n` — "tap two of your elves" — which is the
`sacrifice:<tag>` shape and will parse the same way when a game wants it.

---

# Asking a question — the `options` offer

"Choose one of these" is not a chess rule, so it is not chess's to implement.
The engine has an **offer**: a zone of type `options`, an overlay phase to show
it, and one action.

```json
"pass": ["options:to_queen,to_rook,to_bishop,to_knight"]
```

A card is dealt per choice, the overlay opens, and clicking one plays it.
Everything left is cleared — an offer outlives its question by nothing, which
also keeps the board free of invisible cards.

**The source may be a zone instead of a list**, and then the choices are its
cards: `"options:upgrades"` for a set that varies with the game.

## The offer remembers who asked, and that is the whole trick

The first promotion had the pawn set a `promotion` stat, declared a computed tag
`promoting` to read it back, and wrote `become:mine.promoting:queen`. Three
pieces of bookkeeping to answer "which pawn?".

The offer knows. `options` records the asking card on the zone, and flow plays
the chosen card **with that card as its target**:

```json
{ "key": "to_queen", "play": { "action": ["transform:target:queen", "next_phase"] } }
```

The stat and the computed tag are gone from chess. The choices also inherit the
asker's **owner**, so the per-player asset lookup draws them in the right colour
with nothing said.

Kept on the *zone entity* rather than in a module local, because entities are
what `snapshot`/`restore` copy — so it survives undo with everything else.

## `become` is `transform`

Renamed on the way past. It was always the general verb — a crowned checker, a
levelled unit, a tile turned face up — and `transform` is what that is called.

## An `options` zone is hidden by its type

Not by a tag it has to remember. **An offer that is not open is not on the
board**, and this is exactly the rule whose absence cost a day: chess's first
promotion offer was a `hidden` zone holding four cards permanently, parked over
the middle of the board, and every click that landed in its rectangle hit an
invisible card. A type cannot be forgotten, and a zone that only holds cards
while it is open has nothing to swallow them with.

## It is `reveal` with a choice

The pattern was already there: `reveal` injects a hidden zone and an overlay
phase under one key, fills it, and pushes. `options` is the same pair with more
than one card and an answer that comes back. Both are overridable by declaring
a zone with the key, so a game that wants the offer drawn elsewhere says so.

---

# A card that stops being the card it was

Pawn promotion, and the engine learned one verb for it.

**The detection was already built and a comment said so.** `zones.lua:237`
stamps `rank` from a piece's *owner's* own side on every placement, so a pawn's
home is rank 2 whichever colour it is — and the comment there had already worked
out the consequence: *"conditions and computed tags then read
`{ "stat": "rank", "at_least": 8 }` and needs nothing new at all."*

**The conditional was already built too.** `resolve_challenge` runs one of two
action lists off the acting card's `challenge` block, so the pawn asks the
question inside its own move:

```json
"activate": { "moves": [...], "action": ["move_to:target:taken",
              "gain_stat:moves_made@self:1", "resolve_challenge"] },
"challenge": { "needs": { "rank@self": { "equals": 8 } },
               "pass":  ["set_stat:promotion@self:1", "push_phase:promote"],
               "fail":  ["next_phase"] }
```

That makes promotion **mandatory and part of the move**, which is what it is. A
granted ability would have made it a click the player could decline, leaving a
pawn sitting on the eighth rank.

## The one new verb

`transform:<scope>:<card>` — replace each card in scope with a new one of that key,
standing on the same square, in the same zone, belonging to the same player.
Everything else is the new card's own, because it is a different card.

Deliberately general rather than promotion-shaped: a crowned checker, a levelled
unit and a tile turned face up are the same sentence. It collects its victims
before changing any of them (the scope is recomputed from the board, so
replacing the first would move the ground under the rest) and destroys before
creating, since `place_in_slot` refuses an occupied square.

## The choice is Lost Cities' opening question in different clothes

A `per_seat` hidden zone and an `overlay` phase, four cards in it. **They carry
no owner** — they sit in *this* seat's copy of the zone, and that is what picks
the light sprite over the dark one, through the same per-seat asset lookup the
pieces use. The other seat's copy is unplayable for free, because flow already
refuses a card in another seat's zone.

## Two things the drafting got wrong, both the engine's fault for being right

- **`flow.play_card` already pops an overlay** before the chosen card's action
  runs — it says so in a comment, so that a chained reveal lands on top rather
  than burying what it came from. A choice card that pops again takes the phase
  *underneath* with it, and the stack empties. Symptom: the phase after
  promoting is `nil`.
- **A placement into a `per_seat` zone goes into every copy.** Giving the four
  choices an `owner` did not send them to that seat's zone; it put eight cards
  in each. Dropping the owner entirely was both the fix and the better design.

## And one real bug, found by drafting rather than by playing

`resolve_challenge` evaluated its condition with **no context**, so `@self` and
`@target` named nothing inside a challenge — a gate reading false whatever the
board said. Five shipped games use challenges and none noticed, because every
one asks a scope-free question: *do I hold the torch*, *is there food*, *is the
wall strong enough*. Fixed by passing `ctx`, which changed no shipped behaviour
and left the golden traces where they were.

---

# Six cards, thirty-two pieces

Chess was 39 cards and 704 lines, written by a generator because no person would
maintain thirty-two templates by hand. It is now **13 cards and 279 lines, and
the generator is deleted.** Six of the cards are the pieces.

The 32 templates were doing three jobs at once — a kind, a placement and a
presentation — and each of the three moved to where it belongs.

**Ownership is placement state.** It used to be a tag the *template* wore
(`"tags": ["white"]`) plus an `owns` field on the seat saying which tag was
whose. That forced one template per owner: a `white` rook and a `black` rook
that were byte-identical apart from a sprite. Whose a piece is gets decided when
it is put on the board, so that is where it is written:

```json
{ "card": "rook", "owner": "player_white", "zone": "board", "at": ["a1", "h1"] }
```

It is an ordinary stat, so it snapshots for free, reads through the condition
vocabulary that already existed, and `owner_of` is three lines instead of a
loop over seats. The `white`/`black` tags and `seat_owns` are gone, which also
closes the last name collision [13](13-one-name-one-thing.md) had to work around.

**Squares have names.** `"at": "e1"` — a column letter and a rank counted from
the near edge — replaces `"slot": 61`. A list is that many cards, so the eight
pawns are one line. This is most of why the file can be read: the placement list
is now the diagram in a rulebook rather than a table of cell indices. It is not
chess-only; castle's throne room is at `"c3"`.

**A named asset may carry one picture per player.**

```json
"assets": { "rook": { "src": ["Chess_rlt60.png", "Chess_rdt60.png"] } }
```

## Why this is *not* a dynamic style, though [14](14-kinds-and-placements.md) said it would be

Worth keeping, because the plan was specific and wrong. It said the presentation
half was a style keyed on the owner, choosing the light or dark sprite.

A dynamic style fires on a **computed tag**, and a computed tag reads *one of the
card's own stats* and compares it to a number. It can say "is black". It cannot
say **"is a rook and is black"** — and that is the question, because six kinds
times two owners is twelve sprites where an owner-keyed style offers two. Getting
around it by packing both facts into one number is the boolean-field mistake in a
different hat.

So the picture varies where pictures are declared, not where looks are claimed.
That also kept `asset` out of `styles`, and it generalises to every game with
coloured pieces — checkers, go, backgammon.

## Castling needed no new machinery, and the reason is a nice one

Its gates named pieces (`moves_made@w_rook_h`) and so did its actions
(`place:w_king_e:3:8`), and with six kinds there are no piece names left. Both
became references to **squares**, via absolute patterns:

```json
"needs":  { "count:rook@w_rook_h_home": { "equals": 1 },
            "moves_made@w_rook_h_home": { "equals": 0 } },
"action": ["gain_stat:moves_made@w_king_home:1",
           "place:w_king_home:7:8", "place:w_rook_h_home:6:8", "next_phase"]
```

`place` was **already** taking a scope rather than a card key, and a pattern
scope already yielded *the occupants of those squares* — so the action came free
with the condition. It is also more correct than the old form, which would have
accepted a different rook that wandered onto h1 after a promotion.

One ordering trap: count the move **before** anything moves, or the square being
named is the one the king has just walked off.

## The test was the proof, and it caught the bug

Chess has no golden trace, so `tests/run.lua`'s scripted opening is the whole
guarantee. It addressed pieces by template key, which cannot survive eight cards
keyed `pawn`, so it now addresses them **by square** — which is both the only
thing that works and how chess is actually written:

```lua
check("1. e4 — and the turn passes", move("e2", "e4") and zones.active_seat() == "player_black")
check("2. exd5 — a capture", move("e4", "d5") and at("d5") == "white pawn")
```

**It earned its keep on the first run.** The generated castling actions passed
the algebraic rank where the grid row was wanted, so white castled onto black's
back rank — the king landed on g8. The file validated clean, the board rendered,
and castling "worked". Nothing else in the suite would have noticed.

---

# A stack you can read — the `fan` style

**The fault:** a Lost Cities expedition was a `grid [1, 12]` in a zone about a
finger tall. Twelve cells, eight pixels each, so a played card drew as a
horizontal line — five cards in a colour were five hairlines with no number, no
colour and nothing to read. Every test passed the whole time.

**The fix is one style property.** `"fan": "down"` on a pile draws the whole
stack instead of just its top card: each card over the one before, leaving a
strip of it showing, and the strip is what the arithmetic protects. The fan
opens to a comfortable spread, closes to a minimum readable strip as cards pile
up, and only then do the cards themselves shrink.

```json
"styles": { "stacked": { "fit": "fill", "fan": "down" } },
"zones":  [{ "key": "red", "type": "pile", "label": "Red", "tags": ["stacked", "per_seat"] }]
```

**The card's name moves to the bottom of the visible strip**, not the bottom of
the card. Without that the whole layout is pointless: the title band sits at a
card's foot, which is exactly the part the next card covers, so a fan of ten
would have shown one name. `draw_card_face` takes the uncovered rect and lays
the words out inside it — the same code, given a smaller box.

## It reverses a refusal, and the reason matters

[06](06-schema-and-types.md) gap 1 said: *"Refuse: letting a tag change the
layout algorithm … the moment a tag moves cards around, every renderer question
becomes a search through a tag set."* The danger was real; the mechanism named
in it is what expired. **Styles removed the search** — a zone's tags resolve into
one flat map at load, so `z.style.fan` is a single table lookup, exactly what
`z.zone_type` costs and asked in the same place.

What survives is the distinction: **`type` says what kind of container a zone
is; a style says how it is drawn.** A fan is drawing. The cards are one ordered
list in one zone either way — a pile is a pile whether or not you spread it out.
`fit` was already the precedent and had been all along: it decides where inside
a *cell* a card lands, which is the same kind of decision about one cell instead
of a run.

**The line is enforced where the two would contradict each other.** A `grid`
wearing a fanning style is a validation error: a grid places by slot and a fan
by order, both answer *where does this card go*, and a renderer taking whichever
branch it reached first is the unpredictability the refusal was guarding
against. One error message keeps what the whole refusal was buying.

## Three things that had to move with it

- **`sync_places` collapses a stack to one card**, because only a pile's top
  card is ever drawn or clicked. Miss this and the fan draws perfectly and
  answers the mouse from wherever its cards used to be. Same in `card_at`, where
  the last match must win so a click in the overlap lands on the card actually
  showing there.
- **A fanned zone needs room along its axis.** The layout divides what it is
  given; a dozen cards fanned down a short zone is the original fault wearing a
  new hat. Lost Cities was relaid out around this — the hands and the discard
  row are sized by what they hold (one row of eight, one card), and the height
  left over goes to the expeditions, the only band whose contents grow.
- **The scoring tray moved into the right-hand column and fans too.** Eleven
  cards laid side by side there would be 14px wide, narrower than the words on
  them; eleven strips down it are full width and readable. It also empties the
  bottom edge, where the undo button and event log are drawn over everything.

## Two things it made simpler

**The capacity question disappeared.** As a `[1, 12]` grid an expedition was one
slot short of a full colour, and a full board refuses arrivals *silently* — the
last card of a completed expedition stayed in hand with the turn already spent
on it. A pile takes what it is given.

**The empty-zone rule found its second customer.** A zone with no cards and no
label draws nothing, so the tally tray is invisible for the whole game until it
is dealt into, which is what let it take a whole column without costing the
board anything.

## Testing something that only draws

The arithmetic decides where cards go and paints nothing of its own, so it is
checked in `render_smoke` by measuring `place` after a real frame: every card
gets its own rect, inside the zone, ordered along the fan, one size, with a
strip tall enough to letter. **Both perturbations were run** — a 2px strip fails
the strip assertion, removing `fan` from the game file fails the every-card-has-
a-place assertion — because a layout test that passes on a broken layout is the
only kind worth suspecting.

---

# Bugs found on the way, and what they bought

Recorded because each was invisible to a green test suite, and the fix in each
case was a *check*, not just a patch.

| Bug | Now caught by |
|---|---|
| A card shorter than its text band drew a **negative scissor**, crashing Lost Cities on its first browser frame. Latent until placeholder art made every card have an image. | `render_smoke`'s `setScissor` **asserts** instead of no-oping, and every shipped game gets a draw pass. |
| `truncate` cut **UTF-8 mid-character**: it removed a byte then walked back over continuation bytes (0x80–0xBF), but a lead byte is 0xC2 or higher, so it stopped one short. LÖVE answers invalid UTF-8 by drawing nothing *and abandoning the rest of the zone* — one card titled `Lost Cities · online` deleted itself and every card after it. | `render_smoke`'s `printf` stub **validates UTF-8**, and long non-ASCII titles are drawn. |
| Lost Cities' `tally` zone lay across both players' **hands**. A zone paints its background whether or not it holds anything. | `validate.lua` reports any two visible zones overlapping. |
| A `local function` called **above its declaration** — Lua resolves it as a nil global and fails at runtime; the whole browser panel silently stopped updating. | `tests/run.lua` greps every module for the pattern. |
| The dev container **packed `game.love` once** and never again: `exec nginx` orphaned the watcher, and `set -eu` would have killed it anyway on one transient `stat` failure. | nginx runs beside the watcher; the watcher tolerates its own failures. |
| A **hidden zone swallowed clicks.** `zone_at` had always refused to return one, but the card and slot hit tests did not — and a card keeps its place whether or not anyone can see it. Chess's promotion offer lies over the middle of the board, so a pawn could step to e3 and never to e4, and the targeting session that left open ate every click after it. Lost Cities dodged it for a year by destroying its offer's cards when one is chosen; chess keeps its four all game. | Both tests moved into `zones` beside `zone_at`, where the three have to agree, and honour `hidden` — with the open overlay as the one exception, mirroring what the renderer draws. Tested in `layout.lua`. |
| The dev container **packed a game with no games in it.** A bind mount that has gone stale reads as an *empty directory*, never as an error — and an empty directory has a perfectly good fingerprint, so the watcher saw a change, packed almost nothing, and replaced a working build. The browser met it as `Cannot read game file: menu.json` three layers from the cause, served with a 200. Desktop was fine throughout, which is what made it puzzling. | `pack_game` refuses to overwrite a build unless `main.lua` **and** `games/menu.json` are both there, and says to recreate the container. Fixed by `docker compose up -d --force-recreate`. |
| The golden traces ran **only under LuaJIT**. | rng.lua; both interpreters now produce identical transcripts, and the skip is deleted. |
| A platform choice written `browser(...) or desktop(...)` **ran both branches**, because "still fetching" is falsy. Every remote picture crashed the browser build on its first frame. | `tests/run.lua` stubs a browser and makes the desktop path **fatal** when it is reached, and the other way round. |
| **Capture was unclickable** in chess. Hit-testing returns the topmost *card*; a slot-typed spec's eligible list holds *slots*; the two never met — and every test called `targeting.candidates` directly, so the seam was never crossed. | `targeting.aim` — "pointing at a piece means pointing at its square" — lives in `targeting`, where a test can reach it, not in `main`. |
| **Hovering a castling card crashed the game.** `cards.cost_text` renders `needs` and `accepts` too, and only a cost is always a plain number; the comparison form had been legal since Lost Cities but no card had ever carried one *and* been hovered. | `tests/run.lua` asks `cost_text` for every comparison form, not just the plain number. The gap it exposes — the suite covers the rules layer thoroughly and the presentation layer barely — is still open. |

**Invariants the engine gained:** randomness belongs to the engine (ARCHITECTURE
invariant 8); layouts may not overlap; and — from the Brave bug — a readback is a
correctness surface in a browser.
