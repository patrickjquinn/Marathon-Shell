// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// pacific-boostd: CPU and GPU clock floors while the user touches or scrolls
// a page, as Android's power HAL gives the app in front.
//
// Sailfish raises no clocks on touch. Flinging pages on the Jolla Phone, the
// big cores sat at their 650 MHz minimum for the first ~120 ms and the GPU at
// 385 MHz (of 1000) throughout, 60-70% busy. With floors of 75% of each CPU
// cluster's maximum and 70% of the GPU's, OSNews went from 74 to 86 frames a
// second while moving, Wikipedia from 84 to 90 (the panel's rate) and The
// Verge from 79 to 84, with a third as many frames over 25 ms. Android's
// IPower setBoost(INTERACTION) reaches MediaTek's power HAL but boosts only
// Android's foreground app, and FPSGO never sees Pacific's frames.
//
// It is started by pacific-boost.socket, the abstract datagram socket
// "org.shipwright.pacific.boost" (no file to share with the sandbox), the
// first time Pacific asks, and exits after IDLE_EXIT_MS without requests:
// nothing runs on a phone where Pacific is not in use. Each datagram is a
// uint32 duration in ms, capped at 3000, and is taken only from Pacific's
// own process (the sender's credentials and executable); anything else is
// dropped. The floors stay while requests keep coming.
//
// The clocks always come back. The values before any boost are written once
// per boot to BASELINE (on /run, a tmpfs) and are what every instance puts
// back: after the last request runs out, at exit, at the start of the next
// instance, and from `pacific-boostd --restore` (the unit's ExecStopPost,
// which systemd runs however the daemon ended, a crash or SIGKILL included).
// The baseline is taken at boot, before anyone touches the screen, by
// `pacific-boostd --baseline` (pacific-boost-baseline.service, and the
// package's %post): some kernels raise the floor for a moment on every touch
// (input boost), and the first request comes with a touch, so a baseline
// read then could be a boosted floor kept for the whole boot.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <stddef.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define SOCKET_NAME "org.shipwright.pacific.boost"
#define MAX_BOOST_MS 3000
#define CPU_FLOOR_PERCENT 75
#define GPU_FLOOR_PERCENT 70
#define MAX_KNOBS 16
#define IDLE_EXIT_MS 60000
#define BASELINE "/run/pacific-boost/baseline"
#define PACIFIC_EXE "/usr/bin/shipwright-pacific"
// The device owner's and other people's uids on Sailfish OS.
#define FIRST_USER_UID 100000

// A sysfs value raised while boosting and put back after.
struct knob {
    char path[512];
    char boosted[32];
    char saved[64];
};

static struct knob knobs[MAX_KNOBS];
static int nknobs;
static int boosting;
static volatile sig_atomic_t stopping;

static int read_file(const char *path, char *buf, size_t size)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    size_t n = fread(buf, 1, size - 1, f);
    fclose(f);
    buf[n] = 0;
    while (n && (buf[n - 1] == '\n' || buf[n - 1] == ' '))
        buf[--n] = 0;
    return 0;
}

static int write_file(const char *path, const char *value)
{
    FILE *f = fopen(path, "w");
    if (!f)
        return -1;
    int ok = fputs(value, f) >= 0;
    return fclose(f) == 0 && ok ? 0 : -1;
}

// The decimal number at the start of s (after blanks), or -1 when there is
// none.
static long number(const char *s, char **end)
{
    char *stop = NULL;
    errno = 0;
    long v = strtol(s, &stop, 10);
    if (end)
        *end = stop;
    return stop == s || errno ? -1 : v;
}

static void add_knob(const char *path, const char *boosted)
{
    if (nknobs == MAX_KNOBS || access(path, R_OK | W_OK) != 0)
        return;
    struct knob *k = &knobs[nknobs++];
    snprintf(k->path, sizeof k->path, "%s", path);
    snprintf(k->boosted, sizeof k->boosted, "%s", boosted);
    fprintf(stderr, "pacific-boostd: %s -> %s while boosting\n", path, boosted);
}

// Each cpufreq policy: the lowest available frequency at or above
// CPU_FLOOR_PERCENT of its maximum as scaling_min_freq.
static void find_cpu_knobs(void)
{
    DIR *dir = opendir("/sys/devices/system/cpu/cpufreq");
    struct dirent *e = NULL;
    if (!dir)
        return;
    while ((e = readdir(dir))) {
        if (strncmp(e->d_name, "policy", 6) != 0)
            continue;
        char path[512], buf[1024];
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpufreq/%s/cpuinfo_max_freq", e->d_name);
        if (read_file(path, buf, sizeof buf))
            continue;
        long max = number(buf, NULL);
        if (max <= 0)
            continue;
        long want = max * CPU_FLOOR_PERCENT / 100, floor = max;
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpufreq/%s/scaling_available_frequencies", e->d_name);
        if (!read_file(path, buf, sizeof buf)) {
            for (char *t = strtok(buf, " "); t; t = strtok(NULL, " ")) {
                long f = number(t, NULL);
                if (f >= want && f < floor)
                    floor = f;
            }
        } else {
            floor = want;
        }
        char value[32];
        snprintf(value, sizeof value, "%ld", floor);
        snprintf(path, sizeof path, "/sys/devices/system/cpu/cpufreq/%s/scaling_min_freq", e->d_name);
        add_knob(path, value);
    }
    closedir(dir);
}

// MediaTek GED: custom_boost_gpu_freq takes the operating point index of a
// floor (0 is none); the working OPP table lists "[NN] freq: KHZ, ...".
static void find_gpu_knobs(void)
{
    const char *boost = "/sys/kernel/ged/hal/custom_boost_gpu_freq";
    FILE *f = fopen("/proc/gpufreqv2/gpu_working_opp_table", "r");
    if (!f || access(boost, W_OK) != 0) {
        if (f)
            fclose(f);
        return;
    }
    long max = 0, freqs[64];
    int n = 0;
    char line[256];
    while (n < 64 && fgets(line, sizeof line, f)) {
        // " [NN] freq: KHZ, ..."
        char *open = strchr(line, '['), *end = NULL;
        if (!open)
            continue;
        long index = number(open + 1, &end);
        char *field = *end == ']' ? strstr(end, "freq:") : NULL;
        long freq = field ? number(field + 5, NULL) : -1;
        if (index == n && freq > 0) {
            freqs[n++] = freq;
            if (freq > max)
                max = freq;
        }
    }
    fclose(f);
    // Index 0 is the fastest; the floor is the slowest at or above the share.
    int chosen = -1;
    for (int i = 0; i < n; i++) {
        if (freqs[i] * 100 >= max * GPU_FLOOR_PERCENT)
            chosen = i;
    }
    if (chosen <= 0)
        return;
    char value[16];
    snprintf(value, sizeof value, "%d", chosen);
    add_knob(boost, value);
}

static int is_gpu(const struct knob *k)
{
    return strstr(k->path, "custom_boost_gpu_freq") != NULL;
}

// Puts every knob back to its baseline.
static void restore(void)
{
    for (int i = 0; i < nknobs; i++) {
        // GED's file reads back a log line; its floor's "none" is 0.
        const char *value = is_gpu(&knobs[i]) ? "0" : knobs[i].saved;
        if (*value && write_file(knobs[i].path, value))
            fprintf(stderr, "pacific-boostd: cannot put back %s: %s\n", knobs[i].path, strerror(errno));
    }
}

// The baseline: read from BASELINE when an earlier instance this boot wrote
// it (this instance's knobs may still be boosted by one that died), or else
// from the knobs, which nothing of ours has touched since boot, and written
// there (whole, then renamed).
static void load_baseline(void)
{
    FILE *f = fopen(BASELINE, "r");
    if (f) {
        char line[640];
        while (fgets(line, sizeof line, f)) {
            char *sp = strrchr(line, ' ');
            if (!sp)
                continue;
            *sp = 0;
            char *v = sp + 1;
            v[strcspn(v, "\n")] = 0;
            for (int i = 0; i < nknobs; i++) {
                if (!strcmp(knobs[i].path, line))
                    snprintf(knobs[i].saved, sizeof knobs[i].saved, "%s", v);
            }
        }
        fclose(f);
    }
    int missing = 0;
    for (int i = 0; i < nknobs; i++) {
        if (!knobs[i].saved[0] && !is_gpu(&knobs[i])) {
            if (read_file(knobs[i].path, knobs[i].saved, sizeof knobs[i].saved))
                knobs[i].saved[0] = 0;
            missing = 1;
        }
    }
    if (!missing && f)
        return;
    (void)mkdir("/run/pacific-boost", 0755);
    FILE *w = fopen(BASELINE ".new", "w");
    if (!w)
        return;
    for (int i = 0; i < nknobs; i++) {
        if (knobs[i].saved[0])
            fprintf(w, "%s %s\n", knobs[i].path, knobs[i].saved);
    }
    if (fclose(w) == 0)
        rename(BASELINE ".new", BASELINE);
}

static void boost_on(void)
{
    if (boosting)
        return;
    for (int i = 0; i < nknobs; i++)
        write_file(knobs[i].path, knobs[i].boosted);
    boosting = 1;
}

static void boost_off(void)
{
    if (!boosting)
        return;
    restore();
    boosting = 0;
}

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

// True when the datagram came from Pacific: a person's uid and Pacific's
// executable (the sender's /proc entry, seen from outside its sandbox).
static int from_pacific(const struct ucred *cred)
{
    static pid_t last_refused = -1;
    static long long last_said;
    char link[64], exe[256] = "?";
    if (cred) {
        snprintf(link, sizeof link, "/proc/%d/exe", (int)cred->pid);
        ssize_t n = readlink(link, exe, sizeof exe - 1);
        exe[n > 0 ? n : 0] = 0;
        if (cred->uid >= FIRST_USER_UID && !strcmp(exe, PACIFIC_EXE))
            return 1;
    }
    // Said once per sender and at most once a minute: refused senders cannot
    // fill the journal under this root unit's name.
    pid_t pid = cred ? cred->pid : 0;
    if (pid != last_refused && now_ms() - last_said >= 60000) {
        last_refused = pid;
        last_said = now_ms();
        fprintf(stderr, "pacific-boostd: refused a request from pid %d uid %d (%s): not Pacific\n",
                (int)pid, cred ? (int)cred->uid : -1, exe);
    }
    return 0;
}

// The socket systemd passes (LISTEN_FDS, fd 3), or one of its own when run
// by hand.
static int listen_socket(void)
{
    const char *pid = getenv("LISTEN_PID"), *fds = getenv("LISTEN_FDS");
    if (pid && fds && atol(pid) == (long)getpid() && atoi(fds) >= 1)
        return 3;
    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    memcpy(addr.sun_path + 1, SOCKET_NAME, strlen(SOCKET_NAME));
    socklen_t len = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCKET_NAME);
    if (fd < 0 || bind(fd, (struct sockaddr *)&addr, len) < 0)
        return -1;
    return fd;
}


static void on_signal(int sig)
{
    (void)sig;
    stopping = 1;
}

int main(int argc, char **argv)
{
    find_cpu_knobs();
    find_gpu_knobs();
    if (!nknobs) {
        fprintf(stderr, "pacific-boostd: nothing to boost on this device\n");
        return 0;
    }
    load_baseline();
    if (argc > 1 && !strcmp(argv[1], "--baseline"))
        return 0;
    // A boost left by an instance that died, or --restore after one.
    restore();
    if (argc > 1 && !strcmp(argv[1], "--restore"))
        return 0;

    int fd = listen_socket();
    int on = 1;
    if (fd < 0 || setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &on, sizeof on) < 0) {
        fprintf(stderr, "pacific-boostd: cannot listen: %s\n", strerror(errno));
        return 1;
    }

    struct sigaction sa = { .sa_handler = on_signal };
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    long long until = 0, idle_since = now_ms();
    while (!stopping) {
        int timeout = IDLE_EXIT_MS;
        if (boosting) {
            long long left = until - now_ms();
            if (left <= 0) {
                boost_off();
                idle_since = now_ms();
                continue;
            }
            timeout = (int)left;
        } else if (now_ms() - idle_since >= IDLE_EXIT_MS) {
            break; // the socket starts it again on the next request
        }
        struct pollfd p = { .fd = fd, .events = POLLIN };
        int r = poll(&p, 1, timeout);
        if (r < 0 && errno != EINTR)
            break;
        if (r <= 0)
            continue;
        uint32_t ms = 0;
        union {
            struct cmsghdr align;
            char buf[CMSG_SPACE(sizeof(struct ucred))];
        } control;
        struct iovec iov = { .iov_base = &ms, .iov_len = sizeof ms };
        struct msghdr msg = { .msg_iov = &iov, .msg_iovlen = 1,
                              .msg_control = control.buf, .msg_controllen = sizeof control.buf };
        if (recvmsg(fd, &msg, 0) != sizeof ms || !ms)
            continue;
        struct ucred *cred = NULL;
        for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
            if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_CREDENTIALS)
                cred = (struct ucred *)CMSG_DATA(c);
        }
        if (!from_pacific(cred))
            continue;
        if (ms > MAX_BOOST_MS)
            ms = MAX_BOOST_MS;
        long long end = now_ms() + ms;
        if (end > until)
            until = end;
        boost_on();
    }
    boost_off();
    return 0;
}
