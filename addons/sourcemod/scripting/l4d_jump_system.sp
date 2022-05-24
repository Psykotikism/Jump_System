/**
 * Jump System: a L4D/L4D2 SourceMod Plugin
 * Copyright (C) 2022  Alfred "Psyk0tik" Llagas
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

#include <sourcemod>
#include <dhooks>
#include <sourcescramble>
#include <left4dhooks>

#pragma semicolon 1
#pragma newdecls required

#define JS_VERSION "1.3"

public Plugin myinfo =
{
	name = "[L4D & L4D2] Jump System",
	author = "Psyk0tik",
	description = "Provides a system for controlling jumps.",
	version = JS_VERSION,
	url = "https://github.com/Psykotikism/Jump_System"
};

bool g_bDedicated, g_bLateLoad, g_bSecondGame;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	switch (GetEngineVersion())
	{
		case Engine_Left4Dead: g_bSecondGame = false;
		case Engine_Left4Dead2: g_bSecondGame = true;
		default:
		{
			strcopy(error, err_max, "\"Jump System\" only supports Left 4 Dead 1 & 2.");

			return APLRes_SilentFailure;
		}
	}

	g_bDedicated = IsDedicatedServer();
	g_bLateLoad = late;

	return APLRes_Success;
}

#define SOUND_DAMAGE "player/damage1.wav"
#define SOUND_DAMAGE2 "player/damage2.wav"
#define SOUND_NULL "common/null.wav"

// Client check flags
#define JS_CHECK_INDEX (1 << 0) // check 0 < client <= MaxClients
#define JS_CHECK_CONNECTED (1 << 1) // check IsClientConnected(client)
#define JS_CHECK_INGAME (1 << 2) // check IsClientInGame(client)
#define JS_CHECK_ALIVE (1 << 3) // check IsPlayerAlive(client)
#define JS_CHECK_INKICKQUEUE (1 << 4) // check IsClientInKickQueue(client)
#define JS_CHECK_FAKECLIENT (1 << 5) // check IsFakeClient(client)

#define JS_JUMP_DASHCOOLDOWN 0.15 // time between air dashes
#define JS_JUMP_DEFAULTHEIGHT 57.0 // default jump height

// Chat tags
#define JS_TAG "[JS]"
#define JS_TAG2 "\x04[JS]\x01"
#define JS_TAG3 "\x04[JS]\x03"
#define JS_TAG4 "\x04[JS]\x04"
#define JS_TAG5 "\x04[JS]\x05"

// Water levels
#define JS_WATER_NONE 0 // not in water
#define JS_WATER_FEET 1 // feet in water
#define JS_WATER_WAIST 2 // waist in water
#define JS_WATER_HEAD 3 // head in water

// Entity mask information
#define MAX_EDICT_BITS 11
#define NUM_ENT_ENTRY_BITS (MAX_EDICT_BITS + 1)
#define NUM_ENT_ENTRIES (1 << NUM_ENT_ENTRY_BITS)
#define ENT_ENTRY_MASK (NUM_ENT_ENTRIES - 1)
#define INVALID_EHANDLE_INDEX 0xFFFFFFFF

enum struct esGeneral
{
	Address g_adDoJumpValue;
	Address g_adOriginalJumpHeight[2];

	bool g_bMapStarted;
	bool g_bPatchFallingSound;
	bool g_bPatchJumpHeight;
	bool g_bPluginEnabled;
	bool g_bUpdateDoJumpMemAccess;

	ConVar g_cvJSAutoBunnyhop;
	ConVar g_cvJSBlockDeathCamera;
	ConVar g_cvJSBlockFallDamage;
	ConVar g_cvJSBlockFallScream;
	ConVar g_cvJSBunnyhopMode;
	ConVar g_cvJSDisabledGameModes;
	ConVar g_cvJSEnabledGameModes;
	ConVar g_cvJSForwardJumpBoost;
	ConVar g_cvJSGameMode;
	ConVar g_cvJSGameModeTypes;
	ConVar g_cvJSJumpHeight;
	ConVar g_cvJSMidairDashes;
	ConVar g_cvJSPluginEnabled;

	DynamicDetour g_ddBaseEntityGetGroundEntityDetour;
	DynamicDetour g_ddCheckJumpButtonDetour;
	DynamicDetour g_ddDeathFallCameraEnableDetour;
	DynamicDetour g_ddDoJumpDetour;
	DynamicDetour g_ddFallingDetour;

	Handle g_hSDKGetRefEHandle;

	int g_iCurrentMode;
	int g_iPlatformType;

	MemoryPatch g_mpFallScreamMute;
}

esGeneral g_esGeneral;

enum struct esPlayer
{
	bool g_bFallDamage;
	bool g_bFalling;
	bool g_bFallTracked;
	bool g_bFatalFalling;
	bool g_bReleasedJump;

	float g_flJumpHeight;
	float g_flLastJumpTime;
	float g_flPreFallZ;

	int g_iBunnyHop;
	int g_iMidairDashesCount;
	int g_iMidairDashesLimit;
}

esPlayer g_esPlayer[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_bhop", cmdJSBunnyHop, ADMFLAG_ROOT, "Toggle a player's automatic bunnyhopping.");
	RegAdminCmd("sm_bunny", cmdJSBunnyHop, ADMFLAG_ROOT, "Toggle a player's automatic bunnyhopping.");
	RegAdminCmd("sm_bunnyhop", cmdJSBunnyHop, ADMFLAG_ROOT, "Toggle a player's automatic bunnyhopping.");
	RegAdminCmd("sm_jump", cmdJSJumpHeight, ADMFLAG_ROOT, "Set a player's jump height.");
	RegAdminCmd("sm_height", cmdJSJumpHeight, ADMFLAG_ROOT, "Set a player's jump height.");
	RegAdminCmd("sm_dash", cmdJSMidairDash, ADMFLAG_ROOT, "Set a player's midair dash count.");
	RegAdminCmd("sm_midair", cmdJSMidairDash, ADMFLAG_ROOT, "Set a player's midair dash count.");

	g_esGeneral.g_cvJSAutoBunnyhop = CreateConVar("l4d_jump_system_auto_bunnyhop", "1", "Enable automatic bunnyhopping.\n0: OFF\n1: ON", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_esGeneral.g_cvJSBlockDeathCamera = CreateConVar("l4d_jump_system_block_deathcamera", "1", "Block death fall camera.\n0: OFF\n1: ON", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_esGeneral.g_cvJSBlockFallDamage = CreateConVar("l4d_jump_system_block_falldamage", "1", "Block fall damage.\n0: OFF\n1: ON", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_esGeneral.g_cvJSBlockFallScream = CreateConVar("l4d_jump_system_block_fallscream", "1", "Block fall scream.\n0: OFF\n1: ON", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_esGeneral.g_cvJSBunnyhopMode = CreateConVar("l4d_jump_system_bunnyhop_mode", "0", "Enable more control for bunnyhopping.\n0: OFF\n1: ON", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_esGeneral.g_cvJSDisabledGameModes = CreateConVar("l4d_jump_system_disabled_gamemodes", "", "Disable Jump System in these game modes.\nSeparate by commas.\nEmpty: None\nNot empty: Disabled only in these game modes.", FCVAR_NOTIFY);
	g_esGeneral.g_cvJSEnabledGameModes = CreateConVar("l4d_jump_system_enabled_gamemodes", "", "Enable Jump System in these game modes.\nSeparate by commas.\nEmpty: All\nNot empty: Enabled only in these game modes.", FCVAR_NOTIFY);
	g_esGeneral.g_cvJSForwardJumpBoost = CreateConVar("l4d_jump_system_forward_jumpboost", "50.0", "Forward boost for each jump.", FCVAR_NOTIFY, true, 0.0, true, 99999.0);
	g_esGeneral.g_cvJSGameModeTypes = CreateConVar("l4d_jump_system_gamemode_types", "0", "Enable Jump System in these game mode types.\n0 OR 15: All game mode types.\n1: Co-Op modes only.\n2: Versus modes only.\n4: Survival modes only.\n8: Scavenge modes only. (Only available in Left 4 Dead 2.)", FCVAR_NOTIFY, true, 0.0, true, 15.0);
	g_esGeneral.g_cvJSJumpHeight = CreateConVar("l4d_jump_system_jump_height", "57.0", "Height of each jump. (Game default: 57.0)", FCVAR_NOTIFY, true, 0.0, true, 99999.0);
	g_esGeneral.g_cvJSMidairDashes = CreateConVar("l4d_jump_system_midair_dashes", "2", "Number of midair dashes allowed after initial jump.\n0: OFF\n1-99999: Number of midair dashes allowed.", FCVAR_NOTIFY, true, 0.0, true, 99999.0);
	g_esGeneral.g_cvJSPluginEnabled = CreateConVar("l4d_jump_system_enabled", "1", "Enable Jump System.\n0: OFF\n1: ON", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	CreateConVar("l4d_jump_system_version", JS_VERSION, "Jump System Version", FCVAR_DONTRECORD|FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_SPONLY);
	AutoExecConfig(true, "l4d_jump_system");

	g_esGeneral.g_cvJSGameMode = FindConVar("mp_gamemode");

	g_esGeneral.g_cvJSDisabledGameModes.AddChangeHook(vPluginStatusCvar);
	g_esGeneral.g_cvJSEnabledGameModes.AddChangeHook(vPluginStatusCvar);
	g_esGeneral.g_cvJSGameMode.AddChangeHook(vPluginStatusCvar);
	g_esGeneral.g_cvJSGameModeTypes.AddChangeHook(vPluginStatusCvar);
	g_esGeneral.g_cvJSPluginEnabled.AddChangeHook(vPluginStatusCvar);

	GameData gdJumpSystem = new GameData("l4d_jump_system");

	switch (gdJumpSystem == null)
	{
		case true: SetFailState("Unable to load the \"l4d_jump_system\" gamedata file.");
		case false:
		{
			g_esGeneral.g_iPlatformType = gdJumpSystem.GetOffset("OS");
			if (g_esGeneral.g_iPlatformType == -1)
			{
				LogError("%s Failed to load offset: OS", JS_TAG);
			}

			g_esGeneral.g_adDoJumpValue = gdJumpSystem.GetAddress("DoJumpValueBytes");
			if (g_esGeneral.g_adDoJumpValue == Address_Null)
			{
				LogError("%s Failed to find address from \"DoJumpValueBytes\". Retrieving from \"DoJumpValueRead\" instead.", JS_TAG);

				if (g_bSecondGame || g_esGeneral.g_iPlatformType < 2)
				{
					g_esGeneral.g_adDoJumpValue = gdJumpSystem.GetAddress("DoJumpValueRead");
					if (g_esGeneral.g_adDoJumpValue == Address_Null)
					{
						LogError("%s Failed to find address from \"DoJumpValueRead\". Failed to retrieve address from both methods.", JS_TAG);
					}
				}
				else
				{
					Address adValue[4] = {Address_Null, Address_Null, Address_Null, Address_Null};
					adValue[0] = gdJumpSystem.GetAddress("GetMaxJumpHeightStart");

					int iOffset[3] = {-1, -1, -1};
					iOffset[0] = gdJumpSystem.GetOffset("PlayerLocomotion::GetMaxJumpHeight::Call");
					iOffset[1] = gdJumpSystem.GetOffset("PlayerLocomotion::GetMaxJumpHeight::Add");
					iOffset[2] = gdJumpSystem.GetOffset("PlayerLocomotion::GetMaxJumpHeight::Value");

					if (adValue[0] == Address_Null || iOffset[0] == -1 || iOffset[1] == -1 || iOffset[2] == -1)
					{
						LogError("%s Failed to find address from \"DoJumpValueRead\". Failed to retrieve address from both methods.", JS_TAG);
					}
					else
					{
						adValue[1] = adValue[0] + view_as<Address>(iOffset[0]);
						adValue[2] = LoadFromAddress((adValue[0] + view_as<Address>(iOffset[1])), NumberType_Int32);
						adValue[3] = LoadFromAddress((adValue[0] + view_as<Address>(iOffset[2])), NumberType_Int32);
						g_esGeneral.g_adDoJumpValue = (adValue[1] + adValue[2] + adValue[3]);
					}
				}
			}

			StartPrepSDKCall(SDKCall_Raw);
			if (!PrepSDKCall_SetFromConf(gdJumpSystem, SDKConf_Virtual, "CBaseEntity::GetRefEHandle"))
			{
				LogError("%s Failed to find signature: CBaseEntity::GetRefEHandle", JS_TAG);
			}

			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);

			g_esGeneral.g_hSDKGetRefEHandle = EndPrepSDKCall();
			if (g_esGeneral.g_hSDKGetRefEHandle == null)
			{
				LogError("%s Your \"CBaseEntity::GetRefEHandle\" signature is outdated.", JS_TAG);
			}

			vSetupDetour(g_esGeneral.g_ddBaseEntityGetGroundEntityDetour, gdJumpSystem, "JSDetour_CBaseEntity::GetGroundEntity");
			vSetupDetour(g_esGeneral.g_ddCheckJumpButtonDetour, gdJumpSystem, "JSDetour_CTerrorGameMovement::CheckJumpButton");
			vSetupDetour(g_esGeneral.g_ddDeathFallCameraEnableDetour, gdJumpSystem, "JSDetour_CDeathFallCamera::Enable");
			vSetupDetour(g_esGeneral.g_ddDoJumpDetour, gdJumpSystem, "JSDetour_CTerrorGameMovement::DoJump");
			vSetupDetour(g_esGeneral.g_ddFallingDetour, gdJumpSystem, "JSDetour_CTerrorPlayer::OnFalling");

			vSetupPatch(g_esGeneral.g_mpFallScreamMute, gdJumpSystem, "JSPatch_FallScreamMute");

			delete gdJumpSystem;
		}
	}

	g_esGeneral.g_bUpdateDoJumpMemAccess = true;

	if (g_bLateLoad)
	{
		for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
		{
			if (bIsValidClient(iPlayer, JS_CHECK_INGAME))
			{
				OnClientPutInServer(iPlayer);
			}
		}

		g_bLateLoad = false;
	}
}

public void OnMapStart()
{
	g_esGeneral.g_bMapStarted = true;

	PrecacheSound(SOUND_DAMAGE, true);
	PrecacheSound(SOUND_DAMAGE2, true);
	PrecacheSound(SOUND_NULL, true);

	AddNormalSoundHook(FallSoundHook);
}

public void OnMapEnd()
{
	g_esGeneral.g_bMapStarted = false;

	RemoveNormalSoundHook(FallSoundHook);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
}

public void OnConfigsExecuted()
{
	vPluginStatus();
}

Action cmdJSBunnyHop(int client, int args)
{
	client = iGetListenServerHost(client, g_bDedicated);
	if (!bIsValidClient(client, JS_CHECK_INDEX|JS_CHECK_INGAME|JS_CHECK_FAKECLIENT))
	{
		ReplyToCommand(client, "%s You must be in-game to use this command", JS_TAG);

		return Plugin_Handled;
	}

	if (!g_esGeneral.g_bPluginEnabled)
	{
		ReplyToCommand(client, "%s You cannot use this command right now.", JS_TAG2);

		return Plugin_Handled;
	}

	switch (args)
	{
		case 1:
		{
			g_esPlayer[client].g_iBunnyHop = iClamp(GetCmdArgInt(1), -1, 1);

			ReplyToCommand(client, "%s You\x05 %s\x01 your\x03 automatic bunnyhopping\x01.", JS_TAG2, ((g_esPlayer[client].g_iBunnyHop == 1) ? "enabled" : "disabled"));
		}
		case 2:
		{
			bool tn_is_ml;
			char target[32], target_name[32];
			int target_list[MAXPLAYERS], target_count;
			GetCmdArg(1, target, sizeof target);
			if ((target_count = ProcessTargetString(target, client, target_list, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, target_name, sizeof target_name, tn_is_ml)) <= 0)
			{
				ReplyToTargetError(client, target_count);

				return Plugin_Handled;
			}

			int iToggle = iClamp(GetCmdArgInt(2), -1, 1);
			for (int iPlayer = 0; iPlayer < target_count; iPlayer++)
			{
				if (bIsValidClient(target_list[iPlayer]))
				{
					g_esPlayer[target_list[iPlayer]].g_iBunnyHop = iToggle;

					ReplyToCommand(client, "%s You %s\x05 %N's\x01 automatic bunnyhopping.", JS_TAG2, ((g_esPlayer[target_list[iPlayer]].g_iBunnyHop == 1) ? "enabled" : "disabled"), target_list[iPlayer]);
					PrintToChat(target_list[iPlayer], "%s You %s have\x03 automatic bunnyhopping\x01.", JS_TAG2, ((g_esPlayer[target_list[iPlayer]].g_iBunnyHop == 1) ? "now" : "no longer"));
				}
			}
		}
		default:
		{
			char sCmd[32];
			GetCmdArg(0, sCmd, sizeof sCmd);
			ReplyToCommand(client, "%s Usage: %s <-1: OFF|0: Use Cvar|1: ON>", JS_TAG2, sCmd);
		}
	}

	return Plugin_Handled;
}

Action cmdJSJumpHeight(int client, int args)
{
	client = iGetListenServerHost(client, g_bDedicated);
	if (!bIsValidClient(client, JS_CHECK_INDEX|JS_CHECK_INGAME|JS_CHECK_FAKECLIENT))
	{
		ReplyToCommand(client, "%s You must be in-game to use this command", JS_TAG);

		return Plugin_Handled;
	}

	if (!g_esGeneral.g_bPluginEnabled)
	{
		ReplyToCommand(client, "%s You cannot use this command right now.", JS_TAG2);

		return Plugin_Handled;
	}

	switch (args)
	{
		case 1:
		{
			char sValue[8];
			GetCmdArg(1, sValue, sizeof sValue);
			g_esPlayer[client].g_flJumpHeight = flClamp(StringToFloat(sValue), -1.0, 99999.0);

			ReplyToCommand(client, "%s You set your\x03 jump height\x01 to\x05 %.2f\x01.", JS_TAG2, g_esPlayer[client].g_flJumpHeight);
		}
		case 2:
		{
			bool tn_is_ml;
			char target[32], target_name[32];
			int target_list[MAXPLAYERS], target_count;
			GetCmdArg(1, target, sizeof target);
			if ((target_count = ProcessTargetString(target, client, target_list, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, target_name, sizeof target_name, tn_is_ml)) <= 0)
			{
				ReplyToTargetError(client, target_count);

				return Plugin_Handled;
			}

			char sValue[8];
			GetCmdArg(2, sValue, sizeof sValue);
			for (int iPlayer = 0; iPlayer < target_count; iPlayer++)
			{
				if (bIsValidClient(target_list[iPlayer]))
				{
					g_esPlayer[target_list[iPlayer]].g_flJumpHeight = flClamp(StringToFloat(sValue), -1.0, 99999.0);

					ReplyToCommand(client, "%s You set\x05 %N's\x01 jump height to\x03 %.2f\x01.", JS_TAG2, target_list[iPlayer], g_esPlayer[target_list[iPlayer]].g_flJumpHeight);
					PrintToChat(target_list[iPlayer], "%s Your\x03 jump height\x01 has been set to\x05 %.2f\x01.", JS_TAG2, g_esPlayer[target_list[iPlayer]].g_flJumpHeight);
				}
			}
		}
		default:
		{
			char sCmd[32];
			GetCmdArg(0, sCmd, sizeof sCmd);
			ReplyToCommand(client, "%s Usage: %s <-1.0: OFF|0.0: Use Cvar|1.0-99999.0: ON>", JS_TAG2, sCmd);
		}
	}

	return Plugin_Handled;
}

Action cmdJSMidairDash(int client, int args)
{
	client = iGetListenServerHost(client, g_bDedicated);
	if (!bIsValidClient(client, JS_CHECK_INDEX|JS_CHECK_INGAME|JS_CHECK_FAKECLIENT))
	{
		ReplyToCommand(client, "%s You must be in-game to use this command", JS_TAG);

		return Plugin_Handled;
	}

	if (!g_esGeneral.g_bPluginEnabled)
	{
		ReplyToCommand(client, "%s You cannot use this command right now.", JS_TAG2);

		return Plugin_Handled;
	}

	switch (args)
	{
		case 1:
		{
			g_esPlayer[client].g_iMidairDashesLimit = iClamp(GetCmdArgInt(1), -1, 99999);

			ReplyToCommand(client, "%s You now have\x05 %i\x03 midair dashes\x01.", JS_TAG2, g_esPlayer[client].g_iMidairDashesLimit);
		}
		case 2:
		{
			bool tn_is_ml;
			char target[32], target_name[32];
			int target_list[MAXPLAYERS], target_count;
			GetCmdArg(1, target, sizeof target);
			if ((target_count = ProcessTargetString(target, client, target_list, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, target_name, sizeof target_name, tn_is_ml)) <= 0)
			{
				ReplyToTargetError(client, target_count);

				return Plugin_Handled;
			}

			int iDashes = iClamp(GetCmdArgInt(2), -1, 99999);
			for (int iPlayer = 0; iPlayer < target_count; iPlayer++)
			{
				if (bIsValidClient(target_list[iPlayer]))
				{
					g_esPlayer[target_list[iPlayer]].g_iMidairDashesLimit = iDashes;

					ReplyToCommand(client, "%s You set\x05 %N's\x01 midair dash count to\x03 %i\x01.", JS_TAG2, target_list[iPlayer], g_esPlayer[target_list[iPlayer]].g_iMidairDashesLimit);
					PrintToChat(target_list[iPlayer], "%s You now have\x05 %i\x03 midair dashes\x01.", JS_TAG2, g_esPlayer[target_list[iPlayer]].g_iMidairDashesLimit);
				}
			}
		}
		default:
		{
			char sCmd[32];
			GetCmdArg(0, sCmd, sizeof sCmd);
			ReplyToCommand(client, "%s Usage: %s <-1: OFF|0: Use Cvar|1-99999: ON>", JS_TAG2, sCmd);
		}
	}

	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_esGeneral.g_bPluginEnabled || !bIsValidClient(client))
	{
		return Plugin_Continue;
	}

	if (bIsSurvivor(client, JS_CHECK_INDEX|JS_CHECK_INGAME|JS_CHECK_ALIVE))
	{
		if ((buttons & IN_JUMP) && bIsEntityGrounded(client) && !bIsSurvivorDisabled(client) && !bIsSurvivorCaught(client))
		{
			int iHop = (g_esPlayer[client].g_iBunnyHop != 0) ? g_esPlayer[client].g_iBunnyHop : g_esGeneral.g_cvJSAutoBunnyhop.IntValue;
			if (iHop == 1)
			{
				vPushPlayer(client, {-90.0, 0.0, 0.0}, ((flGetJumpHeight(client, true) + 100.0) * 2.0));

				float flBoost = g_esGeneral.g_cvJSForwardJumpBoost.FloatValue;
				if (flBoost > 0.0)
				{
					float flAngles[3];
					GetClientEyeAngles(client, flAngles);
					flAngles[0] = 0.0;

					if (g_esGeneral.g_cvJSBunnyhopMode.BoolValue)
					{
						if (buttons & IN_BACK)
						{
							flAngles[1] += 180.0;
						}

						if (buttons & IN_MOVELEFT)
						{
							flAngles[1] += 90.0;
						}

						if (buttons & IN_MOVERIGHT)
						{
							flAngles[1] += -90.0;
						}
					}

					vPushPlayer(client, flAngles, flBoost);
				}
			}
		}

		if (g_esPlayer[client].g_iMidairDashesCount > 0)
		{
			if (!(buttons & IN_JUMP) && !g_esPlayer[client].g_bReleasedJump)
			{
				g_esPlayer[client].g_bReleasedJump = true;
			}

			if (bIsEntityGrounded(client))
			{
				g_esPlayer[client].g_iMidairDashesCount = 0;
			}
		}

		if (!bIsEntityGrounded(client))
		{
			float flVelocity[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", flVelocity);
			if (flVelocity[2] < 0.0)
			{
				if (!g_esPlayer[client].g_bFallTracked)
				{
					float flOrigin[3];
					GetEntPropVector(client, Prop_Data, "m_vecOrigin", flOrigin);
					g_esPlayer[client].g_flPreFallZ = flOrigin[2];
					g_esPlayer[client].g_bFallTracked = true;

					return Plugin_Continue;
				}
			}
			else if (g_esPlayer[client].g_bFalling || g_esPlayer[client].g_bFallTracked)
			{
				g_esPlayer[client].g_bFalling = false;
				g_esPlayer[client].g_bFallTracked = false;
				g_esPlayer[client].g_flPreFallZ = 0.0;
			}
		}
		else if (g_esPlayer[client].g_bFalling || g_esPlayer[client].g_bFallTracked)
		{
			g_esPlayer[client].g_bFalling = false;
			g_esPlayer[client].g_bFallTracked = false;
			g_esPlayer[client].g_flPreFallZ = 0.0;
		}
	}

	return Plugin_Continue;
}

Action OnPlayerTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (g_esGeneral.g_bPluginEnabled && damage > 0.0 && bIsSurvivor(victim) && bIsFallProtected(victim) && g_esGeneral.g_cvJSBlockFallDamage.BoolValue)
	{
		if ((damagetype & DMG_FALL) && (bIsSafeFalling(victim) || RoundToNearest(damage) < GetEntProp(victim, Prop_Data, "m_iHealth") || !g_esPlayer[victim].g_bFatalFalling))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

Action FallSoundHook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (g_esGeneral.g_bPluginEnabled && bIsSurvivor(entity) && bIsFallProtected(entity) && g_esGeneral.g_cvJSBlockFallScream.BoolValue)
	{
		float flOrigin[3];
		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", flOrigin);
		if ((g_esPlayer[entity].g_bFallDamage && !g_esPlayer[entity].g_bFatalFalling) || (0.0 < (g_esPlayer[entity].g_flPreFallZ - flOrigin[2]) < 900.0 && !g_esPlayer[entity].g_bFalling))
		{
			if (StrEqual(sample, SOUND_NULL, false))
			{
				return Plugin_Stop;
			}
			else if (0 <= StrContains(sample, SOUND_DAMAGE, false) <= 1 || 0 <= StrContains(sample, SOUND_DAMAGE2, false) <= 1)
			{
				g_esPlayer[entity].g_bFallDamage = false;

				return Plugin_Stop;
			}
		}
	}

	return Plugin_Continue;
}

MRESReturn mreBaseEntityGetGroundEntityPre(int pThis, DHookReturn hReturn)
{
	if (bIsSurvivor(pThis) && !bIsSurvivorDisabled(pThis) && !bIsSurvivorCaught(pThis) && iGetPlayerWaterLevel(pThis) < JS_WATER_WAIST)
	{
		float flCurrentTime = GetGameTime();
		if ((g_esPlayer[pThis].g_flLastJumpTime + JS_JUMP_DASHCOOLDOWN) > flCurrentTime)
		{
			g_esPlayer[pThis].g_bReleasedJump = false;

			return MRES_Ignored;
		}

		int iLimit = (g_esPlayer[pThis].g_iMidairDashesLimit != 0) ? g_esPlayer[pThis].g_iMidairDashesLimit : g_esGeneral.g_cvJSMidairDashes.IntValue;
		if (-1 < g_esPlayer[pThis].g_iMidairDashesCount < (iLimit + 1))
		{
			g_esPlayer[pThis].g_flLastJumpTime = flCurrentTime;
			g_esPlayer[pThis].g_iMidairDashesCount++;
			hReturn.Value = pThis;

			return MRES_Override;
		}
	}

	return MRES_Ignored;
}

MRESReturn mreCheckJumpButtonPre(Address pThis, DHookReturn hReturn)
{
	vToggleDetour(g_esGeneral.g_ddBaseEntityGetGroundEntityDetour, "JSDetour_CBaseEntity::GetGroundEntity", Hook_Pre, mreBaseEntityGetGroundEntityPre, true);

	return MRES_Ignored;
}

MRESReturn mreCheckJumpButtonPost(Address pThis, DHookReturn hReturn)
{
	vToggleDetour(g_esGeneral.g_ddBaseEntityGetGroundEntityDetour, "JSDetour_CBaseEntity::GetGroundEntity", Hook_Pre, mreBaseEntityGetGroundEntityPre, false);

	return MRES_Ignored;
}

MRESReturn mreDeathFallCameraEnablePre(int pThis, DHookParam hParams)
{
	int iSurvivor = hParams.IsNull(1) ? 0 : hParams.Get(1);
	if (bIsSurvivor(iSurvivor) && bIsFallProtected(iSurvivor) && g_esGeneral.g_cvJSBlockDeathCamera.BoolValue && g_esPlayer[iSurvivor].g_bFalling)
	{
		g_esPlayer[iSurvivor].g_bFatalFalling = true;

		return MRES_Supercede;
	}

	g_esPlayer[iSurvivor].g_bFatalFalling = true;

	return MRES_Ignored;
}

MRESReturn mreDoJumpPre(Address pThis, DHookParam hParams)
{
	Address adSurvivor = LoadFromAddress((pThis + view_as<Address>(4)), NumberType_Int32);
	int iSurvivor = iGetEntityIndex(iGetRefEHandle(adSurvivor));
	if (bIsSurvivor(iSurvivor) && !g_esGeneral.g_bPatchJumpHeight)
	{
		float flHeight = flGetJumpHeight(iSurvivor);
		if (flHeight > 0.0)
		{
			g_esGeneral.g_bPatchJumpHeight = true;

			switch (!g_bSecondGame && g_esGeneral.g_iPlatformType == 2)
			{
				case true:
				{
					g_esGeneral.g_adOriginalJumpHeight[0] = LoadFromAddress(g_esGeneral.g_adDoJumpValue, NumberType_Int32);
					StoreToAddress(g_esGeneral.g_adDoJumpValue, view_as<int>(flHeight), NumberType_Int32, g_esGeneral.g_bUpdateDoJumpMemAccess);
					g_esGeneral.g_bUpdateDoJumpMemAccess = false;
				}
				case false:
				{
					g_esGeneral.g_adOriginalJumpHeight[1] = LoadFromAddress(g_esGeneral.g_adDoJumpValue, NumberType_Int32);
					g_esGeneral.g_adOriginalJumpHeight[0] = LoadFromAddress((g_esGeneral.g_adDoJumpValue + view_as<Address>(4)), NumberType_Int32);

					int iDouble[2];
					vGetDoubleFromFloat(flHeight, iDouble);
					StoreToAddress(g_esGeneral.g_adDoJumpValue, iDouble[1], NumberType_Int32, g_esGeneral.g_bUpdateDoJumpMemAccess);
					StoreToAddress((g_esGeneral.g_adDoJumpValue + view_as<Address>(4)), iDouble[0], NumberType_Int32, g_esGeneral.g_bUpdateDoJumpMemAccess);

					g_esGeneral.g_bUpdateDoJumpMemAccess = false;
				}
			}
		}
	}

	return MRES_Ignored;
}

MRESReturn mreDoJumpPost(Address pThis, DHookParam hParams)
{
	if (g_esGeneral.g_bPatchJumpHeight)
	{
		g_esGeneral.g_bPatchJumpHeight = false;

		switch (!g_bSecondGame && g_esGeneral.g_iPlatformType > 0)
		{
			case true: StoreToAddress(g_esGeneral.g_adDoJumpValue, g_esGeneral.g_adOriginalJumpHeight[0], NumberType_Int32, g_esGeneral.g_bUpdateDoJumpMemAccess);
			case false:
			{
				StoreToAddress(g_esGeneral.g_adDoJumpValue, g_esGeneral.g_adOriginalJumpHeight[1], NumberType_Int32, g_esGeneral.g_bUpdateDoJumpMemAccess);
				StoreToAddress((g_esGeneral.g_adDoJumpValue + view_as<Address>(4)), g_esGeneral.g_adOriginalJumpHeight[0], NumberType_Int32, g_esGeneral.g_bUpdateDoJumpMemAccess);
			}
		}
	}

	return MRES_Ignored;
}

MRESReturn mreFallingPre(int pThis)
{
	if (bIsSurvivor(pThis) && bIsFallProtected(pThis) && !g_esPlayer[pThis].g_bFalling)
	{
		g_esPlayer[pThis].g_bFallDamage = true;
		g_esPlayer[pThis].g_bFalling = true;

		if (g_esGeneral.g_cvJSBlockFallScream.BoolValue && !g_esGeneral.g_bPatchFallingSound)
		{
			g_esGeneral.g_bPatchFallingSound = true;
			g_esGeneral.g_mpFallScreamMute.Enable();
		}
	}

	return MRES_Ignored;
}

MRESReturn mreFallingPost(int pThis)
{
	if (g_esGeneral.g_bPatchFallingSound)
	{
		g_esGeneral.g_bPatchFallingSound = false;
		g_esGeneral.g_mpFallScreamMute.Disable();
	}

	return MRES_Ignored;
}

public void L4D_OnGameModeChange(int gamemode)
{
	int iMode = g_esGeneral.g_cvJSGameModeTypes.IntValue;
	if (iMode != 0)
	{
		g_esGeneral.g_bPluginEnabled = (gamemode != 0 && (iMode & gamemode));
		g_esGeneral.g_iCurrentMode = gamemode;
	}
}

void vCopySurvivorStats(int oldSurvivor, int newSurvivor)
{
	g_esPlayer[newSurvivor].g_bFallDamage = g_esPlayer[oldSurvivor].g_bFallDamage;
	g_esPlayer[newSurvivor].g_bFalling = g_esPlayer[oldSurvivor].g_bFalling;
	g_esPlayer[newSurvivor].g_bFallTracked = g_esPlayer[oldSurvivor].g_bFallTracked;
	g_esPlayer[newSurvivor].g_bFatalFalling = g_esPlayer[oldSurvivor].g_bFatalFalling;
	g_esPlayer[newSurvivor].g_bReleasedJump = g_esPlayer[oldSurvivor].g_bReleasedJump;
	g_esPlayer[newSurvivor].g_flJumpHeight = g_esPlayer[oldSurvivor].g_flJumpHeight;
	g_esPlayer[newSurvivor].g_flLastJumpTime = g_esPlayer[oldSurvivor].g_flLastJumpTime;
	g_esPlayer[newSurvivor].g_flPreFallZ = g_esPlayer[oldSurvivor].g_flPreFallZ;
	g_esPlayer[newSurvivor].g_iBunnyHop = g_esPlayer[oldSurvivor].g_iBunnyHop;
	g_esPlayer[newSurvivor].g_iMidairDashesLimit = g_esPlayer[oldSurvivor].g_iMidairDashesLimit;
}

void vEventHandler(Event event, const char[] name, bool dontBroadcast)
{
	if (g_esGeneral.g_bPluginEnabled)
	{
		if (StrEqual(name, "bot_player_replace"))
		{
			int iBotId = event.GetInt("bot"), iBot = GetClientOfUserId(iBotId),
				iPlayerId = event.GetInt("player"), iPlayer = GetClientOfUserId(iPlayerId);
			if (bIsValidClient(iBot) && bIsSurvivor(iPlayer))
			{
				vCopySurvivorStats(iBot, iPlayer);
				vResetSurvivorStats(iBot);
			}
		}
		else if (StrEqual(name, "player_bot_replace"))
		{
			int iPlayerId = event.GetInt("player"), iPlayer = GetClientOfUserId(iPlayerId),
				iBotId = event.GetInt("bot"), iBot = GetClientOfUserId(iBotId);
			if (bIsValidClient(iPlayer) && bIsSurvivor(iBot))
			{
				vCopySurvivorStats(iPlayer, iBot);
				vResetSurvivorStats(iPlayer);
			}
		}
		else if (StrEqual(name, "player_connect") || StrEqual(name, "player_disconnect"))
		{
			int iSurvivorId = event.GetInt("userid"), iSurvivor = GetClientOfUserId(iSurvivorId);
			g_esPlayer[iSurvivor].g_flJumpHeight = 0.0;
			g_esPlayer[iSurvivor].g_iBunnyHop = 0;
			g_esPlayer[iSurvivor].g_iMidairDashesLimit = 0;
		}
	}
}

void vGetDoubleFromFloat(float value, int save[2])
{
	int iValue = view_as<int>(value), iSign = (iValue & 0x80000000) ? 1 : 0,
		iExponent = (((iValue & 0x7F800000) >> 23) - 127) + 1023,
		iMantissa = (iValue & 0x7FFFFF) << 1;

	save[0] = iSign << 31;
	save[0] |= iExponent << 20;
	save[0] |= (iMantissa >> 4) & 0xFFFFF;
	save[1] = iMantissa << 28;
}

void vHookEvents(bool hook)
{
	static bool bHooked, bCheck[4];
	if (hook && !bHooked)
	{
		bHooked = true;

		bCheck[0] = HookEventEx("bot_player_replace", vEventHandler);
		bCheck[1] = HookEventEx("player_bot_replace", vEventHandler);
		bCheck[2] = HookEventEx("player_connect", vEventHandler, EventHookMode_Pre);
		bCheck[3] = HookEventEx("player_disconnect", vEventHandler, EventHookMode_Pre);
	}
	else if (!hook && bHooked)
	{
		bHooked = false;
		bool bPreHook[4];
		char sEvent[32];

		for (int iPos = 0; iPos < (sizeof bCheck); iPos++)
		{
			switch (iPos)
			{
				case 0: sEvent = "bot_player_replace";
				case 1: sEvent = "player_bot_replace";
				case 2: sEvent = "player_connect";
				case 3: sEvent = "player_disconnect";
			}

			if (bCheck[iPos])
			{
				bPreHook[iPos] = (2 <= iPos <= 3);
				UnhookEvent(sEvent, vEventHandler, (bPreHook[iPos] ? EventHookMode_Pre : EventHookMode_Post));
			}
		}
	}
}

void vPluginStatusCvar(ConVar convar, const char[] oldValue, const char[] newValue)
{
	vPluginStatus();
}

void vPluginStatus()
{
	bool bPluginAllowed = bIsPluginEnabled();
	if (!g_esGeneral.g_bPluginEnabled && bPluginAllowed)
	{
		vTogglePlugin(bPluginAllowed);
	}
	else if (g_esGeneral.g_bPluginEnabled && !bPluginAllowed)
	{
		vTogglePlugin(bPluginAllowed);
	}
}

void vPushPlayer(int player, float angles[3], float force)
{
	float flForward[3], flVelocity[3];
	GetAngleVectors(angles, flForward, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(flForward, flForward);
	ScaleVector(flForward, force);

	GetEntPropVector(player, Prop_Data, "m_vecAbsVelocity", flVelocity);
	flVelocity[0] += flForward[0];
	flVelocity[1] += flForward[1];
	flVelocity[2] += flForward[2];
	TeleportEntity(player, NULL_VECTOR, NULL_VECTOR, flVelocity);
}

void vResetSurvivorStats(int survivor)
{
	g_esPlayer[survivor].g_bFallDamage = false;
	g_esPlayer[survivor].g_bFalling = false;
	g_esPlayer[survivor].g_bFallTracked = false;
	g_esPlayer[survivor].g_bFatalFalling = false;
	g_esPlayer[survivor].g_bReleasedJump = false;
	g_esPlayer[survivor].g_flJumpHeight = 0.0;
	g_esPlayer[survivor].g_flLastJumpTime = 0.0;
	g_esPlayer[survivor].g_flPreFallZ = 0.0;
	g_esPlayer[survivor].g_iBunnyHop = 0;
	g_esPlayer[survivor].g_iMidairDashesLimit = 0;
}

void vSetupDetour(DynamicDetour &detourHandle, GameData dataHandle, const char[] name)
{
	detourHandle = DynamicDetour.FromConf(dataHandle, name);
	if (detourHandle == null)
	{
		LogError("%s Failed to detour: %s", JS_TAG, name);
	}
}

void vSetupPatch(MemoryPatch &patchHandle, GameData dataHandle, const char[] name)
{
	patchHandle = MemoryPatch.CreateFromConf(dataHandle, name);
	if (!patchHandle.Validate())
	{
		LogError("%s Failed to patch: %s", JS_TAG, name);
	}
}

void vToggleDetour(DynamicDetour &detourHandle, const char[] name, HookMode mode, DHookCallback callback, bool toggle)
{
	if (detourHandle == null)
	{
		return;
	}

	bool bToggle = toggle ? detourHandle.Enable(mode, callback) : detourHandle.Disable(mode, callback);
	if (!bToggle)
	{
		LogError("%s Failed to %s the %s-hook detour for the \"%s\" function.", JS_TAG, (toggle ? "enable" : "disable"), ((mode == Hook_Pre) ? "pre" : "post"), name);
	}
}

void vToggleDetours(bool toggle)
{
	vToggleDetour(g_esGeneral.g_ddCheckJumpButtonDetour, "JSDetour_CTerrorGameMovement::CheckJumpButton", Hook_Pre, mreCheckJumpButtonPre, toggle);
	vToggleDetour(g_esGeneral.g_ddCheckJumpButtonDetour, "JSDetour_CTerrorGameMovement::CheckJumpButton", Hook_Post, mreCheckJumpButtonPost, toggle);
	vToggleDetour(g_esGeneral.g_ddDeathFallCameraEnableDetour, "JSDetour_CDeathFallCamera::Enable", Hook_Pre, mreDeathFallCameraEnablePre, toggle);
	vToggleDetour(g_esGeneral.g_ddDoJumpDetour, "JSDetour_CTerrorGameMovement::DoJump", Hook_Pre, mreDoJumpPre, toggle);
	vToggleDetour(g_esGeneral.g_ddDoJumpDetour, "JSDetour_CTerrorGameMovement::DoJump", Hook_Post, mreDoJumpPost, toggle);
	vToggleDetour(g_esGeneral.g_ddFallingDetour, "JSDetour_CTerrorPlayer::OnFalling", Hook_Pre, mreFallingPre, toggle);
	vToggleDetour(g_esGeneral.g_ddFallingDetour, "JSDetour_CTerrorPlayer::OnFalling", Hook_Post, mreFallingPost, toggle);
}

void vTogglePlugin(bool toggle)
{
	g_esGeneral.g_bPluginEnabled = toggle;

	vHookEvents(toggle);
	vToggleDetours(toggle);
}

bool bIsEntityGrounded(int entity)
{
	int iGround = GetEntPropEnt(entity, Prop_Send, "m_hGroundEntity");
	return bIsValidEntity(iGround, true, -1);
}

bool bIsFallProtected(int survivor)
{
	int iDashes = (g_esPlayer[survivor].g_iMidairDashesLimit != 0) ? g_esPlayer[survivor].g_iMidairDashesLimit : g_esGeneral.g_cvJSMidairDashes.IntValue;
	return flGetJumpHeight(survivor) > 0.0 || iDashes > 0;
}

bool bIsPlayerIncapacitated(int player)
{
	return !!GetEntProp(player, Prop_Send, "m_isIncapacitated", 1);
}

bool bIsPluginEnabled()
{
	if (!g_esGeneral.g_cvJSPluginEnabled.BoolValue || g_esGeneral.g_cvJSGameMode == null)
	{
		return false;
	}

	int iMode = g_esGeneral.g_cvJSGameModeTypes.IntValue;
	if (iMode != 0)
	{
		if (!g_esGeneral.g_bMapStarted)
		{
			return false;
		}

		g_esGeneral.g_iCurrentMode = L4D_GetGameModeType();

		if (g_esGeneral.g_iCurrentMode == 0 || !(iMode & g_esGeneral.g_iCurrentMode))
		{
			return false;
		}
	}

	char sFixed[32], sGameMode[32], sGameModes[513], sList[513];
	g_esGeneral.g_cvJSGameMode.GetString(sGameMode, sizeof sGameMode);
	FormatEx(sFixed, sizeof sFixed, ",%s,", sGameMode);

	g_esGeneral.g_cvJSEnabledGameModes.GetString(sGameModes, sizeof sGameModes);
	if (sGameModes[0] != '\0')
	{
		if (sGameModes[0] != '\0')
		{
			FormatEx(sList, sizeof sList, ",%s,", sGameModes);
		}

		if (sList[0] != '\0' && StrContains(sList, sFixed, false) == -1)
		{
			return false;
		}
	}

	g_esGeneral.g_cvJSDisabledGameModes.GetString(sGameModes, sizeof sGameModes);
	if (sGameModes[0] != '\0')
	{
		if (sGameModes[0] != '\0')
		{
			FormatEx(sList, sizeof sList, ",%s,", sGameModes);
		}

		if (sList[0] != '\0' && StrContains(sList, sFixed, false) != -1)
		{
			return false;
		}
	}

	return true;
}

bool bIsSafeFalling(int survivor)
{
	if (g_esPlayer[survivor].g_bFalling)
	{
		float flOrigin[3];
		GetEntPropVector(survivor, Prop_Data, "m_vecOrigin", flOrigin);
		if (0.0 < (g_esPlayer[survivor].g_flPreFallZ - flOrigin[2]) < 900.0)
		{
			g_esPlayer[survivor].g_bFalling = false;
			g_esPlayer[survivor].g_flPreFallZ = 0.0;

			return true;
		}

		g_esPlayer[survivor].g_bFalling = false;
		g_esPlayer[survivor].g_flPreFallZ = 0.0;
	}

	return false;
}

bool bIsSurvivor(int survivor, int flags = JS_CHECK_INDEX|JS_CHECK_INGAME|JS_CHECK_ALIVE)
{
	return bIsValidClient(survivor, flags) && GetClientTeam(survivor) == 2;
}

bool bIsSurvivorCaught(int survivor)
{
	int iSpecial = GetEntPropEnt(survivor, Prop_Send, "m_pounceAttacker");
	iSpecial = (iSpecial <= 0) ? GetEntPropEnt(survivor, Prop_Send, "m_tongueOwner") : iSpecial;
	if (g_bSecondGame)
	{
		iSpecial = (iSpecial <= 0) ? GetEntPropEnt(survivor, Prop_Send, "m_pummelAttacker") : iSpecial;
		iSpecial = (iSpecial <= 0) ? GetEntPropEnt(survivor, Prop_Send, "m_carryAttacker") : iSpecial;
		iSpecial = (iSpecial <= 0) ? GetEntPropEnt(survivor, Prop_Send, "m_jockeyAttacker") : iSpecial;
	}

	return iSpecial > 0;
}

bool bIsSurvivorDisabled(int survivor)
{
	return bIsSurvivorHanging(survivor) || bIsPlayerIncapacitated(survivor);
}

bool bIsSurvivorHanging(int survivor)
{
	return !!GetEntProp(survivor, Prop_Send, "m_isHangingFromLedge") || !!GetEntProp(survivor, Prop_Send, "m_isFallingFromLedge");
}

bool bIsValidClient(int player, int flags = JS_CHECK_INDEX|JS_CHECK_INGAME)
{
	if (((flags & JS_CHECK_INDEX) && (player <= 0 || player > MaxClients)) || ((flags & JS_CHECK_CONNECTED) && !IsClientConnected(player))
		|| ((flags & JS_CHECK_INGAME) && !IsClientInGame(player)) || ((flags & JS_CHECK_ALIVE) && !IsPlayerAlive(player))
		|| ((flags & JS_CHECK_INKICKQUEUE) && IsClientInKickQueue(player)) || ((flags & JS_CHECK_FAKECLIENT) && IsFakeClient(player)))
	{
		return false;
	}

	return true;
}

bool bIsValidEntity(int entity, bool override = false, int start = 0)
{
	int iIndex = override ? start : MaxClients;
	return entity > iIndex && IsValidEntity(entity);
}

float flClamp(float value, float min, float max)
{
	if (value < min)
	{
		return min;
	}
	else if (value > max)
	{
		return max;
	}

	return value;
}

float flGetJumpHeight(int survivor, bool useDefault = false)
{
	float flHeight = (g_esPlayer[survivor].g_flJumpHeight != 0.0) ? g_esPlayer[survivor].g_flJumpHeight : g_esGeneral.g_cvJSJumpHeight.FloatValue;
	return (flHeight == 0.0 && useDefault) ? JS_JUMP_DEFAULTHEIGHT : flHeight;
}

int iClamp(int value, int min, int max)
{
	if (value < min)
	{
		return min;
	}
	else if (value > max)
	{
		return max;
	}

	return value;
}

int iGetEntityIndex(int ref)
{
	return (ref & ENT_ENTRY_MASK);
}

int iGetListenServerHost(int client, bool dedicated)
{
	if (client == 0 && !dedicated)
	{
		int iManager = FindEntityByClassname(-1, "terror_player_manager");
		if (bIsValidEntity(iManager))
		{
			int iHostOffset = FindSendPropInfo("CTerrorPlayerResource", "m_listenServerHost");
			if (iHostOffset != -1)
			{
				bool bHost[MAXPLAYERS + 1];
				GetEntDataArray(iManager, iHostOffset, bHost, (MAXPLAYERS + 1), 1);
				for (int iPlayer = 1; iPlayer < sizeof bHost; iPlayer++)
				{
					if (bHost[iPlayer])
					{
						return iPlayer;
					}
				}
			}
		}
	}

	return client;
}

int iGetPlayerWaterLevel(int client)
{
	return GetEntProp(client, Prop_Send, "m_nWaterLevel");
}

int iGetRefEHandle(Address entityHandle)
{
	if (!entityHandle)
	{
		return INVALID_EHANDLE_INDEX;
	}

	Address adRefHandle = SDKCall(g_esGeneral.g_hSDKGetRefEHandle, entityHandle);
	return LoadFromAddress(adRefHandle, NumberType_Int32);
}