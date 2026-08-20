Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

The save button in chess is not great, it should just be in the same area as the how to play button. We need a more elegant way to have menus, possibly most games should just reserve a right-hand column for menu-stuff.

Runeterra wastes a lot of space on the left side where there is nothing. it's also missing a zone for the spellstack

When CTRL-hovering and scrolling the mouse it can be impossible to scroll few enough lines. For splendor it jumps from lines 1-59 to 80-120 or so, skipping the whole middle. It should only scroll by 6 lines per mouse wheel click.

Splendor: Many cards have an apology in the text, that seems like an artifact left over from development. Needs cleaning up.

Splendor: The cost shouldn't be part of the text, this makes it cumbersome to read. This should be displayed like we display stats. Possibly we can put the cost into a stat by default and then just refence it? Maybe have stats that are declared to be costs? Do we have a global stat registry where we can default behaviour of them? E.g. "stats: { name: mana, type: cost }" or similar? This needs some care on how we handle conflicts, where a stat could be both a cost and also have a different meaning. For example in MTG, "red mana" is usually a cost, but some cards can also give you red mana, or do something else with it.

Splendor: Prestige is important enough that it needs an icon, right?

Splendor looks: Instead of cards having their stats at the bottom, for splendor it would make a lot of sense if we could list them as a column on the card, and have icons or even coloured fonts. This would make the game read much better. Is there an elegant way to code that into the game.jsons?

Game menu: We need more than 1 line of games. The upper list should be "published games" and the lower list should be "proof of concept games".

Runeterra needs player cards for the nexus for both players which have their mana and their spell mana on it.
