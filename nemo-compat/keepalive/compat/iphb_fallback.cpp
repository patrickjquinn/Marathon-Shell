// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Timer-based stand-in for libiphb (see compat/iphbd/libiphb.h). A wait arms
// a helper thread that writes one byte to a socketpair after `mintime`
// seconds, or after `maxtime` when `mintime` is 0 (real iphb wakes by
// `maxtime` at the latest and never before `mintime`); the reading end is what iphb_get_fd() returns, so Heartbeat's
// QSocketNotifier and recv() work unchanged. KEEL_IPHB_FALLBACK_SCALE_MS
// (default 1000) sets how many milliseconds one requested second lasts, so
// tests can run quickly.

#include "iphbd/libiphb.h"

#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <mutex>
#include <thread>

#include <sys/socket.h>
#include <unistd.h>

namespace {

struct FallbackHandle
{
    int fds[2] = { -1, -1 }; // [0] returned to the client, [1] written on expiry
    std::mutex mutex;
    std::condition_variable cv;
    std::thread worker;
    unsigned generation = 0;
    bool armed = false;
    bool quit = false;
    std::chrono::steady_clock::time_point deadline;

    void run()
    {
        std::unique_lock<std::mutex> lock(mutex);
        while (!quit) {
            if (!armed) {
                cv.wait(lock);
                continue;
            }
            const unsigned gen = generation;
            if (cv.wait_until(lock, deadline) == std::cv_status::timeout && armed && gen == generation) {
                armed = false;
                const char byte = 1;
                ssize_t rc = ::send(fds[1], &byte, 1, MSG_DONTWAIT | MSG_NOSIGNAL);
                (void)rc;
            }
        }
    }
};

long scaleMs()
{
    const char *s = std::getenv("KEEL_IPHB_FALLBACK_SCALE_MS");
    const long v = s ? std::strtol(s, nullptr, 10) : 0;
    return v > 0 ? v : 1000;
}

void drain(int fd)
{
    char buf[64];
    while (::recv(fd, buf, sizeof buf, MSG_DONTWAIT) > 0) {
    }
}

} // namespace

extern "C" {

// NOLINTNEXTLINE(readability-non-const-parameter): libiphb's signature
iphb_t iphb_open(int *dummy)
{
    (void)dummy;
    auto *h = new FallbackHandle;
    if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, h->fds) != 0) {
        delete h;
        return nullptr;
    }
    h->worker = std::thread(&FallbackHandle::run, h);
    return h;
}

int iphb_get_fd(iphb_t iphbh)
{
    if (!iphbh) {
        errno = EINVAL;
        return -1;
    }
    return static_cast<FallbackHandle *>(iphbh)->fds[0];
}

time_t iphb_wait2(iphb_t iphbh, unsigned mintime, unsigned maxtime, int must_wait, int resume)
{
    (void)resume;
    if (!iphbh || must_wait) {
        errno = EINVAL;
        return static_cast<time_t>(-1);
    }
    auto *h = static_cast<FallbackHandle *>(iphbh);
    {
        std::scoped_lock lock(h->mutex);
        drain(h->fds[0]);
        ++h->generation;
        h->armed = mintime > 0 || maxtime > 0;
        // A range [0, max] must not fire at once: a heartbeat that re-arms
        // from its wakeup would busy-loop.
        const unsigned seconds = mintime > 0 ? mintime : maxtime;
        h->deadline = std::chrono::steady_clock::now()
                + std::chrono::milliseconds(scaleMs() * static_cast<long>(seconds));
    }
    h->cv.notify_all();
    return 0;
}

int iphb_discard_wakeups(iphb_t iphbh)
{
    if (!iphbh)
        return -1;
    drain(static_cast<FallbackHandle *>(iphbh)->fds[0]);
    return 0;
}

iphb_t iphb_close(iphb_t iphbh)
{
    if (!iphbh)
        return nullptr;
    auto *h = static_cast<FallbackHandle *>(iphbh);
    {
        std::scoped_lock lock(h->mutex);
        h->quit = true;
    }
    h->cv.notify_all();
    h->worker.join();
    ::close(h->fds[0]);
    ::close(h->fds[1]);
    delete h;
    return nullptr;
}

} // extern "C"
