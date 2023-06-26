#include "meta_utils.h"
#include "misc_utils.h"
#include <chrono>

const char* ADMIN_LIST_FILE = "svencoop/admins.txt";

map<string, int> g_admins;

#define MAX_CVARS 32

cvar_t g_cvar_data[MAX_CVARS];
int g_cvar_count = 0;

cvar_t* RegisterCVar(char* name, char* strDefaultValue, int intDefaultValue, int flags) {
	
	if (g_cvar_count >= MAX_CVARS) {
		println("Failed to add cvar '%s'. Increase MAX_CVARS and recompile.", name);
		return NULL;
	}

	g_cvar_data[g_cvar_count].name = name;
	g_cvar_data[g_cvar_count].string = strDefaultValue;
	g_cvar_data[g_cvar_count].flags = flags | FCVAR_EXTDLL;
	g_cvar_data[g_cvar_count].value = intDefaultValue;
	g_cvar_data[g_cvar_count].next = NULL;

	CVAR_REGISTER(&g_cvar_data[g_cvar_count]);

	g_cvar_count++;

	return CVAR_GET_POINTER(name);
}

bool cgetline(FILE* file, string& output) {
	static char buffer[4096];

	if (fgets(buffer, sizeof(buffer), file)) {
		output = string(buffer);
		if (output[output.length() - 1] == '\n') {
			output = output.substr(0, output.length() - 1);
		}
		return true;
	}

	return false;
}

void LoadAdminList() {
	g_admins.clear();
	FILE* file = fopen(ADMIN_LIST_FILE, "r");

	if (!file) {
		string text = string("[Radio] Failed to open: ") + ADMIN_LIST_FILE + "\n";
		println(text);
		logln(text);
		return;
	}

	string line;
	while (cgetline(file, line)) {
		if (line.empty()) {
			continue;
		}

		// strip comments
		int endPos = line.find_first_of(" \t#/\n");
		string steamId = trimSpaces(line.substr(0, endPos));

		if (steamId.length() < 1) {
			continue;
		}

		int adminLevel = ADMIN_YES;

		if (steamId[0] == '*') {
			adminLevel = ADMIN_OWNER;
			steamId = steamId.substr(1);
		}

		g_admins[steamId] = adminLevel;
	}

	println(UTIL_VarArgs("[Radio] Loaded %d admin(s) from file", g_admins.size()));

	fclose(file);
}

int AdminLevel(edict_t* plr) {
	string steamId = (*g_engfuncs.pfnGetPlayerAuthId)(plr);

	if (!IS_DEDICATED_SERVER()) {
		if (ENTINDEX(plr) == 1) {
			return ADMIN_OWNER; // listen server owner is always the first player to join (I hope)
		}
	}

	if (g_admins.find(steamId) != g_admins.end()) {
		return g_admins[steamId];
	}
	
	return ADMIN_NO;
}

CommandArgs::CommandArgs() {
	
}

void CommandArgs::loadArgs() {
	isConsoleCmd = toLowerCase(CMD_ARGV(0)) != "say";

	string argStr = CMD_ARGC() > 1 ? CMD_ARGS() : "";

	if (isConsoleCmd) {
		argStr = CMD_ARGV(0) + string(" ") + argStr;
	}

	if (!isConsoleCmd && argStr.length() > 2 && argStr[0] == '\"' && argStr[argStr.length() - 1] == '\"') {
		argStr = argStr.substr(1, argStr.length() - 2); // strip surrounding quotes
	}

	while (!argStr.empty()) {
		// strip spaces
		argStr = trimSpaces(argStr);


		if (argStr[0] == '\"') { // quoted argument (include the spaces between quotes)
			argStr = argStr.substr(1);
			int endQuote = argStr.find("\"");

			if (endQuote == -1) {
				args.push_back(argStr);
				break;
			}

			args.push_back(argStr.substr(0, endQuote));
			argStr = argStr.substr(endQuote + 1);
		}
		else {
			// normal argument, separate by space
			int nextSpace = argStr.find(" ");

			if (nextSpace == -1) {
				args.push_back(argStr);
				break;
			}

			args.push_back(argStr.substr(0, nextSpace));
			argStr = argStr.substr(nextSpace + 1);
		}
	}
}

string CommandArgs::ArgV(int idx) {
	if (idx >= 0 && idx < args.size()) {
		return args[idx];
	}

	return "";
}

int CommandArgs::ArgC() {
	return args.size();
}

string CommandArgs::getFullCommand() {
	string str = ArgV(0);

	for (int i = 1; i < args.size(); i++) {
		str += " " + args[i];
	}

	return str;
}

using namespace std::chrono;

uint64_t getEpochMillis() {
	return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

double TimeDifference(uint64_t start, uint64_t end) {
	if (end > start) {
		return (end - start) / 1000.0;
	}
	else {
		return -((start - end) / 1000.0);
	}
}