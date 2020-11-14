
// This plugin needs to know when a weapon will shoot so that monsters are unlagged only as needed.
// Custom weapons can do whatever they want when it comes to preventing a weapon from shooting, so
// special condition checks are needed for them to work with this plugin.

// To test, type ".lagc perf" in console and check that the "CPS" value matches the fire rate of the weapon.
// Also turn on hitmarkers with ".lagc x" to see hit confirmations (if you see blood without the marker, 
// then the shot wasn't compensated).

// The PlayerPostThink Hook has a debug message commented out that will tell you exactly when a bullet was compensated.
// Sometimes things like holding both mouse buttons or reloading will trigger compensation when it shouldn't.

bool will_custom_weapon_fire_this_frame(CBasePlayer@ plr, CBasePlayerWeapon@ wep) {
	int buttons = plr.m_afButtonPressed | plr.m_afButtonLast | plr.m_afButtonReleased;
	bool primaryFirePressed = buttons & IN_ATTACK != 0;
	bool secondaryFirePressed = buttons & IN_ATTACK2 != 0;
	bool inWater = plr.pev.waterlevel == 3;
	bool hasPrimaryAmmo = wep.m_iClip > 0 || (wep.m_iClip == -1 && wep.m_iPrimaryAmmoType != -1 && plr.m_rgAmmo( wep.m_iPrimaryAmmoType ) > 0);
	bool hasSecondaryAmmo = wep.m_iClip2 > 0 || (wep.m_iClip2 == -1 && wep.m_iSecondaryAmmoType != -1 && plr.m_rgAmmo( wep.m_iSecondaryAmmoType ) > 0);
	string weaponName = wep.pev.classname;
	
	// primary/secondary fire hooks going to be called this frame?
	bool primaryAttacking = primaryFirePressed && wep.m_flNextPrimaryAttack < g_Engine.time;
	bool secondaryAttacking = secondaryFirePressed && wep.m_flNextSecondaryAttack < g_Engine.time;
	
	// map-specific weapons
	if (g_Engine.mapname == "pizza_ya_san1" || g_Engine.mapname == "pizza_ya_san2") {			
		if (weaponName == "weapon_as_shotgun") {
			return (primaryAttacking || secondaryAttacking) && !inWater && hasPrimaryAmmo;
		}
		else if (weaponName == "weapon_as_jetpack") {
			return primaryAttacking && !inWater && hasPrimaryAmmo;
		}
	}

	// plugin weapons
	if (weaponName == "weapon_hl357") {
		return hasPrimaryAmmo && wep.m_flNextPrimaryAttack < g_Engine.time && !wep.m_fInReload && primaryFirePressed && !inWater;
	}
	
	
	// By default, don't compensate custom weapons every frame.
	// If you set this to true, the server will have insane lag spikes.
	return false;
}