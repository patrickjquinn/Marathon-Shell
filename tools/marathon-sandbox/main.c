#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/landlock.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <syslog.h>
#include <unistd.h>

#ifndef landlock_create_ruleset
static inline int landlock_create_ruleset(const struct landlock_ruleset_attr *attr, size_t size,
                                          __u32 flags) {
    return syscall(__NR_landlock_create_ruleset, attr, size, flags);
}
#endif

#ifndef landlock_add_rule
static inline int landlock_add_rule(int ruleset_fd, enum landlock_rule_type rule_type,
                                    const void *rule_attr, __u32 flags) {
    return syscall(__NR_landlock_add_rule, ruleset_fd, rule_type, rule_attr, flags);
}
#endif

#ifndef landlock_restrict_self
static inline int landlock_restrict_self(int ruleset_fd, __u32 flags) {
    return syscall(__NR_landlock_restrict_self, ruleset_fd, flags);
}
#endif

#define ACCESS_FILE                                                                                \
    (LANDLOCK_ACCESS_FS_EXECUTE | LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_READ_FILE |   \
     LANDLOCK_ACCESS_FS_TRUNCATE | LANDLOCK_ACCESS_FS_IOCTL_DEV)

#define ACCESS_FS_ROUGHLY_READ                                                                     \
    (LANDLOCK_ACCESS_FS_EXECUTE | LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR)

#define ACCESS_FS_ROUGHLY_WRITE                                                                    \
    (LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_REMOVE_DIR |                               \
     LANDLOCK_ACCESS_FS_REMOVE_FILE | LANDLOCK_ACCESS_FS_MAKE_CHAR | LANDLOCK_ACCESS_FS_MAKE_DIR | \
     LANDLOCK_ACCESS_FS_MAKE_REG | LANDLOCK_ACCESS_FS_MAKE_SOCK | LANDLOCK_ACCESS_FS_MAKE_FIFO |   \
     LANDLOCK_ACCESS_FS_MAKE_BLOCK | LANDLOCK_ACCESS_FS_MAKE_SYM | LANDLOCK_ACCESS_FS_REFER |      \
     LANDLOCK_ACCESS_FS_TRUNCATE | LANDLOCK_ACCESS_FS_IOCTL_DEV)

static int add_path_rule(int ruleset_fd, const char *path, __u64 allowed_access) {
    struct stat                       statbuf;
    struct landlock_path_beneath_attr path_beneath = {
        .allowed_access = allowed_access,
    };

    path_beneath.parent_fd = open(path, O_PATH | O_CLOEXEC);
    if (path_beneath.parent_fd < 0) {
        return 0;
    }

    if (fstat(path_beneath.parent_fd, &statbuf)) {
        close(path_beneath.parent_fd);
        return 0;
    }

    if (!S_ISDIR(statbuf.st_mode)) {
        path_beneath.allowed_access &= ACCESS_FILE;
    }

    int ret = landlock_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &path_beneath, 0);
    close(path_beneath.parent_fd);
    return ret == 0 ? 0 : -1;
}

static int add_net_port_rule(int ruleset_fd, __u16 port, __u64 allowed_access) {
    struct landlock_net_port_attr net_port = {
        .allowed_access = allowed_access,
        .port           = port,
    };
    return landlock_add_rule(ruleset_fd, LANDLOCK_RULE_NET_PORT, &net_port, 0);
}

static void add_standard_net_rules(int ruleset_fd) {
    add_net_port_rule(ruleset_fd, 80, LANDLOCK_ACCESS_NET_CONNECT_TCP);
    add_net_port_rule(ruleset_fd, 443, LANDLOCK_ACCESS_NET_CONNECT_TCP);
    add_net_port_rule(ruleset_fd, 53, LANDLOCK_ACCESS_NET_CONNECT_TCP);
}

static int setup_seccomp(void) {
    if (prctl(PR_GET_SECCOMP) == -1 && errno == EINVAL) {
        fprintf(stderr, "[marathon-sandbox] Seccomp not available\n");
        return 0;
    }

    static const int blocked_syscalls[] = {
        __NR_ptrace,
        __NR_process_vm_readv,
        __NR_process_vm_writev,
#ifdef __NR_mount
        __NR_mount,
#endif
#ifdef __NR_umount2
        __NR_umount2,
#endif
#ifdef __NR_pivot_root
        __NR_pivot_root,
#endif
#ifdef __NR_reboot
        __NR_reboot,
#endif
#ifdef __NR_kexec_load
        __NR_kexec_load,
#endif
#ifdef __NR_kexec_file_load
        __NR_kexec_file_load,
#endif
#ifdef __NR_init_module
        __NR_init_module,
#endif
#ifdef __NR_finit_module
        __NR_finit_module,
#endif
#ifdef __NR_delete_module
        __NR_delete_module,
#endif
#ifdef __NR_acct
        __NR_acct,
#endif
#ifdef __NR_swapon
        __NR_swapon,
#endif
#ifdef __NR_swapoff
        __NR_swapoff,
#endif
#ifdef __NR_personality
        __NR_personality,
#endif
#ifdef __NR_lookup_dcookie
        __NR_lookup_dcookie,
#endif
#ifdef __NR_perf_event_open
        __NR_perf_event_open,
#endif
#ifdef __NR_add_key
        __NR_add_key,
#endif
#ifdef __NR_request_key
        __NR_request_key,
#endif
#ifdef __NR_keyctl
        __NR_keyctl,
#endif
#ifdef __NR_mbind
        __NR_mbind,
#endif
#ifdef __NR_userfaultfd
        __NR_userfaultfd,
#endif
#ifdef __NR_bpf
        __NR_bpf,
#endif
#ifdef __NR_open_by_handle_at
        __NR_open_by_handle_at,
#endif
    };

    const size_t        num_blocked = sizeof(blocked_syscalls) / sizeof(blocked_syscalls[0]);
    const size_t        filter_size = 2 + (2 * num_blocked) + 1;
    struct sock_filter *filter      = calloc(filter_size, sizeof(struct sock_filter));
    if (!filter) {
        perror("[marathon-sandbox] Failed to allocate seccomp filter");
        return -1;
    }

    size_t idx = 0;

    filter[idx++] =
        (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr));

#if defined(__x86_64__)
    filter[idx++] =
        (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch));
    filter[idx - 1] =
        (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr));
#endif

    for (size_t i = 0; i < num_blocked; i++) {
        filter[idx++] =
            (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, blocked_syscalls[i], 0, 1);
        filter[idx++] = (struct sock_filter)BPF_STMT(
            BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA));
    }

    filter[idx++] = (struct sock_filter)BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW);

    struct sock_fprog prog = {
        .len    = (unsigned short)idx,
        .filter = filter,
    };

    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) == -1) {
        perror("[marathon-sandbox] Failed to apply seccomp filter");
        free(filter);
        return -1;
    }

    free(filter);
    return 0;
}

static int setup_landlock(int has_network_permission, int has_storage_permission) {
    int abi = landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 0) {
        if (errno == ENOSYS || errno == EOPNOTSUPP) {
            fprintf(stderr, "[marathon-sandbox] Landlock not available\n");
            return 0;
        }
        return -1;
    }

    __u64 access_fs_rw  = ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE;
    __u64 access_net    = LANDLOCK_ACCESS_NET_BIND_TCP | LANDLOCK_ACCESS_NET_CONNECT_TCP;
    __u64 scoped        = LANDLOCK_SCOPE_SIGNAL;
    int   has_net_rules = 0;
    int   has_scoping   = 0;

    switch (abi) {
        case 1: access_fs_rw &= ~LANDLOCK_ACCESS_FS_REFER; __attribute__((fallthrough));
        case 2: access_fs_rw &= ~LANDLOCK_ACCESS_FS_TRUNCATE; __attribute__((fallthrough));
        case 3: access_net = 0; __attribute__((fallthrough));
        case 4: access_fs_rw &= ~LANDLOCK_ACCESS_FS_IOCTL_DEV; __attribute__((fallthrough));
        case 5: scoped = 0; __attribute__((fallthrough));
        default: break;
    }

    if (has_network_permission) {
        access_net = 0;
    }

    has_net_rules = (access_net != 0);
    has_scoping   = (scoped != 0);

    struct landlock_ruleset_attr ruleset_attr = {
        .handled_access_fs  = access_fs_rw,
        .handled_access_net = access_net,
        .scoped             = scoped,
    };

    int ruleset_fd = landlock_create_ruleset(&ruleset_attr, sizeof(ruleset_attr), 0);
    if (ruleset_fd < 0) {
        perror("[marathon-sandbox] Failed to create ruleset");
        return -1;
    }

    __u64 access_ro = ACCESS_FS_ROUGHLY_READ & access_fs_rw;
    __u64 access_rw = access_fs_rw;

    add_path_rule(ruleset_fd, "/usr", access_ro);
    add_path_rule(ruleset_fd, "/lib", access_ro);
    add_path_rule(ruleset_fd, "/lib64", access_ro);
    add_path_rule(ruleset_fd, "/bin", access_ro);
    add_path_rule(ruleset_fd, "/sbin", access_ro);
    add_path_rule(ruleset_fd, "/etc", access_ro);
    add_path_rule(ruleset_fd, "/opt", access_ro);
    add_path_rule(ruleset_fd, "/proc", access_ro);
    add_path_rule(ruleset_fd, "/sys", access_ro);
    add_path_rule(ruleset_fd, "/var/cache", access_ro);
    add_path_rule(ruleset_fd, "/var/lib", access_ro);

    add_path_rule(ruleset_fd, "/dev", access_rw);
    add_path_rule(ruleset_fd, "/dev/dri", access_rw);
    add_path_rule(ruleset_fd, "/dev/shm", access_rw);

    add_path_rule(ruleset_fd, "/run/dbus", access_rw);
    add_path_rule(ruleset_fd, "/run/user", access_rw);

    const char *xdg_runtime = getenv("XDG_RUNTIME_DIR");
    if (xdg_runtime) {
        add_path_rule(ruleset_fd, xdg_runtime, access_rw);
    }

    const char *home = getenv("HOME");
    if (home) {
        if (has_storage_permission) {
            add_path_rule(ruleset_fd, home, access_rw);
        } else {
            add_path_rule(ruleset_fd, home, access_ro);

            char config_path[PATH_MAX];
            snprintf(config_path, sizeof(config_path), "%s/.config", home);
            add_path_rule(ruleset_fd, config_path, access_rw);

            char cache_path[PATH_MAX];
            snprintf(cache_path, sizeof(cache_path), "%s/.cache", home);
            add_path_rule(ruleset_fd, cache_path, access_rw);

            char local_path[PATH_MAX];
            snprintf(local_path, sizeof(local_path), "%s/.local/share", home);
            add_path_rule(ruleset_fd, local_path, access_rw);
        }
    }

    add_path_rule(ruleset_fd, "/tmp", access_rw);
    add_path_rule(ruleset_fd, "/var/tmp", access_rw);

    if (has_net_rules) {
        add_standard_net_rules(ruleset_fd);
    }

    if (landlock_restrict_self(ruleset_fd, 0)) {
        perror("[marathon-sandbox] Failed to enforce ruleset");
        close(ruleset_fd);
        return -1;
    }

    close(ruleset_fd);

    syslog(LOG_INFO, "[SECURITY] Landlock sandbox active: abi=%d net=%d storage=%d scoped=%d", abi,
           has_network_permission, has_storage_permission, has_scoping);

    return 0;
}

static int env_has_permission(const char *env_var) {
    const char *val = getenv(env_var);
    return val && strcmp(val, "1") == 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        fprintf(stderr, "Environment variables:\n");
        fprintf(stderr, "  MARATHON_PERM_NETWORK=1  - Allow unrestricted network access\n");
        fprintf(stderr, "  MARATHON_PERM_STORAGE=1  - Allow full home directory write access\n");
        return 1;
    }

    openlog("marathon-sandbox", LOG_PID | LOG_NDELAY, LOG_AUTH);

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
        perror("[marathon-sandbox] Failed to set no_new_privs");
        return 1;
    }

    int has_network = env_has_permission("MARATHON_PERM_NETWORK");
    int has_storage = env_has_permission("MARATHON_PERM_STORAGE");

    if (setup_landlock(has_network, has_storage) < 0) {
        syslog(LOG_ERR, "[SECURITY] Landlock setup failed - Aborting");
        fprintf(stderr, "[marathon-sandbox] Error: Landlock setup failed. Aborting.\n");
        return 1;
    }

    if (setup_seccomp() < 0) {
        syslog(LOG_ERR, "[SECURITY] Seccomp setup failed - Aborting");
        fprintf(stderr, "[marathon-sandbox] Error: Seccomp setup failed. Aborting.\n");
        return 1;
    }

    closelog();

    execvp(argv[1], &argv[1]);
    perror("[marathon-sandbox] exec failed");
    return 127;
}
