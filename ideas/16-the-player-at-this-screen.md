# 16 — The player at this screen

**Gap 1 shipped** (`fb3d704`). **Gaps 2–5 parked** — none of it pays off at one
screen, and the network game it does pay off in wants the chat as much as the
name. An afternoon each once picked up.

Three `todo.md` notes that turn out to be one subject: the engine knows which
seat is **up** and has no notion of who is **looking**.

## Shipped — the viewer

`zones.viewer` is the seat in front of this screen, nil unless a client has
claimed one, and `visible`/`peekable` ask it instead of `active_seat()`. Before
it, while your opponent was thinking, `active_seat()` was *them* and their hand
was drawn face up on your screen.

Three things the build settled, and only the first was foreseen:

- **A field written from outside, not a call into `net`.** The dependency runs
  the wrong way and stays that way — `net.lua`'s first line promises no engine
  module requires it, and that is worth more than the one string it costs. It is
  client-side display state and must never join the snapshot.
- **`net.claim_seat` is now the only way to sit down.** The seat was assigned in
  **three** places, not the two this file counted. Sitting down says two things,
  and one site setting half of it is exactly how this comes back.
- **A viewer naming no seat in the current game falls through to the turn.** Not
  in the plan, and needed: claiming `south` and then loading chess would
  otherwise hide every hand on the table, including the one being held. A claim
  this game has never heard of is not a claim about anybody.

**The test is the one the file could not previously express.** With `south`
claimed and north to play, south sees its own hand and not north's; then the
handover *every other test in the file leans on* changes nothing at all. That is
also why a thorough pass missed the bug a commit earlier: with one client the two
seats always move together, so it is invisible from inside a hot-seat test.

## Parked — a name, a place to change it, chat, and debug mode

**A name with nobody to read it is decoration.** Hot-seat is one person driving
two seats, so *North* and *South* are as good as any two names. The only place a
name means anything is a network game — and there the missing thing is not
really the name, it is that **there is no way to say anything to them at all.**
So gaps 2 and 5 ship together or not at all.

**Where the name is kept is answered**, by [24](24-save-and-load.md): `t.identity`,
`love.filesystem`, and the browser flush, which was the whole of the browser
question. A name is one more small file beside a saved game.

**Where it is sent** is the handshake, which already carries a game name and
three hashes. The rule it must follow is already written at `net.lua:331` — *no
field can legitimately contain whitespace* — so it is sanitised, length-capped,
and **untrusted display text**: it names a person in your log, and may never be
a key, a seat, or anything the engine looks up. That applies word for word to a
chat line, and matters more there: longer, more frequent, and chosen by
somebody.

**The input surface is the real decision**, and the note's *this might be tricky*
is right — the engine has no text input anywhere.

| Route | Costs | Gives |
|---|---|---|
| The browser panel | almost nothing — already HTML with `<input>` fields | browser only; desktop and `play.lua` get no settings |
| A settings screen as a game file | nothing in the engine *if* settings are choices | a name is free text, and no card can be typed into |
| Text entry in the engine | `love.textinput`, a focused field, a caret, and a second input surface every overlay must think about | one answer everywhere |

The honest order is the panel first — nearly free, and it proves whether a name
is worth having. Building the general text field first is how a settings menu
becomes the project instead of the feature. **Chat is what should decide the
route**, because it needs the field *during* a game where a name wants it once.

**Debug mode is the last of them**, and half of what the note asked for is
already fixed by the other route: the inspector asks `zones.peekable` like every
other reading path now. What is left is the opposite and better request: *an
author needs the unconditional view back, and a player must be told when
somebody has it.* A mode off by default, announced in the handshake and in the
netpanel's status line, and logged locally so a game started in debug does not
quietly stay that way for the next one.

**State the limit rather than implying a guarantee.** A client that announces
its own debug mode is choosing to be honest, and a modified client will not.
What would actually fix that is a referee that takes moves rather than states;
this is not it. What it buys is real and smaller: **an accident cannot happen
silently, and a friend cannot forget they left it on.**

## Refused

- **A player *entity*.** A seat is already a card, and a name is a property of
  the human, not of the seat they took. It must not enter the game state, or it
  joins the snapshot, the hashes and the protocol — and two peers with different
  names for themselves would disagree about the game.
- **Names as identity.** Seats stay keyed by the game file's own words.
- **A debug mode that can change state.** The moment it can move a card, undo or
  edit a stat, it is a cheat rather than a window, and "announced" stops being
  enough.
- **A settings file that games can read.** Client preferences are not game input.
  A game that behaves differently because of a local setting is unreproducible,
  and both peers would compute different states from the same moves.
- **Settings collecting rendering preferences.** That is a second place where a
  game's look is decided, and [11](11-styles-as-tags.md) just finished making it
  one place.
