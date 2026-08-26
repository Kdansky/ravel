Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

Puzzle strike: the bank should be where trashed cards go by default, in all cases — so if Argagarg's Bubble Shield takes a gem off a pile it goes back to the bank without extra logic. The zone half of this is done (`status: "supply"`, and moving a card into one already turns it back into stock); what is missing is the default destination, so nothing has to name the bank.

Puzzle strike: Kept back zone should be called "piggybank". The buttons for end turn and end action are too small (we could allow different card shapes or styles, such as "fill" and then two cards in one zone actually use the whole zone. Would look way better for this.

Puzzle strike: The stats on the top right are overlaid over one player's gem pile. That isn't very nice. It would be better if we could assign the stats window to any zone and it would be displayed there. In this case this would work perfectly for "played this turn" if right-aligned. Also it should not show 0 values (this should be a toggleable feature of whether we want to show 0 values)

Puzzle strike: Per the rules it is legal to buy multiple chips per round, not just one.

Puzzle strike: The bank draft screen shows all fifty-one plates in one offer, which is a lot of cards at once. It works, but it wants a layout of its own — and the draft buttons are two more small squares in a row that was already too small (see the button-size note above).

General: "Where" lists a bunch of requirements which are ANDed together, but sometimes we need an OR. How do we solve this? Multiple where clauses? Explicit OR syntax?
