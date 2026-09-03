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
HEAL  = lambda n: "stat_gain:health@mine.player:%d" % n
DMG   = lambda n: "stat_damage:health@enemy.player:%d" % n
SELF_DMG = lambda n: "stat_damage:health@mine.player:%d" % n
SHARD = lambda n: "stat_gain:shards@mine.player:%d" % n

# Initiative is one tracker, so taking it is two writes and there is no way to
# say it as one. Both spellings exist because both directions appear on cards.
GAIN_INIT = ["stat_set:initiative@mine.player:1", "stat_set:initiative@enemy.player:0"]
LOSE_INIT = ["stat_set:initiative@mine.player:0", "stat_set:initiative@enemy.player:1"]

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
DISCARD_RANDOM = lambda who: "move:random.%s.hand:%s.discard" % (who, who)

# Offering the Storm Cloud. `show:` lends the real cards, so what comes back is
# the card that was on the shelf rather than a copy of it; the `chosen` block on
# each card says where its pick lands and refills the shelf behind it.
OFFER_CLOUD = "show:storm_cloud:optional"
OFFER_HAND  = "show:mine.hand:optional"
REFILL_CLOUD = "draw_from:spellstorm_deck:storm_cloud:1"
TAKE_TO_HAND = ["move_target_to:mine.hand", REFILL_CLOUD]

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
         disc=None, chosen=None, tier=None, kind="spell", flavour=None,
         simplified=None, asset=None, tags=(), comment=None):
    return dict(key=key, name=name, element=element, tooltip=tooltip,
                cast=list(cast), cast2=cast2, cast3=cast3, disc=disc,
                chosen=chosen, tier=tier, kind=kind, flavour=flavour,
                simplified=simplified, asset=asset, tags=list(tags),
                comment=comment)


# --- The six-card starting deck -------------------------------------------

BASIC = [
    card("magicdart", "Magic Dart", FIRE, kind="basic",
         tooltip="Gain 1 mana. If you have Initiative, deal 1 damage.",
         flavour="Fire magic is often banned from use in many parts of the world, due to its unpredictable nature.",
         cast=[MANA], cast2=(HAS_INIT, [DMG(1)])),
    card("block", "Block", WATER, kind="basic",
         tooltip="Gain Initiative. Heal 1 for every Fire card revealed this round.",
         flavour='"He just needs a little splash, is all he needs." - The Splashmaster',
         cast=GAIN_INIT + ["stat_gain:health@mine.player:count:fire@battle"]),
    card("powergem", "Power Gem", EARTH, kind="basic",
         tooltip="Power up. You may gain a card from the Storm Cloud; if you do, it goes to your discard. On discard: power up.",
         flavour="The golden gems of the Spell Storm take time to develop their power.",
         cast=[POWER, OFFER_CLOUD],
         chosen=["move_target_to:mine.discard", REFILL_CLOUD],
         disc=[POWER]),
]

# --- The three Essence cards, seeded into the Storm Cloud at setup ---------
# Each voids itself and lets you take a card of its own element. The engine's
# offer cannot be narrowed to one element, so the whole shelf is offered.

ESSENCE = [
    card("fireessence", "Fire Essence", FIRE, kind="essence", tier=1,
         tooltip="Deal 1 damage. You may gain any Tier I or II Fire card in the Storm Cloud. VOID this.",
         flavour="Fire Magic is generally associated with destruction.",
         simplified="the offer is not narrowed to Fire, or to Tier I-II",
         cast=[DMG(1), "move_to:void", OFFER_CLOUD], chosen=TAKE_TO_HAND),
    card("wateressence", "Water Essence", WATER, kind="essence", tier=1,
         tooltip="Gain 1 mana. You may gain any Tier I or II Water card in the Storm Cloud. VOID this.",
         flavour="Water Magic is generally associated with healing.",
         simplified="the offer is not narrowed to Water, or to Tier I-II",
         cast=[MANA, "move_to:void", OFFER_CLOUD], chosen=TAKE_TO_HAND),
    card("earthessence", "Earth Essence", EARTH, kind="essence", tier=1,
         tooltip="Power up. You may gain any Tier I or II Earth card in the Storm Cloud. VOID this. On discard: power up.",
         flavour="Earth Magic is generally associated with building.",
         simplified="the offer is not narrowed to Earth, or to Tier I-II",
         cast=[POWER, "move_to:void", OFFER_CLOUD], chosen=TAKE_TO_HAND,
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
    card("flame", "Flame", FIRE, tier=1,
         tooltip="Deal 1 damage, then resolve and discard a different Fire card from your hand.",
         flavour="You need *magic* water to put a magical flame out.",
         simplified="the offer is not narrowed to Fire cards",
         cast=[DMG(1), OFFER_HAND],
         chosen=["copy:target:activate", "move_target_to:mine.discard"]),
    card("heartgem", "Heart Gem", FIRE, tier=1,
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
         simplified="the printed card moves a Fire card between any two discards; here it is their discard to yours, any card",
         cast=[MANA] + GAIN_INIT + ["show:enemy.discard:optional"],
         chosen=["move_target_to:mine.discard"]),
    card("manafont", "Mana Font", FIRE, tier=1,
         tooltip="VOID a card in the Storm Cloud. If you did, gain 3 mana. On discard: take 1 damage and gain 1 mana.",
         flavour="While there are many theories, no one knows where the magic inside gems originally comes from.",
         simplified="the offer is not narrowed to Water cards",
         cast=[OFFER_CLOUD],
         chosen=["move_target_to:void", REFILL_CLOUD, MANA, MANA, MANA],
         disc=[SELF_DMG(1), MANA]),
    card("obsidian", "Obsidian", FIRE, tier=2,
         tooltip="Take 1 damage and lose 2 mana. If you did, you may use your Ultimate without paying its mana cost.",
         flavour='"Whenever I close my eyes, I see my twisted reflection in that black mirrored gem." - Unknown',
         simplified="the free Ultimate is not granted -- there is no way to waive a cost; the damage and mana loss happen",
         cast=[SELF_DMG(1), "stat_damage:mana@mine.player:2"]),
    card("rapidfire", "Rapid Fire", FIRE, tier=2,
         tooltip="Draw a card. If you have Initiative, deal 2 damage and you may redraw this to your hand.",
         flavour="When going for a fire-based strategy, it's important to keep the pressure on.",
         simplified="returning the card to hand is not optional; if you have Initiative it always comes back",
         cast=[DRAW], cast2=(HAS_INIT, [DMG(2), "move_to:mine.hand"])),
    card("ruby", "Ruby", FIRE, tier=1,
         tooltip="Discard the top 3 cards of your deck and deal 1 damage.",
         flavour="The popular trend of ruby-adorned garments was blamed for the Great Royal Ball Fire of 1976.",
         simplified="the printed card deals 1 damage per Fire discarded, or voids one instead; there is no way to count what was just discarded, so it deals a flat 1",
         cast=["draw_from:mine.deck:mine.discard:3", DMG(1)]),
    card("shockwave", "Shockwave", FIRE, tier=2,
         tooltip="Your opponent loses 2 Power Tokens and discards a card. You gain Initiative. Deal 1 damage.",
         flavour='The 1981 hit song "Shockwave" is often credited with creating the Bonepunk genre.',
         cast=["stat_damage:power@enemy.player:2",
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
         tooltip="Give an ICE. You may VOID an ICE from your hand. Gain Initiative.",
         flavour='"Watch your step!" - Unknown',
         simplified="the offer is your hand only, and is not narrowed to ICE",
         cast=GIVE("ice") + GAIN_INIT + [OFFER_HAND],
         chosen=["move_target_to:ice_pile"]),
    card("lapis", "Lapis", WATER, tier=1,
         tooltip="Draw a card. You may discard a card and heal 1.",
         flavour="Doctors throughout Omia have used Water Magic to heal the sick for generations.",
         simplified="the printed card discards up to 2 and heals 1 per Water discarded; here it is one card and a flat 1",
         cast=[DRAW, OFFER_HAND],
         chosen=["move_target_to:mine.discard", HEAL(1)]),
    card("leap", "Leap", WATER, tier=2,
         tooltip="Gain Initiative and heal 1. If your opponent revealed Fire, you may VOID a card from your hand.",
         flavour="Azure wizards historically specialized in Water Gems, but they have since taken others from throughout the globe.",
         cast=GAIN_INIT + [HEAL(1)],
         cast2=("count:fire@enemy.battle >= 1", [OFFER_HAND]),
         chosen=["move_target_to:void"]),
    card("moonstone", "Moonstone", WATER, tier=3,
         tooltip="Heal 4. On discard: heal 2.",
         flavour="The rare and beautiful Moonstone is one of the most coveted in all of Omia.",
         cast=[HEAL(4)], disc=[HEAL(2)]),
    card("reflect", "Reflect", WATER, tier=2,
         tooltip="Draw a card, gain Initiative, heal 1. If your opponent revealed Fire, they take 2 damage.",
         flavour='"He just needs a little splash, is all he needs." - The Splashmaster',
         cast=[DRAW] + GAIN_INIT + [HEAL(1)],
         cast2=("count:fire@enemy.battle >= 1", [DMG(2)])),
    card("sapphire", "Sapphire", WATER, tier=1,
         tooltip="Draw a card, heal 1, and gain an ASH.",
         flavour='Many of Omia\'s most impressive Wizards have a signature move, which some call an "Ultimate".',
         cast=[DRAW, HEAL(1)] + GAIN_JUNK("ash")),
    card("step", "Step", WATER, tier=1,
         tooltip="If you have Initiative, heal 1. Otherwise, gain Initiative. On discard: gain Initiative.",
         flavour="From the year 366-1182, the Water Kingdom reigned over much of the Eastern Continent.",
         cast2=(HAS_INIT, [HEAL(1)]), cast3=(NO_INIT, GAIN_INIT),
         disc=GAIN_INIT),
    card("twinsapphire", "Twin Sapphire", WATER, tier=2,
         tooltip="Draw a card and heal 2.",
         flavour='"TWO sapphires?! Wow, thanks!" - Someone\'s son',
         cast=[DRAW, HEAL(2)]),
    card("ultimate", "Ultimate", WATER, tier=1,
         tooltip="You may VOID a card from your hand. If you did, gain 3 mana.",
         flavour='"He just needs a little splash, is all he needs." - The Splashmaster',
         simplified="the offer is not narrowed to Earth cards",
         cast=[OFFER_HAND],
         chosen=["move_target_to:void", MANA, MANA, MANA]),
    card("wave", "Wave", WATER, tier=2,
         tooltip="Gain 3 mana. Your opponent discards their hand and draws a new hand of 4 cards.",
         flavour="A wave does not ask what it washes away.",
         cast=[MANA, MANA, MANA, "move:enemy.hand:enemy.discard",
               "draw_from:enemy.deck:enemy.hand:4"]),

    # Earth
    card("amber", "Amber", EARTH, tier=1,
         tooltip="Power up. You must gain a card from the Storm Cloud. On discard: power up.",
         flavour="The Business Demons considered drilling operations at the Spellstorm, but it was deemed too costly.",
         simplified="the printed card gains twice and is mandatory; here it gains once and may be declined",
         cast=[POWER, OFFER_CLOUD], chosen=TAKE_TO_HAND, disc=[POWER]),
    card("bloodstone", "Bloodstone", EARTH, tier=1,
         tooltip="Gain 1 mana. Take 1 damage. You may VOID a card from your hand. On discard: gain 1 mana.",
         flavour='"It\'s best to leave gems that you find in the wild alone, unless you really know what you\'re doing." - Abragail',
         simplified="the offer is your hand only, not hand or discard",
         cast=[MANA, SELF_DMG(1), OFFER_HAND],
         chosen=["move_target_to:void"], disc=[MANA]),
    card("diamond", "Diamond", EARTH, tier=1,
         tooltip="If you hold 3 or more other cards, discard 3 of them and power up 3 times. On discard: power up.",
         flavour='"Learned more spells in 1 day at the Spellstorm, than I had in the past 3 years." - Azura Spellstorm Scholar',
         simplified="the three discarded cards are the first three in hand rather than your choice",
         cast2=("count:spell@mine.hand >= 3",
                ["draw_from:mine.hand:mine.discard:3", POWER, POWER, POWER]),
         disc=[POWER]),
    card("meteorite", "Meteorite", EARTH, tier=1,
         tooltip="Take 1 damage. You may resolve any card in the Storm Cloud regardless of tier, then VOID it. On discard: take 1 damage.",
         flavour='"Mom! Look! This fell from the sky!" - A child of Tiya Bannet',
         cast=[SELF_DMG(1), OFFER_CLOUD],
         chosen=["move_target_to:void", "copy:target:activate", REFILL_CLOUD],
         disc=[SELF_DMG(1)]),
    card("opal", "Opal", EARTH, tier=3,
         tooltip="Draw a card, power up twice, gain 2 mana, and you may gain a card from the Storm Cloud. On discard: power up twice.",
         flavour="Gems are rocks found deep in the earth that are charged with mysterious power.",
         cast=[DRAW, POWER, POWER, MANA, MANA, OFFER_CLOUD],
         chosen=TAKE_TO_HAND, disc=[POWER, POWER]),
    card("quake", "Quake", EARTH, tier=1,
         tooltip="Your opponent loses 2 Power Tokens and gains an ASH. You may gain a card from the Storm Cloud. On discard: power up.",
         flavour="A huge earthquake that happened in 1951 is attributed to the emergence of the Business Demons.",
         cast=["stat_damage:power@enemy.player:2"] + GIVE("ash") + [OFFER_CLOUD],
         chosen=TAKE_TO_HAND, disc=[POWER]),
    card("shatter", "Shatter", EARTH, tier=2,
         tooltip="You may VOID a card from your hand; if you do, power up. On discard: power up.",
         flavour='"That there spellstorm water\'s FULL-a gold, I tell ya!" - Prospector',
         simplified="the printed card voids up to 2; here it is one",
         cast=[OFFER_HAND], chosen=["move_target_to:void", POWER], disc=[POWER]),
    card("sift", "Sift", EARTH, tier=1,
         tooltip="Power up. Draw 2 cards, then you may discard one of them.",
         flavour="Almost all Earth cards have discard effects.",
         simplified="the printed card looks at the top 2 and may put them back in order; here they are drawn and one may be discarded",
         cast=[POWER, "draw_from:mine.deck:mine.hand:2", OFFER_HAND],
         chosen=["move_target_to:mine.discard"]),
    card("spiritcrystal", "Spirit Crystal", EARTH, tier=1,
         tooltip="Draw a card. Reveal a card from your hand, resolve it and then discard it. On discard: power up.",
         flavour="It's said that Earth magic is the oldest form of magic, which is why so many stones are imbued with powers.",
         simplified="the offer is not narrowed to Earth cards",
         cast=[DRAW, OFFER_HAND],
         chosen=["copy:target:activate", "move_target_to:mine.discard"],
         disc=[POWER]),
    card("threepower", "Three Power", EARTH, tier=2,
         tooltip="Power up twice and you may gain a card from the Storm Cloud. If anyone revealed Water, power up again. On discard: power up twice.",
         flavour='When you see the "Gain Card" icon on a card, keep in mind that you may choose not to gain a card.',
         cast=[POWER, POWER, OFFER_CLOUD],
         cast2=("count:water@battle >= 1", [POWER]),
         chosen=TAKE_TO_HAND, disc=[POWER, POWER]),
    card("twopower", "Two Power", EARTH, tier=1,
         tooltip="Power up twice and you may gain a card from the Storm Cloud. On discard: power up twice.",
         flavour='When you see the "Gain Card" icon on a card, keep in mind that you may choose not to gain a card.',
         cast=[POWER, POWER, OFFER_CLOUD],
         chosen=TAKE_TO_HAND, disc=[POWER, POWER]),
]

# --- Special cards: the three junk piles and the five Dragons -------------
# ICE, ASH and CURSE cannot be played. They carry no `playable` stat, which is
# what the hand's play block tests, so they sit in a hand doing nothing but
# blocking a Blast Score -- exactly what they are for.

JUNK = [
    card("ice", "Ice", WATER, kind="junk",
         tooltip="This can't be played. On discard during Regroup: -1 to your Blast Score.",
         flavour='"Ice cut into a cube shape is kind of like a gem." - Beosnook',
         disc=["stat_gain:ice_pen@mine.player:1"], tags=["junk"]),
    card("ash", "Ash", EARTH, kind="junk",
         tooltip="This can't be played. On discard: lose 1 Power Token.",
         flavour="The Spellstorm is a highly volcanic area, often covered in ash.",
         disc=["stat_damage:power@mine.player:1"], tags=["junk"]),
    card("curse", "Curse", FIRE, kind="junk",
         tooltip="This can't be played. On discard: take 1 damage.",
         flavour='"Curses!" - H.M.T. Holliganger, Distinguished Professor at the Azura Academy School of Archaeology',
         disc=[SELF_DMG(1)], tags=["junk"]),
]

DRAGONS = [
    card("firedragon", "Fire Dragon", FIRE, tier=4, kind="dragon",
         tooltip="Deal 4 damage. Gain 2 mana.",
         flavour="No Dragon is more feared than the destructive and terrible Fire Dragon.",
         cast=[DMG(4), MANA, MANA]),
    card("winddragon", "Wind Dragon", FIRE, tier=4, kind="dragon",
         tooltip="Gain Initiative. Gain a Storm Shard. You may resolve a card from your hand.",
         flavour="The elusive Storm Dragons were considered to be cryptids until very recently.",
         simplified="the printed card resolves up to two cards; here it is one, and the card resolved is then discarded — the printed card may not say that",
         cast=GAIN_INIT + [SHARD(1), OFFER_HAND],
         # GAP: does the resolved card go anywhere? The tooltip says only
         # "resolve", and the discard here was a guess made when a discard fired
         # nothing. It fires an On Discard now, so the guess costs something.
         # Waiting on a re-read of the printed card, or on Keith.
         chosen=["copy:target:activate", "move_target_to:mine.discard"]),
    card("icedragon", "Ice Dragon", WATER, tier=4, kind="dragon",
         tooltip="Heal 3. Gain a Storm Shard. Give an ICE.",
         flavour="The elusive Storm Dragons were considered to be cryptids until very recently.",
         cast=[HEAL(3), SHARD(1)] + GIVE("ice")),
    card("stormdragon", "Storm Dragon", WATER, tier=4, kind="dragon",
         tooltip="Deal 3 damage and gain a Storm Shard.",
         flavour="The elusive Storm Dragons were considered to be cryptids until very recently.",
         cast=[DMG(3), SHARD(1)]),
    card("earthdragon", "Earth Dragon", EARTH, tier=4, kind="dragon",
         tooltip="You may gain a card from the Storm Cloud. Deal 2 damage. Gain a Storm Shard. Your opponent gains an ASH.",
         flavour="The Earth Dragons are known to hoard massive amounts of treasure in caves.",
         simplified="the printed card gains twice; here it gains once",
         cast=[DMG(2), SHARD(1)] + GIVE("ash") + [OFFER_CLOUD],
         chosen=TAKE_TO_HAND),
]

# ---------------------------------------------------------------------------
# Weather
#
# One card is flipped at the start of each round and every player resolves it.
# Two moments: `wx` at the flip, and `wy` at the reveal -- which is what lets
# "if you reveal Fire this round" be asked at all, since at flip time nobody
# has played anything yet.
# ---------------------------------------------------------------------------

def weather(key, name, tooltip, wx=(), wy=None, calm=False, simplified=None):
    return dict(key=key, name=name, tooltip=tooltip, wx=list(wx), wy=wy,
                calm=calm, simplified=simplified)

REVEALED = lambda el: "count:%s@mine.battle >= 1" % el

WEATHER = [
    # The eight Calm Before the Storm cards, which sit on top of the deck so
    # the first two battles are gentle.
    weather("nice_breeze", "Nice Breeze", "Draw a card, gain 1 mana, power up.",
            wx=[DRAW, MANA, POWER], calm=True),
    weather("crystalflurries", "Crystal Flurries",
            "Draw a card and gain 1 mana. If you reveal Water this round, gain 1 mana.",
            wx=[DRAW, MANA], wy=(REVEALED(WATER), [MANA]), calm=True),
    weather("heatwave", "Heatwave",
            "Draw a card. If you reveal Fire this round, gain 1 mana.",
            wx=[DRAW], wy=(REVEALED(FIRE), [MANA]), calm=True),
    weather("fallingearth", "Falling Earth",
            "Draw a card. If you reveal Earth this round, power up.",
            wx=[DRAW], wy=(REVEALED(EARTH), [POWER]), calm=True),
    weather("dustcloud", "Dust Cloud",
            "Draw a card, power up. All players discard a card.",
            wx=[DRAW, POWER, DISCARD_RANDOM("mine")], calm=True),
    weather("fallingstar", "Falling Star",
            "Draw a card and gain 1 mana.",
            simplified="the printed card lets every player gain a card from the Storm Cloud; an offer cannot be opened once per seat inside one automatic step, so it gives mana instead",
            wx=[DRAW, MANA], calm=True),
    weather("strange_weather", "Strange Weather",
            "Draw 2 cards. Discard the next card in the Weather Deck.",
            wx=[DRAW, DRAW], calm=True),

    # The sixteen standard cards.
    weather("burningblizzard", "Burning Blizzard",
            "Draw a card. If you reveal Fire this round, gain 2 mana.",
            wx=[DRAW], wy=(REVEALED(FIRE), [MANA, MANA])),
    weather("energywave", "Energy Wave",
            "Draw a card. After resolving, players may use their Ultimate ability.",
            simplified="Ultimates are already usable every round in this build, so this only draws",
            wx=[DRAW]),
    weather("gemlightomen", "Gemlight Omen",
            "Draw a card. Tier II players gain 1 mana; Tier I players power up 3 times.",
            wx=[DRAW]),
    weather("glitteringdust", "Glittering Dust",
            "Draw 2 cards. Earth cards do nothing when resolved but heal 2.",
            simplified="the replacement of every Earth card's effect is a continuous effect the engine has no way to express; this only draws",
            wx=[DRAW, DRAW]),
    weather("ionicatmosphere", "Ionic Atmosphere",
            "Draw 2 cards and gain 1 mana. Tier II and III players lose 2 Power Tokens.",
            wx=[DRAW, DRAW, MANA]),
    weather("lightningstrike", "Lightning Strike!",
            "Draw a card and gain 1 mana. Players with more than 8 health take 1 damage.",
            wx=[DRAW, MANA]),
    weather("magneticwarp", "Magnetic Warp",
            "Draw 2 cards. VOID all cards in the Storm Cloud and draw out 5 new ones.",
            wx=[DRAW, DRAW]),
    weather("rainoftoads", "Rain of Toads",
            "Draw a card. Whoever has Initiative loses it; whoever gains it gains a CURSE and 1 mana.",
            wx=[DRAW]),
    weather("shootingstar", "Shooting Star", "Draw 2 cards and power up twice.",
            wx=[DRAW, DRAW, POWER, POWER]),
    weather("soothingrain", "Soothing Rain",
            "Draw a card. You may VOID an ASH, CURSE or ICE in your discard pile.",
            simplified="the void is not offered inside an automatic step; this only draws",
            wx=[DRAW]),
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

# ---------------------------------------------------------------------------
# Wizards
#
# Each is a character card that sits in the player's wizard zone carrying the
# Ultimate, two Wizard Spell Cards shuffled into the starting deck, and a
# chooser card that configures the seat when it is picked.
# ---------------------------------------------------------------------------

def wizard(key, name, epithet, elements, health, rating, ult_cost, ult_name,
           ult_tooltip, ult_action, spells, start=(), ult_chosen=None,
           simplified=None, blurb=""):
    return dict(key=key, name=name, epithet=epithet, elements=elements,
                health=health, rating=rating, ult_cost=ult_cost,
                ult_name=ult_name, ult_tooltip=ult_tooltip,
                ult_action=list(ult_action), ult_chosen=ult_chosen,
                spells=spells, start=list(start), simplified=simplified,
                blurb=blurb)


WIZARDS = [
    wizard("derby", "Derby Pocket", "Infernal Intern", "Fire, Earth", 13, 3, 6,
           "Flaming Yardstick",
           "Deal 2 damage and gain 1 mana.",
           [DMG(2), MANA],
           simplified="the printed Ultimate gives 2 mana only at an odd number of health; there is no parity test, so it always gives 1",
           blurb="An ex-Business Demon intern who loves to encourage others. Strong early, and gains power passively. A good all-rounder.",
           start=["draw_from:spellstorm_deck:mine.discard:0"],
           spells=[
               card("derby_coffee", "Coffee Run", EARTH, kind="wizard_spell",
                    tooltip="Power up twice and you may gain a card from the Storm Cloud. If you gained an Earth card, gain Initiative.",
                    flavour='"This is gonna be the best coffee run of all time!"',
                    simplified="Initiative is granted for any gained card, not only an Earth one",
                    cast=[POWER, POWER, OFFER_CLOUD],
                    chosen=TAKE_TO_HAND + GAIN_INIT),
               card("derby_reckless", "Reckless Charge", FIRE, kind="wizard_spell",
                    tooltip="Gain 1 mana and power up. Deal 1 damage. Gain an ASH. If you have Initiative, deal 1 more damage.",
                    flavour='"I know we can do it if we work together!"',
                    cast=[MANA, POWER, DMG(1)] + GAIN_JUNK("ash"),
                    cast2=(HAS_INIT, [DMG(1)])),
           ]),

    wizard("eve", "Eve Williams", "Radical Activist", "Fire, Water", 14, 5, 5,
           "Doom Bauble",
           "Draw 2 cards. You may move a card from your discard to your opponent's discard.",
           [DRAW, DRAW, "show:mine.discard:optional"],
           ult_chosen=["move_target_to:enemy.discard"],
           simplified="the offer is not narrowed to ICE and CURSE",
           blurb="A radical activist who loves to blow things up. Aggressive, and can really mess up her opponent's deck.",
           start=GIVE("ice") + GAIN_JUNK("ice"),
           spells=[
               card("eve_facepunch", "Face Punch", WATER, kind="wizard_spell",
                    tooltip="Gain Initiative. Steal 1 mana from your opponent and they discard a card.",
                    flavour='"We use voices to avoid having to use fists. We use fists to avoid having to use bombs."',
                    cast=GAIN_INIT + ["stat_damage:mana@enemy.player:1", MANA,
                                      DISCARD_RANDOM("enemy")]),
               card("eve_riot", "Riot", FIRE, kind="wizard_spell",
                    tooltip="Discard your hand without triggering any discard effects. Deal 1 damage per Earth card discarded. Draw 2 cards.",
                    flavour='"Destroying the Omni-Gem was only the first step in our struggle against colonial oppression."',
                    comment="The two moves are one discard, and the detour is the whole of \"without triggering any discard effects\". An On Discard fires on a card going from a hand to a discard; leaving a hand for the quiet is not that, and leaving the quiet for a discard is not either. The cards are there for the length of one step and this is the only card in the box that needs it.",
                    cast=["stat_damage:health@enemy.player:count:earth@mine.hand",
                          "move:mine.hand:quiet", "move:quiet:mine.discard", DRAW, DRAW]),
           ]),

    wizard("abra", "Abragail", "Professor of Magical Chemistry", "Water, Earth", 16, 7, 4,
           "Level Up!",
           "Add a Research Token to your journal. At the start of each battle, every researched power activates.",
           ["stat_gain:research@mine.player:1"],
           blurb="A professor at Azura Academy who levels up her magic as the game goes on. Great for players who like to plan.",
           spells=[
               card("abra_deepgems", "Deep Gems", WATER, kind="wizard_spell",
                    tooltip="Draw a card and gain 1 mana. You may lose 1 Power Token to resolve and then VOID a card from the Storm Cloud.",
                    flavour="The Water Kingdom's dominance was possible, in part, due to their ability to dredge resources from the deep.",
                    simplified="the offer is not narrowed to Water cards and the Power Token is not spent",
                    cast=[DRAW, MANA, OFFER_CLOUD],
                    chosen=["move_target_to:void", "copy:target:activate", REFILL_CLOUD]),
               card("abra_newcurriciulum", "New Curriculum", EARTH, kind="wizard_spell",
                    tooltip="Power up once per Tier you have reached. You may VOID a card in the Storm Cloud, and you may gain one.",
                    flavour='"Can\'t believe the *garbage* I\'m asked to teach sometimes!"',
                    simplified="the printed card voids up to 2; here one card is offered, and taking it gains rather than voids",
                    cast=["stat_gain:power@mine.player:sum:tier@mine.player", OFFER_CLOUD],
                    chosen=TAKE_TO_HAND),
           ]),

    wizard("croh", "Croh Vosh", "Undead Lich", "Fire, Water", 20, 8, 6,
           "DOOOOOOOOOM!",
           "Redraw one card from your discard for each DOOM Token you have, then gain a DOOM Token.",
           ["draw_from:mine.discard:mine.hand:sum:doom@mine.player",
            "activate_zone:rules:by_column:croh_doom"],
           simplified="the printed Ultimate lets you take any card from your discard, or draw instead; here the redraw is off the top of the discard",
           blurb="An undead Lich back from a thousand-year slumber. Enormous health, but he cannot heal -- healing becomes a CURSE for his opponent instead.",
           spells=[
               card("croh_sinking", "Sinking Strike", FIRE, kind="wizard_spell",
                    tooltip="Gain 2 mana. Deal damage equal to your number of DOOM Tokens. If the CURSE pile is empty, gain a DOOM Token.",
                    flavour="Long ago, Croh Vosh was betrayed and killed at Dragon Bridge by his longtime ally, Salutaire Ruupart.",
                    cast=[MANA, MANA,
                          "stat_damage:health@enemy.player:sum:doom@mine.player"],
                    cast2=("count:junk@curse_pile <= 0",
                           ["stat_gain:doom@mine.player:1"])),
               card("croh_undertow", "Undertow", WATER, kind="wizard_spell",
                    tooltip="Your opponent discards a card. Draw a card. If you hold at least 3 more cards than they do, gain a DOOM Token.",
                    flavour="Croh has come to the Spellstorm seeking his path to world domination.",
                    cast=[DISCARD_RANDOM("enemy"), DRAW],
                    cast2=("count:spell@mine.hand >= count:spell@enemy.hand",
                           ["stat_gain:doom@mine.player:1"])),
           ]),

    wizard("omar", "Omar Evans", "Ninja and Eco-Terrorist", "Fire, Water", 10, 1, 4,
           "Hidden Movement",
           "Return a card from your discard to your hand, and draw a card.",
           [DRAW, "show:mine.discard:optional"],
           ult_chosen=["move_target_to:mine.hand"],
           simplified="Omar's three Trap cards are not implemented -- a face-down card revealed at a trigger of the player's choosing has no expression in the engine",
           blurb="A ninja and wanted eco-terrorist. Low health, but he acts first in every matchup and Shuriken always resolves before anything else.",
           spells=[
               card("omar_beetle", "Beetle Buster", FIRE, kind="wizard_spell",
                    tooltip="Discard a card from your hand to deal 2 damage.",
                    flavour="A hero to many, Omar is regarded by the powerful as an eco-terrorist.",
                    simplified="the offer is not narrowed to Fire cards",
                    cast=[OFFER_HAND],
                    chosen=["move_target_to:mine.discard", DMG(2)]),
               card("omar_shuriken", "Shuriken", WATER, kind="wizard_spell",
                    tooltip="Gain Initiative and draw a card.",
                    flavour='"..."',
                    simplified='the printed card ALWAYS resolves first and can discard the opponent\'s revealed card; resolution order is set by Initiative alone, so it takes Initiative instead',
                    cast=GAIN_INIT + [DRAW]),
           ]),

    wizard("bunny", "Bunny Wizard", "Healer of Bunny Island", "Water, Earth", 8, 2, 5,
           "Cast a Magic Trick!",
           "Reveal a card from your hand, resolve it twice and VOID it. All players heal 1.",
           ["show:mine.hand:optional"],
           ult_chosen=["copy:target:activate:2", "move_target_to:void",
                       HEAL(1), "stat_gain:health@enemy.player:1"],
           simplified="Bunny's Double Stitch heals past his starting health to 10, so his ceiling is 10 from the start and the overheal draw of Triple Stitch never fires",
           blurb="A stuffie from Bunny Island who heals fast and often helps his opponent along the way. A good choice if you like to play nice.",
           spells=[
               card("bunny_buddy", "Buddy System", EARTH, kind="wizard_spell",
                    tooltip="Power up and gain 1 mana. If your opponent is Tier I, they power up too.",
                    flavour='"Bunny is wondering if it would be okay to hold your hand." - Bunny\'s Handler',
                    simplified="resolving a different revealed Earth card is not offered",
                    cast=[POWER, MANA],
                    cast2=("tier@enemy.player <= 1",
                           ["stat_gain:power@enemy.player:1"])),
               card("bunny_snowday", "Snow Day", WATER, kind="wizard_spell",
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
                  "stat_set:water_el@mine.player:3"],
           blurb="A chemistry student who loves danger and whose experiments keep exploding. A good character for players who like to gamble.",
           spells=[
               card("oren_potion", "Potion Gun", FIRE, kind="wizard_spell",
                    tooltip="Deal 1 damage. You may give a card from your hand to your opponent's hand.",
                    flavour='"Think I can hit that old barrel by the hill over there?"',
                    simplified="which Element the given card matches is not read, so no Element is gained",
                    cast=[DMG(1), OFFER_HAND],
                    chosen=["move_target_to:enemy.hand"]),
               card("oren_unstable", "Unstable Formula", EARTH, kind="wizard_spell",
                    tooltip="Power up and gain 1 mana. If anyone revealed Water, power up again.",
                    flavour='"Oh, it\'ll work, trust me. But, uh... you might wanna stand back a bit..."',
                    simplified="choosing which Element to lower and which to raise is not offered",
                    cast=[POWER, MANA],
                    cast2=("count:water@battle >= 1", [POWER])),
           ]),

    wizard("may", "May Danaris", "Hacker", "Fire, Earth", 12, 4, 6,
           "Void Traveler",
           "Gain 3 Energy Tokens. You may resolve a card from the VOID, then put it on the bottom of the Spellstorm Deck.",
           ["stat_gain:energy@mine.player:3", "show:void:optional"],
           ult_chosen=["copy:target:activate",
                       "move_target_to:spellstorm_deck:bottom"],
           simplified="Dangerous Download -- resolving an opponent's revealed Tier II card at the end of a round -- is not implemented",
           blurb="A hacker who used to work for Central Intelligence. She can play cards from the VOID, and is good for players who like to feel like they're cheating.",
           start=["stat_gain:energy@mine.player:2"],
           spells=[
               card("may_data", "Data Breach", EARTH, kind="wizard_spell",
                    tooltip="Lose 2 Energy Tokens to power up twice and make your opponent discard a card.",
                    flavour='"Yes! I\'m in. Now let\'s see what these idiots have planned next..."',
                    simplified="the choice of losing 1 or 2 Energy is not offered",
                    cast2=("energy@mine.player >= 2",
                           ["stat_damage:energy@mine.player:2", POWER, POWER,
                            DISCARD_RANDOM("enemy")])),
               card("may_starshot", "Star Shot", FIRE, kind="wizard_spell",
                    tooltip="Discard a card to deal 1 damage. Gain 1 mana for each Energy Token you have, then lose 2 Energy.",
                    flavour='"Hey, YOU! Eat this!"',
                    simplified="the extra damage for discarding a Tier II card is not checked",
                    cast=["stat_gain:mana@mine.player:sum:energy@mine.player",
                          "stat_damage:energy@mine.player:2", OFFER_HAND],
                    chosen=["move_target_to:mine.discard", DMG(1)]),
           ]),
]

# Abragail's Research Journal: eight spaces, each firing at battle start once a
# Research Token sits on it. Three of them ask a question, and an offer is one
# at a time, so those three get a step of their own and a phase each to open in
# -- an ask is the last thing an action list can do, and three asks in one list
# is three overlays on one table.
JOURNAL = [
    (1, [MANA], None),
    (2, [OFFER_HAND], {"action": ["move_target_to:void"]}),
    (3, [MANA], None),
    (4, ["show:mine.discard:optional"],
        {"where": ["tagged:junk@target"],
         "action": ["move_target_to:enemy.discard"]}),
    (5, [POWER], None),
    (6, [OFFER_CLOUD], {"action": TAKE_TO_HAND}),
    (7, [POWER], None),
    (8, [DRAW], None),
]

# The spaces that ask, in order, which is both the steps and the phases.
JOURNAL_ASKS = [n for n, _, ch in JOURNAL if ch]

# Oren's potion deck. Each potion costs a number of one Element off the Chemistry
# Board and does nothing if the beaker is too low, which is a condition and so an
# ability rather than a play. Six of the nine carry the TOXIC icon on the printed
# card; the transcription's table marks five, and the table is what is followed
# here (ideas/spellstorm/07-wizards.md).
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
    ("pot_gasoline", "I Think I Just Drank Gasoline", "Take 1 damage. Your next potion happens twice, and you pay its cost once.",
     EARTH, 2, True, (None, [SELF_DMG(1)]), None),
    ("pot_dragon", "Dragon Elixir", "Resolve the top card of the Dragon Deck.",
     EARTH, 4, False, (None, ["activate_zone:rules:by_column:dry_dragon",
                              "draw_from:dragon_deck:mine.hand:1"]), None),
    ("pot_frost", "Frost Bomb", "Your opponent loses 1 mana. Give an ICE.",
     WATER, 2, False, (None, ["stat_damage:mana@enemy.player:1"] + GIVE("ice")), None),
    ("pot_storm", "Storm Juice", "Draw a card and power up.",
     WATER, 3, False, (None, [DRAW, POWER]), None),
    ("pot_soda", "Health Soda", "Heal 2.",
     WATER, 4, True, (None, [HEAL(2)]), None),
]

# What ends the Ultimate, whichever way it ends: the beakers go back to 3 and the
# phase the Ultimate pushed comes off. The pushed phase is on top by now -- a
# revealed page pops before the card it showed acts -- so this pops the loop.
POTION_END = ["stat_set:fire_el@mine.player:3",
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
    if when: a["when"] = list(when)
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
    t["tags"] = tags
    t["tooltip"] = tip(c["tooltip"], c["flavour"], c["simplified"])
    if c["comment"]: t["comment"] = c["comment"]

    # A card that can be cast says so by carrying a play block; ICE, ASH and
    # CURSE carry none, which is the whole of "this can't be played" and needs
    # no rule anywhere else.
    if c["kind"] != "junk":
        t["play"] = {"action": ["set_owner:self:mine", "move_to:mine.commit"]}

    # `tier_req` is what the Storm Cloud's take tests against your Tier.
    stats = {}
    if c["tier"]: stats["tier_req"] = c["tier"]
    elif c["kind"] == "junk": stats["tier_req"] = 1
    else: stats["tier_req"] = 1
    t["card_stats"] = stats

    asks = [a for a in c["cast"] if a.startswith("show:")]
    does = [a for a in c["cast"] if not a.startswith("show:")]
    assert not asks or c["cast"].index(asks[0]) == len(c["cast"]) - 1, \
        "%s: the offer has to be the last thing its cast does" % c["key"]

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
    if c["chosen"]: t["chosen"] = {"action": list(c["chosen"])}
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
    if abil: t["abilities"] = abil
    return t


def wizard_templates(w):
    """The character card that carries the Ultimate, and the chooser card."""
    out = []
    # Cast while you are choosing a card to play, which is the one moment the
    # engine can offer -- see the gaps note. Named rather than left open because
    # an Ultimate that may be used inside anything can be used inside itself,
    # and Oren's opens a phase of its own to be used inside.
    ult = {"cost": {"mana@mine.player": w["ult_cost"]},
           "phases": ["play_1", "play_2"],
           "action": list(w["ult_action"])}
    char = {
        "key": "wiz_" + w["key"], "text": w["name"], "asset": WIZ_ART[w["key"]],
        "tags": ["wizard_card", w["key"]],
        "tooltip": tip("%s. %s\n\nUltimate (%d mana) - %s: %s\n\nStarting health %d, Initiative rating %d."
                       % (w["epithet"], w["blurb"], w["ult_cost"], w["ult_name"],
                          w["ult_tooltip"], w["health"], w["rating"]),
                       simplified=w["simplified"]),
        "activate": ult,
    }
    if w["ult_chosen"]: char["chosen"] = {"action": list(w["ult_chosen"])}
    out.append(char)

    pick_action = [
        "stat_boost:health@mine.player:%d" % (w["health"] - 1),
        "stat_set:health@mine.player:%d" % w["health"],
        "stat_set:init_rating@mine.player:%d" % w["rating"],
        "fill:mine.wizard:wiz_%s:1" % w["key"],
    ]
    for s in w["spells"]:
        pick_action.append("fill:mine.deck:%s:1" % s["key"])
    pick_action += list(w["start"])
    pick_action.append("stat_gain:picked@mine.player:1")
    out.append({
        "key": "pick_" + w["key"], "text": w["name"], "asset": WIZ_ART[w["key"]],
        "tags": ["chooser", "no_undo"],
        "tooltip": "%s (%s). %s\n\nHealth %d, Initiative rating %d, Ultimate %d mana."
                   % (w["epithet"], w["elements"], w["blurb"], w["health"],
                      w["rating"], w["ult_cost"]),
        "play": {"action": pick_action},
    })
    return out


def rules_card(key, text, tooltip, abilities, chosen=None):
    """A rule with nowhere else to live: a card in an offscreen zone that a
    phase walks. Its `when` is the if the action grammar has no room for."""
    t = {"key": key, "text": text, "tags": ["immutable"], "tooltip": tooltip,
         "asset": "auto", "abilities": abilities}
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
            [ability("check", [DRAW],
                     when=["count:%s@mine.battle >= 1" % a,
                           "count:%s@enemy.battle >= 1" % b])]))

    # Blast Scoring. Your Blast Score is what you still hold once the discard
    # effects have gone; a single highest takes two Shards, a tie takes one each.
    out.append(rules_card(
        "r_blast", "Blast Score",
        "Blast Score is the cards left in your hand after discard effects, less one per ICE discarded. The single highest score gains 2 Storm Shards; a tie gains 1 each.",
        [ability("score", ["stat_set:blast@mine.player:count:spell@mine.hand",
                           "stat_damage:blast@mine.player:sum:ice_pen@mine.player"]),
         ability("award_win", [SHARD(2)],
                 when=["blast@mine.player > blast@enemy.player"]),
         ability("award_tie", [SHARD(1)],
                 when=["blast@mine.player == blast@enemy.player"])]))

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
                      ["stat_damage:power@enemy.player:2"]),
            ("curse", [SELF_DMG(1)], [DMG(1)]),
            ("ice",   [DISCARD_RANDOM("mine")] * 2, [DISCARD_RANDOM("enemy")] * 2)):
        out.append(rules_card(
            "r_dry_" + kind, "The %s pile is empty" % kind.upper(),
            tip("When the %s pile is empty, whoever would have been given one VOIDs "
                "a %s from their hand or discard and takes the penalty instead."
                % (kind.upper(), kind.upper()),
                simplified="only the penalty happens; the VOID needs a card of one kind "
                           "in one seat's hand, and a scope names a zone or a kind, never both"),
            [ability("dry_take_" + kind, take, when=["count:junk@%s_pile <= 0" % kind]),
             ability("dry_give_" + kind, give, when=["count:junk@%s_pile <= 0" % kind])]))

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
                 when=["init_rating@mine.player < init_rating@enemy.player"])]))

    # Abragail's journal: every researched space fires at battle start. The
    # three that ask a question run under their own step so a phase can open
    # them one at a time.
    for n, acts, chosen in JOURNAL:
        out.append(rules_card(
            "r_journal_%d" % n, "Abragail's Journal, space %d" % n,
            tip("At the start of each battle, Abragail activates every power she has researched.",
                simplified="a Research Token goes on the next space rather than one you choose, so the journal fills in order"),
            [ability("jr%d" % n if chosen else "bstart", acts,
                     when=["count:abra@mine.wizard >= 1",
                           "research@mine.player >= %d" % n])],
            chosen=chosen))

    # A third TOXIC ends the Ultimate whatever the player wanted, and costs one
    # of each junk card on the way out.
    out.append(rules_card(
        "r_potion", "A third TOXIC",
        "Drawing a third TOXIC potion ends Oren's Ultimate after that potion resolves, and gives him an ASH, a CURSE and an ICE.",
        [ability("potion_toxic",
                 GAIN_JUNK("ash") + GAIN_JUNK("curse") + GAIN_JUNK("ice") + POTION_END,
                 when=["toxic@mine.player >= 3"])]))

    # Croh gains DOOM Tokens only from failure states -- having none, or an
    # empty CURSE pile -- which is the trap his whole design is built around.
    # An if lives in an ability, so the Ultimate calls one rather than saying it.
    out.append(rules_card(
        "r_doom", "Looming",
        "Croh Vosh gains a DOOM Token from his Ultimate only when he has none left.",
        [ability("croh_doom", ["stat_gain:doom@mine.player:1"],
                 when=["doom@mine.player <= 0"])]))

    # Croh cannot heal: his healing becomes a CURSE for the other seat. This is
    # the closest the engine gets to a passive -- it is a battle-start sweep
    # rather than a rule that intercepts every heal.
    out.append(rules_card(
        "r_accursed", "Accursed",
        "Croh Vosh can never heal. Approximated: at the start of each battle he gives a CURSE instead of whatever healing he did.",
        [ability("bstart", GIVE("curse"),
                 when=["count:croh@mine.wizard >= 1"])]))
    return out


def potion_templates():
    out = []
    for key, name, tooltip, el, cost, toxic, main, other in POTIONS:
        line = "%s %d%s. %s" % (el.title(), cost, " - TOXIC" if toxic else "", tooltip)
        note = None
        if key == "pot_dragon": note = "the Dragon is gained rather than resolved"
        if key == "pot_gasoline": note = "the next potion is not doubled"
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
        play += ["activate_zone:rules:by_column:potion_toxic", "move_to:potion_discard"]
        t["play"] = {"action": play}

        pay = ["stat_damage:%s_el@mine.player:%d" % (el, cost)]
        afford = "%s_el@mine.player >= %d" % (el, cost)
        abil = [ability("sip", pay + list(main[1]),
                        when=[afford] + ([main[0]] if main[0] else []))]
        if other:
            abil.append(ability("sip2", pay + list(other[1]), when=[afford, other[0]]))
        t["abilities"] = abil
        out.append(t)
    return out


def zones():
    P = lambda *r: list(r)
    return [
        # Per-seat. Bottom seat first, top seat second, everywhere.
        # Offscreen, and a grid so it counts as in play: "who holds the
        # Initiative Tracker" is asked of the seat cards as a computed tag, and a
        # tag scope only reaches a board.
        {"key": "seats", "layout": "grid", "grid": [2, 1],
         "display": "offscreen", "use": "abilities"},
        {"key": "wizard", "label": "Wizard", "layout": "grid", "grid": [1, 1],
         "copies": "per_seat", "use": "abilities",
         "pos": [P(0.005, 0.795, 0.135, 0.995), P(0.865, 0.005, 0.995, 0.205)]},
        # Named so the box stays on screen when the hand is empty -- which it is
        # across `regroup` and both gain steps, and whenever somebody plays their
        # last card. An unlabelled empty zone draws nothing at all (render.lua).
        {"key": "hand", "label": "Hand", "layout": "row", "visibility": "owner",
         "copies": "per_seat",
         "pos": [P(0.14, 0.795, 0.79, 0.995), P(0.21, 0.005, 0.86, 0.205)]},
        {"key": "deck", "label": "Deck", "layout": "stack", "visibility": "secret",
         "copies": "per_seat", "tags": ["shuffle"], "refill_from": "discard",
         "tooltip": "Your draw deck. When you need a card and it is empty, your discard is shuffled into it.",
         "pos": [P(0.795, 0.795, 0.885, 0.995), P(0.115, 0.005, 0.205, 0.205)]},
        {"key": "discard", "label": "Discard", "layout": "stack",
         "copies": "per_seat",
         "pos": [P(0.89, 0.795, 0.995, 0.995), P(0.005, 0.005, 0.11, 0.205)]},
        # Where a card waits face down, and where it stands once both are turned
        # over. Two zones rather than one because "who may read this" is a
        # property of the place and not of the moment: `visibility` is declared,
        # so the only way to stop being face down is to be somewhere else.
        #
        # They would share a rect if they could -- the two are never both
        # occupied, so the reveal would be the card turning over where it lay --
        # but the validator refuses overlapping zones and is right to in general:
        # nothing in the format says "these two are never open at once". So the
        # face-down card gets the free strip down the right edge instead, and
        # the reveal is a slide to the middle.
        {"key": "commit", "label": "Face down", "layout": "grid", "grid": [1, 1],
         "copies": "per_seat", "visibility": "owner",
         "tooltip": "Your card for this round, face down. Only you may read it. It turns over when both players have played.",
         "pos": [P(0.915, 0.520, 0.995, 0.775), P(0.915, 0.215, 0.995, 0.470)]},
        {"key": "battle", "label": "Battle", "layout": "grid", "grid": [1, 1],
         "copies": "per_seat",
         "pos": [P(0.435, 0.575, 0.565, 0.785), P(0.435, 0.215, 0.565, 0.425)]},

        # Shared.
        {"key": "storm_cloud", "use": "abilities", "label": "Storm Cloud", "layout": "grid",
         "grid": [1, 5], "applies": ["takeable"],
         "tooltip": "Five cards to gain from. You may only take one at or below your Tier. After any card leaves, another is drawn to replace it.",
         "pos": P(0.005, 0.215, 0.105, 0.785),
         "contents": ["fireessence", "wateressence", "earthessence"]},
        {"key": "spellstorm_deck", "label": "Deck", "layout": "stack",
         "visibility": "secret", "tags": ["shuffle"], "refill_from": "void",
         "tooltip": "The Spellstorm Deck. When it runs out, the VOID is shuffled to become the new one.",
         "pos": P(0.115, 0.215, 0.20, 0.40),
         "contents": [c["key"] for c in SPELLS]},
        {"key": "void", "label": "VOID", "layout": "stack", "use": "none",
         "tooltip": "Cards removed from the game. When the Spellstorm Deck runs out, this becomes the new one.",
         "pos": P(0.115, 0.42, 0.20, 0.605)},

        {"key": "weather_now", "label": "Weather", "layout": "stack",
         "tooltip": "This round's weather. Only the current card is active.",
         "pos": P(0.245, 0.40, 0.415, 0.60)},
        {"key": "weather_calm", "label": "Calm", "layout": "stack",
         "visibility": "secret", "tags": ["shuffle"], "refill_from": "weather_main",
         "tooltip": "The eight Calm Before the Storm cards sit on top of the Weather Deck, so the first battles are gentle. When they run out the sixteen standard cards are shuffled in.",
         "pos": P(0.115, 0.625, 0.20, 0.785),
         "contents": [w["key"] for w in WEATHER if w["calm"]]},
        {"key": "weather_main", "label": "Storm", "layout": "stack",
         "visibility": "secret", "tags": ["shuffle"],
         "pos": P(0.245, 0.625, 0.33, 0.785),
         "contents": [w["key"] for w in WEATHER if not w["calm"]]},
        {"key": "weather_discard", "layout": "stack", "use": "none",
         "pos": P(0.34, 0.625, 0.425, 0.785)},

        {"key": "ice_pile", "use": "abilities", "label": "Ice", "layout": "stack",
         "applies": ["takeable"], "contents": ["ice:6"],
         "tooltip": "Six ICE. Given to an opponent's discard, and returned here when VOIDed.",
         "pos": P(0.615, 0.215, 0.705, 0.40)},
        {"key": "ash_pile", "use": "abilities", "label": "Ash", "layout": "stack",
         "applies": ["takeable"], "contents": ["ash:6"],
         "tooltip": "Six ASH. Given to an opponent's discard, and returned here when VOIDed.",
         "pos": P(0.715, 0.215, 0.805, 0.40)},
        {"key": "curse_pile", "use": "abilities", "label": "Curse", "layout": "stack",
         "applies": ["takeable"], "contents": ["curse:6"],
         "tooltip": "Six CURSE. Given to an opponent's discard, and returned here when VOIDed.",
         "pos": P(0.815, 0.215, 0.905, 0.40)},
        {"key": "dragon_deck", "label": "Dragons", "layout": "stack",
         "tags": ["shuffle"], "use": "none",
         "tooltip": "Tier IV. Gained by filling your Power Track while already at Tier III.",
         "contents": [c["key"] for c in DRAGONS],
         "pos": P(0.615, 0.44, 0.705, 0.625)},

        {"key": "controls", "layout": "grid", "grid": [1, 4],
         "use": "abilities", "tags": ["optional"],
         "pos": P(0.735, 0.44, 0.825, 0.785)},

        # The offer, claimed so a roster of eight wizards has the middle of the
        # screen for one click and no strip of board for the rest of the game.
        {"key": "options", "layout": "row", "status": "offer",
         "display": "offscreen", "pos": P(0.06, 0.28, 0.94, 0.72)},

        # Rules that have to run at a named moment live on cards, and cards have
        # to live somewhere.
        {"key": "rules", "layout": "stack", "display": "offscreen", "use": "none"},
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


# Abragail's three question spaces, one phase each and one seat each. An action
# list has no cursor -- whatever follows an ask runs before the answer arrives --
# so the ask is the last thing each of these does and the next one waits for the
# phase to come back. One seat each because two Abragails would otherwise hold up
# both hands at once and the second question would land in the first one's offer.
#
# Only the first phase of each side names a seat: "the enemy of whoever is up"
# said three times running walks back and forth.
JOURNAL_PHASES = []
for side, setter in (("a", "set_active_seat:has_init"),
                     ("b", "set_active_seat:enemy.player")):
    for n in JOURNAL_ASKS:
        first = n == JOURNAL_ASKS[0]
        JOURNAL_PHASES.append(
            {"key": "journal_%d%s" % (n, side), "type": "automatic",
             "actions": ([setter] if first else [])
                        + ["activate_zone:rules:by_column:jr%d" % n]})
for i, ph in enumerate(JOURNAL_PHASES):
    ph["next"] = [{"then": JOURNAL_PHASES[i + 1]["key"]
                           if i + 1 < len(JOURNAL_PHASES) else "weather"}]


def phases():
    return [
        {"key": "boot", "type": "automatic",
         "actions": ["draw_from:spellstorm_deck:storm_cloud:2"],
         "next": [{"then": "pick_1"}]},

        # One question per seat, asked out of the offer rather than a zone kept
        # empty for the rest of the game.
        {"key": "pick_1", "type": "player_input", "seat": "next",
         "label": "Choose your wizard",
         "actions": ["options:" + ",".join("pick_" + w["key"] for w in WIZARDS)],
         "ends_when": "picked@mine.player >= 1", "next": [{"then": "pick_2"}]},
        {"key": "pick_2", "type": "player_input", "seat": "next",
         "label": "Choose your wizard",
         "actions": ["options:" + ",".join("pick_" + w["key"] for w in WIZARDS)],
         "ends_when": "picked@mine.player >= 1", "next": [{"then": "begin"}]},

        {"key": "begin", "type": "automatic",
         "actions": ["each_seat:fill:mine.deck:magicdart:2",
                     "each_seat:fill:mine.deck:block:2",
                     "each_seat:fill:mine.deck:powergem:2",
                     "each_seat:shuffle:mine.deck",
                     "each_seat:activate_zone:rules:by_column:first"],
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
         "next": [{"then": JOURNAL_PHASES[0]["key"]}]},

        ] + JOURNAL_PHASES + [

        {"key": "weather", "type": "automatic",
         "actions": ["move:weather_now:weather_discard",
                     "draw_from:weather_calm:weather_now:1",
                     "stat_gain:battle_round@plan:1",
                     "each_seat:activate_zone:weather_now:by_column:wx"],
         "next": [{"then": "play_1"}]},

        # Both players play face down, then reveal together. The card goes to
        # `commit`, which only its own seat may read, so the second player
        # chooses without seeing the first card -- really, over the network;
        # only on the screen, in hot-seat, where the other player watched the
        # click. See the gaps note.
        {"key": "play_1", "type": "player_input", "seat": "next",
         "label": "Play a card face down", "zone": ["hand", "wizard", "controls"],
         "ends_when": "count:spell@mine.commit >= 1",
         "next": [{"then": "play_2"}]},
        {"key": "play_2", "type": "player_input", "seat": "next",
         "label": "Play a card face down", "zone": ["hand", "wizard", "controls"],
         "ends_when": "count:spell@mine.commit >= 1",
         "next": [{"then": "showdown"}]},

        # This move is the reveal, and it has to come before anything that reads
        # the two cards against each other: countering asks about `enemy.battle`.
        {"key": "showdown", "type": "automatic",
         "actions": ["each_seat:move:mine.commit:mine.battle",
                     "each_seat:activate_zone:rules:by_column:check",
                     "each_seat:activate_zone:weather_now:by_column:wy"],
         "next": [{"then": "resolve_1"}]},

        # Resolution follows the Initiative Tracker, and each card must resolve
        # while its own seat is up or "mine" would name the wrong player.
        {"key": "resolve_1", "type": "automatic",
         "actions": ["set_active_seat:has_init"] + RESOLVE,
         "next": [{"then": "resolve_2"}]},
        {"key": "resolve_2", "type": "automatic",
         "actions": ["set_active_seat:enemy.player"] + RESOLVE,
         "next": [{"then": "round_end"}]},

        {"key": "round_end", "type": "automatic",
         "actions": ["each_seat:move:mine.battle:mine.discard",
                     "each_seat:activate_zone:rules:by_column:tier_up",
                     "each_seat:activate_zone:rules:by_column:tier_up",
                     "each_seat:activate_zone:rules:by_column:tier_gem"],
         "next": [{"when": "battle_round@plan >= 4", "then": "regroup"},
                  {"then": "weather", "ends_round": True}]},

        # Regroup: the four weather cards go, discard effects fire, what is left
        # in hand is a Blast Score, and each player gains one card.
        {"key": "regroup", "type": "automatic",
         "actions": ["move:weather_now:weather_discard",
                     "each_seat:move:mine.hand.has_discard:mine.discard",
                     "each_seat:move:mine.hand.junk:mine.discard",
                     "each_seat:activate_zone:rules:by_column:score",
                     "each_seat:activate_zone:rules:by_column:award_win",
                     "each_seat:activate_zone:rules:by_column:award_tie",
                     "each_seat:move:mine.hand:mine.discard"],
         "next": [{"then": "gain_1"}]},

        {"key": "gain_1", "type": "player_input",
         "label": "Gain a card from the Storm Cloud",
         "actions": ["set_active_seat:has_init",
                     "each_seat:stat_set:took@mine.player:0"],
         "zone": ["wizard", "controls"],
         "ends_when": "took@mine.player >= 1", "next": [{"then": "gain_2"}]},
        # Oren's Ultimate pushes this over whatever he was doing and the two
        # potion buttons are the only things reachable while it is up. It ends
        # when one of them says so, or when a third TOXIC says so -- so it has no
        # "ends_when" of its own: what ends it is an action, every time.
        {"key": "potion", "type": "player_input", "label": "Bottoms up, I guess!",
         "zone": ["controls"]},

        {"key": "gain_2", "type": "player_input", "seat": "next",
         "label": "Gain a card from the Storm Cloud",
         "zone": ["wizard", "controls"],
         "ends_when": "took@mine.player >= 1",
         "next": [{"then": "battle_start", "ends_round": True}]},
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
        cards.append({"key": key, "text": label, "asset": "auto",
                      "tags": ["seat"],
                      "tooltip": "Your wizard, your health, your Storm Shards.",
                      "card_stats": {"health": {"value": 1, "min": 0, "max": 1}}})

    # The scratch card the battle's round number lives on.
    cards.append({"key": "plan", "text": "The Battle", "tags": ["immutable", "plan"],
                  "asset": "auto",
                  "tooltip": "A battle is four rounds, then a Regroup."})

    # Two board buttons. Neither charges exhaust, so both stay clickable.
    cards.append({
        "key": "btn_unplayable", "text": "Unplayable hand",
        "asset": "auto", "tags": ["immutable"],
        "tooltip": "If your hand is nothing but ICE, ASH and CURSE, use this: discard them all with their effects, take 1 damage, and draw a new hand of 4.",
        "activate": {"phases": ["play_1", "play_2"],
                     "action": ["move:mine.hand:mine.discard",
                                SELF_DMG(1),
                                "draw_from:mine.deck:mine.hand:4"]}})
    cards.append({
        "key": "btn_potion_draw", "text": "Draw a potion",
        "asset": "auto", "tags": ["immutable"],
        "tooltip": "Draw the next potion. Its effect happens only if the Element it costs is high enough on your Chemistry Board.",
        "activate": {"phases": ["potion"], "action": ["reveal_top:potion_deck"]}})
    cards.append({
        "key": "btn_potion_stop", "text": "Stop drinking",
        "asset": "auto", "tags": ["immutable"],
        "tooltip": "End your Ultimate while you are ahead. Your Elements go back to 3.",
        "activate": {"phases": ["potion"], "action": list(POTION_END)}})
    cards.append({
        "key": "btn_rules", "text": "The rules",
        "asset": "auto", "tags": ["immutable"],
        "tooltip": ("SPELLSTORM. Win by reaching 8 Storm Shards, or by taking your "
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
                    "Tier III a filled track gains you a Dragon instead."),
        "activate": {"action": ["effect:spark"]}})

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
            {"key": "battle_round", "min": 0, "max": 9, "tags": ["hidden"],
             "on": ["plan"], "start": 0},
            # Read off the card on the shelf rather than the player: what it
            # costs in Tier to take it.
            {"key": "tier_req", "min": 0, "max": 9, "tags": ["hidden"]},
        ],
        "computed_tags": {
            "has_init": {"stat": "initiative", "at_least": 1},
        },
        "styles": {
            "ember": {"color": [0.62, 0.20, 0.16], "title": False},
            "tide":  {"color": [0.16, 0.36, 0.58], "title": False},
            "loam":  {"color": [0.45, 0.34, 0.14], "title": False},
            "storm": {"color": [0.18, 0.36, 0.32], "title": False},
            "wizard_card": {"color": [0.24, 0.16, 0.34], "title": False},
            "chooser": {"color": [0.24, 0.16, 0.34], "title": False},
            "potion": {"color": [0.32, 0.42, 0.18], "title": False},
        },
        "tags": {
            # What a card on a shelf does: it comes to your hand, if your Tier
            # reaches it, and the shelf refills behind it. An ability rather than
            # a play, because an ability's "when" is read where a granted play's
            # "needs" is not -- and because a card on a shelf must not be
            # castable, which "merge": "this" is what says.
            "takeable": {
                "tooltip": "Gain this card. You may only take a card at or below your Tier.",
                "abilities": [{
                    "key": "take", "text": "Gain this card", "merge": "this",
                    "phases": ["gain_1", "gain_2"],
                    "when": ["tier@mine.player >= tier_req@self"],
                    "action": ["set_owner:self:mine", "move_to:mine.hand",
                               REFILL_CLOUD, "stat_gain:took@mine.player:1"]}]},
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
            {"card": "seat_one", "owner": "seat_one", "zone": "seats", "at": "a1"},
            {"card": "seat_two", "owner": "seat_two", "zone": "seats", "at": "b1"},
            {"card": "plan", "zone": "table"},
            {"card": "btn_unplayable", "zone": "controls"},
            {"card": "btn_potion_draw", "zone": "controls"},
            {"card": "btn_potion_stop", "zone": "controls"},
            {"card": "btn_rules", "zone": "controls"},
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
    out = guard.destination("game/games/spellstorm.json", sys.argv[1:])
    g = build()
    with open(out, "w") as f:
        f.write(jsonfmt.dump(g))
    print("%s: %d cards, %d zones, %d phases"
          % (out, len(g["cards"]), len(g["zones"]), len(g["phases"])))
