#include "weapons"
#include "util"

// TODO:
// - auto-enable for high pings?
// - gauss explosion broken?
// EVERYTHING is gibbing when disabled (undo gib after the shot possible?)

// can't reproduce:
// - extreme lag barnacle weapon op_blackmesa4

// minor todo:
// - compensate in PvP
// - compensate moving platforms somehow?
// - compensate moving breakable solids and/or buttons
// - egon maybe
// - gauss reflections+explosions
// - move blood effect closer to monster (required linking monsters to LagEnt)
// - show monster info at rewind position
// - performance improvements: filter visible monsters before rewind?
// - use BulletAccuracy method somehow
// - custom weapon support?

// unfixable(?) bugs:
// - monsters bleed and react to being shot in the non-rewound position, but will take no damage
//   - the blood effect can be disabled but has other side effects (no bleeding from projectiles or NPC bullets)
// - skill CVars will show "0" damage for the supported weapons
// - monsters ALWAYS gib certain monsters from mp5 when disabled
//   - headcrab, zombie, gonome, alien grunt, alien slave, bullsquid, pit drone, voltigore, grunt, shocktrooper

const float MAX_LAG_COMPENSATION_TIME = 2.0f; // 2 seconds
const float BULLET_RANGE = 8192;
const string CUSTOM_DAMAGE_KEY = "$f_lagc_dmg"; // used to restore custom damage values on lagged bullets
const string WEAPON_STATE_KEY = "$i_lagc_state"; // weapon compensation state
const string hitmarker_spr = "sprites/misc/mlg.spr";
const string hitmarker_snd = "misc/hitmarker.mp3";
const int BULLET_UZI = 0;
const int BULLET_GAUSS = 8;
const int BULLET_GAUSS2 = 9;
const int BULLET_EGON = 10;

bool shotgun_doubleshot_mode = false;
bool pistol_silencer_mode = false;
bool is_classic_mode = false;
bool g_enabled = true;
float g_update_delay = 0.05f; // time between monster state updates
CScheduledFunction@ update_interval = null;
CScheduledFunction@ player_state_interval = null;
CScheduledFunction@ cvar_interval = null;
CScheduledFunction@ cleanup_interval = null;

array<LagEnt> laggyEnts; // ents that are lag compensated
array<float> g_bullet_damage; // used to calculate compensated bullet damage
array<float> last_shoot; // needed to calculate recoil. punchangle is not updated when shooting weapons.
array<float> gauss_start_charge; // needed to calculate how much damage to apply for secondary fire

// stuff needed to know if a player shot or nod
array<int> last_shotgun_clips; // none of the weapon props are reliable.
array<int> last_minigun_clips; // seconday fire hook is called many times for a single bullet.
array<float> egon_last_dmg; // egon fires at 10fps, but hook called at one gorllion fps.

dictionary g_monster_blacklist; // don't track these - waste of time
dictionary g_weapon_info;

dictionary g_player_states;
int g_state_count = 0;

CClientCommand _lagc("lagc", "Lag compensation commands", @consoleCmd );

void PluginInit()  {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponSecondaryAttack, @WeaponSecondaryAttack );
	g_Hooks.RegisterHook( Hooks::Game::EntityCreated, @EntityCreated );
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

void late_init() {
	check_classic_mode();

	save_cvar_values();
	
	if (g_enabled)
		disable_default_damages();
		
	reload_ents();
	start_polling();
}

enum WeaponCompensationStates {
	// default mode for all weapons. The plugin needs to modify the gun so it works properly
	WEP_NOT_INITIALIZED,
	
	// weapon has been modified so that only this plugin can deal damage.
	// That means saving any map-specific damage to a separate keyvalue, then
	// setting the custom damage to 0, so that it uses the skill setting (which will also be 0, unless 556 ammo is used)
	WEP_COMPENSATE_ON,
	
	// weapon has a custom damage set so that the default sven damage logic works.
	// A custom damage is needed because the skill settings will all be set to 0.
	WEP_COMPENSATE_OFF
}

enum AdjustModes {
	ADJUST_NONE, // use ping value
	ADJUST_ADD, // add to ping value
	ADJUST_SUB // subtract from ping value
}

class PlayerState
{
	// Never store player handle? It needs to be set to null on disconnect or else states start sharing
	// player handles and cause weird bugs or break states entirely. Check if disconnect is called
	// if player leaves during level change.

	bool enabled = true;
	int compensation = 0;
	int adjustMode = 0;
	int debug = 0;
	bool hitmarker = true;
}

class WeaponInfo {
	int bulletType;
	int dmgType;
	Vector spread;
	string skillSetting;

	WeaponInfo() {}
	
	WeaponInfo(int bulletType, int dmgType, Vector spread, string skillSetting) {
		this.bulletType = bulletType;
		this.dmgType = dmgType;
		this.spread = spread;
		this.skillSetting = skillSetting;
	}
}

class LagBullet {
	Vector vecAim;
	float damage;
	
	LagBullet() {}
	
	LagBullet(Vector spread, float damage) {	
		float x, y;
		g_Utility.GetCircularGaussianSpread( x, y );
		
		this.vecAim = g_Engine.v_forward + x*spread.x*g_Engine.v_right + y*spread.y*g_Engine.v_up;
		this.damage = damage;
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
}

// removes deleted ents
void cleanup_ents() {
	array<LagEnt> newLagEnts;
	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		if (mon is null) {
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
	
	oldEnt.pev.sequence = lastState.sequence;
	oldEnt.pev.frame = lastState.frame;
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
		if (mon is null) {
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
					g_Utility.BloodStream(tr.vecEndPos, tr.vecPlaneNormal, mon.BloodColor(), 160);
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
	else if (ent.pev.classname == "playerhornet") {
	
	}
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
	
	g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, '\nPlayers using compensation (' + count + ' / ' + total + '):\n');
	
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
			
			mode += ", hitmarks " + (state.hitmarker ? "ON" : "OFF") + ", debug " + state.debug;
				
			g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, '    ' + plr.pev.netname + ": " + mode + "\n");
		}
	}
	
	g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, "\nCompensated entities (" + laggyEnts.size() + "):\n");
	for (uint i = 0; i < laggyEnts.size(); i++ )
	{
		LagEnt lagEnt = laggyEnts[i];
		CBaseEntity@ ent = lagEnt.h_ent;
		string cname = ent !is null ? string(ent.pev.classname) : "null";
		
		g_PlayerFuncs.ClientPrint(debugger, HUD_PRINTCONSOLE, "    " + cname + ": " + lagEnt.history.size() + " states\n");
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
					enable_default_damages();
					g_PlayerFuncs.SayTextAll(plr, "Lag compensation plugin disabled.\n");
				}
				else if (arg == "resume" && isAdmin) {
					g_enabled = true;
					reload_ents();
					disable_default_damages();
					g_PlayerFuncs.SayTextAll(plr, "Lag compensation plugin enabled. Say '.lagc' for help.\n");
				}
				else if (arg == "reload" && isAdmin) {
					g_PlayerFuncs.SayTextAll(plr, "Reloaded skill settings\n");
					reload_skill_files();
					late_init();
					reload_ents();
					reset_weapon_damages();
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
					CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
					if (wep !is null) {
						debug_bullet_damage(plr, wep, 0, false);
					}
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
					
					int amt = Math.min(atoi(arg), int(MAX_LAG_COMPENSATION_TIME*1000));
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
				int maxComp = int(MAX_LAG_COMPENSATION_TIME*1000);
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
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".lagc x" to toggle hit confirmations.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        This will make it obvious when you hit a target. Blood effects\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        are unreliable due to how this plugin works.\n');
				
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
		return HOOK_HANDLED;
	}
	return HOOK_CONTINUE;
}

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}