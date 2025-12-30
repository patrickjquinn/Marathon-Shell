/*
 * marathon-sandbox - Lightweight Landlock-based sandboxing for Marathon apps
 * 
 * Usage: marathon-sandbox <command> [args...]
 * 
 * Applies filesystem restrictions using Landlock, then execs the command.
 * This provides security without the overhead of bubblewrap/systemd-run and
 * without breaking Wayland compositor surface sharing.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/landlock.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef landlock_create_ruleset
static inline int landlock_create_ruleset(
    const struct landlock_ruleset_attr *attr, size_t size, __u32 flags)
{
    return syscall(__NR_landlock_create_ruleset, attr, size, flags);
}
#endif

#ifndef landlock_add_rule
static inline int landlock_add_rule(int ruleset_fd, enum landlock_rule_type rule_type,
    const void *rule_attr, __u32 flags)
{
    return syscall(__NR_landlock_add_rule, ruleset_fd, rule_type, rule_attr, flags);
}
#endif

#ifndef landlock_restrict_self
static inline int landlock_restrict_self(int ruleset_fd, __u32 flags)
{
    return syscall(__NR_landlock_restrict_self, ruleset_fd, flags);
}
#endif

#define ACCESS_FS_ROUGHLY_READ ( \
    LANDLOCK_ACCESS_FS_EXECUTE | \
    LANDLOCK_ACCESS_FS_READ_FILE | \
    LANDLOCK_ACCESS_FS_READ_DIR)

#define ACCESS_FS_ROUGHLY_WRITE ( \
    LANDLOCK_ACCESS_FS_WRITE_FILE | \
    LANDLOCK_ACCESS_FS_REMOVE_DIR | \
    LANDLOCK_ACCESS_FS_REMOVE_FILE | \
    LANDLOCK_ACCESS_FS_MAKE_CHAR | \
    LANDLOCK_ACCESS_FS_MAKE_DIR | \
    LANDLOCK_ACCESS_FS_MAKE_REG | \
    LANDLOCK_ACCESS_FS_MAKE_SOCK | \
    LANDLOCK_ACCESS_FS_MAKE_FIFO | \
    LANDLOCK_ACCESS_FS_MAKE_BLOCK | \
    LANDLOCK_ACCESS_FS_MAKE_SYM | \
    LANDLOCK_ACCESS_FS_TRUNCATE)

static int add_path_rule(int ruleset_fd, const char *path, __u64 allowed_access)
{
    struct landlock_path_beneath_attr path_beneath = {
        .allowed_access = allowed_access,
    };
    
    path_beneath.parent_fd = open(path, O_PATH | O_CLOEXEC);
    if (path_beneath.parent_fd < 0) {
        return -1;
    }
    
    int ret = landlock_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &path_beneath, 0);
    close(path_beneath.parent_fd);
    return ret;
}

static int setup_landlock(void)
{
    int abi = landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 0) {
        if (errno == ENOSYS || errno == EOPNOTSUPP) {
            fprintf(stderr, "[marathon-sandbox] Landlock not available, running without sandbox\n");
            return 0;
        }
        return -1;
    }

    struct landlock_ruleset_attr ruleset_attr = {
        .handled_access_fs = ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE,
    };

    if (abi < 2) {
        ruleset_attr.handled_access_fs &= ~LANDLOCK_ACCESS_FS_REFER;
    }
    if (abi < 3) {
        ruleset_attr.handled_access_fs &= ~LANDLOCK_ACCESS_FS_TRUNCATE;
    }

    int ruleset_fd = landlock_create_ruleset(&ruleset_attr, sizeof(ruleset_attr), 0);
    if (ruleset_fd < 0) {
        perror("[marathon-sandbox] Failed to create ruleset");
        return -1;
    }

    /* Read-only access to system directories */
    add_path_rule(ruleset_fd, "/usr", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/lib", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/lib64", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/bin", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/sbin", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/etc", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/opt", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/proc", ACCESS_FS_ROUGHLY_READ);
    add_path_rule(ruleset_fd, "/sys", ACCESS_FS_ROUGHLY_READ);
    
    /* Device access - needed for GPU/DRI, audio, input */
    add_path_rule(ruleset_fd, "/dev", ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    add_path_rule(ruleset_fd, "/dev/dri", ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    add_path_rule(ruleset_fd, "/dev/shm", ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    
    /* Runtime directories - Wayland, D-Bus, PipeWire, etc. */
    add_path_rule(ruleset_fd, "/run", ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    add_path_rule(ruleset_fd, "/var", ACCESS_FS_ROUGHLY_READ);
    
    /* Read-write access to user directories */
    const char *home = getenv("HOME");
    if (home) {
        add_path_rule(ruleset_fd, home, ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    }
    
    /* XDG runtime dir (Wayland socket, etc.) */
    const char *xdg_runtime = getenv("XDG_RUNTIME_DIR");
    if (xdg_runtime) {
        add_path_rule(ruleset_fd, xdg_runtime, ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    }
    
    /* Temp directories */
    add_path_rule(ruleset_fd, "/tmp", ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);
    add_path_rule(ruleset_fd, "/var/tmp", ACCESS_FS_ROUGHLY_READ | ACCESS_FS_ROUGHLY_WRITE);

    /* Apply Landlock */
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
        perror("[marathon-sandbox] Failed to set no_new_privs");
        close(ruleset_fd);
        return -1;
    }
    
    if (landlock_restrict_self(ruleset_fd, 0)) {
        perror("[marathon-sandbox] Failed to enforce ruleset");
        close(ruleset_fd);
        return -1;
    }
    
    close(ruleset_fd);
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    if (setup_landlock() < 0) {
        fprintf(stderr, "[marathon-sandbox] Warning: continuing without sandbox\n");
    }

    execvp(argv[1], &argv[1]);
    perror("[marathon-sandbox] exec failed");
    return 127;
}
