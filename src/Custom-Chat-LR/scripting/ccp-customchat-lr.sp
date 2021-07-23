#pragma newdecls required

#define INCLUDE_RIPJSON

#include <ccprocessor>
#include <lvl_ranks>
#include <ccprocessor_pkg>
#include <clientprefs>

public Plugin myinfo = 
{
    name = "[CCP] Custom Chat <LR>",
    author = "nullent?",
    description = "...",
    version = "1.0.2",
    url = "discord.gg/ChTyPUG"
};

static const char pkgKey[] = "level_ranks_chat";

int levels[BIND_MAX];

Cookie g_cLEVEL;

bool g_bLate;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    g_bLate = late;
    return APLRes_Success;
}

public void OnPluginStart() {
    LoadTranslations("ccp_core.phrases");
    LoadTranslations("ccp_lvlranks.phrases");

    LR_Hook(LR_OnPlayerLoaded, OnPlayerLoaded);

    RegConsoleCmd("sm_lvlchat", cmduse);

    manageConVars();

    g_cLEVEL = new Cookie(pkgKey, NULL_STRING, CookieAccess_Private);
}

void manageConVars(bool bCreate = true) {
    char szBuffer[128];

    for(int i; i < BIND_MAX; i++) {
        FormatBind("ccp_lr_", i, 'l', szBuffer, sizeof(szBuffer)/2);
        if(bCreate){
            Format(szBuffer[strlen(szBuffer)+1], sizeof(szBuffer), "Priority level for %s", szBinds[i]);
            CreateConVar(szBuffer, "1", szBuffer[strlen(szBuffer)+1], _, true, 1.0).AddChangeHook(onChange);
        } else {
            onChange(FindConVar(szBuffer), NULL_STRING, NULL_STRING);
        }
    }
    
    if(bCreate) {
        AutoExecConfig(true, "ccp_lrchat", "ccprocessor");
    }
}

public void onChange(ConVar convar, const char[] oldVal, const char[] newVal)
{
    char szBuffer[64];
    convar.GetName(szBuffer, sizeof(szBuffer));

    int part = BindFromString(szBuffer);
    if(part == BIND_MAX)
        return;
    
    levels[part] = convar.IntValue;
}

public void OnPlayerLoaded(int iClient, int iAccountID) {
    ccp_OnPackageAvailable(iClient, ccp_GetPackage(iClient));
}

public void ccp_OnPackageAvailable(int iClient, Handle hPkg) {
    if(!hPkg) {
        return;
    }

    JSONObject pkg = asJSONO(hPkg);

    if(!iClient) {
        static char config[MESSAGE_LENGTH] = "configs/ccprocessor/level-ranks/chat.json";

        if(config[0] == 'c') {
            BuildPath(Path_SM, config, sizeof(config), config);
        }

        if(!FileExists(config)) {
            SetFailState("Config file is not exists: %s", config);
        }
        
        JSONArray objArr = JSONArray.FromFile(config, 0);
        pkg.Set(pkgKey, objArr);

        delete objArr;
    } else if(pkg.HasKey("auth")) {
        JSONObject obj;

        if(pkg.HasKey(pkgKey) && pkg.HasKey("cloud")) {
            obj = asJSONO(pkg.Get(pkgKey));
            if(obj.GetInt("level") <= LR_GetClientInfo(iClient, ST_RANK)) {
                delete obj;
                return;
            }

            delete obj;

            pkg.Remove(pkgKey);
        }

        obj = ReadCookieValue(iClient);
        if(obj) {
            pkg.Set(pkgKey, obj);
        }
        
        delete obj;
    }

}

public void ccp_OnPackageUpdated(int iClient, Handle jsonObj, Handle hCaller) {
    char szName[NAME_LENGTH];
    GetPluginFilename(hCaller, szName, sizeof(szName));

    // ccp-cloud.sp
    if(StrContains(szName, "ccp-cloud", false) == -1) {
        return;
    }

    ccp_OnPackageAvailable(iClient, jsonObj);
}

JSONObject ReadCookieValue(int iClient) {
    char szValue[MESSAGE_LENGTH];
    GetClientCookie(iClient, g_cLEVEL, szValue, sizeof(szValue));

    if(!szValue[0]) {
        return null;
    }

    int level = StringToInt(szValue);

    JSONArray objItems = asJSONA(asJSONO(ccp_GetPackage(0)).Get(pkgKey));
    JSONObject obj;

    for(int i; i < objItems.Length; i++) {
        obj = asJSONO(objItems.Get(i));
        if(!obj) {
            continue;
        }

        if(obj.GetInt("level") == level) {
            break;
        }
        
        delete obj;
    }

    delete objItems;
    return obj;
}

public void OnMapStart() {
    cc_proc_APIHandShake(cc_get_APIKey());
    manageConVars(false);

    if(g_bLate) {
        g_bLate = false;
        ccp_OnPackageAvailable(0, ccp_GetPackage(0));

        for(int i = 1; i <= MaxClients; i++) {
            if(IsClientInGame(i) && !IsFakeClient(i)) {
                OnPlayerLoaded(i, LR_GetClientInfo(i, ST_RANK));
            }
        }
    }
}

Action cmduse(int iClient, int args) {
    Menu hMenu;

    if(!iClient || !IsClientConnected(iClient)) {
        return Plugin_Handled;
    }

    if(!ccp_GetPackage(iClient)) {
        PrintToChat(iClient, "%T", "auth_failed", iClient);
        return Plugin_Handled;
    }

    JSONArray objItems = asJSONA(asJSONO(ccp_GetPackage(0)).Get(pkgKey));

    if((hMenu = RankMenu(iClient, objItems))) {
        hMenu.Display(iClient, MENU_TIME_FOREVER);
    }

    delete objItems;

    return Plugin_Handled;
}

Menu RankMenu(int iClient, JSONArray objItems) {
    Menu hMenu;

    if(!objItems || !objItems.Length) {
        return hMenu;
    }

    int iClientLevel = LR_GetClientInfo(iClient, ST_RANK);

    char szBuffer[MESSAGE_LENGTH];
    FormatEx(szBuffer, sizeof(szBuffer), "%T", "rankmenu_title_tag", iClient);

    hMenu = new Menu(RankMenu_CallBack);
    hMenu.SetTitle("%T \n \n", "rankmenu_title", iClient, szBuffer);

    JSONObject objItem;
    for(int i; i < objItems.Length; i++) {
        objItem = asJSONO(objItems.Get(i));

        if(!objItem) {
            continue;
        }

        if(objItem.GetInt("level") <= iClientLevel) {
            objItem.GetString("itemName", szBuffer, sizeof(szBuffer));
            Format(szBuffer, sizeof(szBuffer), "%c%T", i+1, szBuffer, iClient);

            hMenu.AddItem(szBuffer, szBuffer[1]);
        }

        delete objItem;
    }


    if(hMenu) {
        hMenu.ExitButton = true;
        hMenu.ExitBackButton = false;
    }

    return hMenu; 
}

public int RankMenu_CallBack(Menu hMenu, MenuAction action, int iClient, int option) {
    switch(action) {
        case MenuAction_End: {
            delete hMenu;
        }

        case MenuAction_Select: {
            char szBuffer[MESSAGE_LENGTH];
            hMenu.GetItem(option, szBuffer, sizeof(szBuffer));

            int index = szBuffer[0] - 1;
            JSONArray   objItems    =   asJSONA(asJSONO(ccp_GetPackage(0)).Get(pkgKey));
            JSONObject  objItem     =   asJSONO(objItems.Get(index));
            JSONObject  objModel    =   asJSONO(ccp_GetPackage(iClient));
            
            objModel = (objModel.HasKey(pkgKey)) ? asJSONO(objModel.Get(pkgKey)) : null;

            Menu hRank = RankInfo(iClient, objModel, index, objItem);

            if(!hRank) {
                PrintToChat(iClient, "%T", "some_wrong", iClient);
                RankMenu(iClient, objItems).Display(iClient, MENU_TIME_FOREVER);
            } else hRank.Display(iClient, MENU_TIME_FOREVER);

            delete objItem;
            delete objItems;
            delete objModel;
        }
    }
}

Menu RankInfo(int iClient, JSONObject objModel, int index, JSONObject objItem) {
    Menu hMenu;

    if(!objItem) {
        return hMenu;
    }

    char szBuffer[MESSAGE_LENGTH];
    FormatEx(szBuffer, sizeof(szBuffer), "%T", "rankmenu_title_tag", iClient);

    char szItem[MESSAGE_LENGTH];
    char szDesc[MESSAGE_LENGTH];
    char szBindName[MESSAGE_LENGTH];
    for(int i; i < BIND_MAX; i++) {
        if(!objItem.HasKey(szBinds[i])) {
            continue;
        }


        FormatEx(szBindName, sizeof(szBindName), "%T", szBinds[i], iClient);

        objItem.GetString(szBinds[i], szItem, sizeof(szItem));
        Format(szItem, sizeof(szItem), "%T", szItem, iClient);
        ccp_replaceColors(szItem);

        Format(
            szDesc, sizeof(szDesc), 
            "%s%s%T", 
            szDesc[0] ? szDesc : "", 
            (szDesc[0]) ? " \n" : "", 
            "item_view_pattern", iClient, szBindName, szItem
        );
    }

    objItem.GetString("itemName", szItem, sizeof(szItem));
    Format(szItem, sizeof(szItem), "%T", szItem, iClient);

    hMenu = new Menu(RankInfo_CallBack);
    hMenu.SetTitle("%T \n \n%s \n \n", "rankinfo_title", iClient, szBuffer, szItem, szDesc);

    FormatEx(szBuffer, sizeof(szBuffer), "c%c%T", index+1, "item_choose", iClient);
    hMenu.AddItem(
        szBuffer, szBuffer[2], 
        (objModel && objItem.GetInt("level") == objModel.GetInt("level"))
            ? ITEMDRAW_DISABLED
            : ITEMDRAW_DEFAULT
    );

    FormatEx(szBuffer, sizeof(szBuffer), "d%c%T", index+1, "item_disable", iClient);
    hMenu.AddItem(
        szBuffer, szBuffer[2], 
        (objModel && objItem.GetInt("level") == objModel.GetInt("level"))
            ? ITEMDRAW_DEFAULT
            : ITEMDRAW_DISABLED
    );

    hMenu.ExitBackButton = true;
    hMenu.ExitButton = true;
    return hMenu;
}

public int RankInfo_CallBack(Menu hMenu, MenuAction action, int iClient, int option) {
    switch(action) {
        case MenuAction_End: {
            delete hMenu;
        }

        case MenuAction_Cancel: {
            if(option == MenuCancel_ExitBack) {
                cmduse(iClient, 0);
            }
        }

        case MenuAction_Select: {
            char szBuffer[MESSAGE_LENGTH];
            hMenu.GetItem(option, szBuffer, sizeof(szBuffer));

            int index = szBuffer[1] - 1;
            JSONArray   objItems    =   asJSONA(asJSONO(ccp_GetPackage(0)).Get(pkgKey));
            JSONObject  objItem     =   asJSONO(objItems.Get(index));
            JSONObject  objModel    =   asJSONO(ccp_GetPackage(iClient));
            
            if(szBuffer[0] == 'd') {
                objModel.Remove(pkgKey);
                SetClientCookie(iClient, g_cLEVEL, NULL_STRING);
            } else {
                objModel.Set(pkgKey, objItem);

                FormatEx(szBuffer, sizeof(szBuffer), "%i", objItem.GetInt("level"));
                SetClientCookie(iClient, g_cLEVEL, szBuffer);
            }

            objModel = (objModel.HasKey(pkgKey)) ? asJSONO(objModel.Get(pkgKey)) : null;

            Menu hRank = RankInfo(iClient, objModel, index, objItem);

            if(!hRank) {
                PrintToChat(iClient, "%T", "some_wrong", iClient);
                RankMenu(iClient, objItems).Display(iClient, MENU_TIME_FOREVER);
            } else hRank.Display(iClient, MENU_TIME_FOREVER);

            delete objItem;
            delete objItems;
            delete objModel;
        }
    }
}

JSONObject senderModel;

public Processing cc_proc_OnNewMessage(const int[] props, int propsCount, ArrayList params) {
    char szIndent[64];
    params.GetString(0, szIndent, sizeof(szIndent));
    
    if(StrContains(szIndent, "ST") != 0 || strlen(szIndent) != 3 || !props[0]) {
        return Proc_Continue;
    } 

    senderModel = asJSONO(ccp_GetPackage(props[0]));
    if(!senderModel || !senderModel.HasKey(pkgKey)) {
        senderModel = null;
        return Proc_Continue;
    }

    senderModel = asJSONO(senderModel.Get(pkgKey));
    return Proc_Continue;
}

public Processing  cc_proc_OnRebuildString(const int[] props, int part, ArrayList params, int &level, char[] value, int size) {
    if(!senderModel) {
        return Proc_Continue;
    }

    if(levels[part] < level) {
        return Proc_Continue;
    }

    static char szValue[MESSAGE_LENGTH];
    if(!senderModel.GetString(szBinds[part], szValue, sizeof(szValue)) || !szValue[0]) {
        return Proc_Continue;
    }

    if(part == BIND_PREFIX) {
        Format(szValue, sizeof(szValue), "%T", szValue, props[2]);
    }

    level = levels[part];
    FormatEx(value, size, szValue);

    return Proc_Change;
}

public void cc_proc_OnMessageEnd(const int[] props, int propsCount, ArrayList params) {
    if(senderModel) {
        delete senderModel;
    }
}
