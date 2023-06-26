#include "main.h"

void debug_stats(edict_t* debugger) {
	int count = 0;
	int total = 0;

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		total++;
		PlayerState& state = getPlayerState(ent);
		if (state.enabled) {
			count++;
		}
	}

	ClientPrint(debugger, HUD_PRINTCONSOLE, ("\nCompensated entities (" + to_string(laggyEnts.size()) + "):\n").c_str());
	for (int i = 0; i < laggyEnts.size(); i++)
	{
		LagEnt lagEnt = laggyEnts[i];
		CBaseEntity* ent = lagEnt.h_ent;
		string cname = ent ? ent->GetClassname() : "null";
		if (ent && ent->IsPlayer()) {
			cname = STRING(ent->pev->netname);
		}

		ClientPrint(debugger, HUD_PRINTCONSOLE, ("    " + cname + ": " + to_string(lagEnt.history.size()) + " states\n").c_str());
	}

	ClientPrint(debugger, HUD_PRINTCONSOLE, ("\nHitmark-only entities (" + to_string(hitmarkEnts.size()) + "):\n    ").c_str());
	for (int i = 0; i < hitmarkEnts.size(); i++)
	{
		HitmarkEnt hitmarkEnt = hitmarkEnts[i];
		CBaseEntity* ent = hitmarkEnt.h_ent;
		string cname = ent ? ent->GetClassname() : "null";
		ClientPrint(debugger, HUD_PRINTCONSOLE, (cname + ", ").c_str());
		if (i % 8 == 0)
			ClientPrint(debugger, HUD_PRINTCONSOLE, string("\n    ").c_str());
	}

	ClientPrint(debugger, HUD_PRINTCONSOLE, ("\n\nPlayers using compensation(" + to_string(count) + " / " + to_string(total) + ") : \n").c_str());

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);

		if (state.enabled) {
			string mode = "auto";
			if (state.adjustMode == ADJUST_ADD) {
				mode = "ping +" + to_string(state.compensation) + "ms";
			}
			else if (state.adjustMode == ADJUST_SUB) {
				mode = "ping -" + to_string(state.compensation) + "ms";
			}

			string name = STRING(plr->v.netname);
			while (name.length() < 16) {
				name += " ";
			}
			mode = string("hitmarks ") + (state.hitmarker ? "ON" : "OFF") + ", debug " + to_string(state.debug) + ", " + mode;

			ClientPrint(debugger, HUD_PRINTCONSOLE, ("    " + name + ": " + mode + "\n").c_str());
		}
	}
}

bool doCommand(edict_t* plr) {
	PlayerState& state = getPlayerState(plr);
	bool isAdmin = AdminLevel(plr) >= ADMIN_YES;

	CommandArgs args = CommandArgs();
	args.loadArgs();

	string lowerArg = toLowerCase(args.ArgV(0));

	if (args.ArgC() > 0)
	{
		if (args.ArgV(0) == ".lagc") {
			if (args.ArgC() > 1) {
				string arg = args.ArgV(1);

				if (arg == "info") {
					state.debug = state.debug == 0 ? 1 : 0;
					ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation info " + string(state.debug > 0 ? "enabled" : "disabled") + "\n").c_str());
				}
				else if (arg == "x" || arg == "hitmarker") {
					state.hitmarker = !state.hitmarker;

					if (args.ArgC() > 2) {
						state.hitmarker = atoi(args.ArgV(2).c_str()) != 0;
					}

					if (state.hitmarker) {
						state.enabled = true;
					}
					ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation hitmarker " + string(state.hitmarker ? "enabled" : "disabled") + "\n").c_str());
				}
				else if (arg == "debug" && isAdmin) {
					state.enabled = true;
					state.debug = state.debug != 2 ? 2 : 0;
					ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation debug mode " + string(state.debug > 0 ? "enabled" : "disabled") + "\n").c_str());
				}
				else if (arg == "pause" && isAdmin) {
					g_enabled = false;
					ClientPrintAll(HUD_PRINTTALK, "Lag compensation plugin disabled.\n");
				}
				else if (arg == "resume" && isAdmin) {
					g_enabled = true;
					reload_ents();
					ClientPrintAll(HUD_PRINTTALK, "Lag compensation plugin enabled. Say '.lagc' for help.\n");
				}
				else if (arg == "stats") {
					debug_stats(plr);
				}
				else if (arg == "rate" && isAdmin) {
					if (args.ArgC() > 2) {
						g_update_delay = Min(atof(args.ArgV(2).c_str()), 1.0f);
						if (g_update_delay < 0) {
							g_update_delay = 0;
						}
						g_Scheduler.RemoveTimer(update_interval);
						update_interval = g_Scheduler.SetInterval(update_ent_history, g_update_delay, -1);
						ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation rate set to " + to_string(g_update_delay) + "\n").c_str());
					}
				}
				else if (arg == "test" && isAdmin) {

				}
				else if (arg == "on") {
					state.enabled = true;
					state.compensation = -1;
					ClientPrint(plr, HUD_PRINTTALK, "Lag compensation enabled (auto)\n");
				}
				else if (arg == "off") {
					state.enabled = false;
					state.compensation = 0;
					state.adjustMode = ADJUST_NONE;
					ClientPrint(plr, HUD_PRINTTALK, "Lag compensation disabled\n");
				}
				else if (arg == "toggle") {
					state.enabled = !state.enabled;
					state.compensation = 0;
					state.adjustMode = ADJUST_NONE;
					ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation " + string(state.enabled ? "enabled" : "disabled") + "\n").c_str());
				}
				else if (arg == "auto") {
					state.enabled = true;
					state.compensation = 0;
					ClientPrint(plr, HUD_PRINTTALK, "Lag compensation set to auto\n");
				}
				else {
					int adjustMode = ADJUST_ADD;

					if (arg[0] == '=') {
						adjustMode = ADJUST_NONE;
						arg = arg.substr(1);
						println("NEWARG " + arg);
					}
					else if (arg[0] == '-') {
						adjustMode = ADJUST_SUB;
						arg = arg.substr(1);
					}

					int amt = Min(atoi(arg.c_str()), int(MAX_LAG_COMPENSATION_SECONDS * 1000));
					if (amt < -1) {
						amt = -1;
					}

					state.compensation = amt;
					state.adjustMode = adjustMode;
					state.enabled = true;

					if (adjustMode == ADJUST_NONE) {
						ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation set to " + to_string(state.compensation) + "ms\n").c_str());
					}
					else {
						string prefix = adjustMode == ADJUST_ADD ? "ping + " : "ping - ";
						ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation set to " + prefix + to_string(state.compensation) + "ms\n").c_str());
					}
				}
			}
			else {
				int maxComp = int(MAX_LAG_COMPENSATION_SECONDS * 1000);
				ClientPrint(plr, HUD_PRINTCONSOLE, "-----------------------------Lag Compensation Commands-----------------------------\n\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "Lag compensation rewinds enemies so that you don't have to aim ahead of them to get a hit.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "\nType \".lagc [on/off/toggle]\" to enable or disable lag compensation.\n");

				ClientPrint(plr, HUD_PRINTCONSOLE, "\nIf you still need to aim ahead/behind enemies to hit them, then try one of these commands:\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc +X\" to increase compensation.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc -X\" to decrease compensation.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc =X\" to set a specific compensation.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc auto\" to use the default compensation.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    X = milliseconds\n");

				ClientPrint(plr, HUD_PRINTCONSOLE, "\nIf you're unsure how to adjust compensation, try these commands:\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc info\" to toggle compensation messages.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "        This will show your compensation ping when you shoot.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "        Try matching it with the ping you see in net_graph.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "        The net_graph ping might be more accurate than the scoreboard.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "        To turn on net_graph, type \"net_graph 2\" in this console.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc x [0/1]\" to toggle hit confirmations.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "        This will make it obvious when you hit a target.\n");

				if (isAdmin) {
					ClientPrint(plr, HUD_PRINTCONSOLE, "\nAdmins only:");
					ClientPrint(plr, HUD_PRINTCONSOLE, "\n    Type \".lagc debug\" to toggle compensation visualizations.\n        - This may cause extreme lag and/or desyncs!\n");
					ClientPrint(plr, HUD_PRINTCONSOLE, "    Type \".lagc [pause/resume]\" to enable or disable ths plugin.\n        - Try this if the server is lagging horribly.\n");
				}

				string mode = " (auto)";
				if (state.adjustMode == ADJUST_ADD) {
					mode = " (ping + " + to_string(state.compensation) + "ms)";
				}
				else if (state.adjustMode == ADJUST_SUB) {
					mode = " (ping - " + to_string(state.compensation) + "ms)";
				}
				if (!state.enabled) {
					mode = "";
				}

				ClientPrint(plr, HUD_PRINTCONSOLE, "\nYour settings:\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, ("    Compensation is " + string(state.enabled ? "enabled" : "disabled") + mode + "\n").c_str());
				ClientPrint(plr, HUD_PRINTCONSOLE, ("    Hitmarkers are " + string(state.hitmarker ? "enabled" : "disabled") + "\n").c_str());
				ClientPrint(plr, HUD_PRINTCONSOLE, ("    Info messages are " + string(state.debug > 0 ? "enabled" : "disabled") + "\n").c_str());

				if (!g_enabled)
					ClientPrint(plr, HUD_PRINTCONSOLE, "\nThe lag compensation plugin is currently disabled.\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "\n-----------------------------------------------------------------------------------\n");

				if (!args.isConsoleCmd) {
					if (g_enabled) {
						ClientPrint(plr, HUD_PRINTTALK, ("Lag compensation is " + string(state.enabled ? "enabled" : "disabled") + mode + "\n").c_str());
						ClientPrint(plr, HUD_PRINTTALK, "Say \".lagc [on/off/toggle]\" to enable or disable lag compensation.\n");
						ClientPrint(plr, HUD_PRINTTALK, "Say \".lagc x\" to toggle hit confirmations.\n");
					}
					else
						ClientPrint(plr, HUD_PRINTTALK, "The lag compensation plugin is currently disabled.\n");
					ClientPrint(plr, HUD_PRINTTALK, "Type \".lagc\" in console for more commands/info\n");
				}
			}
			return true;
		}
	}
	return false;
}

// called before angelscript hooks
void ClientCommand(edict_t* pEntity) {
	META_RES ret = doCommand(pEntity) ? MRES_SUPERCEDE : MRES_IGNORED;
	RETURN_META(ret);
}
