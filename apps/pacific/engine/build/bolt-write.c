// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// BOLT training only (build.sh bolt-instrument, pgo-train.sh): loaded into
// the BOLT-instrumented engine's processes, it writes each process's counts
// every 5 s. BOLT's own timed dump cannot write a file per process, and
// WebKit SIGKILLs its helper processes, so the dump at exit never runs in
// them.
//
// The runtime's __bolt_instr_data_dump(fd) is hidden in libWPEWebKit, so it
// is called at its address: the library's load base plus the symbol's value,
// which pgo-train.sh passes as PACIFIC_BOLT_DUMP (llvm-nm on the
// instrumented library). Each dump has the totals so far: it goes to a
// temporary file renamed over the process's own, so a process killed while
// writing leaves its last whole dump. File names carry a random token as well
// as the pid: the sandboxes number their processes from 1 each.
#define _GNU_SOURCE
#include <fcntl.h>
#include <link.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <unistd.h>

static uintptr_t dump_offset;
static char path[512], tmp[520];

static int find(struct dl_phdr_info *info, size_t size, void *data)
{
    (void)size;
    if (info->dlpi_name && strstr(info->dlpi_name, "/libWPEWebKit-2.0.so")) {
        *(uintptr_t *)data = info->dlpi_addr;
        return 1;
    }
    return 0;
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
        int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
        if (fd < 0)
            continue;
        ((void (*)(int))(base + dump_offset))(fd);
        close(fd);
        rename(tmp, path);
    }
    return NULL;
}

__attribute__((constructor)) static void start(void)
{
    const char *v = getenv("PACIFIC_BOLT_DUMP");
    const char *dir = getenv("PACIFIC_BOLT_DIR");
    if (!v || !dir)
        return;
    dump_offset = (uintptr_t)strtoull(v, NULL, 0);
    if (!dump_offset)
        return;
    unsigned int token = 0;
    if (getrandom(&token, sizeof token, 0) != (ssize_t)sizeof token)
        token = (unsigned int)getpid() * 2654435761u;
    snprintf(path, sizeof path, "%s/bolt.%d.%08x.fdata", dir, (int)getpid(), token);
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    pthread_t t;
    if (pthread_create(&t, NULL, loop, NULL) == 0)
        pthread_detach(t);
}
