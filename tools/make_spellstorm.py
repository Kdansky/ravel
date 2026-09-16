#!/usr/bin/env python3
"""Generate game/games/spellstorm.json.

Spellstorm (Keith Burgun, 2024): a tactical deckbuilding card game for 1-4
players. Eight asymmetrical wizards battle in four-round battles, then regroup
to score Storm Shards and buy a card. First to 8 Shards wins, or reduce the
opponent to 0 health.

Source notes, transcriptions and the art this file references are in
ideas/spellstorm/ -- README.md there indexes the rest. Every card's printed
text is quoted in its tooltip, so a rule that reads oddly can be checked
against the card without leaving the game.

About a hundred and eighty templates is far too many to hand-write and keep
consistent, so they are generated and the generator is checked in
(AUTHORING.md section 3, "Big decks").

    python3 tools/spellstorm_art.py    # the card faces, once
    python3 tools/make_spellstorm.py   # the game file

Where the engine cannot say what the card says, the tooltip says so in a
trailing "[Simplified: ...]" note and the deviation is listed in
ideas/spellstorm/09-engine-gaps.md. Nothing is silently wrong.
"""

import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfmt
import guard

# ---------------------------------------------------------------------------
# The vocabulary. Every card is written in terms of these, so a rule that
# appears on forty cards is spelled one way and can be corrected in one place.
# ---------------------------------------------------------------------------

MANA  = "stat_gain:mana@mine.player:1"
POWER = "stat_gain:power@mine.player:1"
DRAW  = "draw_from:mine.deck:mine.hand:1"
# **Healing is a moment with a name**, and the only one this game declares. The
# engine's own stat_gain is deliberately unwatchable, so a rule that answers
# healing -- Croh's Accursed -- needs the game to have said that healing is a
# thing that happens, as against a number going up. Every heal in the box goes
# through this verb, including the one Bunny hands his opponent.
HEAL  = lambda n: "heal:health@mine.player:%d" % n
# **Damage is three moments, and each one is a different sentence.**
#
# `hit` is a blow from across the table: declaring it is the whole of announcing
# it, so Omar's Dodge! answers `hit` and every card that deals one is answerable
# without writing a word on any of them. `hurt` is damage you do to yourself,
# which is a cost and not an attack -- nothing answers it, which is what keeps
# Dodge! from being revealed because the other player poked themselves.
#
# `wound` is what arrives once anything standing in front of it has taken its
# bite. Dodge! replaces the blow with a wound of the same size and the shifts that
# shrink it are about the wound: one verb would find the same rule again on the
# way down and the blow would never land.
DMG   = lambda n: "hit:health@opponent:%d" % n
SELF_DMG = lambda n: "hurt:health@mine.player:%d" % n
SHARD = lambda n: "stat_gain:shards@mine.player:%d" % n
# What a blow Dodge! has soaked does instead of landing: a wound of the same size,
# which the shifts are about, and the budget down by the size of the blow --
# stat_damage stops at the floor, so a blow bigger than what is left uses up the
# rest and no more.
SOAK  = ["wound:health@mine.player:amount", "stat_damage:guard@mine.traps:amount"]

# Initiative is one tracker, so taking it is two writes and there is no way to
# say it as one. Both spellings exist because both directions appear on cards.
GAIN_INIT = ["stat_set:initiative@mine.player:1", "stat_set:initiative@opponent:0"]
LOSE_INIT = ["stat_set:initiative@mine.player:0", "stat_set:initiative@opponent:1"]

HAS_INIT = "initiative@mine.player >= 1"
NO_INIT  = "initiative@mine.player <= 0"

# The junk piles are real stacks of six, so giving one is a draw off the pile
# and voiding one is a move back onto it -- which is what the rulebook says
# happens to a VOIDed ICE, and it means the piles run out on their own.
#
# Which the board has printed rules for, so each of these is two steps: the
# empty-pile rule first, then the draw. That order because a draw that takes the
# last card is not a draw from an empty pile, and only the second reading is the
# one the board means.
GIVE = lambda kind: ["activate_zone:rules:by_column:dry_give_%s" % kind,
                     "draw_from:%s_pile:enemy.discard:1" % kind]
GAIN_JUNK = lambda kind: ["activate_zone:rules:by_column:dry_take_%s" % kind,
                          "draw_from:%s_pile:mine.discard:1" % kind]

# "Discard a random card", which is a selection and a coin toss and nothing
# else: `random.` narrows a scope to one of whatever it named, and `move:` obeys
# it. Two cards is the line twice -- there is no count on a move, and doubling it
# is exactly what the rule says. Being a move rather than a draw, it fires the
# On Discard of whatever comes up, which is the point of it being a discard.
DISCARD_RANDOM = lambda who: "destroy:random.%s.hand" % who

# Offering the Storm Cloud. `show:` lends the real cards, so what comes back is
# the card that was on the shelf rather than a copy of it; the `chosen` block on
# each card says where its pick lands and refills the shelf behind it.
OFFER_CLOUD = "show:storm_cloud:optional"
# The same shelf, with no way out of the question. `[GAIN]` is optional wherever
# the rulebook does not say MUST, which is everywhere but Amber. An offer where
# nothing qualifies still does not open, so "must" cannot ask the impossible.
MUST_GAIN   = "show:storm_cloud"
OFFER_HAND  = "show:mine.hand:optional"
# The same question with no way out, which is how a card says "discard exactly
# N": N of these, one after the other. The offer queue holds them.
HAND_PICK   = "show:mine.hand"
# "From your hand or discard" is one place, because `held` is a word both
# zones wear: a scope's place half says it without a union anywhere.
OFFER_HELD  = "show:mine.held:optional"

# "Wizard Spell Cards can never be VOIDed for any reason" -- the rulebook says it
# twice, and the tag was on all sixteen of them with nothing reading it. Said on
# the asker rather than on the card because the offer is where the rule bites:
# `chosen.where` is what gates a pick, the same word Puzzle Strike protects its
# Puzzle chips with. Only the six offers that void out of a player's own cards
# need it -- nothing in the Storm Cloud is a Wizard Spell Card, and the junk
# piles are junk.
VOIDABLE = ["not_tagged:no_void@target"]

# The same two, narrowed to one kind of card. `<zone>.<tag>` is the engine's word
# for one place and one kind, and an element is a tag on every card, so "gain a
# Fire card" is a question about *which cards come up* -- which is what a scope
# says. What may be *taken* out of what came up is `chosen.where`, and it is a
# different question because it can ask about the player: your Tier is not a
# property of the card you are looking at.
#
# An offer with nothing in it does not open, so a card that wants a Fire card and
# finds none simply does nothing, which is what the printed card says.
OFFER_CLOUD_OF = lambda kind: "show:storm_cloud.%s:optional" % kind
OFFER_HAND_OF  = lambda kind: "show:mine.hand.%s:optional" % kind
REFILL_CLOUD = "draw_from:spellstorm_deck:storm_cloud:1"
TAKE_TO_HAND = ["move:target:mine.hand", REFILL_CLOUD]

# The [GAIN] icon in full: "May gain a card from the Storm Cloud of your Tier or
# lower, to hand" (02-icons), which the rulebook says twice over for the Regroup
# gain -- "you may only take a card at or below your Tier", and "gained cards go
# to your hand unless the card says otherwise".
#
# It is a `chosen.where` rather than a narrower scope because it is a fact about
# the *player*: no tag on the card being looked at could say whether it is at or
# below somebody's Tier. An offer where nothing qualifies does not open, so a
# [GAIN] with nothing takeable is a card that does nothing -- which is what "may"
# means. The three Essences say a Tier of their own ("any Tier I or II"), and
# Meteorite says "regardless of tier": those override this rather than add to it.
GAIN_TIER = ["tier@mine.player >= tier_req@target"]

FIRE, WATER, EARTH = "fire", "water", "earth"

# ---------------------------------------------------------------------------
# Cards
#
# One row per printed card. `cast` is what resolving it does; `cast2` and
# `cast3` are riders with an "if" in them, run as later steps so that a
# condition is read before the main effect has changed it. `disc` is the
# On Discard effect, run in the Regroup phase.
# ---------------------------------------------------------------------------

def card(key, name, element, tooltip, cast=(), cast2=None, cast3=None,
         disc=None, chosen=None, chosen_where=None, tier=None, kind="spell",
         flavour=None, simplified=None, asset=None, tags=(), comment=None, ult=False):
    return dict(key=key, name=name, element=element, tooltip=tooltip,
                cast=list(cast), cast2=cast2, cast3=cast3, disc=disc,
                chosen=chosen, chosen_where=chosen_where, tier=tier, kind=kind,
                flavour=flavour, simplified=simplified, asset=asset,
                tags=list(tags), comment=comment, ult=ult)


# --- The six-card starting deck -------------------------------------------

BASIC = [
    card("magicdart", "Magic Dart", FIRE, kind="basic", ult=True,
         tooltip="Gain 1 mana. If you have Initiative, deal 1 damage.",
         flavour="Fire magic is often banned from use in many parts of the world, due to its unpredictable nature.",
         cast=[MANA], cast2=(HAS_INIT, [DMG(1)])),
    card("block", "Block", WATER, kind="basic",
         tooltip="Gain Initiative. Heal 1 for every Fire card revealed this round.",
         flavour='"He just needs a little splash, is all he needs." - The Splashmaster',
         cast=GAIN_INIT + ["heal:health@mine.player:count:fire@battle"]),
    card("powergem", "Power Gem", EARTH, kind="basic",
         tooltip="Power up. You may gain a card from the Storm Cloud at or below your Tier; if you do, it goes to your discard. On discard: power up.",
         flavour="The golden gems of the Spell Storm take time to develop their power.",
         cast=[POWER, OFFER_CLOUD],
         chosen=["move:target:mine.discard", REFILL_CLOUD], chosen_where=GAIN_TIER,
         disc=[POWER]),
]

# --- The three Essence cards, seeded into the Storm Cloud at setup ---------
# Each voids itself and lets you take a card of its own element, at Tier I or II.
# Two different narrowings: the element decides which cards come up (a scope), the
# Tier decides which of them may be taken (a condition, because it is a number on
# the card rather than a kind).

ESSENCE = [
    card("fireessence", "Fire Essence", FIRE, kind="essence", tier=1,
         tooltip="Deal 1 damage. You may gain any Tier I or II Fire card in the Storm Cloud. VOID this.",
         flavour="Fire Magic is generally associated with destruction.",
         cast=[DMG(1), "move_to:void", OFFER_CLOUD_OF(FIRE)],
         chosen=TAKE_TO_HAND, chosen_where=["tier_req@target <= 2"]),
    card("wateressence", "Water Essence", WATER, kind="essence", tier=1,
         tooltip="Gain 1 mana. You may gain any Tier I or II Water card in the Storm Cloud. VOID this.",
         flavour="Water Magic is generally associated with healing.",
         cast=[MANA, "move_to:void", OFFER_CLOUD_OF(WATER)],
         chosen=TAKE_TO_HAND, chosen_where=["tier_req@target <= 2"]),
    card("earthessence", "Earth Essence", EARTH, kind="essence", tier=1,
         tooltip="Power up. You may gain any Tier I or II Earth card in the Storm Cloud. VOID this. On discard: power up.",
         flavour="Earth Magic is generally associated with building.",
         cast=[POWER, "move_to:void", OFFER_CLOUD_OF(EARTH)],
         chosen=TAKE_TO_HAND, chosen_where=["tier_req@target <= 2"],
         disc=[POWER]),
]

# --- The Spellstorm Deck ---------------------------------------------------

SPELLS = [
    # Fire
    card("fireball", "Fireball", FIRE, tier=1,
         tooltip="Deal 1 damage and gain an ASH. If you have Initiative, deal 2 more damage and lose Initiative.",
         flavour='It is customary to say "shaboom!" when one reveals the Fireball card.',
         cast=[DMG(1)] + GAIN_JUNK("ash"),
         cast2=(HAS_INIT, [DMG(2)] + LOSE_INIT)),
    card("fireball2", "Fireball II", FIRE, tier=3,
         tooltip="Deal 2 damage. If you have Initiative, deal 2 more damage.",
         flavour='It is customary to say "shaboom-ya!" when one reveals the Fireball II card.',
         cast=[DMG(2)], cast2=(HAS_INIT, [DMG(2)])),
    card("flame", "Flame", FIRE, tier=1, ult=True,
         tooltip="Deal 1 damage, then resolve and discard a different Fire card from your hand.",
         flavour="You need *magic* water to put a magical flame out.",
         cast=[DMG(1), OFFER_HAND_OF(FIRE)],
         chosen=["copy:target:activate", "destroy:target"]),
    card("heartgem", "Heart Gem", FIRE, tier=1, ult=True,
         tooltip="Heal 3 and gain a CURSE. On discard: take 1 damage.",
         flavour="The Heart Gem has surfaced and disappeared many times throughout history, bringing a deadly curse each time.",
         cast=[HEAL(3)] + GAIN_JUNK("curse"), disc=[SELF_DMG(1)]),
    card("lantern", "Lantern", FIRE, tier=1,
         tooltip="Gain 2 mana. If your opponent revealed Water, VOID this, gain a CURSE and take 1 damage.",
         flavour="Do not keep sentient fire spirits trapped in a lantern, for any reason.",
         cast=[MANA, MANA],
         cast2=("count:water@enemy.battle >= 1",
                ["move_to:void"] + GAIN_JUNK("curse") + [SELF_DMG(1)])),
    card("lavabat", "Lava Bat", FIRE, tier=1,
         tooltip="Gain 1 mana. You may move a card from your opponent's discard to your own. Gain Initiative.",
         flavour="Dangerous flaming bats have been known to fly out of the volcanic activity of the Spellstorm.",
         cast=[MANA] + GAIN_INIT + ["options:bat_take,bat_give:optional"],
         ),
    card("manafont", "Mana Font", FIRE, tier=1,
         tooltip="VOID a Water card in the Storm Cloud. If you did, gain 3 mana. On discard: take 1 damage and gain 1 mana.",
         flavour="While there are many theories, no one knows where the magic inside gems originally comes from.",
         cast=[OFFER_CLOUD_OF(WATER)],
         chosen=["move:target:void", REFILL_CLOUD, MANA, MANA, MANA],
         disc=[SELF_DMG(1), MANA]),
    # The one card in the box that waives a cost, and it needed no word for
    # waiving one: a cost is a map of what is owed, and the Ultimate is owed
    # two different ways. The wizard answers "resolving" twice -- once for
    # mana, once for the pass this card hands out -- and the player picks which
    # answer to give. Obsidian does its own announcing, because the [ULT] icon's
    # phase runs before a card resolves and the pass does not exist yet then.
    card("obsidian", "Obsidian", FIRE, tier=2,
         tooltip="Take 1 damage and lose 2 mana. If you did, you may cast your Ultimate here without paying its mana cost.",
         flavour='"Whenever I close my eyes, I see my twisted reflection in that black mirrored gem." - Unknown',
         cast=[SELF_DMG(1)],
         # "If you did" is asked before the mana goes, which is the only moment
         # that can tell two mana from none.
         cast2=("mana@mine.player >= 2",
                ["stat_damage:mana@mine.player:2",
                 "stat_gain:ult_free@mine.player:1", "emit:resolving"]),
         # And if there were not two, the mana still goes, whatever there was.
         cast3=("ult_free@mine.player <= 0", ["stat_damage:mana@mine.player:2"])),
    card("rapidfire", "Rapid Fire", FIRE, tier=2,
         tooltip="Draw a card. If you have Initiative, deal 2 damage and you may redraw this to your hand.",
         flavour="When going for a fire-based strategy, it's important to keep the pressure on.",
         cast=[DRAW], cast2=(HAS_INIT, [DMG(2), "options:rf_back:optional"])),
    # **A choice shown beside the cards it is about.** The three go to a zone
    # of their own rather than straight to the discard, which gives the set a
    # name to be counted and shown by -- and the other half of the "or" is a
    # card minted into that same zone, so one question holds all four and the
    # player reads the three before deciding. The minted card says what it is
    # worth in its own text: a card's text is filled like any label, so
    # "{stats.counted}" is the number written onto it a step earlier.
    card("ruby", "Ruby", FIRE, tier=1,
         tooltip="Discard the top 3 cards of your deck. Then either deal 1 damage per Fire card among them, or VOID one of them.",
         flavour="The popular trend of ruby-adorned garments was blamed for the Great Royal Ball Fire of 1976.",
         cast=["draw_from:mine.deck:sifting:3",
               "create:sifting:ruby_burn:1",
               "stat_set:counted@sifting.burn:count:fire@sifting",
               "show:sifting"],
         chosen=["activate_zone:rules:by_column:ruby_pick",
                 "purge:options.burn", "purge:sifting.burn",
                 "move:sifting:mine.discard"]),
    card("shockwave", "Shockwave", FIRE, tier=2,
         tooltip="Your opponent loses 2 Power Tokens and discards a card. You gain Initiative. Deal 1 damage.",
         flavour='The 1981 hit song "Shockwave" is often credited with creating the Bonepunk genre.',
         cast=["stat_damage:power@opponent:2",
               DISCARD_RANDOM("enemy")] + GAIN_INIT + [DMG(1)]),
    card("swampsilt", "Swamp Silt", FIRE, tier=1,
         tooltip="Draw a card. Whoever has Initiative loses it. Give your opponent a CURSE.",
         flavour="The Order's imperial land-grab has much to do with the increasing swampland in their territory.",
         cast=[DRAW] + GIVE("curse"),
         cast2=(HAS_INIT, LOSE_INIT), cast3=(NO_INIT, GAIN_INIT)),
    card("crossfire", "Crossfire", FIRE, tier=2,
         tooltip="If you have Initiative, deal 3 damage, lose Initiative, and put this in your opponent's discard.",
         flavour='"The first lesson in using fire magic always must be... how not to burn one\'s self." - B Underbrom, Professor of Fire Magic',
         cast2=(HAS_INIT, [DMG(3)] + LOSE_INIT + ["move_to:enemy.discard"])),

    # Water
    card("arctite", "Arctite", WATER, tier=3,
         tooltip="Draw 2 cards. Heal 2 and give an ICE.",
         flavour="Pirates have been known to smuggle large amounts of Arctite inside icebergs.",
         cast=[DRAW, DRAW, HEAL(2)] + GIVE("ice")),
    card("frostmagic", "Frost Magic", WATER, tier=1,
         tooltip="Heal 1. Lose 1 Power Token. Give your opponent an ICE.",
         flavour="The Azure Order was focused on water magic until the 1970s, when ice magic suddenly became far more popular.",
         cast=[HEAL(1), "stat_damage:power@mine.player:1"] + GIVE("ice")),
    card("iceflume", "Ice Flume", WATER, tier=2,
         tooltip="Give an ICE. You may VOID an ICE from your hand or discard. Gain Initiative.",
         flavour='"Watch your step!" - Unknown',
         cast=GIVE("ice") + GAIN_INIT + ["show:mine.held.ice:optional"],
         chosen=["move:target:ice_pile"]),
    # "Up to 2" is the question asked twice, and "1 for each Water" rides on
    # the answer: the rule is asked while the card picked is still lying in the
    # offer, which is the only moment it can be counted.
    card("lapis", "Lapis", WATER, tier=1,
         tooltip="Draw a card. You may discard up to 2 cards, and heal 1 for each Water card discarded.",
         flavour="Doctors throughout Omia have used Water Magic to heal the sick for generations.",
         cast=[DRAW, OFFER_HAND, OFFER_HAND],
         chosen=["activate_zone:rules:by_column:lapis_heal", "destroy:target"]),
    card("leap", "Leap", WATER, tier=2,
         tooltip="Gain Initiative and heal 1. If your opponent revealed Fire, you may VOID a card from your hand or discard.",
         flavour="Azure wizards historically specialized in Water Gems, but they have since taken others from throughout the globe.",
         cast=GAIN_INIT + [HEAL(1)],
         cast2=("count:fire@enemy.battle >= 1", [OFFER_HELD]),
         chosen=["move:target:void"], chosen_where=VOIDABLE),
    card("moonstone", "Moonstone", WATER, tier=3,
         tooltip="Heal 4. On discard: heal 2.",
         flavour="The rare and beautiful Moonstone is one of the most coveted in all of Omia.",
         cast=[HEAL(4)], disc=[HEAL(2)]),
    card("reflect", "Reflect", WATER, tier=2,
         tooltip="Draw a card, gain Initiative, heal 1. If your opponent revealed Fire, they take 2 damage.",
         flavour='"He just needs a little splash, is all he needs." - The Splashmaster',
         cast=[DRAW] + GAIN_INIT + [HEAL(1)],
         cast2=("count:fire@enemy.battle >= 1", [DMG(2)])),
    card("sapphire", "Sapphire", WATER, tier=1, ult=True,
         tooltip="Draw a card, heal 1, and gain an ASH.",
         flavour='Many of Omia\'s most impressive Wizards have a signature move, which some call an "Ultimate".',
         cast=[DRAW, HEAL(1)] + GAIN_JUNK("ash")),
    card("step", "Step", WATER, tier=1,
         tooltip="If you have Initiative, heal 1. Otherwise, gain Initiative. On discard: gain Initiative.",
         flavour="From the year 366-1182, the Water Kingdom reigned over much of the Eastern Continent.",
         cast2=(HAS_INIT, [HEAL(1)]), cast3=(NO_INIT, GAIN_INIT),
         disc=GAIN_INIT),
    card("twinsapphire", "Twin Sapphire", WATER, tier=2, ult=True,
         tooltip="Draw a card and heal 2.",
         flavour='"TWO sapphires?! Wow, thanks!" - Someone\'s son',
         cast=[DRAW, HEAL(2)]),
    card("ultimate", "Ultimate", WATER, tier=1, ult=True,
         tooltip="You may VOID an Earth card from your hand. If you did, gain 3 mana.",
         flavour='"He just needs a little splash, is all he needs." - The Splashmaster',
         cast=[OFFER_HAND_OF(EARTH)],
         chosen=["move:target:void", MANA, MANA, MANA], chosen_where=VOIDABLE),
    card("wave", "Wave", WATER, tier=2,
         tooltip="Gain 3 mana. Your opponent discards their hand and draws a new hand of 4 cards.",
         flavour="A wave does not ask what it washes away.",
         cast=[MANA, MANA, MANA, "destroy:enemy.hand",
               "draw_from:enemy.deck:enemy.hand:4"]),

    # Earth
    # Two questions from one card, which the offer queue holds one at a time --
    # and the only [GAIN] in the box that says MUST, so neither may be declined.
    card("amber", "Amber", EARTH, tier=1,
         tooltip="Power up. You must gain two cards from the Storm Cloud at or below your Tier. On discard: power up.",
         flavour="The Business Demons considered drilling operations at the Spellstorm, but it was deemed too costly.",
         cast=[POWER, MUST_GAIN, MUST_GAIN], chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER, disc=[POWER]),
    card("bloodstone", "Bloodstone", EARTH, tier=1,
         tooltip="Gain 1 mana. Take 1 damage. You may VOID a card from your hand or discard. On discard: gain 1 mana.",
         flavour='"It\'s best to leave gems that you find in the wild alone, unless you really know what you\'re doing." - Abragail',
         cast=[MANA, SELF_DMG(1), OFFER_HELD],
         chosen=["move:target:void"], chosen_where=VOIDABLE, disc=[MANA]),
    # Three questions, each of which has to be answered. `chosen` is one block
    # per card, so an offer cannot carry its own count -- but it does not need
    # one: three mandatory offers in a row *are* "discard exactly 3", and the
    # gate is read once, before the first of them opens, so the hand emptying
    # under the questions cannot close the ones that are still queued.
    card("diamond", "Diamond", EARTH, tier=1,
         tooltip="If you hold 3 or more other cards, discard 3 of them and power up 3 times. On discard: power up.",
         flavour='"Learned more spells in 1 day at the Spellstorm, than I had in the past 3 years." - Azura Spellstorm Scholar',
         cast2=("count:spell@mine.hand >= 3",
                [POWER, POWER, POWER, HAND_PICK, HAND_PICK, HAND_PICK]),
         chosen=["move:target:mine.discard"],
         disc=[POWER]),
    card("meteorite", "Meteorite", EARTH, tier=1,
         tooltip="Take 1 damage. You may resolve any card in the Storm Cloud regardless of tier, then VOID it. On discard: take 1 damage.",
         flavour='"Mom! Look! This fell from the sky!" - A child of Tiya Bannet',
         cast=[SELF_DMG(1), OFFER_CLOUD],
         chosen=["move:target:void", "copy:target:activate", REFILL_CLOUD],
         disc=[SELF_DMG(1)]),
    card("opal", "Opal", EARTH, tier=3,
         tooltip="Draw a card, power up twice, gain 2 mana, and you may gain a card from the Storm Cloud at or below your Tier. On discard: power up twice.",
         flavour="Gems are rocks found deep in the earth that are charged with mysterious power.",
         cast=[DRAW, POWER, POWER, MANA, MANA, OFFER_CLOUD],
         chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER, disc=[POWER, POWER]),
    card("quake", "Quake", EARTH, tier=1,
         tooltip="Your opponent loses 2 Power Tokens and gains an ASH. You may gain a card from the Storm Cloud at or below your Tier. On discard: power up.",
         flavour="A huge earthquake that happened in 1951 is attributed to the emergence of the Business Demons.",
         cast=["stat_damage:power@opponent:2"] + GIVE("ash") + [OFFER_CLOUD],
         chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER, disc=[POWER]),
    card("shatter", "Shatter", EARTH, tier=2,
         tooltip="You may VOID up to 2 cards from your hand, and power up for each. On discard: power up.",
         flavour='"That there spellstorm water\'s FULL-a gold, I tell ya!" - Prospector',
         cast=[OFFER_HAND, OFFER_HAND], chosen=["move:target:void", POWER],
         chosen_where=VOIDABLE, disc=[POWER]),
    # Looking at cards without holding them is what `sifting` is for. The pick
    # goes back last and a deck takes a card on top, so the card you name is the
    # one you draw next and the other sits under it -- which is the whole of "in
    # any order" for two cards. Leaving them alone is choosing the one that was
    # already on top, so the question needs no way out.
    card("sift", "Sift", EARTH, tier=1,
         tooltip="Power up. Look at the top 2 cards of your deck and put them back in any order: the one you pick is the one you draw next.",
         flavour="Almost all Earth cards have discard effects.",
         cast=[POWER, "draw_from:mine.deck:sifting:2", "show:sifting"],
         chosen=["move:sifting:mine.deck", "move:target:mine.deck"]),
    card("spiritcrystal", "Spirit Crystal", EARTH, tier=1,
         tooltip="Draw a card. Reveal an Earth card from your hand, resolve it and then discard it. On discard: power up.",
         flavour="It's said that Earth magic is the oldest form of magic, which is why so many stones are imbued with powers.",
         cast=[DRAW, OFFER_HAND_OF(EARTH)],
         chosen=["copy:target:activate", "destroy:target"],
         disc=[POWER]),
    card("threepower", "Three Power", EARTH, tier=2,
         tooltip="Power up twice and you may gain a card from the Storm Cloud at or below your Tier. If anyone revealed Water, power up again. On discard: power up twice.",
         flavour='When you see the "Gain Card" icon on a card, keep in mind that you may choose not to gain a card.',
         cast=[POWER, POWER, OFFER_CLOUD],
         cast2=("count:water@battle >= 1", [POWER]),
         chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER, disc=[POWER, POWER]),
    card("twopower", "Two Power", EARTH, tier=1,
         tooltip="Power up twice and you may gain a card from the Storm Cloud at or below your Tier. On discard: power up twice.",
         flavour='When you see the "Gain Card" icon on a card, keep in mind that you may choose not to gain a card.',
         cast=[POWER, POWER, OFFER_CLOUD],
         chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER, disc=[POWER, POWER]),
]

# --- Special cards: the three junk piles and the five Dragons -------------
# ICE, ASH and CURSE cannot be played. They carry no `playable` stat, which is
# what the hand's play block tests, so they sit in a hand doing nothing but
# blocking a Blast Score -- exactly what they are for.

JUNK = [
    card("ice", "Ice", WATER, kind="junk",
         tooltip="This can't be played. On discard during Regroup: -1 to your Blast Score.",
         flavour='"Ice cut into a cube shape is kind of like a gem." - Beosnook',
         disc=["stat_gain:ice_pen@mine.player:1"], tags=["junk", "ice"]),
    card("ash", "Ash", EARTH, kind="junk",
         tooltip="This can't be played. On discard: lose 1 Power Token.",
         flavour="The Spellstorm is a highly volcanic area, often covered in ash.",
         disc=["stat_damage:power@mine.player:1"], tags=["junk", "ash"]),
    card("curse", "Curse", FIRE, kind="junk",
         tooltip="This can't be played. On discard: take 1 damage.",
         flavour='"Curses!" - H.M.T. Holliganger, Distinguished Professor at the Azura Academy School of Archaeology',
         disc=[SELF_DMG(1)], tags=["junk", "curse"]),
]

DRAGONS = [
    card("firedragon", "Fire Dragon", FIRE, tier=4, kind="dragon", ult=True,
         tooltip="Deal 4 damage. Gain 2 mana.",
         flavour="No Dragon is more feared than the destructive and terrible Fire Dragon.",
         cast=[DMG(4), MANA, MANA]),
    card("winddragon", "Wind Dragon", FIRE, tier=4, kind="dragon", ult=True,
         tooltip="Gain Initiative. Gain a Storm Shard. You may resolve a card from your hand.",
         flavour="The elusive Storm Dragons were considered to be cryptids until very recently.",
         cast=GAIN_INIT + [SHARD(1), OFFER_HAND, OFFER_HAND],
         # A resolved card goes to the discard pile like any other, so the On
         # Discard it fires there is meant to fire.
         chosen=["copy:target:activate", "destroy:target"]),
    card("icedragon", "Ice Dragon", WATER, tier=4, kind="dragon", ult=True,
         tooltip="Heal 3. Gain a Storm Shard. Give an ICE.",
         flavour="The elusive Storm Dragons were considered to be cryptids until very recently.",
         cast=[HEAL(3), SHARD(1)] + GIVE("ice")),
    card("stormdragon", "Storm Dragon", WATER, tier=4, kind="dragon", ult=True,
         tooltip="Deal 3 damage and gain a Storm Shard.",
         flavour="The elusive Storm Dragons were considered to be cryptids until very recently.",
         cast=[DMG(3), SHARD(1)]),
    card("earthdragon", "Earth Dragon", EARTH, tier=4, kind="dragon", ult=True,
         tooltip="You may gain two cards from the Storm Cloud at or below your Tier. Deal 2 damage. Gain a Storm Shard. Your opponent gains an ASH.",
         flavour="The Earth Dragons are known to hoard massive amounts of treasure in caves.",
         cast=[DMG(2), SHARD(1)] + GIVE("ash") + [OFFER_CLOUD, OFFER_CLOUD],
         chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER),
]

# ---------------------------------------------------------------------------
# Weather
#
# One card is flipped at the start of each round and every player resolves it.
# Three moments: `wx` at the flip, `wy` at the reveal -- which is what lets "if
# you reveal Fire this round" be asked at all, since at flip time nobody has
# played anything yet -- and `wz` once both cards have resolved, which is where a
# card that adds something *after* the round's work goes. Each is an ability with
# that key, walked once per seat by a phase of its own.
# ---------------------------------------------------------------------------

def weather(key, name, tooltip, wx=(), wy=None, wz=(), calm=False, copies=1,
            simplified=None, chosen=None, chosen_where=None):
    return dict(key=key, name=name, tooltip=tooltip, wx=list(wx), wy=wy,
                wz=list(wz), calm=calm, copies=copies, simplified=simplified,
                chosen=chosen, chosen_where=chosen_where)

REVEALED = lambda el: "count:%s@mine.battle >= 1" % el

WEATHER = [
    # The eight Calm Before the Storm cards, which sit on top of the deck so
    # the first two battles are gentle.
    weather("nice_breeze", "Nice Breeze", "Draw a card, gain 1 mana, power up.",
            wx=[DRAW, MANA, POWER], calm=True),
    weather("crystalflurries", "Crystal Flurries",
            "Draw a card and gain 1 mana. If you reveal Water this round, gain 1 mana.",
            wx=[DRAW, MANA], wy=(REVEALED(WATER), [MANA]), calm=True, copies=2),
    weather("heatwave", "Heatwave",
            "Draw a card. If you reveal Fire this round, gain 1 mana.",
            wx=[DRAW], wy=(REVEALED(FIRE), [MANA]), calm=True),
    weather("fallingearth", "Falling Earth",
            "Draw a card. If you reveal Earth this round, power up.",
            wx=[DRAW], wy=(REVEALED(EARTH), [POWER]), calm=True),
    weather("dustcloud", "Dust Cloud",
            "Draw a card, power up. All players discard a card.",
            wx=[DRAW, POWER, DISCARD_RANDOM("mine")], calm=True),
    # The card the offer queue was built for. The weather phase already runs a
    # weather card's `wx` once per seat, so the offer is written once and every
    # seat is asked in turn: the second ask waits rather than tipping its shelf
    # into the first one's.
    weather("fallingstar", "Falling Star",
            "Draw a card. Every player may gain a card from the Storm Cloud at or below their Tier.",
            wx=[DRAW, OFFER_CLOUD],
            chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER, calm=True),
    weather("strange_weather", "Strange Weather",
            "Draw 2 cards. Discard the next card in the Weather Deck.",
            wx=[DRAW, DRAW], calm=True),

    # The sixteen standard cards.
    weather("burningblizzard", "Burning Blizzard",
            "Draw a card. If you reveal Fire this round, gain 2 mana.",
            wx=[DRAW], wy=(REVEALED(FIRE), [MANA, MANA])),
    # An Ultimate is a reaction to one of your own cards announcing that it is
    # resolving, so a round in which anybody may cast one is a round in which
    # something else does the announcing. That is this card: once both spells
    # have resolved it says the same word they say, once per player, and each
    # wizard answers their own. The mana is still owed, because the cost is on
    # the reaction and nothing here waives it.
    weather("energywave", "Energy Wave",
            "Draw a card. Once both cards have resolved, each player may cast their Ultimate.",
            wx=[DRAW], wz=["emit:resolving"], copies=2),
    weather("gemlightomen", "Gemlight Omen",
            "Draw a card. Tier II players gain 1 mana; Tier I players power up 3 times.",
            wx=[DRAW]),
    weather("glitteringdust", "Glittering Dust",
            "Draw 2 cards. Earth cards do nothing when resolved but heal 2.",
            simplified="the replacement of every Earth card's effect is a continuous effect the engine has no way to express; this only draws",
            wx=[DRAW, DRAW]),
    weather("ionicatmosphere", "Ionic Atmosphere",
            "Draw 2 cards and gain 1 mana. Tier II and III players lose 2 Power Tokens.",
            wx=[DRAW, DRAW, MANA], copies=2),
    weather("lightningstrike", "Lightning Strike!",
            "Draw a card and gain 1 mana. Players with more than 8 health take 1 damage.",
            wx=[DRAW, MANA]),
    weather("magneticwarp", "Magnetic Warp",
            "Draw 2 cards. VOID all cards in the Storm Cloud and draw out 5 new ones.",
            wx=[DRAW, DRAW], copies=2),
    weather("rainoftoads", "Rain of Toads",
            "Draw a card. Whoever has Initiative loses it; whoever gains it gains a CURSE and 1 mana.",
            wx=[DRAW]),
    weather("shootingstar", "Shooting Star", "Draw 2 cards and power up twice.",
            wx=[DRAW, DRAW, POWER, POWER]),
    # The other card the offer queue was built for, and the one that needed it
    # most: every player is asked, and the answer is a card out of a hand nobody
    # else may read. VOIDed junk goes back on its own pile rather than into the
    # VOID -- that is what the piles running dry is about -- and which pile
    # depends on what was picked, so the three moves are written out and two of
    # them find nothing. The pick is the only card left in the offer by the time
    # these run; the rest has already gone home.
    weather("soothingrain", "Soothing Rain",
            "Draw a card. You may VOID an ASH, CURSE or ICE from your hand or discard pile.",
            wx=[DRAW, "show:mine.held.junk:optional"],
            chosen=["move:options.ice:ice_pile", "move:options.ash:ash_pile",
                    "move:options.curse:curse_pile"], copies=2),
    weather("tidalwave", "Tidal Wave",
            "Draw 2 cards and gain 1 mana. All players discard 2 cards.",
            wx=[DRAW, DRAW, MANA, DISCARD_RANDOM("mine"), DISCARD_RANDOM("mine")]),
    weather("wildcolorwinds", "Wildcolor Winds",
            "Draw a card. All players draw a card from the Spellstorm Deck into their discard.",
            wx=[DRAW, "draw_from:spellstorm_deck:mine.discard:1"]),
]

# A handful of weather cards ask a question of the player's Tier or health, and
# those are riders on the flip step rather than one line, so they live here.
WEATHER_RIDERS = {
    "gemlightomen": [("tier@mine.player == 2", [MANA]),
                     ("tier@mine.player <= 1", [POWER, POWER, POWER])],
    "ionicatmosphere": [("tier@mine.player >= 2", ["stat_damage:power@mine.player:2"])],
    "lightningstrike": [("health@mine.player >= 9", [SELF_DMG(1)])],
    "magneticwarp": [(HAS_INIT,
                      ["move:storm_cloud:void",
                       "draw_from:spellstorm_deck:storm_cloud:5"])],
    "rainoftoads": [(NO_INIT, GAIN_INIT + GAIN_JUNK("curse") + [MANA])],
    # Both of these act on the shared table, so they are hung on the seat with
    # Initiative -- weather is walked once per seat and would otherwise fire twice.
    "strange_weather": [(HAS_INIT, ["draw_from:weather_calm:weather_discard:1"])],
}

# Oren's Chemistry Board holds three beakers, and *Unstable Formula* pours two
# out of one into another. Which pair is the player's to choose, so the six pairs
# are dealt as an offer -- and each entry carries its own rule, which is what an
# `options:` entry is for: the beaker has to hold two before it can lose two.
SWAPS = [(a, b) for a in (FIRE, EARTH, WATER) for b in (FIRE, EARTH, WATER) if a != b]
OFFER_SWAP = "options:" + ",".join("pour_%s_%s" % (a, b) for a, b in SWAPS) + ":optional"


# **"A or B" is an offer of two, and the two are cards.** `options:` deals one
# entry per branch, each carrying what that branch does -- and, since a dealt
# entry's own `needs` is read, each carrying whether it is on the table at all.
# A branch that asks a question of its own asks it from the entry, whose `chosen`
# answers it: the asker is the card standing in the offer, not the card that
# dealt it.
# "If you still have 2 Energy Tokens" is asked after the branch has spent what it
# spends, so it cannot live on the card: an offer written into a cast is split out
# to run last, which is what keeps every other rider here from reading a hand that
# has been lent to a question. An if lives in an ability, and the branches call it.
BREACH = "activate_zone:rules:by_column:breach"


def choice_templates():
    def entry(key, text, tooltip, action, needs=None, chosen=None, where=None,
              stats=None, tags=()):
        t = {"key": key, "text": text, "tags": ["immutable"] + list(tags),
             "asset": "auto", "tooltip": tooltip, "play": {"action": list(action)}}
        if stats: t["card_stats"] = dict(stats)
        if needs: t["play"]["needs"] = list(needs)
        if chosen:
            t["chosen"] = {"action": list(chosen)}
            if where: t["chosen"]["where"] = list(where)
        return t

    return [
        # Omar's Hidden Movement: "return a card from your discard to your hand
        # OR draw". It did both for a long time, which is a different card.
        entry("omar_recall", "Take a card back",
              "Return a card from your discard to your hand.",
              ["show:mine.discard:optional"],
              needs=["count:spell@mine.discard >= 1"],
              chosen=["move:target:mine.hand"]),
        entry("omar_draw", "Draw instead", "Draw a card.", [DRAW]),

        # Croh's DOOOOOOOOOM!, one token's worth: "a card of your choice from
        # your discard, OR draw". The choice is per token, so the Ultimate asks
        # it as many times as he has tokens -- four rules cards, one per token,
        # each gated on holding that many.
        entry("croh_take", "Take a card back",
              "Return a card of your choice from your discard to your hand.",
              ["show:mine.discard:optional"],
              needs=["count:spell@mine.discard >= 1"],
              chosen=["move:target:mine.hand"]),
        entry("croh_draw", "Draw instead", "Draw a card.", [DRAW]),

        # Rapid Fire's "you may redraw this". A cost is one map settled in full,
        # so a part you may decline is an offer -- of one, with a No button.
        entry("rf_back", "Take Rapid Fire back",
              "Return Rapid Fire to your hand.", ["move:target:mine.hand"]),

        # May's Void Traveler: "a non-Wizard card from your hand, or any card in
        # the VOID". Only the VOID half was built.
        entry("may_hand", "From your hand",
              "Resolve a non-Wizard card from your hand, then put it on the bottom of the Spellstorm Deck.",
              ["show:mine.hand:optional"],
              needs=["count:spell@mine.hand >= 1"],
              chosen=["move:target:spellstorm_deck:bottom", "copy:target:activate"],
              where=["not_tagged:wizard_spell@target"]),
        entry("may_void", "From the VOID",
              "Resolve a card in the VOID, then put it on the bottom of the Spellstorm Deck.",
              ["show:void:optional"],
              needs=["count:spell@void >= 1"],
              chosen=["move:target:spellstorm_deck:bottom", "copy:target:activate"]),

        # Lava Bat: "from any discard to any other discard", which with two
        # players is two directions and so two entries. The card that moves
        # changes hands as well as places -- a card dealt into a seat's deck is
        # stamped with that seat, and one carrying the old name would go home to
        # the wrong discard the next time it was thrown away.
        entry("bat_take", "Take one of theirs",
              "Move a non-Wizard Fire card from your opponent's discard to yours.",
              ["show:enemy.discard.fire:optional"],
              needs=["count:fire@enemy.discard >= 1"],
              chosen=["set_owner:target:mine.player", "move:target:mine.discard"],
              where=["not_tagged:wizard_spell@target"]),
        entry("bat_give", "Give one of yours",
              "Move a non-Wizard Fire card from your discard to your opponent's.",
              ["show:mine.discard.fire:optional"],
              needs=["count:fire@mine.discard >= 1"],
              chosen=["set_owner:target:opponent", "move:target:enemy.discard"],
              where=["not_tagged:wizard_spell@target"]),

        # Ruby's "OR", standing in the same question as the three cards it is
        # an alternative to. It is picked like any of them, and the rule that
        # runs afterwards tells it apart by the tag it wears. `{stats.counted}`
        # is the damage, written onto it before the question opened -- a card's
        # text is filled like any other label, so the choice says what it is
        # worth rather than making the player count Fire icons.
        entry("ruby_burn", "Deal {stats.counted} damage",
              "Deal 1 damage for each Fire card among the three. Take one of the cards beside this instead to VOID that card.",
              [], stats={"counted": 0}, tags=["burn"]),

        # May's Data Breach: "lose 1 or 2 Energy Tokens, and power up that many
        # times". The card read the 2 as a gate rather than as a choice.
        entry("may_lose1", "Lose 1 Energy", "Lose 1 Energy Token and power up.",
              ["stat_damage:energy@mine.player:1", POWER, BREACH],
              needs=["energy@mine.player >= 1"]),
        entry("may_lose2", "Lose 2 Energy", "Lose 2 Energy Tokens and power up twice.",
              ["stat_damage:energy@mine.player:2", POWER, POWER, BREACH],
              needs=["energy@mine.player >= 2"]),
    ]


def trap_templates():
    """Omar's Traps: a card held face down that answers a moment of its own."""
    def trap(key, name, tooltip, to, whose, needs, action):
        return {
            "key": key, "text": name, "asset": "auto", "tags": ["trap"],
            "tooltip": tooltip,
            "card_stats": {"sprung": 0, "guard": 0},
            # A Trap is revealed *by its holder*, after the trigger, or not at
            # all -- so it is a reaction and not a rule about the moment. `in`
            # names the zone it answers from, which is what makes a Trap that
            # has been swapped back onto its pile inert without saying so.
            "reactions": [{
                "to": to, "whose": whose, "in": "traps",
                "needs": ["sprung@self <= 0"] + list(needs),
                "action": ["stat_set:sprung@self:1"] + list(action)}],
        }

    def counter_trap(key, name, tooltip, element, action):
        return trap(key, name, tooltip, "countered", "mine",
                    ["count:%s@mine.battle >= 1" % element], action)

    return [
        counter_trap("trap_mud", "Mud Trap",
                     "Reveal when you counter with a Fire card: deal 1 damage, gain 1 mana and gain Initiative.",
                     FIRE, [DMG(1), MANA] + GAIN_INIT),
        counter_trap("trap_ice", "Ice Bomb",
                     "Reveal when you counter with a Water card: give an ICE, gain 1 mana, and you may cast your Ultimate.",
                     WATER, GIVE("ice") + [MANA, "emit:resolving"]),
        # The budget is written on the Trap itself, because the Trap is where a
        # player can see it and because it goes when the Trap does. `whose` is
        # what says "an opponent is dealing damage to you": the announcement is
        # somebody else's, and every blow aimed at the other seat is aimed at
        # this one.
        trap("trap_dodge", "Dodge!",
             "Reveal when an opponent deals damage to you: the first 2 points of damage you take this round are negated.",
             "hit", "enemy", [], ["stat_set:guard@self:2"]),
    ]


def swap_templates():
    # A beaker with less than two in it cannot pour two, and the entry says so
    # itself: a dealt option's own `needs` gates whether it may be picked, so a
    # pour there is no room for is offered greyed out rather than offered and
    # then doing nothing.
    return [{"key": "pour_%s_%s" % (a, b), "text": "%s down, %s up" % (a.title(), b.title()),
             "tags": ["immutable"], "asset": "auto",
             "tooltip": "Lower your %s beaker by 2 to raise your %s beaker by 2. "
                        "Needs 2 in the %s beaker." % (a.title(), b.title(), a.title()),
             "play": {"needs": ["%s_el@mine.player >= 2" % a],
                      "action": ["stat_damage:%s_el@mine.player:2" % a,
                                 "stat_gain:%s_el@mine.player:2" % b]}}
            for a, b in SWAPS]


# ---------------------------------------------------------------------------
# Wizards
#
# Each is a character card that sits in the player's wizard zone carrying the
# Ultimate, two Wizard Spell Cards shuffled into the starting deck, and a
# chooser card that configures the seat when it is picked.
# ---------------------------------------------------------------------------

def wizard(key, name, epithet, elements, health, rating, ult_cost, ult_name,
           ult_tooltip, ult_action, spells, start=(), ult_chosen=None,
           ult_chosen_where=None, passive=None, keywords=(), max_health=None,
           simplified=None, blurb="", ult_compute=()):
    return dict(key=key, name=name, epithet=epithet, elements=elements,
                health=health, rating=rating, ult_cost=ult_cost,
                ult_name=ult_name, ult_tooltip=ult_tooltip,
                ult_action=list(ult_action), ult_chosen=ult_chosen,
                ult_chosen_where=ult_chosen_where,
                passive=passive, keywords=list(keywords), spells=spells,
                max_health=max_health or health,
                start=list(start), simplified=simplified, blurb=blurb,
                ult_compute=list(ult_compute))


WIZARDS = [
    wizard("derby", "Derby Pocket", "Infernal Intern", "Fire, Earth", 13, 3, 6,
           "Flaming Yardstick",
           "Deal 2 damage. If you have an odd number of health, gain 2 mana.",
           [DMG(2), "stat_gain:mana@mine.player:yardstick_mana"],
           ult_compute=["yardstick_mana"],
           blurb="An ex-Business Demon intern who loves to encourage others. Strong early, and gains power passively. A good all-rounder.",
           start=["move:storm_cloud.earth_essence:mine.discard", REFILL_CLOUD],
           spells=[
               card("derby_coffee", "Coffee Run", EARTH, kind="wizard_spell", ult=True,
                    tooltip="Power up twice and you may gain a card from the Storm Cloud at or below your Tier. If you gained an Earth card, gain Initiative.",
                    flavour='"This is gonna be the best coffee run of all time!"',
                    cast=[POWER, POWER, OFFER_CLOUD],
                    chosen=["activate_zone:rules:by_column:coffee"] + TAKE_TO_HAND,
                    chosen_where=GAIN_TIER),
               card("derby_reckless", "Reckless Charge", FIRE, kind="wizard_spell", ult=True,
                    tooltip="Gain 1 mana and power up. Deal 1 damage. Gain an ASH. If you have Initiative, deal 1 more damage.",
                    flavour='"I know we can do it if we work together!"',
                    cast=[MANA, POWER, DMG(1)] + GAIN_JUNK("ash"),
                    cast2=(HAS_INIT, [DMG(1)])),
           ]),

    wizard("eve", "Eve Williams", "Radical Activist", "Fire, Water", 14, 5, 5,
           "Doom Bauble",
           "Draw 2 cards. You may move a CURSE or an ICE from your hand or discard to your opponent's discard.",
           [DRAW, DRAW, "show:mine.held.curse_or_ice:optional"],
           ult_chosen=["move:target:enemy.discard"],
           blurb="A radical activist who loves to blow things up. Aggressive, and can really mess up her opponent's deck.",
           start=GIVE("ice") + GAIN_JUNK("ice"),
           spells=[
               card("eve_facepunch", "Face Punch", WATER, kind="wizard_spell", ult=True,
                    tooltip="Gain Initiative. Steal 1 mana from your opponent and they discard a card.",
                    flavour='"We use voices to avoid having to use fists. We use fists to avoid having to use bombs."',
                    cast=GAIN_INIT + ["stat_damage:mana@opponent:1", MANA,
                                      DISCARD_RANDOM("enemy")]),
               card("eve_riot", "Riot", FIRE, kind="wizard_spell", ult=True,
                    tooltip="Discard your hand without triggering any discard effects. Deal 1 damage per Earth card discarded. Draw 2 cards.",
                    flavour='"Destroying the Omni-Gem was only the first step in our struggle against colonial oppression."',
                    comment="The two moves are one discard, and the detour is the whole of \"without triggering any discard effects\". An On Discard fires on a card going from a hand to a discard; leaving a hand for the quiet is not that, and leaving the quiet for a discard is not either. The cards are there for the length of one step and this is the only card in the box that needs it.",
                    cast=["hit:health@opponent:count:earth@mine.hand",
                          "move:mine.hand:quiet", "move:quiet:mine.discard", DRAW, DRAW]),
           ]),

    wizard("abra", "Abragail", "Professor of Magical Chemistry", "Water, Earth", 16, 7, 4,
           "Level Up!",
           "Put one of your six Research Tokens on any empty space of your journal. Every"
           " researched space fires at the start of each battle.",
           ["show:rules.jspace:optional"],
           # The eight spaces are already cards, sitting in the rules zone, so the
           # offer lends the real ones rather than dealing copies of them: the
           # player picks the space itself. `where` carries both halves of "an
           # empty space, while she has tokens left" -- neither is a property of
           # the card alone, which is what `chosen.where` is for.
           ult_chosen=["stat_set:researched@target:1",
                       "stat_gain:research@mine.player:1"],
           ult_chosen_where=["researched@target <= 0", "research@mine.player <= 5"],
           blurb="A professor at Azura Academy who levels up her magic as the game goes on. Great for players who like to plan.",
           spells=[
               card("abra_deepgems", "Deep Gems", WATER, kind="wizard_spell", ult=True,
                    tooltip="Draw a card and gain 1 mana. You may lose 1 Power Token to resolve and then VOID a Water card from the Storm Cloud.",
                    flavour="The Water Kingdom's dominance was possible, in part, due to their ability to dredge resources from the deep.",
                    # "You *may* lose a Power Token to ..." is a price on the
                    # answer, and `chosen` has no cost -- so the gate is the
                    # `where` and the payment is the first thing the answer does.
                    # Nothing is owed for declining, which the optional offer
                    # already says.
                    cast=[DRAW, MANA, OFFER_CLOUD_OF(WATER)],
                    chosen=["stat_damage:power@mine.player:1",
                            "move:target:void", "copy:target:activate", REFILL_CLOUD],
                    chosen_where=["power@mine.player >= 1"]),
               # Three questions about one shelf, and two different things to do
               # with the answer -- which one `chosen` block cannot say. So the
               # VOIDs are asked by the rule that is about VOIDing: a card that
               # asks owns the answer, and a second asker is a second answer. The
               # order falls out of the list and matters to nobody, which is the
               # point -- a counter telling the questions apart would be undone
               # by the first "up to" the player declined.
               card("abra_newcurriciulum", "New Curriculum", EARTH, kind="wizard_spell", ult=True,
                    tooltip="Power up once per Tier you have reached. You may VOID up to 2 cards in the Storm Cloud, and you may gain one at or below your Tier.",
                    flavour='"Can\'t believe the *garbage* I\'m asked to teach sometimes!"',
                    cast=["stat_gain:power@mine.player:sum:tier@mine.player",
                          "activate_zone:rules:by_column:curric_void", OFFER_CLOUD],
                    chosen=TAKE_TO_HAND, chosen_where=GAIN_TIER),
           ]),

    wizard("croh", "Croh Vosh", "Undead Lich", "Fire, Water", 20, 8, 6,
           "DOOOOOOOOOM!",
           "For each DOOM Token you have, take a card of your choice from your discard"
           " or draw one. If you have none, gain a DOOM Token.",
           ["activate_zone:rules:by_column:croh_redraw",
            "activate_zone:rules:by_column:croh_doom"],
           keywords=["accursed"],
           blurb="An undead Lich back from a thousand-year slumber. Enormous health, but he cannot heal -- healing becomes a CURSE for his opponent instead.",
           spells=[
               card("croh_sinking", "Sinking Strike", FIRE, kind="wizard_spell", ult=True,
                    tooltip="Gain 2 mana. Deal damage equal to your number of DOOM Tokens. If the CURSE pile is empty, gain a DOOM Token.",
                    flavour="Long ago, Croh Vosh was betrayed and killed at Dragon Bridge by his longtime ally, Salutaire Ruupart.",
                    cast=[MANA, MANA,
                          "hit:health@opponent:sum:doom@mine.player"],
                    cast2=("count:junk@curse_pile <= 0",
                           ["stat_gain:doom@mine.player:1"])),
               card("croh_undertow", "Undertow", WATER, kind="wizard_spell", ult=True,
                    tooltip="Your opponent discards a card. Draw a card. If you hold at least 3 more cards than they do, gain a DOOM Token.",
                    flavour="Croh has come to the Spellstorm seeking his path to world domination.",
                    cast=[DISCARD_RANDOM("enemy"), DRAW],
                    cast2=("count:spell@mine.hand >= count:spell@enemy.hand",
                           ["stat_gain:doom@mine.player:1"])),
           ]),

    wizard("omar", "Omar Evans", "Ninja and Eco-Terrorist", "Fire, Water", 10, 1, 4,
           "Hidden Movement",
           "Return a card from your discard to your hand, or draw a card. Then arm a Trap, face down, replacing whatever was armed.",
           ["options:omar_recall,omar_draw:optional", "show:trap_pile"],
           # The swap out happens on the pick and not before it, so the Trap
           # coming off is not among the ones offered -- which is the whole of
           # "you can't play the same Trap twice in a row", said by the order
           # rather than by a rule remembering what was last armed.
           # The Trap going back to the pile takes its unspent Dodge with it
           # unless somebody says otherwise, and a Trap re-armed with a budget
           # already on it would soak before it was ever revealed.
           ult_chosen=["stat_set:sprung@mine.traps:0",
                       "stat_set:guard@mine.traps:0",
                       "move:mine.traps:trap_pile",
                       "move:target:mine.traps"],
           start=["create:trap_pile:trap_mud:1",
                  "create:trap_pile:trap_ice:1",
                  "create:trap_pile:trap_dodge:1"],
           keywords=["dodging"],
           blurb="A ninja and wanted eco-terrorist. Low health, but he acts first in every matchup and Shuriken always resolves before anything else.",
           spells=[
               card("omar_beetle", "Beetle Buster", FIRE, kind="wizard_spell", ult=True,
                    tooltip="Discard a Fire card from your hand to deal 2 damage.",
                    flavour="A hero to many, Omar is regarded by the powerful as an eco-terrorist.",
                    cast=[OFFER_HAND_OF(FIRE)],
                    chosen=["destroy:target", DMG(2)]),
               card("omar_shuriken", "Shuriken", WATER, kind="wizard_spell", ult=True,
                    tooltip="Gain Initiative and draw a card.",
                    flavour='"..."',
                    simplified='the printed card ALWAYS resolves first and can discard the opponent\'s revealed card; resolution order is set by Initiative alone, so it takes Initiative instead',
                    cast=GAIN_INIT + [DRAW]),
           ]),

    wizard("bunny", "Bunny Wizard", "Healer of Bunny Island", "Water, Earth", 8, 2, 5,
           "Cast a Magic Trick!",
           "Reveal a non-Wizard card from your hand, resolve it twice and VOID it. All players heal 1.",
           ["show:mine.hand:optional"],
           ult_chosen=["copy:target:activate:2", "move:target:void",
                       HEAL(1), "heal:health@opponent:1"],
           ult_chosen_where=VOIDABLE,
           max_health=10, keywords=["overhealing"],
           blurb="A stuffie from Bunny Island who heals fast and often helps his opponent along the way. He is the only wizard who can heal past his starting health, and what will not fit he draws instead. A good choice if you like to play nice.",
           spells=[
               # "A *different* revealed Earth card" is `others.`, which is the
               # pool with the asking card taken out of it -- so the card cannot
               # offer itself and nothing has to say which card is meant.
               card("bunny_buddy", "Buddy System", EARTH, kind="wizard_spell", ult=True,
                    tooltip="Power up and gain 1 mana. If your opponent is Tier I, they power up too. You may resolve a different revealed Earth card.",
                    flavour='"Bunny is wondering if it would be okay to hold your hand." - Bunny\'s Handler',
                    cast=[POWER, MANA, "show:others.battle.earth:optional"],
                    cast2=("tier@opponent <= 1",
                           ["stat_gain:power@opponent:1"]),
                    chosen=["copy:target:activate"]),
               card("bunny_snowday", "Snow Day", WATER, kind="wizard_spell", ult=True,
                    tooltip="Heal 2. Give an ICE to your opponent if they have none in their discard.",
                    flavour="The Stuffies are a species of stuffed animals that have been brought to life by powerful Star magic.",
                    cast=[HEAL(2)],
                    cast2=("count:junk@enemy.discard <= 0", GIVE("ice"))),
           ]),

    wizard("oren", "Oren Bark", "Magical Chemistry Student", "Fire, Earth", 16, 6, 5,
           "Bottoms up, I guess!",
           "Reshuffle your Potion Deck, then draw potions one at a time for as long as you dare. A third TOXIC ends it and gives you an ASH, a CURSE and an ICE. Your Elements reset to 3 afterwards.",
           ["move:potion_discard:potion_deck", "shuffle:potion_deck",
            "stat_set:toxic@mine.player:0", "push_phase:potion"],
           start=["stat_set:fire_el@mine.player:3",
                  "stat_set:earth_el@mine.player:3",
                  "stat_set:water_el@mine.player:3",
                  "create:mine.sidecar:btn_potion_draw:1",
                  "create:mine.sidecar:btn_potion_stop:1"],
           blurb="A chemistry student who loves danger and whose experiments keep exploding. A good character for players who like to gamble.",
           spells=[
               card("oren_potion", "Potion Gun", FIRE, kind="wizard_spell", ult=True,
                    tooltip="Deal 1 damage. You may give a non-Wizard card from your hand to your opponent. If you do, gain 2 of the Element matching it.",
                    flavour='"Think I can hit that old barrel by the hill over there?"',
                    # "Gain 2 of the Element matching that card" -- and which
                    # Element that is depends on the pick, so it is read off the
                    # offer rather than named. The pick is the only card left in
                    # there while a `chosen` list runs, so `count:fire@options`
                    # is one if it was a Fire card and nought otherwise; the
                    # doubling is the amount grammar's product. Before the move,
                    # because a card in the enemy's hand is no longer in the
                    # offer to be counted.
                    cast=[DMG(1), OFFER_HAND],
                    chosen=["stat_gain:fire_el@mine.player:count:fire@options:x:2",
                            "stat_gain:earth_el@mine.player:count:earth@options:x:2",
                            "stat_gain:water_el@mine.player:count:water@options:x:2",
                            "move:target:enemy.hand"],
                    # "A non-Wizard card": a fact about the card, but said as a
                    # condition rather than a tag because no tag says what a card
                    # is *not*. The whole hand still comes up, which is right --
                    # you are looking through it either way.
                    chosen_where=["count:wizard_spell@target <= 0"]),
               # Six ways to pour one beaker into another, dealt as an offer of six.
               # Two questions would read better -- which down, then which up -- but
               # the second could not leave the first one out, and pouring Fire into
               # Fire is not a move. So the pairs are the entries, and each says in
               # its own `needs` whether there is enough in the beaker to pour.
               card("oren_unstable", "Unstable Formula", EARTH, kind="wizard_spell", ult=True,
                    tooltip="Power up and gain 1 mana. Lower one Element by 2 to raise another by 2. If anyone revealed Water, gain 1 Earth Element.",
                    flavour='"Oh, it\'ll work, trust me. But, uh... you might wanna stand back a bit..."',
                    cast=[POWER, MANA, OFFER_SWAP],
                    cast2=("count:water@battle >= 1", ["stat_gain:earth_el@mine.player:1"])),
           ]),

    wizard("may", "May Danaris", "Hacker", "Fire, Earth", 12, 4, 6,
           "Void Traveler",
           "Gain 3 Energy Tokens. You may resolve a non-Wizard card from your hand or any card in the VOID, then put it on the bottom of the Spellstorm Deck.",
           ["stat_gain:energy@mine.player:3", "options:may_hand,may_void:optional"],
           # Dangerous Download: at the end of a round she may spend an Energy
           # and a mana to resolve the opponent's revealed Tier II card. A thing
           # a player may do, at a cost, at a moment -- which is a reaction, and
           # the moment is the round saying it is over. The cards are still in
           # the battle spots when it does; `round_end` sweeps them a phase later.
           passive={"to": "round_over", "whose": "mine", "in": "wizard",
                    "cost": {"energy@mine.player": 1, "mana@mine.player": 1},
                    "needs": ["tier_req@enemy.battle == 2"],
                    "action": ["copy:enemy.battle:activate"]},
           blurb="A hacker who used to work for Central Intelligence. She can play cards from the VOID, and is good for players who like to feel like they're cheating.",
           start=["stat_gain:energy@mine.player:2"],
           spells=[
               # Two "if"s the card was reading as one. The Energy spent is a
               # choice of two, and "if you still have 2" is asked *after* it --
               # so losing two is what usually costs you the second half.
               card("may_data", "Data Breach", EARTH, kind="wizard_spell", ult=True,
                    tooltip="Lose 1 or 2 Energy Tokens to power up that many times. If you still hold 2 Energy, your opponent reveals their hand and you choose what they discard.",
                    flavour='"Yes! I\'m in. Now let\'s see what these idiots have planned next..."',
                    cast=["options:may_lose1,may_lose2:optional"]),
               card("may_starshot", "Star Shot", FIRE, kind="wizard_spell", ult=True,
                    tooltip="Discard a card to deal 1 damage. Gain 1 mana for each Energy Token you have, then lose 2 Energy.",
                    flavour='"Hey, YOU! Eat this!"',
                    cast=["stat_gain:mana@mine.player:sum:energy@mine.player",
                          "stat_damage:energy@mine.player:2", OFFER_HAND],
                    chosen=["activate_zone:rules:by_column:starshot",
                            "destroy:target", DMG(1)]),
           ]),
]

# Abragail's Research Journal: eight spaces, each firing at battle start once a
# Research Token sits on it. Three of them ask a question, and an offer is one
# at a time, so those three get a step of their own and a phase each to open in
# -- an ask is the last thing an action list can do, and three asks in one list
# is three overlays on one table.
JOURNAL = [
    (1, "Gain 1 mana.", [MANA], None),
    (2, "You may VOID a card from your hand.",
        [OFFER_HAND], {"where": VOIDABLE, "action": ["move:target:void"]}),
    (3, "Gain 1 mana.", [MANA], None),
    (4, "Move an ICE, ASH or CURSE from your discard to your opponent's.",
        ["show:mine.discard.junk:optional"],
        {"action": ["move:target:enemy.discard"]}),
    (5, "Power up.", [POWER], None),
    (6, "You may gain a card from the Storm Cloud at or below your Tier.",
        [OFFER_CLOUD], {"action": TAKE_TO_HAND, "where": GAIN_TIER}),
    (7, "Power up.", [POWER], None),
    (8, "Draw a card.", [DRAW], None),
]

# The spaces that ask, in order, which is both the steps and the phases.
JOURNAL_ASKS = [n for n, _, _, ch in JOURNAL if ch]

# Oren's potion deck. Each potion costs a number of one Element off the Chemistry
# Board and does nothing if the beaker is too low, which is a condition and so an
# ability rather than a play. Five of the nine carry the TOXIC icon — the
# transcription's table is right and its prose, which says six, is not.
#
# The last two columns are what the potion does once it is paid for: a condition
# and its actions, and a second pair for the one potion whose text has an if.
POTIONS = [
    ("pot_haste", "Haste Potion", "If you have Initiative, deal 1 damage. Otherwise, gain Initiative.",
     FIRE, 1, False, (HAS_INIT, [DMG(1)]), (NO_INIT, GAIN_INIT)),
    ("pot_purple", "I Call It... Purple Stuff.", "Power up and gain 2 mana.",
     FIRE, 2, True, (None, [POWER, MANA, MANA]), None),
    ("pot_explosion", "A Slight... Explosion", "Deal 1 damage. Gain 1 of each Element.",
     FIRE, 3, True, (None, [DMG(1), "stat_gain:fire_el@mine.player:1",
                            "stat_gain:earth_el@mine.player:1",
                            "stat_gain:water_el@mine.player:1"]), None),
    ("pot_devils", "Devil's Breath", "Power up. Give an ASH.",
     EARTH, 1, True, (None, [POWER] + GIVE("ash")), None),
    # The flag the next potion reads. It is set here and spent there, which is
    # the only way a card in this game reaches forward to the next one.
    ("pot_gasoline", "I Think I Just Drank Gasoline", "Take 1 damage. Your next potion happens twice, and you pay its cost once.",
     EARTH, 2, True, (None, [SELF_DMG(1), "stat_set:doubled@mine.player:1"]), None),
    # Resolve it where it lies: the printed card says resolve, not gain, and
    # `copy:` is the word for running a card's whole list without taking it.
    ("pot_dragon", "Dragon Elixir", "Resolve the top card of the Dragon Deck.",
     EARTH, 4, False, (None, ["activate_zone:rules:by_column:dry_dragon",
                              "copy:dragon_deck:activate"]), None),
    ("pot_frost", "Frost Bomb", "Your opponent loses 1 mana. Give an ICE.",
     WATER, 2, False, (None, ["stat_damage:mana@opponent:1"] + GIVE("ice")), None),
    ("pot_storm", "Storm Juice", "Draw a card and power up.",
     WATER, 3, False, (None, [DRAW, POWER]), None),
    ("pot_soda", "Health Soda", "Heal 2.",
     WATER, 4, True, (None, [HEAL(2)]), None),
]

# What ends the Ultimate, whichever way it ends: the beakers go back to 3 and the
# phase the Ultimate pushed comes off. The pushed phase is on top by now -- a
# revealed page pops before the card it showed acts -- so this pops the loop.
POTION_END = ["stat_set:doubled@mine.player:0",
              "stat_set:fire_el@mine.player:3",
              "stat_set:earth_el@mine.player:3",
              "stat_set:water_el@mine.player:3",
              "stat_set:toxic@mine.player:0",
              "pop_phase"]

# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------

ART = {
    # Card key -> the file in game/games/assets. Named rather than derived
    # because a handful of the print files are spelled differently from the
    # card (roboy-boy2, abra-newcurriciulum) and a silent miss draws blank.
    "magicdart": "ss_magicdart.jpg", "block": "ss_block.jpg",
    "powergem": "ss_powergem.jpg",
    "fireessence": "ss_fireessence.jpg", "wateressence": "ss_wateressence.jpg",
    "earthessence": "ss_earthessence.jpg",
    "ice": "ss_ice.jpg", "ash": "ss_ash.jpg", "curse": "ss_curse.jpg",
    "derby_coffee": "ss_derby_coffee.jpg", "derby_reckless": "ss_derby_reckless.jpg",
    "eve_facepunch": "ss_eve_facepunch.jpg", "eve_riot": "ss_eve_riot.jpg",
    "abra_deepgems": "ss_abra_deepgems.jpg",
    "abra_newcurriciulum": "ss_abra_newcurriciulum.jpg",
    "croh_sinking": "ss_croh_sinking.jpg", "croh_undertow": "ss_croh_undertow.jpg",
    "omar_beetle": "ss_omar_beetle.jpg", "omar_shuriken": "ss_omar_shuriken.jpg",
    "bunny_buddy": "ss_bunny_buddy.jpg", "bunny_snowday": "ss_bunny_snowday.jpg",
    "oren_potion": "ss_oren_potion.jpg", "oren_unstable": "ss_oren_unstable.jpg",
    "may_data": "ss_may_data.jpg", "may_starshot": "ss_may_starshot.jpg",
}
for c in SPELLS + DRAGONS:
    ART.setdefault(c["key"], "ss_%s.jpg" % c["key"])
for w in WEATHER:
    ART.setdefault(w["key"], "ss_%s.jpg" % w["key"])
WIZ_ART = {"derby": "ss_derby.jpg", "eve": "ss_eve.jpg", "abra": "ss_abra.jpg",
           "croh": "ss_croh.jpg", "omar": "ss_omar.jpg", "bunny": "ss_bunny.jpg",
           "oren": "ss_oren.jpg", "may": "ss_may.jpg"}
POTION_ART = {"pot_explosion": "ss_oren1.jpg", "pot_haste": "ss_oren2.jpg",
              "pot_purple": "ss_oren3.jpg", "pot_dragon": "ss_oren4.jpg",
              "pot_devils": "ss_oren5.jpg", "pot_gasoline": "ss_oren6.jpg",
              "pot_frost": "ss_oren7.jpg", "pot_soda": "ss_oren8.jpg",
              "pot_storm": "ss_oren9.jpg"}

ELEMENT_STYLE = {FIRE: "ember", WATER: "tide", EARTH: "loam"}


# Bold is the mechanics, and the vocabulary is written down once here rather
# than by hand into a hundred and thirty strings: a term the game gains is then
# marked up everywhere it is already named, and a term it loses stops being
# marked everywhere at once.
#
# Verbs stay plain and their objects are bolded -- "deal *2 damage*", not "*deal
# 2 damage*". The eye is looking for the number and the named thing; bolding the
# sentence around them would leave nothing standing out from anything.
MECHANICS = [
    r"\d+ more damage", r"\d+ damage", r"\d+ mana", r"\d+ cards?",
    r"health \d+", r"\d+ health",
    r"\d+ Power Tokens?", r"\d+ Storm Shards?", r"\d+ Shards?",
    r"\d+ Research Tokens?", r"\d+ DOOM Tokens?", r"\d+ Energy",
    r"[Hh]eals? \d+", r"[Hh]eals? for", r"[Pp]ower up \d+ times",
    r"[Pp]ower up twice", r"[Pp]owers? up",
    r"[Dd]raws? a card", r"[Dd]iscards? a card", r"[Dd]iscards? their hand",
    r"Power Tokens?", r"Power Track", r"Initiative rating \d+",
    r"Initiative rating", r"Initiative",
    r"Storm Clouds?", r"Storm Shards?", r"Spellstorm Deck", r"Weather Deck",
    r"Research Journal", r"Research Tokens?", r"DOOM Tokens?", r"Chemistry Board",
    r"Blast Score", r"Ultimates?", r"Tier [IV]+", r"Tier", r"Regroup",
    r"ICE", r"ASH", r"CURSE", r"VOIDed", r"VOID", r"Energy",
    # The three elements are read by rules as often as any stat is -- "if your
    # opponent revealed Water" is a condition, not a mood.
    r"Fire", r"Water", r"Earth",
]
MECH_RE = re.compile(r"\b(?:%s)\b" % "|".join(MECHANICS))


def mark(text):
    """Bold the mechanics, and leave the paragraphs already set in italic alone.

    A paragraph wearing italic is flavour or an aside about the engine -- the
    half a player may skip -- and bolding inside it would put the emphasis back
    exactly where the italic was taking it away.
    """
    out = []
    for para in text.split("\n\n"):
        if para.startswith("_") and para.endswith("_"):
            out.append(para)
        else:
            out.append(MECH_RE.sub(lambda m: "*%s*" % m.group(0), para))
    return "\n\n".join(out)


def tip(base, flavour=None, simplified=None):
    """One tooltip: what the card does, what it says, and where we fell short.

    The printed flavour line and our own note about where the engine fell short
    are both italic: neither is a rule, and a player deciding what to play wants
    to know that before reading either of them.
    """
    out = base
    if flavour:
        out += "\n\n_%s_" % flavour
    if simplified:
        out += "\n\n_[Simplified: %s]_" % simplified
    return out


def ability(key, actions, when=None, text=None):
    a = {"key": key}
    if text: a["text"] = text
    if when: a["needs"] = list(when)
    a["action"] = list(actions)
    return a


def spell_template(c):
    """One playable card: art, tags, the numbers a rule reads, and its steps."""
    t = {"key": c["key"], "text": c["name"]}
    art = ART.get(c["key"]) or c.get("asset")
    if art: t["asset"] = art
    tags = [c["element"], ELEMENT_STYLE[c["element"]], "spell"] + c["tags"]
    if c["kind"] == "basic":   tags.append("basic")
    if c["kind"] == "essence": tags.append("essence")
    if c["kind"] == "dragon":  tags.append("dragon")
    if c["kind"] == "wizard_spell": tags += ["wizard_spell", "no_void"]
    if c["disc"]: tags.append("has_discard")
    # The [ULT] icon, and now it means what it says: the resolve phase announces
    # a card wearing this, and your wizard's Ultimate is the answer.
    if c["ult"]: tags.append("ult")
    t["tags"] = tags
    # The icon is a rule now, so it is said in words too -- nothing else on the
    # card tells a player why a window opens while this one resolves.
    text = c["tooltip"]
    if c["ult"]: text += "\n\nCarries the Ultimate icon: you may cast your Ultimate as this resolves."
    t["tooltip"] = tip(text, c["flavour"], c["simplified"])
    if c["comment"]: t["comment"] = c["comment"]

    # A card that can be cast says so by carrying a play block; ICE, ASH and
    # CURSE carry none, which is the whole of "this can't be played" and needs
    # no rule anywhere else.
    # No owner is written here. A card dealt into a seat's deck already carries
    # that seat, and one gained from the Storm Cloud is nobody's -- so the pile
    # it is lying in answers for it, which is what a card crossing the table
    # needs: Crossfire posts itself to the other player's discard, and stamping
    # it with the caster on the way out would send it home again the next time
    # they threw it away.
    if c["kind"] != "junk":
        t["play"] = {"action": ["move_to:mine.commit"]}

    # `tier_req` is what the Storm Cloud's take tests against your Tier.
    stats = {}
    if c["tier"]: stats["tier_req"] = c["tier"]
    elif c["kind"] == "junk": stats["tier_req"] = 1
    else: stats["tier_req"] = 1
    t["card_stats"] = stats

    # An action list has no cursor, so whatever follows an ask runs before the
    # answer arrives. The asks therefore go at the end -- and there may be more
    # than one now, since the offer queue holds the second question until the
    # first is answered. What is not allowed is doing something in between.
    asks = [a for a in c["cast"] if a.startswith("show:") or a.startswith("options:")]
    does = [a for a in c["cast"] if a not in asks]
    for col in ("cast", "cast2", "cast3"):
        steps = c[col] if col == "cast" else (c[col][1] if c[col] else [])
        tail = [a for a in steps if a.startswith("show:") or a.startswith("options:")]
        assert steps[len(steps) - len(tail):] == tail, \
            "%s: the offers have to be the last thing its %s does" % (c["key"], col)

    abil = []
    # Kept even when it is empty, so the resolve phase's first pass always has
    # something to name.
    abil.append(ability("cast", does, text="Resolve"))
    if c["cast2"]: abil.append(ability("cast2", c["cast2"][1], when=[c["cast2"][0]], text="Resolve"))
    if c["cast3"]: abil.append(ability("cast3", c["cast3"][1], when=[c["cast3"][0]], text="Resolve"))
    if asks:       abil.append(ability("cast_ask", asks, text="Resolve"))
    t["abilities"] = abil
    # On Discard is not an ability. An ability is something the card does, and
    # every rule that runs abilities would run this one -- resolving it, copying
    # it -- each needing a reason not to. This is something that happens *to* the
    # card, so it is a trigger: leaving the hand for the discard pile, which is
    # what the rulebook means and nothing else. VOIDing it goes somewhere else
    # and fires nothing, which is the rule stated once instead of on every card.
    if c["disc"]:
        t["leaves"] = {"from": "hand", "into": "discard", "action": list(c["disc"])}
    if c["chosen"]:
        t["chosen"] = {"action": list(c["chosen"])}
        if c["chosen_where"]: t["chosen"]["where"] = list(c["chosen_where"])
    return t


def weather_template(w):
    t = {"key": w["key"], "text": w["name"], "tags": ["weather", "storm"],
         "asset": ART.get(w["key"]),
         "tooltip": tip(w["tooltip"], simplified=w["simplified"])}
    abil = []
    if w["wx"]: abil.append(ability("wx", w["wx"], text="Weather"))
    for i, (cond, acts) in enumerate(WEATHER_RIDERS.get(w["key"], [])):
        abil.append(ability("wx%d" % (i + 2), acts, when=[cond], text="Weather"))
    if w["wy"]:
        abil.append(ability("wy", w["wy"][1], when=[w["wy"][0]], text="Weather"))
    if w["wz"]: abil.append(ability("wz", w["wz"], text="Weather"))
    if abil: t["abilities"] = abil
    # A weather card that asks is the card doing the asking, so the answer comes
    # back to it, exactly as it does for a spell.
    if w["chosen"]:
        t["chosen"] = {"action": list(w["chosen"])}
        if w["chosen_where"]: t["chosen"]["where"] = list(w["chosen_where"])
    return t


def wizard_templates(w):
    """The character card that carries the Ultimate, and the chooser card."""
    out = []
    # The printed moment, at last: you may cast your Ultimate while one of your
    # own cards carrying the [ULT] icon resolves. That is a reaction to a verb --
    # the card announces "resolving" and this answers it -- so the icon means
    # what it says and an Ultimate can reply to what the reveal turned over.
    #
    # "whose": "mine" is the whole of "your own card": the announcement is made
    # by whichever seat is resolving, and only that seat's wizard may answer it.
    # **Exactly one of these is ever payable, and that is the point.** A click on
    # a card means the one answer it offers; a card offering two is unreachable,
    # so the paid one steps aside while a pass is in hand rather than standing
    # beside it. Nothing is lost by that -- free is the better of the two every
    # time, and the card that hands out the pass says the Ultimate is free.
    ult = {"to": "resolving", "whose": "mine", "in": "wizard",
           "needs": ["ult_free@mine.player <= 0"],
           "cost": {"mana@mine.player": w["ult_cost"]},
           "action": list(w["ult_action"])}
    if w["ult_compute"]:
        ult["compute"] = list(w["ult_compute"])
    # The same Ultimate, owed differently: Obsidian hands out a one-shot pass and
    # this is what spends it.
    ult_free = {"to": "resolving", "whose": "mine", "in": "wizard",
                "cost": {"ult_free@mine.player": 1},
                "action": list(w["ult_action"])}
    if w["ult_compute"]:
        ult_free["compute"] = list(w["ult_compute"])
    char = {
        "key": "wiz_" + w["key"], "text": w["name"], "asset": WIZ_ART[w["key"]],
        "tags": ["wizard_card", w["key"]] + w["keywords"],
        "tooltip": tip("%s. %s\n\nUltimate (%d mana) - %s: %s\n\nCast it while one of your own cards"
                       " carrying the Ultimate icon resolves.\n\nStarting health %d, Initiative rating %d."
                       % (w["epithet"], w["blurb"], w["ult_cost"], w["ult_name"],
                          w["ult_tooltip"], w["health"], w["rating"]),
                       simplified=w["simplified"]),
        "reactions": [ult, ult_free] + ([w["passive"]] if w["passive"] else []),
    }
    if w["ult_chosen"]:
        char["chosen"] = {"action": list(w["ult_chosen"])}
        if w["ult_chosen_where"]:
            char["chosen"]["where"] = list(w["ult_chosen_where"])
    out.append(char)

    pick_action = [
        "stat_boost:health@mine.player:%d" % (w["max_health"] - 1),
        "stat_set:health@mine.player:%d" % w["health"],
        "stat_set:init_rating@mine.player:%d" % w["rating"],
        "create:mine.wizard:wiz_%s:1" % w["key"],
    ]
    for s in w["spells"]:
        pick_action.append("create:mine.deck:%s:1" % s["key"])
    pick_action += list(w["start"])
    # The chair takes the wizard's name. The seat prints "{name}" and starts as
    # "Player One", so this is the moment it stops being a number and becomes
    # somebody — and {owner}/{active} read it everywhere from here on.
    pick_action.append("set_name:mine.player:text@self")
    pick_action.append("stat_gain:picked@mine.player:1")
    # The copy dealt into the offer spends the real card it was copied from, so
    # the second seat is offered seven wizards rather than eight including the
    # one already taken. The tag is the wizard's own key, which is what lets a
    # scope name one entry in the roster; nothing else wears it.
    pick_action.append("purge:roster." + w["key"])
    out.append({
        "key": "pick_" + w["key"], "text": w["name"], "asset": WIZ_ART[w["key"]],
        "tags": ["chooser", "no_undo", w["key"]],
        "tooltip": "%s (%s). %s\n\nHealth %d, Initiative rating %d, Ultimate %d mana."
                   % (w["epithet"], w["elements"], w["blurb"], w["health"],
                      w["rating"], w["ult_cost"]),
        "play": {"action": pick_action},
    })
    return out


def rules_card(key, text, tooltip, abilities, chosen=None, tags=(), stats=None):
    """A rule with nowhere else to live: a card in an offscreen zone that a
    phase walks. Its `when` is the if the action grammar has no room for."""
    t = {"key": key, "text": text, "tags": ["immutable"] + list(tags),
         "tooltip": tooltip, "asset": "auto", "abilities": abilities}
    if stats: t["card_stats"] = dict(stats)
    # A rule that asks is the card doing the asking, so the answer comes back to
    # it -- which is why a space that asks needs a rules card to itself.
    if chosen: t["chosen"] = dict(chosen)
    return t


def rules_templates():
    out = []
    # Countering. Each seat asks it of its own card, so one card per matchup
    # rather than one with three same-keyed abilities -- the same either way to
    # the engine, and this reads.
    beats = [(FIRE, EARTH), (EARTH, WATER), (WATER, FIRE)]
    for a, b in beats:
        out.append(rules_card(
            "r_ctr_" + a, "%s beats %s" % (a.title(), b.title()),
            "Countering: %s beats %s. Countering the opponent draws you a card."
            % (a.title(), b.title()),
            # Countering is announced, so a card held for it can answer. The
            # draw is the emit's held action rather than the line after it: an
            # action list runs to completion, so anything written beside an emit
            # would happen before the answer arrived.
            [ability("check", ["emit:countered:" + DRAW],
                     when=["count:%s@mine.battle >= 1" % a,
                           "count:%s@enemy.battle >= 1" % b])]))

    out.append(rules_card(
        "r_lapis", "Lapis",
        "Lapis heals 1 for each Water card you discard to it.",
        [ability("lapis_heal", [HEAL(1)], when=["count:water@options >= 1"])]))

    # Ruby's two branches, told apart by which card came back in the offer.
    # A pick leaves the offer holding exactly the card that was taken -- the
    # rest go home before the chosen actions run -- so "@options" here is the
    # answer and not the question.
    # One card per branch, because a card may not wear the same ability key
    # twice -- the same reason countering is three cards rather than one.
    out.append(rules_card(
        "r_ruby_burn", "Ruby: the flame",
        "Ruby: taking the flame deals 1 damage for each Fire card among the three.",
        [ability("ruby_pick", ["hit:health@opponent:sum:counted@options"],
                 when=["count:burn@options >= 1"])]))
    out.append(rules_card(
        "r_ruby_void", "Ruby: the card",
        "Ruby: taking one of the three VOIDs it.",
        [ability("ruby_pick", ["move:options:void"],
                 when=["count:burn@options <= 0"])]))

    # Blast Scoring. Your Blast Score is what you still hold once the discard
    # effects have gone; a single highest takes two Shards, a tie takes one each.
    out.append(rules_card(
        "r_blast", "Blast Score",
        "Blast Score is the cards left in your hand after discard effects, less one per ICE discarded. The single highest score gains 2 Storm Shards; a tie gains 1 each.",
        [ability("score", ["stat_set:blast@mine.player:count:spell@mine.hand",
                           "stat_damage:blast@mine.player:sum:ice_pen@mine.player"]),
         ability("award_win", [SHARD(2)],
                 when=["blast@mine.player > blast@opponent"]),
         ability("award_tie", [SHARD(1)],
                 when=["blast@mine.player == blast@opponent"])]))

    # The Power Track. Six tokens fill it; the seventh is a Tier, and at Tier III
    # a filled track is a Dragon instead. Checked between rounds rather than the
    # instant the sixth token lands, which is the one place this drifts.
    out.append(rules_card(
        "r_tier", "The Power Track",
        "Six Power Tokens fill the track. Filling it raises your Tier by one and returns the six; at Tier III a filled track gains you a Dragon instead. Checked between rounds.",
        [ability("tier_up", ["stat_damage:power@mine.player:6",
                             "stat_gain:tier@mine.player:1"],
                 when=["power@mine.player >= 6", "tier@mine.player <= 2"]),
         ability("tier_gem", ["stat_damage:power@mine.player:6",
                              "activate_zone:rules:by_column:dry_dragon",
                              "draw_from:dragon_deck:mine.hand:1"],
                 when=["power@mine.player >= 6", "tier@mine.player >= 3"])]))

    # What the board prints for a pile that has run out. Six ICE, six ASH and
    # six CURSE is few enough to reach in a long game, and until now giving from
    # an empty pile did nothing at all -- which made running the supply dry a
    # reward. Each alternative is the same shape as the card that is no longer
    # there: get rid of one you are holding, and take the penalty instead.
    #
    # Two abilities per pile because there are two directions -- being handed
    # junk and taking it yourself -- and the penalty follows whoever would have
    # received the card.
    for kind, take, give in (
            ("ash",   ["stat_damage:power@mine.player:2"],
                      ["stat_damage:power@opponent:2"]),
            ("curse", [SELF_DMG(1)], [DMG(1)]),
            ("ice",   [DISCARD_RANDOM("mine")] * 2, [DISCARD_RANDOM("enemy")] * 2)):
        # VOIDing one is a move back onto the pile, which is where a VOIDed junk
        # card goes -- so the pile refills by one and the penalty lands on top.
        # Which one is VOIDed is the holder's choice, and it is a real one: every
        # ICE is the same card, but one in your hand costs a Blast Score and one
        # in your discard costs a draw. So the holder is asked -- and when the
        # junk was being *given*, the holder is the other player, which is what
        # `set_priority` is for: from inside that window `mine` is theirs.
        ask = "show:mine.held.%s" % kind
        out.append(rules_card(
            "r_dry_" + kind, "The %s pile is empty" % kind.upper(),
            tip("When the %s pile is empty, whoever would have been given one VOIDs "
                "a %s of their choosing from their hand or discard and takes the "
                "penalty instead." % (kind.upper(), kind.upper())),
            [ability("dry_take_" + kind, take + [ask],
                     when=["count:junk@%s_pile <= 0" % kind]),
             ability("dry_give_" + kind, give + ["set_priority:enemy.player", ask],
                     when=["count:junk@%s_pile <= 0" % kind])],
            chosen={"action": ["move:target:%s_pile" % kind]}))

    # The Dragon pile is the one whose empty rule is a reward rather than a
    # penalty, because a Dragon is what you were owed.
    out.append(rules_card(
        "r_dry_dragon", "The Dragon pile is empty",
        "When the Dragon pile is empty, gaining a Dragon deals 2 damage and gains 2 Storm Shards instead.",
        [ability("dry_dragon", [DMG(2), SHARD(2)],
                 when=["count:dragon@dragon_deck <= 0"])]))

    # Who begins with the Initiative Tracker: the lower Initiative rating.
    out.append(rules_card(
        "r_first", "Initiative rating",
        "The wizard with the lower Initiative rating takes the Initiative Tracker at the start of the game.",
        [ability("first", GAIN_INIT,
                 when=["init_rating@mine.player < init_rating@opponent"]),
         # "At all times exactly one player holds the Initiative Tracker", and
         # two wizards with the same rating -- a mirror match -- left nobody
         # holding it, which quietly turned every "starting with the player who
         # has Initiative" into "starting with whoever happened to be up". The
         # printed game does not say how to break the tie, so the engine gives it
         # to the player who is up as the game begins. Run once rather than once
         # per seat, or the second seat would take it back off the first.
         ability("first_tie", GAIN_INIT,
                 when=["initiative@mine.player <= 0",
                       "initiative@opponent <= 0"])]))

    # Abragail's journal: every researched space fires at battle start. The
    # three that ask a question run under their own step so a phase can open
    # them one at a time.
    for n, what, acts, chosen in JOURNAL:
        out.append(rules_card(
            "r_journal_%d" % n, "Space %d - %s" % (n, what.rstrip(".")),
            tip("%s\n\nSpace %d of Abragail's Research Journal. Put a Research Token here"
                " with her Ultimate and it fires at the start of every battle from then on."
                % (what, n)),
            [ability("jr%d" % n if chosen else "bstart", acts,
                     when=["count:abra@mine.wizard >= 1", "researched@self >= 1"])],
            chosen=chosen, tags=["jspace"], stats={"researched": 0}))

    # A third TOXIC ends the Ultimate whatever the player wanted, and costs one
    # of each junk card on the way out.
    out.append(rules_card(
        "r_potion", "A third TOXIC",
        "Drawing a third TOXIC potion ends Oren's Ultimate after that potion resolves, and gives him an ASH, a CURSE and an ICE.",
        [ability("potion_toxic",
                 GAIN_JUNK("ash") + GAIN_JUNK("curse") + GAIN_JUNK("ice") + POTION_END,
                 when=["toxic@mine.player >= 3"])]))

    # The second half of May's *Data Breach*, here rather than on the card
    # because it is an if asked after the player has answered a question -- and
    # an offer written into a cast runs last, after every rider.
    out.append(rules_card(
        "r_breach", "Data Breach",
        "If May still holds 2 Energy after paying, her opponent reveals their hand and she chooses what they discard.",
        [ability("breach", ["show:enemy.hand"], when=["energy@mine.player >= 2"])],
        chosen={"action": ["destroy:target"]}))

    # Coffee Run's Initiative and Star Shot's extra damage both ask about the
    # card the player just chose, which is still lying in the offer while the
    # `chosen` list runs -- the same reading Potion Gun takes its Element from.
    out.append(rules_card(
        "r_coffee", "Coffee Run",
        "Derby gains Initiative only if the card he gained was an Earth card.",
        [ability("coffee", GAIN_INIT, when=["count:earth@options >= 1"])]))
    out.append(rules_card(
        "r_starshot", "Star Shot",
        "May deals 1 more damage if the card she discarded was Tier II.",
        [ability("starshot", [DMG(1)], when=["sum:tier_req@options == 2"])]))

    # One card per DOOM Token he might hold, so the Ultimate asks exactly as many
    # times as he has. A number of questions worked out from a stat has no other
    # spelling: an action list is written once and a stat is read at run time.
    for n in range(1, 5):
        out.append(rules_card(
            "r_croh_redraw_%d" % n, "DOOM Token %d" % n,
            "With %d or more DOOM Tokens, Croh takes a card from his discard or draws." % n,
            [ability("croh_redraw", ["options:croh_take,croh_draw:optional"],
                     when=["doom@mine.player >= %d" % n])]))

    # Croh gains DOOM Tokens only from failure states -- having none, or an
    # empty CURSE pile -- which is the trap his whole design is built around.
    # An if lives in an ability, so the Ultimate calls one rather than saying it.
    out.append(rules_card(
        "r_doom", "Looming",
        "Croh Vosh gains a DOOM Token from his Ultimate only when he has none left.",
        [ability("croh_doom", ["stat_gain:doom@mine.player:1"],
                 when=["doom@mine.player <= 0"])]))

    # The VOIDing half of Abragail's *New Curriculum*, which is here rather than
    # on the card because the card is already asking a question of its own and
    # means something else by the answer. Two shows, so two questions: the queue
    # holds the second until the first is answered, and either may be declined --
    # "up to 2" is the whole of what this rule says about how many.
    out.append(rules_card(
        "r_curriculum", "New Curriculum",
        "Abragail may VOID up to 2 cards in the Storm Cloud. The shelf refills behind each one.",
        [ability("curric_void", [OFFER_CLOUD, OFFER_CLOUD])],
        chosen={"action": ["move:target:void", REFILL_CLOUD]}))

    # Somebody has to say the round is over, or nothing can answer it. May's
    # Dangerous Download is the only thing that does, and a verb no card answers
    # never opens a window -- so in a game without her this line costs nothing.
    out.append(rules_card(
        "r_round_over", "The round is over",
        "The end of a round, said out loud so that a rule which happens then has something to answer.",
        [ability("round_close", ["emit:round_over"])]))

    # Abragail's BATTLE START. The `bstart` column is already walked once per
    # seat at the top of every battle, so a wizard power that happens then is a
    # rules card and its `when` is which wizard is sitting there -- the same
    # sentence Croh's below, and the same one her journal spaces say with a
    # Research Token counted as well.
    out.append(rules_card(
        "r_research", "Did Her Research",
        "At the start of each battle, Abragail powers up.",
        [ability("bstart", [POWER], when=["count:abra@mine.wizard >= 1"])]))

    return out


def potion_templates():
    out = []
    for key, name, tooltip, el, cost, toxic, main, other in POTIONS:
        line = "%s %d%s. %s" % (el.title(), cost, " - TOXIC" if toxic else "", tooltip)
        note = None
        t = {"key": key, "text": name, "tags": ["potion"],
             "asset": POTION_ART[key],
             "story": "%s\n\n%s" % (name, line),
             "tooltip": tip(line, simplified=note)}
        # Counted on the draw rather than on the sip: a third TOXIC ends the
        # Ultimate whether or not the beaker could pay for it.
        play = ["stat_gain:toxic@mine.player:1"] if toxic else []
        # The page has already popped, so the potion is lying in the reveal zone
        # while this runs and that is the zone its own steps are reached through.
        play += ["activate_zone:reveal:by_column:sip"]
        if other: play.append("activate_zone:reveal:by_column:sip2")
        if key != "pot_gasoline":
            play.append("activate_zone:reveal:by_column:again")
            if other: play.append("activate_zone:reveal:by_column:again2")
        play += ["activate_zone:rules:by_column:potion_toxic", "move_to:potion_discard"]
        t["play"] = {"action": play}

        pay = ["stat_damage:%s_el@mine.player:%d" % (el, cost)]
        afford = "%s_el@mine.player >= %d" % (el, cost)
        abil = [ability("sip", pay + list(main[1]),
                        when=[afford] + ([main[0]] if main[0] else []))]
        if other:
            abil.append(ability("sip2", pay + list(other[1]), when=[afford, other[0]]))
        # *I Think I Just Drank Gasoline* doubles the **next** potion, so every
        # potion but that one carries the second helping: the same effect again
        # without the cost, and the flag spent in the doing. Gasoline itself is
        # left out or it would double the damage it takes to set the flag.
        if key != "pot_gasoline":
            spend = ["stat_set:doubled@mine.player:0"]
            abil.append(ability("again", list(main[1]) + spend,
                                when=[afford, "doubled@mine.player >= 1"]
                                     + ([main[0]] if main[0] else [])))
            if other:
                abil.append(ability("again2", list(other[1]) + spend,
                                    when=[afford, "doubled@mine.player >= 1", other[0]]))
        t["abilities"] = abil
        out.append(t)
    return out


def deck_of(calm):
    """The weather deck as the box prints it, duplicates and all."""
    return ["%s:%d" % (w["key"], w["copies"]) if w["copies"] > 1 else w["key"]
            for w in WEATHER if w["calm"] == calm]


def zones():
    P = lambda *r: list(r)
    return [
        # Per-seat. Bottom seat first, top seat second, everywhere.
        #
        # **Mirrored, not rotated.** Two people at a table read the same board
        # from opposite sides, so the second seat's row is the first one's
        # reflected across the middle -- wizard on the left, hand, then deck and
        # discard on the right -- and not turned through half a circle. A rotated
        # board puts your deck where your opponent's wizard is, which is only
        # right if you are actually sitting opposite each other.
        # The chair and whoever is sitting in it, side by side in one box. They
        # were two zones and the seat half was a cell wedged into whatever gap
        # the middle of the board had left, which is how a thing that is only
        # ever read next to the wizard ended up nowhere near it. A grid so it
        # counts as in play: "who holds the Initiative Tracker" is asked of the
        # seat cards as a computed tag, and a tag scope only reaches a board.
        # Labelled with the seat rather than "Wizard": before the pick the box is
        # the only thing that says which chair this is, and after it the wizard's
        # own name is what the chair took.
        {"key": "wizard", "label": "{owner}", "status": "board", "layout": "grid", "grid": [2, 1],
         "copies": "per_seat", "use": "abilities",
         "pos": [P(0.005, 0.795, 0.195, 0.995), P(0.005, 0.005, 0.195, 0.205)]},
        # Named so the box stays on screen when the hand is empty -- which it is
        # across `regroup` and both gain steps, and whenever somebody plays their
        # last card. An unlabelled empty zone draws nothing at all (render.lua).
        # `applies` so that "your hand or discard" -- which four printed cards
        # say and no single zone key covers -- has two kinds to be the union of.
        #
        # Labelled with the seat rather than the word "Hand". Two hands facing
        # each other are obviously hands; what a rule saying "the player with
        # Initiative" needs is a board that points at one of them by name.
        # "{owner}" is the seat this copy belongs to, read off the board.
        {"key": "hand", "label": "{owner}", "layout": "row", "visibility": "owner",
         "copies": "per_seat", "tags": ["held"],
         "pos": [P(0.335, 0.795, 0.730, 0.995), P(0.335, 0.005, 0.730, 0.205)]},
        # Whatever a wizard brings that nobody else has. Empty for seven of the
        # eight, and an empty row with no label draws nothing at all, so a board
        # that has to hold Oren's two potion buttons does not show a hole for
        # them to everybody else. Populated on the pick rather than at setup,
        # which is the only moment that knows which wizard this is.
        {"key": "sidecar", "layout": "row", "copies": "per_seat", "use": "abilities",
         "pos": [P(0.335, 0.575, 0.445, 0.785), P(0.335, 0.215, 0.445, 0.425)]},
        {"key": "deck", "label": "Deck", "layout": "stack", "visibility": "secret",
         "copies": "per_seat", "tags": ["shuffle"], "refill_from": "discard",
         "tooltip": "Your draw deck. When you need a card and it is empty, your discard is shuffled into it.",
         "pos": [P(0.740, 0.795, 0.855, 0.995), P(0.740, 0.005, 0.855, 0.205)]},
        {"key": "discard", "label": "Discard", "layout": "stack", "status": "grave",
         "copies": "per_seat", "tags": ["held"],
         "pos": [P(0.865, 0.795, 0.980, 0.995), P(0.865, 0.005, 0.980, 0.205)]},
        # Where a card waits face down, and where it stands once both are turned
        # over. Two zones rather than one because "who may read this" is a
        # property of the place and not of the moment: `visibility` is declared,
        # so the only way to stop being face down is to be somewhere else.
        #
        # One rect, though: the two are never both occupied, so `commit` sits on
        # `battle` and the reveal is the card turning over where it lay.
        {"key": "battle", "label": "Battle", "layout": "grid", "grid": [1, 1],
         "copies": "per_seat",
         "pos": [P(0.465, 0.575, 0.595, 0.785), P(0.465, 0.215, 0.595, 0.425)]},
        {"key": "commit", "label": "Face down", "layout": "grid", "grid": [1, 1],
         "copies": "per_seat", "visibility": "owner", "pos": "battle",
         "tooltip": "Your card for this round, face down. Only you may read it. It turns over when both players have played."},
        # Omar's armed Trap, face down: the same shape as `commit`, and for the
        # same reason -- who may read a card is a property of the place. A row
        # rather than a grid so that seven of the eight wizards, who have no
        # Traps, get no empty box drawn on their board.
        {"key": "traps", "layout": "row", "copies": "per_seat", "visibility": "owner",
         "use": "abilities",
         "tooltip": "Your armed Trap, face down. Only you may read it. Reveal it when its trigger happens; it is spent until your Ultimate swaps it.",
         "pos": [P(0.745, 0.605, 0.860, 0.785), P(0.745, 0.215, 0.860, 0.395)]},
        # The Traps not in use -- "a nearby face-down pile". Offscreen, because
        # the only thing that ever looks in it is the offer his Ultimate opens,
        # and shared, because only one of the two seats can be Omar.
        {"key": "trap_pile", "layout": "stack", "visibility": "secret",
         "display": "offscreen"},

        # Shared.
        # Its own column, full height, between the wizards and the hands. Five
        # cards stacked in the middle band had 60 pixels of height each and could
        # only be read by hovering them; the whole window gives them nearly
        # double that, which is the difference between a market and a row of
        # thumbnails. The weather took the column it left behind.
        {"key": "storm_cloud", "use": "abilities", "label": "Storm Cloud", "layout": "grid",
         "grid": [1, 5], "applies": ["takeable"],
         "tooltip": "Five cards to gain from. You may only take one at or below your Tier. After any card leaves, another is drawn to replace it.",
         "pos": P(0.205, 0.005, 0.325, 0.995),
         "contents": ["fireessence", "wateressence", "earthessence"]},
        # And the VOID is this deck's grave, for the same reason it is its own.
        # "Resolve a card and then discard it" waits for the resolving to finish,
        # and an Essence resolving VOIDs itself -- so by the time the discard
        # lands the card may have been shuffled back into this deck, the VOID
        # being where it refills from. Discarding it there puts it back in the
        # VOID, which is where a storm card that leaves goes.
        {"key": "spellstorm_deck", "label": "Spellstorm", "layout": "stack",
         "visibility": "secret", "tags": ["shuffle"], "refill_from": "void", "grave": "void",
         "tooltip": "The Spellstorm Deck. When it runs out, the VOID is shuffled to become the new one.",
         "pos": P(0.620, 0.215, 0.740, 0.400),
         "contents": [c["key"] for c in SPELLS]},
        # Its own grave, which is not a joke: a card that dies in the VOID is
        # already where the dead go. The three Essences VOID themselves as they
        # resolve, and the card that made one resolve -- Flame, Spirit Crystal,
        # Wind Dragon -- then says to discard it. That is a card which has
        # already left, and nothing should happen to it.
        {"key": "void", "label": "VOID", "layout": "stack", "use": "none", "grave": "void",
         "tooltip": "Cards removed from the game. When the Spellstorm Deck runs out, this becomes the new one.",
         "pos": P(0.620, 0.410, 0.740, 0.595)},

        {"key": "announce", "label": "{phase}", "layout": "row", "use": "none",
         "tags": ["bare"], "pos": P(0.450, 0.435, 0.610, 0.565)},

        {"key": "weather_now", "label": "Weather", "layout": "stack",
         "tooltip": "This round's weather. Only the current card is active.",
         "pos": P(0.005, 0.215, 0.195, 0.470)},
        {"key": "weather_calm", "label": "Calm", "layout": "stack",
         "visibility": "secret", "tags": ["shuffle"], "refill_from": "weather_main",
         "tooltip": "The eight Calm Before the Storm cards sit on top of the Weather Deck, so the first battles are gentle. When they run out the sixteen standard cards are shuffled in.",
         "pos": P(0.005, 0.490, 0.098, 0.630),
         "contents": deck_of(True)},
        {"key": "weather_main", "label": "Storm", "layout": "stack",
         "visibility": "secret", "tags": ["shuffle"],
         "pos": P(0.102, 0.490, 0.195, 0.630),
         "contents": deck_of(False)},
        {"key": "weather_discard", "layout": "stack", "use": "none",
         "pos": P(0.005, 0.650, 0.195, 0.785)},

        {"key": "ice_pile", "use": "abilities", "label": "Ice", "layout": "stack",
         "applies": ["takeable"], "contents": ["ice:6"],
         "tooltip": "Six ICE. Given to an opponent's discard, and returned here when VOIDed.",
         "pos": P(0.865, 0.215, 0.980, 0.395)},
        {"key": "ash_pile", "use": "abilities", "label": "Ash", "layout": "stack",
         "applies": ["takeable"], "contents": ["ash:6"],
         "tooltip": "Six ASH. Given to an opponent's discard, and returned here when VOIDed.",
         "pos": P(0.865, 0.405, 0.980, 0.585)},
        {"key": "curse_pile", "use": "abilities", "label": "Curse", "layout": "stack",
         "applies": ["takeable"], "contents": ["curse:6"],
         "tooltip": "Six CURSE. Given to an opponent's discard, and returned here when VOIDed.",
         "pos": P(0.865, 0.595, 0.980, 0.775)},
        {"key": "dragon_deck", "label": "Dragons", "layout": "stack",
         "tags": ["shuffle"], "use": "none",
         "tooltip": "Tier IV. Gained by filling your Power Track while already at Tier III.",
         "contents": [c["key"] for c in DRAGONS],
         "pos": P(0.620, 0.605, 0.740, 0.785)},

        # The offer, claimed so a roster of eight wizards has the middle of the
        # screen for one click and no strip of board for the rest of the game.
        {"key": "options", "layout": "row", "status": "offer",
         "display": "offscreen", "pos": P(0.06, 0.28, 0.94, 0.72)},

        # Rules that have to run at a named moment live on cards, and cards have
        # to live somewhere.
        {"key": "rules", "layout": "stack", "display": "offscreen", "use": "none"},

        # The eight wizards, as cards rather than as a list written into two
        # phases. `options:` deals copies and leaves these alone, so a pick
        # destroys its own entry here and the next seat is offered what is left.
        {"key": "roster", "layout": "stack", "display": "offscreen", "use": "none",
         "contents": ["pick_" + w["key"] for w in WIZARDS]},

        # Where a card waits while it is being answered -- one record at a time,
        # and only ever a card announcing the Ultimate icon. Offscreen because
        # the engine already says so across the top of the screen, naming the
        # card and offering the way out, and the board has no strip left.
        # "stack" is the engine's own word for the response window, read off the
        # zone rather than named in a setting -- so the tag is what makes this
        # zone the one flow settles against.
        {"key": "stack", "layout": "stack", "display": "offscreen", "use": "none",
         "tags": ["stack"],
         "tooltip": "A card that has announced itself and is waiting to be answered."},
        # Where cards wait while the player is being asked about them. A set
        # that moves without anybody picking it has no name -- so it is given
        # one, and a zone is how. Offscreen because the question borrows the
        # cards into the offer, which is where they are read.
        {"key": "sifting", "layout": "stack", "display": "offscreen", "use": "none",
         "tooltip": "Cards you are looking at, until the question about them is answered."},
        {"key": "quiet", "layout": "stack", "display": "offscreen", "use": "none",
         "status": "exile",
         "comment": "Empty except for the instant between the two halves of a discard that must not be heard. Riot is the only card that uses it, and it puts them here and takes them away again in consecutive steps.",
         "tooltip": "Cards passing through on their way to a discard that triggers nothing."},
        {"key": "table", "layout": "grid", "grid": [1, 1],
         "display": "offscreen", "use": "abilities"},
        {"key": "potion_deck", "layout": "stack", "visibility": "secret",
         "display": "offscreen", "tags": ["shuffle"], "refill_from": "potion_discard",
         "contents": [pot[0] for pot in POTIONS]},
        {"key": "potion_discard", "layout": "stack", "display": "offscreen",
         "use": "none"},
    ]


# Every step the resolve phases walk, in the order a round runs them.
RESOLVE = ["activate_zone:mine.battle:by_column:cast",
           "activate_zone:mine.battle:by_column:cast2",
           "activate_zone:mine.battle:by_column:cast3",
           "activate_zone:mine.battle:by_column:cast_ask"]


# Abragail's three question spaces, one phase each. An action list has no cursor
# -- whatever follows an ask runs before the answer arrives -- so the ask is the
# last thing each of these does and the next one waits for the phase to come
# back. All three, then the other player's three: one seat at a time, because two
# Abragails would otherwise hold up both hands at once and the second question
# would land in the first one's offer.
#
# The run is a group, which is why `each_seat:` cannot say it: that lives inside
# one action list and stops at the phase boundary. Nothing here names a seat --
# the group's `order` does, once, for the whole run.
JOURNAL_PHASES = [{"key": "journal_%d" % n, "type": "automatic",
                   "actions": ["activate_zone:rules:by_column:jr%d" % n]}
                  for n in JOURNAL_ASKS]


def phases():
    return [
        {"key": "boot", "type": "automatic",
         "actions": ["draw_from:spellstorm_deck:storm_cloud:2"],
         "next": [{"then": "pick"}]},

        # One question per seat, asked out of the offer rather than a zone kept
        # empty for the rest of the game. No `order`, so the table goes round
        # from whoever is next -- which at the top of the game is seat one.
        {"key": "pick", "type": "turn", "seat": "each",
         "phases": ["pick_wizard"], "next": [{"then": "begin"}]},
        {"key": "pick_wizard", "type": "player_input",
         "label": "Choose your wizard",
         "actions": ["options:roster"],
         "ends_when": "picked@mine.player >= 1"},

        {"key": "begin", "type": "automatic",
         "actions": ["each_seat:create:mine.deck:magicdart:2",
                     "each_seat:create:mine.deck:block:2",
                     "each_seat:create:mine.deck:powergem:2",
                     "each_seat:shuffle:mine.deck",
                     "each_seat:activate_zone:rules:by_column:first",
                     "activate_zone:rules:by_column:first_tie"],
         "next": [{"then": "battle_start"}]},

        # A battle begins with three cards in hand. After the first one you are
        # holding the card you gained in Regroup, so this tops up rather than
        # deals -- which is the same line either way.
        {"key": "battle_start", "type": "automatic",
         "actions": ["stat_set:battle_round@plan:0",
                     "each_seat:stat_set:ice_pen@mine.player:0",
                     "each_seat:activate_zone:rules:by_column:bstart",
                     "each_seat:activate_zone:rules:by_column:topup",
                     "each_seat:activate_zone:rules:by_column:topup",
                     "each_seat:activate_zone:rules:by_column:topup"],
         "next": [{"then": "journal"}]},

        # Resolution order all round is the Initiative Tracker, and it is said
        # once here rather than by a `set_active_seat` at the top of every phase
        # that needs it. `initiative` is 1 for whoever holds it and 0 for
        # everybody else, so "highest" is the tracker written as a sort -- and a
        # tie, which the rules can reach before the first battle, falls back to
        # the order the players are listed in.
        {"key": "journal", "type": "turn", "seat": "each", "order": "highest:initiative",
         "phases": [ph["key"] for ph in JOURNAL_PHASES],
         "next": [{"then": "weather"}]},

        ] + JOURNAL_PHASES + [

        # The seat is named before the sweep because `each_seat:` goes round the
        # table from whoever is up: that is how Falling Star says "all players
        # may gain, player with Initiative first". It also settles who commits
        # first, which the printed game leaves open -- both cards go down face
        # down -- and having the Initiative player lead every ordered step of the
        # round is the one answer that is consistent with the rest of it.
        {"key": "weather", "type": "automatic",
         "actions": ["move:weather_now:weather_discard",
                     "draw_from:weather_calm:weather_now:1",
                     "stat_gain:battle_round@plan:1",
                     "set_active_seat:has_init",
                     "each_seat:activate_zone:weather_now:by_column:wx"],
         "next": [{"then": "play"}]},

        # Both players play face down, then reveal together. The card goes to
        # `commit`, which only its own seat may read, so the second player
        # chooses without seeing the first card -- really, over the network;
        # only on the screen, in hot-seat, where the other player watched the
        # click. See the gaps note.
        {"key": "play", "type": "turn", "seat": "each", "order": "highest:initiative",
         "phases": ["play_card"], "next": [{"then": "showdown"}]},
        {"key": "play_card", "type": "player_input",
         "label": "Play a card face down", "zone": ["hand", "wizard", "menu"],
         "ends_when": "count:spell@mine.commit >= 1"},

        # This move is the reveal, and it has to come before anything that reads
        # the two cards against each other: countering asks about `enemy.battle`.
        {"key": "showdown", "type": "automatic",
         "actions": ["each_seat:move:mine.commit:mine.battle",
                     "each_seat:activate_zone:rules:by_column:check",
                     "each_seat:activate_zone:weather_now:by_column:wy"],
         "next": [{"then": "duel"}]},

        # Resolution follows the Initiative Tracker, and each card must resolve
        # while its own seat is up or "mine" would name the wrong player. The
        # announce and the resolution are one seat's turn, taken twice -- which
        # is what the group says, so neither phase names a seat any more.
        #
        # **The announce is a phase of its own, and that is what makes it work.**
        # An action list has no cursor -- whatever follows an ask runs before the
        # answer arrives -- so the ask is the last thing this phase does, and the
        # resolution waits behind it. A phase is the engine's word for "and then".
        {"key": "duel", "type": "turn", "seat": "each", "order": "highest:initiative",
         "phases": ["ult", "resolve"], "next": [{"then": "aftermath"}]},
        {"key": "ult", "type": "automatic",
         "actions": ["activate_zone:mine.battle:by_column:ult_call"]},
        {"key": "resolve", "type": "automatic", "actions": list(RESOLVE)},

        # Both cards have resolved, and this is where whatever happens *then*
        # happens: the weather's last word (Energy Wave's extra Ultimate) and the
        # round announcing that it is over (May's Dangerous Download answers it).
        # Both open windows, so this is a phase for the same reason the announce
        # phases are -- the window has to hold the rest of the round behind it.
        {"key": "aftermath", "type": "automatic",
         "actions": ["each_seat:activate_zone:weather_now:by_column:wz",
                     "each_seat:activate_zone:rules:by_column:round_close"],
         "next": [{"then": "round_end"}]},

        {"key": "round_end", "type": "automatic",
         "actions": ["each_seat:destroy:mine.battle",
                     # An unspent pass does not keep. It is offered while the
                     # card that gave it is resolving and goes out with the round.
                     "each_seat:stat_set:ult_free@mine.player:0",
                     # Dodge! negates the first 2 points *this round*, so what is
                     # left of it goes out with the round the way the pass does.
                     "each_seat:stat_set:guard@mine.traps:0",
                     "each_seat:activate_zone:rules:by_column:tier_up",
                     "each_seat:activate_zone:rules:by_column:tier_up",
                     "each_seat:activate_zone:rules:by_column:tier_gem"],
         "next": [{"when": "battle_round@plan >= 4", "then": "regroup"},
                  {"then": "weather", "ends_round": True}]},

        # Regroup: the four weather cards go, discard effects fire, what is left
        # in hand is a Blast Score, and each player gains one card.
        {"key": "regroup", "type": "automatic",
         "actions": ["move:weather_now:weather_discard",
                     "each_seat:destroy:mine.hand.has_discard",
                     "each_seat:destroy:mine.hand.junk",
                     "each_seat:activate_zone:rules:by_column:score",
                     "each_seat:activate_zone:rules:by_column:award_win",
                     "each_seat:activate_zone:rules:by_column:award_tie",
                     "each_seat:destroy:mine.hand",
                     "each_seat:stat_set:took@mine.player:0"],
         "next": [{"then": "gain"}]},

        # The counter is zeroed for everybody by the phase before, because a
        # group runs its body once per player and a reset inside it would wipe
        # the first player's answer on the way to asking the second.
        {"key": "gain", "type": "turn", "seat": "each", "order": "highest:initiative",
         "phases": ["gain_card"],
         "next": [{"then": "battle_start", "ends_round": True}]},
        {"key": "gain_card", "type": "player_input",
         "label": "Gain a card from the Storm Cloud",
         "zone": ["wizard", "menu"],
         "ends_when": "took@mine.player >= 1"},
        # Oren's Ultimate pushes this over whatever he was doing and the two
        # potion buttons are the only things reachable while it is up. It ends
        # when one of them says so, or when a third TOXIC says so -- so it has no
        # "ends_when" of its own: what ends it is an action, every time.
        {"key": "potion", "type": "player_input", "label": "Bottoms up, I guess!",
         "zone": ["sidecar"]},

    ]


def build():
    cards = []
    for c in BASIC + ESSENCE + SPELLS + JUNK + DRAGONS:
        cards.append(spell_template(c))
    for w in WIZARDS:
        cards += wizard_templates(w)
        for s in w["spells"]:
            cards.append(spell_template(s))
    for w in WEATHER:
        cards.append(weather_template(w))
    cards += potion_templates()
    cards += swap_templates()
    cards += choice_templates()
    cards += trap_templates()
    cards += rules_templates()

    # Top-up: three abilities' worth of "draw if you are short", because a
    # phase cannot say "draw until you hold three" in one line.
    cards.append(rules_card(
        "r_topup", "Battle Start",
        "At the start of a battle every player draws until they hold three cards.",
        [ability("topup", [DRAW], when=["count:spell@mine.hand <= 2"])]))

    # The two seats. Health carries its own ceiling because a wizard raises it
    # when it is chosen, and stat_boost can only move a ceiling that exists.
    for key, label in (("seat_one", "Player One"), ("seat_two", "Player Two")):
        cards.append({"key": key, "text": "{name}", "name": label,
                      "tags": ["seat", "chair"],
                      "tooltip": "Your wizard, your health, your Storm Shards.",
                      "card_stats": {"health": {"value": 1, "min": 0, "max": 1}}})

    # The scratch card the battle's round number lives on.
    cards.append({"key": "plan", "text": "The Battle", "tags": ["immutable", "plan"],
                  "asset": "auto",
                  "tooltip": "A battle is four rounds, then a Regroup."})

    # Two board buttons. Neither charges exhaust, so both stay clickable.
    cards.append({
        "key": "btn_unplayable", "text": "Unplayable hand",
        "asset": "cross:slate", "tags": ["immutable"],
        "tooltip": "If your hand is nothing but ICE, ASH and CURSE, use this: discard them all with their effects, take 1 damage, and draw a new hand of 4.",
        "abilities": [{"phases": ["play_card"],
                     "action": ["destroy:mine.hand",
                                SELF_DMG(1),
                                "draw_from:mine.deck:mine.hand:4"]}]})
    cards.append({
        "key": "btn_potion_draw", "text": "Draw a potion",
        "asset": "auto", "tags": ["immutable"],
        "tooltip": "Draw the next potion. Its effect happens only if the Element it costs is high enough on your Chemistry Board.",
        "abilities": [{"phases": ["potion"], "action": ["reveal_top:potion_deck"]}]})
    cards.append({
        "key": "btn_potion_stop", "text": "Stop drinking",
        "asset": "auto", "tags": ["immutable"],
        "tooltip": "End your Ultimate while you are ahead. Your Elements go back to 3.",
        "abilities": [{"phases": ["potion"], "action": list(POTION_END)}]})
    # The button opens the page; the page is where the rules are. Hovering it
    # for the same words worked and read as nothing happening -- a sparkle and
    # no answer -- because the only place the text lived was a tooltip nobody
    # thought to hover on a thing that plainly wanted clicking.
    cards.append({
        "key": "btn_rules", "text": "The rules",
        "asset": "diamond:slate", "tags": ["immutable"],
        "tooltip": "How Spellstorm is won and how a battle runs. Click to read it.",
        "abilities": [{"action": ["reveal:rules_page"]}]})
    cards.append({
        "key": "rules_page", "text": "Spellstorm", "asset": "diamond:slate",
        "tags": ["immutable"],
        "story": ("SPELLSTORM. Win by reaching 8 Storm Shards, or by taking your "
                 "opponent to 0 health.\n\n"
                 "A battle is four rounds. Each round: the weather is flipped and "
                 "resolved, both players play a card face down, the cards are "
                 "revealed, and they resolve in Initiative order. Countering the "
                 "opponent -- Fire beats Earth, Earth beats Water, Water beats Fire "
                 "-- draws you a card.\n\n"
                 "After four rounds comes the Regroup: discard effects fire, the "
                 "cards you still hold are your Blast Score, the higher score takes "
                 "2 Storm Shards (1 each on a tie), and each player gains one card "
                 "from the Storm Cloud at or below their Tier.\n\n"
                 "Six Power Tokens fill your track; filling it raises your Tier. At "
                 "Tier III a filled track gains you a Dragon instead.")})

    # Endings.
    cards.append({"key": "end_shards", "outcome": "victory",
                  "text": "The Shards Are Taken", "asset": "auto",
                  "story": "Eight Storm Shards. The storm answers to you now, and the crag is quiet for the first time in an age.",
                  "play": {"action": ["load_game:menu.json"]}})
    cards.append({"key": "end_dead", "outcome": "defeat",
                  "text": "Overwhelmed", "asset": "auto",
                  "story": "The Spellstorm takes what it is owed. Somewhere below the waves, something with too many teeth finishes the sentence you started.",
                  "play": {"action": ["load_game:menu.json"]}})

    game = {
        "title": "Spellstorm",
        "players": [{"card": "seat_one"}, {"card": "seat_two"}],
        "stats": [
            {"key": "health", "label": "Health", "icon": "heart", "color": "crimson",
             "min": 0, "max": 20, "subject": "health@mine.player",
             "on": ["player"], "start": 0},
            {"key": "shards", "label": "Storm Shards", "icon": "diamond",
             "color": "violet", "min": 0, "max": 8,
             "subject": "shards@mine.player", "on": ["player"], "start": 0},
            {"key": "mana", "label": "Mana", "icon": "orb", "color": "magenta",
             "min": 0, "max": 40, "subject": "mana@mine.player",
             "on": ["player"], "start": 2},
            {"key": "power", "label": "Power", "icon": "coin", "color": "gold",
             "min": 0, "max": 12, "subject": "power@mine.player",
             "on": ["player"], "start": 0},
            {"key": "tier", "label": "Tier", "icon": "banner", "color": "amber",
             "min": 1, "max": 4, "subject": "tier@mine.player",
             "on": ["player"], "start": 1},
            {"key": "initiative", "label": "Initiative", "icon": "arrow",
             "color": "yellow", "min": 0, "max": 1,
             "subject": "initiative@mine.player", "on": ["player"], "start": 0},
            {"key": "doom", "label": "Doom", "icon": "fist", "color": "indigo",
             "min": 0, "max": 4, "subject": "doom@mine.player",
             "on": ["player"], "start": 0},
            {"key": "energy", "label": "Energy", "icon": "shield", "color": "teal",
             "min": 0, "max": 3, "subject": "energy@mine.player",
             "on": ["player"], "start": 0},
            {"key": "research", "label": "Research", "icon": "leaf",
             "color": "olive", "min": 0, "max": 6,
             "subject": "research@mine.player", "on": ["player"], "start": 0},
            # Oren's Chemistry Board: three beakers, 0 to 6, that his potions
            # are paid out of and that go back to 3 when his Ultimate ends.
            {"key": "fire_el", "label": "Fire", "icon": "pot", "color": "orange",
             "min": 0, "max": 6, "subject": "fire_el@mine.player",
             "on": ["player"], "start": 0},
            {"key": "earth_el", "label": "Earth", "icon": "pot", "color": "brown",
             "min": 0, "max": 6, "subject": "earth_el@mine.player",
             "on": ["player"], "start": 0},
            {"key": "water_el", "label": "Water", "icon": "pot", "color": "cyan",
             "min": 0, "max": 6, "subject": "water_el@mine.player",
             "on": ["player"], "start": 0},

            # Working numbers. Hidden, floored at zero -- the floor is what makes
            # the Blast Score subtraction clamp instead of going negative.
            {"key": "blast", "min": 0, "max": 99, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "ice_pen", "min": 0, "max": 99, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "init_rating", "min": 0, "max": 99, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "picked", "min": 0, "max": 9, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "took", "min": 0, "max": 9, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "toxic", "min": 0, "max": 9, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            # Obsidian's pass. A one-shot, like Oren's doubled potion, and it
            # is spent by being a cost rather than by anything checking it.
            {"key": "ult_free", "min": 0, "max": 1, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "doubled", "min": 0, "max": 1, "tags": ["hidden"],
             "on": ["player"], "start": 0},
            {"key": "battle_round", "min": 0, "max": 9, "tags": ["hidden"],
             "on": ["plan"], "start": 0},
            # Read off the card on the shelf rather than the player: what it
            # costs in Tier to take it.
            {"key": "tier_req", "min": 0, "max": 9, "tags": ["hidden"]},
            # A Research Token, read off the journal space it sits on.
            {"key": "researched", "min": 0, "max": 1, "tags": ["hidden"]},
            # A Trap that has been revealed. It stays where it lies and does
            # nothing more until the Ultimate swaps it out.
            {"key": "sprung", "min": 0, "max": 1, "tags": ["hidden"]},
            # What is left of Omar's Dodge!, written on the Trap that set it.
            {"key": "guard", "min": 0, "max": 2, "tags": ["hidden"]},
            # What a card standing for a choice is worth, written onto it before
            # the question opens so that the card can say the number out loud.
            {"key": "counted", "min": 0, "max": 9, "tags": ["hidden"]},
        ],
        # A tag is what a card *is*, and these are the kinds the printed cards
        # name that no single tag did.
        #
        # "Wherever I am keeping it" used to live here, and it was five of these:
        # the hand and the discard each handed out a tag, "held" was a union of
        # the two, and then one "and" per kind put the real question back --
        # over `everywhere`, which is every card in the game. "held" is a word
        # both zones wear now, so a scope's place half says it: `mine.held.ice`.
        "computed_tags": {
            "has_init": {"needs": ["initiative@self >= 1"]},
            "curse_or_ice": {"any_of": ["curse", "ice"]},
            # One card in the box, and no tag of its own says so: an element and
            # the word "essence" name it between them, and a list of conditions
            # already means and. Derby's opening takes the real card off the shelf.
            "earth_essence": {"needs": ["tagged:earth@self", "tagged:essence@self"]},
        },
        # **The number is the condition, so there is no condition.** Derby's
        # Ultimate gives two mana at an odd number of health and none at an even
        # one; a remainder says that as an amount, and nothing in the card has to
        # ask a question. `%` binds as `*` does, so this is (health % 2) * 2.
        "computes": [{"key": "yardstick_mana", "value": "health@mine.player % 2 * 2",
                      "tooltip": "Two mana at an odd number of health, none at an even one."}],
        "verbs": [{"key": "heal", "does": "stat_gain",
                   "tooltip": "Healing. Named as a moment of its own so that a rule can answer it - the engine's own stat_gain is unwatchable on purpose."},
                  {"key": "hit", "does": "stat_damage",
                   "tooltip": "A blow from across the table. Declared, so it announces itself and a Trap can answer it."},
                  {"key": "hurt", "does": "stat_damage",
                   "tooltip": "Damage you do to yourself. A cost rather than an attack, so nothing answers it."},
                  {"key": "wound", "does": "stat_damage",
                   "tooltip": "Damage as it arrives, once anything standing in front of it has taken its bite."}],
        "styles": {
            "ember": {"color": [0.62, 0.20, 0.16], "hide": ["title"]},
            "tide":  {"color": [0.16, 0.36, 0.58], "hide": ["title"]},
            "loam":  {"color": [0.45, 0.34, 0.14], "hide": ["title"]},
            "storm": {"color": [0.18, 0.36, 0.32], "hide": ["title"]},
            "wizard_card": {"color": [0.24, 0.16, 0.34], "hide": ["title"]},
            "chooser": {"color": [0.24, 0.16, 0.34], "hide": ["title"]},
            "potion": {"color": [0.32, 0.42, 0.18], "hide": ["title"]},
            "chair": {"color": [0.13, 0.15, 0.22]},
        },
        "tags": {
            # What a card on a shelf does: it comes to your hand, if your Tier
            # reaches it, and the shelf refills behind it. An ability rather than
            # a play, because an ability's "needs" is read where a granted play's
            # "needs" is not -- and because a card on a shelf must not be
            # castable, which "merge": "this" is what says.
            "takeable": {
                "tooltip": "Gain this card. You may only take a card at or below your Tier.",
                "abilities": [{
                    "key": "take", "text": "Gain this card", "merge": "this",
                    "phases": ["gain_card"],
                    "needs": ["tier@mine.player >= tier_req@self"],
                    "action": ["move_to:mine.hand",
                               REFILL_CLOUD, "stat_gain:took@mine.player:1"]}]},
            # The [ULT] icon, said once for the twenty-seven cards that carry
            # it. A phase of its own walks the battle spots for this one
            # ability, so only a card wearing the icon announces itself -- and
            # it is the card that announces, not a rule about the round, because
            # the window the player is shown says which card opened it. On the
            # tag rather than on each card because "carries the icon" is what
            # the tag already means, and a column walk reaches a tag's abilities
            # exactly as it reaches a card's own.
            "ult": {"abilities": [{"key": "ult_call", "text": "Ultimate",
                                   "action": ["emit:resolving"]}]},
            # Croh's passive, printed on Croh's card. `instead` is what says the
            # healing does not happen at all -- no shift reaches "do this other
            # thing rather than that one" -- and the list runs as the aura's own
            # side, so the CURSE goes from the cursed player to the other seat
            # whoever was doing the healing. `covers` reads the seat card from
            # Croh's, which is where the health it guards actually lives.
            # Triple Stitch! -- the other end of the same hook. At his ceiling
            # every point of healing is wasted, so replacing the whole heal with
            # a draw apiece *is* the printed rule, and `amount` is the size of
            # the heal that would have landed. Below the ceiling it says nothing,
            # which is the card too: the condition is "already at 10", not "some
            # of it was wasted".
            "overhealing": {
                "adjusts": [{"key": "spare", "verb": "heal", "stat": "health",
                             "covers": "mine.player",
                             "needs": ["health@mine.player >= 10"],
                             "instead": ["draw_from:mine.deck:mine.hand:amount"]}]},
            "accursed": {
                "adjusts": [{"key": "curse", "verb": "heal", "stat": "health",
                             "covers": "mine.player",
                             "instead": GIVE("curse")}]},
            # Omar's Dodge!, printed on Omar's card and reading the budget off
            # the Trap that set it.
            #
            # **"The first 2 points" is two points, each said once.** `by` takes a
            # number and not a measure, so a budget of two is two shifts of one,
            # and each asks whether that much of it is still there. Three would be
            # three lines; nothing in the box says three.
            #
            # **And it is spent as it is used.** The hit does not land: a wound of
            # the same size lands in its place, which is what the two shifts are
            # about, and the budget goes down by the size of the blow. stat_damage
            # stops at the floor, so a hit bigger than what is left uses up the
            # rest and no more -- which is the whole of "the first 2 points",
            # across as many blows as the round holds.
            "dodging": {
                "adjusts": [
                    {"key": "soak_one", "verb": "wound", "stat": "health",
                     "covers": "mine.player", "needs": ["guard@mine.traps >= 1"], "by": -1},
                    {"key": "soak_two", "verb": "wound", "stat": "health",
                     "covers": "mine.player", "needs": ["guard@mine.traps >= 2"], "by": -1},
                    {"key": "soak", "verb": "hit", "stat": "health",
                     "covers": "mine.player", "needs": ["guard@mine.traps >= 1"],
                     "instead": SOAK},
                    # Damage you take is damage you take, whoever dealt it, so the
                    # same replacement answers the blow you do to yourself.
                    {"key": "soak_self", "verb": "hurt", "stat": "health",
                     "covers": "mine.player", "needs": ["guard@mine.traps >= 1"],
                     "instead": SOAK}]},
        },
        "zones": zones(),
        "phases": phases(),
        "cards": cards,
        "effects": {"spark": {"base": "sparkle"}},
        "end_conditions": [
            {"when": "max:shards@anyone.player >= 8", "then": ["reveal:end_shards"]},
            {"when": "min:health@anyone.player <= 0", "then": ["reveal:end_dead"]},
        ],
        "setup": {"place": [
            {"card": "seat_one", "owner": "seat_one", "zone": "wizard"},
            {"card": "seat_two", "owner": "seat_two", "zone": "wizard"},
            {"card": "plan", "zone": "table"},
            {"card": "btn_rules", "zone": "menu"},
            {"card": "btn_unplayable", "zone": "menu"},
        ]},
    }

    # Every rules card into the rules zone. They are not scenery a player sees,
    # so they are placed rather than dealt.
    for c in cards:
        if c["key"].startswith("r_"):
            game["setup"]["place"].append({"card": c["key"], "zone": "rules"})

    # Last, and over everything: the prose a player reads is marked up here
    # rather than at the fifty places that write it, so a tooltip typed into a
    # zone gets the same treatment as one a card template assembled.
    for group in (game["cards"], game["zones"]):
        for e in group:
            for field in ("tooltip", "story"):
                if e.get(field):
                    e[field] = mark(e[field])
    return game


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = guard.destination(os.path.join(here, "..", "game", "games", "spellstorm.json"), sys.argv[1:])
    if out is None:
        sys.exit(1)
    g = build()
    with open(out, "w") as f:
        f.write(jsonfmt.dump(g))
    print("%s: %d cards, %d zones, %d phases"
          % (out, len(g["cards"]), len(g["zones"]), len(g["phases"])))
