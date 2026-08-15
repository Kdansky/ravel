# Two decks

Reference material for [18](../18-legends-of-runeterra.md), beside
[rules.md](rules.md). Riot's card text and names are theirs — `CREDITS.md` is
where this repository records that, and a fan implementation of two decks
belongs in it.

**Read this first: the card texts are not here, and that is a finding rather
than an omission.** The deck list below is real. The 25 distinct cards in it
each have a cost, a power, a health and a line of text, and none of that could
be copied to a standard worth building against in this pass. What follows says
exactly where it is and what it costs to fetch, because a *nearly* right card
list is the confident-and-wrong document [18](../18-legends-of-runeterra.md)
exists to avoid.

**Milestone 1 does not need them.** [18](../18-legends-of-runeterra.md) stage 3
opens with *two decks of units with no text at all* — vanilla bodies, no spells,
no keywords — to prove the blocking pairing and the combat resolution. That
milestone can be built from the shape at the bottom of this file today, and the
real cards can arrive with milestone 2, when there is something to put the text
on.

---

## The deck that exists: Demacia / Freljord starter

Riot's own two-region starter, and a good first target: 40 cards, four
champions, and almost no text that milestone 2 could not carry.

| Cost | Cards |
|---|---|
| 1 | Cithria of Cloudfield ×2 · Fleetfeather Tracker ×2 · Omen Hawk ×2 |
| 2 | Single Combat ×2 · Starlit Seer ×1 · Vanguard Defender ×2 |
| 3 | Avarosan Marksman ×2 · Kindly Tavernkeeper ×2 · Laurent Protege ×2 · Mighty Poro ×2 · Take Heart ×2 · Vanguard Sergeant ×2 |
| 4 | Avalanche ×1 · Babbling Bjerg ×2 · Braum ×1 · Laurent Bladekeeper ×2 |
| 5 | Avarosan Hearthguard ×1 · Garen ×1 · Lux ×1 |
| 6 | Alpha Wildclaw ×2 · Redoubled Valor ×1 |
| 7+ | They Who Endure ×1 · Judgment ×1 |

Champions: Garen, Lux, Braum, Tryndamere. **The list is second-hand** — read out
of a search summary of [Out of Cards](https://outof.cards/legends-of-runeterra/decks/154-demacia-freljord-starter-deck)
and [runeterrafire](https://www.runeterrafire.com/decks/starter-demacia-freljord-527)
rather than off a card database, and the counts add to 40 only if Tryndamere is
one of the entries above that the summary flattened. **Count it again before
building it.**

## Where the card text actually is

**`https://dd.b.pvp.net/latest/set1/en_us/data/set1-en_us.json`** — Riot's Data
Dragon, machine-readable, no key, and it answers. This was confirmed during this
pass, not assumed. One record per card, with the fields an implementation wants
named almost as ravel would name them:

```
name · cost · attack · health · keywords[] · descriptionRaw · regionRef · type · collectible · supertype
```

**Why it did not get copied here.** The file is a few megabytes and a fetch that
converts it to text and answers a question about it only ever saw part of it —
asking for "every collectible Noxus unit costing 1–4" returned one card. It
wants downloading and reading locally, not fetching. That is ten minutes with
`curl` and a script, and it is the *right* ten minutes: a generated card list
from the source of truth, rather than 25 wiki pages transcribed by hand.
[Assumption: one set file per set, `set1` through however many shipped, same URL
shape — only `set1` was tried.]

Cards read out of that file during this pass, as a sample of what it holds —
**each of these came through a lossy summariser and none should be trusted
without a second look**:

| Card | Region | Cost | Power/Health | Keywords | Text |
|---|---|---|---|---|---|
| Nimble Poro | Ionia | 1 | 1/1 | Quick Attack | — |
| Navori Conspirator | Ionia | 2 | 2/2 | Elusive | — |
| Greenglade Duo | Ionia | 2 | 2/1 | Elusive | — |
| Kinkou Lifeblade | Ionia | 4 | 2/3 | Lifesteal, Elusive | — |
| Inspiring Mentor | Ionia | 1 | 2/2 | — | Play: Grant an ally in hand +1\|+0. |
| Draven | Noxus | 3 | 3/3 | Quick Attack | When I'm summoned or strike: Create a Spinning Axe in hand. |

Note what the sample already shows: **a unit with no text at all is common**, and
several cards carry a keyword and nothing else. Vanilla combat is not a
simplification invented for the milestone — it is most of a real deck's bottom
half.

## The milestone-1 deck, which needs no card text

Two decks of vanilla bodies, one per seat, to prove the pairing and the strike
order. This is a *shape* rather than a card list, and it is deliberately made of
numbers rather than names so that nothing here can be subtly wrong about
somebody else's game.

- **12 templates, ×3 each, is 36** — near enough to 40, and it keeps the 3-copy
  rule that the real decks are built under.
- Costs 1 to 6, two templates per cost.
- Power and health from the sample above: a 1-cost is 1/1 or 2/1, a 2-cost is
  2/2 or 2/1, a 3-cost is 3/3, a 4-cost is 2/3 through 4/4, and a 6-cost is the
  fat one. **A body is worth roughly its cost in power plus health**, which is
  the only balance rule milestone 1 needs.
- No keywords, no text, no spells, no champions.

What that deck exercises, and nothing else: drawing at round start, mana rising
by one a round, playing a unit to the bench, the attack token alternating,
declaring an attack, blocking one to one, strikes resolving left to right,
unblocked attackers hitting the Nexus, and a Nexus at zero ending the game with
a winner — which is every rule in [rules.md](rules.md) that is not a keyword or
a spell.
