#pragma semicolon 1
#pragma newdecls required //強制1.7以後的新語法
#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <multicolors>

#define SCORE_DELAY_EMPTY_SERVER 3.0
#define ZOMBIECLASS_SMOKER 1
#define ZOMBIECLASS_BOOMER 2
#define ZOMBIECLASS_HUNTER 3
#define ZOMBIECLASS_SPITTER 4
#define ZOMBIECLASS_JOCKEY 5
#define ZOMBIECLASS_CHARGER 6
#define ZOMBIECLASS_TANK 8
#define MaxHealth 100
#define VOTE_NO "no"
#define VOTE_YES "yes"
#define MENU_TIME 20
#define L4D_TEAM_SPECTATE	1
#define MAX_CAMPAIGN_LIMIT 64
#define FORCESPECTATE_PENALTY 60
#define VOTEDELAY_TIME 5
#define READY_RESTART_MAP_DELAY 2

int Votey = 0;
int Voten = 0;
bool game_l4d2 = false;
int kickplayer_userid;
char kickplayer_name[MAX_NAME_LENGTH];
char kickplayer_SteamId[MAX_NAME_LENGTH];
char votesmaps[MAX_NAME_LENGTH];
char votesmapsname[MAX_NAME_LENGTH];
ConVar g_Cvar_Limits;
ConVar VotensHpED;
ConVar VotensAlltalkED;
ConVar VotensAlltalk2ED;
ConVar VotensRestartmapED;
ConVar VotensMapED;
ConVar VotensMap2ED;
ConVar VotensED;
ConVar VotensKickED;
ConVar VotensForceSpectateED;
ConVar g_hCvarPlayerLimit;
ConVar g_hKickImmueAccess;
int g_iCvarPlayerLimit;
Handle g_hVoteMenu = null;
float lastDisconnectTime;
bool ClientVoteMenu[MAXPLAYERS + 1];
int g_iCount;
char g_sMapinfo[MAX_CAMPAIGN_LIMIT][MAX_NAME_LENGTH];
char g_sMapname[MAX_CAMPAIGN_LIMIT][MAX_NAME_LENGTH];
float g_fLimit;
bool g_bEnable, VotensHpE_D, VotensAlltalkE_D, VotensAlltalk2E_D, VotensRestartmapE_D, 
	VotensMapE_D, VotensMap2E_D, g_bVotensKickED, g_bVotensForceSpectateED;
char g_sKickImmueAccesslvl[16];

enum voteType
{
	None,
	hp,
	alltalk,
	alltalk2,
	restartmap,
	kick,
	map,
	map2,
	forcespectate,
}
voteType g_voteType = None;

int forcespectateid;
char forcespectateplayername[MAX_NAME_LENGTH];
static	int g_iSpectatePenaltyCounter[MAXPLAYERS + 1];
static int g_votedelay;
int MapRestartDelay;
Handle MapCountdownTimer;
bool isMapRestartPending = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	EngineVersion test = GetEngineVersion();
	
	if( test == Engine_Left4Dead ) game_l4d2 = false;
	else if( test == Engine_Left4Dead2 ) game_l4d2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success; 
}

public Plugin myinfo =
{
	name = "L4D2 Vote Menu",
	author = "HarryPotter",
	description = "Votes Commands",
	version = "6.1",
	url = "http://steamcommunity.com/profiles/76561198026784913"
};

public void OnPluginStart()
{
	RegConsoleCmd("voteshp", Command_VoteHp);
	RegConsoleCmd("votesalltalk", Command_VoteAlltalk);
	RegConsoleCmd("votesalltalk2", Command_VoteAlltalk2);
	RegConsoleCmd("votesrestartmap", Command_VoteRestartmap);
	RegConsoleCmd("votesmapsmenu", Command_VotemapsMenu);
	RegConsoleCmd("votesmaps2menu", Command_Votemaps2Menu);
	RegConsoleCmd("voteskick", Command_VotesKick);
	RegConsoleCmd("sm_votes", Command_Votes, "open vote meun");
	RegConsoleCmd("sm_callvote", Command_Votes, "open vote meun");
	RegConsoleCmd("sm_callvotes", Command_Votes, "open vote meun");
	RegConsoleCmd("votesforcespectate", Command_Votesforcespectate);
	RegAdminCmd("sm_restartmap", CommandRestartMap, ADMFLAG_CHANGEMAP, "sm_restartmap - changelevels to the current map");
	RegAdminCmd("sm_rs", CommandRestartMap, ADMFLAG_CHANGEMAP, "sm_restartmap - changelevels to the current map");

	g_Cvar_Limits = CreateConVar("sm_votes_s", "0.60", "pass vote percentage.", 0, true, 0.05, true, 1.0);
	VotensHpED = CreateConVar("l4d_VotenshpED", "1", "If 1, Enable Give HP Vote.", FCVAR_NOTIFY);
	VotensAlltalkED = CreateConVar("l4d_VotensalltalkED", "1", "If 1, Enable All Talk On Vote.", FCVAR_NOTIFY);
	VotensAlltalk2ED = CreateConVar("l4d_Votensalltalk2ED", "1", "If 1, Enable All Talk Off Vote.", FCVAR_NOTIFY);
	VotensRestartmapED = CreateConVar("l4d_VotensrestartmapED", "1", "If 1, Enable Restart Current Map Vote.", FCVAR_NOTIFY);
	VotensMapED = CreateConVar("l4d_VotensmapED", "1", "If 1, Enable Change Valve Map Vote.", FCVAR_NOTIFY);
	VotensMap2ED = CreateConVar("l4d_Votensmap2ED", "1", "If 1, Enable Change Custom Map Vote.", FCVAR_NOTIFY);
	VotensED = CreateConVar("l4d_Votens", "1", "0=Off, 1=On this plugin", FCVAR_NOTIFY);
	VotensKickED = CreateConVar("l4d_VotesKickED", "1", "If 1, Enable Kick Player Vote.", FCVAR_NOTIFY);
	VotensForceSpectateED = CreateConVar("l4d_VotesForceSpectateED", "1", "If 1, Enable ForceSpectate Player Vote.", FCVAR_NOTIFY);
	g_hCvarPlayerLimit = CreateConVar("sm_vote_player_limit", "1", "Minimum # of players in game to start the vote", FCVAR_NOTIFY);
	g_hKickImmueAccess = CreateConVar("l4d_VotesKick_immue_access_flag", "z", "Players with these flags have kick immune. (Empty = Everyone, -1: Nobody)", FCVAR_NOTIFY);
	
	HookEvent("round_start", event_Round_Start);

	GetCvars();
	g_Cvar_Limits.AddChangeHook(ConVarChanged_Cvars);
	VotensHpED.AddChangeHook(ConVarChanged_Cvars);
	VotensAlltalkED.AddChangeHook(ConVarChanged_Cvars);
	VotensAlltalk2ED.AddChangeHook(ConVarChanged_Cvars);
	VotensRestartmapED.AddChangeHook(ConVarChanged_Cvars);
	VotensMapED.AddChangeHook(ConVarChanged_Cvars);
	VotensMap2ED.AddChangeHook(ConVarChanged_Cvars);
	VotensED.AddChangeHook(ConVarChanged_Cvars);
	VotensKickED.AddChangeHook(ConVarChanged_Cvars);
	VotensForceSpectateED.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarPlayerLimit.AddChangeHook(ConVarChanged_Cvars);
	g_hKickImmueAccess.AddChangeHook(ConVarChanged_Cvars);

	AutoExecConfig(true, "l4d_votes_5");
}

public void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_fLimit = g_Cvar_Limits.FloatValue;
	g_iCvarPlayerLimit = g_hCvarPlayerLimit.IntValue;
	VotensHpE_D = VotensHpED.BoolValue;
	VotensAlltalkE_D = VotensAlltalkED.BoolValue;
	VotensAlltalk2E_D = VotensAlltalk2ED.BoolValue;
	VotensRestartmapE_D = VotensRestartmapED.BoolValue;		
	VotensMapE_D = VotensMapED.BoolValue;
	VotensMap2E_D = VotensMap2ED.BoolValue;
	g_bVotensKickED = VotensKickED.BoolValue;
	g_bVotensForceSpectateED = VotensForceSpectateED.BoolValue;
	g_bEnable = VotensED.BoolValue;
	g_hKickImmueAccess.GetString(g_sKickImmueAccesslvl,sizeof(g_sKickImmueAccesslvl));
}
public Action CommandRestartMap(int client, int args)
{	
	if(!isMapRestartPending)
	{
		CPrintToChatAll("[{olive}Orz{default}] 地图将在 {green}%d{default} 秒后重启。Map restart in {green}%d{default} seconds.", READY_RESTART_MAP_DELAY+1, READY_RESTART_MAP_DELAY+1);
		RestartMapDelayed();
	}
	return Plugin_Handled;
}

void RestartMapDelayed()
{
	if (MapCountdownTimer == INVALID_HANDLE)
	{
		PrintHintTextToAll("Get Ready!\nMap restart in: %d",READY_RESTART_MAP_DELAY+1);
		isMapRestartPending = true;
		MapRestartDelay = READY_RESTART_MAP_DELAY;
		MapCountdownTimer = CreateTimer(1.0, timerRestartMap, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action timerRestartMap(Handle timer)
{
	if (MapRestartDelay == 0)
	{
		MapCountdownTimer = INVALID_HANDLE;
		RestartMapNow();
		return Plugin_Stop;
	}
	else
	{
		PrintHintTextToAll("Get Ready!\nMap restart in: %d", MapRestartDelay);
		EmitSoundToAll("buttons/blip1.wav", _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		MapRestartDelay--;
	}
	return Plugin_Continue;
}

void RestartMapNow() 
{
	isMapRestartPending = false;
	char currentMap[256];
	GetCurrentMap(currentMap, 256);
	ServerCommand("changelevel %s", currentMap);
}

public void event_Round_Start(Event event, const char[] name, bool dontBroadcast) 
{
	for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = false; 
	
}

public void OnClientPutInServer(int client)
{
	g_iSpectatePenaltyCounter[client] = FORCESPECTATE_PENALTY;
}

public void OnMapStart()
{
	isMapRestartPending = false;
	MapCountdownTimer = INVALID_HANDLE;
	
	ParseCampaigns();
	
	g_votedelay = 15;
	CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT| TIMER_FLAG_NO_MAPCHANGE);

	
	for(int i = 1; i <= MaxClients; i++)
	{	
		g_iSpectatePenaltyCounter[i] = FORCESPECTATE_PENALTY;
	}
	PrecacheSound("ui/menu_enter05.wav");
	PrecacheSound("ui/beep_synthtone01.wav");
	PrecacheSound("ui/beep_error01.wav");
	PrecacheSound("buttons/blip1.wav");
	
	VoteMenuClose();
}

public Action Command_Votes(int client, int args) 
{ 
	if (client == 0)
	{
		PrintToServer("[votes] sm_votes cannot be used by server.");
		return Plugin_Handled;
	}
	if(GetClientTeam(client) == 1)
	{
		ReplyToCommand(client, "[votes] 旁观无权发起投票. Spectators can not call a vote.");	
		return Plugin_Handled;
	}

	ClientVoteMenu[client] = true;
	if(g_bEnable == true)
	{	
		Handle menu = CreatePanel();
		SetPanelTitle(menu, "菜单 menu");
		if (VotensHpE_D == false)
		{
			DrawPanelItem(menu, "回血(关闭中) Give Hp(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "回血 Give hp");
		}
		if (VotensAlltalkE_D == false)
		{ 
			DrawPanelItem(menu, "全语音(关闭中) Turn on AllTalk(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "全语音 All talk");
		}
		if (VotensAlltalk2E_D == false)
		{
			DrawPanelItem(menu, "关闭全语音(关闭中) Turn off AllTalk(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "关闭全语音 Turn off AllTalk");
		}
		if (VotensRestartmapE_D == false)
		{
			DrawPanelItem(menu, "重新目前地图(关闭中) Stop restartmap(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "重启目前地图 Restartmap");
		}
		if (VotensMapE_D == false)
		{
			DrawPanelItem(menu, "换图(关闭中) Change Maps(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "换图 Change Maps");
		}

		if (VotensMap2E_D == false)
		{
			DrawPanelItem(menu, "换第三方图(关闭中) Change addon maps (Disable)");
		}
		else
		{
			DrawPanelItem(menu, "换第三方图 Change addon maps");
		}

		if (g_bVotensKickED == false)
		{
			DrawPanelItem(menu, "踢出玩家(关闭中) Change addon map(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "踢出玩家 Kick Player");
		}

		if (g_bVotensForceSpectateED == false)
		{
			DrawPanelItem(menu, "强制玩家旁观(关闭中) Forcespectate Player(Disable)");
		}
		else
		{
			DrawPanelItem(menu, "强制玩家旁观 Forcespectate Player");
		}
		DrawPanelText(menu, " \n");
		DrawPanelText(menu, "0. Exit");
		SendPanelToClient(menu, client, Votes_Menu, MENU_TIME);
		return Plugin_Handled;
	}
	else
	{
		CPrintToChat(client, "[{olive}Orz{default}] 投票菜单插件已关闭!");
	}
	
	return Plugin_Stop;
}
public int Votes_Menu(Menu menu, MenuAction action, int client, int itemNum)
{
	if ( action == MenuAction_Select ) 
	{ 
		switch (itemNum)
		{
			case 1: 
			{
				if (VotensHpE_D == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用回血");
				}
				else if (VotensHpE_D == true)
				{
					FakeClientCommand(client,"voteshp");
				}
			}
			case 2: 
			{
				if (VotensAlltalkE_D == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用全语音");
				}
				else if (VotensAlltalkE_D == true)
				{
					FakeClientCommand(client,"votesalltalk");
				}
			}
			case 3: 
			{
				if (VotensAlltalk2E_D == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用关闭全语音");
				}
				else if (VotensAlltalk2E_D == true)
				{
					FakeClientCommand(client,"votesalltalk2");
				}
			}
			case 4: 
			{
				if (VotensRestartmapE_D == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用重新目前地图");
				}
				else if (VotensRestartmapE_D == true)
				{
					FakeClientCommand(client,"votesrestartmap");
				}
			}
			case 5: 
			{
				if (VotensMapE_D == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用换图");
				}
				else if (VotensMapE_D == true)
				{
					FakeClientCommand(client,"votesmapsmenu");
				}
			}
			case 6: 
			{
				if (VotensMap2E_D == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用换第三方图");
				}
				else if (VotensMap2E_D == true)
				{
					FakeClientCommand(client,"votesmaps2menu");
				}
			}
			case 7: 
			{
				if (g_bVotensKickED == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用踢人");
				}
				else if (g_bVotensKickED == true)
				{
					FakeClientCommand(client,"voteskick");
				}
			}
			case 8: 
			{
				if (g_bVotensForceSpectateED == false)
				{
					FakeClientCommand(client,"sm_votes");
					CPrintToChat(client, "[{olive}Orz{default}] 禁用强制旁观玩家");
				}
				else if (g_bVotensForceSpectateED == true)
				{
					FakeClientCommand(client,"votesforcespectate");
				}
			}
		}
	}
	else if ( action == MenuAction_Cancel)
	{
		ClientVoteMenu[client] = false;
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_VoteHp(int client, int args)
{
	if(g_bEnable == true 
	&& VotensHpE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}	
		if(CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票: {blue}回血{default}。{olive}%N {default}starts a vote: {blue}give hp{default})",client,client);
			
			
			for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = true;
			
			g_voteType = view_as<voteType>(hp);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2,SteamId, sizeof(SteamId));
			LogMessage("%N(%s) starts a vote: give hp!",  client, SteamId);//記錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "Sure to give hp?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		
			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);	
			
			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}
		
		return Plugin_Handled;	
	}
	else if(g_bEnable == false || VotensHpE_D == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 本投票被禁止。This vote is prohibited.");
	}
	return Plugin_Handled;
}
public Action Command_VoteAlltalk(int client, int args)
{
	if(g_bEnable == true 
	&& VotensAlltalkE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		if(CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票：{blue}打开全语音{default}。{olive}%N {default}starts a vote: {blue}turn on alltalk{default})", client, client);
			
			for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = true;
			
			g_voteType = view_as<voteType>(alltalk);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) starts a vote: turn on Alltalk!",  client, SteamId);//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "sure to turn on alltalk?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		
			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);
			
			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}
		
		return Plugin_Handled;	
	}
	else if(g_bEnable == false || VotensAlltalkE_D == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 本投票被禁止。This vote is prohibited.");
	}
	return Plugin_Handled;
}
public Action Command_VoteAlltalk2(int client, int args)
{
	if(g_bEnable == true 
	&& VotensAlltalk2E_D == true )
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}	
		
		if(CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票：{blue}关闭全语音{default}。{olive}%N {default}starts a vote: {blue}turn off alltalk{default}.", client, client);
			
			for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = true;
			
			g_voteType = view_as<voteType>(alltalk2);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) starts a vote: turn off Alltalk!",  client, SteamId);//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "sure to trun off alltalk?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		
			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);
			
			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}
		
		return Plugin_Handled;	
	}
	else if(g_bEnable == false || VotensAlltalk2E_D == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 本投票被禁止。This vote is prohibited.");
	}
	return Plugin_Handled;
}
public Action Command_VoteRestartmap(int client, int args)
{
	if(g_bEnable == true 
	&& VotensRestartmapE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}	

		if(CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票：{blue}重启地图{default}。{olive}%N {default}starts a vote: {blue}restartmap{default}.", client, client);
			
			for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = true;
			
			g_voteType = view_as<voteType>(restartmap);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) starts a vote: restartmap!",  client, SteamId);//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "sure to restartmap?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		
			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);
			
			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}
		
		return Plugin_Handled;	
	}
	else if(g_bEnable == false || VotensRestartmapE_D == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 本投票被禁止。This vote is prohibited.");
	}
	return Plugin_Handled;
}
public Action Command_VotesKick(int client, int args)
{
	if(client==0) return Plugin_Handled;		
	if(g_bEnable == true && g_bVotensKickED == true)
	{
		CreateVoteKickMenu(client);	
	}	
	else if(g_bEnable == false || g_bVotensKickED == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 踢出玩家操作被禁止。Kick Player is prohibited.");
	}	
	return Plugin_Handled;
}

void CreateVoteKickMenu(int client)
{	
	int team = GetClientTeam(client);
	Handle menu = CreateMenu(Menu_VotesKick);		
	char name[MAX_NAME_LENGTH];
	char playerid[32];
	SetMenuTitle(menu, "plz choose player u want to kick");
	for(int i = 1;i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && (GetClientTeam(i) == team || GetClientTeam(i) == 1))
		{
			Format(playerid,sizeof(playerid),"%i",GetClientUserId(i));
			if(GetClientName(i,name,sizeof(name)))
			{
				AddMenuItem(menu, playerid, name);						
			}
		}		
	}
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME);	
}
public int Menu_VotesKick(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32], name[32];
		GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
		int player = StringToInt(info);
		player = GetClientOfUserId(player);
		if(player && IsClientInGame(player))
		{
			if (player == param1)
			{
				CPrintToChat(param1, "[{olive}Orz{default}] 踢出自己？请重选。Kick yourself? choose again.");
				CreateVoteKickMenu(param1);
				return 0;
			}
			
			if(HasAccess(player, g_sKickImmueAccesslvl))
			{
				CPrintToChat(param1, "[{olive}Orz{default}] 该目标免疫被踢，请重选！Target has kick immue, choose again!");
				CPrintToChat(player, "[{olive}Orz{default}] {olive}%N{default} 尝试踢出你，但你免疫被踢。{olive}%N{default} tries to kick you, but you have kick immue.", param1, param1);
				CreateVoteKickMenu(param1);
			}
			else
			{
				kickplayer_userid = GetClientUserId(player);
				kickplayer_name = name;
				GetClientAuthId(player, AuthId_Steam2,kickplayer_SteamId, sizeof(kickplayer_SteamId));
				DisplayVoteKickMenu(param1);
			}
		}	
		else
		{
			CPrintToChat(param1, "[{olive}Orz{default}] 目标不在游戏中，请重选。Target is not in game, choose again.");
			CreateVoteKickMenu(param1);
		}	
	}
	else if ( action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack) {
			FakeClientCommand(param1,"votes");
		}
		else
			ClientVoteMenu[param1] = false;
	}
	else if ( action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DisplayVoteKickMenu(int client)
{
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	if(CanStartVotes(client))
	{
		char SteamId[35];
		GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
		LogMessage("%N(%s) starts a vote: kick %s(%s)",  client, SteamId, kickplayer_name, kickplayer_SteamId);//紀錄在log文件
		CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票：{blue}踢出 %s{default}。{olive} %N {default}starts a votes: {blue}kick %s{default}.", client, kickplayer_name, client, kickplayer_name);
		
		for(int i=1; i <= MaxClients; i++) 
			ClientVoteMenu[i] = true;
		
		g_voteType = view_as<voteType>(kick);
		
		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL); 
		SetMenuTitle(g_hVoteMenu, "kick player %s ?",kickplayer_name);
		AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
		AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		SetMenuExitButton(g_hVoteMenu, false);
		VoteMenuToAll(g_hVoteMenu, 20);
		
		EmitSoundToAll("ui/beep_synthtone01.wav");
	}
	else
	{
		return;
	}
}

public Action Command_VotemapsMenu(int client, int args)
{
	if(g_bEnable == true && VotensMapE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		Handle menu = CreateMenu(MapMenuHandler);
		
		SetMenuTitle(menu, "Plz choose maps");
		if(game_l4d2)
		{
			AddMenuItem(menu, "c1m1_hotel", "死亡中心 C1");
			AddMenuItem(menu, "c2m1_highway", "黑色嘉年华 C2");
			AddMenuItem(menu, "c3m1_plankcountry", "沼泽激战 C3");
			AddMenuItem(menu, "c4m1_milltown_a", "暴风骤雨 C4");
			AddMenuItem(menu, "c5m1_waterfront", "教区 C5");
			AddMenuItem(menu, "c6m1_riverbank", "短暂时刻 C6");
			AddMenuItem(menu, "c7m1_docks", "牺牲 C7");
			AddMenuItem(menu, "c8m1_apartment", "毫不留情 C8");
			AddMenuItem(menu, "c9m1_alleys", "坠机险途 C9");
			AddMenuItem(menu, "c10m1_caves", "死亡丧钟 C10");
			AddMenuItem(menu, "c11m1_greenhouse", "寂静时分 C11");
			AddMenuItem(menu, "c12m1_hilltop", "血腥收获 C12");
			AddMenuItem(menu, "c13m1_alpinecreek", "刺骨寒溪 C13");
			AddMenuItem(menu, "c14m1_junkyard", "最后一刻 C14");
		}
		else
		{
			AddMenuItem(menu, "l4d_vs_hospital01_apartment", "毫不留情 No Mercy");
			AddMenuItem(menu, "l4d_garage01_alleys", "坠机险途 Crash Course");
			AddMenuItem(menu, "l4d_vs_smalltown01_caves", "死亡丧钟 Death Toll");
			AddMenuItem(menu, "l4d_vs_airport01_greenhouse", "寂静时分 Dead Air");
			AddMenuItem(menu, "l4d_vs_farm01_hilltop", "血腥收获 Bloody Harvest");
			AddMenuItem(menu, "l4d_river01_docks", "牺牲 The Sacrifice");
		}
		SetMenuExitBackButton(menu, true);
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME);
		
		return Plugin_Handled;
	}
	else if(g_bEnable == false || VotensMapE_D == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 换地图投票被禁止。Change map vote is prohibited.");
	}
	return Plugin_Handled;
}

public Action Command_Votemaps2Menu(int client, int args)
{
	if(g_bEnable == true && VotensMap2E_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		Handle menu = CreateMenu(MapMenuHandler);
	
		SetMenuTitle(menu, "▲ Vote Custom Maps <%d map%s>", g_iCount, ((g_iCount > 1) ? "s": "") );
		for (int i = 0; i < g_iCount; i++)
		{
			AddMenuItem(menu, g_sMapinfo[i], g_sMapname[i]);
		}
		
		SetMenuExitBackButton(menu, true);
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME);
		
		return Plugin_Handled;
	}
	else if(g_bEnable == false || VotensMap2E_D == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 换三方图投票被禁止。Change Custom map vote is prohibited.");
	}
	return Plugin_Handled;
}

public int MapMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
	if ( action == MenuAction_Select ) 
	{
		char info[32], name[64];
		GetMenuItem(menu, itemNum, info, sizeof(info), _, name, sizeof(name));
		votesmaps = info;
		votesmapsname = name;	
		DisplayVoteMapsMenu(client);		
	}
	else if ( action == MenuAction_Cancel)
	{
		if (itemNum == MenuCancel_ExitBack) {
			FakeClientCommand(client,"votes");
		}
		else
			ClientVoteMenu[client] = false;
	}
	else if ( action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}
public void DisplayVoteMapsMenu(int client)
{
	if (!TestVoteDelay(client))
	{
		return;
	}
	if(CanStartVotes(client))
	{
	
		char SteamId[35];
		GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
		LogMessage("%N(%s) starts a vote: change map %s",  client, SteamId,votesmapsname);//紀錄在log文件
		CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票：{blue}更换地图 %s {default}。{olive} %N {default}starts a vote: {blue}change map %s", client, votesmapsname, client, votesmapsname);
		
		for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = true;
		
		g_voteType = view_as<voteType>(map);
		
		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
		//SetMenuTitle(g_hVoteMenu, "Vote to change map %s %s",votesmapsname, votesmaps);
		SetMenuTitle(g_hVoteMenu, "Vote to change map: %s",votesmapsname);
		AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
		AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		SetMenuExitButton(g_hVoteMenu, false);
		VoteMenuToAll(g_hVoteMenu, 20);
		
		EmitSoundToAll("ui/beep_synthtone01.wav");
	}
	else
	{
		return;
	}
}

public Action Command_Votesforcespectate(int client, int args)
{
	if(client==0) return Plugin_Handled;		
	if(g_bEnable == true && g_bVotensForceSpectateED == true)
	{
		CreateVoteforcespectateMenu(client);
	}	
	else if(g_bEnable == false || g_bVotensForceSpectateED == false)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 强制使玩家旁观的投票被禁止。Forcespectate Player is prohibited.");
	}
	return Plugin_Handled;
}

void CreateVoteforcespectateMenu(int client)
{	
	Handle menu = CreateMenu(Menu_Votesforcespectate);		
	int team = GetClientTeam(client);
	char name[MAX_NAME_LENGTH];
	char playerid[32];
	SetMenuTitle(menu, "plz choose player u want to forcespectate");
	for(int i = 1;i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i)==team)
		{
			Format(playerid,sizeof(playerid),"%d",i);
			if(GetClientName(i,name,sizeof(name)))
			{
				AddMenuItem(menu, playerid, name);				
			}
		}		
	}
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME);	
}
public int Menu_Votesforcespectate(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32], name[32];
		GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
		forcespectateid = StringToInt(info);
		forcespectateid = GetClientUserId(forcespectateid);
		forcespectateplayername = name;
		
		DisplayVoteforcespectateMenu(param1);		
	}
	else if ( action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack) {
			FakeClientCommand(param1,"votes");
		}
		else
			ClientVoteMenu[param1] = false;
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DisplayVoteforcespectateMenu(int client)
{
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	if(CanStartVotes(client))
	{
		char SteamId[35];
		GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
		LogMessage("%N(%s) starts a vote: forcespectate player %s", client, SteamId, forcespectateplayername);//紀錄在log文件
		
		int iTeam = GetClientTeam(client);
		CPrintToChatAll("[{olive}Orz{default}]{olive} %N {default}发起了一项投票: {blue}强制旁观玩家 %s{default}，只有Ta们队可以投票。{olive} %N {default}starts a vote: {blue}forcespectate player %s{default}, only their team can vote.", client, forcespectateplayername, client, forcespectateplayername);
		
		for(int i=1; i <= MaxClients; i++) 
			if (IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == iTeam)
				ClientVoteMenu[i] = true;
		
		g_voteType = view_as<voteType>(forcespectate);
		
		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL); 
		SetMenuTitle(g_hVoteMenu, "forcespectate player %s?",forcespectateplayername);
		AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
		AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
		SetMenuExitButton(g_hVoteMenu, false);
		DisplayVoteMenuToTeam(g_hVoteMenu, 20,iTeam);
		
		for (int i=1; i<=MaxClients; i++)
			if(IsClientConnected(i)&&IsClientInGame(i)&&!IsFakeClient(i)&&GetClientTeam(i) == iTeam)
				EmitSoundToClient(i,"ui/beep_synthtone01.wav");
	}
	else
	{
		return;
	}
}

stock bool DisplayVoteMenuToTeam(Handle hMenu,int iTime, int iTeam)
{
    int iTotal = 0;
    int[] iPlayers = new int[MaxClients];
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != iTeam)
        {
            continue;
        }
        
        iPlayers[iTotal++] = i;
    }
    
    return VoteMenu(hMenu, iPlayers, iTotal, iTime, 0);
}    
public int Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
	//==========================
	if(action == MenuAction_Select)
	{
		switch(param2)
		{
			case 0: 
			{
				Votey += 1;
				//CPrintToChatAll("[{olive}Orz{default}] %N {blue}has voted{default}.", param1);
			}
			case 1: 
			{
				Voten += 1;
				//CPrintToChatAll("[{olive}Orz{default}] %N {blue}has voted{default}.", param1);
			}
		}
	}
	else if ( action == MenuAction_Cancel)
	{
		if (param1>0 && param1 <=MaxClients && IsClientConnected(param1) && IsClientInGame(param1) && !IsFakeClient(param1))
		{
			//CPrintToChatAll("[{olive}Orz{default}] %N {blue}abandons the vote{default}.", param1);
		}
	}
	//==========================
	char item[64], display[64];
	float percent;
	int votes, totalVotes;

	GetMenuVoteInfo(param2, votes, totalVotes);
	GetMenuItem(menu, param1, item, sizeof(item), _, display, sizeof(display));
	
	if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
	{
		votes = totalVotes - votes;
	}
	percent = GetVotePercent(votes, totalVotes);

	CheckVotes();
	if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		CPrintToChatAll("[{olive}Orz{default}] 没有投票。No votes.");
		g_votedelay = VOTEDELAY_TIME;
		EmitSoundToAll("ui/beep_error01.wav");
		CreateTimer(2.0, VoteEndDelay);
		CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT| TIMER_FLAG_NO_MAPCHANGE);
	}	
	else if (action == MenuAction_VoteEnd)
	{
		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent, g_fLimit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
		{
			g_votedelay = VOTEDELAY_TIME;
			CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT| TIMER_FLAG_NO_MAPCHANGE);
			EmitSoundToAll("ui/beep_error01.wav");
			CPrintToChatAll("[{olive}Orz{default}] {lightgreen}投票失败。{default} 至少 {green}%d%%{default} 同意。（同意 {green}%d%%{default} 票, 总共 {green}%i {default}票） {lightgreen}Vote fail.{default} At least {green}%d%%{default} to agree.(agree {green}%d%%{default}, total {green}%i {default}votes)",
				RoundToNearest(100.0*g_fLimit), RoundToNearest(100.0*percent), totalVotes, RoundToNearest(100.0*g_fLimit), RoundToNearest(100.0*percent), totalVotes);
			CreateTimer(2.0, VoteEndDelay);
		}
		else
		{
			g_votedelay = VOTEDELAY_TIME;
			CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT| TIMER_FLAG_NO_MAPCHANGE);
			EmitSoundToAll("ui/menu_enter05.wav");
			CPrintToChatAll("[{olive}Orz{default}] {lightgreen}投票通过。{default}（同意 {green}%d%%{default} 票, 总共 {green}%i {default}票） {lightgreen}Vote pass.{default}(agree {green}%d%%{default}, total {green}%i {default}votes)", RoundToNearest(100.0*percent), totalVotes, RoundToNearest(100.0*percent), totalVotes);
			CreateTimer(2.0, VoteEndDelay);
			CreateTimer(3.0, COLD_DOWN,_);
		}
	}
	else if(action == MenuAction_End)
	{
		VoteMenuClose();
		//delete menu;
	}

	return 0;
}

public Action Timer_forcespectate(Handle timer, any client)
{
	static bool bClientJoinedTeam = false;		//did the client try to join the infected?
	
	if (!IsClientInGame(client) || IsFakeClient(client)) return Plugin_Stop; //if client disconnected or is fake client
	
	if (g_iSpectatePenaltyCounter[client] != 0)
	{
		if ( (GetClientTeam(client) == 3 || GetClientTeam(client) == 2))
		{
			ChangeClientTeam(client, 1);
			CPrintToChat(client, "[{olive}Orz{default}] 你被投票强制移到旁观！请等待 {green}%d{default} 秒重新加入队伍。You have been voted to be forcespectated! Wait {green}%ds {default}to rejoin team again.", g_iSpectatePenaltyCounter[client], g_iSpectatePenaltyCounter[client]);
			bClientJoinedTeam = true;	//client tried to join the infected again when not allowed
		}
		else if(GetClientTeam(client) == 1 && IsClientIdle(client))
		{
			L4D_TakeOverBot(client);
			ChangeClientTeam(client, 1);
			CPrintToChat(client, "[{olive}Orz{default}] 你被投票强制移到旁观！请等待 {green}%d{default} 秒重新加入队伍。You have been voted to be forcespectated! Wait {green}%ds {default}to rejoin team again.", g_iSpectatePenaltyCounter[client], g_iSpectatePenaltyCounter[client]);
			bClientJoinedTeam = true;	//client tried to join the infected again when not allowed
		}
		g_iSpectatePenaltyCounter[client]--;
		return Plugin_Continue;
	}
	else if (g_iSpectatePenaltyCounter[client] == 0)
	{
		if (GetClientTeam(client) == 3||GetClientTeam(client) == 2)
		{
			ChangeClientTeam(client, 1);
			bClientJoinedTeam = true;
		}
		if (GetClientTeam(client) == 1 && bClientJoinedTeam)
		{
			CPrintToChat(client, "[{olive}Orz{default}] 你现在可以重新加入某个队伍了。You can rejoin both team now.");	//only print this hint text to the spectator if he tried to join the infected team, and got swapped before
		}
		bClientJoinedTeam = false;
		g_iSpectatePenaltyCounter[client] = FORCESPECTATE_PENALTY;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

//====================================================
public void AnyHp()
{
	//CPrintToChatAll("[{olive}Orz{default}] All players{blue}");
	int flags = GetCommandFlags("give");	
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			FakeClientCommand(i, "give health");
			SetEntityHealth(i, MaxHealth);
		}
	}
	SetCommandFlags("give", flags|FCVAR_CHEAT);
}
//================================
void CheckVotes()
{
	PrintHintTextToAll("Agree: %i\nDisagree: %i", Votey, Voten);
}
public Action VoteEndDelay(Handle timer)
{
	Votey = 0;
	Voten = 0;
	for(int i=1; i <= MaxClients; i++) ClientVoteMenu[i] = false;

	return Plugin_Continue;
}
public Action Changelevel_Map(Handle timer)
{
	ServerCommand("changelevel %s", votesmaps);

	return Plugin_Continue;
}
//===============================
void VoteMenuClose()
{
	Votey = 0;
	Voten = 0;
	CloseHandle(g_hVoteMenu);
	g_hVoteMenu = INVALID_HANDLE;
}
float GetVotePercent(int votes, int totalVotes)
{
	return (float(votes) / float(totalVotes));
}
bool TestVoteDelay(int client)
{
	
 	int delay = CheckVoteDelay();
 	
 	if (delay > 0)
 	{
 		if (delay > 60)
 		{
 			CPrintToChat(client, "[{olive}Orz{default}] 你必须等待 {red}%i{default} 秒才能重新开启投票！You must wait for {red}%i {default}sec then start a int vote!", delay % 60, delay % 60);
 		}
 		else
 		{
 			CPrintToChat(client, "[{olive}Orz{default}] 你必须等待 {red}%i{default} 秒才能重新开启投票！You must wait for {red}%i {default}sec then start a int vote!", delay, delay);
 		}
 		return false;
 	}
	
	delay = GetVoteDelay();
 	if (delay > 0)
 	{
 		CPrintToChat(client, "[{olive}Orz{default}] 你必须等待 {red}%i{default} 秒才能重新开启投票！You must wait for {red}%i {default}sec then start a int vote!", delay, delay);
 		return false;
 	}
	return true;
}

bool CanStartVotes(int client)
{
 	if(g_hVoteMenu  != INVALID_HANDLE || IsVoteInProgress())
	{
		CPrintToChat(client, "[{olive}Orz{default}] 正在处理一个其他投票！A vote is already in progress!");
		return false;
	}
	int iNumPlayers;
	//list of players
	for (int i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsClientConnected(i))
		{
			continue;
		}
		iNumPlayers++;
	}
	if (iNumPlayers < g_iCvarPlayerLimit)
	{
		CPrintToChat(client, "[{olive}Orz{default}] 投票无法被开启。因为不足 {red}%d{default} 人。Vote cannot be started. Not enough {red}%d {default}players.", g_iCvarPlayerLimit, g_iCvarPlayerLimit);
		return false;
	}
	return true;
}
//=======================================
public void OnClientDisconnect(int client)
{
	if (IsClientInGame(client) && IsFakeClient(client)) return;

	float currenttime = GetGameTime();
	
	if (lastDisconnectTime == currenttime) return;
	
	CreateTimer(SCORE_DELAY_EMPTY_SERVER, IsNobodyConnected, currenttime);
	lastDisconnectTime = currenttime;
}

public Action IsNobodyConnected(Handle timer, any timerDisconnectTime)
{
	if (timerDisconnectTime != lastDisconnectTime) return Plugin_Stop;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && !IsFakeClient(i))
			return  Plugin_Stop;
	}	
	
	return  Plugin_Stop;
}

public Action COLD_DOWN(Handle timer,any client)
{
	switch (g_voteType)
	{
		case (hp):
		{
			AnyHp();
			//DisplayBuiltinVotePass(vote, "vote to give hp pass");
			LogMessage("vote to give hp pass");	
		}
		case (alltalk):
		{
			ServerCommand("sv_alltalk 1");
			//DisplayBuiltinVotePass(vote, "vote to turn on alltalk pass");
			LogMessage("vote to turn on alltalk pass");
		}
		case (alltalk2):
		{
			ServerCommand("sv_alltalk 0");
			//DisplayBuiltinVotePass(vote, "vote to turn off alltalk pass");
			LogMessage("vote to turn off alltalk pass");
		}
		case (restartmap):
		{
			ServerCommand("sm_restartmap");
			//DisplayBuiltinVotePass(vote, "vote to restartmap pass");
			LogMessage("vote to restartmap pass");
		}
		case (map):
		{
			CreateTimer(5.0, Changelevel_Map);
			CPrintToChatAll("[{olive}Orz{default}] {green}5{default} 秒后更换地图为 {blue}%s。{green}5{default} sec to change map {blue}%s{default} .", votesmapsname, votesmapsname);
			//CPrintToChatAll("{blue}%s",votesmaps);
			//DisplayBuiltinVotePass(vote, "Vote to change map pass");
			LogMessage("Vote to change map %s %s pass",votesmaps,votesmapsname);
		}
		case (kick):
		{
			//DisplayBuiltinVotePass(vote, "Vote to kick player pass");						
			CPrintToChatAll("[{olive}Orz{default}] %s 已经被踢出！%s has been kicked!", kickplayer_name, kickplayer_name);
			LogMessage("Vote to kick %s pass", kickplayer_name);

			int player = GetClientOfUserId(kickplayer_userid);
			if(player && IsClientInGame(player)) KickClient(player, "You have been kicked due to vote");				
			ServerCommand("sm_addban 10 \"%s\" \"You have been kicked due to vote\" ", kickplayer_SteamId);
		}
		case (forcespectate):
		{
			forcespectateid = GetClientOfUserId(forcespectateid);
			if(forcespectateid && IsClientInGame(forcespectateid))
			{
				CPrintToChatAll("[{olive}Orz{default}] {blue}%s{default} 已经被强制移到旁观！{blue}%s{default} has been forcespectated!", forcespectateplayername, forcespectateplayername);
				ChangeClientTeam(forcespectateid, 1);								
				LogMessage("Vote to forcespectate %s pass",forcespectateplayername);
				CreateTimer(1.0, Timer_forcespectate, forcespectateid, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE); // Start unpause countdown
			}
			else
			{
				CPrintToChatAll("[{olive}Orz{default}] %s 玩家找不到。%s player not found.", forcespectateplayername, forcespectateplayername);	
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_VoteDelay(Handle timer, any client)
{
	g_votedelay--;
	if(g_votedelay<=0)
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

int GetVoteDelay()
{
	return g_votedelay;
}

void ParseCampaigns()
{
	KeyValues g_kvCampaigns = new KeyValues("VoteCustomCampaigns");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/VoteCustomCampaigns.txt");

	if ( !FileToKeyValues(g_kvCampaigns, sPath) ) 
	{
		SetFailState("<VCC> File not found: %s", sPath);
		delete g_kvCampaigns;
		return;
	}
	
	if (!KvGotoFirstSubKey(g_kvCampaigns))
	{
		SetFailState("<VCC> File can't read: you dumb noob!");
		delete g_kvCampaigns;
		return;
	}
	
	for (int i = 0; i < MAX_CAMPAIGN_LIMIT; i++)
	{
		KvGetString(g_kvCampaigns,"mapinfo", g_sMapinfo[i], sizeof(g_sMapinfo));
		KvGetString(g_kvCampaigns,"mapname", g_sMapname[i], sizeof(g_sMapname));
		
		if ( !KvGotoNextKey(g_kvCampaigns) )
		{
			g_iCount = ++i;
			break;
		}
	}

	delete g_kvCampaigns;
}

bool HasAccess(int client, char[] g_sAcclvl)
{
	// no permissions set
	if (strlen(g_sAcclvl) == 0)
		return true;

	else if (StrEqual(g_sAcclvl, "-1"))
		return false;

	// check permissions
	int iFlag = GetUserFlagBits(client);
	if ( iFlag & ReadFlagString(g_sAcclvl) || iFlag & ADMFLAG_ROOT )
	{
		return true;
	}

	return false;
}

bool IsClientIdle(int client)
{
	if(GetClientTeam(client) != 1)
		return false;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			if(HasEntProp(i, Prop_Send, "m_humanSpectatorUserID"))
			{
				if(GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID")) == client)
						return true;
			}
		}
	}
	return false;
}