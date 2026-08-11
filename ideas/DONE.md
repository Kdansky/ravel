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
Cities), [04](04-simulation-games.md) (Cultist Simulator), [09](09-composition.md)
(one game out of several files) and [14](14-kinds-and-placements.md) (a template
is a kind, not a piece on a square).

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
— drawn by `game/art.lua`. `"placeholder_art": true` at the top of a game file
gives every card without art a generated one derived from its key, so a
brand-new file has visual differentiation from its first save.

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

**Still open:** hidden hands, a nameplate, a pass-the-device overlay. All
presentation; the rules are done.

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
| The golden traces ran **only under LuaJIT**. | rng.lua; both interpreters now produce identical transcripts, and the skip is deleted. |
| A platform choice written `browser(...) or desktop(...)` **ran both branches**, because "still fetching" is falsy. Every remote picture crashed the browser build on its first frame. | `tests/run.lua` stubs a browser and makes the desktop path **fatal** when it is reached, and the other way round. |
| **Capture was unclickable** in chess. Hit-testing returns the topmost *card*; a slot-typed spec's eligible list holds *slots*; the two never met — and every test called `targeting.candidates` directly, so the seam was never crossed. | `targeting.aim` — "pointing at a piece means pointing at its square" — lives in `targeting`, where a test can reach it, not in `main`. |
| **Hovering a castling card crashed the game.** `cards.cost_text` renders `needs` and `accepts` too, and only a cost is always a plain number; the comparison form had been legal since Lost Cities but no card had ever carried one *and* been hovered. | `tests/run.lua` asks `cost_text` for every comparison form, not just the plain number. The gap it exposes — the suite covers the rules layer thoroughly and the presentation layer barely — is still open. |

**Invariants the engine gained:** randomness belongs to the engine (ARCHITECTURE
invariant 8); layouts may not overlap; and — from the Brave bug — a readback is a
correctness surface in a browser.
