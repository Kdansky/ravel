Scratch list. Anything here that turns out to be more than an afternoon gets
worked through in `ideas/` and taken off this list — this file is the inbox, not
the plan. `ideas/README.md` is the plan.

Remove fully completed entries when we have done them or moved them to other files to not waste time reading solved things. Strike-through is only useful if something is half-done.

## Open

**The zone-`applies` merge warning names the same tag twice.** When one tag's
`abilities` list has two entries both saying `merge: "this"`, the check at
`validate.lua:2375` sets `sole` from the *tag* while looping over its
*abilities*, so it reports "hands out 'for_sale' and 'for_sale'". The
contradiction it found is real — that pairing is only caught here, since a
zone-granted tag is not in the card's own `tags` — but the sentence sends the
author looking for a second tag that does not exist. Report the ability keys
when both come from one tag.
