# Jump System

## PayPal
[Donate to Motivate](https://paypal.me/Psyk0tikism?locale.x=en_US)

## License
> The following license is placed inside the source code of the plugin.
Jump System: a L4D/L4D2 SourceMod Plugin
Copyright (C) 2022  Alfred "Psyk0tik" Llagas

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

## About
Provides a system for controlling jumps.

## Credits
**epz/epzminion** - For helping with gamedata information, giving some ideas, and overall invaluable input.

**Chanz** - For the [[ANY] Infinite-Jumping](https://forums.alliedmods.net/showthread.php?t=132391) plugin.

**SourceMod Team** - For continually updating/improving SourceMod.

## Requirements
1. `SourceMod 1.11.0.6724` or higher
2. [`DHooks 2.2.0-detours15` or higher](https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589)
3. [`Source Scramble`](https://github.com/nosoop/SMExt-SourceScramble)
4. [`Left 4 DHooks`](https://forums.alliedmods.net/showthread.php?t=321696)
5. Knowledge of installing SourceMod plugins.

## Notes
1. I do not provide support for listen/local servers but the plugin should still work properly on them.
2. I will not help you with installing or troubleshooting problems on your part.
3. If you get errors from SourceMod itself, that is your problem, not mine.
4. MAKE SURE YOU MEET ALL THE REQUIREMENTS AND FOLLOW THE INSTALLATION GUIDE PROPERLY.

## Features
1. Automatic bunnyhopping - Hold down your jump button and automatically bunnyhop.
2. Adjustable jump height - Jump as high as you want (or as high as the map allows you).
3. Midair dashes - Jump as many times as you want after taking off from the ground.
4. No fall scream - Mute the game's fall scream while you fall. (This only works if you have a custom jump height or at least 1 midair dash.)
5. No fall damage - Block fall damage when you land from a high place. (This only works if you have a custom jump height or at least 1 midair dash.)
6. No death fall camera - Remove death fall camera when you land from a high place (only if the place you land on is a safe zone). [This only works if you have a custom jump height or at least 1 midair dash.]

## Commands
```
// Accessible by admins with "z" (Root) flag only.
sm_bhop - Toggle a player's automatic bunnyhopping.
- Usage: sm_bhop <-1: OFF|0: Use Cvar|1: ON>
- Usage: sm_bhop <#userid|name> <-1: OFF|0: Use Cvar|1: ON>
sm_bunny - Toggle a player's automatic bunnyhopping.
- Usage: sm_bunny <-1: OFF|0: Use Cvar|1: ON>
- Usage: sm_bunny <#userid|name> <-1: OFF|0: Use Cvar|1: ON>
sm_bunnyhop - Toggle a player's automatic bunnyhopping.
- Usage: sm_bunnyhop <-1: OFF|0: Use Cvar|1: ON>
- Usage: sm_bunnyhop <#userid|name> <-1: OFF|0: Use Cvar|1: ON>

sm_jump - Set a player's jump height.
- Usage: sm_jump <-1.0: OFF|0.0: Use Cvar|1.0-99999.0: ON>
- Usage: sm_jump <#userid|name> <-1.0: OFF|0.0: Use Cvar|1.0-99999.0: ON>
sm_height - Set a player's jump height.
- Usage: sm_height <-1.0: OFF|0.0: Use Cvar|1.0-99999.0: ON>
- Usage: sm_height <#userid|name> <-1.0: OFF|0.0: Use Cvar|1.0-99999.0: ON>

sm_dash - Set a player's midair dash count.
- Usage: sm_dash <-1: OFF|0: Use Cvar|1-99999: ON>
- Usage: sm_dash <#userid|name> <-1: OFF|0: Use Cvar|1-99999: ON>
sm_midair - Set a player's midair dash count.
- Usage: sm_midair <-1: OFF|0: Use Cvar|1-99999: ON>
- Usage: sm_midair <#userid|name> <-1: OFF|0: Use Cvar|1-99999: ON>
```

## ConVar Settings
```
// Enable automatic bunnyhopping.
// 0: OFF
// 1: ON
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
l4d_jump_system_auto_bunnyhop "1"

// Block death fall camera.
// 0: OFF
// 1: ON
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
l4d_jump_system_block_deathcamera "1"

// Block fall damage.
// 0: OFF
// 1: ON
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
l4d_jump_system_block_falldamage "1"

// Block fall scream.
// 0: OFF
// 1: ON
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
l4d_jump_system_block_fallscream "1"

// Disable Jump System in these game modes.
// Separate by commas.
// Empty: None
// Not empty: Disabled only in these game modes.
// -
// Default: ""
l4d_jump_system_disabled_gamemodes ""

// Enable Jump System.
// 0: OFF
// 1: ON
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
l4d_jump_system_enabled "1"

// Enable Jump System in these game modes.
// Separate by commas.
// Empty: All
// Not empty: Enabled only in these game modes.
// -
// Default: ""
l4d_jump_system_enabled_gamemodes ""

// Enable Jump System in these game mode types.
// 0 OR 15: All game mode types.
// 1: Co-Op modes only.
// 2: Versus modes only.
// 4: Survival modes only.
// 8: Scavenge modes only. (Only available in Left 4 Dead 2.)
// -
// Default: "0"
// Minimum: "0.000000"
// Maximum: "15.000000"
l4d_jump_system_gamemode_types "0"

// Height of each jump. (Game default: 57.0)
// -
// Default: "57.0"
// Minimum: "0.000000"
// Maximum: "99999.000000"
l4d_jump_system_jump_height "57.0"

// Number of midair dashes allowed after initial jump.
// 0: OFF
// 1-99999: Number of midair dashes allowed.
// -
// Default: "2"
// Minimum: "0.000000"
// Maximum: "99999.000000"
l4d_jump_system_midair_dashes "2"
```

## Installation
1. Delete files from old versions of the plugin.
2. Place `l4d_jump_system.txt` in the `addons/sourcemod/gamedata` folder.
3. Place `l4d_jump_system.smx` in the `addons/sourcemod/plugins` folder.
4. Place `l4d_jump_system.sp` in the `addons/sourcemod/scripting` folder.

## Uninstalling/Upgrading to Newer Versions
1. Delete `l4d_jump_system.sp` from the `addons/sourcemod/scripting` folder.
2. Delete `l4d_jump_system.smx` from the `addons/sourcemod/plugins` folder.
3. Delete `l4d_jump_system.txt` from the `addons/sourcemod/gamedata` folder.
4. Follow the Installation guide above. (Only for upgrading to newer versions.)

## Disabling
1. Move `l4d_jump_system.smx` to the `plugins/disabled` folder.
2. Unload Jump System by typing `sm plugins unload l4d_jump_system` in the server console.

## Third-Party Revisions Notice
If you would like to share your own revisions of this plugin, please rename the files so that there is no confusion for users.

## Final Words
Enjoy all my hard work and have fun with it!