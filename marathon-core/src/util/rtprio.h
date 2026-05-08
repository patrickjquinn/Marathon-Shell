// Header-only helper for elevating the calling thread to SCHED_RR. See
// docs/RT_SCHEDULING.md for the priority hierarchy and rationale.

#pragma once

#ifdef Q_OS_LINUX
#include <pthread.h>
#include <sched.h>

namespace marathon::rt {

    // priority>0 → SCHED_RR | SCHED_RESET_ON_FORK at that priority.
    // priority==0 → SCHED_OTHER. Returns errno from pthread_setschedparam.
    inline int setCurrentThreadPriority(int priority) {
        sched_param param;
        if (priority > 0) {
            param.sched_priority = priority;
            return pthread_setschedparam(pthread_self(), SCHED_RR | SCHED_RESET_ON_FORK, &param);
        }
        param.sched_priority = 0;
        return pthread_setschedparam(pthread_self(), SCHED_OTHER, &param);
    }

} // namespace marathon::rt
#endif
