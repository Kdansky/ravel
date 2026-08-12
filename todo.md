Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and struck off with a pointer — this file is the
inbox, not the plan. `ideas/README.md` is the plan.

## Worked through, see ideas/

- ~~Fix the run.sh script~~ — done (`3971317`).
- ~~Zone square lines invisible via tag; maybe an `invis` tag on everything~~ —
  [07 gap 4](ideas/07-presentation.md). One zone tag per piece of chrome, not
  one `invisible` meaning four things; a card's is refused, and the doc says why.
- ~~Enforce ratio of zones (chess must be square) when resizing~~ —
  [07 gap 5](ideas/07-presentation.md). `"ratio": 1` on the zone, largest rect
  of that shape inside the allotted one, slack centred.
- ~~A list of literally every tag or trait included by default~~ —
  [06 gap 4](ideas/06-schema-and-types.md). The document is the small half; the
  interesting half is warning on a *near-miss* tag, since a misspelled
  `activate` is a silently dead board today.
- ~~A base config json of non-obvious dynamic tags and patterns~~ and
  ~~game.json files including other game.json files~~ — both are
  [09](ideas/09-composition.md), and they are one feature: build `include`, and
  the base file is then just content. The trap is that the network ships *a
  file*, so includes must flatten before being sent or hashed.

## Open

Put the debug features (CTRL+hover) behind an explicit "enable debug" which is told to all players so that cheating can be seen more easily.

Consider instead of complex {stat "at_least": 8 } struct to just use small eval blocks, which look more like "a.b@c.d > e.f@g.h", allowing simple math and lookup logic. This might just be easier, and we can parse this on validation and generate lambda functions for it all instead of having to write unique special cases for every field type.



(nothing yet — add as it comes up)
