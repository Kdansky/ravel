# Where this came from

Everything in this directory describes **Legends of Runeterra**, which is Riot
Games'. Card names, card text, keywords and the rules themselves are theirs, and
nothing here is licensed to this repository — it is reference material for
building a fan implementation of a subset, kept beside the code that reads it so
that neither drifts from the other.

| What | Where it came from |
|---|---|
| `data/set1.json`, `data/set2.json` | Riot's Data Dragon, `https://dd.b.pvp.net/latest/set<n>/en_us/data/set<n>-en_us.json`, fetched 2026-08-16. Unmodified. |
| [rules.md](rules.md) | Written from the [League of Legends Wiki](https://wiki.leagueoflegends.com/en-us/Legends_of_Runeterra_(game)) and [gamepressure](https://www.gamepressure.com/legends-of-runeterra/turns-and-rounds-system/z0cf3d); each rule marks whether it was verified there or recalled. |
| [decks.md](decks.md) | Card lists read out of `data/` with the queries printed beside them. |

**No art.** The Data Dragon files name image URLs and this directory holds none
of them: a card here is a name, a cost, two numbers and a line of text, and the
implementation draws its own. `game/games/assets/CREDITS.md` is where art
provenance is recorded for the art this repository actually carries.
