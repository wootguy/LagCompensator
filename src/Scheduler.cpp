#include "Scheduler.h"
#include "meta_utils.h"

Scheduler g_Scheduler;
unsigned int g_schedule_id = 1;

void Scheduler::Think() {
    float now = g_engfuncs.pfnTime();

    for (int i = 0; i < functions.size(); i++) {
        ScheduledFunction_internal& sched = functions[i];

        if (now - sched.lastCall < sched.delay) {
            continue;
        }

        sched.func();
        sched.lastCall = now;
        sched.callCount++;

        if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
            functions.erase(functions.begin() + i);
            i--;
        }
    }
}

void Scheduler::RemoveTimer(ScheduledFunction sched) {
    for (int i = 0; i < functions.size(); i++) {
        if (functions[i].scheduleId == sched.scheduleId) {
            functions.erase(functions.begin() + i);
            return;
        }
    }
}

bool ScheduledFunction::HasBeenRemoved() {
    for (int i = 0; i < g_Scheduler.functions.size(); i++) {
        if (g_Scheduler.functions[i].scheduleId == scheduleId) {
            return false;
        }
    }
    return true;
}