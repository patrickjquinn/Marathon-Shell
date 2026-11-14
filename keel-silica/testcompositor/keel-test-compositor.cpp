// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel-test-compositor: a headless stand-in for Lipstick on a host, for
// Keel's direct mode (ADR-0016). It speaks the protocol path that native
// Sailfish Qt 5 apps and Keel apps with QT_WAYLAND_SHELL_INTEGRATION=wl-shell
// use with Lipstick:
//
//   wl_compositor v4, wl_shm, wl_output v2 (with transform), wl_seat v5
//   (pointer, keyboard, touch), wl_shell, and qt_surface_extension /
//   qt_extended_surface (window properties, onscreen_visibility, close).
//
// It has no xdg_wm_base, as Lipstick before 5.1 had none, so a client that
// does not use wl-shell fails to map a window here.
//
// What it mirrors from Lipstick (sailfishos/lipstick src/compositor,
// sailfishos/qtwayland 5.6 src/compositor; see keel/README.md):
//   * the window category comes from the CATEGORY generic property, decoded
//     from a QDataStream QVariant (lipstickcompositor.cpp surfaceCategory());
//   * content orientation is wl_surface.set_buffer_transform
//     (qwlsurface.cpp Surface::surface_set_buffer_transform);
//   * device orientation is the wl_output transform
//     (QWaylandCompositor::setScreenOrientation);
//   * a new non-cover window gets keyboard focus (activation);
//   * set_fullscreen / set_maximized get a configure to the screen size.
//
// It writes one JSON object per line to --log (default stderr) for every
// event a test or a measurement needs, with CLOCK_MONOTONIC timestamps in
// seconds ("t"), so a driver can compare them with its own monotonic clock.
// It reads commands from stdin, one per line:
//
//   transform <0|90|180|270>       output transform (device rotation)
//   visibility <surface> <n>       qt_extended_surface.onscreen_visibility
//   close <surface>                qt_extended_surface.close
//   throttle <surface> <0|1>       withhold frame callbacks (hidden window)
//   focus <surface>                keyboard focus
//   press <surface> <x> <y>        pointer button down at x,y (surface coords)
//   release <surface>              pointer button up
//   quit
//
// Surfaces are numbered from 1 in creation order ("surface" in the log).

#include <wayland-server.h>

#include "surface-extension-server-protocol.h"

#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

namespace {

FILE *g_log = stderr;
int g_width = 540;
int g_height = 960;
int g_transform = WL_OUTPUT_TRANSFORM_NORMAL;
wl_display *g_display = nullptr;

double now()
{
    timespec ts {};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<double>(ts.tv_sec) + static_cast<double>(ts.tv_nsec) / 1e9;
}

uint32_t nowMs()
{
    return static_cast<uint32_t>(std::llround(now() * 1000.0));
}

std::string jsonEscape(const std::string &s)
{
    std::string out;
    for (unsigned char c : s) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof buf, "\\u%04x", c);
                out += buf;
            } else {
                out += static_cast<char>(c);
            }
        }
    }
    return out;
}

// One log line: {"t":..., "ev":"<ev>", <fields>}
void logEvent(const char *ev, const std::string &fields = std::string())
{
    std::fprintf(g_log, "{\"t\":%.6f,\"ev\":\"%s\"%s%s}\n", now(), ev,
                 fields.empty() ? "" : ",", fields.c_str());
    std::fflush(g_log);
}

std::string str(const char *key, const std::string &value)
{
    return std::string("\"") + key + "\":\"" + jsonEscape(value) + "\"";
}

std::string num(const char *key, long long value)
{
    return std::string("\"") + key + "\":" + std::to_string(value);
}

// ---- QDataStream QVariant decoding (big endian) --------------------------
//
// Lipstick decodes generic properties with Qt 5.6's QDataStream. Type ids
// below 0x1000 that Qt 5 and Qt 6 share are decoded; Qt 6's GUI types
// (0x1000 and up, e.g. QRegion 0x1008) have different ids in Qt 5, so a Qt 5.6
// compositor cannot read them: they are reported "lipstickCompatible":false.

struct Reader {
    const uint8_t *p = nullptr;
    size_t n = 0;
    size_t pos = 0;
    bool ok = true;
    bool need(size_t k)
    {
        if (pos + k > n)
            ok = false;
        return ok;
    }
    uint32_t u32()
    {
        if (!need(4))
            return 0;
        uint32_t v = (static_cast<uint32_t>(p[pos]) << 24) | (static_cast<uint32_t>(p[pos + 1]) << 16)
                | (static_cast<uint32_t>(p[pos + 2]) << 8) | static_cast<uint32_t>(p[pos + 3]);
        pos += 4;
        return v;
    }
    uint8_t u8()
    {
        if (!need(1))
            return 0;
        return p[pos++];
    }
    std::string qstring()
    {
        const uint32_t bytes = u32();
        if (!ok || bytes == 0xffffffffu)
            return std::string();
        if (!need(bytes))
            return std::string();
        std::string out;
        for (size_t i = 0; i + 1 < bytes; i += 2) {
            const uint32_t c = (static_cast<uint32_t>(p[pos + i]) << 8) | p[pos + i + 1];
            // BMP only; enough for property values in tests.
            if (c < 0x80) {
                out += static_cast<char>(c);
            } else if (c < 0x800) {
                out += static_cast<char>(0xc0 | (c >> 6));
                out += static_cast<char>(0x80 | (c & 0x3f));
            } else {
                out += static_cast<char>(0xe0 | (c >> 12));
                out += static_cast<char>(0x80 | ((c >> 6) & 0x3f));
                out += static_cast<char>(0x80 | (c & 0x3f));
            }
        }
        pos += bytes;
        return out;
    }
};

// Returns a JSON value for the variant; sets typeId and compat.
std::string decodeVariant(Reader &r, uint32_t *typeIdOut, bool *compat)
{
    const uint32_t type = r.u32();
    if (typeIdOut)
        *typeIdOut = type;
    r.u8(); // isNull
    if (!r.ok)
        return "null";
    switch (type) {
    case 1: return r.u8() ? "true" : "false";
    case 2: return std::to_string(static_cast<int32_t>(r.u32()));
    case 3: return std::to_string(r.u32());
    case 10: return "\"" + jsonEscape(r.qstring()) + "\"";
    case 11: {
        const uint32_t count = r.u32();
        std::string out = "[";
        for (uint32_t i = 0; r.ok && i < count && i < 1024; ++i)
            out += (i ? ",\"" : "\"") + jsonEscape(r.qstring()) + "\"";
        return out + "]";
    }
    case 9: {
        const uint32_t count = r.u32();
        std::string out = "[";
        for (uint32_t i = 0; r.ok && i < count && i < 1024; ++i)
            out += (i ? "," : "") + decodeVariant(r, nullptr, compat);
        return out + "]";
    }
    default:
        if (type >= 0x1000 && compat)
            *compat = false;
        return "\"<type " + std::to_string(type) + ">\"";
    }
}

// ---- State --------------------------------------------------------------------

struct Surface {
    uint32_t id = 0;
    wl_resource *resource = nullptr;
    pid_t pid = 0;
    wl_resource *pendingBuffer = nullptr;
    bool bufferAttached = false;
    bool mapped = false;
    int width = -1;
    int height = -1;
    int bufferTransform = 0;
    unsigned commits = 0;
    unsigned bufferCommits = 0;
    std::vector<wl_resource *> pendingFrames;
    std::vector<wl_resource *> frames;
    wl_resource *shellSurface = nullptr;
    wl_resource *extended = nullptr;
    std::string category;
    bool throttled = false;
};

std::map<uint32_t, Surface *> g_surfaces;
uint32_t g_nextSurfaceId = 1;
std::vector<wl_resource *> g_outputs;
std::vector<wl_resource *> g_pointers;
std::vector<wl_resource *> g_keyboards;
std::vector<wl_resource *> g_touches;
Surface *g_pointerFocus = nullptr;
Surface *g_keyboardFocus = nullptr;
uint32_t g_serial = 1;

Surface *surfaceFromResource(wl_resource *r)
{
    return r ? static_cast<Surface *>(wl_resource_get_user_data(r)) : nullptr;
}

Surface *surfaceById(uint32_t id)
{
    auto it = g_surfaces.find(id);
    return it == g_surfaces.end() ? nullptr : it->second;
}

std::string surfaceFields(const Surface *s)
{
    return num("surface", s->id) + "," + num("pid", s->pid);
}

template <typename F>
void forClientResources(const std::vector<wl_resource *> &list, wl_client *client, F f)
{
    for (wl_resource *r : list) {
        if (wl_resource_get_client(r) == client)
            f(r);
    }
}

void setKeyboardFocus(Surface *s)
{
    if (s == g_keyboardFocus)
        return;
    wl_array keys {};
    wl_array_init(&keys);
    if (g_keyboardFocus) {
        forClientResources(g_keyboards, wl_resource_get_client(g_keyboardFocus->resource),
                           [](wl_resource *k) {
            wl_keyboard_send_leave(k, g_serial++, g_keyboardFocus->resource);
        });
    }
    g_keyboardFocus = s;
    if (s) {
        forClientResources(g_keyboards, wl_resource_get_client(s->resource), [&](wl_resource *k) {
            wl_keyboard_send_enter(k, g_serial++, s->resource, &keys);
            wl_keyboard_send_modifiers(k, g_serial++, 0, 0, 0, 0);
        });
        logEvent("focus", surfaceFields(s));
    }
    wl_array_release(&keys);
}

void removeResource(std::vector<wl_resource *> &list, wl_resource *r)
{
    for (auto it = list.begin(); it != list.end(); ++it) {
        if (*it == r) {
            list.erase(it);
            return;
        }
    }
}

// ---- wl_region ------------------------------------------------------------

void resourceDestroy(wl_client *, wl_resource *r)
{
    wl_resource_destroy(r);
}

void regionAdd(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
void regionSubtract(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
const struct wl_region_interface kRegionImpl = { resourceDestroy, regionAdd, regionSubtract };

// ---- wl_surface -------------------------------------------------------------

void surfaceAttach(wl_client *, wl_resource *r, wl_resource *buffer, int32_t, int32_t)
{
    Surface *s = surfaceFromResource(r);
    s->pendingBuffer = buffer;
    s->bufferAttached = true;
}

void surfaceDamage(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}

void frameResourceDestroyed(wl_resource *r)
{
    for (auto &kv : g_surfaces) {
        removeResource(kv.second->pendingFrames, r);
        removeResource(kv.second->frames, r);
    }
}

void surfaceFrame(wl_client *client, wl_resource *r, uint32_t callback)
{
    Surface *s = surfaceFromResource(r);
    wl_resource *cb = wl_resource_create(client, &wl_callback_interface, 1, callback);
    wl_resource_set_implementation(cb, nullptr, nullptr, frameResourceDestroyed);
    s->pendingFrames.push_back(cb);
}

void surfaceSetOpaqueRegion(wl_client *, wl_resource *, wl_resource *) {}
void surfaceSetInputRegion(wl_client *, wl_resource *, wl_resource *) {}

void surfaceCommit(wl_client *, wl_resource *r)
{
    Surface *s = surfaceFromResource(r);
    ++s->commits;
    s->frames.insert(s->frames.end(), s->pendingFrames.begin(), s->pendingFrames.end());
    s->pendingFrames.clear();
    if (!s->bufferAttached)
        return;
    s->bufferAttached = false;
    wl_resource *buffer = s->pendingBuffer;
    s->pendingBuffer = nullptr;
    if (!buffer) {
        if (s->mapped)
            logEvent("unmap", surfaceFields(s));
        s->mapped = false;
        return;
    }
    int w = -1;
    int h = -1;
    bool drawn = false;
    if (wl_shm_buffer *shm = wl_shm_buffer_get(buffer)) {
        w = wl_shm_buffer_get_width(shm);
        h = wl_shm_buffer_get_height(shm);
        // Did the client draw anything (any non-zero pixel)?
        wl_shm_buffer_begin_access(shm);
        const auto *data = static_cast<const uint8_t *>(wl_shm_buffer_get_data(shm));
        const size_t bytes = static_cast<size_t>(wl_shm_buffer_get_stride(shm)) * static_cast<size_t>(h);
        constexpr size_t kStep = 388; // every 97th pixel of 4 bytes
        for (size_t i = 0; data && i < bytes; i += kStep) {
            if (data[i] || data[i + 1] || data[i + 2] || data[i + 3]) {
                drawn = true;
                break;
            }
        }
        wl_shm_buffer_end_access(shm);
    }
    ++s->bufferCommits;
    const bool first = !s->mapped;
    s->mapped = true;
    s->width = w;
    s->height = h;
    logEvent("buffer", surfaceFields(s) + "," + num("width", w) + "," + num("height", h) + ","
             + num("n", s->bufferCommits) + ",\"first\":" + (first ? "true" : "false")
             + ",\"drawn\":" + (drawn ? "true" : "false") + "," + str("category", s->category));
    // The content is not kept: release at once so the client can reuse it.
    wl_buffer_send_release(buffer);
    // Lipstick activates a newly mapped application window.
    if (first && s->shellSurface && s->category.empty() && !g_keyboardFocus)
        setKeyboardFocus(s);
}

void surfaceSetBufferTransform(wl_client *, wl_resource *r, int32_t transform)
{
    Surface *s = surfaceFromResource(r);
    if (transform == s->bufferTransform)
        return;
    s->bufferTransform = transform;
    static const int degrees[] = { 0, 90, 180, 270, 0, 90, 180, 270 };
    logEvent("buffer_transform", surfaceFields(s) + "," + num("transform", transform) + ","
             + num("degrees", transform >= 0 && transform < 8 ? degrees[transform] : -1));
}

void surfaceSetBufferScale(wl_client *, wl_resource *, int32_t) {}
void surfaceDamageBuffer(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}

const struct wl_surface_interface kSurfaceImpl = {
    resourceDestroy, surfaceAttach, surfaceDamage, surfaceFrame, surfaceSetOpaqueRegion,
    surfaceSetInputRegion, surfaceCommit, surfaceSetBufferTransform, surfaceSetBufferScale,
    surfaceDamageBuffer,
#if defined(WL_SURFACE_OFFSET_SINCE_VERSION)
    nullptr,
#endif
};

void surfaceDestroyed(wl_resource *r)
{
    Surface *s = surfaceFromResource(r);
    if (!s)
        return;
    logEvent("surface_destroyed", surfaceFields(s));
    if (g_keyboardFocus == s)
        g_keyboardFocus = nullptr;
    if (g_pointerFocus == s)
        g_pointerFocus = nullptr;
    for (wl_resource *cb : s->frames)
        wl_resource_set_destructor(cb, nullptr);
    for (wl_resource *cb : s->pendingFrames)
        wl_resource_set_destructor(cb, nullptr);
    if (s->shellSurface)
        wl_resource_set_user_data(s->shellSurface, nullptr);
    if (s->extended)
        wl_resource_set_user_data(s->extended, nullptr);
    g_surfaces.erase(s->id);
    delete s;
}

// ---- wl_compositor ------------------------------------------------------------

void compositorCreateSurface(wl_client *client, wl_resource *r, uint32_t id)
{
    auto *s = new Surface;
    s->id = g_nextSurfaceId++;
    s->resource = wl_resource_create(client, &wl_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(s->resource, &kSurfaceImpl, s, surfaceDestroyed);
    uid_t uid = 0;
    gid_t gid = 0;
    wl_client_get_credentials(client, &s->pid, &uid, &gid);
    g_surfaces[s->id] = s;
    logEvent("surface", surfaceFields(s));
}

void compositorCreateRegion(wl_client *client, wl_resource *r, uint32_t id)
{
    wl_resource *region = wl_resource_create(client, &wl_region_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(region, &kRegionImpl, nullptr, nullptr);
}

const struct wl_compositor_interface kCompositorImpl = { compositorCreateSurface, compositorCreateRegion };

void bindCompositor(wl_client *client, void *, uint32_t version, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_compositor_interface, static_cast<int>(std::min<uint32_t>(version, 4)), id);
    wl_resource_set_implementation(r, &kCompositorImpl, nullptr, nullptr);
}

// ---- wl_output ------------------------------------------------------------------

void sendOutput(wl_resource *r)
{
    wl_output_send_geometry(r, 0, 0, 62, 110, WL_OUTPUT_SUBPIXEL_UNKNOWN, "keel", "test-lipstick",
                            g_transform);
    wl_output_send_mode(r, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED, g_width, g_height, 60000);
    if (wl_resource_get_version(r) >= 2) {
        wl_output_send_scale(r, 1);
        wl_output_send_done(r);
    }
}

void outputRelease(wl_client *, wl_resource *r)
{
    wl_resource_destroy(r);
}
const struct wl_output_interface kOutputImpl = { outputRelease };

void outputDestroyed(wl_resource *r)
{
    removeResource(g_outputs, r);
}

void bindOutput(wl_client *client, void *, uint32_t version, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_output_interface, static_cast<int>(std::min<uint32_t>(version, 2)), id);
    wl_resource_set_implementation(r, &kOutputImpl, nullptr, outputDestroyed);
    g_outputs.push_back(r);
    sendOutput(r);
}

// ---- wl_seat --------------------------------------------------------------------

void pointerSetCursor(wl_client *, wl_resource *, uint32_t, wl_resource *, int32_t, int32_t) {}
const struct wl_pointer_interface kPointerImpl = { pointerSetCursor, resourceDestroy };
const struct wl_keyboard_interface kKeyboardImpl = { resourceDestroy };
const struct wl_touch_interface kTouchImpl = { resourceDestroy };

void pointerDestroyed(wl_resource *r) { removeResource(g_pointers, r); }
void keyboardDestroyed(wl_resource *r) { removeResource(g_keyboards, r); }
void touchDestroyed(wl_resource *r) { removeResource(g_touches, r); }

void seatGetPointer(wl_client *client, wl_resource *seat, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_pointer_interface, wl_resource_get_version(seat), id);
    wl_resource_set_implementation(r, &kPointerImpl, nullptr, pointerDestroyed);
    g_pointers.push_back(r);
}

void seatGetKeyboard(wl_client *client, wl_resource *seat, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_keyboard_interface, wl_resource_get_version(seat), id);
    wl_resource_set_implementation(r, &kKeyboardImpl, nullptr, keyboardDestroyed);
    g_keyboards.push_back(r);
    // No keymap: focus and activation are what the tests need.
    const int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
    wl_keyboard_send_keymap(r, WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP, fd, 0);
    close(fd);
    if (wl_resource_get_version(r) >= 4)
        wl_keyboard_send_repeat_info(r, 25, 600);
}

void seatGetTouch(wl_client *client, wl_resource *seat, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_touch_interface, wl_resource_get_version(seat), id);
    wl_resource_set_implementation(r, &kTouchImpl, nullptr, touchDestroyed);
    g_touches.push_back(r);
}

const struct wl_seat_interface kSeatImpl = { seatGetPointer, seatGetKeyboard, seatGetTouch, resourceDestroy };

void bindSeat(wl_client *client, void *, uint32_t version, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_seat_interface, static_cast<int>(std::min<uint32_t>(version, 5)), id);
    wl_resource_set_implementation(r, &kSeatImpl, nullptr, nullptr);
    wl_seat_send_capabilities(r, WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD
                                         | WL_SEAT_CAPABILITY_TOUCH);
    if (wl_resource_get_version(r) >= 2)
        wl_seat_send_name(r, "seat0");
}

// ---- wl_shell / wl_shell_surface ---------------------------------------------------

Surface *shellSurfaceOwner(wl_resource *r)
{
    return static_cast<Surface *>(wl_resource_get_user_data(r));
}

void shellPong(wl_client *, wl_resource *, uint32_t) {}
void shellMove(wl_client *, wl_resource *, wl_resource *, uint32_t) {}
void shellResize(wl_client *, wl_resource *, wl_resource *, uint32_t, uint32_t) {}

void shellRole(wl_resource *r, const char *role)
{
    if (Surface *s = shellSurfaceOwner(r))
        logEvent("shell_state", surfaceFields(s) + "," + str("state", role));
}

void shellSetToplevel(wl_client *, wl_resource *r)
{
    shellRole(r, "toplevel");
}

void shellSetTransient(wl_client *, wl_resource *r, wl_resource *, int32_t, int32_t, uint32_t)
{
    shellRole(r, "transient");
}

void shellSetFullscreen(wl_client *, wl_resource *r, uint32_t, uint32_t, wl_resource *)
{
    shellRole(r, "fullscreen");
    wl_shell_surface_send_configure(r, WL_SHELL_SURFACE_RESIZE_NONE, g_width, g_height);
}

void shellSetPopup(wl_client *, wl_resource *r, wl_resource *, uint32_t, wl_resource *, int32_t,
                   int32_t, uint32_t)
{
    shellRole(r, "popup");
}

void shellSetMaximized(wl_client *, wl_resource *r, wl_resource *)
{
    shellRole(r, "maximized");
    wl_shell_surface_send_configure(r, WL_SHELL_SURFACE_RESIZE_NONE, g_width, g_height);
}

void shellSetTitle(wl_client *, wl_resource *r, const char *title)
{
    if (Surface *s = shellSurfaceOwner(r))
        logEvent("title", surfaceFields(s) + "," + str("title", title ? title : ""));
}

void shellSetClass(wl_client *, wl_resource *r, const char *cls)
{
    if (Surface *s = shellSurfaceOwner(r))
        logEvent("class", surfaceFields(s) + "," + str("class", cls ? cls : ""));
}

const struct wl_shell_surface_interface kShellSurfaceImpl = {
    shellPong, shellMove, shellResize, shellSetToplevel, shellSetTransient, shellSetFullscreen,
    shellSetPopup, shellSetMaximized, shellSetTitle, shellSetClass,
};

void shellGetShellSurface(wl_client *client, wl_resource *r, uint32_t id, wl_resource *surfaceRes)
{
    Surface *s = surfaceFromResource(surfaceRes);
    wl_resource *ss = wl_resource_create(client, &wl_shell_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(ss, &kShellSurfaceImpl, s, [](wl_resource *res) {
        if (Surface *owner = shellSurfaceOwner(res))
            owner->shellSurface = nullptr;
    });
    s->shellSurface = ss;
    logEvent("shell_surface", surfaceFields(s));
}

const struct wl_shell_interface kShellImpl = { shellGetShellSurface };

void bindShell(wl_client *client, void *, uint32_t, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &wl_shell_interface, 1, id);
    wl_resource_set_implementation(r, &kShellImpl, nullptr, nullptr);
}

// ---- qt_surface_extension / qt_extended_surface ------------------------------------

void extUpdateGenericProperty(wl_client *, wl_resource *r, const char *name, wl_array *value)
{
    auto *s = static_cast<Surface *>(wl_resource_get_user_data(r));
    if (!s)
        return;
    Reader reader;
    reader.p = static_cast<const uint8_t *>(value->data);
    reader.n = value->size;
    uint32_t type = 0;
    bool compat = true;
    const std::string json = decodeVariant(reader, &type, &compat);
    if (!reader.ok)
        compat = false;
    const std::string key = name ? name : "";
    if (key == "CATEGORY" && type == 10) {
        // Lipstick: surfaceCategory() reads it as a string.
        Reader again;
        again.p = static_cast<const uint8_t *>(value->data);
        again.n = value->size;
        again.u32();
        again.u8();
        s->category = again.qstring();
    }
    logEvent("property", surfaceFields(s) + "," + str("name", key) + ",\"value\":" + json + ","
             + num("type", type) + ",\"lipstickCompatible\":" + (compat ? "true" : "false") + ","
             + "\"mapped\":" + (s->mapped ? "true" : "false"));
}

void extSetContentOrientationMask(wl_client *, wl_resource *r, int32_t mask)
{
    if (auto *s = static_cast<Surface *>(wl_resource_get_user_data(r)))
        logEvent("content_orientation_mask", surfaceFields(s) + "," + num("mask", mask));
}

void extSetWindowFlags(wl_client *, wl_resource *r, int32_t flags)
{
    if (auto *s = static_cast<Surface *>(wl_resource_get_user_data(r)))
        logEvent("window_flags", surfaceFields(s) + "," + num("flags", flags));
}

void extRaise(wl_client *, wl_resource *r)
{
    if (auto *s = static_cast<Surface *>(wl_resource_get_user_data(r)))
        logEvent("raise", surfaceFields(s));
}

void extLower(wl_client *, wl_resource *r)
{
    if (auto *s = static_cast<Surface *>(wl_resource_get_user_data(r)))
        logEvent("lower", surfaceFields(s));
}

const struct qt_extended_surface_interface kExtendedImpl = {
    extUpdateGenericProperty, extSetContentOrientationMask, extSetWindowFlags, extRaise, extLower,
};

void extGetExtendedSurface(wl_client *client, wl_resource *r, uint32_t id, wl_resource *surfaceRes)
{
    Surface *s = surfaceFromResource(surfaceRes);
    wl_resource *ext = wl_resource_create(client, &qt_extended_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(ext, &kExtendedImpl, s, [](wl_resource *res) {
        if (auto *owner = static_cast<Surface *>(wl_resource_get_user_data(res)))
            owner->extended = nullptr;
    });
    s->extended = ext;
    logEvent("extended_surface", surfaceFields(s));
}

const struct qt_surface_extension_interface kSurfaceExtensionImpl = { extGetExtendedSurface };

void bindSurfaceExtension(wl_client *client, void *, uint32_t, uint32_t id)
{
    wl_resource *r = wl_resource_create(client, &qt_surface_extension_interface, 1, id);
    wl_resource_set_implementation(r, &kSurfaceExtensionImpl, nullptr, nullptr);
}

// ---- Frame callbacks ---------------------------------------------------------------

wl_event_source *g_frameTimer = nullptr;

int onFrameTimer(void *)
{
    const uint32_t ms = nowMs();
    for (auto &kv : g_surfaces) {
        Surface *s = kv.second;
        if (s->throttled || s->frames.empty())
            continue;
        std::vector<wl_resource *> done;
        done.swap(s->frames);
        for (wl_resource *cb : done) {
            wl_resource_set_destructor(cb, nullptr);
            wl_callback_send_done(cb, ms);
            wl_resource_destroy(cb);
        }
    }
    wl_event_source_timer_update(g_frameTimer, 16);
    return 0;
}

// ---- Commands ------------------------------------------------------------------------

void pointerTo(Surface *s, double x, double y)
{
    wl_client *client = wl_resource_get_client(s->resource);
    if (g_pointerFocus != s) {
        if (g_pointerFocus) {
            forClientResources(g_pointers, wl_resource_get_client(g_pointerFocus->resource),
                               [](wl_resource *p) {
                wl_pointer_send_leave(p, g_serial++, g_pointerFocus->resource);
                if (wl_resource_get_version(p) >= 5)
                    wl_pointer_send_frame(p);
            });
        }
        g_pointerFocus = s;
        forClientResources(g_pointers, client, [&](wl_resource *p) {
            wl_pointer_send_enter(p, g_serial++, s->resource, wl_fixed_from_double(x), wl_fixed_from_double(y));
            if (wl_resource_get_version(p) >= 5)
                wl_pointer_send_frame(p);
        });
    }
    forClientResources(g_pointers, client, [&](wl_resource *p) {
        wl_pointer_send_motion(p, nowMs(), wl_fixed_from_double(x), wl_fixed_from_double(y));
        if (wl_resource_get_version(p) >= 5)
            wl_pointer_send_frame(p);
    });
}

void pointerButton(Surface *s, bool down)
{
    constexpr uint32_t kBtnLeft = 0x110;
    forClientResources(g_pointers, wl_resource_get_client(s->resource), [&](wl_resource *p) {
        wl_pointer_send_button(p, g_serial++, nowMs(), kBtnLeft,
                               down ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
        if (wl_resource_get_version(p) >= 5)
            wl_pointer_send_frame(p);
    });
}

bool g_quit = false;

void runCommand(const std::string &line)
{
    std::istringstream in(line);
    std::string c;
    if (!(in >> c))
        return;
    // Reads the command's arguments in order; false if any is missing or
    // malformed (the line is then reported as a bad command).
    const auto read = [&in](auto &...values) { return static_cast<bool>((in >> ... >> values)); };
    unsigned id = 0;
    int a = 0;
    double x = 0;
    double y = 0;
    if (c == "quit") {
        g_quit = true;
        wl_display_terminate(g_display);
    } else if (c == "transform" && read(a)) {
        g_transform = a == 90 ? WL_OUTPUT_TRANSFORM_90 : a == 180 ? WL_OUTPUT_TRANSFORM_180
                    : a == 270 ? WL_OUTPUT_TRANSFORM_270 : WL_OUTPUT_TRANSFORM_NORMAL;
        for (wl_resource *r : g_outputs)
            sendOutput(r);
        logEvent("output_transform", num("degrees", a) + "," + num("transform", g_transform));
    } else if (c == "visibility" && read(id, a)) {
        Surface *s = surfaceById(id);
        if (s && s->extended) {
            qt_extended_surface_send_onscreen_visibility(s->extended, a);
            logEvent("sent_visibility", surfaceFields(s) + "," + num("visibility", a));
        }
    } else if (c == "close" && read(id)) {
        Surface *s = surfaceById(id);
        if (s && s->extended) {
            qt_extended_surface_send_close(s->extended);
            logEvent("sent_close", surfaceFields(s));
        }
    } else if (c == "throttle" && read(id, a)) {
        if (Surface *s = surfaceById(id))
            s->throttled = a != 0;
    } else if (c == "focus" && read(id)) {
        setKeyboardFocus(surfaceById(id));
    } else if (c == "press" && read(id, x, y)) {
        if (Surface *s = surfaceById(id)) {
            pointerTo(s, x, y);
            logEvent("input", surfaceFields(s) + "," + str("kind", "press"));
            pointerButton(s, true);
        }
    } else if (c == "release" && read(id)) {
        if (Surface *s = surfaceById(id)) {
            logEvent("input", surfaceFields(s) + "," + str("kind", "release"));
            pointerButton(s, false);
        }
    } else {
        logEvent("bad_command", str("line", line));
    }
}

std::string g_stdinBuffer;

int onStdin(int fd, uint32_t mask, void *)
{
    char buf[512];
    const ssize_t n = (mask & WL_EVENT_READABLE) ? read(fd, buf, sizeof buf) : 0;
    if (n <= 0) {
        // The driver went away: stop.
        wl_display_terminate(g_display);
        return 0;
    }
    g_stdinBuffer.append(buf, static_cast<size_t>(n));
    size_t nl = 0;
    while ((nl = g_stdinBuffer.find('\n')) != std::string::npos) {
        const std::string line = g_stdinBuffer.substr(0, nl);
        g_stdinBuffer.erase(0, nl + 1);
        runCommand(line);
    }
    wl_display_flush_clients(g_display);
    return 0;
}

void usage()
{
    std::fprintf(stderr,
                 "usage: keel-test-compositor [--socket NAME] [--log FILE] [--size WxH]\n"
                 "Headless Lipstick stand-in (wl_shell + qt_surface_extension); see the source.\n");
}

} // namespace

int main(int argc, char **argv)
{
    std::string socket = "keel-test-lipstick-0";
    std::string logPath;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--socket" && i + 1 < argc) {
            socket = argv[++i];
        } else if (a == "--log" && i + 1 < argc) {
            logPath = argv[++i];
        } else if (a == "--size" && i + 1 < argc) {
            std::istringstream size(argv[++i]);
            char by = 0;
            if (!(size >> g_width >> by >> g_height) || by != 'x' || !size.eof()) {
                usage();
                return 2;
            }
        } else {
            usage();
            return a == "-h" || a == "--help" ? 0 : 2;
        }
    }
    if (!logPath.empty()) {
        g_log = std::fopen(logPath.c_str(), "w");
        if (!g_log) {
            std::perror(logPath.c_str());
            return 1;
        }
    }
    g_display = wl_display_create();
    if (wl_display_add_socket(g_display, socket.c_str()) != 0) {
        std::fprintf(stderr, "keel-test-compositor: cannot listen on %s: %s\n", socket.c_str(),
                     std::strerror(errno));
        return 1;
    }
    wl_display_init_shm(g_display);
    wl_global_create(g_display, &wl_compositor_interface, 4, nullptr, bindCompositor);
    wl_global_create(g_display, &wl_output_interface, 2, nullptr, bindOutput);
    wl_global_create(g_display, &wl_seat_interface, 5, nullptr, bindSeat);
    wl_global_create(g_display, &wl_shell_interface, 1, nullptr, bindShell);
    wl_global_create(g_display, &qt_surface_extension_interface, 1, nullptr, bindSurfaceExtension);

    wl_event_loop *loop = wl_display_get_event_loop(g_display);
    g_frameTimer = wl_event_loop_add_timer(loop, onFrameTimer, nullptr);
    wl_event_source_timer_update(g_frameTimer, 16);
    wl_event_loop_add_fd(loop, STDIN_FILENO, WL_EVENT_READABLE, onStdin, nullptr);

    logEvent("ready", str("socket", socket) + "," + num("width", g_width) + "," + num("height", g_height));
    std::fprintf(stdout, "ready %s\n", socket.c_str());
    std::fflush(stdout);
    wl_display_run(g_display);
    logEvent("exit");
    wl_display_destroy_clients(g_display);
    wl_display_destroy(g_display);
    return 0;
}
