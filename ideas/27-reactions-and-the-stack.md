# 27 — Reactions and the stack

**Shipped and in use.** One reaction mechanism, so every game that lets a player
answer another's action spells it the same way. Puzzle Strike is the first
customer; AUTHORING carries the full reference.

**Left:** speeds (Runeterra Fast/Slow), Magic depth, and Dragon Form's emission
suppressor. All three below.

## The core idea: invert the dependency

Writing "this card can be countered by X, Y, Z" onto every counterable card is
the wrong direction — a fireball must not know what answers it. **The thing
acted on emits a generic, self-describing event; each reaction declares which
events it answers.** Fireball never mentions flame-counter. The engine scans
reactions for a match, never the reverse.

The one hard blocker was that out-of-turn play was refused: `reachable()` gated
every play on `owner == active_seat`. Everything adjacent already existed — the
pass/priority idiom, `set_active_seat`, the ordered zone walk, the
case-table-is-a-zone pattern — so this was mostly combining them plus that
unlock.

## The decisions that carried it

**Priority is distinct from turn.** `active_seat` reads priority over turn, so
moving priority is the whole of out-of-turn play and the turn stays put.

**Nothing on the stack is a game card.** Every entry is an `event` record
standing for something announced, and the card that announced it stays where the
play found it. This replaced putting the played card up itself, which was the
riskiest thing in the design: `resolve_top` had to reason about whether a card's
own action had moved it, a reaction had to mint a fresh copy of itself to get
back into a bag, and countering meant destroying a real game object. All three
disappear, and an id is then the only handle anything holds, which is what keeps
undo's deep copy honest.

**`emits` is keyed by the moment**, because one card is often two things:
`{ "play": "cast", "activate": "ability" }` is a spell from hand and a machine on
the board, and a reaction to one must not catch the other. It sits *beside* the
moment blocks rather than inside them, and that is load-bearing: a `play` block
is granted whole or not at all, so a tag inside `play` would take the card's own
action away from it. Written on a tag, one line makes every spell in the game
answerable.

**`counterspell` names no zone**, and that is the whole design: a counter that
had to know where a spent chip goes would need half the rules of every game it
appears in. Named for the word every player knows — `cancel` already meant six
things, one of them the button that abandons a targeting session.

**`spent` says where a card goes however its play ends** — resolved, or countered
before it ever ran. An MTG sorcery goes to the graveyard either way and a Puzzle
Strike chip to the table either way, and neither the action list nor the counter
should be the one that remembers. Run as the card's *owner* rather than as
whoever is up, since a counter resolves while the answering seat holds priority
and `mine.table` has to mean mine. It replaced 54 hand-written `move_to` lines in
Puzzle Strike alone.

**`spent` cannot come from a tag, and that stays.** Tags grant a whole `play`
block or none of it. Editing a block rather than granting one is a different act
and would want a different word — `"play_merge": { "spent": … }` — rather than
quietly making `play` mean both.

**A window locks everything else.** Priority was the whole out-of-turn unlock and
it unlocked *everything*: the reactor could empty their hand into the turn
player's turn. `reactions` is ravel's only spelling for a card played out of
turn, so the lock costs nothing that should have worked.

**One card answers one record once.** The stack no longer takes the reaction out
of the hand it came from, so without this a reaction that moves itself nowhere
answers the same record forever. Tracked per record, which is the right
granularity — the seat may still answer again with a *different* card.

**Priority is released when nothing holds it.** A phase interjected mid-answer is
up because *they* are, so the stack emptying must not hand their phase to the
turn player. `phase.depth() > 1` is the whole test. Two rules fall out: the stack
**suspends** under an interjection, and the window lock **lifts** inside one — a
phase pushed for this seat is a hand-over, not a window, and playing in it is
the point.

**The window is a `player_input` phase, not an overlay.** A window that surfaces
a board reaction must not be a modal that covers the very card it is asking
about. The player sees the board with the eligible cards lit and a pass button.

**Filter B needed no field at all.** It was to be a `prompt` enum,
`possible`/`certain`. The loose reading is the only one worth having: a game that
hides nothing has no secret zone for it to widen, so it already gets the exact
answer, and the setting could only ever have been used to *turn the leak on*.
Every zone the opponent cannot read is one pool — a hand and the bag behind it
are the same place from across the table — so the window's appearance says
nothing. What the asked seat is *offered* is exact either way: a question that
was a guess must not become a lie to the player's face.

**No per-event "already reacted" latch.** The window re-opens, priority resets,
and only all-players-pass-in-succession ends it. The same trigger may match an
event repeatedly, bounded only by its own cost and `when`. This is a thing to get
right by *not* building the obvious dedup.

**A resolution is itself an event**, which is how reacting as the stack resolves
works without new machinery: popping the top and running its action can emit, and
`settle` opens a fresh window before the next pop. That is Magic's rule verbatim.

**Where the card sits plus `from` decides what answering means.** `from: "hand"`
*plays* it out of turn; `from: "board"` either activates it or fires a static
trigger, and the card stays put while its effect is stacked.

**`destroy` takes a count**, which is what Stone Wall needed and repeating the
line could never give: how many is the size of the crash, known only as the game
runs. It reads the same amount grammar every other count does. Which ones, where
there are more than asked for: the earliest, unless the scope says `random` —
most pools are identical cards, and spending randomness on a choice that does not
matter costs a reproducible game for nothing.

## What the first customer settled

Bubble Shield's chip `transform`s into a second card when laid out, so the two
halves are two cards and `from` never has to tell an ongoing row from a hand. The
negation is *remove a gem already landed* rather than *prevent one arriving*,
which is free because defeat is only read at the end of your own turn.

**Rigorous Training needed no price filter on a shop.** The allowance is handed
over as *money*, so the ordinary price of every pile does the gating — which is
why `options` never grew a `where`, though that was the plan. The bank hands
whatever lies in it a `buy` announcement through `applies`, so eighteen piles say
nothing about being answerable and one tag says it once — and un-says it the
moment a card leaves, for free.

**`price` is on every chip and read by nothing.** Each pile duplicates the number
by hand into its cost block. Making the cost read the price would kill eighteen
duplications, but cost values go through `plan`, and `can_afford` is the hot
legality path — asked per board card per frame, on a browser build with no JIT.
Left alone deliberately.

## Still open

**Dragon Form** — *your purples can't be reacted to*. It needs an emission
suppressor keyed on the emitting seat, which is genuinely new surface: distinct
from `applies` (zone-local) and from `where` (event-local), and not reachable by
making Dragon Form react to its own purples, since countering is the opposite of
what it wants. Under the record design a suppressed emit would simply create no
record, so the card resolves as in a game with no reactions at all.

**Speeds**, for Runeterra Fast/Slow.

**Magic depth**: APNAP trigger ordering, and targeting at cast versus at
resolution.

## Deliberately cut

- **Replacement effects** ("if it would die, exile it instead"). They do not use
  the stack; they rewrite the event before it happens. Magic needs them; Puzzle
  Strike and Runeterra do not.
