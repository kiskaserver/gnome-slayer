GNOMOBOY — Shards of the Mountain Heart (v4.3.0)
======================================

What's new in 4.3 — the Craft of War Update:
  - Interactive tutorial on your first singleplayer campaign: nine guided
    steps (movement, sprint, combo, block & roll, chest, inventory,
    character sheet, belt items, and following a golden waypoint beacon
    to the elder). Skippable from the pause menu, replayable from the
    game menu; every step waits for the real action
  - Stamina: sprinting and dodge rolls drain the yellow bar under your
    health; it refills when you ease off. An empty bar drops sprint to a
    walk and blocks the roll (softer drain on Easy, harsher on Hard)
  - Parry: raise your block in the last moment before a hit to deflect
    it completely — the attacker staggers wide open for a finisher, and
    you get a burst of stamina back
  - Charged heavy attack: hold LMB out of combat to wind up, release to
    strike at 1.7x damage with a wider arc (costs stamina)
  - Explosive barrels: red-marked kegs scattered around battlefields,
    war camps and dungeon rooms — strike or bomb them for an area blast
    that hurts everyone and chain-detonates nearby barrels
  - The overworld is reforged: tighter map (radius 120 -> 80) with the
    dead space cut out, every area now has a real composed core (market
    stalls in the settlement, a broken shieldwall with planted swords on
    the battlefield, a graveyard approach to the crypt...), hidden
    road-side cache trails with chests, and chapter-specific area types:
    autumn brings a gnome war camp with an elite mini-boss, winter a
    fortified outpost, night a fenced cemetery
  - Dungeons got three themes by chapter: crypt (stone halls), cave
    (ragged caverns with glowing mushrooms), catacombs (a dense maze) —
    plus loop corridors, a secret room behind a cracked wall, a gated
    boss hall whose key is held by an elite mini-boss, a trophy alcove
    where you pick ONE of two rewards, and fire braziers among the traps
What's new in 4.2:
  - Localization fixes: shop consumables, PvP victory banner, mouse-button
    names, hotbar codes are now translated in all three languages
  - Big internal refactor (test harness, world generation, HUD panels,
    shop/POI services split into modules) — same gameplay, cleaner code

Patch 4.1.1 (level-design fixes):
  - Gates are open now (were showing closed doors across the road)
  - Lanterns stand beside the road facing it, not on the paths
  - Buildings and props no longer overlap or clip into each other

What's new in 4.1:
  - Crossbow weapon class: a ranged path — aim with the camera, the server
    resolves the hit (rate-limited, no PvP for now)
  - The settlement area now has real buildings (tavern, blacksmith, market,
    homes) instead of an empty field
  - Fixed props placed at wrong angles / not forming solid lines (fences,
    gates, lanterns now align correctly)
  - Performance: much less frame drop when turning the camera — fewer shadow
    casters and view-distance culling on distant trees/props

What's new in 4.0 — the Journey Update:
  - The story is no longer arena-hopping: each chapter is a large multi-area
    world — camp, settlement, battlefield, grove — linked by a real road with
    gates, ending at a crypt dungeon where the shard guardian waits
  - Procedural dungeons: torch-lit rooms and corridors, spike traps, loot
    rooms, a banner-dressed boss hall; the party descends together and
    portals back to the surface after taking the shard
  - Full inventory and equipment (I key): 20 slots, weapon + trinket,
    5 weapon classes with their own combos, 4 rarity tiers with random
    affixes; gear drops from bosses/elites/chests and persists in your save
  - Merchant at camp: buy gear and potions, sell your loot
  - Campfires are now respawn checkpoints; enemies keep to their home areas

What's new in 3.1:
  - Join from Discord: host an "Open" session and friends can jump in straight
    from your Discord status — the game receives the invite and connects
    automatically (LAN / Radmin VPN / internet). Pick Open or Private when
    creating a server.
  - Discord Rich Presence now shows party size, cover art, and (Open sessions)
    a Join button. Set your own Discord Application ID in Settings if you like.
  - A batch of stability and balance fixes: hired mages can now die properly and
    no longer take friendly fire, level-ups no longer soft-lock a downed
    teammate, sturdier server-side anti-cheat, and various smaller fixes.

Patch 3.0.1:
  - Cutscene subtitles used to flash by too fast to read — their on-screen
    time now scales with line length, and the whole HUD (bars, buffs, quest
    tracker, chat, hotbar...) hides completely during cutscenes instead of
    just part of it
  - Portal and points of interest now use real hand-modeled CC0 props (stone
    archway + columns for the portal, ruined pillars, a broken crypt entrance,
    a tattered war banner, real logs for the campfire...) instead of bare
    primitive shapes

What's new in 3.0:
  - Characters "talk": lines type out letter by letter with a retro blip sound,
    like old-school RPGs, instead of appearing instantly or using AI voices
  - Twice as many points of interest per map (4 instead of 2): campfires, wells
    and a bounty board join the shrine, ruins and standing stones — plus two
    new lore locations, an old crypt and a forgotten battlefield
  - Rare golden "elite" gnomes: more HP and damage, guaranteed rich loot, and
    their own achievement for hunting one down
  - Finisher mechanic: land the killing blow on a staggered gnome for bonus
    damage and a dedicated achievement
  - World lore roughly doubled (24 fragments instead of 6), with a lore-progress
    counter tracked per profile
  - 6 new achievements (19 total): elite hunter, bounty board, campfire rest,
    well wisher, finisher, and collecting all of a map's lore

Patch 2.9.1: toned down the hired mage's colors and removed a glow effect
that didn't fit the game's art style — now a subtle bronze/cream recolor
instead of a bright glowing look.

What's new in 2.9:
  - Hired mages now have their own distinct look (light robes, gold trim) instead
    of a plain recolor, level up, and stick close instead of wandering off to fight
  - Cinematic multi-shot cutscenes for chapter transitions
  - World lore details scattered across the map — examine ruins and standing
    stones to read fragments of the story (fully localized)
  - Points of interest are now interactive: ask a shrine for a blessing, or
    examine ruins/standing stones for lore
  - New "Second Wind" mechanic: a one-time safety net when you're near death
  - Taller tent roof and fixed NPC name tags clipping into hats/hoods

Previously in 2.8:
  - Bosses now have unique attack patterns (ground slam, charge, summon adds)
  - Chapters end with a portal you walk into, plus a short cutscene
  - Branching skill tree (in addition to the stat panel)
  - Achievement system (see "Achievements" in the main menu)
  - Bigger arenas with new points of interest
  - Various fixes: chest/obstacle collision, ragdoll clipping, smoother HUD bars

To launch:
  chmod +x Gnomoboy.x86_64   (if the archive didn't preserve permissions)
  ./Gnomoboy.x86_64

Requires a Vulkan-compatible video driver (included in any modern distribution).
Discord Rich Presence on Linux uses python3 (installed on almost all systems);
if it's missing, the game simply runs without Discord status.

Controls:
  WASD        — movement
  Shift       — sprint (drains stamina)
  LMB         — attack (hold out of combat to charge a heavy strike)
  RMB (hold)  — block (raise it at the last moment to parry)
  Space       — roll (costs stamina)
  E           — revive fallen friend / talk to NPC / open chest / interact
  I           — inventory & equipment
  C           — hero stats (leveling up) & skill tree
  1-5         — belt items
  V (hold)    — voice chat
  T           — text chat
  ESC         — pause / settings

Multiplayer: "Multiplayer" -> host opens port 7788 (UDP), or everyone
connects via Radmin VPN. Windows <-> Linux crossplay is supported.