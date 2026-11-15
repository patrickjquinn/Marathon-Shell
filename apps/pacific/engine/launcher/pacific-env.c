// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine deploy/runtime-common.sh)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// pacific-env: the runtime environment Pacific's engine needs, installed as
// /usr/libexec/pacific/pacific-env by shipwright-pacific-engine.
//
//   pacific-env <program> [args]   sets the environment, then execs program
//   pacific-env --print            prints it as `export NAME='value'` lines
//                                  (pacific-env.sh evaluates them)
//
// A program, not a shell script, because the browser starts inside Sailjail:
// sailjail refuses an Exec that is not an ELF binary, and Firejail's
// private-bin leaves no shell in the sandbox. The browser (an ELF in
// /usr/bin) re-execs itself through this when PACIFIC_ENV is not set.
//
// A cut-down port of Atlantic's deploy/runtime-common.sh (atlantic-engine
// a91f8ec), for Qt 6 and the Jolla Phone (Mali-G610); ../README.md lists each
// variable and why. Anything already set in the environment wins, so a single
// launch can override any of it. The WebProcess and NetworkProcess inherit
// all of it from the UI process.

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *prefix;
static int print_mode;

// Every variable this sets, in order, for --print.
static const char *touched[128];
static int ntouched;

static void touch(const char *name)
{
    for (int i = 0; i < ntouched; i++)
        if (strcmp(touched[i], name) == 0)
            return;
    if (ntouched < (int)(sizeof touched / sizeof *touched))
        touched[ntouched++] = name;
}

// NAME=value, always.
static void set(const char *name, const char *value)
{
    setenv(name, value, 1);
    touch(name);
}

// NAME=${NAME:-value}
static void dflt(const char *name, const char *value)
{
    const char *cur = getenv(name);
    if (!cur || !*cur)
        setenv(name, value, 1);
    touch(name);
}

// NAME="first${NAME:+:$NAME}"
static void prepend(const char *name, const char *first)
{
    const char *cur = getenv(name);
    char *v = NULL;
    if (cur && *cur) {
        if (asprintf(&v, "%s:%s", first, cur) < 0)
            exit(127);
    } else {
        v = strdup(first);
    }
    setenv(name, v, 1);
    free(v);
    touch(name);
}

static char *path(const char *rel)
{
    char *p = NULL;
    if (asprintf(&p, "%s/%s", prefix, rel) < 0)
        exit(127);
    return p;
}

static int file_contains(const char *file, const char *needle, int nocase)
{
    FILE *f = fopen(file, "r");
    char line[512];
    int found = 0;
    if (!f)
        return 0;
    while (!found && fgets(line, sizeof line, f))
        found = (nocase ? strcasestr(line, needle) : strstr(line, needle)) != NULL;
    fclose(f);
    return found;
}

// The libhybris Wayland EGL platform this one was built against
// (hybris/README.md): libhybris 0.0.5.58 (a1b75cb) of the Jolla Phone.
// FNV-1a 64 of the file, to know the build, not to authenticate it.
static int is_known_hybris_wayland_platform(const char *file)
{
    FILE *f = fopen(file, "rb");
    if (!f)
        return 0;
    unsigned long long hash = 0xcbf29ce484222325ULL;
    long size = 0;
    int c = 0;
    while ((c = getc(f)) != EOF) {
        hash = (hash ^ (unsigned char)c) * 0x100000001b3ULL;
        ++size;
    }
    fclose(f);
    return size == 68648 && hash == 0x5f6e6a1489bff071ULL;
}

static long mem_total_kb(void)
{
    FILE *f = fopen("/proc/meminfo", "r");
    char line[256];
    long kb = 0;
    if (!f)
        return 0;
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, "MemTotal:", 9) == 0) {
            kb = strtol(line + 9, NULL, 10);
            break;
        }
    }
    fclose(f);
    return kb;
}

static int is(const char *name, const char *value)
{
    const char *v = getenv(name);
    return v && strcmp(v, value) == 0;
}

static void apply(void)
{
    // --- Libraries: the engine's own and the compat set, private to this
    // process tree.
    char *lib = path("lib"), *compat = path("lib/compat"), *libs = NULL;
    if (asprintf(&libs, "%s:%s", lib, compat) < 0)
        exit(127);
    prepend("LD_LIBRARY_PATH", libs);
    free(libs);
    free(compat);

    // LD_PRELOAD shims (Atlantic's shims/compat): libegl-stubs.so forwards
    // the EGL 1.5 sync and image entry points to the KHR extensions
    // (PACIFIC_EGL_STUBS=0 turns it off); libsyncskip.so is inert unless
    // ATLANTIC_SKIP_SWAP_FENCE=1; libsigill_skip.so only with Patchmanager's
    // preload library, whose constructor traps; libpacific-eglshadercache.so
    // keeps the GPU driver's compiled shaders on disk (shims/eglshadercache.c,
    // PACIFIC_EGL_SHADER_CACHE).
    const char *no_preload = getenv("PACIFIC_NO_PRELOAD");
    if (!no_preload || !*no_preload) {
        char *shims = NULL, *s = NULL;
        const char *stubs = getenv("PACIFIC_EGL_STUBS");
        if (!stubs || !*stubs || strcmp(stubs, "1") == 0)
            shims = path("lib/shims/libegl-stubs.so");
        s = path("lib/shims/libsyncskip.so");
        {
            char *cache = path("lib/shims/libpacific-eglshadercache.so"), *t = NULL;
            if (asprintf(&t, "%s:%s", cache, s) < 0)
                exit(127);
            free(cache);
            free(s);
            s = t;
        }
        if (shims) {
            char *t = NULL;
            if (asprintf(&t, "%s:%s", shims, s) < 0)
                exit(127);
            free(shims);
            free(s);
            shims = t;
        } else {
            shims = s;
        }
        if (file_contains("/etc/ld.so.preload", "preloadpatchmanager", 0)) {
            char *sig = path("lib/shims/libsigill_skip.so"), *t = NULL;
            if (asprintf(&t, "%s:%s", sig, shims) < 0)
                exit(127);
            free(sig);
            free(shims);
            shims = t;
        }
        prepend("LD_PRELOAD", shims);
        free(shims);
    }
    // On by default on Adreno (kgsl): on the Xperia 10 II flinging went from
    // ~45 to ~49 frames/s and frames over 40 ms from 8% to 5% (19 October
    // 2026), as Atlantic found there. Off elsewhere until measured.
    dflt("ATLANTIC_SKIP_SWAP_FENCE", access("/dev/kgsl-3d0", F_OK) == 0 ? "1" : "0");

    // --- libhybris's Wayland EGL platform with cancelled buffers fixed
    // (hybris/README.md): its cancelBuffer() left a buffer queued and the next
    // eglSwapBuffers() aborted the WebProcess. Only in place of the exact
    // build it was made from; PACIFIC_HYBRIS_PLATFORM=0 keeps the system's.
    if (!is("PACIFIC_HYBRIS_PLATFORM", "0") && !getenv("HYBRIS_EGLPLATFORM_DIR")
        && is_known_hybris_wayland_platform("/usr/lib64/libhybris/eglplatform_wayland.so")) {
        char *dir = path("lib/hybris");
        set("HYBRIS_EGLPLATFORM_DIR", dir);
        free(dir);
    }

    // --- Sandbox: Sailjail confines the whole app; a namespace-free seccomp
    // filter in every WebProcess and NetworkProcess (Atlantic's patch).
    set("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1");
    dflt("WEBKIT_ENABLE_SECCOMP_FILTER", "1");
    char *bundle = path("lib/wpe-webkit-2.0/injected-bundle");
    dflt("WEBKIT_INJECTED_BUNDLE_PATH", bundle);
    free(bundle);

    // --- Spell checking: enchant's personal word list in the app's data
    // directory (writable under Sailjail), Pacific's dictionaries.
    char *dicts = path("share/hunspell"), *voikko = path("share/voikko");
    dflt("PACIFIC_DICTIONARY_DIR", dicts);
    dflt("VOIKKO_DICTIONARY_PATH", voikko);
    free(dicts);
    free(voikko);
    const char *enchant_dir = getenv("ENCHANT_CONFIG_DIR");
    if (!enchant_dir || !*enchant_dir) {
        const char *data = getenv("XDG_DATA_HOME"), *home = getenv("HOME");
        char *dir = NULL;
        int r = (data && *data) ? asprintf(&dir, "%s/org.shipwright/pacific/enchant", data)
                                : asprintf(&dir, "%s/.local/share/org.shipwright/pacific/enchant",
                                           home ? home : "");
        if (r < 0)
            exit(127);
        set("ENCHANT_CONFIG_DIR", dir);
        free(dir);
    } else {
        touch("ENCHANT_CONFIG_DIR");
    }

    // --- Qt: frames are EGLImages bound as GL textures.
    set("QSG_RHI_BACKEND", "opengl");
    dflt("QSG_RENDER_LOOP", "threaded");

    // --- GStreamer and audio.
    dflt("GST_PLUGIN_FEATURE_RANK", "droidvdec:300,droidvenc:0,vp9dec:310,vp8dec:310,droidadec:0");
    char *gst = path("lib/gstreamer-1.0");
    prepend("GST_PLUGIN_PATH", gst);
    free(gst);
    dflt("WEBKIT_GST_ENABLE_HLS_SUPPORT", "1");
    dflt("WEBKIT_GST_DISABLE_GL_SINK", "1");
    dflt("WEBKIT_GST_VIDEO_DECODING_LIMIT", "1920x1080@60");
    dflt("WEBKIT_GST_QUEUE_HIGH_WATERMARK", "0.05");
    dflt("WEBKIT_GST_RING_BUFFER_MAX_SIZE", "16777216");
    dflt("WEBKIT_GST_URIDECODEBIN_BUFFER_SIZE", "8388608");
    dflt("WPE_SHELL_MEDIA_DISK_CACHE_SIZE_BYTES", "67108864");
    dflt("WEBKIT_GST_MEDIA_ROLE", "x-maemo");
    dflt("WEBKIT_VOLUME_LOCKED", "1");
    dflt("WEBKIT_GST_AUDIO_SYSTEM_CLOCK", "1");
    char *pulse = path("share/pulse-client.conf");
    dflt("PULSE_CLIENTCONFIG", pulse);
    free(pulse);

    // --- JavaScriptCore: fewer JIT and GC threads than cores.
    dflt("JSC_numberOfFTLCompilerThreads", "2");
    dflt("JSC_numberOfDFGCompilerThreads", "2");
    dflt("JSC_numberOfBaselineCompilerThreads", "2");
    dflt("JSC_numberOfGCMarkers", "2");
    dflt("JSC_maxNumberOfWorklistThreads", "4");

    // --- Memory: 4000 MB base and a prewarmed WebProcess on 8 GB phones.
    if (mem_total_kb() >= 7340032 && !is("PACIFIC_MEMORY_TIER", "low")) {
        dflt("WEBKIT_MEMORY_BASE_THRESHOLD_MB", "4000");
        dflt("WEBKIT_PROCESS_PREWARM", "1");
        set("PACIFIC_MEMORY_TIER", "high");
    } else {
        dflt("WEBKIT_MEMORY_BASE_THRESHOLD_MB", "700");
        set("PACIFIC_MEMORY_TIER", "low");
    }
    dflt("WEBKIT_MEMORY_POLL_INTERVAL_MS", "3000");
    dflt("WEBKIT_TEXTURE_POOL_CAP_MB", "64");
    dflt("WEBKIT_URL_CACHE_DISK_CAPACITY_MB", "100");

    // --- GPU mode: mali when the Mali kernel driver is there.
    const char *mode = getenv("PACIFIC_GPU_MODE");
    if (!mode || !*mode) {
        if (access("/dev/mali0", F_OK) == 0 || file_contains("/proc/devices", "mali", 1)) {
            set("PACIFIC_GPU_MODE", "mali");
        } else {
            set("PACIFIC_GPU_MODE", "default");
            // Not a Mali phone (the Xperia 10 II and III are Adreno): the
            // tuning below was measured on the Jolla Phone's Mali only, so
            // say so in the journal. Behaviour is unchanged: WebKit's own
            // GPU painting defaults.
            fprintf(stderr, "pacific-env: no Mali GPU driver (/dev/mali0, \"mali\" in /proc/devices): "
                            "PACIFIC_GPU_MODE=default, WebKit's GPU painting defaults, not tuned or tested "
                            "on this GPU; set PACIFIC_GPU_MODE to choose another mode\n");
        }
    } else {
        touch("PACIFIC_GPU_MODE");
    }
    // mali: tiles are painted on the CPU by four threads (Skia's raster
    // backend) and the GPU only composites, as the phones that scrolled well
    // on one core did. GPU painting ran on the compositor thread, where a new
    // tile, a shader compile or a GPU allocation delayed the frame: flinging
    // OSNews on the Jolla Phone, 61 frames a second with a repeatable 75 ms
    // pause, against 72 and at worst 41 ms with CPU painting (Wikipedia 73
    // against 80), for about half a core more while the page moves.
    // Atlantic's low-resolution tiles draw wrongly with CPU painting and are
    // off. Tiles of 512 px (1 MB) upload a new tile in a frame where 1024 px
    // ones (4 MB) cost up to 42 ms. PACIFIC_GPU_MODE=mali-gpu paints on the
    // GPU as before.
    if (is("PACIFIC_GPU_MODE", "mali")) {
        set("WEBKIT_SKIA_ENABLE_CPU_RENDERING", "1");
        dflt("WEBKIT_SKIA_CPU_PAINTING_THREADS", "4");
        dflt("WEBKIT_LOWRES_TILE_SCALE", "1.0");
        dflt("WEBKIT_LAYERS_TILE_SIZE", "512");
    } else if (is("PACIFIC_GPU_MODE", "mali-gpu") || is("PACIFIC_GPU_MODE", "mali-sync")) {
        dflt("WEBKIT_RASTER_ON_COMPOSITOR_THREAD", "1");
        dflt("WEBKIT_SKIA_GPU_PAINTING_THREADS", "1");
        dflt("WEBKIT_LOWRES_TILE_SCALE", "1.0");
        // Atlantic's synchronous tile readback and per-frame glFinish are
        // off: on the Jolla Phone's Mali-G610 (EGL 1.5 with fences) they
        // capped scrolling at about 54 frames a second, against 60 to 70
        // without, with no rendering faults. PACIFIC_GPU_MODE=mali-sync (or
        // setting the variables) brings them back for older Mali drivers.
        if (is("PACIFIC_GPU_MODE", "mali-sync")) {
            dflt("WEBKIT_TILE_GPU_READBACK_SYNC", "1");
            dflt("WEBKIT_COMPOSITOR_GL_FINISH", "1");
        }
    } else if (is("PACIFIC_GPU_MODE", "cpu")) {
        set("WEBKIT_SKIA_ENABLE_CPU_RENDERING", "1");
        dflt("WEBKIT_SKIA_CPU_PAINTING_THREADS", "2");
    }

    // --- Scrolling and painting (Atlantic's patch-stack flags).
    dflt("WEBKIT_LOWRES_TILE_SCALE", "0.3");
    dflt("WEBKIT_LOWRES_SCROLL_SPEED", "120");
    dflt("WEBKIT_CHECKERBOARD_DURING_SCROLL", "800");
    dflt("WEBKIT_CHECKERBOARD_SETTLE_MS", "200");
    dflt("WEBKIT_COVER_AREA_MULTIPLIER", "2");
    dflt("WEBKIT_LOWRES_COST_TRIGGER", "1");
    dflt("WEBKIT_LOWRES_COST_BUDGET_MS", "11");
    dflt("WEBKIT_LOWRES_SHARPEN_VIEWPORT_ONLY", "1");
    dflt("WEBKIT_LOWRES_SHARPEN_MARGIN_PX", "512");
    dflt("WEBKIT_NO_FAKE_MOUSE_MOVE", "1");
    dflt("WEBKIT_FORCE_ASYNC_SCROLL", "1");
    dflt("WEBKIT_INDEPENDENT_SCROLL", "1");
    // Flings slow as iOS's do (its 0.998 a millisecond is a friction of 2):
    // upstream's 4 is tuned for desktop wheels, and a flick lost half its
    // speed in 200 ms and coasted 420 css px, where iOS goes about 750.
    // At 2 it goes 820 at the same frame rates (Jolla Phone, The Verge 90
    // fps with no gap over 38 ms).
    dflt("WEBKIT_KINETIC_DECEL_FRICTION", "2");
    dflt("WEBKIT_SKIP_ROOT_CUSTOMPROP_REPAINT", "1");
    dflt("WEBKIT_COMPOSITE_SKIP_LOCKED_LAYERS", "1");
    dflt("WEBKIT_TILE_UPLOAD_BUDGET_MB", "6");
    dflt("WEBKIT_TILE_UPLOAD_BUDGET_SCROLL_ONLY", "1");
    dflt("WEBKIT_TILE_UPLOAD_SCROLL_SETTLE_MS", "800");
    dflt("WEBKIT_TILE_UPLOAD_REST_BUDGET_MB", "16");
    dflt("WEBKIT_LOADING_TIMER_ALIGNMENT_MS", "50");
    dflt("WEBKIT_PARSER_TIME_LIMIT_MS", "100");
    dflt("WEBKIT_TOUCH_ACK_TIMEOUT_MS", "100");
    // Atlantic's 3 matched its 3x page zoom. Pacific renders at the real
    // device scale, so 3 made the scrollbar track 63 CSS px wide, and taps
    // on close buttons near the right edge pressed it (The Verge's notice).
    dflt("WEBKIT_SCROLLBAR_SCALE", "1");
    dflt("WEBKIT_SCROLLBAR_SPRITE", "1");
    dflt("WEBKIT_SCROLLBAR_SMOOTHING", "0.4");
    dflt("WEBKIT_SCROLLBAR_NO_HOVER", "1");
    dflt("WEBKIT_LAYERS_TILE_SIZE", "1024");

    // Applied: the browser does not re-exec through this again.
    set("PACIFIC_ENV", "1");
    free(lib);
}

static void print_quoted(const char *name, const char *value)
{
    printf("export %s='", name);
    for (const char *c = value; *c; c++) {
        if (*c == '\'')
            fputs("'\\''", stdout);
        else
            putchar(*c);
    }
    puts("'");
}

int main(int argc, char **argv)
{
    prefix = getenv("PACIFIC_ENGINE_PREFIX");
    if (!prefix || !*prefix)
        prefix = "/opt/pacific";
    if (argc > 1 && strcmp(argv[1], "--print") == 0)
        print_mode = 1;
    else if (argc < 2 || argv[1][0] == '-') {
        fprintf(stderr, "usage: pacific-env <program> [args] | pacific-env --print\n");
        return 2;
    }
    apply();
    // The shader cache file's base name, in the app's own cache directory
    // (~/.cache/<program>, writable under Sailjail); each process appends
    // its program's name. Empty turns the cache off.
    if (!print_mode && !getenv("PACIFIC_EGL_SHADER_CACHE")) {
        const char *home = getenv("HOME");
        const char *xdg = getenv("XDG_CACHE_HOME");
        const char *slash = strrchr(argv[1], '/');
        const char *program = slash ? slash + 1 : argv[1];
        char *dir = NULL, *file = NULL;
        if (xdg && *xdg ? asprintf(&dir, "%s/%s", xdg, program) >= 0
                        : home && *home && asprintf(&dir, "%s/.cache/%s", home, program) >= 0) {
            mkdir(dir, 0755);
            if (asprintf(&file, "%s/egl-shader-cache", dir) >= 0)
                set("PACIFIC_EGL_SHADER_CACHE", file);
            free(file);
            free(dir);
        }
    }
    if (print_mode) {
        for (int i = 0; i < ntouched; i++) {
            const char *v = getenv(touched[i]);
            if (v)
                print_quoted(touched[i], v);
        }
        return 0;
    }
    // Open files up to the hard limit, for the browser and the engine's
    // processes it starts. Every gralloc buffer costs a WebProcess about
    // three descriptors (a zero-copy tile, a frame buffer), and at Sailfish's
    // soft limit of 1024 a long scroll ran out: the next frame buffer could
    // not be imported ("failed to register buffer") and the page froze.
    struct rlimit files;
    if (getrlimit(RLIMIT_NOFILE, &files) == 0 && files.rlim_cur < files.rlim_max) {
        files.rlim_cur = files.rlim_max;
        setrlimit(RLIMIT_NOFILE, &files);
    }
    execvp(argv[1], argv + 1);
    fprintf(stderr, "pacific-env: cannot run %s: %m\n", argv[1]);
    return 127;
}
