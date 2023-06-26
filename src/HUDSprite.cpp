#include "HUDSprite.h"
#include "private_api.h"
#include "meta_utils.h"
#include "misc_utils.h"

// for some reason sven sends some floats this way instead of using WRITE_COORD
void WRITE_FLOAT_SVEN(float f) {
	uint8_t* fbytes = (uint8_t*)&f;
	WRITE_BYTE(fbytes[0]);
	WRITE_BYTE(fbytes[1]);
	WRITE_BYTE(fbytes[2]);
	WRITE_BYTE(fbytes[3]);
}

void WRITE_RGBA(RGBA rgba) {
	WRITE_BYTE(rgba.r);
	WRITE_BYTE(rgba.g);
	WRITE_BYTE(rgba.b);
	WRITE_BYTE(rgba.a);
}

void HudCustomSprite(edict_t* targetPlr, const HUDSpriteParams& params) {
	int msg_dest = targetPlr ? MSG_ONE : MSG_ALL;

	MESSAGE_BEGIN(msg_dest, MSG_CustSpr, NULL, targetPlr);

	WRITE_BYTE(params.channel);
	WRITE_LONG(params.flags);
	WRITE_STRING(params.spritename.c_str());
	WRITE_BYTE(params.left);
	WRITE_BYTE(params.top);
	WRITE_SHORT(params.width);
	WRITE_SHORT(params.height);
	WRITE_FLOAT_SVEN(params.x);
	WRITE_FLOAT_SVEN(params.y);
	WRITE_RGBA(params.color1);
	WRITE_RGBA(params.color2);
	WRITE_BYTE(params.frame);
	WRITE_BYTE(params.numframes);
	WRITE_FLOAT_SVEN(params.framerate);
	WRITE_FLOAT_SVEN(params.fadeinTime);
	WRITE_FLOAT_SVEN(params.fadeoutTime);
	WRITE_FLOAT_SVEN(params.holdTime);
	WRITE_FLOAT_SVEN(params.fxTime);
	WRITE_BYTE(params.effect);

	MESSAGE_END();
}