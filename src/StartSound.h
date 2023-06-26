#pragma once
#include <string>
#include <extdll.h>

#define MSG_StartSound 107

#define SND_VOLUME 1
#define SND_PITCH 2
#define SND_ATTENUATION 4
#define SND_ORIGIN 8
#define SND_ENT 16
//#define SND_STOP 32
//#define SND_CHANGE_VOL 64
//#define SND_CHANGE_PITCH 128
#define SND_SENTENCE 256
#define SND_REFRESH 512
#define SND_FORCE_SINGLE 1024
#define SND_FORCE_LOOP 2048
#define SND_LINEAR 4096
#define SND_SKIP_ORIGIN_USE_ENT 8192
#define SND_IDK 16384 // this is set by ambient_music but idk what it does
#define SND_OFFSET 32768

#define CHAN_MUSIC 7
#define MAX_SOUND_CHANNELS (CHAN_MUSIC + 1)

struct StartSoundMsg {
	std::string sample = "";
	int soundIdx = 0;
	int channel = 0;
	float volume = 1.0f;
	float attenuation = 1.0f;
	int pitch = 100;
	float offset = 0;
	int entindex = -1;
	Vector origin = Vector(0, 0, 0);
	int flags = 0;

	StartSoundMsg() {}
	void send(int msg_dest=MSG_BROADCAST, edict_t* target=NULL);
};

void PlaySound(edict_t* entity, int channel, const std::string& sample, float volume, float attenuation, int flags = 0, int pitch = PITCH_NORM, int target_ent_unreliable = 0, bool setOrigin = false, const Vector& vecOrigin = Vector(0, 0, 0));