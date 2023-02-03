#pragma once

// functions to making porting from angelscript to metamod easier
#include <extdll.h>
#include <meta_api.h>

// engine hook table
extern enginefuncs_t g_engine_hooks;
extern enginefuncs_t g_engine_hooks_post;

// game dll hook table
extern DLL_FUNCTIONS g_dll_hooks;
extern DLL_FUNCTIONS g_dll_hooks_post;

extern NEW_DLL_FUNCTIONS g_newdll_hooks;

void PluginInit();

void PluginExit();
