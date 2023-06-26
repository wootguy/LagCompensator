#pragma once
#include <extdll.h>
#include <string>
#include "main.h"
#include <map>

using namespace std;

#define MSG_ChatMsg 74
#define MSG_TextMsg 75

#define println(fmt,...) {ALERT(at_console, (char*)(std::string(fmt) + "\n").c_str(), ##__VA_ARGS__); }

// prevent conflicts with auto-included headers
#define Min(a,b)            (((a) < (b)) ? (a) : (b))
#define Max(a,b)           (((a) > (b)) ? (a) : (b))

string replaceString(string subject, string search, string replace);

edict_t* getPlayerByUniqueId(string id);

string getPlayerUniqueId(edict_t* plr);

bool isValidPlayer(edict_t* plr);

string trimSpaces(string s);

string toLowerCase(string str);

string vecToString(Vector vec);

void ClientPrintAll(int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);

void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);

void HudMessageAll(const hudtextparms_t& textparms, const char* pMessage, int dest = -1);

void HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage, int dest = -1);

char* UTIL_VarArgs(char* format, ...);

edict_t* CreateEntity(string cname, map<string, string> keyvalues=map<string,string>(), bool spawn = true);

void GetSequenceInfo(void* pmodel, entvars_t* pev, float* pflFrameRate, float* pflGroundSpeed);

int GetSequenceFlags(void* pmodel, entvars_t* pev);

float clampf(float val, float min, float max);

int clamp(int val, int min, int max);