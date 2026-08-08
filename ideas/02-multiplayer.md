# Idea 02 — More Than One Player

> *Start with hot-seating […] Ideally it would be networked […] a button that
> says "transfer to other player" which returns a (compressed) json, and a
> "receive move" button.* — `IDEAS.md`

**Status:** **A, B and C shipped.** A's HUD polish (nameplate, hidden hands,
pass-the-device) is all that remains, and it is presentation only.
**Size:** A small–medium, B small, C medium — B and C came in together

Three stages. Each one is independently shippable and each one is genuinely
useful on its own, which is unusual and worth exploiting — do not treat this as
one project.

---

## Stage A — Hot-seat — **shipped** (`4b1a96f`)

Everything below describes what was built. Its "Done when" is met: a two-seat
fixture in `tests/run.lua` runs a full turn cycle with each seat's stats
differing and neither able to play from the other's hand, and
[Lost Cities](01-boardgames.md#gap-4--scoring-functions-knizia) is playable by
two people on one keyboard.

Three things the design did not anticipate, worth knowing before stage B:

- **`turn` starts at 0**, not 1. A phase declaring `"seat": "next"` rotates on
  entry, so starting at 1 made the game begin on seat *two*. Zero means
  "nobody yet" and reads as the first seat.
- **A seat card is its own seat.** Seat cards live in the shared hidden zone,
  so the owner words could not reach them by zone. One line, and it states
  something true: the player card *is* the player.
- **Two legality holes** turned up on the way, both older than this stage:
  target *identity* was never checked (any card id could be passed as a target
  of anything), and a card could be played out of any zone. Flow now
  re-derives both.

---

**This was originally written as "90% the foundation doc". It wasn't.** That assumed
[00](00-foundation-scope.md)'s first draft, where a scope was a seat (`@me`,
`@opponent`). The shipped design made a scope a plain zone key or tag and
dropped seats entirely — a better decision, but it leaves the whole of seats
here rather than 10% of it.

What the foundation *did* give: several cards can be tagged `player`, each with
its own stats, individually addressable by tag (`gold@north`), and a `system`
card that already exists to hold a `turn` counter. What it did not give: any
notion of which seat is active, or of a zone belonging to one.

What remains:

- ~~**Seats, and zones that belong to one.**~~ Built as designed below.
- ~~**Turn rotation in phases.**~~ `"seat": "next"` rotates on entry.
- ~~**A play gate.**~~ Flow refuses a card in an inactive seat's zone, and a
  card outside the phase's declared zone.
- **Whose turn is it** — a HUD element. `render.lua`'s stat bar
  (`draw_stats`, `game/render.lua:608`) grows a player nameplate; the inactive
  player's stats render dimmed.
- **Hidden hands.** The inactive player's hand renders as backs
  (`draw_card_back`, `game/render.lua:229` already exists). This is *presentation
  only* — the state still holds everything, which is correct for hot-seat and
  emphatically not sufficient for stage C.
- **A pass-the-device screen.** No engine work: it is an overlay phase with one
  card that says "Hand the laptop to Blue" and `on_pick: ["pop_phase"]`.
  Invariant 7 pays out again.
- ~~**Undo becomes an information leak.**~~ Built: the history is cleared at
  every handover, which also makes stage B's replay model sound.

So what is left of stage A is **presentation only** — a nameplate, hidden
hands, a pass-the-device screen. The rules are done.

### Seats, and whose zone a name means

The question this stage exists to answer: if a card says `move_to:arena` and
there is an arena per player, whose arena? And how do you say "kill all
creatures", "kill all *enemy* creatures" and "kill *one* enemy creature"
without any of it becoming engine special cases?

**Ownership is one more word, in the vocabulary that already exists.** The
foundation gave subjects a scope (a zone key or a tag) and a quantifier
(`each` / `any` / `random`). Ownership is a third, orthogonal axis, and every
combination of the three is meaningful — which is the test that it belongs
alongside them rather than inside them.

#### A seat is a card, and a zone can belong to one

A seat is a card tagged `player`, **named by its own key**. Seat order is
`card_list` order, and the active seat is a `turn` stat on the injected system
card, which [00](00-foundation-scope.md) reserved for exactly this. (Give the
card an extra tag — `["player", "north_side"]` — when you also want to address
that seat's stats by name, as `score@north_side`; the owner words reach it
either way, because a seat card is its own seat.)

A zone declares that it exists once per seat:

```json
{ "key": "arena", "type": "grid", "grid": [5, 1], "per_seat": true }
```

The engine instances it at load — one `arena` entity per seat, each carrying
its seat — and `zones.find` resolves the key against the active seat. That is
the whole per-seat mechanism, and it lands in the one function every zone
reference in the engine already goes through. **A card's owner is the seat of
the zone it is in.** No per-card controller field, no new state to snapshot; a
card in a shared zone (a common deck, a market row) simply has no owner.

#### Scope expressions

The thing after `@` becomes a small expression instead of a single name:

```
[<quant>.][<owner>.]<zone-or-tag>
```

with owner one of `mine` / `enemy` / `anyone`. The same expression stands alone
as an action's zone argument, so there is one grammar in two positions:

```
hp@each.enemy.creature       every creature an opponent owns
hp@random.mine.follower      one of my followers, seeded
sum:value@mine.red           my red expedition's score
move_to:arena                a destination must be one zone, so: the active seat's
move_to:enemy.arena          put it in the opponent's arena
destroy:each.enemy.creature  a board wipe that spares your own
```

`destroy:<zone>` generalises to `destroy:<scope expression>` for free —
`destroy:hand` keeps meaning exactly what it means today, because a bare zone
key is a scope expression that names one zone.

Targeting takes the same word, so the player-chooses case needs no new syntax
either:

```json
"target": { "tags": ["creature"], "owner": "enemy", "count": 1 }
```

#### The four cases, composed

| English | Written as |
|---|---|
| Kill all creatures | `destroy:each.anyone.creature` |
| Kill all enemy creatures | `destroy:each.enemy.creature` |
| Kill one enemy creature (chosen) | `target: {tags, owner: "enemy", count: 1}` + `destroy:target` |
| Kill any one creature (random) | `destroy:random.anyone.creature` |

Nothing above is a new verb. That is the point.

#### Bare means "anyone", and it is deliberate

An unqualified scope filters by *nothing* — exactly today's meaning, so every
shipped game changes by zero bytes and castle's shared board keeps working.

The tempting alternative is bare = `mine`. Rejected for two reasons. First,
cards in shared zones have no owner, so `mine` would have to be defined as
"mine *or* unowned" — a special case, in the one place the engine cannot afford
one. Second, real card games already read this way: "destroy all creatures"
destroys yours too, and it is the *narrowing* that gets a word in the text.

In a one-player game the distinction never surfaces: with one seat, `anyone`,
`mine` and unqualified name the same cards, and `enemy` names none — so
`each.enemy.x` is simply false, by the empty-scope rule the foundation already
established. That is the sense in which this "defaults to P1".

The one asymmetry, stated out loud: a **destination** must resolve to exactly
one zone, so an unqualified per-seat zone used as a destination means the active
seat's. A set can be wide; a place to put a card cannot.

#### What this costs

- `zones.lua`: `key_map` becomes key → seat → id; `zones.find` resolves against
  the active seat. Every existing caller is unchanged.
- `predicate.lua`: `parse_scope` (the expression above) beside `parse_subject`,
  and an owner filter inside `entities_in_scope`.
- `flow.lua`: seat rotation on a phase's `"seat": "next"`, a play gate refusing
  cards in an inactive seat's zones, and clearing undo history at handover
  (below).
- `targeting.lua`: honour `spec.owner`.
- `validate.lua`: unknown owner word, `per_seat` on a zone a one-seat game
  declares, a `"seat"` phase in a game with one seat.

`actions.lua` needs one generalisation (`destroy`) and no new verbs, which is
the signal the shape is right.

---

## Stage B — Play-by-post — **shipped** (`781a624`)
## Stage C — Networked — **shipped**: two tabs (`781a624`), two computers (`WEBRTC`)

They arrived together, because the thing that made C hard turned out not to be
the network. Three files, all additive: `net.lua` (protocol), `netlink.lua`
(transports), `netpanel.lua` (the browser's controls). The engine needed one
new function — `flow.forget_history` — and `main.lua` three lines. Delete the
three files and the game is exactly what it was.

### What we shipped, against what was planned

The plan recommended **moves with a state hash appended**. We shipped **state
with a fingerprint**, and the reasoning inverted along the way:

- A move is only small if the far machine can re-derive the result. [05](05-determinism.md)
  made that possible, but "possible" is not "cannot fail" — a move-based
  protocol desyncs on any behaviour difference, and then you are debugging two
  machines through one symptom.
- A **delta between two states** is nearly as small as a move (**273 bytes** for
  a Lost Cities turn, against **25 KB** for the state it describes) and cannot
  desync, because there is nothing to re-derive. It is a diff, not a
  re-simulation.
- The fingerprint moved from "appended, checked after" to **"named by the patch,
  checked before"**. A delta says which state it was computed against; a
  receiver whose own state hashes to something else refuses it and asks for a
  full copy. Drift repairs itself in one round trip instead of being detected
  after the damage.

The other change: the plan's 25 KB first message is usually unnecessary. Both
players start the same file with the same seed — which now means the same deck
on both machines — and every message including the first is a delta. The whole
handshake is a **34-character invite**: `RAVEL1I:lost_cities.json:4242`.

### Format

```
RAVEL1:<label>:<game>:<seq>:<kind><enc>:<base64>
  label init · t<round>p<seat> · resync · hello
  kind  F full state · D delta · R "send a full state" · H "I am here"
  enc   x base64(lzss(json)) · j base64(json), when lzss found nothing
```

Game and clock are plain text in the header, so a human can read them in a chat
window and a receiver can drop a stale message without unpacking it; the header
is written from the payload and cross-checked against it on arrival, so it is
meaningful rather than decorative. Whitespace is stripped before parsing, so a
chat client that hard-wraps the line does no damage.

Both layers are hand-rolled in `netpack.lua` rather than taken from `love.data`,
and the reason is the same for each: the format has to be **identical on every
host**. A CLI player must be able to paste a string a browser player produced,
and `love.data` — which has both deflate and base64 — does not exist under the
headless shim. A format only half the clients can read is not a format.

The compressor is LZSS, deliberately not deflate. A Lua deflate with its Huffman
stage is several hundred lines and a long time spent not trusting it; LZSS is
the half that does nearly all the work here, because a game state is the same
twenty key names over and over and every one is a long match. Measured on a Lost
Cities state: **19131 → 4353 bytes, 4.4×, in 2 ms**, against deflate's 6.5× —
68% of the ratio for 80 portable lines, which is the right trade when the
alternative is two formats. A message is only compressed if it actually came out
shorter; the header says which, so a short delta with nothing to repeat is not
punished with base64's 33%.

| | before | after |
|---|---|---|
| full state (Lost Cities) | 25537 | **5881** |
| one turn (delta) | 273 | **293** |

The delta grew slightly, because it now carries the three hashes below. That is
a good trade at 7%.

### Three hashes, three questions

Every message carries all three, and they fail differently on purpose:

- **`gh` — the game file.** *Are we even playing the same game?* Two people with
  different versions of `lost_cities.json` produce states that diff perfectly
  cleanly and mean entirely different things, which is the worst kind of bug:
  silent and much later. A mismatch is refused at the door with a message naming
  both hashes, and is the one refusal that does **not** trigger a resync request,
  because no amount of resending fixes two different files.
- **`prev` — the state this message follows.** *Did we start from the same
  place?* A delta that does not fit is refused rather than applied to the wrong
  thing, and the sender is asked for a whole state. Absent only on a cold full
  state, which follows nothing.
- **`post` — the state this message produces.** *Did we end up in the same
  place?* Checked after applying, so a divergence surfaces the moment it happens
  instead of as a rejected delta several turns later. If the two clients ever
  disagree here the cause is an engine version skew rather than drift, so it is
  reported once and the protocol falls back to whole states, which always apply.

The state's hash is kept beside the state rather than recomputed: the browser
panel reads it every frame, and hashing 19 KB of JSON sixty times a second to
draw one line of text is not a trade worth making. The wrappers that publish are
also the ones that invalidate it — they are the only things that see every
mutation. (They now do so even when offline; skipping it while unlinked left a
stale hash for whoever linked later, which the tests caught.)

djb2, not a cryptographic hash. This catches two people holding different
things, not somebody constructing a collision — cheating is out of scope by
design.

### Getting data out of a browser

This was the open question, and the answer is: no server, no rebuild, and **not
by the route `cards.lua` guesses at**. There is no `love.js.eval` in the
2dengine runtime this repo serves — the `love.js` table exists but has no
`eval` — which means **`cards.lua`'s browser asset path has never worked**. It
fails silently, because every call is `pcall`-guarded and a failure looks like a
missing image. Worth fixing separately.

What does work is 2dengine's actual documented bridge, spelled out in
`player.js`:

- it overrides `window.open`, so `love.system.openURL("javascript:…")` is
  `eval`'d and the result parked in `window._output`;
- it overrides `window.prompt` to hand back `window._output`, and emscripten
  implements **stdin** by calling `window.prompt` — so `io.read("*l")` returns
  whatever the last snippet evaluated to.

That is a synchronous, repeatable, two-way bridge. `BroadcastChannel` across it
is two tabs of the same page talking with no server and no signalling, which is
exactly the scope the question asked for.

Two constraints are load-bearing, both measured rather than guessed:

- **Inbound is quadratic.** Emscripten's tty returns stdin one byte at a time
  via `Array.shift()`. A 40 KB reply costs **41 ms** as one string and **2.2 ms**
  in 8 KB chunks. So outbound is one call and inbound is always chunked.
- **Never return `null` from a snippet.** A null reply reaches Lua as
  end-of-file, and a closed stdin never reopens. Every snippet is wrapped so it
  always yields a string.

And one that is not about the bridge at all: the platform check must come
**first**. On a desktop LÖVE, `openURL` launches a real web browser and
`io.read` blocks on a real stdin, so probing for the bridge by trying it would
hang the game and open a window. Only the emscripten build reports
`love.system.getOS() == "Web"`.

### Transports

`net.lua` knows only `send`/`recv`. `netlink.lua` has:

| | |
|---|---|
| `loopback` | two ends in one process, for tests |
| `folder` | one file per side in a shared directory — two terminals, or **any folder that syncs itself between two machines** (Syncthing, Dropbox, a mounted share). A cross-machine transport with no server and no code. |
| `browser` | `BroadcastChannel` between two tabs — **of one browser profile**. Not across browsers, and not across a private window and a normal one. |
| `webrtc` | two computers, peer to peer, signalled by copy/paste |

Copy/paste needs no transport at all: `net.export` / `net.import`, and the chat
window is the wire.

### Surfaces

- **CLI:** `n host`, `n join`, `n seat`, `n send`, `n recv`, `n folder`.
- **Browser:** an HTML panel drawn over the canvas by `netpanel.lua`. The
  renderer needed no changes at all, which is the point — and a textarea you
  can paste 25 KB into is a thing the browser already has and LÖVE does not.
- **Seats** gate at `flow`, and now also at `flow.can_play`, so an opponent's
  turn *looks* like waiting: the renderer dims a card it cannot play instead of
  accepting a click and refusing it at the end.

### Verified

- Two OS processes played **101 alternating moves** of Lost Cities through a
  shared folder and finished on the same fingerprint.
- Two headless Chromium tabs link with one click each, move in **both**
  directions, carry a game load across, and refuse to move out of turn.
- 40 assertions in `tests/run.lua`, including that a delta is refused against a
  state it does not fit, across a game change, and that junk leaves the game
  untouched.

### Cheating is not handled, and that is an architecture decision

Worth stating at length, because it is the thing most likely to be assumed
solved. **Two separate things are missing, and neither is a hole to be plugged.**

1. **Both players hold the entire state**, hidden zones included. A hand is
   hidden by the renderer, not by the protocol — stage A's hidden-hand work is
   presentation and always was.
2. **A client applies whatever state arrives.** The three hashes check that a
   message *follows* the state we agreed on; they do not check that the new
   state is *reachable* from it by a legal move. A modified client can hand you
   any position it likes and this will accept it quite happily — and the
   fingerprints will agree afterwards, because by then both sides hold the same
   lie.

The hashes exist to catch **accidents**: a stale paste, two different versions
of a game file, an engine that serialises differently. They are djb2, not a
cryptographic hash, precisely because collision resistance would be pointless
armour on a door that is standing open.

**What a fix would require**, so nobody mistakes it for an afternoon: an
authoritative referee — a server, or one client designated as one — that

- receives **moves** rather than states (possible now that
  [05](05-determinism.md) makes a seed mean one sequence everywhere, and not
  before),
- **validates** each move against the rules before applying it,
- **owns** the resulting state rather than negotiating it,
- and sends each player **only the part they may see**, or hidden information
  leaks regardless of everything above.

Three of those four are new work. The engine has no notion of a state filtered
per player, and no notion of validating a move it did not originate. The one
piece that carries over is real, though: `flow` already re-derives legality for
local input rather than trusting what an interface hands it (ARCHITECTURE
invariant 2), which is exactly the check a referee would run — it would simply
run it on somebody else's move.

That is a different project, and a much larger one. Until it exists this is play
between people who trust each other. **Do not put it in front of strangers.**

### What is deliberately not built

- **Cross-machine browser play without WebRTC.** Two tabs share an origin; two
  machines do not. The honest options are ranked in the note below.
- **A relay.** Still refused, still correct to refuse.

### Cross-machine, ranked

1. **Copy/paste through whatever chat you already use.** Works today, works
   everywhere, needs nothing. A turn is 273 bytes; Discord's limit is 2000
   characters. This is the answer for "play with a friend in another city".
2. **A synced folder.** `netlink.folder` already does it. Zero further code.
3. **WebRTC, signalled by copy/paste** — **shipped**, see below.
4. **Discord or Telegram as the wire.** Both are a relay you did not have to
   run, which is not the same as no relay. Telegram's bot API allows CORS and
   would work from the browser, but the bot token would have to ship in the
   client, where anyone holding it controls the bot. Fine between friends,
   dishonest to call serverless.

### Peer to peer, over the internet — shipped

The "two browsers just talk to each other" ideal, and the thing that made it
cheap is that **the signalling channel already existed**. WebRTC's reputation
for needing a server is really a reputation for needing signalling, and a chat
window is signalling — so the paste box that carries game states carries the
handshake too, and there is no signalling server anywhere.

The whole handshake is two blobs carried by a human:

```
A clicks "Invite over the internet" → RAVEL1O:…   (1332 chars, measured)
B pastes it, gets back              → RAVEL1A:…   (960 chars, measured)
A pastes that                       → connected
```

Both fit in a single Discord message. After the second blob nothing is ever
pasted again: it is a live peer-to-peer link, and every move crosses it by
itself.

Four things can now arrive in the same box — a state, a delta, an invite, an
offer, an answer — so `net.kind_of` is the one place that decides which is
which, and the panel and the CLI route on its answer rather than each growing
an opinion about the grammar.

**No port forwarding is needed.** That was the original worry and it is simply
not a thing: ICE has each side discover its own public address and the two meet
in the middle.

Three caveats, none of them fixable here:

- **STUN is a third party.** `netlink.stun` is a list you can change or empty
  (empty works on a LAN). It carries no game data and sees an IP and a port.
- **Symmetric NAT defeats hole-punching** — common on mobile networks and some
  ISPs. The usual answer is a TURN relay, which is the server this project
  declined. There is no fix, only the fallback: copy/paste, which never fails.
- **The offer blob contains your IP addresses**, local and public. That is what
  it is *for*. Sending it to a friend in a DM is fine; pasting it into a public
  channel tells the room where you live. Worth saying out loud, because the
  blob looks like opaque base64 and gives no hint that it is not.

Verified with **two separate browser processes** — not two tabs, so no shared
origin and no broadcast channel could possibly be doing the work — connected
only by blobs carried between them: the channel opens, a game load crosses as a
full state, and moves cross in both directions.

Browser only. Desktop LÖVE has no WebRTC, and for two desktops the folder
transport or copy/paste already covers it.

### Two ways for this to look broken, both now fixed

Both were found by a person trying to use it, not by a test, and both are the
same shape: **something that fails silently looks exactly like something that
works.**

**Attaching a transport always succeeds.** A broadcast channel with nobody else
on it is a perfectly healthy broadcast channel, so clicking *Link tabs* in two
*different browsers* reported `browser:ravel — room ravel, 0 waiting` on both
sides and connected nothing, with no error, forever. Three changes: the button
now says *Link tabs (same browser)*, `net.last_heard` records whether the far
end has ever said anything, and after four seconds of silence the panel says so
and names the button that does cross browsers.

**And the peer that links second heard nothing back.** The first peer publishes
on link and the second one hears it; the second publishes and the first hears
that — but whoever linked first has no reason to speak again, so the *second*
player sat looking at silence even though the connection was fine. Hence a
fourth message kind, `H`, carrying nothing: first contact is answered with a
hello, exactly once. Deliberately a hello and not a state, because we may have
just *refused* what they sent, and answering that by overwriting them with our
own position would turn a clear error into a silent one.

### What is left

- Hidden hands and a nameplate — stage A's remaining presentation polish,
  unchanged by any of this.
- A "your opponent moved" cue louder than the log line.
- Reconnect: a tab that reloads mid-game starts at the menu and needs one
  paste, or one click of Link, to catch up.

---

## Ordering

Stage A and Stage B are **independent after the foundation** — A is scoping and
UI, B is serialization and determinism, and they barely touch the same files.
That makes them the natural first pair of parallel worktrees (see
[README](README.md)).
