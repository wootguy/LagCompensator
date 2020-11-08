#include "weapons"
#include "commands"
#include "util"

// TODO:
// - auto-enable for high pings?
// - EVERYTHING is gibbing when disabled (undo gib after the shot possible?)
// - check normal shotgun spread
// - custom weapon NO DAMAGE (pizza san)

// can't reproduce:
// - extreme lag barnacle weapon op_blackmesa4

// minor todo:
// - compensate moving platforms somehow?
// - compensate moving breakable solids and/or buttons
// - move blood effect closer to monster (required linking monsters to LagEnt)
// - show monster info at rewind position
// - performance improvements: filter visible monsters before rewind?
// - use BulletAccuracy method somehow
// - custom weapon support?

// unfixable(?) bugs:
// - monsters bleed and react to being shot in the non-rewound position, but will take no damage
//   - the blood effect can be disabled but has other side effects (no bleeding from projectiles or NPC bullets)
// - skill CVars will show "0" damage for the supported weapons
// - some weapons ALWAYS gib certain monsters when comp disabled
// - 5.56 weapons do 0.5 more damage to stationary targets, -0.5 to moving

const float MAX_LAG_COMPENSATION_TIME = 2.0f; // 2 seconds
const string hitmarker_spr = "sprites/misc/mlg.spr";
const string hitmarker_snd = "misc/hitmarker.mp3";

bool g_enabled = true;
float g_update_delay = 0.05f; // time between monster state updates
CScheduledFunction@ update_interval = null;
CScheduledFunction@ player_state_interval = null;
CScheduledFunction@ cvar_interval = null;
CScheduledFunction@ cleanup_interval = null;

array<LagEnt> laggyEnts; // ents that are lag compensated
dictionary g_monster_blacklist; // don't track these - waste of time
dictionary g_player_states;
int g_state_count = 0;

enum AdjustModes {
	ADJUST_NONE, // use ping value
	ADJUST_ADD, // add to ping value
	ADJUST_SUB // subtract from ping value
}

class PlayerState {
	// Never store player handle? It needs to be set to null on disconnect or else states start sharing
	// player handles and cause weird bugs or break states entirely. Check if disconnect is called
	// if player leaves during level change.

	bool enabled = true;
	int compensation = 0;
	int adjustMode = 0;
	int debug = 0;
	bool hitmarker = false;
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
	
	EntState currentState; // only updated on shoots
	array<EntState> history;
	bool isRewound = false;
	
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

void PluginInit()  {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponSecondaryAttack, @WeaponSecondaryAttack );
	g_Hooks.RegisterHook( Hooks::Game::EntityCreated, @EntityCreated );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );
	g_Hooks.RegisterHook( Hooks::Player::PlayerPreThink, @PlayerPreThink );
	g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );
	
	g_bullet_damage.resize(11);
	
	last_shotgun_clips.resize(33);
	last_shoot.resize(33);
	last_minigun_clips.resize(33);
	gauss_start_charge.resize(33);
	egon_last_dmg.resize(33);
	
	g_monster_blacklist["monster_barney_dead"] = true;
	g_monster_blacklist["monster_cockroach"] = true;
	g_monster_blacklist["monster_furniture"] = true;
	g_monster_blacklist["monster_handgrenade"] = true;
	g_monster_blacklist["monster_hevsuit_dead"] = true;
	g_monster_blacklist["monster_hgrunt_dead"] = true;
	g_monster_blacklist["monster_human_grunt_ally_dead"] = true;
	g_monster_blacklist["monster_leech"] = true;
	g_monster_blacklist["monster_otis_dead"] = true;
	g_monster_blacklist["monster_satchel"] = true;
	g_monster_blacklist["monster_scientist_dead"] = true;
	g_monster_blacklist["monster_sitting_scientist"] = true;
	g_monster_blacklist["monster_tripmine"] = true;
	
	init_weapon_info();
	
	// disabling turrets would make defendthefort boss harder
	//g_monster_blacklist["monster_sentry"] = true;
	//g_monster_blacklist["monster_miniturret"] = true;
	//g_monster_blacklist["monster_turret"] = true;
	
	if (g_Engine.time > 4) { // plugin reloaded mid-map?
		reload_skill_files();
		late_init();
	}
}

void MapInit() {
	g_Game.PrecacheModel(hitmarker_spr);
	g_SoundSystem.PrecacheSound(hitmarker_snd);
	g_Game.PrecacheGeneric("sound/" + hitmarker_snd);
	
	g_EngineFuncs.ServerCommand("mp_noblastgibs 1;\n");
	g_EngineFuncs.ServerExecute();
}

void MapActivate() {	
	for (int i = 0; i < 33; i++) {
		last_shotgun_clips[i] = 8;
		last_minigun_clips[i] = 500;
		last_shoot[i] = 0;
		gauss_start_charge[0] = -1;
		egon_last_dmg[0] = 0;
	}
	
	late_init();
}

HookReturnCode MapChange() {
	stop_polling();
	return HOOK_CONTINUE;
}

void start_polling() {
	println("lagc polling started");
	@update_interval = g_Scheduler.SetInterval("update_ent_history", g_update_delay, -1);
	@cvar_interval = g_Scheduler.SetInterval("refresh_cvars", 5.0f, -1);
	@cleanup_interval = g_Scheduler.SetInterval("cleanup_ents", 5.0f, -1);
	
	// interval must be faster than any weapon can deploy
	@player_state_interval = g_Scheduler.SetInterval("refresh_player_states", 0.5f, -1);
}

void stop_polling() {
	println("lagc polling stopped");
	g_Scheduler.RemoveTimer(update_interval);
	g_Scheduler.RemoveTimer(player_state_interval);
	g_Scheduler.RemoveTimer(cvar_interval);
	g_Scheduler.RemoveTimer(cleanup_interval);
	@update_interval = null;
	@player_state_interval = null;
	@cvar_interval = null;
	@cleanup_interval = null;
}

void late_init() {
	check_classic_mode();

	save_cvar_values();
	
	if (g_enabled)
		disable_default_damages();
		
	reload_ents();
	start_polling();
}

void add_lag_comp_ent(CBaseEntity@ ent) {
	if (g_monster_blacklist.exists(ent.pev.classname)) {
		return;
	}
	laggyEnts.insertLast(LagEnt(ent));
}

void reload_ents() {
	laggyEnts.resize(0);

	CBaseEntity@ ent;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "monster_*");
		if (ent !is null)
		{
			add_lag_comp_ent(ent);
		}
	} while(ent !is null);
	
	@ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player");
		if (ent !is null)
		{
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			if (plr.IsConnected())
				add_lag_comp_ent(ent);
		}
	} while(ent !is null);
}

// removes deleted ents
void cleanup_ents() {
	array<LagEnt> newLagEnts;
	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		
		if (mon is null) {
			continue;
		}
		
		if (mon.IsPlayer()) {
			CBasePlayer@ plr = cast<CBasePlayer@>(mon);
			if (!plr.IsConnected())
				continue;
		}
		
		newLagEnts.insertLast(laggyEnts[i]);
	}
	laggyEnts = newLagEnts;
}

void update_ent_history() {
	if (!g_enabled) {
		return;
	}
	
	g_state_count = 0;
	for (uint i = 0; i < laggyEnts.size(); i++) {
		laggyEnts[i].update_history();
		g_state_count += laggyEnts[i].history.size();
	}
}

void delay_kill(EHandle h_ent) {
	g_EntityFuncs.Remove(h_ent);
}

void debug_rewind(CBaseMonster@ mon, EntState lastState) {
	dictionary keys;
	keys["origin"] = lastState.origin.ToString();
	keys["angles"] = lastState.angles.ToString();
	keys["model"] = string(mon.pev.model);
	keys["rendermode"] = "1";
	keys["renderamt"] = "200";
	CBaseMonster@ oldEnt = cast<CBaseMonster@>(g_EntityFuncs.CreateEntity("cycler", keys, true));
	oldEnt.pev.solid = SOLID_NOT;
	oldEnt.pev.movetype = MOVETYPE_NOCLIP;
	
	oldEnt.m_Activity = ACT_RELOAD;
	oldEnt.pev.sequence = lastState.sequence;
	oldEnt.pev.frame = lastState.frame;
	oldEnt.ResetSequenceInfo();
	oldEnt.pev.framerate = 0.00001f;
	
	g_Scheduler.SetTimeout("delay_kill", 1.0f, EHandle(oldEnt));
}

int rewind_monsters(CBasePlayer@ plr, PlayerState@ state) {
	int iping;
	
	if (state.adjustMode == ADJUST_NONE) {
		if (state.compensation > 0) {
			iping = state.compensation;
		} else {
			int packetLoss;
			g_EngineFuncs.GetPlayerStats(plr.edict(), iping, packetLoss);
		}
	} else {
		int packetLoss;
		g_EngineFuncs.GetPlayerStats(plr.edict(), iping, packetLoss);
			
		if (state.adjustMode == ADJUST_ADD) {
			iping += state.compensation;
		} else {
			iping -= state.compensation;
		}
	}
	
	if (state.debug > 0 && laggyEnts.size() > 0) {
		string shift = "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
		float scale = (1.0f / MAX_LAG_COMPENSATION_TIME);
		int rate = int((g_state_count / laggyEnts.size())*scale);
		g_PlayerFuncs.PrintKeyBindingString(plr, shift + "Compensation: " + iping + " ms\n" + 
			"Replay FPS: " + rate);
	}
	
	float ping = float(iping) / 1000.0f;
	float shootTime = g_Engine.time - ping;
	
	int rewind_count = 0;

	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		if (mon is null or mon.entindex() == plr.entindex()) {
			continue;
		}
		
		rewind_count++;
		
		// get state closest to the time the player shot
		int bestHistoryIdx = 0;
		
		for (uint k = 0; k < laggyEnts[i].history.size(); k++) {
			if (laggyEnts[i].history[k].time >= shootTime || k == laggyEnts[i].history.size()-1) {
				bestHistoryIdx = k;
				//println("Best delta: " + int((laggyEnts[i].history[k].time - shootTime)*1000) + " for ping " + iping);
				break;
			}
		}
		
		if (bestHistoryIdx == 0) {
			continue;
		}
		
		laggyEnts[i].isRewound = true;
		laggyEnts[i].currentState.origin = mon.pev.origin;
		laggyEnts[i].currentState.sequence = mon.pev.sequence;
		laggyEnts[i].currentState.frame = mon.pev.frame;
		laggyEnts[i].currentState.angles = mon.pev.angles;
		
		EntState newState = laggyEnts[i].history[bestHistoryIdx]; // later than shoot time
		EntState oldState = laggyEnts[i].history[bestHistoryIdx-1]; // earlier than shoot time		
		
		// interpolate between states to get the exact position the monster was in when the player shot
		// this probably won't matter much unless the server framerate is really low.
		float t = (shootTime - oldState.time) / (newState.time - oldState.time);

		mon.pev.sequence = t >= 0.5f ? newState.sequence : oldState.sequence;
		mon.pev.frame = oldState.frame + (newState.frame - oldState.frame)*t;
		mon.pev.angles = t >= 0.5f ? newState.angles : oldState.angles;
		g_EntityFuncs.SetOrigin(mon, oldState.origin + (newState.origin - oldState.origin)*t);
		
		if (state.debug > 1) {
			EntState tweenState;
			tweenState.origin = mon.pev.origin;
			tweenState.sequence = mon.pev.sequence;
			tweenState.frame = mon.pev.frame;
			tweenState.angles = mon.pev.angles;
		
			debug_rewind(mon, tweenState);
		}
	}
	
	return rewind_count;
}

void undo_rewind_monsters() {
	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		if (!laggyEnts[i].isRewound or mon is null) {
			continue;
		}
		
		// move back to current position
		g_EntityFuncs.SetOrigin(mon, laggyEnts[i].currentState.origin);
		mon.pev.sequence = laggyEnts[i].currentState.sequence;
		mon.pev.frame = laggyEnts[i].currentState.frame;
		mon.pev.angles = laggyEnts[i].currentState.angles;
		
		laggyEnts[i].isRewound = false;
	}
}

void delay_compensate(EHandle h_plr, EHandle h_wep, bool isSecondaryFire, int burst_round) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(h_wep.GetEntity());
	
	if (plr !is null && wep !is null) {
		compensate(plr, wep, isSecondaryFire, burst_round);
	}
}

void shoot_compensated_bullets(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire, PlayerState@ state, WeaponInfo@ wepInfo) {
	Vector vecSrc = plr.GetGunPosition();
	bool doBloodStream = wep.pev.classname == "weapon_sniperrifle";
	bool doEgonBlast = wep.pev.classname == "weapon_egon";
	bool isGauss = wep.pev.classname == "weapon_gauss";
	int hits = 0;
	CBaseEntity@ target = null;
	
	array<LagBullet> lagBullets = get_bullets(plr, wep, isSecondaryFire, wepInfo, state.debug > 0);
	
	for (uint b = 0; b < lagBullets.size(); b++) {
		LagBullet bullet = lagBullets[b];
		
		if (isGauss) {
			CBaseEntity@ hitMonster = @gauss_effects(plr, wep, bullet, isSecondaryFire);
			if (hitMonster !is null) {
				@target = @hitMonster;
				hits++;
			}
			continue;
		}
		
		TraceResult tr;
		g_Utility.TraceLine( vecSrc, vecSrc + bullet.vecAim*BULLET_RANGE, dont_ignore_monsters, plr.edict(), tr );
		
		bool hit = false;
		CBaseEntity@ phit = g_EntityFuncs.Instance(tr.pHit);
		if (phit !is null) {
			if (phit.IsMonster()) {	
				
				// move the impact sprite closer to the where the monster currently is
				//tr.vecEndPos = tr.vecEndPos + (currentOrigin - lastState.origin);
			
				if (doBloodStream && !phit.IsMachine()) {
					CBaseMonster@ mon = cast<CBaseMonster@>(phit);
					int bloodColor = mon.BloodColor();
					if (bloodColor == BLOOD_COLOR_RED) {
						// BLOOD_COLOR_RED actually means CIRCUS CLOWN CONFETTI PIZZA PARTY
						bloodColor = 70; // THIS is red
					}
					g_Utility.BloodStream(tr.vecEndPos, tr.vecPlaneNormal, bloodColor, 160);
				}
			
				@target = @phit;
				hit = true;
				hits++;
			}
			
			g_WeaponFuncs.ClearMultiDamage();
			phit.TraceAttack(plr.pev, bullet.damage, bullet.vecAim, tr, wepInfo.dmgType);
			g_WeaponFuncs.ApplyMultiDamage(plr.pev, plr.pev);
			
			if (doEgonBlast) {
				g_WeaponFuncs.RadiusDamage( tr.vecEndPos, wep.pev, plr.pev, bullet.damage/4, 128, CLASS_NONE, DMG_ENERGYBEAM | DMG_BLAST | DMG_ALWAYSGIB );
			}
		}
		
		if (state.debug > 1) {
			int life = 10;
			te_beampoints(vecSrc, tr.vecEndPos, "sprites/laserbeam.spr", 0, 100, life, 2, 0, hit ? RED : GREEN);
		}
	}
	
	if (hits > 0 && state.hitmarker) {
		HUDSpriteParams params;
		params.flags = HUD_SPR_MASKED | HUD_ELEM_SCR_CENTER_X | HUD_ELEM_SCR_CENTER_Y | HUD_ELEM_EFFECT_ONCE;
		params.spritename = hitmarker_spr.SubString("sprites/".Length());
		params.holdTime = 0.5f;
		params.x = 0;
		params.y = 0;
		params.color1 = RGBA( 255, 255, 255, 255 );
		params.color2 = RGBA(255, 255, 255, 0);
		params.fxTime = 0.8f;
		params.effect = HUD_EFFECT_RAMP_UP;
		params.channel = 15;
		g_PlayerFuncs.HudCustomSprite(plr, params);
		
		g_SoundSystem.PlaySound(target.edict(), CHAN_AUTO, hitmarker_snd, 0.8f, 0.0f, 0, 100, plr.entindex());
	}
}

void compensate(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire, int burst_round=1, bool force_shoot=false) {
	if (!g_enabled) {
		return; // lag compensation disabled for everyon
	}
	
	PlayerState@ state = getPlayerState(plr);
	
	if (!state.enabled) {
		return; // lag compensation disabled for this player
	}
	
	WeaponInfo@ wepInfo = cast<WeaponInfo@>( g_weapon_info[wep.pev.classname] );
	
	if (wepInfo is null) {
		return; // unsupported gun
	}
	
	if (!force_shoot && !didPlayerShoot(plr, wep, isSecondaryFire)) {
		return; // didn't actually shoot a bullet (the hooks are not at all reliable)
	}
	
	// TODO maybe: make this generic so it works for any burst-fire weapon
	if (burst_round < 3 && wep.pev.classname == "weapon_m16") {
		g_Scheduler.SetTimeout("delay_compensate", 0.075f, EHandle(plr), EHandle(wep), isSecondaryFire, burst_round+1);
	}
	
	rewind_monsters(plr, state);
	
	shoot_compensated_bullets(plr, wep, isSecondaryFire, state, wepInfo);
	
	undo_rewind_monsters();
	
	last_shoot[plr.entindex()] = g_Engine.time;
}

HookReturnCode WeaponPrimaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {
	compensate(plr, wep, false);
	return HOOK_CONTINUE;
}

HookReturnCode WeaponSecondaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {
	compensate(plr, wep, true);	
	return HOOK_CONTINUE;
}

HookReturnCode EntityCreated(CBaseEntity@ ent){
	if (!g_enabled) {
		return HOOK_CONTINUE;
	}
	
	if (string(ent.pev.classname).Find("monster_") == 0) {
		add_lag_comp_ent(ent);
	}
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin(CBasePlayer@ plr)
{
	add_lag_comp_ent(plr);
	return HOOK_CONTINUE;
}

HookReturnCode PlayerPreThink(CBasePlayer@ plr, uint&out test) {
	if (!g_enabled) {
		return HOOK_CONTINUE;
	}
	
	// need to poll to know when a player released the secondary fire button for gauss chargeup
	update_gauss_charge_state(plr);
	
	return HOOK_CONTINUE;
}

