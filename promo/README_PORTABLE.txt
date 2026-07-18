GNOMOBOY — Shards of the Mountain Heart (v4.3.0) — PORTABLE EDITION
======================================

This is the portable Windows build: everything the game writes — saves,
settings, keybinds, achievements — is stored in a "data_..." folder NEXT TO
the executable instead of the Windows user profile. Unzip it to a USB stick
or any folder, play anywhere, carry your progress with you.

How it works: the empty "_sc_" file next to Gnomoboy.exe switches the Godot
engine into self-contained mode. Keep that file where it is; delete it and
the game will fall back to the regular per-user save location (%APPDATA%).

To launch: run Gnomoboy.exe (no installation required).

Upon the first launch, Windows SmartScreen may display a warning —
click "More info" -> "Run anyway."

For the full changelog and controls, see the notes inside the regular
Windows package or the itch.io page. Quick reference:

  WASD        — Movement          Shift — Sprint (stamina)
  LMB         — Attack (hold out of combat to charge a heavy strike)
  RMB (hold)  — Block (last-moment raise = parry)
  Space       — Roll              E     — Interact / revive
  I           — Inventory         C     — Stats & skill tree
  1-5         — Belt items        V/T   — Voice / text chat

Multiplayer: "Multiplayer" -> Host opens port 7788 (UDP), or everyone
connects via Radmin VPN. Windows <-> Linux crossplay is supported.
