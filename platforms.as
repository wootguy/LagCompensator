class LagPlatform {
	EHandle h_plat; // platform being synced to
	EHandle h_comp; // fake compensated entity
	
	LagPlatform() {}
	
	LagPlatform(CBaseEntity@ plat, CBaseEntity@ comp) {
		h_comp = EHandle(comp);
		h_plat = EHandle(plat);
	}
}

// set of compensated platforms per player
array<array<LagPlatform>> lagPlatforms;

void kill_compensated_rotating_ents() {
	array<CBaseEntity@> killEnts;
	
	{
		CBaseEntity@ kill = null;
		do {
			@kill = g_EntityFuncs.FindEntityByTargetname(kill, "lagc_ent");
			killEnts.insertLast(kill);
			println("KILL IT");
		} while(kill !is null);
	}
	
	for (uint i = 0; i < killEnts.size(); i++) {
		g_EntityFuncs.Remove(killEnts[i]);
	}
}

void sync_platforms() {
	for (uint i = 0; i < lagPlatforms.size(); i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		
		array<LagPlatform>@ platforms = lagPlatforms[i];
		PlayerState@ state = getPlayerState(plr);
		float ping = state.getCompensationPing(plr);
		CBaseEntity@ groundEnt = (plr.pev.flags & FL_ONGROUND != 0) ? g_EntityFuncs.Instance(plr.pev.groundentity) : null;
		string ground = groundEnt !is null ? string(groundEnt.pev.classname) : "null";
		println("COMP " + plr.pev.netname + " " + ping + " " + ground);
		
		for (uint k = 0; k < platforms.size(); k++) {
			CBaseEntity@ plat = platforms[k].h_plat;
			CBaseEntity@ comp = platforms[k].h_comp;
			
			comp.pev.angles = plat.pev.angles + plat.pev.avelocity*ping;
			comp.pev.avelocity = plat.pev.avelocity;
			
			
			if (groundEnt !is null && plat.entindex() == groundEnt.entindex()) {
				plat.pev.rendermode = 0;
				comp.pev.rendermode = 1;
				comp.pev.renderamt = 16;
				comp.pev.rendercolor = Vector(255, 255, 255);
			} else {
				comp.pev.rendermode = 0;
				plat.pev.rendermode = 1;
				plat.pev.renderamt = 16;
				plat.pev.rendercolor = Vector(255, 255, 255);
			}
			
		}
	}
}

int count_visible_pvs_ents(CBaseEntity@ fromEnt) {
	int count = 0;
	
	edict_t@ edt = g_EngineFuncs.EntitiesInPVS(fromEnt.edict());
	while (edt !is null)
	{
		CBaseEntity@ ent = g_EntityFuncs.Instance( edt );
		if (ent is null) {
			break;
		}
		
		if (ent.pev.effects & EF_NODRAW == 0 && ent.pev.modelindex != 0) {
			println("NEAR " + ent.pev.classname + " " + ent.pev.modelindex);
			count++;
		}
		
		
		@edt = @ent.pev.chain;
	}
	
	println("" + fromEnt.pev.classname + " near " + count + " ents");
	return count;
}

void delay_use(CBaseEntity@ ent) {
	ent.Use(null, null, USE_ON);
}

int idx = 0;

void compensate_func_rotating(CBasePlayer@ plr) {
	lagPlatforms.resize(33);
	
	g_Scheduler.SetInterval("sync_platforms", 0.05, -1);
	
	array<LagPlatform>@ compList = lagPlatforms[plr.entindex()];
	
	kill_compensated_rotating_ents();
	
	array<CBaseEntity@> rotateEnts;
	
	{
		CBaseEntity@ ent = null;
		do {
			@ent = g_EntityFuncs.FindEntityByClassname(ent, "func_rotating");
			if (ent !is null)
			{
				//for (int i = 0; i < 32; i++)
				rotateEnts.insertLast(ent);
			}
		} while(ent !is null);
	}
	
	
	for (uint i = 0; i < rotateEnts.size(); i++) {
		CBaseEntity@ ent = rotateEnts[i];
		//ent.pev.speed = 80;
		//ent.Use(null, null, USE_OFF);
		//g_Scheduler.SetTimeout("delay_use", 0.5f, @ent);
		
		bool isOn = ent.pev.avelocity == ent.pev.movedir*ent.pev.speed;
		
		dictionary keys;
		keys["targetname"] = "lagc_ent";
		keys["origin"] = ent.pev.origin.ToString();
		keys["angles"] = ent.pev.angles.ToString();
		keys["model"] = string(ent.pev.model);
		keys["speed"] = "0";
		keys["sounds"] = "0";
		keys["volume"] = "0";
		keys["rendermode"] = "0";
		keys["renderamt"] = "200";
		keys["spawnflags"] = "" + 65; // not solid
		CBaseEntity@ futureEnt = @g_EntityFuncs.CreateEntity("func_rotating", keys, true);
		futureEnt.pev.solid = SOLID_NOT;
		
		compList.insertLast(LagPlatform(ent, futureEnt));
		
		println("CHECK PLEASE");
		
		//g_EntityFuncs.Remove(ent);
	}
}