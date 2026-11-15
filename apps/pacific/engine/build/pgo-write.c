// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// PGO training only: loaded into the instrumented engine's processes, it
// writes WebKit's profile every 5 s. WebKit SIGKILLs its helper processes
// when the UI process exits, so the profile runtime's write at exit never
// runs in them.
//
// The profile file is opened in merge mode (%m in LLVM_PROFILE_FILE), so each
// write adds the counters to the file: they are zeroed after each write, or
// every write would add the running totals again (the counts grow without
// bound and overflow). The runtime's functions are hidden in libWPEWebKit and
// __llvm_profile_reset_counters is not linked in, so they are called at their
// addresses: the library's load base plus each symbol's value, which
// pgo-train.sh passes as PACIFIC_PGO_WRITE, five llvm-nm values separated by
// commas: __llvm_profile_write_file, __llvm_profile_begin_counters,
// __llvm_profile_end_counters, __llvm_profile_begin_vnodes,
// __llvm_profile_end_vnodes.
//
// A file written while the process is killed can be torn: merge only the
// files llvm-profdata merges cleanly.
#define _GNU_SOURCE
#include <link.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { WRITE, BEGIN_COUNTERS, END_COUNTERS, BEGIN_VNODES, END_VNODES, N };
static uintptr_t offsets[N];

// compiler-rt's ValueProfNode (InstrProfData.inc).
struct vnode {
    uint64_t value;
    uint64_t count;
    struct vnode *next;
};

static int find(struct dl_phdr_info *info, size_t size, void *data)
{
    (void)size;
    if (info->dlpi_name && strstr(info->dlpi_name, "/libWPEWebKit-2.0.so")) {
        *(uintptr_t *)data = info->dlpi_addr;
        return 1;
    }
    return 0;
}

static void *call(uintptr_t base, int which)
{
    return ((void *(*)(void))(base + offsets[which]))();
}

static void *loop(void *arg)
{
    (void)arg;
    for (;;) {
        sleep(5);
        uintptr_t base = 0;
        dl_iterate_phdr(find, &base);   // the UI process loads WebKit late
        if (!base)
            continue;
        if (((int (*)(void))(base + offsets[WRITE]))() != 0)
            continue;
        char *b = call(base, BEGIN_COUNTERS), *e = call(base, END_COUNTERS);
        if (b && e > b)
            memset(b, 0, (size_t)(e - b));
        struct vnode *vb = call(base, BEGIN_VNODES), *ve = call(base, END_VNODES);
        for (struct vnode *v = vb; v && v < ve; v++)
            v->count = 0;
    }
    return NULL;
}

__attribute__((constructor)) static void start(void)
{
    const char *v = getenv("PACIFIC_PGO_WRITE");
    if (!v)
        return;
    for (int i = 0; i < N; i++) {
        char *end = NULL;
        offsets[i] = (uintptr_t)strtoull(v, &end, 0);
        if (!offsets[i] || (i < N - 1 && *end != ','))
            return;
        v = end + 1;
    }
    pthread_t t;
    if (pthread_create(&t, NULL, loop, NULL) == 0)
        pthread_detach(t);
}
