#pragma once
#pragma pack(push,1)
#include "studio.h"

// This code was automatically generated by the ApiGenerator plugin.
// Prefer updating the generator code instead of editing this directly.
// "u[]" variables are unknown data.

void GetSequenceInfo(void* pmodel, entvars_t* pev, float* pflFrameRate, float* pflGroundSpeed);
int GetSequenceFlags(void* pmodel, entvars_t* pev);

// Example entity: player
class CBaseAnimating : public CBaseDelay {
public:
    float m_flFrameRate; // Computed FPS for current sequence.
    float m_flGroundSpeed; // Computed linear movement rate for current sequence.
    float m_flLastEventCheck; // Last time the event list was checked.
    float m_flLastGaitEventCheck; // Last time the event list was checked.
    bool m_fSequenceFinished; // Flag set when StudioAdvanceFrame moves across a frame boundry.
    bool m_fSequenceLoops; // True if the sequence loops.

    void ResetSequenceInfo() {
        void* pmodel = GET_MODEL_PTR(ENT(pev));

        GetSequenceInfo(pmodel, pev, &m_flFrameRate, &m_flGroundSpeed);
        m_fSequenceLoops = ((GetSequenceFlags(pmodel, pev) & STUDIO_LOOPING) != 0);
        pev->animtime = gpGlobals->time;
        pev->framerate = 1.0;
        m_fSequenceFinished = FALSE;
        m_flLastEventCheck = gpGlobals->time;
    }
 
};
#pragma pack(pop)