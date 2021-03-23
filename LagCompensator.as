#include "custom_weapons"
#include "commands"
#include "util"

// minor todo:
// - auto-enable for high pings?
// - global history timestep
// - rewind moving objects too?
// - compensate moving platforms somehow?
// - compensate moving breakable solids and/or buttons
// - custom weapon support for all maps and plugins (ohgod)
// - double shotgun compensated while reloading
// - update PVS of player and only rewind ents near them?

// Ping colors:
// <75 = green
// 76+ = pale green
// 151+ = yellow
// 251+ = orange
// 401+ = red

const float MAX_LAG_COMPENSATION_SECONDS = 1.0f; // don't set too high or else newly spawned monsters take too long to be compensated
const string hitmarker_spr = "sprites/misc/mlg.spr";
const string hitmarker_snd = "misc/hitmarker.mp3";

bool g_enabled = true;
float g_update_delay = 0.05f; // time between monster state updates
CScheduledFunction@ update_interval = null;
CScheduledFunction@ cleanup_interval = null;

array<LagEnt> laggyEnts; // ents that are lag compensated
array<HitmarkEnt> hitmarkEnts; // ents that show hitmarkers but aren't lag compensated
dictionary g_monster_blacklist; // don't track these - waste of time
dictionary g_custom_hitmark_ents;
dictionary g_player_states;
dictionary g_no_compensate_weapons; // skip compensating these weapons to improve performance
int g_state_count = 0;
int g_rewind_count = 0;
int g_stat_rps = 0;
int g_stat_comps = 0;
array<int> lastPlrButtons; // player button properties dont't work right for secondary/tertiary fire
array<float> lastM16Delay1; // hack to figure out when the m16 will fire next
array<float> lastM16Delay2; // hack to figure out when the m16 will fire next
array<float> g_lastAttack; // for weapon cooldowns

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
	bool perfDebug = false; // show performance stats
	
	// get ping time in seconds
	float getCompensationPing(CBasePlayer@ plr) {
		int iping;
		
		if (adjustMode == ADJUST_NONE) {
			if (compensation > 0) {
				iping = compensation;
			} else {
				int packetLoss;
				g_EngineFuncs.GetPlayerStats(plr.edict(), iping, packetLoss);
			}
		} else {
			int packetLoss;
			g_EngineFuncs.GetPlayerStats(plr.edict(), iping, packetLoss);
				
			if (adjustMode == ADJUST_ADD) {
				iping += compensation;
			} else {
				iping -= compensation;
			}
		}
		
		return float(iping) / 1000.0f;
	}
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
	float currentHealth; // used to detect if player shot this monster
	int currentDeadFlag;
	
	EntState debugState; // used to display a debug model when a player shoots
	array<EntState> history;
	bool isRewound = false;
	bool hasEnoughHistory = false;
	
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
		
		while (history[0].time < g_Engine.time - MAX_LAG_COMPENSATION_SECONDS) {
			history.removeAt(0);
			hasEnoughHistory = true;
		}
		
		return true;
	}
}

class HitmarkEnt {
	EHandle h_ent;
	float currentHealth; // used to detect if player shot this breakable
	
	HitmarkEnt() {}
	
	HitmarkEnt(CBaseEntity@ ent) {
		h_ent = EHandle(ent);
	}
}

void PluginInit()  {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	lastPlrButtons.resize(33);
	lastM16Delay1.resize(33);
	lastM16Delay2.resize(33);
	g_lastAttack.resize(33);
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Game::EntityCreated, @EntityCreated );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );
	g_Hooks.RegisterHook( Hooks::Player::PlayerPostThink, @PlayerPostThink );
	g_Hooks.RegisterHook( Hooks::Player::PlayerUse, @PlayerUse );
	g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );
	
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
	
	g_no_compensate_weapons["weapon_crowbar"] = true;
	g_no_compensate_weapons["weapon_pipewrench"] = true;
	g_no_compensate_weapons["weapon_medkit"] = true;
	g_no_compensate_weapons["weapon_crossbow"] = true;
	g_no_compensate_weapons["weapon_rpg"] = true;
	g_no_compensate_weapons["weapon_hornetgun"] = true;
	g_no_compensate_weapons["weapon_handgrenade"] = true;
	g_no_compensate_weapons["weapon_satchel"] = true;
	g_no_compensate_weapons["weapon_tripmine"] = true;
	g_no_compensate_weapons["weapon_snark"] = true;
	g_no_compensate_weapons["weapon_sporelauncher"] = true;
	g_no_compensate_weapons["weapon_displacer"] = true;
	
	g_custom_hitmark_ents["func_breakable_custom"] = true;
	
	if (g_Engine.time > 4) { // plugin reloaded mid-map?
		late_init();
	}
	
	g_Scheduler.SetInterval("rewind_stats", 1.0f, -1);
	
}

void MapInit() {
	g_Game.PrecacheModel(hitmarker_spr);
	g_SoundSystem.PrecacheSound(hitmarker_snd);
	g_Game.PrecacheGeneric("sound/" + hitmarker_snd);
}

void MapActivate() {	
	late_init();
}

HookReturnCode MapChange() {
	stop_polling();
	return HOOK_CONTINUE;
}

void start_polling() {
	@update_interval = g_Scheduler.SetInterval("update_ent_history", g_update_delay, -1);
	@cleanup_interval = g_Scheduler.SetInterval("cleanup_ents", 0.5f, -1);
}

void stop_polling() {
	g_Scheduler.RemoveTimer(update_interval);
	g_Scheduler.RemoveTimer(cleanup_interval);
	@update_interval = null;
	@cleanup_interval = null;
}

void late_init() {
	reload_ents();
	start_polling();
}

void rewind_stats() {
	g_stat_rps = int(float(g_rewind_count) / 1.0f);
	g_stat_comps = g_compensations;
	
	g_rewind_count = 0;
	g_compensations = 0;
}

void add_lag_comp_ent(CBaseEntity@ ent) {
	if (ent.IsMonster() && (ent.IsPlayer() || string(ent.pev.classname).Find("monster_") == 0)) {
		if (g_monster_blacklist.exists(ent.pev.classname)) {
			return;
		}
		laggyEnts.insertLast(LagEnt(ent));
	} else if (ent.IsBreakable() or g_custom_hitmark_ents.exists(ent.pev.classname)) {
		hitmarkEnts.insertLast(HitmarkEnt(ent));
	}
}

void reload_ents() {
	laggyEnts.resize(0);
	hitmarkEnts.resize(0);
	
	CBaseEntity@ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "*");
		if (ent !is null)
		{
			add_lag_comp_ent(ent);
		}
	} while(ent !is null);
}

// removes deleted ents
void cleanup_ents() {
	array<LagEnt> newLagEnts;
	array<HitmarkEnt> newHitmarkEnts;
	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseEntity@ mon = laggyEnts[i].h_ent.GetEntity();
		
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
	
	for (uint i = 0; i < hitmarkEnts.size(); i++) {
		CBaseEntity@ ent = hitmarkEnts[i].h_ent;
		
		if (ent is null) {
			continue;
		}		
		newHitmarkEnts.insertLast(hitmarkEnts[i]);
	}
	
	laggyEnts = newLagEnts;
	hitmarkEnts = newHitmarkEnts;
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

void rewind_monsters(CBasePlayer@ plr, PlayerState@ state) {
	float ping = state.getCompensationPing(plr);
	float shootTime = g_Engine.time - ping;

	if (state.debug > 0 && laggyEnts.size() > 0) {
		string shift = "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
		float scale = (1.0f / MAX_LAG_COMPENSATION_SECONDS);
		int rate = int((g_state_count / laggyEnts.size())*scale);
		g_PlayerFuncs.PrintKeyBindingString(plr, shift + "Compensation: " + int(ping*1000) + " ms\n" + 
			"Replay FPS: " + rate);
	}

	int bestHistoryIdx = 0;

	for (uint i = 0; i < laggyEnts.size(); i++) {
		
		LagEnt@ lagEnt = laggyEnts[i];
		CBaseEntity@ mon = lagEnt.h_ent;
		
		if (mon is null) {
			continue;
		}
		if (lagEnt.history.size() <= 1 || mon.entindex() == plr.entindex() || mon.pev.deadflag != DEAD_NO) {
			//println("Not enough history for monster");
			continue;
		}

		g_rewind_count++;
		int useHistoryIdx = bestHistoryIdx;
		
		// get state closest to the time the player shot
		if (bestHistoryIdx == 0 || !lagEnt.hasEnoughHistory) {
			for (uint k = 0; k < lagEnt.history.size(); k++) {
				if (lagEnt.history[k].time >= shootTime || k == lagEnt.history.size()-1) {
					useHistoryIdx = k;
					if (lagEnt.hasEnoughHistory) {
						bestHistoryIdx = k; // use this for all other monsters that have enough history
					}
					//println("Best delta: " + int((lagEnt.history[k].time - shootTime)*1000) + " for ping " + iping);
					break;
				}
			}
			if (bestHistoryIdx == 0 || useHistoryIdx == 0) {
				continue;
			}
		}
		
		if (useHistoryIdx >= int(lagEnt.history.size()) || bestHistoryIdx >= int(lagEnt.history.size())) {
			continue;
		}
		
		lagEnt.isRewound = true;		
		lagEnt.currentState.origin = mon.pev.origin;
		lagEnt.currentState.angles = mon.pev.angles;
		lagEnt.currentState.sequence = mon.pev.sequence;
		lagEnt.currentState.frame = mon.pev.frame;
		lagEnt.currentHealth = mon.pev.health;
		lagEnt.currentDeadFlag = mon.pev.deadflag;
		
		// interpolate between states to get the exact position the monster was in when the player shot
		// this probably won't matter much unless the server framerate is really low.
		EntState@ newState = lagEnt.history[bestHistoryIdx]; // later than shoot time
		EntState@ oldState = lagEnt.history[bestHistoryIdx-1]; // earlier than shoot time
		float t = (shootTime - oldState.time) / (newState.time - oldState.time);

		mon.pev.sequence = t >= 0.5f ? newState.sequence : oldState.sequence;
		mon.pev.frame = oldState.frame + (newState.frame - oldState.frame)*t;
		mon.pev.angles = t >= 0.5f ? newState.angles : oldState.angles;
		mon.pev.origin = oldState.origin + (newState.origin - oldState.origin)*t;

		//mon.m_LastHitGroup = -1337; // for detecting hits on things that don't take damage from bullets (garg)
		
		if (state.debug > 1) {
			EntState tweenState;
			tweenState.origin = mon.pev.origin;
			tweenState.sequence = mon.pev.sequence;
			tweenState.frame = mon.pev.frame;
			tweenState.angles = mon.pev.angles;
			lagEnt.debugState = tweenState;
		}
	}
	
	if (state.hitmarker) {
		for (uint i = 0; i < hitmarkEnts.size(); i++) {
			CBaseEntity@ ent = hitmarkEnts[i].h_ent;
			if (ent is null) {
				continue;
			}
			hitmarkEnts[i].currentHealth = ent.pev.health;
		}
		
		// not as heavy as a rewind, but this loop still impacts performance at high frequencies
		g_rewind_count += hitmarkEnts.size() / 4;
	}
}

CBaseEntity@ undo_rewind_monsters(PlayerState@ state, bool didShoot) {
	CBaseEntity@ hitTarget = null;
	
	for (uint i = 0; i < laggyEnts.size(); i++) {
		LagEnt@ lagEnt = laggyEnts[i];
		CBaseEntity@ ent = lagEnt.h_ent;
		if (!lagEnt.isRewound or ent is null) {
			continue;
		}

		// move back to current position
		ent.pev.origin = lagEnt.currentState.origin;
		ent.pev.sequence = lagEnt.currentState.sequence;
		ent.pev.frame = lagEnt.currentState.frame;
		ent.pev.angles = lagEnt.currentState.angles;
		
		lagEnt.isRewound = false;
		
		if (state.debug > 1 && didShoot && ent.IsMonster()) {
			CBaseMonster@ mon = cast<CBaseMonster@>(ent);
			debug_rewind(mon, lagEnt.debugState);
		}
		
		if (ent.pev.health != lagEnt.currentHealth || ent.pev.deadflag != lagEnt.currentDeadFlag) {
			//hits++;
			@hitTarget = @ent;
		}
	}
	
	if (state.hitmarker) {
		for (uint i = 0; i < hitmarkEnts.size(); i++) {
			CBaseEntity@ ent = hitmarkEnts[i].h_ent;
			if (ent is null) {
				continue;
			}
			if (ent.pev.health != hitmarkEnts[i].currentHealth) {
				//hits++;
				@hitTarget = @ent;
			}
		}
	}
	
	return hitTarget;
}

void show_hit_marker(CBasePlayer@ plr, CBaseEntity@ target) {
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

HookReturnCode EntityCreated(CBaseEntity@ ent){
	if (!g_enabled) {
		return HOOK_CONTINUE;
	}
	
	add_lag_comp_ent(ent);
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin(CBasePlayer@ plr)
{
	PlayerState@ state = getPlayerState(plr);
	if (state.perfDebug) {
		debug_perf(EHandle(plr));
	}
	
	add_lag_comp_ent(plr);
	return HOOK_CONTINUE;
}

int g_compensations = 0;
int playerPostThinkAmmo = 0;
bool playerWasCompensated = false;

bool will_weapon_fire_this_frame(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {
	if (!plr.IsAlive() || plr.m_hTank.IsValid()) {
		return false;
	}
	
	if (g_CustomEntityFuncs.IsCustomEntity(wep.pev.classname)) {
		return will_custom_weapon_fire_this_frame(plr, wep);
	}
	
	if (plr.m_flNextAttack > 0)
		return false;

	int buttons = plr.m_afButtonPressed | plr.m_afButtonLast | plr.m_afButtonReleased;
	bool primaryFirePressed = buttons & IN_ATTACK != 0;
	bool secondaryFirePressed = buttons & IN_ATTACK2 != 0;
	bool hasPrimaryAmmo = wep.m_iClip > 0 || (wep.m_iClip == -1 && wep.m_iPrimaryAmmoType != -1 && plr.m_rgAmmo( wep.m_iPrimaryAmmoType ) > 0);
	bool hasSecondaryAmmo = wep.m_iClip2 > 0;
	bool primaryFireIsNow = wep.m_flNextPrimaryAttack <= 0;
	bool inWater = plr.pev.waterlevel == 3;
	
	if (wep.pev.classname == "weapon_9mmhandgun") {
		return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && (primaryFirePressed || secondaryFirePressed);
	}
	else if (wep.pev.classname == "weapon_9mmAR") {
		return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && primaryFirePressed && !secondaryFirePressed && !inWater;
	}
	else if (wep.pev.classname == "weapon_shotgun") {
		bool firing = (primaryFirePressed && primaryFireIsNow) || (secondaryFirePressed && wep.m_flNextSecondaryAttack <= 0);
		return hasPrimaryAmmo && !wep.m_fInReload && firing && !inWater;
	}
	else if (wep.pev.classname == "weapon_m16") {
		// will fire this frame if primary delay goes positive (bullet 1)
		// or if secondary delay goes positive after the first bullet (bullet 2+3)
		bool shotFirstBullet = primaryFirePressed && wep.m_flNextPrimaryAttack >= 0 && lastM16Delay1[plr.entindex()] < 0;
		bool shotBurstBullet = wep.m_flNextSecondaryAttack < 0 && lastM16Delay2[plr.entindex()] >= 0 && wep.m_flNextPrimaryAttack > 0.2f;
		bool firing = shotFirstBullet || shotBurstBullet;

		lastM16Delay1[plr.entindex()] = wep.m_flNextPrimaryAttack;
		lastM16Delay2[plr.entindex()] = wep.m_flNextSecondaryAttack;
		
		return hasPrimaryAmmo && firing && !wep.m_fInReload && !secondaryFirePressed && !inWater;
	}
	else if (wep.pev.classname == "weapon_uzi") {
		if (wep.m_fIsAkimbo) {
			return primaryFirePressed && (hasPrimaryAmmo || hasSecondaryAmmo) && primaryFireIsNow && !wep.m_fInReload && !inWater;
		} else {
			return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && primaryFirePressed && !secondaryFirePressed && !inWater;
		}
	}
	else if (wep.pev.classname == "weapon_gauss") {		
		if ((plr.m_afButtonPressed & IN_ATTACK2) == 0 && (lastPlrButtons[plr.entindex()] & IN_ATTACK2) != 0) {
			return !inWater;
		} else {
			return primaryFirePressed && !secondaryFirePressed && hasPrimaryAmmo && !inWater;
		}
	}
	else if (wep.pev.classname == "weapon_egon") {
		return hasPrimaryAmmo && (primaryFirePressed && !secondaryFirePressed) && wep.pev.dmgtime < g_Engine.time && wep.m_flNextPrimaryAttack < g_Engine.time && !inWater;
	}
	else if (wep.pev.classname == "weapon_shockrifle") {
		float nextDmg = wep.pev.dmgtime - g_Engine.time;
		return hasPrimaryAmmo && wep.m_flNextSecondaryAttack <= 0 && secondaryFirePressed && nextDmg < 0 && !inWater;
	}
	
	// 357, deagle, saw, sniper
	return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && primaryFirePressed && !inWater;
}

// called before weapon shoot code
HookReturnCode PlayerPostThink(CBasePlayer@ plr) {
	if (!g_enabled) {
		return HOOK_CONTINUE;
	}
	
	playerWasCompensated = false;
	
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
	if (wep !is null && !g_no_compensate_weapons.exists(wep.pev.classname)) {
		//println("COMP? " + wep.pev.classname);
		
		PlayerState@ state = getPlayerState(plr);

		if (state.enabled && will_weapon_fire_this_frame(plr, wep)) {
			//println("COMPENSATE " + g_Engine.time);
			playerWasCompensated = true;
			g_compensations++;
			
			playerPostThinkAmmo = wep.m_iClip;
			rewind_monsters(plr, state);
		}
		
		lastPlrButtons[plr.entindex()] = plr.m_afButtonPressed;
	}
	
	return HOOK_CONTINUE;
}

// called after weapon shoot code
HookReturnCode PlayerUse( CBasePlayer@ plr, uint& out uiFlags ) {	
	if (!g_enabled || !playerWasCompensated) {
		return HOOK_CONTINUE;
	}
	
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
	if (wep is null) {
		return HOOK_CONTINUE;
	}
	
	PlayerState@ state = getPlayerState(plr);
	
	bool didPlayerShoot = wep.m_iClip != playerPostThinkAmmo;
	
	if (didPlayerShoot)
		g_lastAttack[plr.entindex()] = g_Engine.time;
	
	CBaseEntity@ hitTarget = undo_rewind_monsters(state, didPlayerShoot);
	if (state.hitmarker && hitTarget !is null) {
		show_hit_marker(plr, hitTarget);
	}
	
	return HOOK_CONTINUE;
}
