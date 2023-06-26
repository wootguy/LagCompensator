#include "misc_utils.h"
#include "meta_init.h"
#include "studio.h"

string getFileExtension(string fpath) {
	int dot = fpath.find_last_of(".");
	if (dot != -1 && dot < fpath.size()-1) {
		return fpath.substr(dot + 1);
	}

	return "";
}

string getPlayerUniqueId(edict_t* plr) {
	if (plr == NULL) {
		return "STEAM_ID_NULL";
	}

	string steamId = (*g_engfuncs.pfnGetPlayerAuthId)(plr);

	if (steamId == "STEAM_ID_LAN" || steamId == "BOT") {
		steamId = STRING(plr->v.netname);
	}

	return steamId;
}

string replaceString(string subject, string search, string replace) {
	size_t pos = 0;
	while ((pos = subject.find(search, pos)) != string::npos)
	{
		subject.replace(pos, search.length(), replace);
		pos += replace.length();
	}
	return subject;
}

edict_t* getPlayerByUniqueId(string id) {
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!ent || (ent->v.flags & FL_CLIENT) == 0) {
			continue;
		}

		if (id == getPlayerUniqueId(ent)) {
			return ent;
		}
	}

	return NULL;
}

edict_t* getPlayerByUserId(int id) {
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		if (id == (*g_engfuncs.pfnGetPlayerUserId)(ent)) {
			return ent;
		}
	}

	return NULL;
}

bool isValidPlayer(edict_t* plr) {
	return plr && (plr->v.flags & FL_CLIENT) != 0;
}

string trimSpaces(string s) {
	int start = s.find_first_not_of(" \t\n\r");
	int end = s.find_last_not_of(" \t\n\r");
	return (start == string::npos) ? "" : s.substr(start, end - start + 1);
}

string toLowerCase(string str) {
	string out = str;

	for (int i = 0; str[i]; i++) {
		out[i] = tolower(str[i]);
	}

	return out;
}

string vecToString(Vector vec) {
	return UTIL_VarArgs("%f, %f, %f", vec.x, vec.y, vec.z);
}

void ClientPrintAll(int msg_dest, const char* msg_name, const char* param1, const char* param2, const char* param3, const char* param4) {
	ClientPrint((edict_t*)NULL, msg_dest, msg_name, param1, param2, param3, param4);
}

void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1, const char* param2, const char* param3, const char* param4) {
	int dest = client ? MSG_ONE : MSG_ALL;
	
	MESSAGE_BEGIN(dest, MSG_TextMsg, NULL, client);
	WRITE_BYTE(msg_dest);
	WRITE_STRING(msg_name);

	if (param1)
		WRITE_STRING(param1);
	if (param2)
		WRITE_STRING(param2);
	if (param3)
		WRITE_STRING(param3);
	if (param4)
		WRITE_STRING(param4);

	MESSAGE_END();
}

unsigned short FixedUnsigned16(float value, float scale)
{
	int output;

	output = value * scale;
	if (output < 0)
		output = 0;
	if (output > 0xFFFF)
		output = 0xFFFF;

	return (unsigned short)output;
}

short FixedSigned16(float value, float scale)
{
	int output;

	output = value * scale;

	if (output > 32767)
		output = 32767;

	if (output < -32768)
		output = -32768;

	return (short)output;
}

// modified to not use CBaseEntity or loop through players to send individual messages
void HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage, int dest)
{
	if (dest == -1) {
		dest = pEntity ? MSG_ONE : MSG_ALL;
	}

	MESSAGE_BEGIN(dest, SVC_TEMPENTITY, NULL, pEntity);
	WRITE_BYTE(TE_TEXTMESSAGE);
	WRITE_BYTE(textparms.channel & 0xFF);

	WRITE_SHORT(FixedSigned16(textparms.x, 1 << 13));
	WRITE_SHORT(FixedSigned16(textparms.y, 1 << 13));
	WRITE_BYTE(textparms.effect);

	WRITE_BYTE(textparms.r1);
	WRITE_BYTE(textparms.g1);
	WRITE_BYTE(textparms.b1);
	WRITE_BYTE(textparms.a1);

	WRITE_BYTE(textparms.r2);
	WRITE_BYTE(textparms.g2);
	WRITE_BYTE(textparms.b2);
	WRITE_BYTE(textparms.a2);

	WRITE_SHORT(FixedUnsigned16(textparms.fadeinTime, 1 << 8));
	WRITE_SHORT(FixedUnsigned16(textparms.fadeoutTime, 1 << 8));
	WRITE_SHORT(FixedUnsigned16(textparms.holdTime, 1 << 8));

	if (textparms.effect == 2)
		WRITE_SHORT(FixedUnsigned16(textparms.fxTime, 1 << 8));

	if (strlen(pMessage) < 512)
	{
		WRITE_STRING(pMessage);
	}
	else
	{
		char tmp[512];
		strncpy(tmp, pMessage, 511);
		tmp[511] = 0;
		WRITE_STRING(tmp);
	}
	MESSAGE_END();
}

void HudMessageAll(const hudtextparms_t& textparms, const char* pMessage, int dest)
{
	HudMessage(NULL, textparms, pMessage, dest);
}

char* UTIL_VarArgs(char* format, ...)
{
	va_list		argptr;
	static char		string[1024];

	va_start(argptr, format);
	vsprintf(string, format, argptr);
	va_end(argptr);

	return string;
}

edict_t* CreateEntity(string cname, map<string, string> keyvalues, bool spawn) {
	edict_t* ent = g_engfuncs.pfnCreateNamedEntity(MAKE_STRING(cname.c_str()));

	for (auto item : keyvalues) {
		KeyValueData dat;
		dat.fHandled = false;
		dat.szClassName = (char*)STRING(ent->v.classname);
		dat.szKeyName = (char*)item.first.c_str();
		dat.szValue = (char*)item.second.c_str();
		gpGamedllFuncs->dllapi_table->pfnKeyValue(ent, &dat);
	}

	if (ent && spawn) {
		gpGamedllFuncs->dllapi_table->pfnSpawn(ent);
	}

	return ent;
}

void GetSequenceInfo(void* pmodel, entvars_t* pev, float* pflFrameRate, float* pflGroundSpeed)
{
	studiohdr_t* pstudiohdr;

	pstudiohdr = (studiohdr_t*)pmodel;
	if (!pstudiohdr)
		return;

	mstudioseqdesc_t* pseqdesc;

	if (pev->sequence >= pstudiohdr->numseq)
	{
		*pflFrameRate = 0.0;
		*pflGroundSpeed = 0.0;
		return;
	}

	pseqdesc = (mstudioseqdesc_t*)((byte*)pstudiohdr + pstudiohdr->seqindex) + (int)pev->sequence;

	if (pseqdesc->numframes > 1)
	{
		*pflFrameRate = 256 * pseqdesc->fps / (pseqdesc->numframes - 1);
		*pflGroundSpeed = sqrt(pseqdesc->linearmovement[0] * pseqdesc->linearmovement[0] + pseqdesc->linearmovement[1] * pseqdesc->linearmovement[1] + pseqdesc->linearmovement[2] * pseqdesc->linearmovement[2]);
		*pflGroundSpeed = *pflGroundSpeed * pseqdesc->fps / (pseqdesc->numframes - 1);
	}
	else
	{
		*pflFrameRate = 256.0;
		*pflGroundSpeed = 0.0;
	}
}

int GetSequenceFlags(void* pmodel, entvars_t* pev)
{
	studiohdr_t* pstudiohdr;

	pstudiohdr = (studiohdr_t*)pmodel;
	if (!pstudiohdr || pev->sequence >= pstudiohdr->numseq)
		return 0;

	mstudioseqdesc_t* pseqdesc;
	pseqdesc = (mstudioseqdesc_t*)((byte*)pstudiohdr + pstudiohdr->seqindex) + (int)pev->sequence;

	return pseqdesc->flags;
}

float clampf(float val, float min, float max) {
	if (val > max) {
		return max;
	}
	else if (val < min) {
		return min;
	}
	return val;
}

int clamp(int val, int min, int max) {
	if (val > max) {
		return max;
	}
	else if (val < min) {
		return min;
	}
	return val;
}