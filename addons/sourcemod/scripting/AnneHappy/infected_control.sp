#pragma semicolon 1
#pragma newdecls required
#define DEBUG 0
#define TESTBUG 0

// 头文件
#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <treeutil>
#undef REQUIRE_PLUGIN
#include <si_target_limit>
#include <pause>
#include <ai_smoker_new>
#include <si_pool>

#define CVAR_FLAG             FCVAR_NOTIFY
#define TEAM_SURVIVOR         2
#define TEAM_INFECTED         3
// 数据
#define NAV_MESH_HEIGHT       20.0
#define PLAYER_HEIGHT         72.0
#define PLAYER_CHEST          45.0
#define HIGHERPOS             300.0
#define HIGHERPOSADDDISTANCE  300.0
#define INCAPSURVIVORCHECKDIS 500.0
#define NORMALPOSMULT         1.4
#define BaitDistance          200.0
#define LadderDetectDistance  500.0

// 启用特感类型
#define ENABLE_SMOKER         (1 << 0)
#define ENABLE_BOOMER         (1 << 1)
#define ENABLE_HUNTER         (1 << 2)
#define ENABLE_SPITTER        (1 << 3)
#define ENABLE_JOCKEY         (1 << 4)
#define ENABLE_CHARGER        (1 << 5)

// Spitter吐口水之后能传送的时间
#define SPIT_INTERVAL         2.0
//确认为跑男的距离
#define RushManDistance       1200.0
//确认射线类型
#define TRACE_RAY_FLAG 					MASK_SHOT | CONTENTS_MONSTERCLIP | CONTENTS_GRATE

// max函数定义
#define max(a, b) ((a) > (b) ? (a) : (b))

stock const char InfectedName[10][] = {
    "common",
    "smoker",
    "boomer",
    "hunter",
    "spitter",
    "jockey",
    "charger",
    "witch",
    "tank",
    "survivor"
};

char sLogFile[PLATFORM_MAX_PATH] = "addons/sourcemod/logs/infected_control.txt";

// 插件基本信息，根据 GPL 许可证条款，需要修改插件请勿修改此信息！
public Plugin myinfo =
{
    name = "Direct InfectedSpawn",
    author = "Caibiii, 夜羽真白，东, Paimon-Kawaii",
    description = "特感刷新控制，传送落后特感",
    version = "2024.05.01#SIPool",
    url = "https://github.com/fantasylidong/CompetitiveWithAnne",


}

// Cvars
ConVar g_hSpawnDistanceMin,            // 特感最低生成距离
    g_hSpawnDistanceMax,               // 特感最大生成距离
    g_hTeleportSi,                     // 是否打开特感传送
    // g_hTeleportDistance                传送距离
    g_hSiLimit,                        // 一波特感生成数量上限
    g_hSiInterval,                     // 每波特感生成基础间隔
    g_hMaxPlayerZombies,               // 设置导演系统的特感数量上限
    g_hTeleportCheckTime,              // 几秒不被看到后可以传送
    g_hEnableSIoption,                 // 设置生成哪几种特感
    g_hAllChargerMode,                 // 是否为全牛模式
    g_hAutoSpawnTimeControl,           // 自动设置增加时间，加到基础间隔之上，这项不打开，增加时间默认为g_hSiInterval/2.打开为特感数量小于g_hSiLimit/3 + 1后再过基准时间开始刷特。
                                       // 但是这个值大于g_hSiInterval/2也会开始强制刷特
    g_hAddDamageToSmoker,              // 被smoker拉的时候是否对smoker是否进行增伤
    g_hIgnoreIncappedSurvivorSight,    // 是否忽视掉倒地生还者视线
    g_hAntiBaitMode,                   // 是否开启防诱饵模式，以免生还获得过多地利优势
    g_hBaitFlow,                       // 这一回合刷特的流程进度与上一回合的流程进度如果低于这个权重，如果没有tank或者高紧张度，会判定为摸鱼等刷，会被Bait系统判定在进行诱饵，进行惩罚
    //g_hSIAttackIntent,                 // 特感攻击意图权重， 如果生还者低于这个权重，没有特殊情况，就会提前开启刷特进程（最低为设置秒数）
    g_hVsBossFlowBuffer, g_hAllHunterMode;

// Ints
int
    g_iSiLimit,                              //特感数量
    g_iRushManIndex,                         //跑男id
    g_iWaveTime,                             // Debug时输出这是第几波刷特
    g_iLastSpawnTime,                        //离上次刷特过去了多久
    g_iTotalSINum = 0,                       //总共还活着的特感
    g_iEnableSIoption = 63,                  //可生成的特感种类
    g_iTeleportCheckTime = 5,                //特感传送要求的不被看到的次数(1s检查一次)
    g_iSINum[6] = { 0 },                     //记录当前还存活的特感数量
    g_ArraySIlimit[6] = { 0 },               //记录去除队列里特感数量后还能生成的特感
    g_iTeleCount[MAXPLAYERS + 1] = { 0 },    //每个特感传送的不被看到次数
    g_iTargetSurvivor = -1,                  // OnGameFrame参数里，以该目标生成生成网络，寻找生成目标
    g_iQueueIndex = 0,                       //当前生成队列长度
    g_iTeleportIndex = 0,                    //当前传送队列长度
    g_iSpawnMaxCount = 0,                    //当前可生成特感数量
    g_iSurvivorNum = 0,                      //活着的生还者数量
    g_iHordeStatus = 0,    // 是不是处于无限尸潮的机关中
    g_iBaitTimeCheckTime = 0,                //检测到玩家Bait的次数，方便进行何种惩罚
    g_iLadderBaitTimeCheckTime = 0,          //检测到玩家梯子Bait的次数，方便进行何种惩罚
    g_iSurvivors[MAXPLAYERS + 1] = { 0 };    //活着生还者的索引

// Floats
float
    g_fSpitterSpitTime[MAXPLAYERS + 1],    // Spitter吐口水时间
    g_fSpawnDistanceMin,                   //特感的最小生成距离
    g_fSpawnDistanceMax,                   //特感的最大生成距离
    g_fSpawnDistance,                      //特感的当前生成距离
//	g_fTeleportDistanceMin, 			   //特感传送距离生还的最小距离
    g_fTeleportDistance,                   //特感当前传送生成距离
    g_fLastSISpawnStartTime,               //上一波特感生成时间
    g_fUnpauseNextSpawnTime,               //因为暂停记录下下一波特感的时间，方便解除暂停时创建处理线程
    g_fLastSISpawnAurSurFlow,              //上一波刷特生还者的平均进度，用于检测玩家一回合是否在特意等特感刷新，没有走
    g_fBaitFlow,                           //储存Convar设置的Baitflow大小
    //g_fSIAttackIntent,                     // 特感进攻意图
    g_fSiInterval;                         //特感的生成时间间隔
// Bools
bool
    g_bTeleportSi,                       //是否开启特感传送检测
    g_bPickRushMan,                      //是否针对跑男
    g_bShouldCheck,                      //是否开启时间检测
    g_bAutoSpawnTimeControl,             //是否开启自动增加时间
    g_bAddDamageToSmoker,                //是否对smoker增伤（一般alone模式开启）
    g_bIgnoreIncappedSurvivorSight,      //是否忽略倒地生还者的视线
    g_bIsLate = false,                   // text插件是否发送开启刷特命令
    g_bSmokerAvailable = false,          // ai_smoker_new是否存在
    g_bAntiBaitMode = false,             //抗诱饵模式是否开启
    g_bSIPoolAvailable = false,          //特感池是否存在
    g_bPauseSystemAvailable = false,     // 能否暂停
    g_bTargetSystemAvailable = false;    //目标选择插件是否存在

// Handle
Handle
    g_hCheckShouldSpawnOrNot = INVALID_HANDLE,    // 1s检测一次是否开启刷特进程的维护进程
    g_hSpawnProcess = INVALID_HANDLE,             //刷特 handle
    g_hTeleHandle = INVALID_HANDLE,               //传送sdk Handle
    g_hRushManNotifyForward = INVALID_HANDLE;     //检测到跑男提醒Target_limit插件放开单人目标限制

// ArrayList
ArrayList
    aTeleportQueue,    //传送队列
    // aSpawnNavList,						//储存特感生成的navid，用来限制特感不能生成在同一块Navid上
    ladderList = null,
    aSpawnQueue;    //刷特队列

SIPool
    g_hSIPool;

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    RegPluginLibrary("infected_control");
    g_hRushManNotifyForward = CreateGlobalForward("OnDetectRushman", ET_Ignore, Param_Cell);
    CreateNative("GetNextSpawnTime", Native_GetNextSpawnTime);
    return APLRes_Success;
}

any Native_GetNextSpawnTime(Handle plugin, int numParams)
{
    float time = 0.0;
    //如果刷特进程还不开始，直接返回刷特间隔
    if (g_hSpawnProcess == null)
        time = g_fSiInterval;
    else time = g_fSiInterval - (GetGameTime() - g_fLastSISpawnStartTime);

#if DEBUG
    Debug_Print("下一波特感生成时间是%.2f秒后", time);
#endif
    return time;
}

public void OnAllPluginsLoaded()
{
    g_bTargetSystemAvailable = LibraryExists("si_target_limit");
    g_bSmokerAvailable = LibraryExists("ai_smoker_new");
    g_bSIPoolAvailable = LibraryExists("si_pool");
    g_bPauseSystemAvailable = LibraryExists("pause");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "si_target_limit"))
        g_bTargetSystemAvailable = true;
    else if (StrEqual(name, "ai_smoker_new"))
        g_bSmokerAvailable = true;
    else if (StrEqual(name, "si_pool"))
        g_bSIPoolAvailable = true;
    else if (StrEqual(name, "pause"))
        g_bPauseSystemAvailable = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "si_target_limit"))
        g_bTargetSystemAvailable = false;
    else if (StrEqual(name, "ai_smoker_new"))
        g_bSmokerAvailable = false;
    else if (StrEqual(name, "si_pool"))
        g_bSIPoolAvailable = false;
    else if (StrEqual(name, "pause"))
        g_bPauseSystemAvailable = false;
}

public void OnPluginStart()
{
    // CreateConVar
    g_hSpawnDistanceMin = CreateConVar("inf_SpawnDistanceMin", "250.0", "特感复活离生还者最近的距离限制", CVAR_FLAG, true, 0.0);
    g_hSpawnDistanceMax = CreateConVar("inf_SpawnDistanceMax", "1500.0", "特感复活离生还者最远的距离限制", CVAR_FLAG, true, g_hSpawnDistanceMin.FloatValue);
    g_hTeleportSi = CreateConVar("inf_TeleportSi", "1", "是否开启特感距离生还者一定距离将其传送至生还者周围", CVAR_FLAG, true, 0.0, true, 1.0);
    g_hTeleportCheckTime = CreateConVar("inf_TeleportCheckTime", "5", "特感几秒后没被看到开始传送", CVAR_FLAG, true, 0.0);
    g_hEnableSIoption = CreateConVar("inf_EnableSIoption", "63", "启用生成的特感类型，1 smoker 2 boomer 4 hunter 8 spitter 16 jockey 32 charger,把你想要生成的特感值加起来", CVAR_FLAG, true, 0.0, true, 63.0);
    g_hAllChargerMode = CreateConVar("inf_AllChargerMode", "0", "是否是全牛模式", CVAR_FLAG, true, 0.0, true, 1.0);
    g_hAllHunterMode = CreateConVar("inf_AllHunterMode", "0", "是否是全猎人模式", CVAR_FLAG, true, 0.0, true, 1.0);
    g_hAntiBaitMode = CreateConVar("inf_AntiBaitMode", "0", "是否开启诱饵模式", CVAR_FLAG, true, 0.0, true, 1.0);
    g_hBaitFlow = CreateConVar("inf_BaitFlow", "3.0", "一个刷特回合推进进度如果小于这个数值会被判定为消极定点对抗(无tank)情况，可设置值为(1-10)", CVAR_FLAG, true, 0.0, true, 10.0);
    //g_hSIAttackIntent = CreateConVar("inf_SIAttackIntent", "0.48", "如果生还者紧张度低于这个值，没有特殊情况下会提前刷新特感", CVAR_FLAG, true, 0.0, true, 10.0);
    g_hAutoSpawnTimeControl = CreateConVar("inf_EnableAutoSpawnTime", "1", "是否开启自动设置增加时间", CVAR_FLAG, true, 0.0, true, 1.0);
    g_hIgnoreIncappedSurvivorSight = CreateConVar("inf_IgnoreIncappedSurvivorSight", "1", "特感传送检测是否被看到的时候是否忽略倒地生还者视线", CVAR_FLAG, true, 0.0, true, 1.0);
    g_hAddDamageToSmoker = CreateConVar("inf_AddDamageToSmoker", "0", "单人模式smoker拉人时是否5倍伤害", CVAR_FLAG, true, 0.0, true, 1.0);
    // 传送会根据这个数值画一个以选定生还者为核心，两边各长inf_TeleportDistance单位距离，高inf_TeleportDistance距离的长方形区域内找复活位置,PS传送最好近一点
    // g_hTeleportDistance = CreateConVar("inf_TeleportDistance", "600.0", "特感传送区域的最小复活大小", CVAR_FLAG, true, g_hSpawnDistanceMin.FloatValue);
    g_hSiLimit = CreateConVar("l4d_infected_limit", "6", "一次刷出多少特感", CVAR_FLAG, true, 0.0);
    g_hSiInterval = CreateConVar("versus_special_respawn_interval", "16.0", "对抗模式下刷特时间控制", CVAR_FLAG, true, 0.0);
    g_hMaxPlayerZombies = FindConVar("z_max_player_zombies");
    g_hVsBossFlowBuffer = FindConVar("versus_boss_buffer");
    SetConVarInt(FindConVar("director_no_specials"), 1);

    // HookEvents
    // PostNoCopy是绝对不正确的，NoCopy 会导致 event 丢弃所有的数据("Use 'PostNoCopy' if your action is Post and ONLY requires the event name.")
    // 丢弃的数据包括 userid,attackerid,weaponid 等等，对于求生来说这几个字节的内存没必要省略
    // 详见：https://wiki.alliedmods.net/Events_(SourceMod_Scripting)
    HookEvent("finale_win", evt_RoundEnd);
    HookEvent("mission_lost", evt_RoundEnd);
    HookEvent("player_hurt", evt_PlayerHurt);
    HookEvent("ability_use", evt_GetSpitTime);
    HookEvent("round_start", evt_RoundStart);
    HookEvent("map_transition", evt_RoundEnd);
    HookEvent("player_death", evt_PlayerDeath);
    HookEvent("player_spawn", evt_PlayerSpawn);

    // AddChangeHook
    g_hSpawnDistanceMax.AddChangeHook(ConVarChanged_Cvars);
    g_hSpawnDistanceMin.AddChangeHook(ConVarChanged_Cvars);
    g_hTeleportSi.AddChangeHook(ConVarChanged_Cvars);
    g_hTeleportCheckTime.AddChangeHook(ConVarChanged_Cvars);
    // g_hTeleportDistance.AddChangeHook(ConVarChanged_Cvars);
    g_hSiInterval.AddChangeHook(ConVarChanged_Cvars);
    g_hIgnoreIncappedSurvivorSight.AddChangeHook(ConVarChanged_Cvars);
    g_hEnableSIoption.AddChangeHook(ConVarChanged_Cvars);
    g_hAllChargerMode.AddChangeHook(ConVarChanged_Cvars);
    g_hAllHunterMode.AddChangeHook(ConVarChanged_Cvars);
    g_hAntiBaitMode.AddChangeHook(ConVarChanged_Cvars);
    g_hAutoSpawnTimeControl.AddChangeHook(ConVarChanged_Cvars);
    g_hAddDamageToSmoker.AddChangeHook(ConVarChanged_Cvars);
    g_hSiLimit.AddChangeHook(MaxPlayerZombiesChanged_Cvars);

    // ArrayList
    aSpawnQueue = new ArrayList();
    aTeleportQueue = new ArrayList();
    // aSpawnNavList = new ArrayList();
    ladderList = new ArrayList(3);

    //  GetCvars
    GetCvars();
    GetSiLimit();

    // SetConVarBonus
    SetConVarBounds(g_hMaxPlayerZombies, ConVarBound_Upper, true, g_hSiLimit.FloatValue);

    // Debug
    RegAdminCmd("sm_startspawn", Cmd_StartSpawn, ADMFLAG_ROOT, "管理员重置刷特时钟");
    RegAdminCmd("sm_stopspawn", Cmd_StopSpawn, ADMFLAG_ROOT, "管理员重置刷特时钟");
}

/*
public void OnMapStart()
{
    if (g_bSIPoolAvailable && !g_hSIPool) g_hSIPool = SIPool.Instance();
}
*/
public void OnPluginEnd()
{
    if (g_hAllChargerMode.BoolValue)
    {
        FindConVar("z_charger_health").RestoreDefault();
        FindConVar("z_charge_max_speed").RestoreDefault();
        FindConVar("z_charge_start_speed").RestoreDefault();
        FindConVar("z_charger_pound_dmg").RestoreDefault();
        FindConVar("z_charge_max_damage").RestoreDefault();
        FindConVar("z_charge_interval").RestoreDefault();
    }
    delete ladderList;
}

void TweakSettings()
{
    if (g_hAllChargerMode.BoolValue)
    {
        FindConVar("z_charger_health").SetFloat(500.0);
        FindConVar("z_charge_max_speed").SetFloat(750.0);
        FindConVar("z_charge_start_speed").SetFloat(350.0);
        FindConVar("z_charger_pound_dmg").SetFloat(10.0);
        FindConVar("z_charge_max_damage").SetFloat(6.0);
        FindConVar("z_charge_interval").SetFloat(2.0);
    }
}

// 向量绘制
// #include "vector/vector_show.sp"

stock Action Cmd_StartSpawn(int client, int args)
{
    if (L4D_HasAnySurvivorLeftSafeArea())
    {
#if TESTBUG
        PrintToChatAll("目前是测试版本v2.2");
#endif
        ResetStatus();
        CreateTimer(0.1, SpawnFirstInfected);
        GetSiLimit();
        TweakSettings();
    }
    return Plugin_Handled;
}

stock Action Cmd_StopSpawn(int client, int args)
{
    StopSpawn();
    return Plugin_Handled;
}

// *********************
//		获取Cvar值
// *********************
void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void MaxPlayerZombiesChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_iSiLimit = g_hSiLimit.IntValue;
    CreateTimer(0.1, MaxSpecialsSet);
}

void GetCvars()
{
    g_fSpawnDistanceMax = g_hSpawnDistanceMax.FloatValue;
    g_fSpawnDistanceMin = g_hSpawnDistanceMin.FloatValue;
    g_bTeleportSi = g_hTeleportSi.BoolValue;
    // g_fTeleportDistanceMin = g_hTeleportDistance.FloatValue;
    g_fSiInterval = g_hSiInterval.FloatValue;
    g_iSiLimit = g_hSiLimit.IntValue;
    g_iTeleportCheckTime = g_hTeleportCheckTime.IntValue;
    g_iEnableSIoption = g_hEnableSIoption.IntValue;
    g_bAddDamageToSmoker = g_hAddDamageToSmoker.BoolValue;
    g_bAutoSpawnTimeControl = g_hAutoSpawnTimeControl.BoolValue;
    g_bIgnoreIncappedSurvivorSight = g_hIgnoreIncappedSurvivorSight.BoolValue;
    g_bAntiBaitMode = g_hAntiBaitMode.BoolValue;
    //g_fSIAttackIntent = g_hSIAttackIntent.FloatValue;
    g_fBaitFlow = g_hBaitFlow.FloatValue;
    if (g_hAllChargerMode.BoolValue)
        TweakSettings();
}

public Action MaxSpecialsSet(Handle timer)
{
    SetConVarBounds(g_hMaxPlayerZombies, ConVarBound_Upper, true, g_hSiLimit.FloatValue);
    g_hMaxPlayerZombies.IntValue = g_iSiLimit;
    return Plugin_Continue;
}

// *********************
//		    事件
// *********************
// Spitter出生重置能力
void evt_PlayerSpawn(Event event, const char[] name, bool dont_broadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsSpitter(client))
        g_fSpitterSpitTime[client] = GetGameTime();
#if DEBUG
    else if (IsAiTank(client))
        Debug_Print("系统生成一只tank，特感总数量 %d, 真实特感数量：%d", g_iTotalSINum, GetCurrentSINum());
#endif
}

//获取spitter口水时间
void evt_GetSpitTime(Event event, const char[] name, bool dont_broadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || !IsClientInGame(client) || !IsFakeClient(client))
        return;

    static char ability[16];
    event.GetString("ability", ability, sizeof ability);
    if (strcmp(ability, "ability_spit") == 0)
        g_fSpitterSpitTime[client] = GetGameTime();
}

/* 玩家受伤,增加对smoker得伤害 */
void evt_PlayerHurt(Event event, const char[] name, bool dont_broadcast)
{
    if (!g_bAddDamageToSmoker) return;

    int victim = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    int damage = GetEventInt(event, "dmg_health");
    int eventhealth = GetEventInt(event, "health");
    int AddDamage = 0;
    if (IsValidSurvivor(attacker) && IsInfectedBot(victim) && GetEntProp(victim, Prop_Send, "m_zombieClass") == 1)
    {
        if (GetEntPropEnt(victim, Prop_Send, "m_tongueVictim") > 0)
            AddDamage = damage * 5;

        int health = eventhealth - AddDamage;
        if (health < 1) health = 0;

        SetEntityHealth(victim, health);
        SetEventInt(event, "health", health);
    }
}

void InitStatus()
{
    if (g_hTeleHandle != INVALID_HANDLE)
    {
        delete g_hTeleHandle;
        g_hTeleHandle = INVALID_HANDLE;
        //这里其实可以不用赋值，delete 后变量会被分配为 null，可以使用 if(g_hTeleHandle != null) 进行判断
    }

    if (g_hCheckShouldSpawnOrNot != INVALID_HANDLE)
    {
        delete g_hCheckShouldSpawnOrNot;
        g_hCheckShouldSpawnOrNot = INVALID_HANDLE;
    }

    if (g_hSpawnProcess != INVALID_HANDLE)
    {
        KillTimer(g_hSpawnProcess);
#if DEBUG
        Debug_Print("刷特进程终止");
#endif
        g_hSpawnProcess = INVALID_HANDLE;
    }

    g_bPickRushMan = false;
    g_bShouldCheck = false;
    g_bIsLate = false;
    g_iHordeStatus = 0;
    g_iSpawnMaxCount = 0;
    g_fLastSISpawnStartTime = 0.0;
    g_fUnpauseNextSpawnTime = 0.0;
    g_fLastSISpawnAurSurFlow = 0.0;
    g_iBaitTimeCheckTime = 0;
    g_iLadderBaitTimeCheckTime = 0;
    aSpawnQueue.Clear();
    aTeleportQueue.Clear();
    // aSpawnNavList.Clear();
    g_iQueueIndex = 0;
    g_iTeleportIndex = 0;
    g_iWaveTime = 0;
    for (int i = 0; i <= MAXPLAYERS; i++)
        g_fSpitterSpitTime[i] = 0.0;

    for (int i = 0; i < 6; i++)
        g_iSINum[i] = 0;
}

void StopSpawn()
{
    InitStatus();
}

void evt_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    InitStatus();
    CreateTimer(0.1, MaxSpecialsSet);
    CreateTimer(1.0, SafeRoomReset, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(3.0, initLadder, _, TIMER_FLAG_NO_MAPCHANGE);
}

void evt_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    ladderList.Clear();
    InitStatus();
}

// 开局重置梯子状态
Action initLadder(Handle timer)
{
	if(ladderList.Length <= 1){
		CheckAllLadder();
	}
	return Plugin_Continue;
}

void evt_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsInfectedBot(client)) return;

    int type = GetEntProp(client, Prop_Send, "m_zombieClass");
    //防止无声口水
    if (type != ZC_SPITTER || g_bSIPoolAvailable)    // 使用SIPool后不会出现无声口水
        CreateTimer(0.5, Timer_KickBot, client);

    if (type >= 1 && type <= 6)
    {
        if (g_iSINum[type - 1] > 0) g_iSINum[type - 1]--;
        else g_iSINum[type - 1] = 0;

        if (g_iTotalSINum > 0) g_iTotalSINum--;
        else g_iTotalSINum = 0;

#if DEBUG
        Debug_Print("杀死%N,特感总数和该种类特感数量减1分别为%d %d", client, g_iTotalSINum, g_iSINum[type - 1]);
#endif
    }
    g_iTeleCount[client] = 0;
}

Action Timer_KickBot(Handle timer, int client)
{
    if (IsClientInGame(client) && !IsClientInKickQueue(client) && IsFakeClient(client))
    {
#if DEBUG
        Debug_Print("踢出特感%N", client);
#endif
        if (g_bSIPoolAvailable)
            g_hSIPool.ReturnSIBot(client);
        else
            KickClient(client, "You are worthless and was kicked by console");
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

// *********************
//		  功能部分
// *********************
public void OnGameFrame()
{
    // 根据情况动态调整 z_maxplayers_zombie 数值
    if (g_iSiLimit > g_hMaxPlayerZombies.IntValue)
        CreateTimer(0.1, MaxSpecialsSet);

    if (g_iTeleportIndex <= 0 && g_iQueueIndex < g_iSiLimit)
    {
        int zombieclass = 0;
        if (g_hAllChargerMode.BoolValue)
            zombieclass = 6;
        else if (g_hAllHunterMode.BoolValue)
            zombieclass = 3;
        else zombieclass = GetRandomInt(1, 6);

        if (zombieclass != 0 && MeetRequire(zombieclass) && !HasReachedLimit(zombieclass) && g_iQueueIndex < g_iSiLimit)
        {
            //这里增加一些boomer和spitter生成的判定，让boomer和spitter比较晚生成
            aSpawnQueue.Push(g_iQueueIndex);
            aSpawnQueue.Set(g_iQueueIndex, zombieclass, 0, false);
            g_ArraySIlimit[zombieclass - 1] -= 1;
            g_iQueueIndex += 1;
#if DEBUG
            Debug_Print("<刷特队列> 当前入队特感：%s，当前队列长度：%d，当前队列索引位置：%d", InfectedName[zombieclass], aSpawnQueue.Length, g_iQueueIndex);
#endif
        }
    }

    if (g_bIsLate)
    {
        /*
        // 当nav存储长度超过特感生成上限时，删去第一个
        if (aSpawnNavList.Length > g_iSiLimit)
        {
            //Debug_Print("<nav记录> 当前队列长度：%d, 超过特感上限，清除队列第一个元素", aSpawnNavList.Length);
            aSpawnNavList.Erase(0);
        }
        */
        if (g_iTotalSINum < g_iSiLimit)
        {
            if (g_iTeleportIndex > 0)
            {
                g_iTargetSurvivor = GetTargetSurvivor();
                if (g_fTeleportDistance < g_fSpawnDistanceMax)
                    g_fTeleportDistance += 20.0;

                float fSpawnPos[3] = { 0.0 };
                bool posfinded = g_iLadderBaitTimeCheckTime >= 1? GetSpawnPos(fSpawnPos, aTeleportQueue.Get(0), g_iTargetSurvivor, g_fTeleportDistance * 2, true) : GetSpawnPos(fSpawnPos, aTeleportQueue.Get(0), g_iTargetSurvivor, g_fTeleportDistance, true);
                if (posfinded)
                {
                    int iZombieClass = aTeleportQueue.Get(0);
                    if (!(iZombieClass >= 1 && iZombieClass <= 6))
                    {
#if DEBUG
                        Debug_Print("特感类型读取错误，读取的特感类型为：%d", iZombieClass);
#endif
                        aTeleportQueue.Erase(0);
                        g_iTeleportIndex -= 1;
                        return;
                    }

                    if (SpawnInfected(fSpawnPos, g_fTeleportDistance, iZombieClass, true))
                    {
                        g_iSINum[iZombieClass - 1] += 1;
                        g_iTotalSINum += 1;
                        if (aTeleportQueue.Length > 0 && g_iTeleportIndex > 0)
                        {
                            aTeleportQueue.Erase(0);
                            g_iTeleportIndex -= 1;
                        }
#if DEBUG
                        print_type(iZombieClass, g_fSpawnDistance, true);
#endif
                    }
                    else if (g_iTeleportIndex <= 0)
                    {
                        aTeleportQueue.Clear();
                        g_iTeleportIndex = 0;
                    }
                }
            }

            // Debug_Print("spawn_max:%d, tpidx:%d, queue_idx:%d", g_iSpawnMaxCount, g_iTeleportIndex, g_iQueueIndex);
            //传送队列优先处理，防止普通刷特刷出来把特感数量刷满了
            if (g_iSpawnMaxCount > 0 && g_iTeleportIndex <= 0 && g_iQueueIndex > 0)
            {
                g_iTargetSurvivor = GetTargetSurvivor();
                if (g_fSpawnDistance < g_fSpawnDistanceMax)
                    g_fSpawnDistance += 5.0;

                float fSpawnPos[3] = { 0.0 };
                bool posfinded = g_iLadderBaitTimeCheckTime >= 1? GetSpawnPos(fSpawnPos, aSpawnQueue.Get(0), g_iTargetSurvivor, g_fSpawnDistance * 2, false) : GetSpawnPos(fSpawnPos, aSpawnQueue.Get(0), g_iTargetSurvivor, g_fSpawnDistance, false);
                if (posfinded)
                {
                    int iZombieClass = aSpawnQueue.Get(0);
                    if ( SpawnInfected(fSpawnPos, g_fSpawnDistance, iZombieClass))
                    {
                        g_iSpawnMaxCount -= 1;
                        g_iSINum[iZombieClass - 1] += 1;
                        g_iTotalSINum += 1;
                        if (aSpawnQueue.Length > 0 && g_iQueueIndex > 0)
                        {
                            aSpawnQueue.Erase(0);
                            g_iQueueIndex -= 1;
                            //刷出来之后要求特感激进进攻
                            BypassAndExecuteCommand("nb_assault");
                        }
#if DEBUG
                        print_type(iZombieClass, g_fSpawnDistance);
#endif
                    }
                    else
                    {
                        if (HasReachedLimit(iZombieClass))
#if DEBUG
                            ReachedLimit(iZombieClass);
#else
                            ReachedLimit();
#endif

                        if (g_iQueueIndex <= 0)
                        {
                            aSpawnQueue.Clear();
                            g_iQueueIndex = 0;
                        }
                    }
                }
            }
        }
    }
}

stock bool GetSpawnPos(float fSpawnPos[3], const int class, int TargetSurvivor, float SpawnDistance, bool IsTeleport = false)
{
    if (!IsValidClient(TargetSurvivor)) return false;

    float fSurvivorPos[3], fDirection[3], fEndPos[3], fMins[3], fMaxs[3];
    // 根据指定生还者坐标，拓展刷新范围
    GetClientEyePosition(TargetSurvivor, fSurvivorPos);
    //增加高度，增加刷房顶的几率
    if (SpawnDistance < 500.0)
        fMaxs[2] = fSurvivorPos[2] + 800.0;
    else fMaxs[2] = fSurvivorPos[2] + SpawnDistance + 300.0;

    float SurAurDistance = GetSurAvrDistance();
    if( SurAurDistance < BaitDistance)
    {
        SpawnDistance *= (1 + SurAurDistance / BaitDistance);
    }

    if(g_iLadderBaitTimeCheckTime)
    {
        SpawnDistance += BaitDistance;
    }

    fMins[0] = fSurvivorPos[0] - SpawnDistance;
    fMaxs[0] = fSurvivorPos[0] + SpawnDistance;
    fMins[1] = fSurvivorPos[1] - SpawnDistance;
    fMaxs[1] = fSurvivorPos[1] + SpawnDistance;
    fMaxs[2] = fSurvivorPos[2] + SpawnDistance;
    // 规定射线方向
    fDirection[0] = 90.0;
    fDirection[1] = fDirection[2] = 0.0;
    // 随机刷新位置
    fSpawnPos[0] = GetRandomFloat(fMins[0], fMaxs[0]);
    fSpawnPos[1] = GetRandomFloat(fMins[1], fMaxs[1]);
    fSpawnPos[2] = GetRandomFloat(fSurvivorPos[2], fMaxs[2]);
    // 找位条件，可视，是否在有效 NavMesh，是否卡住，否则先会判断是否在有效 Mesh 与是否卡住导致某些位置刷不出特感
    int count2 = 0;
    //生成的时候只能在有跑男情况下才特意生成到幸存者前方
    while (PlayerVisibleToSDK(fSpawnPos, IsTeleport) || !IsOnValidMesh(fSpawnPos) || IsPlayerStuck(fSpawnPos) || ((g_bPickRushMan || IsTeleport) && !Is_Pos_Ahead(fSpawnPos, g_iTargetSurvivor)))
    {
        count2++;
        if (count2 > 20)
        {
            return false;
        }
        fSpawnPos[0] = GetRandomFloat(fMins[0], fMaxs[0]);
        fSpawnPos[1] = GetRandomFloat(fMins[1], fMaxs[1]);
        fSpawnPos[2] = GetRandomFloat(fSurvivorPos[2], fMaxs[2]);
        TR_TraceRay(fSpawnPos, fDirection, TRACE_RAY_FLAG, RayType_Infinite);
        if (TR_DidHit())
        {
            TR_GetEndPosition(fEndPos);
            fSpawnPos = fEndPos;
            fSpawnPos[2] += NAV_MESH_HEIGHT;
        }
    }
    return true;
}

/** thanks 树树子 https://github.com/GlowingTree880/L4D2_LittlePlugins/blob/main/Infected_Control_Rework/inf_pos_find.sp
* 使用射线并配合 L4D_GetRandomPZSpawnPosition 进行找位, 思路来自鹅国人 (鹅佬)
* @param client 以这个客户端为中心进行找位
* @param class 需要刷新的特感类型
* @param gridIncrement 网格增量
* @param spawnPos 刷新位置
* @return void

bool getSpanPosByAPIEnhance(float fSpawnPos[3], const int class, int TargetSurvivor, float SpawnDistance, bool IsTeleport = false) {
    if (!IsValidClient(TargetSurvivor)) return false;

    float fSurvivorPos[3], fDirection[3], fEndPos[3], fMins[3], fMaxs[3];
    // 根据指定生还者坐标，拓展刷新范围
    GetClientEyePosition(TargetSurvivor, fSurvivorPos);
    //增加高度，增加刷房顶的几率
    if (SpawnDistance < 500.0)
        fMaxs[2] = fSurvivorPos[2] + 800.0;
    else fMaxs[2] = fSurvivorPos[2] + SpawnDistance + 300.0;

    float SurAurDistance = GetSurAvrDistance();
    if( SurAurDistance < BaitDistance)
    {
        SpawnDistance *= (1 + SurAurDistance / BaitDistance);
    }

    if(g_iLadderBaitTimeCheckTime)
    {
        SpawnDistance += BaitDistance;
    }

    fMins[0] = fSurvivorPos[0] - SpawnDistance;
    fMaxs[0] = fSurvivorPos[0] + SpawnDistance;
    fMins[1] = fSurvivorPos[1] - SpawnDistance;
    fMaxs[1] = fSurvivorPos[1] + SpawnDistance;
    fMaxs[2] = fSurvivorPos[2] + SpawnDistance;
    // 规定射线方向
    fDirection[0] = 90.0;
    fDirection[1] = fDirection[2] = 0.0;
    // 随机刷新位置
    fSpawnPos[0] = GetRandomFloat(fMins[0], fMaxs[0]);
    fSpawnPos[1] = GetRandomFloat(fMins[1], fMaxs[1]);
    fSpawnPos[2] = GetRandomFloat(fSurvivorPos[2], fMaxs[2]);
    // 找位条件，可视，是否在有效 NavMesh，是否卡住，否则先会判断是否在有效 Mesh 与是否卡住导致某些位置刷不出特感
    int count2 = 0;
    //生成的时候只能在有跑男情况下才特意生成到幸存者前方
    while (PlayerVisibleToSDK(fSpawnPos, IsTeleport) || !IsOnValidMesh(fSpawnPos) || IsPlayerStuck(fSpawnPos) || ((g_bPickRushMan || IsTeleport) && !Is_Pos_Ahead(fSpawnPos, g_iTargetSurvivor)) && count2 <= 20)
    {
        count2++;
        fSpawnPos[0] = GetRandomFloat(fMins[0], fMaxs[0]);
        fSpawnPos[1] = GetRandomFloat(fMins[1], fMaxs[1]);
        fSpawnPos[2] = GetRandomFloat(fSurvivorPos[2], fMaxs[2]);
        TR_TraceRay(fSpawnPos, fDirection, TRACE_RAY_FLAG, RayType_Infinite);
        if (TR_DidHit())
        {
            TR_GetEndPosition(fEndPos);
            fSpawnPos = fEndPos;
            fSpawnPos[2] += NAV_MESH_HEIGHT;
        }
        ValidMeshAddFlag(fSpawnPos);
    }
    // 选择一个刷新位置
    if (!L4D_GetRandomPZSpawnPosition(TargetSurvivor, class, 20, fSpawnPos))
        return false;
    else
        return true;
}
**/

stock bool SpawnInfected(float fSpawnPos[3], float SpawnDistance, int iZombieClass, bool IsTeleport = false)
{
    float fSurvivorPos[3];
    // Debug_Print("生还者看不到");
    //  生还数量为 4，能循环4次，循环到刷出返回是否成功
    for (int count = 0; count < g_iSurvivorNum; count++)
    {
        int index = g_iSurvivors[count];
        //不是有效生还者不生成
        if (!IsValidSurvivor(index))
            continue;

        //生还者倒地或者挂边，也不生成
        if (IsClientIncapped(index))
            continue;

        //非跑男模式目标已满，跳过
        if (g_bTargetSystemAvailable && !g_bPickRushMan && IsClientReachLimit(index))
            continue;

        GetClientEyePosition(index, fSurvivorPos);
        fSurvivorPos[2] -= 60.0;
        //获取nav地址
        Address nav1 = L4D_GetNearestNavArea(fSpawnPos, 120.0, false, false, false, TEAM_INFECTED);
        Address nav2 = L4D_GetNearestNavArea(fSurvivorPos, 120.0, false, false, false, TEAM_INFECTED);

        //这一段是对高处生成位置进行的补偿
        float distance;
        if (IsTeleport)
            distance = g_fTeleportDistance;
        else
            distance = g_fSpawnDistance;

        if (distance * (NORMALPOSMULT - 1) <= 250.0)
            distance += 250.0;
        else
            distance *= NORMALPOSMULT;

        if (fSpawnPos[2] - fSurvivorPos[2] > HIGHERPOS)
            distance += HIGHERPOSADDDISTANCE;
        //Bait生成拓展后，生成distance也需要进行对应倍数拓展，以防刷不出
        float SurAurDistance = GetSurAvrDistance();
        if( SurAurDistance < BaitDistance)
        {
            distance *= (1 + SurAurDistance / BaitDistance);
        }

        if(g_iLadderBaitTimeCheckTime)
        {
            SpawnDistance += BaitDistance;
        }

        // nav1 和 nav2 必须有网格相连的路，并且生成距离大于distance，增加不能是同nav网格的要求
        if (L4D2_NavAreaBuildPath(nav1, nav2, distance, TEAM_INFECTED, false) && GetVectorDistance(fSurvivorPos, fSpawnPos, true) >= Pow(g_fSpawnDistanceMin, 2.0) && nav1 != nav2)
        {
            if (iZombieClass > 0 && !HasReachedLimit(iZombieClass) && CheckSIOption(iZombieClass))
            {
                if (IsTeleport && g_iTeleportIndex <= 0)
                    return false;

                if (!IsTeleport && g_iSpawnMaxCount <= 0)
                    return false;

                int entityindex;
                if (g_bSIPoolAvailable)
                    entityindex = g_hSIPool.RequestSIBot(iZombieClass, fSpawnPos);
                else entityindex = L4D2_SpawnSpecial(iZombieClass, fSpawnPos, view_as<float>({ 0.0, 0.0, 0.0 }));

                // Debug_Print("请求%d特感，生成：%d", iZombieClass, entityindex);
                if (IsValidEntity(entityindex) && IsValidEdict(entityindex))
                {
                    // aSpawnNavList.Push(nav1);
                    // Debug_Print("<nav记录> 当前入队nav：%d，当前队列长度：%d", nav1, aSpawnNavList.Length);
                    if (IsInfectedBot(entityindex) && IsPlayerAlive(entityindex))
                        return true;
                    else
                    {
#if DEBUG
                        Debug_Print("生成错误");
#endif
                        RemoveEntity(entityindex);
                        return false;
                    }
                }
            }
        }
    }
    return false;
}

// 当前在场的某种特感种类数量达到 Cvar 限制，但因为刷新一个特感，出队此元素，之后再入队相同特感元素，则会刷不出来，需要处理重复情况，如果队列长度大于 1 且索引大于 0，说明队列存在
// 首非零元，直接擦除队首元素并令队列索引 -1 即可，时间复杂度为 O(1)，如果队列中只有一个元素，则循环 1-6 的特感种类替换此元素（一般不会出现），时间复杂度为 O(n)
// 如：当前存在 2 个 Smoker 未死亡，Smoker 的 Cvar 限制为 2 ，这时入队一个 Smoker 元素，则会导致无法刷出特感
#if DEBUG
void ReachedLimit(int type)
#else
void ReachedLimit()
#endif
{
    if (aSpawnQueue.Length > 1 && g_iQueueIndex > 0)
    {
#if DEBUG
        Debug_Print("%s上限已到，无法生成，且队列不为空，删除第一个队列元素", InfectedName[type]);
#endif
        aSpawnQueue.Erase(0);
        g_iQueueIndex -= 1;
    }
    else
        for (int i = 1; i <= 6; i++)
            if (CheckSIOption(i) && !HasReachedLimit(i))
            {
#if DEBUG
                Debug_Print("%s上限已到，无法生成，当前队列为空，遍历1-6类型发现%s类型未满", InfectedName[type], InfectedName[i]);
#endif
                aSpawnQueue.Set(0, i, 0, false);
            }
}

int CheckSIOption(int type)
{
    switch (type)
    {
        case 1:
            return ENABLE_SMOKER & g_iEnableSIoption;
        case 2:
            return ENABLE_BOOMER & g_iEnableSIoption;
        case 3:
            return ENABLE_HUNTER & g_iEnableSIoption;
        case 4:
            return ENABLE_SPITTER & g_iEnableSIoption;
        case 5:
            return ENABLE_JOCKEY & g_iEnableSIoption;
        case 6:
            return ENABLE_CHARGER & g_iEnableSIoption;
    }
    return 0;
}

// 当前某种特感数量是否达到 Convar 值限制
bool HasReachedLimit(int zombieclass)
{
    int count = 0;
    static char convar[16];
    for (int infected = 1; infected <= MaxClients; infected++)
        if (IsClientConnected(infected) && IsClientInGame(infected) && IsPlayerAlive(infected) && GetEntProp(infected, Prop_Send, "m_zombieClass") == zombieclass)
            count += 1;

    if ((g_hAllChargerMode.BoolValue || g_hAllHunterMode.BoolValue) && count == g_iSiLimit)
        return true;
    else if ((g_hAllChargerMode.BoolValue || g_hAllHunterMode.BoolValue) && count < g_iSiLimit)
        return false;

    FormatEx(convar, sizeof(convar), "z_%s_limit\0", InfectedName[zombieclass]);
    // if (count == GetConVarInt(FindConVar(convar)))
    // {
    //     return true;
    // }
    // else
    // {
    //     return false;
    // }
    return count == GetConVarInt(FindConVar(convar));
}

#if DEBUG
void print_type(int iType, float SpawnDistance, bool Isteleport = false)
{
    if (iType >= 1 && iType <= 6)
    {
        Debug_Print(" %s生成一只%s，当前%s数量：%d,特感总数量 %d, 真实特感数量：%d, 找位最大单位距离：%f", Isteleport ? "传送" : "", InfectedName[iType], InfectedName[iType], g_iSINum[iType - 1], g_iTotalSINum, GetCurrentSINum(), SpawnDistance);
    }
}
#endif

// 初始 & 动态刷特时钟
Action SpawnFirstInfected(Handle timer)
{
    if (!g_bIsLate)
    {
        g_bIsLate = true;
        //首先触发一次刷特，然后每1s检测
        g_hCheckShouldSpawnOrNot = CreateTimer(1.0, CheckShouldSpawnOrNot, _, TIMER_REPEAT);
        SpawnInfectedSettings();
        if (g_bTeleportSi)
            g_hTeleHandle = CreateTimer(1.0, Timer_PositionSi, _, TIMER_REPEAT);
    }
    return Plugin_Stop;
}

Action SpawnNewInfected(Handle timer)
{
    SpawnInfectedSettings();
    g_hSpawnProcess = INVALID_HANDLE;
    return Plugin_Stop;
}

void SpawnInfectedSettings()
{
    if (g_bIsLate)
    {
        g_iSurvivorNum = 0;
        g_iLastSpawnTime = 0;
        g_iBaitTimeCheckTime = 0;
        g_iLadderBaitTimeCheckTime = 0;
        for (int client = 1; client <= MaxClients; client++)
            if (IsValidSurvivor(client) && IsPlayerAlive(client))
            {
                g_iSurvivors[g_iSurvivorNum] = client;
                g_iSurvivorNum += 1;
            }

        g_fSpawnDistance = g_fSpawnDistanceMin;
        /*
        //优化性能，每波刷新前清除aSpawnNavList队列中的值，但是如果刷特时间很短，这个优化估计起的作用不大
        if(g_iSpawnMaxCount == 0)
        {
            aSpawnNavList.Clear();
        }
        */

        g_iSpawnMaxCount += g_iSiLimit;
        g_bShouldCheck = true;
        g_iWaveTime++;
        g_fLastSISpawnAurSurFlow = GetSurAvrFlow();

#if DEBUG
        Debug_Print("开始第%d波刷特", g_iWaveTime);
#endif

        // 当一定时间内刷不出特感，触发时钟使 g_iSpawnMaxCount 超过 g_iSiLimit 值时，最多允许刷出 g_iSiLimit + 2 只特感，防止连续刷 2-3 波的情况
        if (g_iSiLimit < g_iSpawnMaxCount)
        {
            g_iSpawnMaxCount = g_iSiLimit;
#if DEBUG
            Debug_Print("当前特感数量达到上限");
#endif
        }
    }
}

public void OnUnpause()
{
    if (g_hSpawnProcess == INVALID_HANDLE)
    {
#if DEBUG
        Debug_Print("解除暂停，原先一波刷特进程已经在处理，下一波刷特是%.2f秒后", g_fUnpauseNextSpawnTime);
#endif
        g_hSpawnProcess = CreateTimer(g_fUnpauseNextSpawnTime, SpawnNewInfected, _, TIMER_REPEAT);
    }
}

// 判断生还是否在Bait，根据Bait不同情况返回不同值
// 1 梯子Bait
// 2 不推进Bait
// 3 生还密度过于集中
int IsSurvivorBait()
{ 
    // 前置条件，没有坦克或者1个生还倒地的情况
    //if( intensity >= g_fSIAttackIntent || IsAnyTankOrAboveHalfSurvivorDownOrDied() || IsPanicEventInProgress())
    if( IsAnyTankOrAboveHalfSurvivorDownOrDied(1) || g_iHordeStatus)
    {
#if TESTBUG
    Debug_Print("[前置条件]未满足");
#endif 
        g_iLadderBaitTimeCheckTime = 0;
        return 0;
    }
    // 条件1：如果玩家平均密度低于200而且附近有梯子，判断生还在Bait
    float SurAvrDistance = GetSurAvrDistance();
    bool ladder = IsLadderArround(GetRandomSurvivor(), LadderDetectDistance);
#if TESTBUG
    Debug_Print("条件1：[生还密度]%f     [附近是否有梯子]%d", SurAvrDistance, ladder);
#endif 
    if( SurAvrDistance > 0 && SurAvrDistance<= BaitDistance && g_iTotalSINum <= RoundToFloor(g_iSiLimit / 3.0) && ladder)
    {
        g_iLadderBaitTimeCheckTime += 1;
    }
    // 条件2：如果玩家两个回合推进没有超过设定的进度权重而且生还者平均密度低于200，特感小于特感数量/3的情况
    float flow = GetSurAvrFlow();
#if TESTBUG
    Debug_Print("条件2：[当前进度]%f [最后一次特感生成时生还者进度]%f [当前特感数量]%d(%d) [生还密度]%f", flow, g_fLastSISpawnAurSurFlow, g_iTotalSINum, RoundToFloor(g_iSiLimit / 3.0) + 1, SurAvrDistance);
#endif 
    if( flow != 0 && flow - g_fLastSISpawnAurSurFlow <= g_fBaitFlow && SurAvrDistance <= BaitDistance && g_iTotalSINum <= RoundToFloor(g_iSiLimit / 3.0) + 1)
    {
        return 2;
    }
    return 0;
}

void PauseTimer()
{
    if (g_hSpawnProcess != INVALID_HANDLE)
    {
        g_fUnpauseNextSpawnTime = g_fSiInterval - (GetGameTime() - g_fLastSISpawnStartTime);
#if TESTBUG
    Debug_Print("暂停%s刷特进程，刷特进程将由抗诱饵模块接管，原本刷特时间将在%.2f秒后", g_bAutoSpawnTimeControl?"自动":"固定", g_fUnpauseNextSpawnTime);
#endif
        KillTimer(g_hSpawnProcess);
        g_hSpawnProcess = INVALID_HANDLE;
    }
}

void UnPauseTimer(float time = 0.0)
{
    if (g_hSpawnProcess == INVALID_HANDLE)
    {
        if(time != 0.0)
        {
#if TESTBUG
    Debug_Print("恢复刷特，下次刷特时间为%.2f秒后，跳过自动刷特系统调度, 总真实刷特时间为 %.2f 秒", time, g_iLastSpawnTime + time);
#endif
            g_hSpawnProcess = CreateTimer(time, SpawnNewInfected, _, TIMER_REPEAT);
        }
        else
        {
#if TESTBUG
    Debug_Print("恢复刷特，下次刷特时间为%.2f秒后，跳过自动刷特系统调度, 总真实刷特时间为 %.2f 秒", g_fUnpauseNextSpawnTime, g_iLastSpawnTime + g_fUnpauseNextSpawnTime);
#endif
            g_hSpawnProcess = CreateTimer(g_fUnpauseNextSpawnTime, SpawnNewInfected, _, TIMER_REPEAT);
        }
            
    }
}

Action CheckShouldSpawnOrNot(Handle timer)
{
    if (g_bPauseSystemAvailable && IsInPause())
    {
#if DEBUG
        Debug_Print("处于暂停状态，停止刷特");
#endif
        if (g_hSpawnProcess != INVALID_HANDLE)
        {
            g_fUnpauseNextSpawnTime = g_fSiInterval - (GetGameTime() - g_fLastSISpawnStartTime);
            KillTimer(g_hSpawnProcess);
            g_hSpawnProcess = INVALID_HANDLE;
        }
        return Plugin_Continue;
    } 

    g_iLastSpawnTime++;
    if (!g_bIsLate) return Plugin_Stop;
    // 如果抗诱饵模式开启，而且时间已经超过1半的刷特时间
    if (g_bAntiBaitMode) {
        // 刷特线程已经启动
        if (!g_bShouldCheck && g_iLastSpawnTime > RoundToFloor(g_fSiInterval / 2) + 2) {
            int result = IsSurvivorBait();
    #if TESTBUG
            Debug_Print("IsSurvivorBait检测结果为%d", result);
    #endif
            if (result == 0 && g_iBaitTimeCheckTime != -10) {
                // 处理bait时间检查时间的减少和边界条件
                g_iBaitTimeCheckTime = (g_iBaitTimeCheckTime > 2) ? 2 : g_iBaitTimeCheckTime - 1;
                if (g_iBaitTimeCheckTime < -1) {
                    g_iBaitTimeCheckTime = -1;
                }
    #if TESTBUG
                    Debug_Print("未检测到生还者Bait，g_iBaitTimeCheckTime为 %d", g_iBaitTimeCheckTime);
    #endif
            } else if (result == 2) {
                // 增加bait时间检查时间
                g_iBaitTimeCheckTime++;
                // 检测超过4次,暂停计时器
                if (g_iBaitTimeCheckTime > 3 && g_hSpawnProcess != INVALID_HANDLE) {
                    PauseTimer();
                }
                // 检测超过6次生成普通僵尸
                if (g_iBaitTimeCheckTime > 6 && g_iBaitTimeCheckTime <= 26) {
                    SpawnCommonInfect(2);
    #if TESTBUG
                    Debug_Print("停刷，停刷超过%d次, 刷2个小僵尸，继续停刷", g_iBaitTimeCheckTime);
    #endif
                }
            }
            // bait时间检查时间为-1且计时器无效，恢复计时器
            if (g_iBaitTimeCheckTime == -1 && g_hSpawnProcess == INVALID_HANDLE) {
                UnPauseTimer(1.0);
    #if TESTBUG
                Debug_Print("g_iBaitTimeCheckTime==-1，满足，1秒后恢复刷特");
    #endif
                g_iBaitTimeCheckTime = -10;
            }
            /*
            // 超过设定时间1.8倍，强制1秒后刷特
            if (g_iLastSpawnTime >= RoundToFloor(g_fSiInterval * 1.8) && g_hSpawnProcess == INVALID_HANDLE) {
                // 只有在 g_iBaitTimeCheckTime < 3 时才强制恢复刷特
                if (g_iBaitTimeCheckTime < 3) {
                    UnPauseTimer(1.0);
    #if TESTBUG
                    Debug_Print("超过设定时间1.8倍，强制1秒后刷特");
    #endif
                }
            }
            */
            // 如果刷特进程等于无效句柄，就继续检测
            //if (g_hSpawnProcess == INVALID_HANDLE) return Plugin_Continue;
        }
    }
    /*
    // 长时间卡住，重启一下刷特进程
    if (g_iLastSpawnTime > RoundToFloor(2 * g_fSiInterval) + 4 && !g_bShouldCheck && g_hSpawnProcess == INVALID_HANDLE) {
        KillTimer(g_hSpawnProcess);
        #if TESTBUG
            Debug_Print("长时间卡住，重置刷特线程");
        #endif
        g_hSpawnProcess = INVALID_HANDLE;
        UnPauseTimer(1.0);
    }
    */
    

    /*if (g_bAntiBaitMode) {
        if (!g_bShouldCheck || g_hSpawnProcess != INVALID_HANDLE) return Plugin_Continue;
    } else {
        if (!g_bShouldCheck && g_hSpawnProcess != INVALID_HANDLE) return Plugin_Continue;
    }*/

    if (!g_bShouldCheck || g_hSpawnProcess != INVALID_HANDLE) return Plugin_Continue;

  
    if (FindConVar("survivor_limit").IntValue >= 2 && IsAnyTankOrAboveHalfSurvivorDownOrDied() && g_iLastSpawnTime < RoundToFloor(g_fSiInterval / 2)) return Plugin_Continue;
    //防止0s情况下spitter无法快速踢出导致的特感越刷越少问题
    /*
    if (g_iEnableSIoption & ENABLE_SPITTER && g_iLastSpawnTime < 4 && !g_bSIPoolAvailable)    // 使用 SIPool 后无此问题
    {
        Debug_Print("因为可以刷spitter，所以最低4秒起刷，不然容易造成特感数量统计错误，特感生成不出来");
        return Plugin_Continue;
    }
    */
    if ((g_iEnableSIoption & ENABLE_SPITTER) && g_iLastSpawnTime < 4 && !g_bSIPoolAvailable)
    {
#if DEBUG
        //Debug_Print("因为可以刷spitter，所以最低4秒起刷，不然容易造成特感数量统计错误，特感生成不出来");
#endif
        return Plugin_Continue;
    }

    if (!g_bAutoSpawnTimeControl)
    {
        if (g_iSpawnMaxCount == g_iSiLimit)
        {
#if DEBUG
            
            Debug_Print("固定增时系统因为等待刷特数量达到上限，暂停刷特, 总用时：%.1f秒", g_iLastSpawnTime + g_fSiInterval);
#endif
            g_iLastSpawnTime = 0;
        }
        else
        {
#if DEBUG
            Debug_Print("固定增时系统开始新一波刷特, 总用时：%.1f秒", g_iLastSpawnTime + g_fSiInterval);
#endif
            g_bShouldCheck = false;
            g_hSpawnProcess = CreateTimer(g_fSiInterval * 1.5, SpawnNewInfected, _, TIMER_REPEAT);
        }
    }
    else if ((IsAllKillersDown() && g_iSpawnMaxCount == 0) || (g_iTotalSINum <= (RoundToFloor(g_iSiLimit / 4.0) + 1) && g_iSpawnMaxCount == 0) || (g_iLastSpawnTime >= g_fSiInterval * 0.5))
    {
        if (g_iSpawnMaxCount == g_iSiLimit)
        {
#if DEBUG
            Debug_Print("自动增时系统因为等待刷特数量达到上限，暂停刷特, 总用时：%.1f秒", g_iLastSpawnTime + g_fSiInterval);
#endif
            g_iLastSpawnTime = 0;
        }
        else
        {
#if DEBUG
            Debug_Print("自动增时系统开始新一波刷特, 总用时：%.1f秒", g_iLastSpawnTime + g_fSiInterval);
#endif
            g_bShouldCheck = false;
            g_hSpawnProcess = CreateTimer(g_fSiInterval, SpawnNewInfected, _, TIMER_REPEAT);
        }
    }
    g_fLastSISpawnStartTime = GetGameTime();
    return Plugin_Continue;
}

//是否存在非克、舌头、口水、胖子存活
bool IsAllKillersDown()
{
    return (g_iSINum[view_as<int>(ZC_CHARGER) - 1]
            + g_iSINum[view_as<int>(ZC_HUNTER) - 1]
            + g_iSINum[view_as<int>(ZC_JOCKEY)] - 1)
        == 0;
}

stock void BypassAndExecuteCommand(char[] strCommand)
{
    int flags = GetCommandFlags(strCommand);
    SetCommandFlags(strCommand, flags & ~FCVAR_CHEAT);
    FakeClientCommand(GetRandomSurvivor(), "%s", strCommand);
    SetCommandFlags(strCommand, flags);
}

// 开局重置特感状态
Action SafeRoomReset(Handle timer)
{
    ResetStatus();
    return Plugin_Continue;
}

void ResetStatus()
{
    g_iTotalSINum = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsInfectedBot(client) && IsPlayerAlive(client))
        {
            g_iTeleCount[client] = 0;
            int type = GetEntProp(client, Prop_Send, "m_zombieClass");
            g_iSINum[type - 1] += 1;
            g_iTotalSINum += 1;
        }
        if (IsValidSurvivor(client) && !IsPlayerAlive(client))
            L4D_RespawnPlayer(client);
    }
}

// *********************
//		   方法
// *********************
bool IsInfectedBot(int client)
{
    // if (client > 0 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_zombieClass") <= 6 && GetEntProp(client, Prop_Send, "m_zombieClass") >= 1)
    // {
    //     return true;
    // }
    // else
    // {
    //     return false;
    // }

    return client > 0 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client)
        && GetClientTeam(client) == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_zombieClass") <= 6
        && GetEntProp(client, Prop_Send, "m_zombieClass") >= 1;
}

bool IsOnValidMesh(float fReferencePos[3])
{
    Address pNavArea = L4D2Direct_GetTerrorNavArea(fReferencePos);
    // if (pNavArea != Address_Null && !(L4D_GetNavArea_SpawnAttributes(pNavArea) & CHECKPOINT))
    // {
    //     return true;
    // }
    // else
    // {
    //     return false;
    // }

    // 我真心建议这样写，可读性不比用if分支差，一个方法太长看着会很乱的
    return pNavArea != Address_Null && !((L4D_GetNavArea_SpawnAttributes(pNavArea) & CHECKPOINT));
}

stock bool ValidMeshAddFlag(float fReferencePos[3])
{
    Address pNavArea = L4D2Direct_GetTerrorNavArea(fReferencePos);
    if (pNavArea != Address_Null && !(L4D_GetNavArea_SpawnAttributes(pNavArea) & CHECKPOINT))
    {
        static int flag;
        flag = L4D_GetNavArea_AttributeFlags(pNavArea);
        flag |= NAV_SPAWN_OBSCURED;
        L4D_SetNavArea_AttributeFlags(pNavArea, flag);
        return true;
    }
    else
    {
        return false;
    }

    // 我真心建议这样写，可读性不比用if分支差，一个方法太长看着会很乱的
    //return pNavArea != Address_Null && !((L4D_GetNavArea_SpawnAttributes(pNavArea) & CHECKPOINT));
}

//判断该坐标是否可以看到生还或者距离小于g_fSpawnDistanceMin码，减少一层栈函数，增加实时性,单人模式增加2条射线模仿左右眼
stock bool PlayerVisibleTo(float targetposition[3], bool IsTeleport = false)
{
    float position[3], vAngles[3], vLookAt[3], spawnPos[3];
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientConnected(client) && IsClientInGame(client) && IsValidSurvivor(client) && IsPlayerAlive(client))
        {
            //传送的时候无视倒地或者挂边生还者的视线，检测到跑男时，也不关注被控生还者的视线
            if (IsTeleport && (IsClientIncapped(client) || (g_bPickRushMan && IsPinned(client))))
                if (!g_bIgnoreIncappedSurvivorSight)
                {
                    int sum = 0;
                    float temp[3];
                    for (int i = 0; i < MaxClients; i++)
                        if (i != client && IsValidSurvivor(i) && !IsClientIncapped(i))
                        {
                            GetClientAbsOrigin(i, temp);
                            //倒地生还者INCAPSURVIVORCHECKDIS范围内已经没有正常生还者，掠过这个人的视线判断
                            if (GetVectorDistance(temp, position, true) < Pow(INCAPSURVIVORCHECKDIS, 2.0))
                                sum++;
                        }
#if DEBUG
                    if (sum == 0)
                    {
                        Debug_Print("Teleport方法，目标位置已经不能被正常生还者所看到");
                        continue;
                    }
                    else Debug_Print("Teleport方法，目标位置依旧能被正常生还者看到，sum为：%d", sum);
#endif
                }
                else continue;

            GetClientEyePosition(client, position);
            // position[0] += 20;
            if (GetVectorDistance(targetposition, position, true) < Pow(g_fSpawnDistanceMin, 2.0))
                return true;

            MakeVectorFromPoints(targetposition, position, vLookAt);
            GetVectorAngles(vLookAt, vAngles);
            Handle trace = TR_TraceRayFilterEx(targetposition, vAngles, MASK_VISIBLE, RayType_Infinite, TraceFilter, client);
            if (TR_DidHit(trace))
            {
                static float vStart[3];
                TR_GetEndPosition(vStart, trace);
                delete trace;    // 用完就 delete，不然迟早会忘
                if ((GetVectorDistance(targetposition, vStart, false) + 75.0) >= GetVectorDistance(position, targetposition))
                    return true;
                spawnPos = targetposition;
                spawnPos[2] += 40.0;
                MakeVectorFromPoints(spawnPos, position, vLookAt);
                GetVectorAngles(vLookAt, vAngles);
                Handle trace2 = TR_TraceRayFilterEx(spawnPos, vAngles, MASK_VISIBLE, RayType_Infinite, TraceFilter, client);
                if (TR_DidHit(trace2))
                {
                    TR_GetEndPosition(vStart, trace2);
                    delete trace2;
                    if ((GetVectorDistance(spawnPos, vStart, false) + 75.0) >= GetVectorDistance(position, spawnPos))
                        return true;
                }
                else delete trace2;

                return true;
            }
            else delete trace;

            return true;
        }
    }
    return false;
}

// thanks fdxx https://github.com/fdxx/l4d2_plugins/blob/main/l4d2_si_spawn_control.sp
stock bool PlayerVisibleToSDK(float targetposition[3], bool IsTeleport = false)
{
    static float fTargetPos[3];

    float position[3];
    fTargetPos = targetposition;
    fTargetPos[2] += 62.0;    //眼睛位置

    //计算该位置是不是和所有人都相隔大于g_fSpawnDistanceMax
    int count = 0, skipcount = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client))
        {
            GetClientEyePosition(client, position);
            //传送的时候无视倒地或者挂边生还者的视线，检测到跑男时，也不关注被控生还者的视线
            if (IsTeleport && (IsClientIncapped(client) || (g_bPickRushMan && IsPinned(client))))
            {
                if (!g_bIgnoreIncappedSurvivorSight)
                {
                    int sum = 0;
                    float temp[3];
                    for (int i = 1; i <= MaxClients; i++)
                        if (i != client && IsValidSurvivor(i) && !IsClientIncapped(i))
                        {
                            GetClientAbsOrigin(i, temp);
                            //倒地生还者500范围内已经没有正常生还者，掠过这个人的视线判断
                            if (GetVectorDistance(temp, position, true) < Pow(INCAPSURVIVORCHECKDIS, 2.0))
                                sum++;
                        }

                    if (sum == 0)
                    {
#if DEBUG
                        Debug_Print("Teleport方法，目标位置已经不能被正常生还者所看到");
#endif
                        skipcount++;
                        continue;
                    }
#if DEBUG
                    else Debug_Print("Teleport方法，目标位置依旧能被正常生还者看到，sum为：%d", sum);
#endif
                }
                else
                {
                    skipcount++;
                    continue;
                }
            }
            //太近直接返回看见
            if (GetVectorDistance(targetposition, position, true) < Pow(g_fSpawnDistanceMin, 2.0))
                return true;

            //太远直接返回没看见
            if (GetVectorDistance(targetposition, position, true) >= Pow(g_fSpawnDistanceMax, 2.0))
            {
                count++;
                if (count >= (g_iSurvivorNum - skipcount))
                    return false;
            }
            if (L4D2_IsVisibleToPlayer(client, 2, 3, 0, targetposition))
                return true;
            if (L4D2_IsVisibleToPlayer(client, 2, 3, 0, fTargetPos))
                return true;
        }
    }

    return false;
}

bool IsPlayerStuck(float fSpawnPos[3])
{
    //似乎所有客户端的尺寸都一样
    static const float fClientMinSize[3] = { -16.0, -16.0, 0.0 };
    static const float fClientMaxSize[3] = { 16.0, 16.0, 72.0 };

    static bool bHit;
    static Handle hTrace;

    hTrace = TR_TraceHullFilterEx(fSpawnPos, fSpawnPos, fClientMinSize, fClientMaxSize, MASK_PLAYERSOLID, TraceFilter_Stuck);
    bHit = TR_DidHit(hTrace);

    delete hTrace;
    return bHit;
}

stock bool TraceFilter_Stuck(int entity, int contentsMask)
{
    if (entity <= MaxClients || !IsValidEntity(entity))
        return false;

    static char sClassName[20];
    GetEntityClassname(entity, sClassName, sizeof(sClassName));
    if (strcmp(sClassName, "env_physics_blocker") == 0 && !EnvBlockType(entity))
        return false;

    return true;
}

stock bool EnvBlockType(int entity)
{
    int BlockType = GetEntProp(entity, Prop_Data, "m_nBlockType");
    //阻拦ai infected
    // if (BlockType == 1 || BlockType == 2)
    //     return false;
    // else
    //     return true;
    return !(BlockType == 1 || BlockType == 2);
}

stock bool TraceFilter(int entity, int contentsMask)
{
    if (entity <= MaxClients || !IsValidEntity(entity))
        return false;

    static char sClassName[9];
    GetEntityClassname(entity, sClassName, sizeof(sClassName));
    if (strcmp(sClassName, "infected") == 0 || strcmp(sClassName, "witch") == 0)
        return false;

    return true;
}

bool IsPinned(int client)
{
    if (!(IsValidSurvivor(client) && IsPlayerAlive(client))) return false;

    return GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0
        || GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0;
}

bool IsPinningSomeone(int client)
{
    bool bIsPinning = false;
    if (IsInfectedBot(client))
    {
        if (GetEntPropEnt(client, Prop_Send, "m_tongueVictim") > 0) bIsPinning = true;
        if (GetEntPropEnt(client, Prop_Send, "m_jockeyVictim") > 0) bIsPinning = true;
        if (GetEntPropEnt(client, Prop_Send, "m_pounceVictim") > 0) bIsPinning = true;
        if (GetEntPropEnt(client, Prop_Send, "m_pummelVictim") > 0) bIsPinning = true;
        if (GetEntPropEnt(client, Prop_Send, "m_carryVictim") > 0) bIsPinning = true;
    }
    return bIsPinning;
}

bool CanBeTeleport(int client)
{
    if (IsInfectedBot(client) && IsClientInGame(client) && IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_TANK && !IsPinningSomeone(client))
    {
        // 防止无声口水 (使用 SIPool 后无此问题)
        // if (!g_bSIPoolAvailable && IsSpitter(client) && GetGameTime() - g_fSpitterSpitTime[client] < SPIT_INTERVAL)
        // return false;
        if (IsSpitter(client) && GetGameTime() - g_fSpitterSpitTime[client] < SPIT_INTERVAL)
        {
            return false;
        }

        if (GetClosetSurvivorDistance(client) < g_fSpawnDistanceMin)
            return false;

        //舌头能力检查
        if (IsAiSmoker(client) && g_bSmokerAvailable && !IsSmokerCanUseAbility(client))
            return false;

        float fPos[3];
        GetClientAbsOrigin(client, fPos);
        if (Is_Pos_Ahead(fPos))
            return false;

        return true;
    }

    return false;
}

// 5秒内以1s检测一次，5次没被看到，就可以踢出并加入传送队列
Action Timer_PositionSi(Handle timer)
{
    if (g_bPauseSystemAvailable && IsInPause())
    {
#if DEBUG
        Debug_Print("处于暂停状态，停止传送检测");
#endif
        return Plugin_Continue;
    }

    //每1s找一次跑男或者是否所有全被控
    if (CheckRushManAndAllPinned())
        return Plugin_Continue;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (CanBeTeleport(client))
        {
            float fSelfPos[3] = { 0.0 };
            GetClientEyePosition(client, fSelfPos);
            if (!PlayerVisibleToSDK(fSelfPos, true))
            {
                // 如果是跑男状态，只要1s没被看到后就能传送
                if ((g_iTeleCount[client] > g_iTeleportCheckTime || (g_bPickRushMan && g_iTeleCount[client] > 0)))
                {
                    int type = GetInfectedClass(client);
                    if (type >= 1 && type <= 6)
                    {
                        if (g_iTeleportIndex == 0)
                            g_fTeleportDistance = g_fSpawnDistanceMin;

                        aTeleportQueue.Push(type);
                        g_iTeleportIndex += 1;
                        // Debug_Print("<传送队列> %N踢出，进入传送队列，当前 <传送队列> 队列长度：%d 队列索引：%d 当前记录特感总数为：%d , 真实数量为：%d", client, aTeleportQueue.Length, g_iTeleportIndex, g_iTotalSINum, GetCurrentSINum());
                        //不再单独处理spitter防止无声口水，已经在canbeteleport处理
                        if (g_iSINum[type - 1] > 0) g_iSINum[type - 1]--;
                        else g_iSINum[type - 1] = 0;

                        if (g_iTotalSINum > 0) g_iTotalSINum--;
                        else g_iTotalSINum = 0;

                        if (g_bSIPoolAvailable)
                            g_hSIPool.ReturnSIBot(client);
                        else
                            KickClient(client, "传送刷特，踢出");

#if DEBUG
                        Debug_Print("当前 <传送队列> 队列长度：%d 队列索引：%d 当前记录特感总数为：%d , 真实数量为：%d",
                                    aTeleportQueue.Length, g_iTeleportIndex, g_iTotalSINum, GetCurrentSINum());
#endif
                        g_iTeleCount[client] = 0;
                    }
                }
                g_iTeleCount[client] += 1;
            }
            else g_iTeleCount[client] = 0;
        }
    }
    //每1s找一次攻击目标，主要用于检测跑男，正常情况ongameframe会调用找攻击目标
    g_iTargetSurvivor = GetTargetSurvivor();
    return Plugin_Continue;
}

stock int GetCurrentSINum()
{
    int sum = 0;
    for (int i = 0; i < MaxClients; i++)
        if (IsInfectedBot(i) && IsPlayerAlive(i))
            sum++;

    return sum;
}

stock bool IsSpitter(int client)
{
    // if (IsInfectedBot(client) && IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_SPITTER)
    // {
    //     return true;
    // }
    // else
    // {
    //     return false;
    // }
    return IsInfectedBot(client) && IsPlayerAlive(client) && (GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_SPITTER);
}

// 跑男定义为距离所有生还者或者特感超过RushManDistance距离
bool CheckRushManAndAllPinned()
{
    bool TempRushMan = g_bPickRushMan;
    int iSurvivors[8] = { 0 }, iSurvivorIndex = 0, PinnedNumber = 0;
    int iInfecteds[MAXPLAYERS] = { 0 }, iInfectedIndex = 0;
    float fInfectedssOrigin[MAXPLAYERS][3], fSurvivorsOrigin[8][3], OriginTemp[3];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidSurvivor(client) && IsPlayerAlive(client))
        {
            if (IsPinned(client) || IsClientIncapped(client))
                PinnedNumber++;

            GetClientAbsOrigin(client, OriginTemp);
            if (iSurvivorIndex < 8)
            {
                fSurvivorsOrigin[iSurvivorIndex] = OriginTemp;
                iSurvivors[iSurvivorIndex++] = client;
            }
        }
        else if (IsInfectedBot(client) && IsPlayerAlive(client))
        {
            iInfecteds[iInfectedIndex] = client;
            GetClientAbsOrigin(client, OriginTemp);
            fInfectedssOrigin[iInfectedIndex++] = OriginTemp;
        }
    }

    //一个人有什么跑男
    if (iSurvivorIndex == 1)
        return false;

    int target = L4D_GetHighestFlowSurvivor();
    if (iSurvivorIndex >= 1 && IsValidClient(target))
    {
        GetClientAbsOrigin(target, OriginTemp);
        bool testSurvior = false;
        if (iSurvivorIndex == 1)
            testSurvior = true;

        for (int i = 0; i < iSurvivorIndex && !testSurvior; i++)
            if (IsPinned(target) || IsClientIncapped(target) || (iSurvivors[i] != target && GetVectorDistance(fSurvivorsOrigin[i], OriginTemp, true) <= Pow(RushManDistance, 2.0)))
            {
                testSurvior = true;
                break;
            }

        if (!testSurvior || g_iTotalSINum < (g_iSiLimit / 2 + 1))
        {
            g_bPickRushMan = false;
            g_iRushManIndex = -1;
            if (TempRushMan != g_bPickRushMan)
                StartForward(g_bPickRushMan);

            return PinnedNumber == iSurvivorIndex;
        }
        else
            for (int i = 0; i < iInfectedIndex; i++)
                if (IsPinned(target) || IsClientIncapped(target) || (GetVectorDistance(fInfectedssOrigin[i], OriginTemp, true) <= Pow(RushManDistance, 2.0) * 1.3))
                {
                    g_bPickRushMan = false;
                    g_iRushManIndex = -1;
                    if (TempRushMan != g_bPickRushMan)
                        StartForward(g_bPickRushMan);

                    return PinnedNumber == iSurvivorIndex;
                }
#if DEBUG
        if (!testSurvior)
            Debug_Print("跑男由于和其他正常生还者过远触发");
        else Debug_Print("跑男由于和特感过远触发");
#endif

        g_bPickRushMan = true;
        g_iRushManIndex = target;
        if (TempRushMan != g_bPickRushMan)
            StartForward(g_bPickRushMan);
    }
    return PinnedNumber == iSurvivorIndex;
}

int GetTargetSurvivor()
{
    //如果有跑男，抓跑男
    if (g_bPickRushMan && IsValidSurvivor(g_iRushManIndex) && IsPlayerAlive(g_iRushManIndex) && !IsPinned(g_iRushManIndex))
        return g_iRushManIndex;

    //没有跑男，抓目标未满的生还者
    int iSurvivors[8] = { 0 }, iSurvivorIndex = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidSurvivor(client) && IsPlayerAlive(client) && (!IsPinned(client) || !IsClientIncapped(client)))
        {
            // 这个应该没有必要
            //g_bIsLate = true;
            if (g_bTargetSystemAvailable && IsClientReachLimit(client))
                continue;

            if (iSurvivorIndex < 8)
            {
                iSurvivors[iSurvivorIndex] = client;
                iSurvivorIndex += 1;
            }
        }
    }
    if (iSurvivorIndex > 0)
        return iSurvivors[GetRandomInt(0, iSurvivorIndex - 1)];

    return L4D_GetHighestFlowSurvivor();
}

void StartForward(bool IsRush)
{
#if DEBUG
    Debug_Print("跑男检测状态变化，发送forward");
#endif
    Call_StartForward(g_hRushManNotifyForward);    //转发触发
    Call_PushCell(IsRush);                         //按顺序将参数push进forward传参列表里
    Call_Finish();                                 //转发结束
}

stock bool IsAiSmoker(int client)
{
    // if (client && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_zombieClass") == 1 && GetEntProp(client, Prop_Send, "m_isGhost") != 1)
    // {
    //     return true;
    // }
    // else
    // {
    //     return false;
    // }

    return client && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)
        && IsFakeClient(client) && (GetClientTeam(client) == TEAM_INFECTED)
        && (GetEntProp(client, Prop_Send, "m_zombieClass") == 1) && (GetEntProp(client, Prop_Send, "m_isGhost") != 1);
}

stock bool IsAiTank(int client)
{
    // if (client && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_INFECTED && GetEntProp(client, Prop_Send, "m_zombieClass") == 8 && GetEntProp(client, Prop_Send, "m_isGhost") != 1)
    // {
    //     return true;
    // }
    // else
    // {
    //     return false;
    // }

    return client && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)
        && IsFakeClient(client) && (GetClientTeam(client) == TEAM_INFECTED)
        && (GetEntProp(client, Prop_Send, "m_zombieClass") == 8) && (GetEntProp(client, Prop_Send, "m_isGhost") != 1);
}

stock bool IsGhost(int client)
{
    return (IsValidClient(client) && view_as<bool>(GetEntProp(client, Prop_Send, "m_isGhost")));
}

//获取队列里Hunter和Charger数量
stock int getArrayHunterAndChargetNum()
{
    int count = 0;
    for (int i = 0; i < aSpawnQueue.Length; i++)
    {
        int type = aSpawnQueue.Get(i);
        if (type == 3 || type == 6)
            count++;
    }
    return count;
}

stock int getArrayDominateSINum()
{
    int count = 0;
    for (int i = 0; i < aSpawnQueue.Length; i++)
    {
        int type = aSpawnQueue.Get(i);
        if (type != 2 || type == 4)
            count++;
    }
    return count;
}

// 返回在场特感数量，根据 z_%s_limit 限制每种特感上限
bool MeetRequire(int iType)
{
    if (g_hAllChargerMode.BoolValue || g_hAllHunterMode.BoolValue)
        return true;

    GetSiLimit();
    if (iType < 1 || iType > 6) return false;
    switch (iType)
    {
        case 2:
            if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0) && ((getArrayDominateSINum() > (g_iSiLimit / 4 + 1)) || (g_iQueueIndex >= g_iSiLimit - 2)))
                return true;
        case 4:
            if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0) && ((getArrayHunterAndChargetNum() > (g_iSiLimit / 5 + 1) || (g_iQueueIndex >= g_iSiLimit - 2))))
                return true;
        default:
            if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0))
                return true;
    }
    return false;
    // if (iType == 1)
    // {
    //     if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0))
    //         return true;
    // }
    // else if (iType == 2)
    // {
    //     if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0) && ((getArrayDominateSINum() > (g_iSiLimit / 4 + 1)) || (g_iQueueIndex >= g_iSiLimit - 2)))
    //         return true;
    // }
    // else if (iType == 3)
    // {
    //     if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0))
    //         return true;
    // }
    // else if (iType == 4)
    // {
    //     if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0) && ((getArrayHunterAndChargetNum() > (g_iSiLimit / 5 + 1) || (g_iQueueIndex >= g_iSiLimit - 2))))
    //         return true;
    // }
    // else if (iType == 5)
    // {
    //     if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0))
    //         return true;
    // }
    // else if (iType == 6)
    // {
    //     if (CheckSIOption(iType) && (g_ArraySIlimit[iType - 1] > 0))
    //         return true;
    // }
    // return false;
}

// 特感种类限制数组，刷完一波特感时重新读取 Cvar 数值，重置特感种类限制数量
void GetSiLimit()
{
    g_ArraySIlimit[0] = GetConVarInt(FindConVar("z_smoker_limit"));
    g_ArraySIlimit[1] = GetConVarInt(FindConVar("z_boomer_limit"));
    g_ArraySIlimit[2] = GetConVarInt(FindConVar("z_hunter_limit"));
    g_ArraySIlimit[3] = GetConVarInt(FindConVar("z_spitter_limit"));
    g_ArraySIlimit[4] = GetConVarInt(FindConVar("z_jockey_limit"));
    g_ArraySIlimit[5] = GetConVarInt(FindConVar("z_charger_limit"));
    //删除队列里已有元素
    for (int i = 0; i < aSpawnQueue.Length; i++)
    {
        int type = aSpawnQueue.Get(i);
        if (type > 0 && type < 7)
        {
            if (g_ArraySIlimit[type - 1] > 0)
                g_ArraySIlimit[type - 1]--;
            else g_ArraySIlimit[type - 1] = 0;
        }
    }
}

// 判断一个坐标是否在当前最高路程的生还者前面
bool Is_Pos_Ahead(float refpos[3], int target = -1)
{
    int pos_flow = 0, target_flow = 0;
    Address pNowNav = L4D2Direct_GetTerrorNavArea(refpos);
    if (pNowNav == Address_Null)
        pNowNav = view_as<Address>(L4D_GetNearestNavArea(refpos, 300.0));

    pos_flow = Calculate_Flow(pNowNav);
    if (target == -1)
        target = L4D_GetHighestFlowSurvivor();

    if (IsValidSurvivor(target))
    {
        float targetpos[3] = { 0.0 };
        GetClientAbsOrigin(target, targetpos);
        Address pTargetNav = L4D2Direct_GetTerrorNavArea(targetpos);
        if (pTargetNav == Address_Null)
            pTargetNav = view_as<Address>(L4D_GetNearestNavArea(refpos, 300.0));

        target_flow = Calculate_Flow(pTargetNav);
    }
    return view_as<bool>(pos_flow >= target_flow);
}

int Calculate_Flow(Address pNavArea)
{
    float now_nav_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea) / L4D2Direct_GetMapMaxFlowDistance();
    float now_nav_promixity = now_nav_flow + g_hVsBossFlowBuffer.FloatValue / L4D2Direct_GetMapMaxFlowDistance();
    if (now_nav_promixity > 1.0)
        now_nav_promixity = 1.0;

    return RoundToNearest(now_nav_promixity * 100.0);
}

// @key：需要调整的 key 值
// @retVal：原 value 值，使用 return Plugin_Handled 覆盖
public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
    if ((strcmp(key, "cm_ShouldHurry", false) == 0) || (strcmp(key, "cm_AggressiveSpecials", false) == 0) && retVal != 1)
    {
        retVal = 1;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

stock void Debug_Print(char[] format, any...)
{
    char sTime[32];
    FormatTime(sTime, sizeof(sTime), "%I-%M-%S", GetTime());
    char sBuffer[512];
    VFormat(sBuffer, sizeof(sBuffer), format, 2);
    Format(sBuffer, sizeof(sBuffer), "[%s] %s: %s", "DEBUG", sTime, sBuffer);
    //	PrintToChatAll(sBuffer);
    PrintToConsoleAll(sBuffer);
    PrintToServer(sBuffer);
    LogToFile(sLogFile, sBuffer);
}

stock bool IsAnyTankOrAboveHalfSurvivorDownOrDied(int limit = 0)
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsAiTank(i))
            return true;
        if (IsValidSurvivor(i) && (L4D_IsPlayerIncapacitated(i) || !IsPlayerAlive(i)))
            count++;
    }
    if(limit == 0)
    {
        if (count >= RoundToCeil(FindConVar("survivor_limit").IntValue / 2.0))
        return true;
    }else{
        if (count >= limit)
        return true;
    }
    

    return false;
}

stock void CheckAllLadder()
{
	ladderList.Clear();
	char className[64] = {'\0'};
	float ladderVec[3] = {0.0}, ladderAgl[3] = {0.0}, ladderActPos[3] = {0.0}, mins[3] = {0.0}, maxs[3] = {0.0};
	for (int i = MaxClients + 1; i < GetEntityCount(); i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEntityClassname(i, className, sizeof(className));
			if (className[0] == 'f' && (strcmp(className, "func_simpleladder") == 0 || strcmp(className, "func_ladder") == 0))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", ladderVec);
				GetEntPropVector(i, Prop_Send, "m_vecMins", mins);
				GetEntPropVector(i, Prop_Send, "m_vecMaxs", maxs);
				GetEntPropVector(i, Prop_Send, "m_angRotation", ladderAgl);
				Math_RotateVector(mins, ladderAgl, mins);
				Math_RotateVector(maxs, ladderAgl, maxs);
				ladderActPos[0] = ladderVec[0] + (mins[0] + maxs[0]) * 0.5;
				ladderActPos[1] = ladderVec[1] + (mins[1] + maxs[1]) * 0.5;
				ladderActPos[2] = ladderVec[2] + (mins[2] + maxs[2]) * 0.5;
				#if TESTBUG
				{
					Debug_Print("[梯子检测系统]：梯子：%d 坐标：[%.2f, %.2f, %.2f]", i, ladderActPos[0], ladderActPos[1], ladderActPos[2]);
				}
				#endif
				ladderList.PushArray(ladderActPos);
			}
		}
	}
}

stock bool IsLadderArround(int client, float distance)
{
	float clinetPos[3] = {0.0}, curLadderPos[3] = {0.0};
	GetClientAbsOrigin(client, clinetPos);
	for (int i = 0; i < ladderList.Length; i++)
	{
		ladderList.GetArray(i, curLadderPos);
		clinetPos[2] = curLadderPos[2] = 0.0;
		if (GetVectorDistance(clinetPos, curLadderPos) <= distance)
		{
			return true;
		}
	}
	return false;
}

/**
 * Rotates a vector around its zero-point.
 * Note: As example you can rotate mins and maxs of an entity and then add its origin to mins and maxs to get its bounding box in relation to the world and its rotation.
 * When used with players use the following angle input:
 *   angles[0] = 0.0;
 *   angles[1] = 0.0;
 *   angles[2] = playerEyeAngles[1];
 *
 * @param vec 			Vector to rotate.
 * @param angles 		How to rotate the vector.
 * @param result		Output vector.
 * @noreturn
 */
stock void Math_RotateVector(const float vec[3], const float angles[3], float result[3])
{
	// First the angle/radiant calculations
	float rad[3];
	// I don't really know why, but the alpha, beta, gamma order of the angles are messed up...
	// 2 = xAxis
	// 0 = yAxis
	// 1 = zAxis
	rad[0] = DegToRad(angles[2]);
	rad[1] = DegToRad(angles[0]);
	rad[2] = DegToRad(angles[1]);

	// Pre-calc function calls
	float cosAlpha = Cosine(rad[0]);
	float sinAlpha = Sine(rad[0]);
	float cosBeta = Cosine(rad[1]);
	float sinBeta = Sine(rad[1]);
	float cosGamma = Cosine(rad[2]);
	float sinGamma = Sine(rad[2]);

	// 3D rotation matrix for more information: http://en.wikipedia.org/wiki/Rotation_matrix#In_three_dimensions
	float x = vec[0], y = vec[1], z = vec[2];
	float newX, newY, newZ;
	newY = cosAlpha*y - sinAlpha*z;
	newZ = cosAlpha*z + sinAlpha*y;
	y = newY;
	z = newZ;

	newX = cosBeta*x + sinBeta*z;
	newZ = cosBeta*z - sinBeta*x;
	x = newX;
	z = newZ;

	newX = cosGamma*x - sinGamma*y;
	newY = cosGamma*y + sinGamma*x;
	x = newX;
	y = newY;

	// Store everything...
	result[0] = x;
	result[1] = y;
	result[2] = z;
}

//用于计算生还者之间的平均距离，并计算平均数
stock float GetSurAvrDistance()
{
    float sum = 0.0;
    int SurNum = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidSurvivor(i))
        {
            SurNum += 1;
            for(int j = i + 1; j <= MaxClients; j++)
            {
                if (IsValidSurvivor(j))
                {
                    sum += GetClientDistance(i, j);
                    SurNum += 1;
                }
            }
            float result = 0.0;
            if(SurNum <= 1)
            {
                result = 0.0;
            }
            else
            {
                result = sum / ( SurNum - 1);
            }
#if TESTBUG
//    Debug_Print("生还者的平均距离为%f, sum= %.2f SurNum =%d", result, sum, SurNum);
#endif
            return result;
        }
    }
    return 0.0;
}

//用于计算生还者之间的平均进度，并计算平均数
stock float GetSurAvrFlow()
{
    float sum = 0.0;
    int SurNum = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidSurvivor(i))
        {
            SurNum += 1;
            sum += L4D2_GetVersusCompletionPlayer(i);
            for(int j = i + 1; j <= MaxClients; j++)
            {
                if (IsValidSurvivor(j))
                {
                    SurNum += 1;
                    sum += L4D2_GetVersusCompletionPlayer(j);
                }
            }
#if TESTBUG
//    Debug_Print("生还者的平均进度为%f", sum/SurNum);
#endif
            return sum / SurNum;
        }
    }
    return 0.0;
}

/**
* 生成小僵尸
* @param amount 需要生成的数量
* @return void
**/
stock void SpawnCommonInfect(int amount)
{
    float pos[3];
    for(int i = 0; i < amount; i++)
    {
        L4D_GetRandomPZSpawnPosition(0, ZC_JOCKEY, 2, pos);
        L4D_SpawnCommonInfected(pos, {0.0, 0.0, 0.0});
    }
}


/**
* 检测某 Nav Area 是否在另一块 Nav Area 路程之前
* @param source 需要检测的 Nav Area 地址
* @param target 作为目标的 Nav Area 地址
* @return bool
**/
stock static bool navIsAheadAnotherNav(Address source, Address target) {
	if (source == Address_Null || target == Address_Null) {
		return false;
	}
	return FloatCompare(L4D2Direct_GetTerrorNavAreaFlow(source), L4D2Direct_GetTerrorNavAreaFlow(target)) > 0;
}

// ========================================================Forward ============================/
// status:
// 1 无限尸潮
// 2 警报车尸潮
// 3 有限尸潮
// 4 救援关尸潮
public void L4D2_HordeStatus(int status)
{
    if(status){
        if(status == 1){
#if TESTBUG
            Debug_Print("<尸潮状态> 目前状态为在无限尸潮");
#endif    
            g_iHordeStatus = 1;        
        }
        else if(status == 2){
#if TESTBUG
            Debug_Print("<尸潮状态> 打警报车触发尸潮，10s后重置尸潮状态");
#endif
            CreateTimer(10.0, ResetHordeStatus, _, TIMER_FLAG_NO_MAPCHANGE);
            g_iHordeStatus = 2;
        }
        else if(status == 3 && g_iHordeStatus <= 2)
        {
#if TESTBUG
            Debug_Print("<尸潮状态> 有限尸潮机关，30s后重置尸潮状态");
#endif
            g_iHordeStatus = 3;
            CreateTimer(60.0, ResetHordeStatus, _, TIMER_FLAG_NO_MAPCHANGE);
        }
        else if(status == 4)
        {
#if TESTBUG
            Debug_Print("<尸潮状态> 救援尸潮");
#endif
            g_iHordeStatus = 4;
        }
    }
    else{
#if TESTBUG
            Debug_Print("<尸潮状态> 尸潮活动即将结束");
#endif
        g_iHordeStatus = 0;
    }
}

Action ResetHordeStatus(Handle timer)
{
    g_iHordeStatus = 0;
#if TESTBUG
        Debug_Print("<尸潮状态> 尸潮活动已结束，已重置尸潮状态为非无限尸潮模式");
#endif
    return Plugin_Stop;
}