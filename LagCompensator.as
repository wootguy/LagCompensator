#include "util"

// TODO:
// - use BulletAccuracy method somehow
// - disable damage+effects for non-rewind hits
// - check underwater firing
// - modern weps
// - secondary gauss
// - egon maybe

const float MAX_LAG_COMPENSATION_TIME = 2; // 2 seconds
bool debug_mode = false;
string hitmarker_spr = "sprites/misc/mlg.spr";
string hitmarker_snd = "misc/hitmarker.mp3";

void PluginInit() 
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack );
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponSecondaryAttack, @WeaponSecondaryAttack );
	g_Hooks.RegisterHook( Hooks::Game::EntityCreated, @EntityCreated );
	
	refresh_ents();
	
	g_Scheduler.SetInterval("update_ent_history", 0.0f, -1);
	g_Scheduler.SetInterval("refresh_player_shotgun_clip_counts", 1.0f, -1);
	
	init();
}

void init() {
	last_shotgun_clips.resize(33);
	last_shoot.resize(33);
	for (int i = 0; i < 33; i++) {
		last_shotgun_clips[i] = 8;
		last_shoot[i] = 0;
	}
}

void MapInit() {
	init();
	
	g_Game.PrecacheModel(hitmarker_spr);
	g_SoundSystem.PrecacheSound(hitmarker_snd);
	g_Game.PrecacheGeneric("sound/" + hitmarker_snd);
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

array<LagEnt> laggyEnts;
array<float> g_bullet_damage;
array<int> last_shotgun_clips; // needed to know if a player shot or not. None of the weapon props are reliable.
array<float> last_shoot; // needed to calculate recoil. punchangle is not updated when shooting weapons.

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
	
	refresh_bullet_damages();
}

const int BULLET_UZI = 0;
const int BULLET_GAUSS = 8;
const int BULLET_GAUSS2 = 9;

void refresh_bullet_damages() {
	g_bullet_damage.resize(0);
	g_bullet_damage.resize(10);
	
	g_bullet_damage[BULLET_UZI] = g_EngineFuncs.CVarGetFloat("sk_plr_uzi");
	g_bullet_damage[BULLET_PLAYER_9MM] = g_EngineFuncs.CVarGetFloat("sk_plr_9mm_bullet");
	g_bullet_damage[BULLET_PLAYER_MP5] = g_EngineFuncs.CVarGetFloat("sk_plr_9mmAR_bullet");
	g_bullet_damage[BULLET_PLAYER_SAW] = g_EngineFuncs.CVarGetFloat("sk_556_bullet");
	g_bullet_damage[BULLET_PLAYER_SNIPER] = g_EngineFuncs.CVarGetFloat("sk_plr_762_bullet");
	g_bullet_damage[BULLET_PLAYER_357] = g_EngineFuncs.CVarGetFloat("sk_plr_357_bullet");
	g_bullet_damage[BULLET_PLAYER_EAGLE] = g_EngineFuncs.CVarGetFloat("sk_plr_357_bullet");
	g_bullet_damage[BULLET_PLAYER_BUCKSHOT] = g_EngineFuncs.CVarGetFloat("sk_plr_buckshot");
	g_bullet_damage[BULLET_GAUSS] = g_EngineFuncs.CVarGetFloat("sk_plr_gauss");
	g_bullet_damage[BULLET_GAUSS2] = g_EngineFuncs.CVarGetFloat("sk_plr_secondarygauss");
}

// sucks to have to do more polling but I can't think of any better way
void refresh_player_shotgun_clip_counts() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
		if (p is null or !p.IsConnected())
			continue;
		
		CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(p.m_hActiveItem.GetEntity());
		
		if (wep !is null and wep.pev.classname == "weapon_shotgun") {
			last_shotgun_clips[i] = wep.m_iClip;
		}
	}
}

void update_ent_history() {
	for (uint i = 0; i < laggyEnts.size(); i++) {
		laggyEnts[i].update_history();
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
	
	g_Scheduler.SetTimeout("delay_kill", 1.0f, EHandle(oldEnt));
}

array<LagBullet> get_bullets(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire) {
	string cname = wep.pev.classname;
	
	float damage = 0;
	Vector spread = Vector(0,0,0);
	int bulletCount = 1;
	
	if (cname == "weapon_9mmhandgun") {
		damage = g_bullet_damage[BULLET_PLAYER_9MM];
		spread = isSecondaryFire ? Vector(0.1, 0.1, 0.1) : Vector(0.01, 0.01, 0.01);
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
		spread = VECTOR_CONE_6DEGREES;
	}
	else if (cname == "weapon_shotgun") {
		damage = g_bullet_damage[BULLET_PLAYER_BUCKSHOT];
		spread = isSecondaryFire ? Vector( 0.17365, 0.04362, 0.00 ) : Vector( 0.08716, 0.04362, 0.00  );
		bulletCount = isSecondaryFire ? 12 : 8;
	}
	else if (cname == "weapon_gauss") {
		damage = g_bullet_damage[BULLET_GAUSS];
		spread = VECTOR_CONE_1DEGREES;
	}
	else if (cname == "weapon_sniperrifle") {
		damage = g_bullet_damage[BULLET_PLAYER_SNIPER];
		spread = VECTOR_CONE_1DEGREES;
	}
	else if (cname == "weapon_m249") {
		damage = g_bullet_damage[BULLET_PLAYER_SAW];
		spread = VECTOR_CONE_1DEGREES;
	} else {
		println("Unsupported gun: " + cname);
		bulletCount = 0;
	}
	
	Math.MakeVectors(plr.pev.v_angle + plr.pev.punchangle + getEstimatedRecoil(plr, wep, isSecondaryFire));
	
	array<LagBullet> bullets;
	for (int i = 0; i < bulletCount; i++) {
		bullets.insertLast(LagBullet(spread, damage));
	}
	
	return bullets;
}

Vector getEstimatedRecoil(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire) {
	float lastShootDelta = g_Engine.time - last_shoot[plr.entindex()];
	Vector recoil;

	if (wep.pev.classname == "weapon_357" || wep.pev.classname == "weapon_eagle") {
		if (lastShootDelta < 1) {
			recoil.x = -(1-lastShootDelta)*8;
		}
	}
	else if (wep.pev.classname == "weapon_eagle") {
		if (lastShootDelta < 1) {
			recoil.x = -(1-lastShootDelta)*8;
		}
	}

	//println("RECOIL " + lastShootDelta + " " + recoil.x);

	return recoil;
}

// primary fire hooks are called when reloading/empty/randomly
// this makes sure a bullet was actually shot
bool didPlayerShoot(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire) {
	if (wep.pev.classname == "weapon_9mmhandgun") {
		if (wep.m_bFireOnEmpty || wep.ShouldReload()) { // fireOnEmpty doesn't work for secondary fire
			return false;
		}
	}
	else if (wep.pev.classname == "weapon_shotgun") {
		bool shooting = true;
		
		if (isSecondaryFire) {
			shooting = last_shotgun_clips[plr.entindex()] >= 2; // TODO: this only works for double-shot mode
		} else {
			shooting = last_shotgun_clips[plr.entindex()] > 0 || !wep.m_bFireOnEmpty;
		}
		
		last_shotgun_clips[plr.entindex()] = wep.m_iClip;
		
		if (!shooting) {
			return false;
		}
	}
	else if (wep.pev.classname == "weapon_uzi") {
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
	else if (isSecondaryFire || wep.m_bFireOnEmpty) {
		return false;
	}
	
	return true;
}

void rewind_monsters(CBasePlayer@ plr) {
	int iping, packetLoss;
	g_EngineFuncs.GetPlayerStats(plr.edict(), iping, packetLoss);
	//iping = 250;
	
	float ping = float(iping) / 1000.0f;
	float shootTime = g_Engine.time - ping;
	

	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		if (mon is null) {
			continue;
		}
		
		// get state closest to the time the player shot
		int bestHistoryIdx = 0;
		
		for (uint k = 0; k < laggyEnts[i].history.size(); k++) {
			if (laggyEnts[i].history[k].time >= shootTime || k == laggyEnts[i].history.size()-1) {
				bestHistoryIdx = k;
				println("Best delta: " + int((laggyEnts[i].history[k].time - shootTime)*1000) + " for ping " + iping);
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
		
		if (debug_mode)
			debug_rewind(mon, newState);
	}
}

void undo_rewind_monsters() {
	for (uint i = 0; i < laggyEnts.size(); i++) {
		CBaseMonster@ mon = cast<CBaseMonster@>(laggyEnts[i].h_ent.GetEntity());
		if (mon is null or !laggyEnts[i].isRewound) {
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

void compensate(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire)
{	
	if (!didPlayerShoot(plr, wep, isSecondaryFire)) {
		return;
	}
	
	array<LagBullet> lagBullets = get_bullets(plr, wep, isSecondaryFire);
	
	println("SHOOT BULLETS " + wep.m_iClip + " " + wep.pev.classname + " " + lagBullets.size());
	
	rewind_monsters(plr);
	
	Vector vecSrc = plr.GetGunPosition();
	
	int hits = 0;
	
	CBaseEntity@ target = null;
	for (uint b = 0; b < lagBullets.size(); b++) {
		LagBullet bullet = lagBullets[b];
		TraceResult tr;
		g_Utility.TraceLine( vecSrc, vecSrc + bullet.vecAim*8192, dont_ignore_monsters, plr.edict(), tr );
		
		bool hit = false;
		CBaseEntity@ phit = g_EntityFuncs.Instance(tr.pHit);
		if (phit !is null && phit.IsMonster()) {
			CBaseMonster@ mon = cast<CBaseMonster@>(phit);
			// move the impact sprite closer to the where the monster currently is
			//tr.vecEndPos = tr.vecEndPos + (currentOrigin - lastState.origin);
			
			g_WeaponFuncs.ClearMultiDamage();
			mon.TraceAttack(plr.pev, bullet.damage, bullet.vecAim, tr, DMG_BULLET);
			g_WeaponFuncs.ApplyMultiDamage(plr.pev, plr.pev);
			@target = @phit;
			
			hit = true;
			hits++;
		}
		
		if (debug_mode) {
			int life = 3;
			te_beampoints(vecSrc, tr.vecEndPos, "sprites/laserbeam.spr", 0, 100, life, 2, 0, hit ? RED : GREEN);
		}
	}
	
	if (hits > 0) {
		HUDSpriteParams params;
		params.flags = HUD_SPR_MASKED | HUD_ELEM_SCR_CENTER_X | HUD_ELEM_SCR_CENTER_Y;
		params.spritename = hitmarker_spr.SubString("sprites/".Length());
		params.holdTime = 0.5f;
		params.x = 0;
		params.y = 0;
		params.color1 = RGBA( 255, 255, 255, 255 );
		params.channel = 15;
		g_PlayerFuncs.HudCustomSprite(plr, params);
		
		g_SoundSystem.PlaySound(target.edict(), CHAN_AUTO, hitmarker_snd, 1.0f, 0.0f, 0, 100, plr.entindex());
	}
	
	undo_rewind_monsters();
	
	last_shoot[plr.entindex()] = g_Engine.time;
	
	//println("Replayed " + replay_count + " monsters");
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