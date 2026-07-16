GNOMOBOY — Shards of the Mountain Heart (v3.0.1)
======================================

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
  LMB / RMB   — attack / block
  Space       — roll
  E           — revive fallen friend / talk to NPC / open chest
  V (hold)    — voice chat
  T           — text chat
  C           — hero stats (leveling up)
  ESC         — pause / settings

Multiplayer: "Multiplayer" -> host opens port 7788 (UDP), or everyone
connects via Radmin VPN. Windows <-> Linux crossplay is supported.