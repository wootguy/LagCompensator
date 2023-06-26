#include "main.h"

// Description of plugin
plugin_info_t Plugin_info = {
	META_INTERFACE_VERSION,	// ifvers
	"LagCompensator",	// name
	"1.0",	// version
	__DATE__,	// date
	"w00tguy",	// author
	"https://github.com/wootguy/",	// url
	"LAGC",	// logtag, all caps please
	PT_ANYTIME,	// (when) loadable
	PT_ANYPAUSE,	// (when) unloadable
};

const float MAX_LAG_COMPENSATION_SECONDS = 1.0f; // don't set too high or else newly spawned monsters take too long to be compensated
const char* hitmarker_spr = "sprites/misc/mlg.spr";
const char* hitmarker_snd = "misc/hitmarker.mp3";

bool g_enabled = true;
float g_update_delay = 0.05f; // time between monster state updates
ScheduledFunction update_interval; // time between removal of deleted entities from entity history
ScheduledFunction cleanup_interval; // time between removal of deleted entities from entity history
ScheduledFunction map_activate_sched; // how often to update rewind stats

vector<LagEnt> laggyEnts; // ents that are lag compensated
vector<HitmarkEnt> hitmarkEnts; // ents that show hitmarkers but aren't lag compensated
set<string> g_monster_blacklist; // don't track these - waste of time
set<string> g_custom_hitmark_ents;
map<string, PlayerState*> g_player_states;
set<string> g_no_compensate_weapons; // skip compensating these weapons to improve performance
int g_state_count = 0;
int lastPlrButtons[33]; // player button properties dont't work right for secondary/tertiary fire
float lastM16Delay1[33]; // hack to figure out when the m16 will fire next
float lastM16Delay2[33]; // hack to figure out when the m16 will fire next
float g_lastAttack[33]; // for weapon cooldowns
bool g_should_scan_for_new_entities = false;
bool trackedEntities[8192] = { false };

int g_compensations = 0;
int playerPostThinkAmmo = 0;
bool playerWasCompensated = false;

bool LagEnt::update_history() {
	CBaseEntity* ent = h_ent;

	if (!ent) {
		return false;
	}

	EntState state;
	state.time = gpGlobals->time;
	state.origin = ent->pev->origin;
	state.angles = ent->pev->angles;
	state.sequence = ent->pev->sequence;
	state.frame = ent->pev->frame;

	history.push_back(state);

	while (history[0].time < gpGlobals->time - MAX_LAG_COMPENSATION_SECONDS) {
		history.erase(history.begin());
		hasEnoughHistory = true;
	}

	return true;
}

// get ping time in seconds
float PlayerState::getCompensationPing(CBasePlayer* plr) {
	int iping;

	if (adjustMode == ADJUST_NONE) {
		if (compensation > 0) {
			iping = compensation;
		}
		else {
			int packetLoss;
			g_engfuncs.pfnGetPlayerStats(plr->edict(), &iping, &packetLoss);
		}
	}
	else {
		int packetLoss;
		g_engfuncs.pfnGetPlayerStats(plr->edict(), &iping, &packetLoss);

		if (adjustMode == ADJUST_ADD) {
			iping += compensation;
		}
		else {
			iping -= compensation;
		}
	}

	return float(iping) / 1000.0f;
}

PlayerState& getPlayerState(edict_t* plr) {
	string steamId = getPlayerUniqueId(plr);

	if (g_player_states.find(steamId) == g_player_states.end()) {
		PlayerState* newState = new PlayerState();
		g_player_states[steamId] = newState;
	}

	return *g_player_states[steamId];
}

PlayerState& getPlayerState(CBasePlayer* plr) {
	return getPlayerState(plr->edict());
}

void add_lag_comp_ent(CBaseEntity* ent) {
	if (!ent) {
		return;
	}
	if (ent->IsMonster() && (ent->IsPlayer() || ent->GetClassname().find("monster_") == 0)) {
		if (g_monster_blacklist.count(ent->GetClassname())) {
			return;
		}
		laggyEnts.push_back(LagEnt(ent));
		trackedEntities[ent->entindex()] = true;
	}
	else if (ent->IsBreakable() || g_custom_hitmark_ents.count(ent->GetClassname())) {
		hitmarkEnts.push_back(HitmarkEnt(ent));
		trackedEntities[ent->entindex()] = true;
	}
}

// removes deleted ents
void cleanup_ents() {
	vector<LagEnt> newLagEnts;
	vector<HitmarkEnt> newHitmarkEnts;
	memset(trackedEntities, 0, sizeof(bool) * 8192);

	for (int i = 0; i < laggyEnts.size(); i++) {
		CBaseEntity* mon = laggyEnts[i].h_ent.GetEntity();

		if (!mon) {
			continue;
		}

		if (mon->IsPlayer()) {
			CBasePlayer* plr = (CBasePlayer*)mon;
			if (!plr->IsConnected())
				continue;
		}

		newLagEnts.push_back(laggyEnts[i]);
		trackedEntities[mon->entindex()] = true;
	}

	for (int i = 0; i < hitmarkEnts.size(); i++) {
		CBaseEntity* ent = hitmarkEnts[i].h_ent;

		if (!ent) {
			continue;
		}
		newHitmarkEnts.push_back(hitmarkEnts[i]);
		trackedEntities[ent->entindex()] = true;
	}

	laggyEnts = newLagEnts;
	hitmarkEnts = newHitmarkEnts;
}

void update_ent_history() {
	if (!g_enabled) {
		return;
	}

	if (g_should_scan_for_new_entities) {
		for (int i = 0; i < gpGlobals->maxEntities; i++) {
			edict_t* ent = INDEXENT(i);
			if (ent && ent->pvPrivateData && !trackedEntities[i]) {
				add_lag_comp_ent((CBaseEntity*)ent->pvPrivateData);
			}
		}
		g_should_scan_for_new_entities = false;
	}

	g_state_count = 0;
	for (int i = 0; i < laggyEnts.size(); i++) {
		laggyEnts[i].update_history();
		g_state_count += laggyEnts[i].history.size();
	}
}

void reload_ents() {
	laggyEnts.resize(0);
	hitmarkEnts.resize(0);
	memset(trackedEntities, 0, sizeof(bool)*8192);

	int failsafe = 0;
	for (int i = 0; i < gpGlobals->maxEntities; i++) {
		edict_t* ent = INDEXENT(i);
		if (ent && ent->pvPrivateData) {
			add_lag_comp_ent((CBaseEntity*)ent->pvPrivateData);
		}
	}
}

void start_polling() {
	update_interval = g_Scheduler.SetInterval(update_ent_history, g_update_delay, -1);
	cleanup_interval = g_Scheduler.SetInterval(cleanup_ents, 0.5f, -1);
}

void stop_polling() {
	g_Scheduler.RemoveTimer(update_interval);
	g_Scheduler.RemoveTimer(cleanup_interval);
}

void late_init() {
	reload_ents();
	start_polling();

	loadSoundCacheFile();
}

void MapActivate() {
	if (gpGlobals->time < 2.0f) {
		g_Scheduler.SetTimeout(MapActivate, 2.0f - gpGlobals->time);
		return;
	}

	late_init();
}

void MapChange() {
	stop_polling();
	RETURN_META(MRES_IGNORED);
}

void MapInit(edict_t* pEdictList, int edictCount, int maxClients) {
	// Not using PrecacheModel because HUD elements don't require the server to load the sprite
	g_engfuncs.pfnPrecacheGeneric((char*)hitmarker_spr);

	PrecacheSound(hitmarker_snd);
	g_engfuncs.pfnPrecacheGeneric((char*)(string("sound/") + hitmarker_snd).c_str());

	RETURN_META(MRES_IGNORED);
}

void MapInit_post(edict_t* pEdictList, int edictCount, int maxClients) {
	// techinically not correct, should use game time instead of wall clock time
	// probably the server will freeze before map init is done
	g_Scheduler.RemoveTimer(map_activate_sched);
	map_activate_sched = g_Scheduler.SetTimeout(MapActivate, 2);
	loadSoundCacheFile();

	RETURN_META(MRES_IGNORED);
}

void delay_kill(EHandle h_ent) {
	g_engfuncs.pfnRemoveEntity(h_ent);
}

void debug_rewind(CBaseMonster* mon, EntState lastState) {
	map<string,string> keys;
	keys["origin"] = vecToString(lastState.origin);
	keys["angles"] = vecToString(lastState.angles);
	keys["model"] = STRING(mon->pev->model);
	keys["rendermode"] = "1";
	keys["renderamt"] = "200";
	CBaseMonster* oldEnt = (CBaseMonster*)CreateEntity("cycler", keys, true)->pvPrivateData;
	oldEnt->pev->solid = SOLID_NOT;
	oldEnt->pev->movetype = MOVETYPE_NOCLIP;

	oldEnt->m_Activity = ACT_RELOAD;
	oldEnt->pev->sequence = lastState.sequence;
	oldEnt->pev->frame = lastState.frame;
	oldEnt->ResetSequenceInfo();
	oldEnt->pev->framerate = 0.00001f;

	g_Scheduler.SetTimeout(delay_kill, 1.0f, EHandle(oldEnt));
}

void rewind_monsters(CBasePlayer* plr, PlayerState& state) {
	float ping = state.getCompensationPing(plr);
	float shootTime = gpGlobals->time - ping;

	if (state.debug > 0 && laggyEnts.size() > 0) {
		string shift = "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
		float scale = (1.0f / MAX_LAG_COMPENSATION_SECONDS);
		int rate = int((g_state_count / laggyEnts.size()) * scale);
		ClientPrint(plr->edict(), HUD_PRINTCENTER, UTIL_VarArgs("%sCompensation: %d ms\nReplay FPS: %d",
			shift.c_str(), (int)(ping * 1000), rate));
	}

	int bestHistoryIdx = 0;

	for (int i = 0; i < laggyEnts.size(); i++) {

		LagEnt& lagEnt = laggyEnts[i];
		CBaseEntity* mon = lagEnt.h_ent;

		if (!mon) {
			continue;
		}
		if (lagEnt.history.size() <= 1 || mon->entindex() == plr->entindex() || mon->pev->deadflag != DEAD_NO) {
			//println("Not enough history for monster");
			continue;
		}

		int useHistoryIdx = bestHistoryIdx;

		// get state closest to the time the player shot
		if (bestHistoryIdx == 0 || !lagEnt.hasEnoughHistory) {
			for (int k = 0; k < lagEnt.history.size(); k++) {
				if (lagEnt.history[k].time >= shootTime || k == lagEnt.history.size() - 1) {
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
		lagEnt.currentState.origin = mon->pev->origin;
		lagEnt.currentState.angles = mon->pev->angles;
		lagEnt.currentState.sequence = mon->pev->sequence;
		lagEnt.currentState.frame = mon->pev->frame;
		lagEnt.currentHealth = mon->pev->health;
		lagEnt.currentDeadFlag = mon->pev->deadflag;

		// interpolate between states to get the exact position the monster was in when the player shot
		// this probably won't matter much unless the server framerate is really low.
		EntState& newState = lagEnt.history[bestHistoryIdx]; // later than shoot time
		EntState& oldState = lagEnt.history[bestHistoryIdx - 1]; // earlier than shoot time
		float t = (shootTime - oldState.time) / (newState.time - oldState.time);

		mon->pev->sequence = t >= 0.5f ? newState.sequence : oldState.sequence;
		mon->pev->frame = oldState.frame + (newState.frame - oldState.frame) * t;
		mon->pev->angles = t >= 0.5f ? newState.angles : oldState.angles;
		mon->pev->origin = oldState.origin + (newState.origin - oldState.origin) * t;

		//mon.m_LastHitGroup = -1337; // for detecting hits on things that don't take damage from bullets (garg)

		if (state.debug > 1) {
			EntState tweenState;
			tweenState.origin = mon->pev->origin;
			tweenState.sequence = mon->pev->sequence;
			tweenState.frame = mon->pev->frame;
			tweenState.angles = mon->pev->angles;
			lagEnt.debugState = tweenState;
		}
	}

	if (state.hitmarker) {
		for (int i = 0; i < hitmarkEnts.size(); i++) {
			CBaseEntity* ent = hitmarkEnts[i].h_ent;
			if (!ent) {
				continue;
			}
			hitmarkEnts[i].currentHealth = ent->pev->health;
		}
	}
}

CBaseEntity* undo_rewind_monsters(PlayerState& state, bool didShoot) {
	CBaseEntity* hitTarget = NULL;

	for (int i = 0; i < laggyEnts.size(); i++) {
		LagEnt& lagEnt = laggyEnts[i];
		CBaseEntity* ent = lagEnt.h_ent;
		if (!lagEnt.isRewound || !ent) {
			continue;
		}

		// move back to current position
		ent->pev->origin = lagEnt.currentState.origin;
		ent->pev->sequence = lagEnt.currentState.sequence;
		ent->pev->frame = lagEnt.currentState.frame;
		ent->pev->angles = lagEnt.currentState.angles;

		lagEnt.isRewound = false;

		if (state.debug > 1 && didShoot && ent->IsMonster()) {
			CBaseMonster* mon = (CBaseMonster*)ent;
			debug_rewind(mon, lagEnt.debugState);
		}

		if (ent->pev->health != lagEnt.currentHealth || ent->pev->deadflag != lagEnt.currentDeadFlag) {
			//hits++;
			hitTarget = ent;
		}
	}

	if (state.hitmarker) {
		for (int i = 0; i < hitmarkEnts.size(); i++) {
			CBaseEntity* ent = hitmarkEnts[i].h_ent;
			if (!ent) {
				continue;
			}
			if (ent->pev->health != hitmarkEnts[i].currentHealth) {
				//hits++;
				hitTarget = ent;
			}
		}
	}

	return hitTarget;
}

void show_hit_marker(CBasePlayer* plr, CBaseEntity* target) {
	HUDSpriteParams params;
	memset(&params, 0, sizeof(HUDSpriteParams));
	params.flags = HUD_SPR_MASKED | HUD_ELEM_SCR_CENTER_X | HUD_ELEM_SCR_CENTER_Y | HUD_ELEM_EFFECT_ONCE;
	params.spritename = string(hitmarker_spr).substr(string("sprites/").length());
	params.holdTime = 0.5f;
	params.x = 0;
	params.y = 0;
	params.color1 = RGBA(255, 255, 255, 255);
	params.color2 = RGBA(255, 255, 255, 0);
	params.fxTime = 0.8f;
	params.effect = HUD_EFFECT_RAMP_UP;
	params.channel = 15;
	HudCustomSprite(plr->edict(), params);

	PlaySound(target->edict(), CHAN_ITEM, hitmarker_snd, 0.8f, 0.0f, 0, 100, plr->entindex());
}

void EntityCreatedWait(EHandle h_ent) {
	if (!h_ent.IsValid() || !h_ent.GetEntity()) {
		return;
	}

	add_lag_comp_ent(h_ent);
}

int EntityCreated(edict_t* pent) {
	if (!g_enabled) {
		RETURN_META_VALUE(MRES_IGNORED, 0);
	}

	// ents usually aren't initialized until the next frame
	g_Scheduler.SetTimeout(EntityCreatedWait, 0, EHandle(pent));

	RETURN_META_VALUE(MRES_IGNORED, 0);
}

void ClientJoin(edict_t* plr)
{
	PlayerState& state = getPlayerState(plr);

	add_lag_comp_ent((CBaseEntity*)plr->pvPrivateData);
	RETURN_META(MRES_IGNORED);
}

bool will_weapon_fire_this_frame(CBasePlayer* plr, CBasePlayerWeapon* wep) {
	if (!plr->IsAlive() || plr->m_hTank.IsValid()) {
		return false;
	}

	//if (g_CustomEntityFuncs.IsCustomEntity(wep->pev->classname)) {
	//	return will_custom_weapon_fire_this_frame(plr, wep);
	//}

	if (plr->m_flNextAttack > 0)
		return false;

	int buttons = plr->m_afButtonPressed | plr->m_afButtonLast | plr->m_afButtonReleased;
	bool primaryFirePressed = (buttons & IN_ATTACK) != 0;
	bool secondaryFirePressed = (buttons & IN_ATTACK2) != 0;
	bool hasPrimaryAmmo = wep->m_iClip > 0 || (wep->m_iClip == -1 && wep->m_iPrimaryAmmoType != -1 && plr->m_rgAmmo[wep->m_iPrimaryAmmoType] > 0);
	bool hasSecondaryAmmo = wep->m_iClip2 > 0;
	bool primaryFireIsNow = wep->m_flNextPrimaryAttack <= 0;
	bool inWater = plr->pev->waterlevel == 3;
	string wepCname = wep->GetClassname();

	if (wepCname == "weapon_9mmhandgun") {
		return hasPrimaryAmmo && primaryFireIsNow && !wep->m_fInReload && (primaryFirePressed || secondaryFirePressed);
	}
	else if (wepCname == "weapon_9mmAR") {
		return hasPrimaryAmmo && primaryFireIsNow && !wep->m_fInReload && primaryFirePressed && !secondaryFirePressed && !inWater;
	}
	else if (wepCname == "weapon_shotgun") {
		bool firing = (primaryFirePressed && primaryFireIsNow) || (secondaryFirePressed && wep->m_flNextSecondaryAttack <= 0);
		return hasPrimaryAmmo && !wep->m_fInReload && firing && !inWater;
	}
	else if (wepCname == "weapon_m16") {
		// will fire this frame if primary delay goes positive (bullet 1)
		// or if secondary delay goes positive after the first bullet (bullet 2+3)
		bool shotFirstBullet = primaryFirePressed && wep->m_flNextPrimaryAttack >= 0 && lastM16Delay1[plr->entindex()] < 0;
		bool shotBurstBullet = wep->m_flNextSecondaryAttack < 0 && lastM16Delay2[plr->entindex()] >= 0 && wep->m_flNextPrimaryAttack > 0.2f;
		bool firing = shotFirstBullet || shotBurstBullet;

		lastM16Delay1[plr->entindex()] = wep->m_flNextPrimaryAttack;
		lastM16Delay2[plr->entindex()] = wep->m_flNextSecondaryAttack;

		return hasPrimaryAmmo && firing && !wep->m_fInReload && !secondaryFirePressed && !inWater;
	}
	else if (wepCname == "weapon_uzi") {
		if (wep->m_fIsAkimbo) {
			return primaryFirePressed && (hasPrimaryAmmo || hasSecondaryAmmo) && primaryFireIsNow && !wep->m_fInReload && !inWater;
		}
		else {
			return hasPrimaryAmmo && primaryFireIsNow && !wep->m_fInReload && primaryFirePressed && !secondaryFirePressed && !inWater;
		}
	}
	else if (wepCname == "weapon_gauss") {
		if ((plr->m_afButtonPressed & IN_ATTACK2) == 0 && (lastPlrButtons[plr->entindex()] & IN_ATTACK2) != 0) {
			return !inWater;
		}
		else {
			return primaryFirePressed && !secondaryFirePressed && hasPrimaryAmmo && !inWater;
		}
	}
	else if (wepCname == "weapon_egon") {
		return hasPrimaryAmmo && (primaryFirePressed && !secondaryFirePressed) && wep->pev->dmgtime < gpGlobals->time && wep->m_flNextPrimaryAttack < gpGlobals->time && !inWater;
	}
	else if (wepCname == "weapon_shockrifle") {
		float nextDmg = wep->pev->dmgtime - gpGlobals->time;
		return hasPrimaryAmmo && wep->m_flNextSecondaryAttack <= 0 && secondaryFirePressed && nextDmg < 0 && !inWater;
	}

	// 357, deagle, saw, sniper
	return hasPrimaryAmmo && primaryFireIsNow && !wep->m_fInReload && primaryFirePressed && !inWater;
}

// called before weapon shoot code
void PlayerPostThink(edict_t* ed_plr) {
	if (!g_enabled) {
		RETURN_META(MRES_IGNORED);
	}
	CBasePlayer* plr = (CBasePlayer*)ed_plr->pvPrivateData;

	playerWasCompensated = false;

	CBasePlayerWeapon* wep = (CBasePlayerWeapon*)plr->m_hActiveItem.GetEntity();
	if (wep && !g_no_compensate_weapons.count(wep->GetClassname())) {
		//println("COMP? " + wep.pev.classname);

		PlayerState& state = getPlayerState(plr);

		if (state.enabled && will_weapon_fire_this_frame(plr, wep)) {
			//println("COMPENSATE %.3f", gpGlobals->time);
			playerWasCompensated = true;
			g_compensations++;

			playerPostThinkAmmo = wep->m_iClip;
			rewind_monsters(plr, state);
		}

		lastPlrButtons[plr->entindex()] = plr->m_afButtonPressed;
	}

	RETURN_META(MRES_IGNORED);
}

// called after weapon shoot code
void PlayerPostThink_post(edict_t* ed_plr) {
	if (!g_enabled || !playerWasCompensated) {
		RETURN_META(MRES_IGNORED);
	}
	CBasePlayer* plr = (CBasePlayer*)ed_plr->pvPrivateData;

	CBasePlayerWeapon* wep = (CBasePlayerWeapon*)plr->m_hActiveItem.GetEntity();
	if (!wep) {
		RETURN_META(MRES_IGNORED);
	}

	PlayerState& state = getPlayerState(plr);

	bool didPlayerShoot = wep->m_iClip != playerPostThinkAmmo;

	if (didPlayerShoot)
		g_lastAttack[plr->entindex()] = gpGlobals->time;

	CBaseEntity* hitTarget = undo_rewind_monsters(state, didPlayerShoot);
	if (state.hitmarker && hitTarget) {
		show_hit_marker(plr, hitTarget);
	}

	RETURN_META(MRES_IGNORED);
}

void StartFrame() {
	g_Scheduler.Think();
	RETURN_META(MRES_IGNORED);
}

edict_t* CreateEntity() {
	g_should_scan_for_new_entities = true;
	RETURN_META_VALUE(MRES_IGNORED, NULL);
}

edict_t* CreateNamedEntity(int cname) {
	g_should_scan_for_new_entities = true;
	RETURN_META_VALUE(MRES_IGNORED, NULL);
}

void PluginInit() {
	g_dll_hooks.pfnServerActivate = MapInit;
	g_dll_hooks_post.pfnServerActivate = MapInit_post;
	g_dll_hooks.pfnServerDeactivate = MapChange;
	g_dll_hooks.pfnClientCommand = ClientCommand;
	g_dll_hooks_post.pfnClientPutInServer = ClientJoin;
	g_dll_hooks.pfnSpawn = EntityCreated;
	g_dll_hooks.pfnPlayerPostThink = PlayerPostThink;
	g_dll_hooks_post.pfnPlayerPostThink = PlayerPostThink_post;
	g_dll_hooks.pfnStartFrame = StartFrame;
	g_engine_hooks.pfnCreateEntity = CreateEntity;
	g_engine_hooks.pfnCreateNamedEntity = CreateNamedEntity;

	g_monster_blacklist.insert("monster_barney_dead");
	g_monster_blacklist.insert("monster_cockroach");
	g_monster_blacklist.insert("monster_furniture");
	g_monster_blacklist.insert("monster_handgrenade");
	g_monster_blacklist.insert("monster_hevsuit_dead");
	g_monster_blacklist.insert("monster_hgrunt_dead");
	g_monster_blacklist.insert("monster_human_grunt_ally_dead");
	g_monster_blacklist.insert("monster_leech");
	g_monster_blacklist.insert("monster_otis_dead");
	g_monster_blacklist.insert("monster_satchel");
	g_monster_blacklist.insert("monster_scientist_dead");
	g_monster_blacklist.insert("monster_sitting_scientist");
	g_monster_blacklist.insert("monster_tripmine");

	g_no_compensate_weapons.insert("weapon_crowbar");
	g_no_compensate_weapons.insert("weapon_pipewrench");
	g_no_compensate_weapons.insert("weapon_medkit");
	g_no_compensate_weapons.insert("weapon_crossbow");
	g_no_compensate_weapons.insert("weapon_rpg");
	g_no_compensate_weapons.insert("weapon_hornetgun");
	g_no_compensate_weapons.insert("weapon_handgrenade");
	g_no_compensate_weapons.insert("weapon_satchel");
	g_no_compensate_weapons.insert("weapon_tripmine");
	g_no_compensate_weapons.insert("weapon_snark");
	g_no_compensate_weapons.insert("weapon_sporelauncher");
	g_no_compensate_weapons.insert("weapon_displacer");

	g_custom_hitmark_ents.insert("func_breakable_custom");

	if (gpGlobals->time > 4) { // plugin reloaded mid-map?
		late_init();
	}
}

void PluginExit() {}