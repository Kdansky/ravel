# 16 — The player at this screen

**Status:** **gap 1 shipped** (`fb3d704`); **gaps 2–4 parked** (2026-08-20) —
a name is only worth having when there is somebody to read it, which means
networked play, and the same is true of the thing that would make it *earn* its
place: see *Gap 5* · **Size:** gaps 2–4 are an afternoon
each now that the concept exists, and they all want the same missing thing.

Three notes from `todo.md`, and they turn out to be one subject: the engine
knows which seat is **up** and has no notion of who is **looking**.

> *Put the debug features (CTRL+hover) behind an explicit "enable debug" which
> is told to all players so that cheating can be seen more easily.*
>
> *It would be nice if a player could set their name somehow.*
>
> *Maybe we need a menu where settings can be adjusted, such as the player name?
> This might be tricky.*

Every one of them is a question about the person in front of *this* client:
what may they see, what are they called, and what have they turned on. The
ending screen ([07](07-presentation.md) gap 6) is a fourth reader of the same
concept — the winner gets the fireworks, and "the winner" only means something
once "who is watching" does.

---

## Gap 1 — the viewer is not a concept — **shipped** (`fb3d704`)

**`zones.viewer` is the seat in front of this screen**, nil unless a client has
claimed one, and `visible`/`peekable` ask it instead of `active_seat()`. The
design below is what shipped; three things the build settled, and only the first
was foreseen:

- **A field written from outside, not a call into `net`.** The dependency runs
  the wrong way and it stays that way — `net.lua`'s first line promises no engine
  module requires it, and that is worth more than the one string it costs.
- **`net.claim_seat` is now the only way to sit down.** The seat was assigned in
  **three** places, not the two this file counted: the `net_seat` action
  (`net.lua`), the browser panel's seat buttons (`netpanel.lua`), and `play.lua`'s
  CLI. Sitting down says two things now, and one site setting half of it is
  exactly how this comes back.
- **A viewer naming no seat in the current game falls through to the turn.**
  Not in the plan, and needed: claiming `south` and then loading chess would
  otherwise hide every hand on the table, including the one being held. A claim
  this game has never heard of is not a claim about anybody.

**The test is the one the file could not previously express**, and it earns its
place — it fails on exactly the two checks that name the bug when the viewer is
disabled. With `south` claimed and north to play, south sees its own hand and
not north's; then the handover that *every other test in the file leans on*
changes nothing at all. That is also the answer to why a thorough pass missed
this a commit earlier: with one client the two seats always move together, so
the bug is invisible from inside a hot-seat test.

### The original write-up

*Urgency: high — it is a bug, in the feature that shipped last · Difficulty:
small · Usefulness: high, and it unblocks the rest of this file*

`zones.visible` (`zones.lua:186`) and `zones.peekable` (`zones.lua:225`) both
end the same way:

```lua
if not z or z.zone_type ~= "hand" or not z.seat then return true end
return z.seat == M.active_seat()
```

`active_seat()` is the seat whose **turn** it is. In hot-seat that is the right
answer and is exactly what `63220e6` checked — one screen, one person, and the
two swap together at the handover.

**In networked play it is the wrong seat.** `net.seat` is the seat this client
may play (`net.lua:53`), and nothing in `zones` or `render` knows it — `main.lua`
and `netpanel.lua` are the only modules that require `net` at all, which is a
deliberate property stated in `net.lua`'s first line:

> *Sits beside the engine rather than inside it: no engine module requires this
> one.*

So while your opponent is thinking, `active_seat()` is *them*, their hand is
drawn face up on **your** screen, and `peekable` will happily lay it out sorted
if you right-click it. The half of hidden information the last commit fixed was
the *reading* paths; this is the other axis, and no test covers it because every
visibility test drives the hot-seat handover.

**The fix is one concept: the seat at this screen.** `net.seat` when a client
has claimed one, `active_seat()` otherwise — which keeps hot-seat, solo play and
a spectator all behaving as they do today.

Where it lives is the only real decision, because the dependency runs the wrong
way: `net` requires `zones`, so `zones` may not ask `net`.
[Assumption: the cheapest shape that respects that is a plain field — `zones.viewer`,
nil by default, written by `net` when a seat is claimed or released, read by the
two functions above. It is client-side display state, so it must **not** join the
snapshot protocol, and `net.seat` already lives outside the snapshot for the same
reason.] *— that is what shipped, unchanged.*

**Test it where the bug is**, not where the old ones are: two clients, seats
claimed, and assert that the same game state answers `visible` differently on
each — which is the property the hot-seat tests can never express, since they
have one client.

---

## Gap 2 — a player has no name — **parked**

*Urgency: low, until there is somebody at the other end · Difficulty: small now
that [24](24-save-and-load.md) has built the store · Usefulness: medium — it is
what makes every other message about a person readable*

Nothing anywhere holds a player's name. `link.name` in `netlink.lua` is the
*transport's* name (`"browser:ravel"`, `"webrtc"`), and `net.seat` is a seat key
from the game file (`player_white`, `north_side`). A game that says *White to
move* or *North wins* is naming a chair.

Two halves, and they are independent:

**Where the name is kept — answered, and built by somebody else.**
[24](24-save-and-load.md) shipped the store this was waiting on: `conf.lua` sets
`t.identity`, `save.lua` writes and reads through `love.filesystem`, and the
browser question is settled — love.js already mounts its save directory out of
IndexedDB and populates it before the game runs, so the only missing piece was
the flush, and `save.lua` does that after every write. A name is one more small
file beside a saved game, and the paragraph that used to stand here (an
assumption about `settings.lua` and a browser check that might not pass) is
gone because it has been done.

**Where the name is sent.** The handshake already carries a game name and three
hashes (`net.lua:107`, and the `pack` header). A name is one more field, and the
rule it must follow is already written down at `net.lua:331`: *no field can
legitimately contain whitespace*. So it is sanitised, length-capped, and — like
every other string that arrives from a peer — it is **untrusted display text**.
It names a person in your log; it may never be a key, a seat, or anything the
engine looks up.

## Gap 3 — a place to change it — **parked**

*Urgency: low, with gap 2 · Difficulty: medium — the whole difficulty is which surface ·
Usefulness: medium*

The note says *this might be tricky*, and it is right: the engine has no text
input anywhere. Three routes, and they are genuinely different bets:

| Route | What it costs | What it gives |
|---|---|---|
| The browser panel (`netpanel.lua`) | almost nothing — it is already HTML with `<input>` fields, and the name lives beside the room name | browser only. The desktop build and `play.lua` get no settings at all |
| A settings screen as a game file | nothing in the engine *if* the settings are choices; `menu.json` is already a game and an offer zone is already a chooser | a name is free text, and no card can be typed into. Toggles and picks fit; a name does not |
| Text entry in the engine | `love.textinput`, a focused field, a caret, and a second input surface that every overlay must now think about | one answer everywhere, and the first thing that makes a *player* a first-class idea |

[Assumption: the honest order is the panel first — it is nearly free and proves
whether a name is worth having — and the third only if the desktop build turns
out to need it. Building the general text field first is how a settings menu
becomes the project instead of the feature.]

**What belongs in settings, once there is a place for them:** the name (gap 2),
debug mode (gap 4), and nothing else yet. A settings screen that starts
collecting rendering preferences is a second place where a game's look is
decided, and [11](11-styles-as-tags.md) just finished making that one place.

## Gap 4 — debug mode, opt-in and announced

*Urgency: low, and lower than when it was written · Difficulty: low once gaps
1–3 exist · Usefulness: medium*

**Half of what this note was about is already fixed, and by the other route.**
When it was written, ctrl+hover printed the key of any card at all — including
a face-down deck's top card and an opponent's hand — which `inspect.lua`
recorded as deliberate:

> *Read-only, and deliberately unconditional: it shows face-down cards and other
> players' hands, because it is a window onto this machine's own state, which the
> client already holds either way.*

`63220e6` closed it: the inspector asks `zones.peekable` like every other
reading path, and the comment above it is now out of date. So the item is no
longer *stop the inspector leaking*. What is left is the opposite request, and
it is a better one:

> **An author needs the unconditional view back. A player must be told when
> somebody has it.**

The shape:

- **A mode, off by default**, that restores the pre-`63220e6` behaviour — the
  inspector answers for anything, peekable or not. Nothing else changes: it stays
  read-only, and it never becomes a way to *move* a card.
- **The peer is told**, in the handshake and again whenever it changes, and the
  netpanel says so where it already says who is linked (`net.lua:577`,
  `netpanel.lua`'s status line). [Assumption: the same one-word field the name
  travels in — it is a boolean beside a string, not a second message type.]
- **The log says it locally too**, so a game you started in debug does not
  quietly stay that way for the next one.

**State the limit rather than implying it is a guarantee.** A client that
announces its own debug mode is a client choosing to be honest, and a modified
client will not. `DESIGN.md:282` and [DONE.md](DONE.md)'s *Trust: cheating is
not handled* already say what would actually fix that — a referee that takes
moves rather than states and shows each player only their part — and this is not
it. What it buys is real and smaller: **an accident cannot happen silently, and
a friend cannot forget they left it on.**

---

## Gap 5 — arbitrary chat, which is what a name is for

*Urgency: low · Difficulty: medium, with the store half of it now built — what
is left is the same input surface · Usefulness: it is the thing that makes gap 2
worth having*

**A name with nobody to read it is decoration.** Hot-seat is one person driving
two seats, so *North* and *South* are as good as any two names. The only place a
name means anything is a network game, where the other seat is a stranger — and
in that setting the missing thing is not really the name, it is that **there is
no way to say anything to them at all.**

So the two belong together. The pieces overlap almost exactly:

- **The transport is already there.** `net.lua` ships whole states and deltas
  over any channel `netlink` can carry, and a chat line is far smaller than a
  delta. [Assumption: it rides as its own message kind rather than as a field on
  a state, because a line said while nothing is happening must still arrive, and
  a state carries a fingerprint chain that a chat line has no business
  disturbing.]
- **The display is already there.** The event log is a scrolling column of
  strings with an expand key, and `log.add` is one call. A line from a peer is
  the same shape as *"— North to play —"*, differently coloured.
- **The input is not**, and it is the same missing thing gap 3 is about: one
  text field, on whichever surface gap 3 settles. Chat wants the field *during*
  a game where a name wants it once, which is the harder version and is
  therefore what should decide the route.

**Everything a peer sends is untrusted display text** — the rule gap 2 already
states for a name applies here word for word and matters more, because a chat
line is longer, arrives more often, and is written by somebody who chose it.
It is displayed, never parsed; never a key, a seat, an action or a filename.

[Assumption: this is where the name lands too — a chat line is worth attributing,
so the handshake field and the chat channel ship together, and neither is worth
building on its own.]

## Refuse

- **A player *entity*.** A seat is already a card (`DESIGN.md:27`), and a name
  is a property of the human, not of the seat they took — it must not enter the
  game state, or it joins the snapshot, the hashes and the network protocol, and
  two peers with different names for themselves would disagree about the game.
- **Names as identity.** A name is display text from an untrusted peer. Seats
  stay keyed by the game file's own words, and every lookup keeps using those.
- **A debug mode that can change state.** The moment it can move a card, undo,
  or edit a stat, it is a cheat rather than a window, and "announced" stops being
  enough. Read-only, and the announcement is about fairness in a game between
  people who trust each other.
- **A settings file that games can read.** Client preferences are not game
  input. A game file that behaves differently because of a local setting is
  unreproducible, and both peers would compute different states from the same
  moves.

## Build order

1. ~~**The viewer** (gap 1), and the two-client visibility test~~ — **done**
   (`fb3d704`). It was a bug fix and it stood alone, as expected.
2. ~~**The store** — `conf.lua` identity, `settings.lua`, and the browser
   check.~~ **Built by [24](24-save-and-load.md)**: identity,
   `love.filesystem`, and the browser flush, which turned out to be the whole
   of the browser question. What is left here is one small file beside a saved
   game.
3. **The name and the chat together** (gaps 2 and 5): settings entry, handshake
   field, a message kind, and the places that print a seat learn to print a name
   when there is one — the log, the netpanel, and [07](07-presentation.md) gap
   6's ending screen. Chat is what decides the input surface, because it needs
   the field *during* a game.
4. **Debug mode**, last, because it is the one that wants both a store and a
   handshake field to already exist.

**Steps 2–4 are parked**, and the reason is the reordering itself: none of it
pays off at one screen, and the network game it does pay off in wants the chat
as much as the name.
