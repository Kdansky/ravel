# 09 — One game out of several files

**Status: shipped, and narrower than this file argued for.** `include` and
`replaces` are in. What the format does is written up in AUTHORING.md (*One game
out of several files*) and `SCHEMA.json`; only the decisions and what is still
open are kept here.

**A game is self-contained, so there is no shared base file.** This document
argued for one — geometry every grid game includes — and it was built and then
taken out again: `line_ortho` in a file that does not define it sends the reader
somewhere else to find out what their own game means, and the saving is four
lines against that. Chess writes its own eight knight vectors and that is the
format working. So the files an `include` names are **the same game's** — a
variant of it, or a set of cards belonging to it — and two games never share
one. Identical text in two independent files is cheaper to read, and cheaper to
change, than one file two games depend on.

## The two decisions the pause was waiting on

**The specific file includes the general one, never the reverse.** The file you
launch has to be a whole game, so a base naming its own variants would *be* one
of them and the plain game would stop existing; and a base that had to be edited
to add a fourth-player module is a change to the thing every module depends on.
One rule covers both the player-count case and MTG's sets.

**A collision is an error unless the including file says `replaces`.** The pause
had recorded the opposite — union-with-identical-or-error, no override at all —
which kills the redefine case the layout modules need. What replaced it keeps
what that decision was protecting: an override nobody announced reads exactly
like an accident, and a set renaming a card while an older file still holds the
old definition would otherwise just work, wrongly, in the file you are *not*
reading. Declaring it costs one word and makes the diff say what happened.

Two consequences that fell out rather than being chosen:

- **`setup` travels now**, where the paused draft said it would not. That draft
  imagined the base as a bag of patterns with no setup of its own; with the base
  being a whole game, a module that must restate the entire setup has inherited
  nothing worth having. `title` and `seed` still do not travel.
- **Sections with nothing naming their entries — `players`, `end_conditions` —
  can only be taken over whole.** There is no key to merge them by, and
  concatenating two seat lists into a four-seat game is the wrong answer
  silently.

## Refused, and still refused

- **Remote includes.** A game file is not a supply chain.
- **Partial includes** (`"include only these keys"`) — a query language waiting
  to happen. A file too big to include whole should be split.
- **Parameterisation** — substitutions, variables, a template an including file
  fills in. That is a programming language.
- **Lazy loading.** `include` is concatenation before parse and must stay so:
  the moment it is lazy, "which cards exist" stops having an answer, which the
  validator, the network hash and `dump` all depend on.

## Left

1. **A module actually written.** The mechanism has a test for every rule and no
   user at all — the one it had, chess over a shared base, was the case that
   turned out to be wrong. No game yet writes the case the word was asked for:
   a player-count module over a whole game, or a card set over the sets before
   it. Arnak is the obvious candidate for the first: 5 of its 22 zones are
   `copies: "per_seat"`, so a third seat is those five zones, `players`, and a
   seat card.
   **[Assumption: the rest of Arnak's three-player rules — component counts, the
   research track — were not looked at. The layout is the part `include` answers;
   whether the rest is a module or a different game is unexamined.]**
2. **Provenance in validator messages.** `card 'lightning_bolt': ...` stops being
   enough when the card came from a file you did not open. The merge already
   keeps a key → source-file map to name both sides of a collision; nothing
   downstream reads it, because `parse` throws it away with the other merge
   bookkeeping. Appending `(from sets/alpha.json)` to a validator warning is the
   use it was built for.
