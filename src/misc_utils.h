#pragma once
#include <extdll.h>
#include <string>
#include "main.h"

using namespace std;

#define MSG_ChatMsg 74
#define MSG_TextMsg 75

#define println(fmt,...) {ALERT(at_console, (char*)(std::string(fmt) + "\n").c_str(), ##__VA_ARGS__); }

string replaceString(string subject, string search, string replace);

edict_t* getPlayerByUniqueId(string id);

string getPlayerUniqueId(edict_t* plr);

bool isValidPlayer(edict_t* plr);

string trimSpaces(string s);

string toLowerCase(string str);

void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);

char* UTIL_VarArgs(char* format, ...);