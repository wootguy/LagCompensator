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

	bool enabled = false;
	int compensation = 0;
	int adjustMode = 0;
	int debug = 0;
	bool hitmarker = true;
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
	EntState debugState; // used to display a debug model when a player shoots
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
	println("lagc polling started");
	@update_interval = g_Scheduler.SetInterval("update_ent_history", g_update_delay, -1);
	@cleanup_interval = g_Scheduler.SetInterval("cleanup_ents", 5.0f, -1);
}

void stop_polling() {
	println("lagc polling stopped");
	g_Scheduler.RemoveTimer(update_interval);
	g_Scheduler.RemoveTimer(cleanup_interval);
	@update_interval = null;
	@cleanup_interval = null;
}

void late_init() {		
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
		
		mon.m_LastHitGroup = -1337; // special value to indicate the monster was NOT hit by the player
		
		if (state.debug > 1) {
			EntState tweenState;
			tweenState.origin = mon.pev.origin;
			tweenState.sequence = mon.pev.sequence;
			tweenState.frame = mon.pev.frame;
			tweenState.angles = mon.pev.angles;
			laggyEnts[i].debugState = tweenState;
		}
	}
	
	return rewind_count;
}

CBaseEntity@ undo_rewind_monsters(PlayerState@ state, bool didShoot) {
	CBaseEntity@ hitTarget = null;
	
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
		
		if (state.debug > 1 && didShoot) {
			debug_rewind(mon, laggyEnts[i].debugState);
		}
		
		if (mon.m_LastHitGroup != -1337) {
			println("HIT? " + mon.m_LastHitGroup);
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

HookReturnCode WeaponPrimaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {
	return HOOK_CONTINUE;
}

HookReturnCode WeaponSecondaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {
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
	
	return HOOK_CONTINUE;
}

int playerPostThinkAmmo = 0;

// called before weapon primary fire code for a single player
HookReturnCode PlayerPostThink(CBasePlayer@ plr) {		
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
	if (wep !is null) {
		playerPostThinkAmmo = wep.m_iClip;
		
		PlayerState@ state = getPlayerState(plr);
		rewind_monsters(plr, state);
	}
	
	return HOOK_CONTINUE;
}

// called after weapon primary fire code for a single player
HookReturnCode PlayerUse( CBasePlayer@ plr, uint& out uiFlags )
{	
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
	if (wep !is null) {
		PlayerState@ state = getPlayerState(plr);
		
		bool didPlayerShoot = wep.m_iClip != playerPostThinkAmmo;
		
		CBaseEntity@ hitTarget = undo_rewind_monsters(state, didPlayerShoot);
		if (state.hitmarker && hitTarget !is null) {
			show_hit_marker(plr, hitTarget);
		}
	}
	return HOOK_CONTINUE;
}
