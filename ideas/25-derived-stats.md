# 25 — A stat that keeps itself

**Status:** not started, written up before any code on purpose · **Size:** small
engine change, one large decision, and it competes with an existing track rather
than sitting beside it — see *Against 17*.

Found by measuring the game files for repetition. Four of the five things that
pass turned up have shipped; this is the fifth and the largest, and the one
nearest a line `DESIGN.md` draws.

> *In The Crew, a ton of cards have a lot of 0 stat values… I want to get rid of
> that* → answered by `on`/`start`. This is the sentence after it: the zeros are
> gone, and what is left holding them is arithmetic written as a sequence of
> assignments because there is nowhere to write an expression.

---

## The measurement

Half of every action string in every shipped game is stat arithmetic, and half
of *that* writes to a hidden scratch register rather than to a number anybody
reads:

| | |
|---|---|
| action strings, all games | 934 |
| of those, `stat_*` | 467 (50%) |
| of those, writing to a `hidden` stat | 218 (47%) |

Three concrete ones, all of which are one formula each:

- **Splendor's `price`** — 40 actions computing 7 numbers, structurally five
  copies of the same six-line block plus a fold.
- **Splendor's noble `check`** — 16 actions for one boolean.
- **The Crew's `contend`** — 16 actions, run twice per trick.

These are not effects. Nothing about them is a *change to the game*; they are
values that are always a function of other values, restated by hand every time
anything they depend on moves.

## The shape

`stats` already says four things about a number — floor, ceiling, icon, and (as
of the `on`/`start` pass) whose it is and where it starts. `from` would say how
it is kept:

```json
{ "key": "due_white", "on": ["development"], "min": 0,
  "from": "cost_white@self - b_white@owner" }
```

Two properties make this fit rather than merely work:

- **The clamp is already declared.** `min: 0` is what makes `max(0, a − b)` — the
  identity the Splendor track discovered and the Crew track confirmed — fall out
  of the stat's own floor instead of being an idiom spelled with `stat_damage`.
- **It removes a hazard rather than only lines.** `short` and `gap` are *shared*
  scratch registers today, reused by different formulas in sequence. Two derived
  values wanting one register at once is a bug that cannot be written once each
  value is its own stat.

## Against 17

[17](17-conditions-as-expressions.md) already owns the arithmetic question, and
its position 2 — *one parser for conditions and for action value slots, which
would delete `:x:` rather than add a notation* — is a different answer to the
same pressure. **These two should not both be built.** The comparison, stated
plainly:

| | 17 step 5 / position 2 | this |
|---|---|---|
| What it adds | arithmetic inside an existing string | a field on a stat |
| Where the formula lives | at every use site | at the declaration, once |
| What it deletes | `:x:`, a whole notation | nothing |
| Recomputation | none — evaluated where written | the open question, below |
| Risk | every rules bug can be an arithmetic bug in a string | a value that is stale, or recomputed at the wrong moment |

[Assumption: they are alternatives and not stages, because a `from` written in
the same grammar 17 would introduce is 17 having happened first. If 17 lands, the
right question is whether `from` is then worth anything at all, and it may not
be — a formula at its use site is one place to look, and a stat that keeps itself
is two. That is a real argument against this file and it is not resolved here.]

## The open questions, which are why this is not built

1. **When is it evaluated?** Three candidates, and they are not equivalent:
   on read (correct always, costs per frame on a path that is a bare table
   lookup today — `cards.def`'s comment says so explicitly); on write of any
   input (needs a dependency graph the engine has nothing like); at settle
   (cheap, predictable, and *wrong* for the half-updated moment inside an action
   list, which is exactly where Splendor's pricing runs).
2. **How much arithmetic?** The cap has to be stated before the first line, and
   the discipline conditions already have is the model: one comparison, no
   boolean operators. The equivalent here is **one binary operator**, and the
   test of whether that is enough is Splendor's `price` — which needs
   `cost − discount`, then `clamp0`, then a five-term sum. The five-term sum is
   the part that does not fit, and if the answer is "so allow n-ary `+`" then
   the cap has already moved once before anything is written.
3. **What does `@owner` mean on a card nobody owns?** `due_white` is about the
   buyer, and a development card lying in the row has no owner until it is
   bought. Today the pricing runs under `activate_zone` with `mine` meaning the
   player whose turn it is, which is a *context*, not a property of the card. A
   declaration has no context. This may be the thing that sinks it.

**Question 3 is the one to answer first.** If a derived stat cannot say "less the
discounts of whoever is currently considering buying me", then the biggest case
in the corpus is not expressible and the rest is not worth a new field.

## Refuse

- **Chained derivation** — a `from` that reads another `from`. It is a dependency
  graph, then a cycle check, then an evaluation order to explain in the schema.
  One level, reading only stored numbers.
- **`from` on a stat that anything also writes.** A number that is both computed
  and assigned has two sources of truth and the last writer wins, which is the
  shape of bug that costs an afternoon. If a stat has `from`, `stat_set` on it is
  an authoring error the validator refuses.

## Build order, if it is built

1. Answer question 3 against Splendor's pricing, on paper, before anything else.
2. Pick the evaluation moment and write down why, in this file.
3. `from` with one binary operator, refused on any stat an action writes.
4. Splendor's `price` and noble `check`, and The Crew's `contend`, as the proof —
   with the trick-winner fuzz and the Splendor turn probe as the evidence that
   nothing moved.
