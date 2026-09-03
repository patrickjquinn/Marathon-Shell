#ifndef LINUXDMABUFV1_H
#define LINUXDMABUFV1_H

#include <QHash>
#include <QObject>
#include <wayland-server-core.h>

class QWaylandCompositor;
class QWaylandSurface;
class LinuxDmabufFeedbackV1;

// zwp_linux_dmabuf_v1 v4 — spike implementation focused on the feedback
// layer (main_device + tranche_target_device + tranche_formats events)
// that Chromium 130 requires for clean EGL config negotiation.
//
// Why: Qt 6.11's bundled wayland-egl client buffer integration ships only
// v3 of this protocol — no feedback events. Chromium's GPU process then
// can't discover which DRM device to allocate via, falls back to an EGL
// config request etnaviv rejects with EGL_BAD_MATCH (ES3-on-ES2-bit),
// and every WebEngine texture comes back as null. Verified live.
//
// This handler registers a SECOND wl_global at version 4 alongside Qt's
// existing v3 global. Wayland-server lets the same interface name be
// advertised at multiple versions — clients bind whichever they prefer.
// Chromium binds v4 for the feedback events.
//
// SCOPE: feedback layer is the load-bearing piece (Chromium GPU
// process + WPE WebKit both need v4 main_device events). create_params
// is implemented as a graceful-fallback path — the spike does NOT
// allocate dmabuf-backed wl_buffers itself (Qt's existing v3 plugin
// handles that path); instead, the v4 binding's create_params/
// create_immed paths emit `failed` events / produce inert wl_buffer
// stubs so Qt's client retries on its v3 binding cleanly.
//
// Previously create_params posted an implementation_error which
// terminated the wayland connection — that took out any Qt client
// whose wayland-egl plugin happened to bind v4 (the higher version)
// and then call create_params. Live regression: per-app QML loaded
// from disk (qrc-strip hot-deploy) crashed marathon-app-runner with
// "create_params not implemented on v4 binding". Now we keep the wire
// protocol valid + signal failure via the documented mechanism so the
// client can fall through.
//
// Pattern follows FifoV1: per-process Manager owns the wl_global,
// per-client Feedback object owns one wp_linux_dmabuf_feedback_v1
// resource. BufferParamsV1 is a transient per-create_params resource.

class LinuxDmabufManagerV1 : public QObject {
    Q_OBJECT

  public:
    explicit LinuxDmabufManagerV1(QWaylandCompositor *compositor);
    ~LinuxDmabufManagerV1() override;

    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);

    // /dev/dri/renderD128 stat'd at construction. Sent as main_device +
    // tranche_target_device events. uint64 across the wire (size of dev_t
    // on Linux is 8 bytes).
    quint64 mainDevice() const {
        return m_mainDevice;
    }

    // Pre-built format_table FD. mmap'd-style: a sequence of 16-byte
    // entries, each (u32 fourcc + u32 pad + u64 modifier). Sent once
    // to every feedback object alongside its size in bytes.
    int formatTableFd() const {
        return m_formatTableFd;
    }
    quint32 formatTableSize() const {
        return m_formatTableSize;
    }

    // Number of (format, modifier) entries in the table — sent as the
    // tranche_formats event payload (array of u16 indices).
    quint32 formatTableEntries() const {
        return m_formatTableEntries;
    }

    // Protocol request handlers (zwp_linux_dmabuf_v1). Public because
    // they are entry points from C wayland-server via function-pointer
    // dispatch tables.
    static void handleDestroy(struct wl_client *, struct wl_resource *);
    static void handleCreateParams(struct wl_client *, struct wl_resource *, uint32_t params_id);
    static void handleGetDefaultFeedback(struct wl_client *, struct wl_resource *, uint32_t id);
    static void handleGetSurfaceFeedback(struct wl_client *, struct wl_resource *, uint32_t id,
                                         struct wl_resource *surface_resource);

  private:
    friend class LinuxDmabufFeedbackV1;

    void                           unregisterFeedback(LinuxDmabufFeedbackV1 *feedback);

    QWaylandCompositor            *m_compositor = nullptr;
    struct wl_global              *m_global     = nullptr;
    QList<LinuxDmabufFeedbackV1 *> m_feedbacks;

    // Render node identity. dev_t on Linux is 8 bytes; we send it raw.
    quint64 m_mainDevice = 0;

    // memfd-backed format table. Owned by the manager for the
    // process lifetime — every feedback object dup()s the fd into
    // its format_table event.
    int     m_formatTableFd      = -1;
    quint32 m_formatTableSize    = 0;
    quint32 m_formatTableEntries = 0;
};

// zwp_linux_buffer_params_v1 — transient per-create_params resource.
//
// This implementation intentionally does NOT perform dmabuf import.
// It exists solely to keep the wire protocol valid on the v4 binding
// when a client (Qt's wayland-egl plugin in particular) calls
// create_params expecting v3-compatible buffer allocation. On the
// create() request we emit the .failed event so the client cleans up
// and (in Qt's case) falls through to a v3 binding that does
// implement allocation. On create_immed() we MUST create a wl_buffer
// (new_id is mandatory) but it's a stub with no backing — the client
// gets a .release event immediately and discards it.
//
// The add() request closes the supplied fd (we will never use it)
// and otherwise no-ops; the alternative is leaking client fds.
class LinuxDmabufBufferParamsV1 {
  public:
    static void handleDestroy(struct wl_client *, struct wl_resource *);
    static void handleAdd(struct wl_client *, struct wl_resource *, int32_t fd, uint32_t plane_idx,
                          uint32_t offset, uint32_t stride, uint32_t modifier_hi,
                          uint32_t modifier_lo);
    static void handleCreate(struct wl_client *, struct wl_resource *, int32_t width,
                             int32_t height, uint32_t format, uint32_t flags);
    static void handleCreateImmed(struct wl_client *, struct wl_resource *, uint32_t buffer_id,
                                  int32_t width, int32_t height, uint32_t format, uint32_t flags);
};

// zwp_linux_dmabuf_feedback_v1 — one per get_default_feedback /
// get_surface_feedback call. Emits the parameter events on construction
// then a single `done`. Re-emission on parameter change is not needed
// in the spike (we never re-emit — formats are static).
class LinuxDmabufFeedbackV1 : public QObject {
    Q_OBJECT

  public:
    LinuxDmabufFeedbackV1(LinuxDmabufManagerV1 *manager, struct wl_client *client, uint32_t version,
                          uint32_t id);
    ~LinuxDmabufFeedbackV1() override;

    void        sendInitial();

    static void handleDestroy(struct wl_client *, struct wl_resource *);

  private:
    LinuxDmabufManagerV1 *m_manager  = nullptr;
    struct wl_resource   *m_resource = nullptr;
};

#endif // LINUXDMABUFV1_H
