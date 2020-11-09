#include "custom_weapons"
#include "commands"
#include "util"

// TODO:
// - auto-enable for high pings?
// - global history timestep

// minor todo:
// - compensate moving platforms somehow?
// - compensate moving breakable solids and/or buttons
// - custom weapon support for all maps and plugins (ohgod)
// - double shotgun compensated while reloading

// unfixable bugs:
// - blood effect shows in the unlagged position

const float MAX_LAG_COMPENSATION_TIME = 2.0f; // 2 seconds
const string hitmarker_spr = "sprites/misc/mlg.spr";
const string hitmarker_snd = "misc/hitmarker.mp3";

bool g_enabled = true;
float g_update_delay = 0.05f; // time between monster state updates
CScheduledFunction@ update_interval = null;
CScheduledFunction@ cleanup_interval = null;

array<LagEnt> laggyEnts; // ents that are lag compensated
dictionary g_monster_blacklist; // don't track these - waste of time
dictionary g_player_states;
dictionary g_no_compensate_weapons; // skip compensating these weapons to improve performance
int g_state_count = 0;
int g_rewind_count = 0;
int g_stat_rps = 0;
int g_stat_comps = 0;
array<int> lastPlrButtons; // player button properties dont't work right for secondary/tertiary fire
array<float> lastM16Delay1; // hack to figure out when the m16 will fire next
array<float> lastM16Delay2; // hack to figure out when the m16 will fire next

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
		
		while (history[0].time < g_Engine.time - MAX_LAG_COMPENSATION_TIME) {
			history.removeAt(0);
			hasEnoughHistory = true;
		}
		
		return true;
	}
}

void PluginInit()  {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	lastPlrButtons.resize(33);
	lastM16Delay1.resize(33);
	lastM16Delay2.resize(33);
	
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
	
	// disabling turrets would make defendthefort boss harder
	//g_monster_blacklist["monster_sentry"] = true;
	//g_monster_blacklist["monster_miniturret"] = true;
	//g_monster_blacklist["monster_turret"] = true;
	
	if (g_Engine.time > 4) { // plugin reloaded mid-map?
		late_init();
	}
	
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
		
		if (mon is null or mon.pev.deadflag != DEAD_NO) {
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

void rewind_monsters(CBasePlayer@ plr, PlayerState@ state) {
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

	int bestHistoryIdx = 0;
	float t = 0;

	for (uint i = 0; i < laggyEnts.size(); i++) {
		
		LagEnt@ lagEnt = laggyEnts[i];
		CBaseMonster@ mon = cast<CBaseMonster@>(lagEnt.h_ent.GetEntity());
		
		if (mon is null) {
			continue;
		}
		if (!lagEnt.hasEnoughHistory || mon.entindex() == plr.entindex()) {
			//println("Not enough history for monster");
			continue;
		}

		g_rewind_count++;
		
		// get state closest to the time the player shot
		if (bestHistoryIdx == 0) {
			for (uint k = 0; k < laggyEnts[i].history.size(); k++) {
				if (lagEnt.history[k].time >= shootTime || k == lagEnt.history.size()-1) {
					bestHistoryIdx = k;
					
					// interpolate between states to get the exact position the monster was in when the player shot
					// this probably won't matter much unless the server framerate is really low.
					EntState@ newState = lagEnt.history[bestHistoryIdx]; // later than shoot time
					EntState@ oldState = lagEnt.history[bestHistoryIdx-1]; // earlier than shoot time	
					
					t = (shootTime - oldState.time) / (newState.time - oldState.time);
					
					//println("Best delta: " + int((laggyEnts[i].history[k].time - shootTime)*1000) + " for ping " + iping);
					break;
				}
			}
			
			if (bestHistoryIdx == 0) {
				continue;
			}
		}
		
		lagEnt.isRewound = true;		
		lagEnt.currentState.origin = mon.pev.origin;
		lagEnt.currentState.angles = mon.pev.angles;
		lagEnt.currentState.sequence = mon.pev.sequence;
		lagEnt.currentState.frame = mon.pev.frame;
		lagEnt.currentHealth = mon.pev.health;
		
		EntState@ newState = lagEnt.history[bestHistoryIdx]; // later than shoot time
		EntState@ oldState = lagEnt.history[bestHistoryIdx-1]; // earlier than shoot time		

		mon.pev.sequence = t >= 0.5f ? newState.sequence : oldState.sequence;
		mon.pev.frame = oldState.frame + (newState.frame - oldState.frame)*t;
		mon.pev.angles = t >= 0.5f ? newState.angles : oldState.angles;
		mon.pev.origin = oldState.origin + (newState.origin - oldState.origin)*t;

		mon.m_LastHitGroup = -1337; // for detecting hits on things that don't take damage from bullets (garg)
		
		if (state.debug > 1) {
			EntState tweenState;
			tweenState.origin = mon.pev.origin;
			tweenState.sequence = mon.pev.sequence;
			tweenState.frame = mon.pev.frame;
			tweenState.angles = mon.pev.angles;
			lagEnt.debugState = tweenState;
		}
	}
}

CBaseEntity@ undo_rewind_monsters(PlayerState@ state, bool didShoot) {
	CBaseEntity@ hitTarget = null;
	
	for (uint i = 0; i < laggyEnts.size(); i++) {
		LagEnt@ lagEnt = laggyEnts[i];
		CBaseMonster@ mon = cast<CBaseMonster@>(lagEnt.h_ent.GetEntity());
		if (!lagEnt.isRewound or mon is null) {
			continue;
		}

		// move back to current position
		mon.pev.origin = lagEnt.currentState.origin;
		mon.pev.sequence = lagEnt.currentState.sequence;
		mon.pev.frame = lagEnt.currentState.frame;
		mon.pev.angles = lagEnt.currentState.angles;
		
		lagEnt.isRewound = false;
		
		if (state.debug > 1 && didShoot) {
			debug_rewind(mon, lagEnt.debugState);
		}
		
		if (mon.pev.health < lagEnt.currentHealth || mon.m_LastHitGroup != -1337) {
			//hits++;
			@hitTarget = @mon;
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
	
	if (string(ent.pev.classname).Find("monster_") == 0) {
		add_lag_comp_ent(ent);
	}
	
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

// will the weapon fire this frame?
bool can_weapon_fire(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {		
	if (g_CustomEntityFuncs.IsCustomEntity(wep.pev.classname)) {
		return can_custom_weapon_fire(plr, wep);
	}
	
	if (plr.m_flNextAttack > 0)
		return false;

	int buttons = plr.m_afButtonPressed | plr.m_afButtonLast | plr.m_afButtonReleased;
	bool primaryFire = buttons & IN_ATTACK != 0;
	bool secondaryFire = buttons & IN_ATTACK2 != 0;
	bool hasPrimaryAmmo = wep.m_iClip > 0 || (wep.m_iClip == -1 && plr.m_rgAmmo( wep.m_iPrimaryAmmoType ) > 0);
	bool hasSecondaryAmmo = wep.m_iClip2 > 0;
	bool primaryFireIsNow = wep.m_flNextPrimaryAttack <= 0;
	bool inWater = plr.pev.waterlevel == 3;
	
	if (wep.pev.classname == "weapon_9mmhandgun") {
		return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && (primaryFire || secondaryFire);
	}
	else if (wep.pev.classname == "weapon_9mmAR") {
		return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && primaryFire && !secondaryFire && !inWater;
	}
	else if (wep.pev.classname == "weapon_shotgun") {
		bool firing = (primaryFire && primaryFireIsNow) || (secondaryFire && wep.m_flNextSecondaryAttack <= 0);
		return hasPrimaryAmmo && !wep.m_fInReload && firing && !inWater;
	}
	else if (wep.pev.classname == "weapon_m16") {
		// will fire this frame if primary delay goes positive (bullet 1)
		// or if secondary delay goes positive after the first bullet (bullet 2+3)
		bool shotFirstBullet = primaryFire && wep.m_flNextPrimaryAttack >= 0 && lastM16Delay1[plr.entindex()] < 0;
		bool shotBurstBullet = wep.m_flNextSecondaryAttack < 0 && lastM16Delay2[plr.entindex()] >= 0 && wep.m_flNextPrimaryAttack > 0.2f;
		bool firing = shotFirstBullet || shotBurstBullet;

		lastM16Delay1[plr.entindex()] = wep.m_flNextPrimaryAttack;
		lastM16Delay2[plr.entindex()] = wep.m_flNextSecondaryAttack;
		
		return hasPrimaryAmmo && firing && !wep.m_fInReload && !secondaryFire && !inWater;
	}
	else if (wep.pev.classname == "weapon_uzi" && wep.m_fIsAkimbo) {
		return primaryFire && (hasPrimaryAmmo || hasSecondaryAmmo) && primaryFireIsNow && !wep.m_fInReload && !inWater;
	}
	else if (wep.pev.classname == "weapon_gauss") {		
		if ((plr.m_afButtonPressed & IN_ATTACK2) == 0 && (lastPlrButtons[plr.entindex()] & IN_ATTACK2) != 0) {
			return !inWater;
		} else {
			return primaryFire && !secondaryFire && hasPrimaryAmmo && !inWater;
		}
	}
	else if (wep.pev.classname == "weapon_egon") {
		return hasPrimaryAmmo && (primaryFire && !secondaryFire) && wep.pev.dmgtime < g_Engine.time && wep.m_flNextPrimaryAttack < g_Engine.time && !inWater;
	}
	else if (wep.pev.classname == "weapon_shockrifle") {
		float nextDmg = wep.pev.dmgtime - g_Engine.time;
		return hasPrimaryAmmo && wep.m_flNextSecondaryAttack <= 0 && secondaryFire && nextDmg < 0 && !inWater;
	}
	
	return hasPrimaryAmmo && primaryFireIsNow && !wep.m_fInReload && primaryFire && !inWater;
}

// called before weapon shoot code
HookReturnCode PlayerPostThink(CBasePlayer@ plr) {
	if (!g_enabled) {
		return HOOK_CONTINUE;
	}
	
	playerWasCompensated = false;
	
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
	if (wep !is null && !g_no_compensate_weapons.exists(wep.pev.classname)) {
	
		if (can_weapon_fire(plr, wep)) {
			//println("COMPENSATE " + g_Engine.time);
			playerWasCompensated = true;
			g_compensations++;
			
			playerPostThinkAmmo = wep.m_iClip;
			PlayerState@ state = getPlayerState(plr);
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
	
	CBaseEntity@ hitTarget = undo_rewind_monsters(state, didPlayerShoot);
	if (state.hitmarker && hitTarget !is null) {
		show_hit_marker(plr, hitTarget);
	}
	
	return HOOK_CONTINUE;
}
