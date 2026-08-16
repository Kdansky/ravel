# Two decks

Reference material for [18](../18-legends-of-runeterra.md), beside
[rules.md](rules.md). Riot's card text and names are theirs — `CREDITS.md` is
where this repository records that, and a fan implementation of two decks
belongs in it.

**The card data is here.** `data/set1.json` and `data/set2.json` are Riot's own
Data Dragon files, checked in beside the rules they describe:

```sh
curl -sS -o ideas/lor/data/set1.json https://dd.b.pvp.net/latest/set1/en_us/data/set1-en_us.json
curl -sS -o ideas/lor/data/set2.json https://dd.b.pvp.net/latest/set2/en_us/data/set2-en_us.json
```

584 KB and 250 KB — small enough to keep, and pinned rather than fetched so a
deck list built from them is reproducible when the endpoint moves. One record per
card:

```
name · cost · attack · health · type · supertype · subtypes · rarity · collectible
keywords[] · descriptionRaw · levelupDescriptionRaw · regionRefs[] · spellSpeedRef · cardCode
```

`descriptionRaw` is the text without LoR's markup, and `levelupDescriptionRaw` is
a champion's level-up condition. Every card list below was read out of these
files rather than recalled.

---

## The deck that exists: Demacia / Freljord starter

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
of a search summary rather than off the card data now sitting in `data/`, so
count it again before building it.

## Milestone 1: the deck, out of real cards

Ten followers, Demacia and Freljord, every one of them **text-free** — read out
of `data/` with the query below, not chosen by hand:

| Cost | Card | Region | Body | Keywords |
|---|---|---|---|---|
| 1 | Plucky Poro | Demacia | 1/1 | Tough |
| 1 | Cithria of Cloudfield | Demacia | 2/2 | — |
| 2 | Vanguard Defender | Demacia | 2/2 | Tough |
| 2 | Vanguard Lookout | Demacia | 1/4 | — |
| 2 | Ruthless Raider | Freljord | 3/1 | Overwhelm, Tough |
| 3 | Loyal Badgerbear | Demacia | 3/4 | — |
| 3 | Mighty Poro | Freljord | 3/3 | Overwhelm |
| 4 | Bull Elnuk | Freljord | 4/5 | — |
| 5 | Vanguard Cavalry | Demacia | 5/5 | Tough |
| 6 | Alpha Wildclaw | Freljord | 7/6 | Overwhelm |

```sh
jq -r --argjson ok '["Tough","Overwhelm","Quick Attack","Lifesteal","Double Attack"]' \
  '.[] | select(.type=="Unit" and .collectible and .descriptionRaw=="" and .supertype==""
   and (.regionRefs[0] | IN("Demacia","Freljord")) and (.keywords - $ok | length == 0))
   | [.cost, .name, "\(.attack)/\(.health)", (.keywords|join(", "))] | @tsv' \
  ideas/lor/data/set1.json ideas/lor/data/set2.json | sort -n
```

The keyword filter is the load-bearing half. Without it the same query returns
fifteen cards, five of them carrying Challenger, Elusive, Scout, Barrier or
Regeneration — every one a rule about *who may block* or a trigger, which is
milestone 4 and later.

**Two keywords in the whole deck, and both are arithmetic**: *Tough* takes one
less damage from everything, *Overwhelm* sends damage past a dead blocker to the
Nexus. Neither changes **who may block whom**, which is the half that would ask
the lane model questions — Elusive, Fearsome and Challenger stay out until
milestone 4. This is the cheap half the ladder predicted, and it arrived without
being planned for: it is simply what a text-free unit looks like.

**A mirror match.** Both seats play the same ten templates. Two different decks
introduce a balance question that has nothing to do with what milestone 1 tests,
and a mirror makes an asymmetric result *evidence of a bug* rather than a matter
of opinion.

**Thirty cards, not forty.** Ten templates at the real 3-copy limit. The 40-card
minimum is a construction rule, and the only thing it touches here is how long it
takes to deck out — which milestone 1 does not test. Say it in the file rather
than padding with cards nobody chose.

### What was left out, and why

- **Champions** (Lucian, Tryndamere) are text-free in body and carry a level-up
  condition, which is a trigger. They land with [01](../01-boardgames.md) gap 5.
- **Every other region**: the same query over all seven yields 20 cards, and the
  rest are thin — Ionia 2, Noxus 2, Piltover & Zaun 3, Shadow Isles 1. Demacia
  and Freljord hold 12 of the 20 between them and are a legal two-region pair,
  which is why the mirror is built from those.
- **Only four collectible units in the whole of set1 have no keyword at all.**
  An earlier draft of this file said vanilla bodies were "most of a real deck's
  bottom half" — that was recollection and it was wrong. A unit with no *text* is
  common; a unit with no text and no keyword is nearly extinct.

What the deck exercises, and nothing else: drawing at round start, mana rising by
one a round, playing a unit to the bench, the attack token alternating, declaring
an attack, blocking one to one in six lanes, strikes resolving left to right,
Tough and Overwhelm as damage arithmetic, unblocked attackers hitting the Nexus,
and a Nexus at zero ending the game with a winner — which is every rule in
[rules.md](rules.md) that is not a spell, a trigger, or a rule about who may
block.
