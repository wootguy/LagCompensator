
CClientCommand _lagc("lagc", "Lag compensation commands", @consoleCmd );

void debug_stats(CBasePlayer@ debugger) {
	
	int count = 0;
	int total = 0;
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr is null or !plr.IsConnected())
			continue;
		
		total++;
		PlayerState@ state = getPlayerState(plr);
		if (state.enabled) {
			count++;
		}
	}
	
	g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, "\nCompensated entities (" + laggyEnts.size() + "):\n");
	for (uint i = 0; i < laggyEnts.size(); i++ )
	{
		LagEnt lagEnt = laggyEnts[i];
		CBaseEntity@ ent = lagEnt.h_ent;
		string cname = ent !is null ? string(ent.pev.classname) : "null";
		if (ent !is null and ent.IsPlayer()) {
			cname = ent.pev.netname;
		}
		
		g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, "    " + cname + ": " + lagEnt.history.size() + " states\n");
	}
	
	g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, "\nHitmark-only entities (" + hitmarkEnts.size() + "):\n    ");
	for (uint i = 0; i < hitmarkEnts.size(); i++ )
	{
		HitmarkEnt hitmarkEnt = hitmarkEnts[i];
		CBaseEntity@ ent = hitmarkEnt.h_ent;
		string cname = ent !is null ? string(ent.pev.classname) : "null";		
		g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, cname + ", ");
		if (i % 8 == 0)
			g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, "\n    ");
	}
	
	g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, '\n\nPlayers using compensation (' + count + ' / ' + total + '):\n');
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr is null or !plr.IsConnected())
			continue;
		
		PlayerState@ state = getPlayerState(plr);
		
		if (state.enabled) {
			string mode = "auto";
			if (state.adjustMode == ADJUST_ADD) {
				mode = "ping +" + state.compensation + "ms";
			} else if (state.adjustMode == ADJUST_SUB) {
				mode = "ping -" + state.compensation + "ms";
			}
			
			string name = plr.pev.netname;
			while (name.Length() < 16) {
				name += " ";
			}
			mode = "hitmarks " + (state.hitmarker ? "ON" : "OFF") + ", debug " + state.debug + ", " + mode;
				
			g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, '    ' + name + ": " + mode + "\n");
		}
	}
}

void debug_perf(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null or !plr.IsConnected()) {
		return;
	}
	
	HUDTextParams params;
	params.effect = 0;
	params.fadeinTime = 0;
	params.fadeoutTime = 0.1;
	params.holdTime = 1.5f;
	
	params.x = -1;
	params.y = 0.99;
	params.channel = 2;
	
	if (g_stat_rps > 10000) {
		params.r1 = 255;
		params.g1 = 0;
		params.b1 = 0;
	} else if (g_stat_rps > 5000) {
		params.r1 = 255;
		params.g1 = 128;
		params.b1 = 0;
	} else if (g_stat_rps > 2500) {
		params.r1 = 255;
		params.g1 = 255;
		params.b1 = 0;
	} else {
		params.r1 = 0;
		params.g1 = 255;
		params.b1 = 0;
	}
	
	
	string info = "OPS: " + g_stat_rps + ", CPS: " + g_stat_comps + "\nOps/shot: " + ((laggyEnts.size()-1) + hitmarkEnts.size()/4);
	
	g_PlayerFuncs.HudMessage(plr, params, info);
	
	PlayerState@ state = getPlayerState(plr);
	if (state.perfDebug) {
		g_Scheduler.SetTimeout("debug_perf", 1.0f, h_plr);
	}
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool isConsoleCommand=false) {
	PlayerState@ state = getPlayerState(plr);
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	
	if ( args.ArgC() > 0 )
	{				
		if (args[0] == ".lagc") {
			if (args.ArgC() > 1) {
				string arg = args[1];
				
				if (arg == "info") {
					state.debug = state.debug == 0 ? 1 : 0;
					g_PlayerFuncs.SayText(plr, "Lag compensation info " + (state.debug > 0 ? "enabled" : "disabled") + "\n");
				} 
				else if (arg == "x" || arg == "hitmarker") {
					state.hitmarker = !state.hitmarker;
					
					if (args.ArgC() > 2) {
						state.hitmarker = atoi(args[2]) != 0;
					}
					
					if (state.hitmarker) {
						state.enabled = true;
					}
					g_PlayerFuncs.SayText(plr, "Lag compensation hitmarker " + (state.hitmarker ? "enabled" : "disabled") + "\n");
				}
				else if (arg == "debug" && isAdmin) {
					state.enabled = true;
					state.debug = state.debug != 2 ? 2 : 0;
					g_PlayerFuncs.SayText(plr, "Lag compensation debug mode " + (state.debug > 0 ? "enabled" : "disabled") + "\n");
				}
				else if (arg == "pause" && isAdmin) {
					g_enabled = false;
					g_PlayerFuncs.SayTextAll(plr, "Lag compensation plugin disabled.\n");
				}
				else if (arg == "resume" && isAdmin) {
					g_enabled = true;
					reload_ents();
					g_PlayerFuncs.SayTextAll(plr, "Lag compensation plugin enabled. Say '.lagc' for help.\n");
				}
				else if (arg == "stats") {
					debug_stats(plr);
				}
				else if (arg == "rate" && isAdmin) {
					if (args.ArgC() > 2) {
						g_update_delay = Math.min(atof(args[2]), 1.0f);
						if (g_update_delay < 0) {
							g_update_delay = 0;
						}
						g_Scheduler.RemoveTimer(update_interval);
						@update_interval = g_Scheduler.SetInterval("update_ent_history", g_update_delay, -1);
						g_PlayerFuncs.SayText(plr, "Lag compensation rate set to " + g_update_delay + "\n");
					}
				}
				else if (arg == "test" && isAdmin) {
					
				}
				else if (arg == "perf") {
					state.perfDebug = !state.perfDebug;
					if (state.perfDebug)
						debug_perf(EHandle(plr));
				}
				else if (arg == "forcex" && isAdmin) {
					array<string>@ stateKeys = g_player_states.getKeys();
					for (uint i = 0; i < stateKeys.length(); i++)
					{
						PlayerState@ s = cast<PlayerState@>( g_player_states[stateKeys[i]] );
						s.hitmarker = true;
					}
					g_PlayerFuncs.SayTextAll(plr, "Hitmarkers forced on. Say \".lagc x\" to turn them off.\n");
				}
				else if (arg == "on") {
					state.enabled = true;
					state.compensation = -1;
					g_PlayerFuncs.SayText(plr, "Lag compensation enabled (auto)\n");
				}
				else if (arg == "off") {
					state.enabled = false;
					state.compensation = 0;
					state.adjustMode = ADJUST_NONE;
					g_PlayerFuncs.SayText(plr, "Lag compensation disabled\n");
				}
				else if (arg == "toggle") {
					state.enabled = !state.enabled;
					state.compensation = 0;
					state.adjustMode = ADJUST_NONE;
					g_PlayerFuncs.SayText(plr, "Lag compensation " + (state.enabled ? "enabled" : "disabled") + "\n");
				}
				else if (arg == "auto") {
					state.enabled = true;
					state.compensation = 0;
					g_PlayerFuncs.SayText(plr, "Lag compensation set to auto\n");
				} 
				else {
					int adjustMode = ADJUST_ADD;
					
					if (arg[0] == '=') {
						adjustMode = ADJUST_NONE;
						arg = arg.SubString(1);
						println("NEWARG " + arg);
					}
					else if (arg[0] == '-') {
						adjustMode = ADJUST_SUB;
						arg = arg.SubString(1);
					}
					
					int amt = Math.min(atoi(arg), int(MAX_LAG_COMPENSATION_SECONDS*1000));
					if (amt < -1) {
						amt = -1;
					}
					
					state.compensation = amt;
					state.adjustMode = adjustMode;
					state.enabled = true;
					
					if (adjustMode == ADJUST_NONE) {
						g_PlayerFuncs.SayText(plr, "Lag compensation set to " + state.compensation + "ms\n");
					} else {
						string prefix = adjustMode == ADJUST_ADD ? "ping + " : "ping - ";
						g_PlayerFuncs.SayText(plr, "Lag compensation set to " + prefix + state.compensation + "ms\n");
					}
				}				
			} else {
				int maxComp = int(MAX_LAG_COMPENSATION_SECONDS*1000);
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '-----------------------------Lag Compensation Commands-----------------------------\n\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Lag compensation "rewinds" enemies so that you don\'t have to aim ahead of them to get a hit.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".lagc [on/off/toggle]" to enable or disable lag compensation.\n');
				
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nIf you still need to aim ahead/behind enemies to hit them, then try one of these commands:\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc +X" to increase compensation.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc -X" to decrease compensation.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc =X" to set a specific compensation.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc auto" to use the default compensation.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    X = milliseconds\n');
				
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nIf you\'re unsure how to adjust compensation, try these commands:\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc info" to toggle compensation messages.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        This will show your compensation ping when you shoot.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        Try matching it with the ping you see in net_graph.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        The net_graph ping might be more accurate than the scoreboard.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        To turn on net_graph, type \'net_graph 2\' in this console.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc x [0/1]" to toggle hit confirmations.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        This will make it obvious when you hit a target.\n');
				
				if (isAdmin) {
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nAdmins only:');
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n    Type ".lagc debug" to toggle compensation visualizations.\n        - This may cause extreme lag and/or desyncs!\n');
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc [pause/resume]" to enable or disable ths plugin.\n        - Try this if the server is lagging horribly.\n');
				}
				
				string mode = " (auto)";
				if (state.adjustMode == ADJUST_ADD) {
					mode = " (ping + " + state.compensation + "ms)";
				} else if (state.adjustMode == ADJUST_SUB) {
					mode = " (ping - " + state.compensation + "ms)";
				}
				if (!state.enabled) {
					mode = "";
				}
				
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nYour settings:\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Compensation is ' + (state.enabled ? 'enabled' : 'disabled') + mode + '\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Hitmarkers are ' + (state.hitmarker ? 'enabled' : 'disabled') + '\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Info messages are ' + (state.debug > 0 ? 'enabled' : 'disabled') + '\n');
				
				if (!g_enabled)
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nThe lag compensation plugin is currently disabled.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n-----------------------------------------------------------------------------------\n');
			
				if (!isConsoleCommand) {
					if (g_enabled) {
						g_PlayerFuncs.SayText(plr, 'Lag compensation is ' + (state.enabled ? 'enabled' : 'disabled') + mode + '\n');
						g_PlayerFuncs.SayText(plr, 'Say ".lagc [on/off/toggle]" to enable or disable lag compensation.\n');
						g_PlayerFuncs.SayText(plr, 'Say ".lagc x" to toggle hit confirmations.\n');
					}
					else
						g_PlayerFuncs.SayText(plr, 'The lag compensation plugin is currently disabled.\n');
					g_PlayerFuncs.SayText(plr, 'Type ".lagc" in console for more commands/info\n');
				}
			}
			return true;
		}
	}
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();	
	if (doCommand(plr, args, false))
	{
		pParams.ShouldHide = true;
	}
	return HOOK_CONTINUE;
}

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}
