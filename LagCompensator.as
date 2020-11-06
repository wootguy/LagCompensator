#include "util"

// TODO:
// - use BulletAccuracy method somehow
// - custom weapon support?
// - chat commands
// - auto-enable for high pings?
// - disable damage for non-rewind position
//    - but still work with breakables/solids
// - custom weapon damage values
// - average ping times?
// - performance improvements: filter visible monsters before rewind?
// - remove dead monsters
// - gauss explosion broken?

// minor todo:
// - compensate in PvP
// - compensate moving platforms somehow?
// - compensate moving breakable solids and/or buttons
// - egon maybe
// - gauss reflections+explosions
// - move blood effect closer to monster (required linking monsters to LagEnt)
// - show monster info at rewind position

// unfixable(?) bugs:
// - monsters bleed and react to being shot in the non-rewound position, but will take no damage
//   - the blood effect can be disabled but has other side effects (no bleeding from projectiles or NPC bullets)
// - custom weapons don't work automatically, and might need code updates too
// - skill CVars will show "0" damage for the supported weapons

const float MAX_LAG_COMPENSATION_TIME = 1.0f; // 1 second
const float BULLET_RANGE = 8192;
const string CUSTOM_DAMAGE_KEY = "$f_lagc_dmg"; // used to restore custom damage values on lagged bullets
string hitmarker_spr = "sprites/misc/mlg.spr";
string hitmarker_snd = "misc/hitmarker.mp3";

bool shotgun_doubleshot_mode = false;
bool pistol_silencer_mode = false;
bool is_classic_mode = false;

array<LagEnt> laggyEnts;
array<float> g_bullet_damage;
array<int> last_shotgun_clips; // needed to know if a player shot or not. None of the weapon props are reliable.
array<int> last_minigun_clips; // needed to know if a player shot or not. Seconday fire hook is called many times for a single bullet.
array<float> last_shoot; // needed to calculate recoil. punchangle is not updated when shooting weapons.
array<float> gauss_start_charge;
dictionary g_supported_weapons;

dictionary g_player_states;
int g_state_count = 0;

void PluginInit() 
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponSecondaryAttack, @WeaponSecondaryAttack );
	g_Hooks.RegisterHook( Hooks::Game::EntityCreated, @EntityCreated );
	g_Hooks.RegisterHook( Hooks::Player::PlayerPreThink, @PlayerPreThink );
	
	g_Scheduler.SetInterval("update_ent_history", 0.0f, -1);
	g_Scheduler.SetInterval("refresh_cvars", 5.0f, -1);
	g_Scheduler.SetInterval("refresh_player_states", 1.0f, -1);
	
	init();
	
	if (g_Engine.time > 4) { // plugin reloaded mid-map?
		check_classic_mode();
		late_init();
		
		// reload skill settings
		string map_skill_file = "" + g_Engine.mapname + "_skl.cfg";
		g_EngineFuncs.ServerCommand("exec skill.cfg; exec " + map_skill_file + ";\n");
		g_EngineFuncs.ServerExecute();
	}
	refresh_ents();
	refresh_cvars();
}

void init() {
	last_shotgun_clips.resize(33);
	last_shoot.resize(33);
	last_minigun_clips.resize(33);
	gauss_start_charge.resize(33);
	for (int i = 0; i < 33; i++) {
		last_shotgun_clips[i] = 8;
		last_minigun_clips[i] = 0;
		last_shoot[i] = 0;
		gauss_start_charge[0] = -1;
	}
	
	g_supported_weapons.clear();
	g_supported_weapons["weapon_9mmhandgun"] = true;
	g_supported_weapons["weapon_357"] = true;
	g_supported_weapons["weapon_eagle"] = true;
	g_supported_weapons["weapon_uzi"] = true;
	g_supported_weapons["weapon_9mmAR"] = true;
	g_supported_weapons["weapon_shotgun"] = true;
	g_supported_weapons["weapon_gauss"] = true;
	g_supported_weapons["weapon_sniperrifle"] = true;
	g_supported_weapons["weapon_m249"] = true;
	g_supported_weapons["weapon_m16"] = true;
	g_supported_weapons["weapon_minigun"] = true;
}

void MapInit() {
	init();
	
	g_Game.PrecacheModel(hitmarker_spr);
	g_SoundSystem.PrecacheSound(hitmarker_snd);
	g_Game.PrecacheGeneric("sound/" + hitmarker_snd);
}

void MapActivate() {
	check_classic_mode();
	g_Scheduler.SetTimeout("late_init", 2);
}

void check_classic_mode() {
	// if the mp5 has secondary ammo, then we're probably in classic mode.
	// plugins can't access the classic mode API for some reason.
	// This has to be called after MapActivate or else the mp5 sounds like a pistol and reloads after every shot (wtf??).
	CBasePlayerWeapon@ mp5 = cast<CBasePlayerWeapon@>(g_EntityFuncs.Create("weapon_9mmAR", Vector(0,0,0), Vector(0,0,0), false));
	is_classic_mode = mp5.iMaxAmmo2() != -1;
	g_EntityFuncs.Remove(mp5);
}

void late_init() {
	g_bullet_damage.resize(0);
	g_bullet_damage.resize(10);
	
	g_bullet_damage[BULLET_UZI] = g_EngineFuncs.CVarGetFloat("sk_plr_uzi");
	g_bullet_damage[BULLET_PLAYER_9MM] = g_EngineFuncs.CVarGetFloat("sk_plr_9mm_bullet");
	g_bullet_damage[BULLET_PLAYER_MP5] = g_EngineFuncs.CVarGetFloat("sk_plr_9mmAR_bullet");
	g_bullet_damage[BULLET_PLAYER_SAW] = g_EngineFuncs.CVarGetFloat("sk_556_bullet");
	g_bullet_damage[BULLET_PLAYER_SNIPER] = g_EngineFuncs.CVarGetFloat("sk_plr_762_bullet");
	g_bullet_damage[BULLET_PLAYER_357] = g_EngineFuncs.CVarGetFloat("sk_plr_357_bullet");
	g_bullet_damage[BULLET_PLAYER_BUCKSHOT] = g_EngineFuncs.CVarGetFloat("sk_plr_buckshot");
	g_bullet_damage[BULLET_GAUSS] = g_EngineFuncs.CVarGetFloat("sk_plr_gauss");
	g_bullet_damage[BULLET_GAUSS2] = g_EngineFuncs.CVarGetFloat("sk_plr_secondarygauss");
	
	disable_default_damages();
}

void disable_default_damages() {
	// all damage will be done by this plugin or with the custom weapon damage keyvalue
	// otherwise enemies can be hit twice by the same bullet (sven bullet + plugin bullet)
	g_EngineFuncs.CVarSetFloat("sk_plr_uzi", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_9mm_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_9mmAR_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_556_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_762_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_357_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_buckshot", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_gauss", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_secondarygauss", 0);
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

void refresh_ents() {
	laggyEnts.resize(0);

	CBaseEntity@ ent;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "monster_*");
		if (ent !is null)
		{
			laggyEnts.insertLast(LagEnt(ent));
		}
	} while(ent !is null);
}

const int BULLET_UZI = 0;
const int BULLET_GAUSS = 8;
const int BULLET_GAUSS2 = 9;

void refresh_cvars() {
	// update bullet damages if cvars were changed mid-map
	array<float> changed_damages;
	changed_damages.resize(10);
	
	changed_damages[BULLET_UZI] = g_EngineFuncs.CVarGetFloat("sk_plr_uzi");
	changed_damages[BULLET_PLAYER_9MM] = g_EngineFuncs.CVarGetFloat("sk_plr_9mm_bullet");
	changed_damages[BULLET_PLAYER_MP5] = g_EngineFuncs.CVarGetFloat("sk_plr_9mmAR_bullet");
	changed_damages[BULLET_PLAYER_SAW] = g_EngineFuncs.CVarGetFloat("sk_556_bullet");
	changed_damages[BULLET_PLAYER_SNIPER] = g_EngineFuncs.CVarGetFloat("sk_plr_762_bullet");
	changed_damages[BULLET_PLAYER_357] = g_EngineFuncs.CVarGetFloat("sk_plr_357_bullet");
	changed_damages[BULLET_PLAYER_BUCKSHOT] = g_EngineFuncs.CVarGetFloat("sk_plr_buckshot");
	changed_damages[BULLET_GAUSS] = g_EngineFuncs.CVarGetFloat("sk_plr_gauss");
	changed_damages[BULLET_GAUSS2] = g_EngineFuncs.CVarGetFloat("sk_plr_secondarygauss");
	
	for (int i = 0; i < 10; i++) {
		if (changed_damages[i] != 0) {
			g_bullet_damage[i] = changed_damages[i];
		}
	}
	
	disable_default_damages();
	
	// these can also change mid-map
	shotgun_doubleshot_mode = g_EngineFuncs.CVarGetFloat("weaponmode_shotgun") == 1;
	pistol_silencer_mode = g_EngineFuncs.CVarGetFloat("weaponmode_9mmhandgun") == 1;
}

void refresh_player_states() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr is null or !plr.IsConnected())
			continue;
		
		CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
		
		if (wep !is null && g_supported_weapons.exists(wep.pev.classname)) {
			if (wep.pev.classname == "weapon_shotgun") {
				last_shotgun_clips[i] = wep.m_iClip;
			}
			if (wep.pev.classname == "weapon_minigun") {
				last_minigun_clips[i] = plr.m_rgAmmo(wep.m_iPrimaryAmmoType);
			}
			
			PlayerState@ state = getPlayerState(plr);			
			
			if (state.enabled && wep.m_flCustomDmg != 0) {
				bool usesDefaultDamage = wep.m_flCustomDmg < 1.0f;
				
				if (!usesDefaultDamage) {
					// save current custom damage, so it can be used later
					KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
					CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();
					pCustom.SetKeyvalue(CUSTOM_DAMAGE_KEY, wep.m_flCustomDmg);
					//println("Saved custom damage");
				}
				
				// prevent sven code from doing damage with this weapon (0 = use cvar, and cvars are set to do 0 damage)
				wep.m_flCustomDmg = 0;
			} else if (!state.enabled && wep.m_flCustomDmg == 0) {
				KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
				CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();
				if (pCustom.HasKeyvalue(CUSTOM_DAMAGE_KEY)) {
					CustomKeyvalue dmgKey( pCustom.GetKeyvalue( CUSTOM_DAMAGE_KEY ) );
					wep.m_flCustomDmg = dmgKey.GetFloat();
					//println("Restored custom damage " + wep.m_flCustomDmg);
				} else {
					// restore cvar damage
					wep.m_flCustomDmg = get_bullet_damage(wep.pev.classname);
				}
			}
		}
	}
}

void update_ent_history() {
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

float get_bullet_damage(string cname) {
	if (cname == "weapon_9mmhandgun") {
		return g_bullet_damage[BULLET_PLAYER_9MM];
	}
	else if (cname == "weapon_357" || cname == "weapon_eagle") {
		return g_bullet_damage[BULLET_PLAYER_357];
	}
	else if (cname == "weapon_uzi" || cname == "weapon_9mmAR") {
		return g_bullet_damage[BULLET_PLAYER_MP5];
	}
	else if (cname == "weapon_shotgun") {
		return g_bullet_damage[BULLET_PLAYER_BUCKSHOT];
	}
	else if (cname == "weapon_gauss") {
		return g_bullet_damage[BULLET_GAUSS];
	}
	else if (cname == "weapon_sniperrifle") {
		return g_bullet_damage[BULLET_PLAYER_SNIPER];
	}
	else if (cname == "weapon_m249" || cname == "weapon_m16" || cname == "weapon_minigun") {
		return g_bullet_damage[BULLET_PLAYER_SAW];
	}
	
	return 0; // whatever the cvar default is
}

array<LagBullet> get_bullets(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire) {
	string cname = wep.pev.classname;
	
	float damage = 0;
	Vector spread = Vector(0,0,0);
	int bulletCount = 1;
	
	if (cname == "weapon_9mmhandgun") {
		damage = g_bullet_damage[BULLET_PLAYER_9MM];
		spread = Vector(0.01, 0.01, 0.01);
		if (isSecondaryFire || (pistol_silencer_mode && !isSecondaryFire)) {
			spread = Vector(0.1, 0.1, 0.1);
		}
	}
	else if (cname == "weapon_357") {
		damage = g_bullet_damage[BULLET_PLAYER_357];
		spread = VECTOR_CONE_3DEGREES;
	}
	else if (cname == "weapon_eagle") {
		damage = g_bullet_damage[BULLET_PLAYER_357];
		spread = VECTOR_CONE_4DEGREES;
	}
	else if (cname == "weapon_uzi") {
		damage = g_bullet_damage[BULLET_PLAYER_MP5];
		spread = VECTOR_CONE_8DEGREES;
		if (wep.m_fIsAkimbo && wep.m_iClip > 0 && wep.m_iClip2 > 0) {
			bulletCount++;
		}
	}
	else if (cname == "weapon_9mmAR") {
		damage = g_bullet_damage[BULLET_PLAYER_MP5];
		spread = wep.m_fInZoom ? VECTOR_CONE_4DEGREES : VECTOR_CONE_6DEGREES;
	}
	else if (cname == "weapon_shotgun") {
		damage = g_bullet_damage[BULLET_PLAYER_BUCKSHOT];
		spread = isSecondaryFire ? Vector( 0.17365, 0.04362, 0.00 ) : Vector( 0.08716, 0.04362, 0.00  );
		bulletCount = 8;
		if (isSecondaryFire && (shotgun_doubleshot_mode || is_classic_mode)) {
			bulletCount = 12;
		}
	}
	else if (cname == "weapon_gauss") {
		damage = g_bullet_damage[BULLET_GAUSS];
		if (isSecondaryFire) {
			float charge = (g_Engine.time - gauss_start_charge[plr.entindex()]) / 4.0f;
			damage = g_bullet_damage[BULLET_GAUSS2] * Math.min(1.0f, charge);
		}
		spread = Vector(0,0,0);
	}
	else if (cname == "weapon_sniperrifle") {
		damage = g_bullet_damage[BULLET_PLAYER_SNIPER];
		spread = wep.m_fInZoom ? Vector(0,0,0) : VECTOR_CONE_6DEGREES;
	}
	else if (cname == "weapon_m249") {
		damage = g_bullet_damage[BULLET_PLAYER_SAW];
		spread = VECTOR_CONE_4DEGREES;
	}
	else if (cname == "weapon_m16") {
		damage = g_bullet_damage[BULLET_PLAYER_SAW];
		spread = VECTOR_CONE_4DEGREES;
	}
	else if (cname == "weapon_minigun") {
		damage = g_bullet_damage[BULLET_PLAYER_SAW];
		spread = VECTOR_CONE_4DEGREES;
	}
	else {
		println("Unsupported gun: " + cname);
		bulletCount = 0;
	}
	
	Math.MakeVectors(plr.pev.v_angle + getEstimatedRecoil(plr, wep, isSecondaryFire));
	
	KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
	CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();
	if (pCustom.HasKeyvalue(CUSTOM_DAMAGE_KEY)) {
		CustomKeyvalue dmgKey( pCustom.GetKeyvalue( CUSTOM_DAMAGE_KEY ) );
		damage = dmgKey.GetFloat();
	}
	
	array<LagBullet> bullets;
	for (int i = 0; i < bulletCount; i++) {
		bullets.insertLast(LagBullet(spread, damage));
	}
	
	return bullets;
}

Vector getEstimatedRecoil(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire) {
	float lastShootDelta = g_Engine.time - last_shoot[plr.entindex()];
	Vector recoil;

	if (lastShootDelta < 1) {
		if (wep.pev.classname == "weapon_357" || wep.pev.classname == "weapon_eagle" ||
			(!is_classic_mode && !shotgun_doubleshot_mode && isSecondaryFire && wep.pev.classname == "weapon_shotgun")) {
			recoil.x = -(1-lastShootDelta)*8;
		}
	}
	
	// other weapons have unpredictable recoil or use punchangle as expected

	//println("RECOIL " + lastShootDelta + " " + recoil.x + " " + plr.pev.punchangle.x);

	return recoil;
}

// primary fire hooks are called when reloading/empty/randomly
// this makes sure a bullet was actually shot
bool didPlayerShoot(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire) {

	if (wep.pev.classname == "weapon_9mmhandgun") {
		if (wep.m_bFireOnEmpty) { // fireOnEmpty doesn't work for secondary fire
			return false;
		}
		if (isSecondaryFire && (wep.ShouldReload() || pistol_silencer_mode)) {
			return false;
		}
	}
	else if (wep.pev.classname == "weapon_shotgun") {
		if (plr.pev.waterlevel == 3) {
			return false;
		}
	
		bool shooting = true;
		
		if (isSecondaryFire) {
			if (is_classic_mode || shotgun_doubleshot_mode) {
				shooting = last_shotgun_clips[plr.entindex()] >= 2;
			} else {
				shooting = last_shotgun_clips[plr.entindex()] > 0;
			}
		} else {
			shooting = last_shotgun_clips[plr.entindex()] > 0 || !wep.m_bFireOnEmpty;
		}
		
		last_shotgun_clips[plr.entindex()] = wep.m_iClip;
		
		if (!shooting) {
			return false;
		}
	}
	else if (wep.pev.classname == "weapon_uzi") {
		if (plr.pev.waterlevel == 3 || isSecondaryFire) {
			return false;
		}
	
		if (wep.m_fIsAkimbo) {
			if (wep.m_bFireOnEmpty && wep.m_iClip2 == 0) {
				// Not perfect, but I really don't want to add more polling for this rare(?) edge case.
				// The last bullet won't count if you:
				//		1) shoot all bullets in both guns
				// 		2) reload only the right gun
				// 		3) shoot all bullets again
				// 		4) reload only the left gun
				// 		5) shoot all bullets again. The last bullet in your left gun won't count.
				return false;
			}
		} else {
			return !wep.m_bFireOnEmpty;
		}
	}
	else if (wep.pev.classname == "weapon_minigun") {
		// movement speed check might not be reliable (probably a percentage of sc_maxspeed)
		if (wep.m_bFireOnEmpty || plr.pev.waterlevel == 3 || plr.pev.maxspeed > 20) {
			return false;
		}
		
		int ammoLeft = plr.m_rgAmmo(wep.m_iPrimaryAmmoType);
		if (last_minigun_clips[plr.entindex()] == ammoLeft) {
			return false;
		}
		
		last_minigun_clips[plr.entindex()] = ammoLeft;
	}
	else if (wep.pev.classname == "weapon_gauss") {
		if (wep.m_bFireOnEmpty || plr.pev.waterlevel == 3) {
			return false;
		}
		if (isSecondaryFire) {
			if (gauss_start_charge[plr.entindex()] == -1 && plr.m_rgAmmo(wep.m_iPrimaryAmmoType) > 0) {
				gauss_start_charge[plr.entindex()] = g_Engine.time;
			}
			return false;
		}
	}
	else if (isSecondaryFire || wep.m_bFireOnEmpty || plr.pev.waterlevel == 3) {
		return false;
	}
	
	return true;
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
	
	if (state.debug > 0) {
		string shift = "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
		g_PlayerFuncs.PrintKeyBindingString(plr, shift + "Compensation: " + iping + " ms\n" + 
			"Rewind FPS: " + (g_state_count / laggyEnts.size()));
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
		
		if (state.debug > 1)
			debug_rewind(mon, newState);
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

void compensate(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire, int burst_round=1, bool force_shoot=false)
{
	PlayerState@ state = getPlayerState(plr);
	
	if (!state.enabled) {
		return;
	}
	
	if (!force_shoot && !didPlayerShoot(plr, wep, isSecondaryFire)) {
		return;
	}
	
	if (burst_round < 3 && wep.pev.classname == "weapon_m16") {
		g_Scheduler.SetTimeout("delay_compensate", 0.075f, EHandle(plr), EHandle(wep), isSecondaryFire, burst_round+1);
	}
	
	array<LagBullet> lagBullets = get_bullets(plr, wep, isSecondaryFire);
	
	int clip = wep.m_iClip;
	if (wep.pev.classname == "weapon_minigun") {
		clip = plr.m_rgAmmo(wep.m_iPrimaryAmmoType);
	}
	//println("SHOOT BULLETS " + clip + " " + wep.pev.classname + " " + lagBullets.size() + " " + plr.pev.maxspeed);
	
	rewind_monsters(plr, state);
	
	Vector vecSrc = plr.GetGunPosition();
	
	int hits = 0;
	
	CBaseEntity@ target = null;
	for (uint b = 0; b < lagBullets.size(); b++) {
		LagBullet bullet = lagBullets[b];
		TraceResult tr;
		g_Utility.TraceLine( vecSrc, vecSrc + bullet.vecAim*BULLET_RANGE, dont_ignore_monsters, plr.edict(), tr );
		
		bool hit = false;
		CBaseEntity@ phit = g_EntityFuncs.Instance(tr.pHit);
		if (phit !is null) {
			if (phit.IsMonster()) {	
				// move the impact sprite closer to the where the monster currently is
				//tr.vecEndPos = tr.vecEndPos + (currentOrigin - lastState.origin);
			
				@target = @phit;
				hit = true;
				hits++;
			}
			
			g_WeaponFuncs.ClearMultiDamage();
			phit.TraceAttack(plr.pev, bullet.damage, bullet.vecAim, tr, DMG_BULLET | DMG_NEVERGIB);
			g_WeaponFuncs.ApplyMultiDamage(plr.pev, plr.pev);
		}
		
		if (state.debug > 1) {
			int life = 3;
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
	
	undo_rewind_monsters();
	
	last_shoot[plr.entindex()] = g_Engine.time;
}

HookReturnCode WeaponPrimaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep)
{
	compensate(plr, wep, false);
	return HOOK_CONTINUE;
}

HookReturnCode WeaponSecondaryAttack(CBasePlayer@ plr, CBasePlayerWeapon@ wep)
{
	compensate(plr, wep, true);	
	return HOOK_CONTINUE;
}

HookReturnCode EntityCreated(CBaseEntity@ ent)
{
	if (ent.IsMonster() && ent.pev.classname != "cycler") {
		//println("CREATED " + ent.pev.classname);
		g_Scheduler.SetTimeout("refresh_ents", 0.0f);
	}
	return HOOK_CONTINUE;
}

HookReturnCode PlayerPreThink(CBasePlayer@ plr, uint&out test) {		
	// need to poll to know when a player released the secondary fire button for gauss chargeup
	float startCharge = gauss_start_charge[plr.entindex()];
	if (startCharge != -1) {
		CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
		
		if (wep !is null and wep.pev.classname == "weapon_gauss") {	
			if (plr.pev.button & IN_ATTACK2 == 0 || plr.m_rgAmmo(wep.m_iPrimaryAmmoType) == 0) {
				float chargeTime = g_Engine.time - startCharge;
				
				if (chargeTime > 0.5f) { // minimum charge time passed?
					// player must have just shot
					compensate(plr, wep, true, 1, true);
					gauss_start_charge[plr.entindex()] = -1;
				}
			}
			
		} else {
			gauss_start_charge[plr.entindex()] = -1;
		}
	}
	
	return HOOK_CONTINUE;
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool isConsoleCommand=false)
{
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
					g_PlayerFuncs.SayText(plr, "Lag compensation hitmarker " + (state.hitmarker ? "enabled" : "disabled") + "\n");
				}
				else if (arg == "debug") {
					state.debug = state.debug == 0 ? 2 : 0;
					g_PlayerFuncs.SayText(plr, "Lag compensation debug mode " + (state.debug > 0 ? "enabled" : "disabled") + "\n");
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
					state.enabled = false;
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
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    X = milliseconds, a number between 0 and ' + maxComp + '.\n');
				
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
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n-----------------------------------------------------------------------------------\n');
			
				if (!isConsoleCommand) {
					g_PlayerFuncs.SayText(plr, 'Lag compensation is ' + (state.enabled ? 'enabled' : 'disabled') + mode + '\n');
					g_PlayerFuncs.SayText(plr, 'Say ".lagc [on/off/toggle]" to enable or disable lag compensation.\n');
					g_PlayerFuncs.SayText(plr, 'Say ".lagc x" to toggle hit confirmations.\n');
					g_PlayerFuncs.SayText(plr, 'Type ".lagc" in console for more commands/info\n');
				}
			}
			return true;
		}
	}
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams )
{
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();	
	if (doCommand(plr, args, false))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	return HOOK_CONTINUE;
}

CClientCommand _lagc("lagc", "Lag compensation commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}