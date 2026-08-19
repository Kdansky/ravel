# 22 — The Crew: The Quest for Planet Nine

**Status:** not started, and **half of its one primitive has shipped** — see
*What shipped* below · **Size:** medium · **Depends on:** none of the
deckbuilder candidates — self-contained

> *Cooperative trick-taking. Named directly alongside the deckbuilder
> research as a good fit.*

**Objective.** The Crew is trick-taking stripped to its cleanest modern
form: four numbered suits plus a trump ("rocket") suit, no bidding, task
cards dealt out at the start of each of fifty missions ("I will win a trick
containing this card," "I will win exactly N tricks," some tasks partially
ordered relative to each other), and a once-per-mission communication token
that lets a player flag exactly one card in hand as highest/lowest/only-of-
suit. [01-boardgames.md](01-boardgames.md) already flagged the general shape
of this question — this file is where it gets checked against one real game:
**the trick winner becomes the next active seat**, which today's phase
routing (`"seat": "next"`) cannot express, since it only walks the fixed
seat list in file order.

---

## What shipped — the reading half of the primitive

**`@owner_of.<scope>` is a scope, and it answers with the seats.** The lookup
this file identified as its one root — *convert "this entity's owner" into a seat
the rules can talk about* — exists now in `predicate.entities_in_scope`, spelled
as a prefix on a scope expression because the words after `@` are separated by
`.` and a colon would arrive as a second action argument. `score@owner_of.target`
is the score of whoever owns the card the player chose; on its own, `@owner_of`
is the acting card's own seat, which no card could name before.

Four things the build settled:

- **It answers with the seat's *card*, not a key**, because a scope's answer is
  entities everywhere else — and the card's `def_key` is the seat key, so the
  other half of the primitive reads it back off the same answer.
- **It uses `predicate.seat_of`, not `tags.owner_of`.** `seat_of` is what
  `mine`/`enemy` ask, so the scope and the owner words can never disagree about
  whose a card is; it also makes a seat card asked about itself answer itself
  rather than nobody.
- **An owner word means whichever side of the prefix it stands on** — inside it
  picks the cards (`@owner_of.enemy.creature`), before it it filters the seats
  that come back (`@mine.owner_of.target`). Each word sits beside what it is
  about, so neither reading has to be remembered.
- **Each seat answers once** however many cards it owns, and a card nobody owns
  names nobody. A seat counted once per card would pay a player twice for
  holding two pieces, which reads as a rules decision rather than as a bug.

**What is left is the writing half**: `set_active_seat:<scope>` (or `"seat":
"owner_of:<scope>"` on a routing entry), which turns that seat into the one whose
turn it is. That is the part The Crew cannot be built without — the trick winner
leads the next trick — and it is now a `G.seat_index` lookup over an answer the
scope already gives. [Assumption: it belongs on the routing entry as well as in
an action, because the trick winner is decided at a phase boundary and a phase's
`seat` field is where turn order is already written; but only the action has a
customer today, so build that one and leave the routing spelling until a game
asks for it.]

## Stage 1 — the rules document

**Deliverable:** `ideas/the_crew/rules.md`, sourced and marked the same way
as [19](19-mage-knight.md)'s. Must cover:

- Trick resolution in exact order: must-follow-suit if able, the trump
  rule, how the winner of a trick is determined.
- The task deck: every task type, especially the partial-order and
  no-particular-order variants, and how tasks are dealt out and assigned to
  players at the start of a mission.
- The communication token: exactly what it restricts (one card, one time
  per mission, highest/lowest/only-of-suit, no take-backs).
- Mission structure and campaign scoring — how a mission is won or lost, and
  what carries over between missions.

**Done** — [ideas/the_crew/rules.md](the_crew/rules.md). Built from the
official KOSMOS rulebook PDF and the official mission logbook PDF, both
fetched and read in full (the logbook through mission 36 of 50); every
unattributed quote in the rules doc is verbatim from one of the two. One
correction to the objective's own framing turned up and is flagged up front
in the doc: "win exactly N tricks," "win no tricks," "win the last trick"
and the rest of that variety are **not** part of the 36-card task deck —
that deck expresses exactly one shape ("win the trick containing this
specific numbered card," optionally sequenced by an order token). The rest
is bespoke per-mission rule text printed in the logbook, assigning the
condition directly rather than dealing a card for it — both systems are
real and both are covered. Every number not cross-confirmed is flagged
inline and collected in rules.md §11.

## Stage 2 — what it names that the engine lacks

**Deliverable:** the gap table, centered on the dynamic-next-actor question —
is "route to the seat that owns the winning card" a small addition to phase
routing, or does it want a new primitive of its own. Note in passing whether
the task-assignment step needs anything beyond an ordinary overlay deal.

| The Crew rule | Ravel today |
|---|---|
| 40-card deck, 4 suits × 1–9 plus rocket 1–4, dealt evenly per seat (13/13/14 at 3p, 10 at 4p, 8 at 5p) | `per_seat` hand zones, `contents`, `shuffle` — **exists** |
| N seats each play one card per trick, in table order, into a played-card area | `per_seat` pile zones plus ordinary `play.action`/`move_to`, `"seat": "next"` for the walk through the trick — **exists**, once the played-card zone is per-seat rather than shared (a shared zone loses ownership the instant a card leaves a per-seat hand) |
| Must follow suit if able; may play anything if unable | the `can_play` escape hatch plus a Form-3 subject-vs-subject `needs` — **expressible, and non-obviously so** — worked through below |
| Rocket is trump: always wins outright over any color card, and is itself a followable suit when led first | the same suit-numbering scheme as follow-suit, rocket as a fifth suit value — **expressible**, no new mechanism |
| Determining the trick winner (trump beats everything; else highest of the led suit; off-suit cards never contend) | **partly expressible, partly a genuine gap** — `max:` alone isn't enough; worked through below |
| **The trick winner becomes the next active seat** | **the central genuine gap** — worked through below |
| Cards from a won trick are set aside face down; no scoring consequence attaches to who physically collected it | an ordinary `destroy:`/`move_to:` on the resolved trick — **exists**, trivially |
| Task deck: 36 cards, one per non-rocket color+number, distributed into a player's own zone | `card:<key>@mine` — Lost Cities' "does the player have the rusty key" idiom — **exists/expressible**, at real authoring volume (36 distinct keys) |
| Task order tokens: strict 1–5 ranking, or `›`/`››`/`›››` partial before/after order | a small authored graph of position markers and edge conditions, the shape Arnak's research track already used — **expressible** |
| Special per-mission task shapes: no tricks at all, exactly N tricks, first/last trick, a trick with every card in a named set | ordinary stat counters and `needs`/`end_conditions` comparisons — **exists/expressible**, contingent on the trick winner's identity being knowable at all |
| The running-parity task ("no crew member ever more than 2 tricks ahead of another") | **small genuine gap** — the amount grammar has no subject-plus-constant comparison; same class as Mage Knight's halving-and-floor gap |
| Task-assignment draft: commander picks first, then every other player takes one revealed task in turn until the shared pool is empty | the ordinary overlay/options-per-seat draft loop AUTHORING already documents — **exists**, except for who picks first |
| The commander is whoever holds the rocket 4 in *this* deal — not a fixed seat, and this same seat also leads the first trick | **the same dynamic-seat gap**, needed once per mission instead of once per trick — see below |
| Commander's decision / Commander's distribution (two mission-specific draft variants) | a yes/no poll via ordinary played tokens, and an `activate.target` assignment loop — **expressible**, ordinary content once the base draft works |
| Communication token: one card, flagged highest/lowest/only-of-suit, once per mission attempt, no take-backs | an ordinary one-shot `destroy_self` card, not `exhaust` — **expressible**, and the obvious first reach is the wrong tool — worked through below |
| Instant loss: a task's target card is won by a player other than its owner | a per-trick check reading `card:<key>@enemy` — **expressible**, and simpler than the objective's own framing feared |
| Instant loss: a task-order token is violated | the same per-trick check against the order-graph's own markers — **expressible** |
| 50-mission campaign, replayable and reorderable, each mission a fresh independent deal | a content-authoring-volume question, not a structural gap — see below |

### Must-follow-suit, worked through with real syntax

Give every card a numeric `suit_id` (`card_stats`: pink 1, green 2, blue 3,
yellow 4, rocket 5 — rocket needs one too, since rocket is itself a
followable suit, rules.md §2 step 4) and give the system card a
`led_suit_id` stat, reset to 0 at the start of each trick. Every card in the
game, whatever its suit, carries the identical clause:

```json
"play": { "needs": { "suit_id@self": { "equals": "led_suit_id@system" } } }
```

This is `DESIGN.md`'s Form-3 bend (a comparison measured against another
subject, not a constant) — the exact idiom Lost Cities already uses for its
ascending-expedition rule. Read against `flow.can_play`'s escape hatch ("a
needs-gated card becomes playable when nothing else in its zone is"), the
same clause on every card produces the whole rule for free:

- **Leading.** `led_suit_id` is 0, and no `suit_id` is ever 0, so *every*
  card in the leader's hand fails its own `needs` identically. Nothing else
  in the zone is playable either — the escape hatch opens for all of them
  at once, so any card, including a rocket, may lead.
- **Holding the led suit.** Only the matching-suit cards pass `needs`
  directly; everything else stays gated, and the escape hatch does not
  fire because *something* in the hand is legal. Follow-suit, enforced.
- **Not holding it.** Every card fails `needs` again, the hatch opens for
  all of them, and any card may be played — exactly "if you do not have a
  card of this suit you may play a card of a different suit."

The one wrinkle worth being honest about: writing `led_suit_id` cannot be a
step in every played card's own `action` list, or the second player's play
would silently overwrite what the third player needs to read, corrupting
the very value the rule depends on. It has to run exactly once per trick,
outside any specific card's action — a one-shot `automatic` phase inserted
between the lead play and the follow loop, reading the single card that has
been played so far: `"set_stat:led_suit_id@system:sum:suit_id@trick_play"`
(`trick_play` a `per_seat` zone, so the sum is honestly one card's value
until the second play lands). This is standard phase sequencing, not a new
primitive — it just has to be gotten right, and getting it wrong produces a
rule that looks correct in testing and is quietly broken on the third
player's turn.

### The trick winner: where `max:` stops being enough

Identifying *which* entity holds a maximum is not itself the gap —
`{"value@self": {"equals": "max:value@<scope>"}}` is exactly Lost Cities'
own destination check, and it works here too, once the scope is narrowed
correctly. The narrowing is the hard part, because it is not a single flat
comparison: trump beats everything regardless of value, and outside that,
only cards that share the led suit even count. Both branches are
expressible in content — `count:rocket@trick_play` (or a `rocket`-tagged
count) selects the branch, and within each branch the same closed set of
per-suit conditions the follow-suit rule already needed (one authored
clause per led suit, since a scope name can't be parameterized by another
card's tag at runtime) picks out the right pool for `max:`. Heavy, but the
same "closed set, a generator's job" texture Mage Knight's sideways play and
Arnak's site-spaces already established — not a new gap.

**What genuinely has no answer in today's vocabulary is the last step**:
having identified — in content, correctly — *which entity* won, nothing
converts that into "this seat plays next." `set_stat:turn:n` could write the
system card's `turn` stat directly, but `n` has to be a literal number or a
`count:`/`sum:`/`max:`/`card:` aggregate — none of which answer "the
position of this card's owner in `seat_list`." `predicate.lua`'s `FNS` table
(`count`, `card`, `sum`, `max`, `tagged`, `not_tagged`) has no such
function, and it would be an odd one to add: it isn't a *measure*, it's a
*lookup* into an ordering the condition vocabulary was never built to
answer. Two ways to close it, worth distinguishing because they cost
differently:

- **Option A — bake trick resolution into routing.** A literal
  `"seat": "winner_of:<comparison>"` value, as the stub's own phrasing
  suggests. This would require phase routing to understand the trump/suit
  priority itself, which is exactly the kind of engine-knows-the-game-rule
  move invariant 7 warns against — the equivalent, for turn order, of
  `render.lua` learning what Overwhelm means.
- **Option B — a narrow, reusable primitive.** *Half built — the scope shipped;
  see [What shipped](#what-shipped--the-reading-half-of-the-primitive).* Keep all of the above (the
  branching, the per-suit narrowing, the winner identification) in content,
  exactly as worked out above, and give the engine exactly one new thing:
  a way to read *whose* card a scope resolves to and make that seat active.
  `predicate.seat_of` and `tags.owner_of` already answer "whose is this" —
  they're existing internal functions, not new ones — and `flow.lua`
  already computes a seat's index (`G.seat_index[e.owner]`) for other
  purposes. What's missing is a content-facing hook wired to them instead
  of `rotate_seat`'s fixed `(turn % #seats) + 1`: something in the shape of
  `"seat": "owner_of:<scope>"` on a routing entry, or an action
  `set_active_seat:<scope>`. This is small — a lookup, not a subsystem —
  and it has a **second customer inside this same game**, which is exactly
  the signal invariant 7 asks for before generalizing: the mission-start
  commander (below) needs the identical primitive.

Option B is the honest answer to "is `max:` enough": no, but not because
`max:` is weak — because the missing piece was never a measuring function
to begin with, and pretending it is would produce the wrong kind of fix.

### The commander is the same gap, once per mission instead of once per trick

Rules.md §5: whoever is dealt the rocket 4 leads the first trick *and*
picks first in the task draft. Both facts are downstream of one seat
identity that the shuffle decides fresh every mission, not the file's seat
order. Concretely, this needs the exact same `owner_of:<scope>` lookup
proposed above, scoped to `card:rocket_4` instead of "won the last trick" —
and unlike the per-trick case, it fires only **once** per mission: after
that single seed, the task-draft's clockwise turn order and the ordinary
`%n+1` rotation coincide, because "clockwise from the commander" *is*
table-seat order once you know where to start. That asymmetry — one seed
per mission, one resolution per trick — is worth keeping in view: it's the
same primitive carrying two very different call frequencies, not two
different primitives.

### The task-assignment draft is otherwise unremarkable

Set aside who picks first, and rules.md §5's procedure is precisely
AUTHORING's "Draft one of three from a real deck" pattern, generalized from
three cards to a variable pool: a `player_input` phase bound to a shared
revealed `task_offer` zone, `ends_after: 1`, `"seat": "next"` on entry,
routed back to itself while `{"zone_empty": ["task_offer"]}` is false and
onward once it's true. Nothing about a shrinking shared pool or a variable
number of tasks per player needs anything past what kingdom's draft already
exercises. Commander's decision and Commander's distribution (rules.md §4b)
layer ordinary content on top once the base loop works — a yes/no poll via
two token cards, an `activate.target` spec scoped `owner: "anyone"` for the
commander's own secret assignment.

### The communication token: exhaust is the wrong reach, again

The obvious first idiom — `"cost": {"exhaust": 1}` — is wrong for the same
reason `refill_when_empty` was wrong for Puzzle Strike's bag: `exhaust`
resets on every round wrap, and a mission is not one round, it's the whole
attempt. The task's own framing is right that a mission maps to something
bigger than a round — closer to a full game, since each mission is a fresh
shuffle, a fresh deal, and a fresh set of tasks (rules.md §6), exactly the
granularity `M.init`/`load_game` already operates at. Once that's the unit,
the token needs no special scope handling at all: an ordinary per-seat card,
one copy, `"activate": {"action": [..., "destroy_self"]}`. It is spent once
and never refreshes, because nothing recreates it until the next mission's
setup deals a fresh one — which is just an ordinary `fill:` step in that
mission's own setup, not a new engine idea. If The Crew's fifty missions
end up as fifty small `game.json` files (see below) rather than one file
looping internally, this is even more literal: the token needs zero
lifetime logic at all, because a fresh `M.init` already clears everything.

### Instant loss: both real triggers are simple, and the fear resolves in ravel's favor

The stub's own framing worried this might only be checkable for "simple"
provably-impossible cases, with deeper cases needing lookahead the engine
can't do. Reading the actual rule closed that question rather than
confirming the worry: **The Crew has exactly two instant-loss triggers, and
both are direct, immediate, observable facts about the trick that just
resolved** — rules.md §6. There is no third, deeper case in the real rules
at all, no "this task can no longer mathematically succeed" reasoning over
remaining-card distributions that the design ever asks a human (let alone
an engine) to perform mid-game:

1. **Wrong-player card loss.** *"If a player wins even a single playing
   card for which another player has the corresponding task card, you lose
   immediately."* This is checked once, the instant a trick closes, against
   every card that was just played: `card:<the played card's task
   key>@enemy` — does some seat *other than the trick's winner* hold a task
   naming this exact card. True, and it's over. This has to run in the same
   moment the trick winner's identity is already known (the "resolve_trick"
   phase above), which makes it a third dependent on the same primitive,
   not a separate one.
2. **Task order violation.** Checked the same way, against the small
   order-token graph rather than card identity: did the task that just
   completed hold a position (`1`–`5`, or a `›`/`››` pair) that the
   already-completed and still-open tasks contradict.

Both are ordinary `end_conditions`/routing checks over state the engine
already has once the trick winner is known — no deduction, no hidden-hand
reasoning, no lookahead. The honest boundary the stub asked about turns out
not to exist in this game.

### The 50-mission campaign is an authoring-volume question, not a gap

Each mission varies independently in task count, which order tokens apply,
and whether it carries bespoke special-rule text (rules.md §4b) — closer in
shape to Arnak's "one card per site-space" scaling problem than to anything
structural. The regular missions (task deck plus order tokens, no special
text) are a plausible generator target, the same texture as
`tools/make_lost_cities.py`; the missions carrying bespoke rule text
(running-parity, "win no tricks," commander's-decision polling) need to be
hand-authored individually, the same mix Arnak's endgame scoring and
site-space cards already accepted. Whether the fifty missions live as one
game file with mission-selection state or fifty small files sharing an
engine skeleton is an authoring decision, not one this document needs to
settle — either way it costs content, not engine code.

### Contrast with 18 — a third shape of turn-order gap, not a repeat

[18](18-legends-of-runeterra.md)'s stage 2 named two turn-order-adjacent
gaps, and neither is this one. LoR's attack token *alternates* between
exactly two seats — trivially `"seat": "next"` on a two-phase cycle, no
engine work, and its own table says so. LoR's real gap, the response stack,
is a card played by the *non-active* seat mid-turn, without a handover at
all — [20](20-puzzle-strike.md)'s counter-crash gap is explicitly the same
shape. The Crew asks for neither of those: every seat still acts strictly
in turn, one at a time, exactly as `flow.reachable` already assumes — there
is no acting out of turn here. What's missing is narrower and more
ordinary-looking: the *next* seat in an otherwise perfectly normal handover
is picked by a runtime comparison instead of file order or a fixed
alternation. Nothing in 18 or 20 needed that, because a two-seat token
alternation and a during-your-opponent's-turn reaction are both already
reachable with what phase routing has. The Crew is the first target game on
this ladder whose turn order genuinely outgrows `"seat": "next"`.

### Verdict

**Buildable in full, contingent on exactly one small primitive — not a
stripped prototype, because there is no honest cut around the piece that's
missing.** Nearly everything The Crew asks for turns out to be either
already built or expressible through real, if sometimes heavy, content: the
follow-suit rule falls out of the escape hatch and a Form-3 comparison with
no new engine code at all; the task deck, order tokens, communication token
and both instant-loss triggers are all ordinary `predicate`/`needs`/
`end_conditions` work once the trick winner's identity is known; the task
draft is a shape kingdom already exercises. That "once known" is doing all
the load-bearing work in this sentence, and it traces to a single root: no
existing primitive converts "this entity's owner" into "the next active
seat." Everything else in the table — trick winner, first-trick lead,
task-draft order, both instant-loss checks — is a customer of that one
missing lookup, not four separate gaps. Unlike Mage Knight, there is no
honest amputation here: a fixed or alternating turn order isn't a smaller
version of trick-taking, it's a different game, so "ship it minus the hard
part" isn't on the table the way dropping Conquest mode or hex geometry
was. The primitive itself is cheap to specify precisely — read who owns the
entity a scope resolves to (`predicate.seat_of`, already internal) and set
that seat active (a `G.seat_index` lookup feeding what `rotate_seat`
currently computes by `%n+1`), exposed as one routing value or one action —
and it earns its place by the ladder's own standard before a second game
ever asks: this document already names two independent call sites for it
(trick winner, mission-start commander) inside one game. That makes The
Crew a better argument for building the primitive than a reason to shelve
the game: everything downstream of it is content, most of it plain, some of
it (the trump/suit branching, the fifty missions) heavy but entirely
familiar in kind to what Mage Knight's sideways play and Arnak's site-space
cards already cost.
