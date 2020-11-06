const float MAX_LAG_COMPENSATION_TIME = 2; // 2 seconds

class Color
{ 
	uint8 r, g, b, a;
	Color() { r = g = b = a = 0; }
	Color(uint8 r, uint8 g, uint8 b) { this.r = r; this.g = g; this.b = b; this.a = 255; }
	Color(uint8 r, uint8 g, uint8 b, uint8 a) { this.r = r; this.g = g; this.b = b; this.a = a; }
	Color(float r, float g, float b, float a) { this.r = uint8(r); this.g = uint8(g); this.b = uint8(b); this.a = uint8(a); }
	Color (Vector v) { this.r = uint8(v.x); this.g = uint8(v.y); this.b = uint8(v.z); this.a = 255; }
	string ToString() { return "" + r + " " + g + " " + b + " " + a; }
	Vector getRGB() { return Vector(r, g, b); }
}

Color RED    = Color(255,0,0);
Color GREEN  = Color(0,255,0);
Color BLUE   = Color(0,0,255);
Color YELLOW = Color(255,255,0);
Color ORANGE = Color(255,127,0);
Color PURPLE = Color(127,0,255);
Color PINK   = Color(255,0,127);
Color TEAL   = Color(0,255,255);
Color WHITE  = Color(255,255,255);
Color BLACK  = Color(0,0,0);
Color GRAY  = Color(127,127,127);

void te_beampoints(Vector start, Vector end, string sprite="sprites/laserbeam.spr", uint8 frameStart=0, uint8 frameRate=100, uint8 life=20, uint8 width=2, uint8 noise=0, Color c=GREEN, uint8 scroll=32, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BEAMPOINTS);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(end.x);m.WriteCoord(end.y);m.WriteCoord(end.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(frameStart);m.WriteByte(frameRate);m.WriteByte(life);m.WriteByte(width);m.WriteByte(noise);m.WriteByte(c.r);m.WriteByte(c.g);m.WriteByte(c.b);m.WriteByte(c.a);m.WriteByte(scroll);m.End(); }

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void PluginInit() 
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack );
	
	refresh_ents();
	
	g_Scheduler.SetInterval("update_ent_history", 0.0f, -1);
}

class EntState {
	float time;
	Vector origin;
	Vector angles;
	int sequence;
	float frame;
}

class LagEnt {
	EHandle h_ent;
	
	array<EntState> history;
	
	LagEnt() {}
	
	LagEnt(CBaseEntity@ ent) {
		h_ent = EHandle(ent);
	}
	
	bool update_history() {
		CBaseEntity@ ent = h_ent;
		
		if (ent is null) {
			return false;
		}
		
		EntState state;
		state.time = g_Engine.time;
		state.origin = ent.pev.origin;
		state.angles = ent.pev.angles;
		state.sequence = ent.pev.sequence;
		state.frame = ent.pev.frame;
		
		history.insertLast(state);
		
		while (history[0].time < g_Engine.time - MAX_LAG_COMPENSATION_TIME) {
			history.removeAt(0);
		}
		
		return true;
	}
}

array<LagEnt> laggyEnts;

void refresh_ents() {
	laggyEnts.resize(0);

	CBaseEntity@ ent;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "monster_*");
		if (ent !is null)
		{
			laggyEnts.insertLast(ent);
		}
	} while(ent !is null);
}

void update_ent_history() {
	for (uint i = 0; i < laggyEnts.size(); i++) {
		laggyEnts[i].update_history();
	}
}

void delay_kill(EHandle h_ent) {
	g_EntityFuncs.Remove(h_ent);
}

void compensate(CBasePlayer@ plr) {
	println("Compensate for plr!");
	
	int replay_count = 0;
	
	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		if (mon is null) {
			continue;
		}
		
		replay_count++;
		
		// get state closest to the time the player shot
		EntState lastState = laggyEnts[i].history[0];
		
		{
			int iping, packetLoss;
			g_EngineFuncs.GetPlayerStats(plr.edict(), iping, packetLoss);
			
			float ping = float(iping) / 1000.0f;
			float shootTime = g_Engine.time - ping;
			
			for (uint k = 0; k < laggyEnts[i].history.size(); k++) {
				if (laggyEnts[i].history[k].time >= shootTime) {
					lastState = laggyEnts[i].history[k];
					break;
				}
			}
		}
		
		Vector currentOrigin = mon.pev.origin;
		int currentSequence = mon.pev.sequence;
		float currentFrame = mon.pev.frame;
		Vector currentAngles = mon.pev.angles;
		
		
		mon.pev.sequence = lastState.sequence;
		mon.pev.frame = lastState.frame;
		mon.pev.angles = lastState.angles;
		g_EntityFuncs.SetOrigin(mon, lastState.origin);
		
		// debug
		{
			dictionary keys;
			keys["origin"] = lastState.origin.ToString();
			keys["angles"] = lastState.angles.ToString();
			keys["model"] = string(mon.pev.model);
			keys["rendermode"] = "1";
			keys["renderamt"] = "128";
			keys["spawnflags"] = "1";
			CBaseMonster@ oldEnt = cast<CBaseMonster@>(g_EntityFuncs.CreateEntity("cycler", keys, true));
			oldEnt.pev.solid = SOLID_NOT;
			oldEnt.pev.movetype = MOVETYPE_NOCLIP;
			
			// reset to swim animation if no emote is playing
			oldEnt.m_Activity = ACT_RELOAD;
			oldEnt.pev.sequence = lastState.sequence;
			oldEnt.pev.frame = lastState.frame;
			oldEnt.ResetSequenceInfo();
			oldEnt.pev.framerate = 0.00001f;
			//oldEnt.pev.flags |= FL_SKIPLOCALHOST;
			
			g_Scheduler.SetTimeout("delay_kill", 1.0f, EHandle(oldEnt));
		}
		
		// hit detection for rewind monster
		bool hit = false;
		TraceResult tr;
		
		Math.MakeVectors( plr.pev.v_angle );
		Vector vecAiming = g_Engine.v_forward;
		
		{
			
			
			Vector vecSrc = plr.GetGunPosition();
			
			g_Utility.TraceLine( vecSrc, vecSrc + vecAiming*4096, dont_ignore_monsters, plr.edict(), tr );
			
			te_beampoints(vecSrc, tr.vecEndPos);
			
			CBaseEntity@ phit = g_EntityFuncs.Instance(tr.pHit);
			if (phit !is null && phit.entindex() != 0) {
				if (phit.entindex() == mon.entindex()) {
					hit = true;
					println("HIT " + phit.pev.classname + " " + phit.pev.solid);
				}
			}
		}
		
		Vector originDelta = currentOrigin - lastState.origin;
		
		// move back to current position
		g_EntityFuncs.SetOrigin(mon, currentOrigin);
		mon.pev.sequence = currentSequence;
		mon.pev.frame = currentFrame;
		mon.pev.angles = currentAngles;
		
		if (hit) {
			tr.vecEndPos = tr.vecEndPos + originDelta;
			
			g_WeaponFuncs.ClearMultiDamage();
			mon.TraceAttack(plr.pev, 10, vecAiming, tr, DMG_BULLET);
			g_WeaponFuncs.ApplyMultiDamage(plr.pev, plr.pev);
		}
	}
	
	//println("Replayed " + replay_count + " monsters");
}

void damage_effects() {
	
}


HookReturnCode WeaponPrimaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep)
{
	compensate(plr);
	return HOOK_CONTINUE;
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args)
{	
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	
	if ( args.ArgC() > 0 )
	{
		if (args[0] == "y") {
			refresh_ents();
			return true;
		}
	}
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams )
{
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();	
	if (doCommand(plr, args))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	return HOOK_CONTINUE;
}