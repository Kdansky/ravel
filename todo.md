Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

- **The log says `{name}`.** A seat renamed by `set_name` reads correctly on its
  card, in its tooltip and on the ending banner, because `label.fill` runs when
  a string is *drawn*. A log line is not drawn from anything: `flow` writes
  `log.add("Played " .. def.text)` and the finished string keeps the template, so
  `tooltip.lua`'s event-log card prints `{name} +1 mana` and `— {name} to play —`.
  Filling it at write time would defeat the whole point of [27]'s answer-when-drawn
  rule; filling it at read time needs the entity the line was about, which the log
  does not keep. Found by watching an engine-played Spellstorm seat.
