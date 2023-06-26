#include "StartSound.h"
#include "meta_utils.h"
#include "misc_utils.h"

void StartSoundMsg::send(int msg_dest, edict_t* target) {
	if (soundIdx == -1) {
		println("ZOMG FIND THE SOUDN INDEX");
		return;
	}

	MESSAGE_BEGIN(msg_dest, MSG_StartSound, NULL, target);
	WRITE_SHORT(flags);

	if (flags & SND_ENT) {
		WRITE_SHORT(entindex);
	}
	if (flags & SND_VOLUME) {
		WRITE_BYTE(clamp(int(volume * 255), 0, 255));
	}
	if (flags & SND_PITCH) {
		WRITE_BYTE(pitch);
	}
	if (flags & SND_ATTENUATION) {
		WRITE_BYTE(clamp(int(attenuation * 64), 0, 255));
	}
	if (flags & SND_ORIGIN) {
		WRITE_COORD(origin.x);
		WRITE_COORD(origin.y);
		WRITE_COORD(origin.z);
	}
	if (flags & SND_OFFSET) {
		uint8_t* fbytes = (uint8_t*)&offset;
		WRITE_BYTE(fbytes[0]);
		WRITE_BYTE(fbytes[1]);
		WRITE_BYTE(fbytes[2]);
		WRITE_BYTE(fbytes[3]);
	}

	WRITE_BYTE(channel);
	WRITE_SHORT(soundIdx);

	MESSAGE_END();
}

void PlaySound(edict_t* entity, int channel, const std::string& sample, float volume, float attenuation, 
	int flags, int pitch, int target_ent_unreliable, bool setOrigin, const Vector& vecOrigin) {

	edict_t* target = target_ent_unreliable ? INDEXENT(target_ent_unreliable) : NULL;
	StartSoundMsg msg;

	msg.channel = clamp(channel, 0, MAX_SOUND_CHANNELS);
	msg.sample = sample;
	msg.volume = volume;
	msg.attenuation = attenuation;
	msg.flags = flags;
	msg.pitch = pitch;
	msg.origin = vecOrigin;
	msg.soundIdx = -1;

	if (entity) {
		msg.entindex = ENTINDEX(entity);
		msg.flags |= SND_ENT;
	}
	if (setOrigin) {
		msg.flags |= SND_ORIGIN;
	}
	if (pitch != PITCH_NORM) {
		msg.flags |= SND_PITCH;
	}
	msg.flags |= SND_ATTENUATION; // TODO: make this conditional. idk what the default value is
	
	if (target) {
		msg.send(MSG_ONE_UNRELIABLE, target);
	}
	else {
		msg.send(MSG_ALL);
	}
}
