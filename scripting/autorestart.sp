#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "MrSquid"
#define PLUGIN_VERSION "1.0.1"

#define STATUS_DISABLED 0
#define STATUS_AUTO 1
#define STATUS_MANUAL 2

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Auto Restart", 
	author = PLUGIN_AUTHOR, 
	description = "Automatically restarts server without losing player locations", 
	version = PLUGIN_VERSION, 
	url = ""
};


char lmapf[PLATFORM_MAX_PATH];
char lmapstr[32];
Database db;
bool restore;
bool fmap = true;
ConVar restartTime;
int uptime;

int saveStatus[MAXPLAYERS];
char saveLoaded[MAXPLAYERS][32];
int saveLoadIndex;
bool saveRestoring[MAXPLAYERS];
int saveTeam[MAXPLAYERS];
int saveClass[MAXPLAYERS];
float savePos[MAXPLAYERS][3];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	restartTime = CreateConVar("sm_autorestart_time", "0", "Minutes of uptime before automatic restart", 0, true, 0.0, false, 0.0);
	
	AutoExecConfig(true, "autorestart", "sourcemod");
	
	RegAdminCmd("sm_autorestart", Command_autorestart, ADMFLAG_RCON, "auto restart server");
	RegAdminCmd("sm_autorestartmap", Command_autorestartmap, ADMFLAG_CHANGEMAP, "auto restart map");
	
	RegConsoleCmd("sm_autorestore", Command_autorestore, "restore your position");
	
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	
	BuildPath(Path_SM, lmapf, sizeof(lmapf), "data/autorestart_lmap.txt");
	
	if (FileExists(lmapf))
	{
		char cmap[32];
		GetCurrentMap(cmap, sizeof(cmap));
		File readlmap = OpenFile(lmapf, "r");
		readlmap.ReadString(lmapstr, sizeof(lmapstr), -1);
		delete readlmap;
		
		
		if (!StrEqual(lmapstr, ""))
		{
			restore = true;
			if (!StrEqual(cmap, lmapstr))
			{
				ServerCommand("changelevel %s", lmapstr);
			}
		}
	}
	
	File lmap = OpenFile(lmapf, "w");
	delete lmap;
	
	char error[128];
	KeyValues kv = CreateKeyValues("autorestart", "driver", "sqlite");
	KvSetString(kv, "database", "autorestart");
	db = SQL_ConnectCustom(kv, error, sizeof(error), true);
	
	CreateTimer(60.0, Timer_checkTime, _, TIMER_REPEAT);
}

public Action Timer_checkTime(Handle timer, int index)
{
	uptime++;
	if (uptime >= GetConVarInt(restartTime) && GetConVarInt(restartTime) != 0)
	{
		preRestart();
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (restore == true)
	{
		DB_LoadPlayer(client);
	}
}

public void OnClientDisconnect(int client)
{
	saveStatus[client] = STATUS_DISABLED;
}

public void OnMapStart()
{
	if (fmap)
	{
		fmap = false;
		return;
	}
	
	char cmap[32];
	GetCurrentMap(cmap, sizeof(cmap));
	if (!StrEqual(cmap, lmapstr))
	{
		restore = false;
	}
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (saveRestoring[client] == true)
	{
		saveRestoring[client] = false;
		PrintCenterText(client, "Restoring your position...");
		CreateTimer(5.0, Timer_tpDelay, client);
	}
	
	if (saveStatus[client] == STATUS_AUTO && restore == true)
	{
		PrintCenterText(client, "Your previous position will be restored shortly. If the restore fails, use /autorestore");
		PrintToChat(client, "Your previous position will be restored shortly. If the restore fails, use /autorestore");
		CreateTimer(15.0, Timer_restore, client);
	}
}

public Action Timer_tpDelay(Handle timer, int client)
{
	if (GetClientTeam(client) == saveTeam[client] && TF2_GetPlayerClass(client) == view_as<TFClassType>(saveClass[client]))
	{
		TeleportEntity(client, savePos[client], NULL_VECTOR, NULL_VECTOR);
	}
}

public Action Timer_restore(Handle timer, int index)
{
	TF2_SetPlayerClass(index, view_as<TFClassType>(saveClass[index]), true, true);
	if (GetClientTeam(index) == saveTeam[index])
	{
		ForcePlayerSuicide(index);
	} else {
		ChangeClientTeam(index, saveTeam[index]);
	}
	saveRestoring[index] = true;
	saveStatus[index] = STATUS_MANUAL;
}

public Action Command_autorestart(int client, int args)
{
	preRestart();
	return Plugin_Handled;
}

public Action Command_autorestartmap(int client, int args)
{
	DB_Nuke();
	
	ReplyToCommand(client, "[SM] Restarting map...");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			DB_SavePlayer(i);
		}
	}
	
	fmap = true;
	restore = true;
	for (int i = 0; i < MAXPLAYERS; i++)
	{
		strcopy(saveLoaded[i], 32, "");
	}
	saveLoadIndex = 0;
	
	CreateTimer(1.0, Timer_restartMap);
	return Plugin_Handled;
}

public Action Command_autorestore(int client, int args)
{
	if (saveStatus[client] != STATUS_DISABLED && restore == true)
	{
		CreateTimer(1.0, Timer_restore, client);
	} else {
		ReplyToCommand(client, "error restoring position");
	}
	return Plugin_Handled;
}

void preRestart()
{
	DB_Nuke();
	
	CreateTimer(1.0, Timer_restartMessage, _, TIMER_REPEAT);
	PrintToChatAll("The server is restarting. Your position has been saved, please stand by.");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			DB_SavePlayer(i);
		}
	}
	
	CreateTimer(10.0, Timer_restartDelay);
}

public Action Timer_restartMessage(Handle timer, int index)
{
	PrintCenterTextAll("The server is restarting. Your position has been saved, please stand by.");
}

public Action Timer_restartDelay(Handle timer, int index)
{
	restart();
}

public Action Timer_restartMap(Handle timer, int index)
{
	char cmap[32];
	GetCurrentMap(cmap, sizeof(cmap));
	ServerCommand("changelevel %s", cmap);
}

void restart()
{
	File lmap = OpenFile(lmapf, "w");
	char cmap[32];
	GetCurrentMap(cmap, sizeof(cmap));
	lmap.WriteString(cmap, true);
	delete lmap;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			KickClient(i, "The server is restarting. Please reconnect to recover your previous location");
		}
	}
	ServerCommand("_restart");
}

void DB_SavePlayer(int client)
{
	if (GetClientTeam(client) == 1)
	{
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
	
	float pos[3];
	GetClientAbsOrigin(client, pos);
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO players (steamid, team, class, x, y, z) VALUES ('%s', '%i', '%i', '%f', '%f', '%f');", sAuth, GetClientTeam(client), TF2_GetPlayerClass(client), pos[0], pos[1], pos[2]);
	
	db.Query(CB_DB_SavePlayer, sQuery, client);
}

void CB_DB_SavePlayer(Database rDB, DBResultSet rs, char[] error, int client)
{
	delete rs;
}


void DB_LoadPlayer(int client)
{
	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT team, class, x, y, z FROM players WHERE steamid = '%s';", sAuth);
	
	db.Query(CB_DB_LoadPlayer, sQuery, client);
}

void CB_DB_LoadPlayer(Database rDB, DBResultSet rs, char[] error, int client)
{
	if (!rs.FetchRow())
	{
		delete rs;
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
	
	bool found = false;
	for (int i = 0; i < MAXPLAYERS; i++)
	{
		if (StrEqual(saveLoaded[i], sAuth))
		{
			saveStatus[client] = STATUS_MANUAL;
			found = true;
		}
	}
	if (!found) {
		saveStatus[client] = STATUS_AUTO;
		strcopy(saveLoaded[saveLoadIndex], 32, sAuth);
	}
	saveTeam[client] = rs.FetchInt(0);
	saveClass[client] = rs.FetchInt(1);
	savePos[client][0] = rs.FetchFloat(2);
	savePos[client][1] = rs.FetchFloat(3);
	savePos[client][2] = rs.FetchFloat(4);
	delete rs;
}

void DB_Nuke()
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM players;");
	
	db.Query(CB_DB_Nuke, sQuery, 0);
}

void CB_DB_Nuke(Database rDB, DBResultSet rs, char[] error, int client)
{
	delete rs;
} 