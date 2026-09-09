# Codex card art

Every card in Codex, with the URL of its face. Scraped from codexcarddb.com, which
also carries each card's rules text as *text* — see the memory note; the JPEGs in
`card_pictures/` are the same images and reading them costs forty-six image reads a
colour where one scrape does the lot.

The images are served straight from `codexcards-assets.surge.sh`. The site fetches
them through a Cloudinary resizer (`res.cloudinary.com/rgdelato/image/fetch/f_auto/`
prefixed to the URL below), which is worth knowing if a size other than the original
is ever wanted.

The number in each filename is the card's own, not its place in any list — it is the
only stable id these have, so it is left in.

`key` is the slug the database uses. Where `codex.json` shortens one — `jaina` for
`jaina_stormborne`, `guargum` for `guargum_eternal_sentinel` — the game file's key is
given in brackets.


## Red — 49 cards

- **Calypso Vystari** — Anarchy tech 1 · `calypso_vystari` · http://codexcards-assets.surge.sh/images/0023_calypso_vystari.jpg
- **Gunpoint Taxman** — Anarchy tech 1 · `gunpoint_taxman` · http://codexcards-assets.surge.sh/images/0024_gunpoint_taxman.jpg
- **Chameleon Lizzo** — Anarchy tech 2 · `chameleon_lizzo` · http://codexcards-assets.surge.sh/images/0030_chameleon_lizzo.jpg
- **Disguised Monkey** — Anarchy tech 2 · `disguised_monkey` · http://codexcards-assets.surge.sh/images/0029_disguised_monkey.jpg
- **Marauder** — Anarchy tech 2 · `marauder` · http://codexcards-assets.surge.sh/images/0031_marauder.jpg
- **Sanatorium** — Anarchy tech 2 · `sanatorium` · http://codexcards-assets.surge.sh/images/0033_sanatorium.jpg
- **Steam Tank** — Anarchy tech 2 · `steam_tank` · http://codexcards-assets.surge.sh/images/0032_steam_tank.jpg
- **Pirate Gunship** — Anarchy tech 3 · `pirate_gunship` · http://codexcards-assets.surge.sh/images/0044_pirate_gunship.jpg
- **Captain Zane [`zane`]** — Anarchy hero · `captain_zane` · http://codexcards-assets.surge.sh/images/0000_anarchy_hero.jpg
- **Chaos Mirror** — Anarchy magic · `chaos_mirror` · http://codexcards-assets.surge.sh/images/0011_chaos_mirror.jpg
- **Detonate** — Anarchy magic · `detonate` · http://codexcards-assets.surge.sh/images/0012_detonate.jpg
- **Maximum Anarchy** — Anarchy magic · `maximum_anarchy` · http://codexcards-assets.surge.sh/images/0014_maximum_anarchy.jpg
- **Surprise Attack** — Anarchy magic · `surprise_attack` · http://codexcards-assets.surge.sh/images/0013_surprise_attack.jpg
- **Crash Bomber** — Blood tech 1 · `crash_bomber` · http://codexcards-assets.surge.sh/images/0025_crash_bomber.jpg
- **Rickety Mine** — Blood tech 1 · `rickety_mine` · http://codexcards-assets.surge.sh/images/0026_rickety_mine.jpg
- **Captured Bugblatter** — Blood tech 2 · `captured_bugblatter` · http://codexcards-assets.surge.sh/images/0035_captured_bugblatter.jpg
- **Crashbarrow** — Blood tech 2 · `crashbarrow` · http://codexcards-assets.surge.sh/images/0036_crashbarrow.jpg
- **Land Octopus** — Blood tech 2 · `land_octopus` · http://codexcards-assets.surge.sh/images/0037_land_octopus.jpg
- **Ogre Recruiter** — Blood tech 2 · `ogre_recruiter` · http://codexcards-assets.surge.sh/images/0038_ogre_recruiter.jpg
- **Shoddy Glider** — Blood tech 2 · `shoddy_glider` · http://codexcards-assets.surge.sh/images/0034_shoddy_glider.jpg
- **Pirate-Gang Commander** — Blood tech 3 · `pirategang_commander` · http://codexcards-assets.surge.sh/images/0045_pirate_gang_commander.jpg
- **Bloodlust** — Blood magic · `bloodlust` · http://codexcards-assets.surge.sh/images/0017_bloodlust.jpg
- **Desperation** — Blood magic · `desperation` · http://codexcards-assets.surge.sh/images/0015_desperation.jpg
- **Drakk Ramhorn [`drakk`]** — Blood hero · `drakk_ramhorn` · http://codexcards-assets.surge.sh/images/0001_blood_hero.jpg
- **Kidnapping** — Blood magic · `kidnapping` · http://codexcards-assets.surge.sh/images/0016_kidnapping.jpg
- **War Drums** — Blood magic · `war_drums` · http://codexcards-assets.surge.sh/images/0018_war_drums.jpg
- **Firebat** — Fire tech 1 · `firebat` · http://codexcards-assets.surge.sh/images/0028_firebat.jpg
- **Lobber** — Fire tech 1 · `lobber` · http://codexcards-assets.surge.sh/images/0027_lobber.jpg
- **Bamstamper Lizzo** — Fire tech 2 · `bamstamper_lizzo` · http://codexcards-assets.surge.sh/images/0039_bamstamper_lizzo.jpg
- **Doubleshot Archer** — Fire tech 2 · `doubleshot_archer` · http://codexcards-assets.surge.sh/images/0040_doubleshot_archer.jpg
- **Firehouse** — Fire tech 2 · `firehouse` · http://codexcards-assets.surge.sh/images/0042_firehouse.jpg
- **Hotter Fire** — Fire tech 2 · `hotter_fire` · http://codexcards-assets.surge.sh/images/0043_hotter_fire.jpg
- **Molting Firebird** — Fire tech 2 · `molting_firebird` · http://codexcards-assets.surge.sh/images/0041_molting_firebird.jpg
- **Cinderblast Dragon** — Fire tech 3 · `cinderblast_dragon` · http://codexcards-assets.surge.sh/images/0046_cinderblast_dragon.jpg
- **Burning Volley** — Fire magic · `burning_volley` · http://codexcards-assets.surge.sh/images/0022_burning_volley.jpg
- **Ember Sparks** — Fire magic · `ember_sparks` · http://codexcards-assets.surge.sh/images/0020_ember_sparks.jpg
- **Fire Dart** — Fire magic · `fire_dart` · http://codexcards-assets.surge.sh/images/0019_fire_dart.jpg
- **Flame Arrow** — Fire magic · `flame_arrow` · http://codexcards-assets.surge.sh/images/0021_flame_arrow.jpg
- **Jaina Stormborne [`jaina`]** — Fire hero · `jaina_stormborne` · http://codexcards-assets.surge.sh/images/0002_fire_hero.jpg
- **Bloodburn** — Red tech 0 · `bloodburn` · http://codexcards-assets.surge.sh/images/0007_bloodburn.jpg
- **Bloodrage Ogre** — Red tech 0 · `bloodrage_ogre` · http://codexcards-assets.surge.sh/images/0005_bloodrage_ogre.jpg
- **Bombaster** — Red tech 0 · `bombaster` · http://codexcards-assets.surge.sh/images/0003_bombaster.jpg
- **Careless Musketeer** — Red tech 0 · `careless_musketeer` · http://codexcards-assets.surge.sh/images/0004_careless_musketeer.jpg
- **Mad Man** — Red tech 0 · `mad_man` · http://codexcards-assets.surge.sh/images/0002_mad_man.jpg
- **Makeshift Rambaster** — Red tech 0 · `makeshift_rambaster` · http://codexcards-assets.surge.sh/images/0006_makeshift_rambaster.jpg
- **Nautical Dog** — Red tech 0 · `nautical_dog` · http://codexcards-assets.surge.sh/images/0001_nautical_dog.jpg
- **Charge** — Red magic · `charge` · http://codexcards-assets.surge.sh/images/0009_charge.jpg
- **Pillage** — Red magic · `pillage` · http://codexcards-assets.surge.sh/images/0010_pillage.jpg
- **Scorch** — Red magic · `scorch` · http://codexcards-assets.surge.sh/images/0008_scorch.jpg

## Green — 49 cards

- **Gemscout Owl** — Balance tech 1 · `gemscout_owl` · http://codexcards-assets.surge.sh/images/0022_gemscout_owl.jpg
- **Tiny Basilisk** — Balance tech 1 · `tiny_basilisk` · http://codexcards-assets.surge.sh/images/0023_tiny_basilisk.jpg
- **Chameleon** — Balance tech 2 · `chameleon` · http://codexcards-assets.surge.sh/images/0028_chameleon.jpg
- **Dothram Horselord** — Balance tech 2 · `dothram_horselord` · http://codexcards-assets.surge.sh/images/0030_dothram_horselord.jpg
- **Fairie Dragon** — Balance tech 2 · `fairie_dragon` · http://codexcards-assets.surge.sh/images/0029_fairie_dragon.jpg
- **Potent Basilisk** — Balance tech 2 · `potent_basilisk` · http://codexcards-assets.surge.sh/images/0032_potent_basilisk.jpg
- **Wandering Mimic** — Balance tech 2 · `wandering_mimic` · http://codexcards-assets.surge.sh/images/0031_wandering_mimic.jpg
- **Tyrannosaurus Rex** — Balance tech 3 · `tyrannosaurus_rex` · http://codexcards-assets.surge.sh/images/0043_tyrannosaurus_rex.jpg
- **Circle of Life** — Balance magic · `circle_of_life` · http://codexcards-assets.surge.sh/images/0012_circle_of_life.jpg
- **Final Showdown Ongoing** — Balance magic · `final_showdown` · http://codexcards-assets.surge.sh/images/0013_final_showdown.jpg
- **Master Midori [`midori`]** — Balance hero · `master_midori` · http://codexcards-assets.surge.sh/images/0003_balance_hero.jpg
- **Moment's Peace** — Balance magic · `moments_peace` · http://codexcards-assets.surge.sh/images/0010_moments_peace.jpg
- **Nature Reclaims** — Balance magic · `nature_reclaims` · http://codexcards-assets.surge.sh/images/0011_nature_reclaims.jpg
- **Centaur** — Feral tech 1 · `centaur` · http://codexcards-assets.surge.sh/images/0025_centaur.jpg
- **Huntress** — Feral tech 1 · `huntress` · http://codexcards-assets.surge.sh/images/0024_huntress.jpg
- **Barkcoat Bear** — Feral tech 2 · `barkcoat_bear` · http://codexcards-assets.surge.sh/images/0035_barkcoat_bear.jpg
- **Gigadon** — Feral tech 2 · `gigadon` · http://codexcards-assets.surge.sh/images/0037_gigadon.jpg
- **Predator Tiger** — Feral tech 2 · `predator_tiger` · http://codexcards-assets.surge.sh/images/0034_predator_tiger.jpg
- **Rampaging Elephant** — Feral tech 2 · `rampaging_elephant` · http://codexcards-assets.surge.sh/images/0036_rampaging_elephant.jpg
- **Stalking Tiger** — Feral tech 2 · `stalking_tiger` · http://codexcards-assets.surge.sh/images/0033_stalking_tiger.jpg
- **Moss Ancient** — Feral tech 3 · `moss_ancient` · http://codexcards-assets.surge.sh/images/0044_moss_ancient.jpg
- **Behind the Ferns** — Feral magic · `behind_the_ferns` · http://codexcards-assets.surge.sh/images/0015_behind_the_ferns.jpg
- **Calamandra Moss [`calamandra`]** — Feral hero · `calamandra_moss` · http://codexcards-assets.surge.sh/images/0004_feral_hero.jpg
- **Feral Strike** — Feral magic · `feral_strike` · http://codexcards-assets.surge.sh/images/0017_feral_strike.jpg
- **Ferocity** — Feral magic · `ferocity` · http://codexcards-assets.surge.sh/images/0014_ferocity.jpg
- **Murkwood Allies** — Feral magic · `murkwood_allies` · http://codexcards-assets.surge.sh/images/0016_murkwood_allies.jpg
- **Ironbark Treant** — Green tech 0 · `ironbark_treant` · http://codexcards-assets.surge.sh/images/0004_ironbark_treant.jpg
- **Merfolk Prospector** — Green tech 0 · `merfolk_prospector` · http://codexcards-assets.surge.sh/images/0000_merfolk_prospector.jpg
- **Playful Panda** — Green tech 0 · `playful_panda` · http://codexcards-assets.surge.sh/images/0003_playful_panda.jpg
- **Rich Earth** — Green tech 0 · `rich_earth` · http://codexcards-assets.surge.sh/images/0007_rich_earth.jpg
- **Spore Shambler** — Green tech 0 · `spore_shambler` · http://codexcards-assets.surge.sh/images/0005_spore_shambler.jpg
- **Tiger Cub** — Green tech 0 · `tiger_cub` · http://codexcards-assets.surge.sh/images/0001_tiger_cub.jpg
- **Verdant Tree** — Green tech 0 · `verdant_tree` · http://codexcards-assets.surge.sh/images/0006_verdant_tree.jpg
- **Young Treant** — Green tech 0 · `young_treant` · http://codexcards-assets.surge.sh/images/0002_young_treant.jpg
- **Forest's Favor** — Green magic · `forests_favor` · http://codexcards-assets.surge.sh/images/0009_forests_favor.jpg
- **Rampant Growth** — Green magic · `rampant_growth` · http://codexcards-assets.surge.sh/images/0008_rampant_growth.jpg
- **Galina Glimmer** — Growth tech 1 · `galina_glimmer` · http://codexcards-assets.surge.sh/images/0026_galina_glimmer.jpg
- **Giant Panda** — Growth tech 1 · `giant_panda` · http://codexcards-assets.surge.sh/images/0027_giant_panda.jpg
- **Artisan Mantis** — Growth tech 2 · `artisan_mantis` · http://codexcards-assets.surge.sh/images/0038_artisan_mantis.jpg
- **Blooming Ancient** — Growth tech 2 · `blooming_ancient` · http://codexcards-assets.surge.sh/images/0040_blooming_ancient.jpg
- **Blooming Elm** — Growth tech 2 · `blooming_elm` · http://codexcards-assets.surge.sh/images/0041_blooming_elm.jpg
- **Might of Leaf and Claw** — Growth tech 2 · `might_of_leaf_and_claw` · http://codexcards-assets.surge.sh/images/0042_might_of_leaf_and_claw.jpg
- **Oversized Rhinoceros** — Growth tech 2 · `oversized_rhinoceros` · http://codexcards-assets.surge.sh/images/0039_oversized_rhinoceros.jpg
- **Guargum, Eternal Sentinel [`guargum`]** — Growth tech 3 · `guargum_eternal_sentinel` · http://codexcards-assets.surge.sh/images/0045_guargum.jpg
- **Argagarg Garg [`argagarg`]** — Growth hero · `argagarg_garg` · http://codexcards-assets.surge.sh/images/0005_growth_hero.jpg
- **Dinosize** — Growth magic · `dinosize` · http://codexcards-assets.surge.sh/images/0019_dinosize.jpg
- **Polymorph: Squirrel** — Growth magic · `polymorph_squirrel` · http://codexcards-assets.surge.sh/images/0018_polymorph_squirrel.jpg
- **Spirit of the Panda** — Growth magic · `spirit_of_the_panda` · http://codexcards-assets.surge.sh/images/0020_spirit_of_the_panda.jpg
- **Stampede** — Growth magic · `stampede` · http://codexcards-assets.surge.sh/images/0021_stampede.jpg

## Blue — 49 cards

- **Bluecoat Musketeer** — Blue tech 0 · `bluecoat_musketeer` · http://codexcards-assets.surge.sh/images/0002_bluecoat_musketeer.jpg
- **Building Inspector** — Blue tech 0 · `building_inspector` · http://codexcards-assets.surge.sh/images/0000_building_inspector.jpg
- **Jail** — Blue tech 0 · `jail` · http://codexcards-assets.surge.sh/images/0006_jail.jpg
- **Porkhand Magistrate** — Blue tech 0 · `porkhand_magistrate` · http://codexcards-assets.surge.sh/images/0004_porkhand_magistrate.jpg
- **Reputable Newsman** — Blue tech 0 · `reputable_newsman` · http://codexcards-assets.surge.sh/images/0005_reputable_newsman.jpg
- **Spectral Aven** — Blue tech 0 · `spectral_aven` · http://codexcards-assets.surge.sh/images/0001_spectral_aven.jpg
- **Traffic Director** — Blue tech 0 · `traffic_director` · http://codexcards-assets.surge.sh/images/0003_traffic_director.jpg
- **Arrest** — Blue magic · `arrest` · http://codexcards-assets.surge.sh/images/0008_arrest.jpg
- **Lawful Search** — Blue magic · `lawful_search` · http://codexcards-assets.surge.sh/images/0007_lawful_search.jpg
- **Manufactured Truth** — Blue magic · `manufactured_truth` · http://codexcards-assets.surge.sh/images/0009_manufactured_truth.jpg
- **Scribe** — Law tech 1 · `scribe` · http://codexcards-assets.surge.sh/images/0023_scribe.jpg
- **Tax Collector** — Law tech 1 · `tax_collector` · http://codexcards-assets.surge.sh/images/0022_tax_collector.jpg
- **Arresting Constable** — Law tech 2 · `arresting_constable` · http://codexcards-assets.surge.sh/images/0036_arresting_constable.jpg
- **Censorship Council** — Law tech 2 · `censorship_council` · http://codexcards-assets.surge.sh/images/0037_censorship_council.jpg
- **Guardian of the Gates** — Law tech 2 · `guardian_of_the_gates` · http://codexcards-assets.surge.sh/images/0033_guardian_of_the_gates.jpg
- **Insurance Agent** — Law tech 2 · `insurance_agent` · http://codexcards-assets.surge.sh/images/0034_insurance_agent.jpg
- **Justice Juggernaut** — Law tech 2 · `justice_juggernaut` · http://codexcards-assets.surge.sh/images/0035_justice_juggernaut.jpg
- **Lawbringer Gryphon** — Law tech 3 · `lawbringer_gryphon` · http://codexcards-assets.surge.sh/images/0043_lawbringer_gryphon.jpg
- **Bigby Hayes [`bigby`]** — Law hero · `bigby_hayes` · http://codexcards-assets.surge.sh/images/0006_law_hero.jpg
- **Community Service** — Law magic · `community_service` · http://codexcards-assets.surge.sh/images/0012_community_service.jpg
- **Injunction** — Law magic · `injunction` · http://codexcards-assets.surge.sh/images/0011_injunction.jpg
- **Judgment Day** — Law magic · `judgment_day` · http://codexcards-assets.surge.sh/images/0013_judgment_day.jpg
- **Jurisdiction** — Law magic · `jurisdiction` · http://codexcards-assets.surge.sh/images/0010_jurisdiction.jpg
- **Brave Knight** — Peace tech 1 · `brave_knight` · http://codexcards-assets.surge.sh/images/0025_brave_knight.jpg
- **Overeager Cadet** — Peace tech 1 · `overeager_cadet` · http://codexcards-assets.surge.sh/images/0024_overeager_cadet.jpg
- **Air Hammer** — Peace tech 2 · `air_hammer` · http://codexcards-assets.surge.sh/images/0031_air_hammer.jpg
- **Debilitator Alpha** — Peace tech 2 · `debilitator_alpha` · http://codexcards-assets.surge.sh/images/0030_debilitator_alpha.jpg
- **Drill Sergeant** — Peace tech 2 · `drill_sergeant` · http://codexcards-assets.surge.sh/images/0028_drill_sergeant.jpg
- **Flagstone Garrison** — Peace tech 2 · `flagstone_garrison` · http://codexcards-assets.surge.sh/images/0032_flagstone_garrison.jpg
- **Flagstone Spy** — Peace tech 2 · `flagstone_spy` · http://codexcards-assets.surge.sh/images/0029_flagstone_spy.jpg
- **Patriot Gryphon** — Peace tech 3 · `patriot_gryphon` · http://codexcards-assets.surge.sh/images/0044_patriot_gryphon.jpg
- **Boot Camp** — Peace magic · `boot_camp` · http://codexcards-assets.surge.sh/images/0014_boot_camp.jpg
- **Elite Training** — Peace magic · `elite_training` · http://codexcards-assets.surge.sh/images/0015_elite_training.jpg
- **General Onimaru [`onimaru`]** — Peace hero · `general_onimaru` · http://codexcards-assets.surge.sh/images/0007_peace_hero.jpg
- **General's Hammer** — Peace magic · `generals_hammer` · http://codexcards-assets.surge.sh/images/0016_generals_hammer.jpg
- **The Art of War** — Peace magic · `the_art_of_war` · http://codexcards-assets.surge.sh/images/0017_the_art_of_war.jpg
- **Spectral Flagbearer** — Truth tech 1 · `spectral_flagbearer` · http://codexcards-assets.surge.sh/images/0026_spectral_flagbearer.jpg
- **Spectral Hound** — Truth tech 1 · `spectral_hound` · http://codexcards-assets.surge.sh/images/0027_spectral_hound.jpg
- **Eyes of the Chancellor** — Truth tech 2 · `eyes_of_the_chancellor` · http://codexcards-assets.surge.sh/images/0042_eyes_of_the_chancellor.jpg
- **Macciatus, The Whisperer [`macciatus`]** — Truth tech 2 · `macciatus_the_whisperer` · http://codexcards-assets.surge.sh/images/0038_macciatus.jpg
- **Reteller of Truths** — Truth tech 2 · `reteller_of_truths` · http://codexcards-assets.surge.sh/images/0039_reteller_of_truths.jpg
- **Spectral Roc** — Truth tech 2 · `spectral_roc` · http://codexcards-assets.surge.sh/images/0041_spectral_roc.jpg
- **Spectral Tiger** — Truth tech 2 · `spectral_tiger` · http://codexcards-assets.surge.sh/images/0040_spectral_tiger.jpg
- **Liberty Gryphon** — Truth tech 3 · `liberty_gryphon` · http://codexcards-assets.surge.sh/images/0045_liberty_gryphon.jpg
- **Dreamscape** — Truth magic · `dreamscape` · http://codexcards-assets.surge.sh/images/0020_dreamscape.jpg
- **Free Speech** — Truth magic · `free_speech` · http://codexcards-assets.surge.sh/images/0018_free_speech.jpg
- **Hallucination** — Truth magic · `hallucination` · http://codexcards-assets.surge.sh/images/0019_hallucination.jpg
- **Mind Control** — Truth magic · `mind_control` · http://codexcards-assets.surge.sh/images/0021_mind_control.jpg
- **Sirus Quince [`sirus`]** — Truth hero · `sirus_quince` · http://codexcards-assets.surge.sh/images/0008_truth_hero.jpg

## Black — 49 cards

- **Graveyard** — Black tech 0 · `graveyard` · http://codexcards-assets.surge.sh/images/0005_graveyard.jpg
- **Jandra, the Negator** — Black tech 0 · `jandra_the_negator` · http://codexcards-assets.surge.sh/images/0004_jandra.jpg
- **Pestering Haunt** — Black tech 0 · `pestering_haunt` · http://codexcards-assets.surge.sh/images/0000_pestering_haunt.jpg
- **Poisonblade Rogue** — Black tech 0 · `poisonblade_rogue` · http://codexcards-assets.surge.sh/images/0002_poisonblade_rogue.jpg
- **Skeletal Archery** — Black tech 0 · `skeletal_archery` · http://codexcards-assets.surge.sh/images/0006_skeletal_archery.jpg
- **Skeleton Javelineer** — Black tech 0 · `skeleton_javelineer` · http://codexcards-assets.surge.sh/images/0001_skeleton_javelineer.jpg
- **Thieving Imp** — Black tech 0 · `thieving_imp` · http://codexcards-assets.surge.sh/images/0003_theiving_imp.jpg
- **Deteriorate** — Black magic · `deteriorate` · http://codexcards-assets.surge.sh/images/0007_deteriorate.jpg
- **Sacrifice the Weak** — Black magic · `sacrifice_the_weak` · http://codexcards-assets.surge.sh/images/0009_sacrifice_the_weak.jpg
- **Summon Skeletons** — Black magic · `summon_skeletons` · http://codexcards-assets.surge.sh/images/0008_summon_skeletons.jpg
- **Gargoyle** — Demonology tech 1 · `gargoyle` · http://codexcards-assets.surge.sh/images/0022_gargoyle.jpg
- **Twilight Baron** — Demonology tech 1 · `twilight_baron` · http://codexcards-assets.surge.sh/images/0023_twilight_baron.jpg
- **Banefire Golem** — Demonology tech 2 · `banefire_golem` · http://codexcards-assets.surge.sh/images/0030_banefire_golem.jpg
- **Blackhand Dozer** — Demonology tech 2 · `blackhand_dozer` · http://codexcards-assets.surge.sh/images/0029_blackhand_dozer.jpg
- **Shrine of Forbidden Knowledge** — Demonology tech 2 · `shrine_of_forbidden_knowledge` · http://codexcards-assets.surge.sh/images/0032_shrine_of_forbidden_knowledge.jpg
- **Terras Q, the Shackled** — Demonology tech 2 · `terras_q_the_shackled` · http://codexcards-assets.surge.sh/images/0031_terras_q.jpg
- **Voidblocker** — Demonology tech 2 · `voidblocker` · http://codexcards-assets.surge.sh/images/0028_voidblocker.jpg
- **Zarramonde, the Obliterator** — Demonology tech 3 · `zarramonde_the_obliterator` · http://codexcards-assets.surge.sh/images/0043_zarramonde.jpg
- **Dark Pact** — Demonology magic · `dark_pact` · http://codexcards-assets.surge.sh/images/0011_dark_pact.jpg
- **Metamorphosis** — Demonology magic · `metamorphosis` · http://codexcards-assets.surge.sh/images/0013_metamorphosis.jpg
- **Shadow Blade** — Demonology magic · `shadow_blade` · http://codexcards-assets.surge.sh/images/0012_shadow_blade.jpg
- **Soul Stone** — Demonology magic · `soul_stone` · http://codexcards-assets.surge.sh/images/0010_soul_stone.jpg
- **Vandy Anadrose** — Demonology hero · `vandy_anadrose` · http://codexcards-assets.surge.sh/images/0009_demonology_hero.jpg
- **Crypt Crawler** — Disease tech 1 · `crypt_crawler` · http://codexcards-assets.surge.sh/images/0026_crypt_crawler.jpg
- **Plague Spitter** — Disease tech 1 · `plague_spitter` · http://codexcards-assets.surge.sh/images/0027_plague_spitter.jpg
- **Abomination** — Disease tech 2 · `abomination` · http://codexcards-assets.surge.sh/images/0036_abomination.jpg
- **Cursed Crow** — Disease tech 2 · `cursed_crow` · http://codexcards-assets.surge.sh/images/0035_cursed_crow.jpg
- **Cursed Ghoul** — Disease tech 2 · `cursed_ghoul` · http://codexcards-assets.surge.sh/images/0034_cursed_ghoul.jpg
- **Gorgon** — Disease tech 2 · `gorgon` · http://codexcards-assets.surge.sh/images/0033_gorgon.jpg
- **Plague Lab** — Disease tech 2 · `plague_lab` · http://codexcards-assets.surge.sh/images/0037_plague_lab.jpg
- **Plague Lord** — Disease tech 3 · `plague_lord` · http://codexcards-assets.surge.sh/images/0044_plague_lord.jpg
- **Carrion Curse** — Disease magic · `carrion_curse` · http://codexcards-assets.surge.sh/images/0016_carrion_curse.jpg
- **Death and Decay** — Disease magic · `death_and_decay` · http://codexcards-assets.surge.sh/images/0017_death_and_decay.jpg
- **Orpal Gloor** — Disease hero · `orpal_gloor` · http://codexcards-assets.surge.sh/images/0010_disease_hero.jpg
- **Sickness** — Disease magic · `sickness` · http://codexcards-assets.surge.sh/images/0014_sickness.jpg
- **Spreading Plague** — Disease magic · `spreading_plague` · http://codexcards-assets.surge.sh/images/0015_spreading_plague.jpg
- **Bone Collector** — Necromancy tech 1 · `bone_collector` · http://codexcards-assets.surge.sh/images/0025_bone_collector.jpg
- **Hooded Executioner** — Necromancy tech 1 · `hooded_executioner` · http://codexcards-assets.surge.sh/images/0024_hooded_executioner.jpg
- **Blackhand Resurrector** — Necromancy tech 2 · `blackhand_resurrector` · http://codexcards-assets.surge.sh/images/0038_blackhand_resurrector.jpg
- **Corpse Catapult** — Necromancy tech 2 · `corpse_catapult` · http://codexcards-assets.surge.sh/images/0040_corpse_catapult.jpg
- **Necromancer** — Necromancy tech 2 · `necromancer` · http://codexcards-assets.surge.sh/images/0042_necromancer.jpg
- **Skeletal Lord** — Necromancy tech 2 · `skeletal_lord` · http://codexcards-assets.surge.sh/images/0039_skeletal_lord.jpg
- **Wight** — Necromancy tech 2 · `wight` · http://codexcards-assets.surge.sh/images/0041_wight.jpg
- **Lord of Shadows** — Necromancy tech 3 · `lord_of_shadows` · http://codexcards-assets.surge.sh/images/0045_lord_of_shadows.jpg
- **Death Rites** — Necromancy magic · `death_rites` · http://codexcards-assets.surge.sh/images/0021_death_rites.jpg
- **Doom Grasp** — Necromancy magic · `doom_grasp` · http://codexcards-assets.surge.sh/images/0020_doom_grasp.jpg
- **Garth Torken** — Necromancy hero · `garth_torken` · http://codexcards-assets.surge.sh/images/0011_necromancy_hero.jpg
- **Lich's Bargain** — Necromancy magic · `lichs_bargain` · http://codexcards-assets.surge.sh/images/0019_lichs_bargain.jpg
- **Nether Drain** — Necromancy magic · `nether_drain` · http://codexcards-assets.surge.sh/images/0018_nether_drain.jpg

## White — 49 cards

- **Rambasa Twin** — Discipline tech 1 · `rambasa_twin` · http://codexcards-assets.surge.sh/images/0022_rambasa_twin.jpg
- **Sparring Partner** — Discipline tech 1 · `sparring_partner` · http://codexcards-assets.surge.sh/images/0023_sparring_partner.jpg
- **Focus Master** — Discipline tech 2 · `focus_master` · http://codexcards-assets.surge.sh/images/0029_focus_master.jpg
- **Mind-Parry Monk** — Discipline tech 2 · `mindparry_monk` · http://codexcards-assets.surge.sh/images/0031_mind_parry_monk.jpg
- **Training Grounds** — Discipline tech 2 · `training_grounds` · http://codexcards-assets.surge.sh/images/0032_training_grounds.jpg
- **Vigor Adept** — Discipline tech 2 · `vigor_adept` · http://codexcards-assets.surge.sh/images/0030_vigor_adept.jpg
- **Young Lightning Dragon** — Discipline tech 2 · `young_lightning_dragon` · http://codexcards-assets.surge.sh/images/0028_young_lightning_dragon.jpg
- **Hero's Monument Legendary** — Discipline tech 3 · `heros_monument` · http://codexcards-assets.surge.sh/images/0043_heros_monument.jpg
- **Grave Stormborne** — Discipline hero · `grave_stormborne` · http://codexcards-assets.surge.sh/images/0015_discipline_hero.jpg
- **Martial Mastery** — Discipline magic · `martial_mastery` · http://codexcards-assets.surge.sh/images/0010_martial_mastery.jpg
- **Reversal** — Discipline magic · `reversal` · http://codexcards-assets.surge.sh/images/0012_reversal.jpg
- **True Power of Storms** — Discipline magic · `true_power_of_storms` · http://codexcards-assets.surge.sh/images/0013_true_power_of_storms.jpg
- **Versatile Style** — Discipline magic · `versatile_style` · http://codexcards-assets.surge.sh/images/0011_versatile_style.jpg
- **Fuzz Cuddles** — Ninjutsu tech 1 · `fuzz_cuddles` · http://codexcards-assets.surge.sh/images/0025_fuzz_cuddles.jpg
- **Inverse Power Ninja** — Ninjutsu tech 1 · `inverse_power_ninja` · http://codexcards-assets.surge.sh/images/0024_inverse_power_ninja.jpg
- **Flying Fox** — Ninjutsu tech 2 · `flying_fox` · http://codexcards-assets.surge.sh/images/0033_flying_fox.jpg
- **Fox's Den School Legendary** — Ninjutsu tech 2 · `foxs_den_school` · http://codexcards-assets.surge.sh/images/0037_foxs_den_school.jpg
- **Glorious Ninja** — Ninjutsu tech 2 · `glorious_ninja` · http://codexcards-assets.surge.sh/images/0034_glorious_ninja.jpg
- **Masked Raccoon** — Ninjutsu tech 2 · `masked_raccoon` · http://codexcards-assets.surge.sh/images/0036_masked_raccoon.jpg
- **Porcupine** — Ninjutsu tech 2 · `porcupine` · http://codexcards-assets.surge.sh/images/0035_porcupine.jpg
- **Jade Fox, Den's Headmistress** — Ninjutsu tech 3 · `jade_fox_dens_headmistress` · http://codexcards-assets.surge.sh/images/0044_jade_fox.jpg
- **Fox's Den Students** — Ninjutsu magic · `foxs_den_students` · http://codexcards-assets.surge.sh/images/0017_foxs_den_students.jpg
- **Hidden Ninja** — Ninjutsu magic · `hidden_ninja` · http://codexcards-assets.surge.sh/images/0014_hidden_ninja.jpg
- **Setsuki Hiruki** — Ninjutsu hero · `setsuki_hiruki` · http://codexcards-assets.surge.sh/images/0016_ninjutsu_hero.jpg
- **Shuriken Hail** — Ninjutsu magic · `shuriken_hail` · http://codexcards-assets.surge.sh/images/0016_shuriken_hail.jpg
- **Speed of the Fox** — Ninjutsu magic · `speed_of_the_fox` · http://codexcards-assets.surge.sh/images/0015_speed_of_the_fox.jpg
- **Ardra's Boulder** — Strength tech 1 · `ardras_boulder` · http://codexcards-assets.surge.sh/images/0027_ardras_boulder.jpg
- **Mythmaking Legendary** — Strength tech 1 · `mythmaking` · http://codexcards-assets.surge.sh/images/0026_mythmaking.jpg
- **Colossus** — Strength tech 2 · `colossus` · http://codexcards-assets.surge.sh/images/0040_colossus.jpg
- **Doubling Barbarbarian** — Strength tech 2 · `doubling_barbarbarian` · http://codexcards-assets.surge.sh/images/0038_doubling_barbarbarian.jpg
- **Jefferson DeGrey, Ghostly Diplomat** — Strength tech 2 · `jefferson_degrey_ghostly_diplomat` · http://codexcards-assets.surge.sh/images/0041_jefferson_degrey.jpg
- **Morningstar Pass Legendary** — Strength tech 2 · `morningstar_pass` · http://codexcards-assets.surge.sh/images/0042_morningstar_pass.jpg
- **Whitestar Grappler** — Strength tech 2 · `whitestar_grappler` · http://codexcards-assets.surge.sh/images/0039_whitestar_grappler.jpg
- **Oathkeeper of Kor Mountain** — Strength tech 3 · `oathkeeper_of_kor_mountain` · http://codexcards-assets.surge.sh/images/0045_oathkeeper_of_kor_mountain.jpg
- **Bird's Nest** — Strength magic · `birds_nest` · http://codexcards-assets.surge.sh/images/0018_birds_nest.jpg
- **Earthquake** — Strength magic · `earthquake` · http://codexcards-assets.surge.sh/images/0021_earthquake.jpg
- **Entangling Vines** — Strength magic · `entangling_vines` · http://codexcards-assets.surge.sh/images/0019_entangling_vines.jpg
- **Garus Rook** — Strength hero · `garus_rook` · http://codexcards-assets.surge.sh/images/0017_strength_hero.jpg
- **Thunderclap** — Strength magic · `thunderclap` · http://codexcards-assets.surge.sh/images/0020_thunderclap.jpg
- **Aged Sensei** — White tech 0 · `aged_sensei` · http://codexcards-assets.surge.sh/images/0003_aged_sensei.jpg
- **Fox Primus** — White tech 0 · `fox_primus` · http://codexcards-assets.surge.sh/images/0005_fox_primus.jpg
- **Fox Viper** — White tech 0 · `fox_viper` · http://codexcards-assets.surge.sh/images/0002_fox_viper.jpg
- **Morningstar Flagbearer** — White tech 0 · `morningstar_flagbearer` · http://codexcards-assets.surge.sh/images/0004_morningstar_flagbearer.jpg
- **Safe Attacking** — White tech 0 · `safe_attacking` · http://codexcards-assets.surge.sh/images/0006_safe_attacking.jpg
- **Savior Monk** — White tech 0 · `savior_monk` · http://codexcards-assets.surge.sh/images/0001_savior_monk.jpg
- **Smoker** — White tech 0 · `smoker` · http://codexcards-assets.surge.sh/images/0000_smoker.jpg
- **Grappling Hook** — White magic · `grappling_hook` · http://codexcards-assets.surge.sh/images/0008_grappling_hook.jpg
- **Sensei's Advice** — White magic · `senseis_advice` · http://codexcards-assets.surge.sh/images/0007_senseis_advice.jpg
- **Snapback** — White magic · `snapback` · http://codexcards-assets.surge.sh/images/0009_snapback.jpg

## Purple — 49 cards

- **Gilded Glaxx** — Future tech 1 · `gilded_glaxx` · http://codexcards-assets.surge.sh/images/0027_gilded_glaxx.jpg
- **Knight of the Conclave** — Future tech 1 · `knight_of_the_conclave` · *no art on the database*
- **Hive** — Future tech 2 · `hive` · http://codexcards-assets.surge.sh/images/0042_hive.jpg
- **Omegacron** — Future tech 2 · `omegacron` · http://codexcards-assets.surge.sh/images/0038_omegacron.jpg
- **Reaver** — Future tech 2 · `reaver` · http://codexcards-assets.surge.sh/images/0039_reaver.jpg
- **Void Star** — Future tech 2 · `void_star` · http://codexcards-assets.surge.sh/images/0040_void_star.jpg
- **Xenostalker** — Future tech 2 · `xenostalker` · http://codexcards-assets.surge.sh/images/0041_xenostalker.jpg
- **Nebula** — Future tech 3 · `nebula` · http://codexcards-assets.surge.sh/images/0045_nebula.jpg
- **Assimilate** — Future magic · `assimilate` · http://codexcards-assets.surge.sh/images/0020_assimilate.jpg
- **Double Time** — Future magic · `double_time` · http://codexcards-assets.surge.sh/images/0021_double_time.jpg
- **Promise of Payment** — Future magic · `promise_of_payment` · http://codexcards-assets.surge.sh/images/0018_promise_of_payment.jpg
- **Unphase** — Future magic · `unphase` · http://codexcards-assets.surge.sh/images/0019_unphase.jpg
- **Vir Garbarean** — Future hero · `vir_garbarean` · http://codexcards-assets.surge.sh/images/0014_future_hero.jpg
- **Seer** — Past tech 1 · `seer` · http://codexcards-assets.surge.sh/images/0022_seer.jpg
- **Stewardess of the Undone** — Past tech 1 · `stewardess_of_the_undone` · http://codexcards-assets.surge.sh/images/0023_stewardess_of_the_undone.jpg
- **Rememberer** — Past tech 2 · `rememberer` · http://codexcards-assets.surge.sh/images/0030_rememberer.jpg
- **Second Chances** — Past tech 2 · `second_chances` · http://codexcards-assets.surge.sh/images/0031_second_chances.jpg
- **Shimmer Ray** — Past tech 2 · `shimmer_ray` · http://codexcards-assets.surge.sh/images/0028_shimmer_ray.jpg
- **Slow-Time Generator** — Past tech 2 · `slowtime_generator` · http://codexcards-assets.surge.sh/images/0032_slow_time_generator.jpg
- **Yesterday's Golgort** — Past tech 2 · `yesterdays_golgort` · http://codexcards-assets.surge.sh/images/0029_yesterdays_golgort.jpg
- **Ebbflow Archon** — Past tech 3 · `ebbflow_archon` · http://codexcards-assets.surge.sh/images/0043_ebbflow_archon.jpg
- **Origin Story** — Past magic · `origin_story` · http://codexcards-assets.surge.sh/images/0012_origin_story.jpg
- **Prynn Pasternaak** — Past hero · `prynn_pasternaak` · http://codexcards-assets.surge.sh/images/0012_past_hero.jpg
- **Rewind** — Past magic · `rewind` · http://codexcards-assets.surge.sh/images/0013_rewind.jpg
- **Undo** — Past magic · `undo` · http://codexcards-assets.surge.sh/images/0011_undo.jpg
- **Vortoss Emblem** — Past magic · `vortoss_emblem` · http://codexcards-assets.surge.sh/images/0010_vortoss_emblem.jpg
- **Argonaut** — Present tech 1 · `argonaut` · http://codexcards-assets.surge.sh/images/0024_argonaut.jpg
- **Sentry** — Present tech 1 · `sentry` · http://codexcards-assets.surge.sh/images/0025_sentry.jpg
- **Chronofixer** — Present tech 2 · `chronofixer` · http://codexcards-assets.surge.sh/images/0033_chronofixer.jpg
- **Hyperion** — Present tech 2 · `hyperion` · http://codexcards-assets.surge.sh/images/0034_hyperion.jpg
- **Immortal** — Present tech 2 · `immortal` · http://codexcards-assets.surge.sh/images/0036_immortal.jpg
- **Tricycloid** — Present tech 2 · `tricycloid` · http://codexcards-assets.surge.sh/images/0037_tricycloid.jpg
- **Warp Gate Disciple** — Present tech 2 · `warp_gate_disciple` · http://codexcards-assets.surge.sh/images/0035_warp_gate_disciple.jpg
- **Octavian** — Present tech 3 · `octavian` · http://codexcards-assets.surge.sh/images/0044_octavian.jpg
- **Max Geiger** — Present hero · `max_geiger` · http://codexcards-assets.surge.sh/images/0013_present_hero.jpg
- **Now!** — Present magic · `now` · http://codexcards-assets.surge.sh/images/0015_now.jpg
- **Ready or Not** — Present magic · `ready_or_not` · http://codexcards-assets.surge.sh/images/0016_ready_or_not.jpg
- **Research & Development** — Present magic · `research__development` · http://codexcards-assets.surge.sh/images/0017_research__development.jpg
- **Temporal Distortion** — Present magic · `temporal_distortion` · http://codexcards-assets.surge.sh/images/0014_temporal_distortion.jpg
- **Battle Suits** — Purple tech 0 · `battle_suits` · http://codexcards-assets.surge.sh/images/0006_battle_suits.jpg
- **Fading Argonaut** — Purple tech 0 · `fading_argonaut` · http://codexcards-assets.surge.sh/images/0003_fading_argonaut.jpg
- **Hardened Mox** — Purple tech 0 · `hardened_mox` · http://codexcards-assets.surge.sh/images/0005_hardened_mox.jpg
- **Neo Plexus** — Purple tech 0 · `neo_plexus` · http://codexcards-assets.surge.sh/images/0000_neo_plexus.jpg
- **Nullcraft** — Purple tech 0 · `nullcraft` · http://codexcards-assets.surge.sh/images/0002_nullcraft.jpg
- **Plasmodium** — Purple tech 0 · `plasmodium` · http://codexcards-assets.surge.sh/images/0001_plasmodium.jpg
- **Tinkerer** — Purple tech 0 · `tinkerer` · http://codexcards-assets.surge.sh/images/0004_tinkerer.jpg
- **Forgotten Fighter** — Purple magic · `forgotten_fighter` · http://codexcards-assets.surge.sh/images/0009_forgotten_fighter.jpg
- **Temporal Research** — Purple magic · `temporal_research` · http://codexcards-assets.surge.sh/images/0008_temporal_research.jpg
- **Time Spiral** — Purple magic · `time_spiral` · http://codexcards-assets.surge.sh/images/0007_time_spiral.jpg

## Neutral — 36 cards

- **Iron Man** — Bashing tech 1 · `iron_man` · http://codexcards-assets.surge.sh/images/0013_iron_man.jpg
- **Revolver Ocelot** — Bashing tech 1 · `revolver_ocelot` · http://codexcards-assets.surge.sh/images/0014_revolver_ocelot.jpg
- **Eggship** — Bashing tech 2 · `eggship` · http://codexcards-assets.surge.sh/images/0018_eggship.jpg
- **Harvest Reaper** — Bashing tech 2 · `harvest_reaper` · http://codexcards-assets.surge.sh/images/0019_harvest_reaper.jpg
- **Hired Stomper** — Bashing tech 2 · `hired_stomper` · http://codexcards-assets.surge.sh/images/0015_hired_stomper.jpg
- **Regular-sized Rhinoceros** — Bashing tech 2 · `regularsized_rhinoceros` · http://codexcards-assets.surge.sh/images/0016_regular_sized_rhinoceros.jpg
- **Sneaky Pig** — Bashing tech 2 · `sneaky_pig` · http://codexcards-assets.surge.sh/images/0017_sneaky_pig.jpg
- **Trojan Duck** — Bashing tech 3 · `trojan_duck` · http://codexcards-assets.surge.sh/images/0020_trojan_duck.jpg
- **Final Smash** — Bashing magic · `final_smash` · http://codexcards-assets.surge.sh/images/0024_final_smash.jpg
- **Intimidate** — Bashing magic · `intimidate` · http://codexcards-assets.surge.sh/images/0023_intimidate.jpg
- **The Boot** — Bashing magic · `the_boot` · http://codexcards-assets.surge.sh/images/0022_the_boot.jpg
- **Troq Bashar** — Bashing hero · `troq_bashar` · http://codexcards-assets.surge.sh/images/0020_bashing_hero.jpg
- **Wrecking Ball** — Bashing magic · `wrecking_ball` · http://codexcards-assets.surge.sh/images/0021_wrecking_ball.jpg
- **Nimble Fencer** — Finesse tech 1 · `nimble_fencer` · http://codexcards-assets.surge.sh/images/0025_nimble_fencer.jpg
- **Star-Crossed Starlet** — Finesse tech 1 · `starcrossed_starlet` · http://codexcards-assets.surge.sh/images/0026_star_crossed_starlet.jpg
- **Backstabber** — Finesse tech 2 · `backstabber` · http://codexcards-assets.surge.sh/images/0029_backstabber.jpg
- **Cloud Sprite** — Finesse tech 2 · `cloud_sprite` · http://codexcards-assets.surge.sh/images/0030_cloud_sprite.jpg
- **Grounded Guide** — Finesse tech 2 · `grounded_guide` · http://codexcards-assets.surge.sh/images/0027_grounded_guide.jpg
- **Leaping Lizard** — Finesse tech 2 · `leaping_lizard` · http://codexcards-assets.surge.sh/images/0031_leaping_lizard.jpg
- **Maestro** — Finesse tech 2 · `maestro` · http://codexcards-assets.surge.sh/images/0028_maestro.jpg
- **Blademaster** — Finesse tech 3 · `blademaster` · http://codexcards-assets.surge.sh/images/0032_blademaster.jpg
- **Appel Stomp** — Finesse magic · `appel_stomp` · http://codexcards-assets.surge.sh/images/0036_appel_stomp.jpg
- **Discord** — Finesse magic · `discord` · http://codexcards-assets.surge.sh/images/0034_discord.jpg
- **Harmony** — Finesse magic · `harmony` · http://codexcards-assets.surge.sh/images/0033_harmony.jpg
- **River Montoya** — Finesse hero · `river_montoya` · http://codexcards-assets.surge.sh/images/0021_finesse_hero.jpg
- **Two Step** — Finesse magic · `two_step` · http://codexcards-assets.surge.sh/images/0035_two_step.jpg
- **Brick Thief** — Neutral tech 0 · `brick_thief` · http://codexcards-assets.surge.sh/images/0006_brick_thief.jpg
- **Fruit Ninja** — Neutral tech 0 · `fruit_ninja` · http://codexcards-assets.surge.sh/images/0009_fruit_ninja.jpg
- **Granfalloon Flagbearer** — Neutral tech 0 · `granfalloon_flagbearer` · http://codexcards-assets.surge.sh/images/0008_granfalloon_flagbearer.jpg
- **Helpful Turtle** — Neutral tech 0 · `helpful_turtle` · http://codexcards-assets.surge.sh/images/0007_helpful_turtle.jpg
- **Older Brother** — Neutral tech 0 · `older_brother` · http://codexcards-assets.surge.sh/images/0005_older_brother.jpg
- **Tenderfoot** — Neutral tech 0 · `tenderfoot` · http://codexcards-assets.surge.sh/images/0004_tenderfoot.jpg
- **Timely Messenger** — Neutral tech 0 · `timely_messenger` · http://codexcards-assets.surge.sh/images/0003_timely_messenger.jpg
- **Bloom** — Neutral magic · `bloom` · http://codexcards-assets.surge.sh/images/0011_bloom.jpg
- **Spark** — Neutral magic · `spark` · http://codexcards-assets.surge.sh/images/0010_spark.jpg
- **Wither** — Neutral magic · `wither` · http://codexcards-assets.surge.sh/images/0012_wither.jpg
