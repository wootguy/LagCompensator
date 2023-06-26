#pragma once
#include <vector>
#include <functional>

struct ScheduledFunction_internal {
    std::function<void()> func;
    float delay;
    int callCount;
    int maxCalls; // infinite if < 0
    float lastCall;
    unsigned int scheduleId;
};

// for ease of angelscript porting
class ScheduledFunction {
public:
    unsigned int scheduleId = 0;

    ScheduledFunction() {}
    ScheduledFunction(int scheduleId) : scheduleId(scheduleId) {}

    bool HasBeenRemoved();
};

// there should only be one instance of this in the plugin (g_Scheduler)
class Scheduler {
public:
    std::vector<ScheduledFunction_internal> functions;

    template <typename F, typename... Args>
    ScheduledFunction SetTimeout(F&& func, float delay, Args&&... args) {
        ScheduledFunction_internal f = {
            std::bind(std::forward<F>(func), std::forward<Args>(args)...),
            delay,
            0,
            1,
            g_engfuncs.pfnTime(),
            g_schedule_id
        };
        functions.push_back(f);
        return ScheduledFunction(g_schedule_id++);
    }

    template <typename F, typename... Args>
    ScheduledFunction SetInterval(F&& func, float delay, int maxCalls, Args&&... args) {
        ScheduledFunction_internal f = {
            std::bind(std::forward<F>(func), std::forward<Args>(args)...),
            delay,
            0,
            maxCalls,
            g_engfuncs.pfnTime(),
            g_schedule_id
        };
        functions.push_back(f);
        return ScheduledFunction(g_schedule_id++);
    }

    void Think();

    void RemoveTimer(ScheduledFunction schedule);

};

extern unsigned int g_schedule_id; // don't touch this
extern Scheduler g_Scheduler;