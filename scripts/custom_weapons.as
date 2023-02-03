
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
	bool inWater = plr.pev.waterlevel == WATERLEVEL_HEAD;
	bool hasPrimaryAmmo = wep.m_iClip > 0 || (wep.m_iClip == -1 && wep.m_iPrimaryAmmoType != -1 && plr.m_rgAmmo( wep.m_iPrimaryAmmoType ) > 0);
	bool hasSecondaryAmmo = wep.m_iClip2 > 0 || (wep.m_iClip2 == -1 && wep.m_iSecondaryAmmoType != -1 && plr.m_rgAmmo( wep.m_iSecondaryAmmoType ) > 0);
	bool secondaryFireReleased = (plr.m_afButtonPressed & IN_ATTACK2) == 0 && (lastPlrButtons[plr.entindex()] & IN_ATTACK2) != 0;
	string weaponName = wep.pev.classname;
	string mapName = g_Engine.mapname;
	
	// primary/secondary fire hooks going to be called this frame?
	bool primaryAttacking = primaryFirePressed && wep.m_flNextPrimaryAttack < g_Engine.time;
	bool secondaryAttacking = secondaryFirePressed && wep.m_flNextSecondaryAttack < g_Engine.time;
	
	// map-specific weapons
	if (mapName.Find("cracklife_") == 0) {
		
		if (weaponName == "weapon_clgauss") {
			if (secondaryFireReleased) {
				return !inWater;
			} else {
				return primaryAttacking && !secondaryFirePressed && hasPrimaryAmmo && !inWater;
			}
		}
		else if (weaponName == "weapon_clglock") {
			return hasPrimaryAmmo && !wep.m_fInReload && (primaryAttacking || secondaryAttacking);
		}
		else if (weaponName == "weapon_clmp5") {
			return primaryAttacking && hasPrimaryAmmo && !secondaryFirePressed && !inWater;
		}
		else if (weaponName == "weapon_clpython") {
			return primaryAttacking && hasPrimaryAmmo && !wep.m_fInReload && !inWater;
		}
		else if (weaponName == "weapon_clshotgun") {
			return (primaryAttacking || secondaryAttacking) && hasPrimaryAmmo && !inWater;
		}
	}
	if (mapName == "pizza_ya_san1" || mapName == "pizza_ya_san2") {			
		if (weaponName == "weapon_as_shotgun") {
			return (primaryAttacking || secondaryAttacking) && !inWater && hasPrimaryAmmo;
		}
		else if (weaponName == "weapon_as_jetpack") {
			return primaryAttacking && !inWater && hasPrimaryAmmo;
		}
	}
	else if (mapName == "alienshooter_demo") {
		if (weaponName == "weapon_alien_pistol") {
			return primaryAttacking && !secondaryFirePressed;
		}
		else if (weaponName == "weapon_alien_shotgun" or weaponName == "weapon_alien_mini") {
			return primaryAttacking && hasPrimaryAmmo && !secondaryFirePressed;
		}
	}
	else if (mapName.Find("rust_") == 0) {
		float cooldownTime = 0;
		float reloadTime = 0;
		int maxClip = 0;
		bool noAutofire = false;
		
		if (weaponName == "weapon_custom_deagle") {
			cooldownTime = 0.15;
			reloadTime = 1.6;
			maxClip = 10;
			noAutofire = true;
		}
		else if (weaponName == "weapon_custom_saw") {
			cooldownTime = 0.09;
			reloadTime = 6.6;
			maxClip = 100;
		}
		else if (weaponName == "weapon_custom_sniper") {
			cooldownTime = 2.0;
			reloadTime = 2.5;
			maxClip = 3;
		}
		else if (weaponName == "weapon_custom_uzi") {
			maxClip = 20;
			reloadTime = 2.7;
			cooldownTime = 0.09;
		}
		else if (weaponName == "weapon_custom_shotgun") {
			maxClip = 6;
			cooldownTime = 1.0;
			reloadTime = 0.6;
		} else {
			return false;
		}
		
		return is_weapon_custom_cooled_down(plr, wep, cooldownTime, reloadTime, maxClip, noAutofire) && !inWater; 
	}
	else if (mapName == "the_dust") {
		return primaryAttacking && hasPrimaryAmmo && !secondaryFirePressed;
	}

	// plugin weapons
	if (weaponName == "weapon_hl357") {
		return hasPrimaryAmmo && wep.m_flNextPrimaryAttack < g_Engine.time && !wep.m_fInReload && primaryFirePressed && !inWater;
	}
	
	
	// By default, don't compensate custom weapons every frame.
	// If you set this to true, the server will have insane lag spikes.
	return false;
}


// special logic for the weapon_custom scripts
bool is_weapon_custom_cooled_down(CBasePlayer@ plr, CBasePlayerWeapon@ wep, float cooldownTime, float reloadTime, int maxClip, bool noAutofire) {
	int buttons = plr.m_afButtonPressed | plr.m_afButtonLast | plr.m_afButtonReleased;
	bool primaryFirePressed = buttons & IN_ATTACK != 0;
	bool secondaryFirePressed = buttons & IN_ATTACK2 != 0;
	bool willReload = !primaryFirePressed && buttons & IN_RELOAD != 0 && wep.m_iClip < maxClip;
	
	if (willReload) {
		// prevent some of the compensation spam when reloading with fire button held with some ammo in clip
		g_lastAttack[plr.entindex()] = (g_Engine.time - cooldownTime) + (reloadTime - 0.1f);
		return false;
	}
	
	bool cooledDown = g_Engine.time - g_lastAttack[plr.entindex()] >= cooldownTime;
	bool hasPrimaryAmmo = wep.m_iClip > 0 || (wep.m_iClip == -1 && wep.m_iPrimaryAmmoType != -1 && plr.m_rgAmmo( wep.m_iPrimaryAmmoType ) > 0);
	bool primaryAttacking = primaryFirePressed && wep.m_flNextPrimaryAttack < g_Engine.time;
	
	if (noAutofire && plr.m_afButtonPressed & IN_ATTACK == 0 && wep.m_iClip < maxClip) {
		return false;
	}
	
	return primaryAttacking && hasPrimaryAmmo && !secondaryFirePressed && cooledDown;
}