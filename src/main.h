#pragma once
#include "meta_init.h"
#include "misc_utils.h"
#include "meta_utils.h"
#include "private_api.h"
#include <set>
#include <map>
#include "Activity.h"
#include "HUDSprite.h"
#include "StartSound.h"
#include "Scheduler.h"
#include "StartSound.h"

struct PlayerState {
	// Never store player handle? It needs to be set to null on disconnect or else states start sharing
	// player handles and cause weird bugs or break states entirely. Check if disconnect is called
	// if player leaves during level change.

	bool enabled = true;
	int compensation = 0;
	int adjustMode = 0;
	int debug = 0;
	bool hitmarker = false;

	// get ping time in seconds
	float getCompensationPing(CBasePlayer* plr);
};

enum AdjustModes {
	ADJUST_NONE, // use ping value
	ADJUST_ADD, // add to ping value
	ADJUST_SUB // subtract from ping value
};

struct EntState {
	float time = 0;
	Vector origin = Vector(0,0,0);
	Vector angles = Vector(0,0,0);
	int sequence = 0;
	float frame = 0;
};

struct LagEnt {
	EHandle h_ent;

	EntState currentState; // only updated on shoots
	float currentHealth = 0; // used to detect if player shot this monster
	int currentDeadFlag = 0;

	EntState debugState; // used to display a debug model when a player shoots
	vector<EntState> history;
	bool isRewound = false;
	bool hasEnoughHistory = false;

	LagEnt() {}

	LagEnt(CBaseEntity* ent) : h_ent(EHandle(ent)) {}

	bool update_history();
};

struct HitmarkEnt {
	EHandle h_ent;
	float currentHealth = 0; // used to detect if player shot this breakable

	HitmarkEnt() {}

	HitmarkEnt(CBaseEntity* ent) : h_ent(EHandle(ent)) { }
};

extern vector<LagEnt> laggyEnts;
extern vector<HitmarkEnt> hitmarkEnts;
extern int g_state_count;
extern bool g_enabled;
extern float g_update_delay;

extern const float MAX_LAG_COMPENSATION_SECONDS;
extern const char* hitmarker_spr;
extern const char* hitmarker_snd;

extern ScheduledFunction update_interval; // time between removal of deleted entities from entity history
extern ScheduledFunction cleanup_interval; // time between removal of deleted entities from entity history

PlayerState& getPlayerState(edict_t* plr);
PlayerState& getPlayerState(CBasePlayer* plr);

void reload_ents();
void update_ent_history();

void ClientCommand(edict_t* pEntity);
