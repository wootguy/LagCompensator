// This code exists because there's no way to prevent a weapon from shooting, or to force it to shoot.
// So, attack functions need to be reimplemented for every supported weapon, and the default weapon
// damage needs to disabled via cvars or the custom weapon damage keyvalue.

// This is full of hacks and reverse-engineered code which will break if weapons are ever rebalanced.

void init_weapon_info() {
	g_weapon_info["weapon_9mmhandgun"] = WeaponInfo(
		BULLET_PLAYER_9MM,
		DMG_BULLET | DMG_NEVERGIB,
		Vector(0.01, 0.01, 0.01),
		"sk_plr_9mm_bullet"
	);
	g_weapon_info["weapon_357"] = WeaponInfo(
		BULLET_PLAYER_357,
		DMG_BULLET | DMG_NEVERGIB,
		VECTOR_CONE_3DEGREES,
		"sk_plr_357_bullet"
	);
	g_weapon_info["weapon_eagle"] = WeaponInfo(
		BULLET_PLAYER_357,
		DMG_BULLET | DMG_NEVERGIB,
		VECTOR_CONE_4DEGREES,
		"sk_plr_357_bullet"
	);
	g_weapon_info["weapon_uzi"]	= WeaponInfo(
		BULLET_UZI,
		DMG_BULLET | DMG_NEVERGIB,
		VECTOR_CONE_8DEGREES,
		"sk_plr_uzi"
	);
	g_weapon_info["weapon_9mmAR"] = WeaponInfo(
		BULLET_PLAYER_MP5,
		DMG_BULLET | DMG_NEVERGIB,
		VECTOR_CONE_6DEGREES,
		"sk_plr_9mmAR_bullet"
	);
	g_weapon_info["weapon_shotgun"] = WeaponInfo(
		BULLET_PLAYER_BUCKSHOT,
		DMG_BULLET | DMG_NEVERGIB | DMG_LAUNCH,
		Vector(0.08716, 0.04362, 0.00),
		"sk_plr_buckshot"
	);
	g_weapon_info["weapon_gauss"] = WeaponInfo(
		BULLET_GAUSS,
	    DMG_BULLET | DMG_NEVERGIB,
		Vector(0,0,0),
		"sk_plr_gauss"
	);
	g_weapon_info["weapon_egon"] = WeaponInfo(
		BULLET_EGON,
	    DMG_ENERGYBEAM | DMG_ALWAYSGIB,
		Vector(0,0,0),
		"sk_plr_egon_wide"
	);
	g_weapon_info["weapon_sniperrifle"] = WeaponInfo(
		BULLET_PLAYER_SNIPER,
		DMG_BULLET | DMG_NEVERGIB | DMG_LAUNCH,
		VECTOR_CONE_6DEGREES,
		"sk_plr_762_bullet"
	);
	g_weapon_info["weapon_m249"] = WeaponInfo(
		BULLET_PLAYER_SAW,
		DMG_BULLET | DMG_NEVERGIB | DMG_LAUNCH,
		VECTOR_CONE_4DEGREES,
		"sk_556_bullet"
	);
	g_weapon_info["weapon_m16"] = WeaponInfo(
		BULLET_PLAYER_SAW,
		DMG_BULLET | DMG_NEVERGIB | DMG_LAUNCH,
		VECTOR_CONE_4DEGREES,
		"sk_556_bullet"
	);
	g_weapon_info["weapon_minigun"] = WeaponInfo(
		BULLET_PLAYER_SAW,
		DMG_BULLET | DMG_NEVERGIB | DMG_LAUNCH,
		VECTOR_CONE_4DEGREES,
		"sk_556_bullet"
	);
}

void refresh_player_states() {
	if (!g_enabled) {
		return;
	}
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr is null or !plr.IsConnected())
			continue;
		
		CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(plr.m_hActiveItem.GetEntity());
		if (wep is null)
			continue;
		
		WeaponInfo@ wepInfo = cast<WeaponInfo@>( g_weapon_info[wep.pev.classname] );
		if (wepInfo is null)
			continue; // unsupported weapon
		
		if (wep.pev.classname == "weapon_shotgun") {
			last_shotgun_clips[i] = wep.m_iClip;
		}
		if (wep.pev.classname == "weapon_minigun") {
			last_minigun_clips[i] = plr.m_rgAmmo(wep.m_iPrimaryAmmoType);
		}
		
		PlayerState@ state = getPlayerState(plr);
		int weaponState = WEP_NOT_INITIALIZED;
		
		KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
		CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();
		if (pCustom.HasKeyvalue(WEAPON_STATE_KEY)) {
			weaponState = pCustom.GetKeyvalue( WEAPON_STATE_KEY ).GetInteger();
		}
		
		// save current custom damage, if one was set by the mapper (or a cheat plugin)
		// because the plugin is about to overwrite that key
		if (weaponState == WEP_NOT_INITIALIZED && wep.m_flCustomDmg >= 1.0f) {
			pCustom.SetKeyvalue(CUSTOM_DAMAGE_KEY, wep.m_flCustomDmg);
		}
		
		if (state.enabled && weaponState != WEP_COMPENSATE_ON) {
			// prevent sven code from doing damage with this weapon (0 = use cvar, and cvars are set to do 0 damage)
			// One exception: 556 guns can't use the cvar because that would prevent monsters from doing damage (hwgrunt)
			// "1" is the minimum damage that can be set for m_flCustomDmg. So, these guns will be more powerful when double-hitting.
			wep.m_flCustomDmg = wepInfo.bulletType == BULLET_PLAYER_SAW ? 1.0f : 0.0f;
			
			pCustom.SetKeyvalue(WEAPON_STATE_KEY, WEP_COMPENSATE_ON);
			
		} else if (!state.enabled && weaponState != WEP_COMPENSATE_OFF) {				
			if (pCustom.HasKeyvalue(CUSTOM_DAMAGE_KEY)) {
				// restore the mapper's custom damage
				CustomKeyvalue dmgKey( pCustom.GetKeyvalue( CUSTOM_DAMAGE_KEY ) );
				wep.m_flCustomDmg = dmgKey.GetFloat();
				//println("Restored custom damage " + wep.pev.classname);
			} else {
				// restore cvar damage
				//println("Restored cvar damage " + wep.pev.classname);
				wep.m_flCustomDmg = g_bullet_damage[wepInfo.bulletType];
			}
			
			pCustom.SetKeyvalue(WEAPON_STATE_KEY, WEP_COMPENSATE_OFF);
		}
	}
}

void save_cvar_values() {
	g_bullet_damage[BULLET_UZI] = g_EngineFuncs.CVarGetFloat("sk_plr_uzi");
	g_bullet_damage[BULLET_PLAYER_9MM] = g_EngineFuncs.CVarGetFloat("sk_plr_9mm_bullet");
	g_bullet_damage[BULLET_PLAYER_MP5] = g_EngineFuncs.CVarGetFloat("sk_plr_9mmAR_bullet");
	g_bullet_damage[BULLET_PLAYER_SAW] = g_EngineFuncs.CVarGetFloat("sk_556_bullet");
	g_bullet_damage[BULLET_PLAYER_SNIPER] = g_EngineFuncs.CVarGetFloat("sk_plr_762_bullet");
	g_bullet_damage[BULLET_PLAYER_357] = g_EngineFuncs.CVarGetFloat("sk_plr_357_bullet");
	g_bullet_damage[BULLET_PLAYER_BUCKSHOT] = g_EngineFuncs.CVarGetFloat("sk_plr_buckshot");
	g_bullet_damage[BULLET_GAUSS] = g_EngineFuncs.CVarGetFloat("sk_plr_gauss");
	g_bullet_damage[BULLET_GAUSS2] = g_EngineFuncs.CVarGetFloat("sk_plr_secondarygauss");
	g_bullet_damage[BULLET_EGON] = g_EngineFuncs.CVarGetFloat("sk_plr_egon_wide");
}

void refresh_cvars() {
	if (!g_enabled or g_Engine.time < 10) {
		return;
	}
	
	// update bullet damages if cvars were changed mid-map
	array<float> changed_damages;
	changed_damages.resize(g_bullet_damage.size());
	
	changed_damages[BULLET_UZI] = g_EngineFuncs.CVarGetFloat("sk_plr_uzi"); 					// 0
	changed_damages[BULLET_PLAYER_9MM] = g_EngineFuncs.CVarGetFloat("sk_plr_9mm_bullet"); 		// 1
	changed_damages[BULLET_PLAYER_MP5] = g_EngineFuncs.CVarGetFloat("sk_plr_9mmAR_bullet");  	// 2
	changed_damages[BULLET_PLAYER_SAW] = g_EngineFuncs.CVarGetFloat("sk_556_bullet");			// 3
	changed_damages[BULLET_PLAYER_SNIPER] = g_EngineFuncs.CVarGetFloat("sk_plr_762_bullet");	// 4
	changed_damages[BULLET_PLAYER_357] = g_EngineFuncs.CVarGetFloat("sk_plr_357_bullet");		// 5
	changed_damages[BULLET_PLAYER_BUCKSHOT] = g_EngineFuncs.CVarGetFloat("sk_plr_buckshot");	// 7
	changed_damages[BULLET_GAUSS] = g_EngineFuncs.CVarGetFloat("sk_plr_gauss");					// 8
	changed_damages[BULLET_GAUSS2] = g_EngineFuncs.CVarGetFloat("sk_plr_secondarygauss");		// 9
	changed_damages[BULLET_EGON] = g_EngineFuncs.CVarGetFloat("sk_plr_egon_wide");				// 10
	
	bool anyChanges = false;
	for (int i = 0; i < 10; i++) {
		if (changed_damages[i] != 0 && changed_damages[i] != g_bullet_damage[i]) {
			g_bullet_damage[i] = changed_damages[i];
			anyChanges = true;
		}
	}
	
	if (anyChanges)
		disable_default_damages();
	
	// these can also change mid-map
	shotgun_doubleshot_mode = g_EngineFuncs.CVarGetFloat("weaponmode_shotgun") == 1;
	pistol_silencer_mode = g_EngineFuncs.CVarGetFloat("weaponmode_9mmhandgun") == 1;
}

void reload_skill_files() {
	string map_skill_file = "" + g_Engine.mapname + "_skl.cfg";
	g_EngineFuncs.ServerCommand("exec skill.cfg; exec " + map_skill_file + ";\n");
	g_EngineFuncs.ServerExecute();
}

void disable_default_damages() {
	// all damage will be done by this plugin or with the custom weapon damage keyvalue
	// otherwise enemies can be hit twice by the same bullet (sven bullet + plugin bullet)
	g_EngineFuncs.CVarSetFloat("sk_plr_uzi", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_9mm_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_9mmAR_bullet", 0);
	//g_EngineFuncs.CVarSetFloat("sk_556_bullet", 0); // can't touch this one. Monsters use it, too.
	g_EngineFuncs.CVarSetFloat("sk_plr_762_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_357_bullet", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_buckshot", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_gauss", 0);
	g_EngineFuncs.CVarSetFloat("sk_plr_secondarygauss", 0);
	println("Disabled default bullet damages");
}

void enable_default_damages() {
	// all damage will be done by this plugin or with the custom weapon damage keyvalue
	// otherwise enemies can be hit twice by the same bullet (sven bullet + plugin bullet)
	g_EngineFuncs.CVarSetFloat("sk_plr_uzi", g_bullet_damage[BULLET_UZI]);
	g_EngineFuncs.CVarSetFloat("sk_plr_9mm_bullet", g_bullet_damage[BULLET_PLAYER_9MM]);
	g_EngineFuncs.CVarSetFloat("sk_plr_9mmAR_bullet", g_bullet_damage[BULLET_PLAYER_MP5]);
	//g_EngineFuncs.CVarSetFloat("sk_556_bullet", g_bullet_damage[BULLET_PLAYER_SAW]); // can't touch this one. Monsters use it, too.
	g_EngineFuncs.CVarSetFloat("sk_plr_762_bullet", g_bullet_damage[BULLET_PLAYER_SNIPER]);
	g_EngineFuncs.CVarSetFloat("sk_plr_357_bullet", g_bullet_damage[BULLET_PLAYER_357]);
	g_EngineFuncs.CVarSetFloat("sk_plr_buckshot", g_bullet_damage[BULLET_PLAYER_BUCKSHOT]);
	g_EngineFuncs.CVarSetFloat("sk_plr_gauss", g_bullet_damage[BULLET_GAUSS]);
	g_EngineFuncs.CVarSetFloat("sk_plr_secondarygauss", g_bullet_damage[BULLET_GAUSS2]);
	println("Re-enabled default bullet damages");
}

void reset_weapon_damages() {
	CBaseEntity@ ent;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "weapon_*");
		if (ent !is null)
		{
			CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(ent);
			
			KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
			CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();
			
			if (pCustom.HasKeyvalue(CUSTOM_DAMAGE_KEY)) {
				wep.m_flCustomDmg = pCustom.GetKeyvalue( CUSTOM_DAMAGE_KEY ).GetFloat();
			}
			
			pCustom.SetKeyvalue(WEAPON_STATE_KEY, WEP_NOT_INITIALIZED);
		}
	} while(ent !is null);
}

void check_classic_mode() {
	// if the mp5 has secondary ammo, then we're probably in classic mode.
	// plugins can't access the classic mode API for some reason.
	// This has to be called after MapActivate or else the mp5 sounds like a pistol and reloads after every shot (wtf??).
	CBasePlayerWeapon@ mp5 = cast<CBasePlayerWeapon@>(g_EntityFuncs.Create("weapon_9mmAR", Vector(0,0,0), Vector(0,0,0), false));
	is_classic_mode = mp5.iMaxAmmo2() != -1;
	g_EntityFuncs.Remove(mp5);
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
	else if (wep.pev.classname == "weapon_egon") {
		if (wep.m_bFireOnEmpty || plr.pev.waterlevel == 3 || isSecondaryFire) {
			return false;
		}
		if (g_Engine.time - egon_last_dmg[plr.entindex()] < 0.1f) {
			return false;
		}
		egon_last_dmg[plr.entindex()] = g_Engine.time;
	}
	else if (isSecondaryFire || wep.m_bFireOnEmpty || plr.pev.waterlevel == 3) {
		return false;
	}
	
	return true;
}

CBaseEntity@ gauss_effects(CBasePlayer@ plr, CBasePlayerWeapon@ wep, LagBullet bullet, bool isSecondaryFire) {
	if (isSecondaryFire)
		plr.pev.velocity = plr.pev.velocity - bullet.vecAim * bullet.damage * 5;
	
	// https://github.com/ValveSoftware/halflife/blob/5d761709a31ce1e71488f2668321de05f791b405/dlls/gauss.cpp
	
	CBaseEntity@ hitMonster = null;
	
	float flDamage = bullet.damage;
	int maxHits = 10;
	Vector vecDir = bullet.vecAim;
	Vector vecSrc = plr.GetGunPosition();
	Vector vecDest = vecSrc + vecDir * 8192;
	edict_t@ pentIgnore = null;
	TraceResult tr, beam_tr;
	float flMaxFrac = 1.0;
	int	nTotal = 0;
	int fHasPunched = 0;
	int fFirstBeam = 1;
	int	nMaxHits = 10;
	
	while (flDamage > 10 && nMaxHits > 0)
	{
		nMaxHits--;

		// ALERT( at_console, "." );
		g_Utility.TraceLine( vecSrc, vecDest, dont_ignore_monsters, plr.edict(), tr );

		if (tr.fAllSolid != 0)
			break;

		CBaseEntity@ pEntity = g_EntityFuncs.Instance(tr.pHit);

		if (pEntity is null)
			break;

		if ( fFirstBeam != 0 )
		{
			fFirstBeam = 0;
			nTotal += 26;
		}
		
		if (pEntity.pev.takedamage != 0)
		{
			g_WeaponFuncs.ClearMultiDamage();
			pEntity.TraceAttack( plr.pev, flDamage, vecDir, tr, DMG_BULLET );
			g_WeaponFuncs.ApplyMultiDamage(plr.pev, plr.pev);
			
			if (pEntity.IsMonster()) {
				@hitMonster = @pEntity;
			}
		}

		if ( pEntity.ReflectGauss() )
		{
			float n;

			@pentIgnore = null;

			n = -DotProduct(tr.vecPlaneNormal, vecDir);

			if (n < 0.5) // 60 degrees
			{
				// ALERT( at_console, "reflect %f\n", n );
				// reflect
				Vector r;
			
				r = 2.0 * tr.vecPlaneNormal * n + vecDir;
				flMaxFrac = flMaxFrac - tr.flFraction;
				vecDir = r;
				vecSrc = tr.vecEndPos + vecDir * 8;
				vecDest = vecSrc + vecDir * 8192;

				// explode a bit
				float radiusDmg = flDamage * n;
				g_WeaponFuncs.RadiusDamage( tr.vecEndPos, wep.pev, plr.pev, radiusDmg, radiusDmg*2.5, CLASS_NONE, DMG_BLAST );

				nTotal += 34;
				
				// lose energy
				if (n == 0) n = 0.1;
				flDamage = flDamage * (1 - n);
			}
			else
			{
				nTotal += 13;

				// limit it to one hole punch
				if (fHasPunched != 0)
					break;
				fHasPunched = 1;

				// try punching through wall if secondary attack (primary is incapable of breaking through)
				if ( isSecondaryFire )
				{
					g_Utility.TraceLine( tr.vecEndPos + vecDir * 8, vecDest, dont_ignore_monsters, pentIgnore, beam_tr);
					if (beam_tr.fAllSolid == 0)
					{
						// trace backwards to find exit point
						g_Utility.TraceLine( beam_tr.vecEndPos, tr.vecEndPos, dont_ignore_monsters, pentIgnore, beam_tr);

						float n2 = (beam_tr.vecEndPos - tr.vecEndPos).Length();

						if (n2 < flDamage)
						{
							if (n2 == 0) n2 = 1;
							flDamage -= n2;

							// ALERT( at_console, "punch %f\n", n );
							nTotal += 21;

							// exit blast damage
							float damage_radius = flDamage * 1.75;  // Old code == 2.5

							g_WeaponFuncs.RadiusDamage( beam_tr.vecEndPos + vecDir * 8, wep.pev, plr.pev, flDamage, damage_radius, CLASS_NONE, DMG_BLAST );

							nTotal += 53;

							vecSrc = beam_tr.vecEndPos + vecDir;
						}
					}
					else
					{
						 //ALERT( at_console, "blocked %f\n", n );
						flDamage = 0;
					}
				}
				else
				{
					//ALERT( at_console, "blocked solid\n" );
					
					flDamage = 0;
				}

			}
		}
		else
		{
			vecSrc = tr.vecEndPos + vecDir;
			@pentIgnore = @pEntity.edict();
		}
	}
	
	return hitMonster;
}

void update_gauss_charge_state(CBasePlayer@ plr) {
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
}

array<LagBullet> get_bullets(CBasePlayer@ plr, CBasePlayerWeapon@ wep, bool isSecondaryFire, WeaponInfo@ wepInfo, bool debug=false) {
	string cname = wep.pev.classname;
	
	int bulletCount = 1;
	
	// 556 is nerfed by 0.5 damage points because bullets hit twice when an npc's rewind position matches its current position.
	// The gun will do 1 point of extra damage when that happens. Subtracting 0.5 points means the gun will
	// be slightly stronger when shooting stationary targets, and slightly weaker for moving targets.
	// This had to be done because custom damage any weapon has to be at least 1, and the skill setting can't be 0
	// because it's shared with monsters (hwgrunt would do no damage if set to 0).
	const float nerf_556 = 0.5f;
	
	float damage = g_bullet_damage[wepInfo.bulletType];
	Vector spread = wepInfo.spread;
	
	if (cname == "weapon_9mmhandgun") {
		if (isSecondaryFire || (pistol_silencer_mode && !isSecondaryFire)) {
			spread = Vector(0.1, 0.1, 0.1);
		}
	}
	else if (cname == "weapon_uzi") {
		if (wep.m_fIsAkimbo && wep.m_iClip > 0 && wep.m_iClip2 > 0) {
			bulletCount++;
		}
	}
	else if (cname == "weapon_9mmAR") {
		damage = g_bullet_damage[BULLET_PLAYER_MP5];
		if (wep.m_fInZoom) {
			spread = VECTOR_CONE_4DEGREES;
		}
	}
	else if (cname == "weapon_shotgun") {
		bulletCount = 8;
		
		if (isSecondaryFire) {
			spread = Vector( 0.17365, 0.04362, 0.00 );
			
			if (shotgun_doubleshot_mode || is_classic_mode) {
				bulletCount = 12;
			}
		}
	}
	else if (cname == "weapon_gauss") {
		if (isSecondaryFire) {
			float charge = (g_Engine.time - gauss_start_charge[plr.entindex()]) / 4.0f;
			damage = g_bullet_damage[BULLET_GAUSS2] * Math.min(1.0f, charge);
		}
	}
	else if (cname == "weapon_sniperrifle") {
		if (wep.m_fInZoom) {
			spread = Vector(0,0,0);
		}
	}
	else if (wepInfo.bulletType == BULLET_PLAYER_SAW) {
		damage -= nerf_556;
	}
	
	Math.MakeVectors(plr.pev.v_angle + getEstimatedRecoil(plr, wep, isSecondaryFire));
	
	KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
	CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();
	if (pCustom.HasKeyvalue(CUSTOM_DAMAGE_KEY)) {
		damage = pCustom.GetKeyvalue( CUSTOM_DAMAGE_KEY ).GetFloat();
	}
	
	if (debug) {
		debug_bullet_damage(plr, wep, damage, true);
	}
	
	array<LagBullet> bullets;
	for (int i = 0; i < bulletCount; i++) {
		bullets.insertLast(LagBullet(spread, damage));
	}
	
	return bullets;
}

void debug_bullet_damage(CBasePlayer@ plr, CBasePlayerWeapon@ wep, float plugin_dmg, bool is_comp) {
	WeaponInfo@ wepInfo = cast<WeaponInfo@>( g_weapon_info[wep.pev.classname] );
	if (wepInfo is null) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Unsupported weapon\n");
		return;
	}

	KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( wep.edict() );
	CustomKeyvalues@ pCustom = wep.GetCustomKeyvalues();

	float custom_damage = wep.m_flCustomDmg;
	int state = WEP_NOT_INITIALIZED;
	if (pCustom.HasKeyvalue(WEAPON_STATE_KEY)) {
		state = pCustom.GetKeyvalue(WEAPON_STATE_KEY).GetInteger();
	}

	string dmg = "m_flCustomDmg = " + custom_damage;
	if (is_comp) {
		dmg += ", plugin = " + plugin_dmg;
	}
	
	if (pCustom.HasKeyvalue(CUSTOM_DAMAGE_KEY)) {
		float key_damage = pCustom.GetKeyvalue( CUSTOM_DAMAGE_KEY ).GetFloat();
		dmg += ", " + CUSTOM_DAMAGE_KEY + " = " + key_damage;
	}
	if (custom_damage < 1.0f) {
		float skillDmg = g_EngineFuncs.CVarGetFloat(wepInfo.skillSetting);
	
		dmg += ", " + wepInfo.skillSetting + " = " + skillDmg;
	}
	if (state == WEP_NOT_INITIALIZED) {
		dmg += " (NOT INIT)";
	} else if (state == WEP_COMPENSATE_ON) {
		dmg += " (COMP ON)";
	} else if (state == WEP_COMPENSATE_OFF) {
		dmg += " (COMP OFF)";
	}
	
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "" + wep.pev.classname + ": "  + dmg + "\n");
}
