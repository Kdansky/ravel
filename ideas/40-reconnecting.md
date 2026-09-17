# 40 — Picking a dropped game back up

*From `todo.md`, 2026-09-17: "In case one side crashes, can we easily reconnect
to a running game? It would be ideal if the original connection string would
still work, and the reconnecting client could ask for a current state, but I'm
willing to solve this otherwise."*

**Not started.** Most of the machinery exists; what is missing is a route
through it that a player can find.

## What already holds

- **The state lives on the survivor.** A networked game is two full copies, so
  one side crashing loses nothing but that side's copy. `net.request_resync`
  (kind `R`) and `net.publish(true)` already move a whole state either way, and
  a peer that has no copy of the game file asks for it (`Q`, then `G`).
- **The host publishes a full state on connecting** — `netpanel.lua`'s `paste`
  handler calls `net.publish(true)` once the answer lands.

## Why the original string cannot simply work again

The internet invite is a WebRTC offer (`netlink.rtc_start`), and an SDP offer
belongs to the one `RTCPeerConnection` that made it: its ICE credentials and
DTLS fingerprint die with that connection, on both ends. [Assumption: a
reusable string would need something outside the two browsers that outlives
either — a signalling server or a TURN relay — and the transport's whole
premise is that there is none (`netlink.lua`'s ICE comment).] Linked tabs and
the folder transport have no such limit: a restarted tab rejoins the same
`BroadcastChannel` room, and a restarted folder peer re-reads its inbox — but
from line one, since `taken` starts at 0.

So the honest version is **one fresh invite, from the side that still has the
game**, and one paste.

## The traps in doing it naively

- **The wrong side hosting overwrites the survivor.** The host publishes a full
  state on connect. If the crashed side, sitting on the title screen, builds the
  invite, its menu is what lands on the survivor. [Assumption: the rule is that
  a full state arriving at a peer that is mid-game from a peer that is not is
  refused, or simpler, that reconnecting is offered only inside a game — the
  panel's `invitable()` already refuses the menu, so this may hold today and
  wants a test rather than code.]
- **Roles decide seats.** Since `843fb23` the host sits in seat one and the guest
  in seat two. If the guest survives and re-invites, it becomes host and
  `sit()` would put it in seat one. `sit()` refuses to reseat once
  `claimed_in == declaration.filename`, which protects the survivor; the
  rejoining side is the problem — it becomes guest and takes seat two, which is
  wrong if it was player one. [Assumption: the reconnect invite carries the seat
  the joiner should take, or the joiner is seated as *whichever seat the host is
  not* rather than by role.]
- **The baseline.** `net.link` keeps the old baseline on purpose; the survivor's
  first delta to a fresh peer is refused and costs a resync round trip. Harmless,
  but a reconnect should just send whole.

## What to build

[Assumption, all of it:]

1. A test in `tests/integration/net.lua` over two loopback ends: play, drop one
   (`unlink` and a fresh `flow.init` of the menu), re-link with the survivor as
   host, and assert both seats and the state hash come back — including the
   case where the survivor was the guest.
2. Seat by complement, not by role, when the state that seats you already has a
   seat claimed on the far side. Small, inside `sit()`.
3. The panel: while a game is running and the link is gone or silent
   (`net.last_heard` older than the existing four seconds), say *"lost them —
   Invite over the internet again to pick this game back up"*. No new button:
   the invite already is the reconnect.
4. [Assumption: if the crash was the browser tab, a local autosave of the last
   agreed state would let *either* side host. [24](24-save-and-load.md) refused
   saving during a networked game because two saves are a resync problem; a
   copy only ever read back by a reconnect is not a save a player loads, but it
   is a second place that decision would have to be reopened.] Ask first.
