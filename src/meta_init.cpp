// functions to making porting from angelscript to metamod easier
#include <extdll.h>
#include <meta_api.h>
#include "meta_init.h"
#include <h_export.h>
#include <stdio.h>
#include <stdarg.h>

// Must provide at least one of these..
static META_FUNCTIONS gMetaFunctionTable = {
	NULL,			// pfnGetEntityAPI				HL SDK; called before game DLL
	NULL,			// pfnGetEntityAPI_Post			META; called after game DLL
	GetEntityAPI2,	// pfnGetEntityAPI2				HL SDK2; called before game DLL
	GetEntityAPI2_Post,			// pfnGetEntityAPI2_Post		META; called after game DLL
	GetNewDLLFunctions,			// pfnGetNewDLLFunctions		HL SDK2; called before game DLL
	NULL,			// pfnGetNewDLLFunctions_Post	META; called after game DLL
	GetEngineFunctions,	// pfnGetEngineFunctions	META; called before HL engine
	GetEngineFunctions_Post,			// pfnGetEngineFunctions_Post	META; called after HL engine
};

// hook tables
enginefuncs_t g_engine_hooks;
enginefuncs_t g_engine_hooks_post;
DLL_FUNCTIONS g_dll_hooks;
DLL_FUNCTIONS g_dll_hooks_post;
NEW_DLL_FUNCTIONS g_newdll_hooks;

// Global vars from metamod:
meta_globals_t* gpMetaGlobals;		// metamod globals
gamedll_funcs_t* gpGamedllFuncs;	// gameDLL function tables
mutil_funcs_t* gpMetaUtilFuncs;		// metamod utility functions

// Metamod requesting info about this plugin:
//  ifvers			(given) interface_version metamod is using
//  pPlugInfo		(requested) struct with info about plugin
//  pMetaUtilFuncs	(given) table of utility functions provided by metamod
C_DLLEXPORT int Meta_Query(char* /*ifvers */, plugin_info_t** pPlugInfo,
	mutil_funcs_t* pMetaUtilFuncs)
{
	memset(&g_engine_hooks, 0, sizeof(enginefuncs_t));
	memset(&g_dll_hooks, 0, sizeof(DLL_FUNCTIONS));
	
	// Give metamod our plugin_info struct
	*pPlugInfo = &Plugin_info;
	// Get metamod utility function table.
	gpMetaUtilFuncs = pMetaUtilFuncs;
	return(TRUE);
}

// Metamod attaching plugin to the server.
//  now				(given) current phase, ie during map, during changelevel, or at startup
//  pFunctionTable	(requested) table of function tables this plugin catches
//  pMGlobals		(given) global vars from metamod
//  pGamedllFuncs	(given) copy of function tables from game dll
C_DLLEXPORT int Meta_Attach(PLUG_LOADTIME /* now */,
META_FUNCTIONS* pFunctionTable, meta_globals_t* pMGlobals,
	gamedll_funcs_t* pGamedllFuncs)
{
	if (!pMGlobals) {
		LOG_ERROR(PLID, "Meta_Attach called with null pMGlobals");
		return(FALSE);
	}
	gpMetaGlobals = pMGlobals;
	if (!pFunctionTable) {
		LOG_ERROR(PLID, "Meta_Attach called with null pFunctionTable");
		return(FALSE);
	}
	memcpy(pFunctionTable, &gMetaFunctionTable, sizeof(META_FUNCTIONS));
	gpGamedllFuncs = pGamedllFuncs;

	PluginInit();

	return(TRUE);
}

// Metamod detaching plugin from the server.
// now		(given) current phase, ie during map, etc
// reason	(given) why detaching (refresh, console unload, forced unload, etc)
C_DLLEXPORT int Meta_Detach(PLUG_LOADTIME /* now */,
	PL_UNLOAD_REASON /* reason */)
{
	PluginExit();
	return(TRUE);
}

C_DLLEXPORT int GetEntityAPI2(DLL_FUNCTIONS* pFunctionTable, int* interfaceVersion)
{
	if (!pFunctionTable) {
		UTIL_LogPrintf("GetEntityAPI2 called with null pFunctionTable");
		return(FALSE);
	}
	else if (*interfaceVersion != INTERFACE_VERSION) {
		UTIL_LogPrintf("GetEntityAPI2 version mismatch; requested=%d ours=%d", *interfaceVersion, INTERFACE_VERSION);
		//! Tell metamod what version we had, so it can figure out who is out of date.
		*interfaceVersion = INTERFACE_VERSION;
		return(FALSE);
	}
	memcpy(pFunctionTable, &g_dll_hooks, sizeof(DLL_FUNCTIONS));
	return(TRUE);
}

C_DLLEXPORT int GetEntityAPI2_Post(DLL_FUNCTIONS* pFunctionTable, int* interfaceVersion)
{
	if (!pFunctionTable) {
		LOG_ERROR(PLID, "GetEntityAPI2_Post called with null pFunctionTable");
		return(FALSE);
	}
	else if (*interfaceVersion != INTERFACE_VERSION) {
		LOG_ERROR(PLID, "GetEntityAPI2_Post version mismatch; requested=%d ours=%d", *interfaceVersion, INTERFACE_VERSION);
		return(FALSE);
	}
	memcpy(pFunctionTable, &g_dll_hooks_post, sizeof(DLL_FUNCTIONS));
	return(TRUE);
}

C_DLLEXPORT int GetNewDLLFunctions(NEW_DLL_FUNCTIONS* pNewFunctionTable, int* interfaceVersion) {
	if (!pNewFunctionTable) {
		UTIL_LogPrintf("GetNewDLLFunctions called with null pNewFunctionTable");
		return(FALSE);
	}
	else if (*interfaceVersion != 1) {
		UTIL_LogPrintf("GetNewDLLFunctions version mismatch; requested=%d ours=%d", *interfaceVersion, ENGINE_INTERFACE_VERSION);
		// Tell metamod what version we had, so it can figure out who is out of date.
		*interfaceVersion = 1;
		return(FALSE);
	}
	memcpy(pNewFunctionTable, &g_newdll_hooks, sizeof(NEW_DLL_FUNCTIONS));
	return(TRUE);
}

C_DLLEXPORT int GetEngineFunctions(enginefuncs_t* pengfuncsFromEngine, int* interfaceVersion)
{
	if (!pengfuncsFromEngine) {
		UTIL_LogPrintf("GetEngineFunctions called with null pengfuncsFromEngine");
		return(FALSE);
	}
	else if (*interfaceVersion != ENGINE_INTERFACE_VERSION) {
		UTIL_LogPrintf("GetEngineFunctions version mismatch; requested=%d ours=%d", *interfaceVersion, ENGINE_INTERFACE_VERSION);
		// Tell metamod what version we had, so it can figure out who is out of date.
		*interfaceVersion = ENGINE_INTERFACE_VERSION;
		return(FALSE);
	}
	memcpy(pengfuncsFromEngine, &g_engine_hooks, sizeof(enginefuncs_t));
	return(TRUE);
}

C_DLLEXPORT int GetEngineFunctions_Post(enginefuncs_t* pengfuncsFromEngine, int* interfaceVersion)
{
	LOG_DEVELOPER(PLID, "called: GetEngineFunctions_Post; version=%d", *interfaceVersion);
	if (!pengfuncsFromEngine) {
		LOG_ERROR(PLID, "GetEngineFunctions_Post called with null pengfuncsFromEngine");
		return(FALSE);
	}
	else if (*interfaceVersion != ENGINE_INTERFACE_VERSION) {
		LOG_ERROR(PLID, "GetEngineFunctions_Post version mismatch; requested=%d ours=%d", *interfaceVersion, ENGINE_INTERFACE_VERSION);
		// Tell metamod what version we had, so it can figure out who is out of date.
		*interfaceVersion = ENGINE_INTERFACE_VERSION;
		return(FALSE);
	}
	memcpy(pengfuncsFromEngine, &g_engine_hooks_post, sizeof(enginefuncs_t));
	return TRUE;
}

//=========================================================
// UTIL_LogPrintf - Prints a logged message to console.
// Preceded by LOG: ( timestamp ) < message >
//=========================================================
void UTIL_LogPrintf(char* fmt, ...)
{
	va_list			argptr;
	static char		string[1024];

	va_start(argptr, fmt);
	vsnprintf(string, sizeof(string), fmt, argptr);
	va_end(argptr);

	// Print to server console
	ALERT(at_logged, "%s", string);
}


// From SDK dlls/h_export.cpp:

//! Holds engine functionality callbacks
enginefuncs_t g_engfuncs;
globalvars_t* gpGlobals;

// Receive engine function table from engine.
// This appears to be the _first_ DLL routine called by the engine, so we
// do some setup operations here.
void WINAPI GiveFnptrsToDll(enginefuncs_t* pengfuncsFromEngine, globalvars_t* pGlobals)
{
	memcpy(&g_engfuncs, pengfuncsFromEngine, sizeof(enginefuncs_t));
	gpGlobals = pGlobals;
}