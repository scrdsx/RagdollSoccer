# Ragdoll Soccer script

Built from a dump of the game (Ragdoll Soccer 8v8, place `106931373443671`). Uses the same window library as the Scrdsx script, kept as its own project.

```
RagdollSoccer/
  VERSION            version string used by build.py
  build.py           bundles src/ -> dist/RagdollSoccer.lua and copies it into the executor workspace
  src/
    main.lua         window, tabs, settings, autosave, keys
    lib/             window library (ui, logo, icons, sfx, config), copied from Scrdsx and pointed at the RagdollSoccer/ workspace folder
    game/
      world.lua      ball, goals, teams, who has the ball, shot target
      net.lua        the single __namecall hook; modules register handlers per remote
      rules.lua      the game's own rule tables (perfect accuracy, sticky ball)
      speed.lua      speed multiplier (scales the game's Tuning.Speed table)
      kick.lua       silent goal aim + power boost on your own shots (KickPlan / DribbleRelease)
      fun.lua        spinbot, moonwalk, sideways, jitter, ball magnet
  tools/game_dump.lua   the dump tool that produced dumps/
  dumps/                the dump of the game (overview + decompiled scripts)
  dist/                 build output
```

## Run (GitHub)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/scrdsx/RagdollSoccer/main/loader.lua"))()
```

## Run (local build)

```
python build.py
```
then in the executor:
```lua
loadstring(readfile("RagdollSoccer/RagdollSoccer.lua"))()
```

## Notes from the dump
- Your player is a Mannequin model (part `Root`, a `ControllerManager`), the ball is `Workspace.Ball` (tag `SoccerBall`), the goals are tagged `SoccerGoalFrame`.
- Kick: `KickPlan { id, leg, t, ball, dir, family, power, ... }` then `DribbleRelease (pid, kind, ballPos, vel, t, nil, spin, family)`.
- Dribble: `DribbleClaim`, `DribbleTouch` (stream), `DribbleBody` (unreliable), `DribbleKnock`.
- Inputs are Roblox `InputAction`s under PlayerScripts (`KickStrike`, `Sprint`, ...); `Fire(true/false)` presses / releases them.
- No stamina exists in the client code.
