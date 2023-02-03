#pragma once

#include "meta_init.h"
#include <string>
#include <vector>
#include <map>
#include <thread>
#include <algorithm>

using namespace std; // ohhh yesss

#define MAX_PLAYERS 32

#define MSG_TextMsg 75

// get a player index as a bitfield index
#define PLAYER_BIT(edt) (1 << (ENTINDEX(edt) % 32))

extern thread::id g_main_thread_id;

#define print(fmt,...) {ALERT(at_console, (char*)string(fmt).c_str(), ##__VA_ARGS__);}
#define log(fmt, ...) {ALERT(at_logged, (char*)string(fmt).c_str(), ##__VA_ARGS__);}

enum AdminLevel_t {
	ADMIN_INIT = -1,
	ADMIN_NO,
	ADMIN_YES,
	ADMIN_OWNER
};

struct CommandArgs {
	vector<string> args;
	bool isConsoleCmd;
	
	// gets current globally defined args
	CommandArgs();

	void loadArgs();

	// returns empty string if idx is out of bounds
	string ArgV(int idx);

	// return number of args
	int ArgC();

	// return entire command string
	string getFullCommand();
};

uint64_t getEpochMillis();
double TimeDifference(uint64_t start, uint64_t end);
