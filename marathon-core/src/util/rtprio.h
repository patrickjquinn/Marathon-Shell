// Header-only helper for elevating the calling thread to the SCHED_RR real-time
// scheduling class. SCHED_RR (not FIFO) round-robins between same-priority RT
// threads so we can't starve same-priority audio / modem / kernel-IRQ paths if
// the caller busy-loops. SCHED_RESET_ON_FORK clears RT on any forked children
// so spawned helpers don't inherit it.
//
// The matching priority hierarchy is documented in docs/RT_SCHEDULING.md.

#pragma once

#ifdef Q_OS_LINUX
#include <pthread.h>
#include <sched.h>

namespace marathon::rt {

    // Set the calling thread's scheduling class.
    //   priority > 0  -> SCHED_RR | SCHED_RESET_ON_FORK at that priority
    //   priority == 0 -> SCHED_OTHER (default time-sharing)
    // Returns the errno-style rc from pthread_setschedparam (0 on success).
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
