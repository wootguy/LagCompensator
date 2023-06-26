#pragma once
#include <string>
#include <extdll.h>
#include <edict.h>

enum HUD_EFFECT {
	HUD_EFFECT_NONE = 0,
	HUD_EFFECT_RAMP_UP = 1,
	HUD_EFFECT_RAMP_DOWN = 2,
	HUD_EFFECT_TRIANGLE = 3,
	HUD_EFFECT_COSINE_UP = 4,
	HUD_EFFECT_COSINE_DOWN = 5,
	HUD_EFFECT_COSINE = 6,
	HUD_EFFECT_TOGGLE = 7,
	HUD_EFFECT_SINE_PULSE = 8
};

enum HUD_ELEM {
	HUD_ELEM_ABSOLUTE_X = 1,
	HUD_ELEM_ABSOLUTE_Y = 2,
	HUD_ELEM_SCR_CENTER_X = 4,
	HUD_ELEM_SCR_CENTER_Y = 8,
	HUD_ELEM_NO_BORDER = 16,
	HUD_ELEM_HIDDEN = 32,
	HUD_ELEM_EFFECT_ONCE = 64,
	HUD_ELEM_DEFAULT_ALPHA = 128,
	HUD_ELEM_DYNAMIC_ALPHA = 256
};

enum HUD_SPR {
	HUD_SPR_OPAQUE = 65536,
	HUD_SPR_MASKED = 131072,
	HUD_SPR_PLAY_ONCE = 262144,
	HUD_SPR_HIDE_WHEN_STOPPED = 524288
};

#define MSG_CustSpr 140

struct RGBA {
	uint8_t r, g, b, a;

	RGBA() : r(0), g(0), b(0), a(255) {}
	RGBA(uint8_t r, uint8_t g, uint8_t b, uint8_t a) : r(r), g(g), b(b), a(a) {}
	RGBA(uint8_t r, uint8_t g, uint8_t b) : r(r), g(g), b(b), a(255) {}
};

struct HUDSpriteParams {
	uint8_t channel;
	int flags;
	std::string spritename;
	uint8_t left;
	uint8_t top;
	uint16_t width;
	uint16_t height;
	float x;
	float y;
	RGBA color1;
	RGBA color2;
	uint8_t frame;
	uint8_t numframes;
	float framerate;
	float fadeinTime;
	float fadeoutTime;
	float holdTime;
	float fxTime;
	uint8_t effect;
};

void HudCustomSprite(edict_t* targetPlr, const HUDSpriteParams& params);