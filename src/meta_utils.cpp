#include "meta_utils.h"
#include "misc_utils.h"

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