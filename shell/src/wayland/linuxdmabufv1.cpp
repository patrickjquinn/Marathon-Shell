#include "linuxdmabufv1.h"

#include "linux-dmabuf-v1-server.h"
#include "src/managers/deviceprofile.h"

#include <QByteArray>
#include <QDebug>
#include <QFile>
#include <QWaylandCompositor>
#include <QWaylandSurface>
#include <drm/drm_fourcc.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {

    // Static format table for the spike. Etnaviv on GC7000Lite supports
    // these natively without modifiers (LINEAR). The compositor will accept
    // dmabuf imports for these (format, modifier) pairs only — anything
    // else clients propose via create_params should be rejected by the
    // underlying integration. Chromium only really needs XRGB8888 +
    // ARGB8888 for its compositor; NV12 covers video decode.
    struct FormatEntry {
        uint32_t fourcc;
        uint32_t _pad;
        uint64_t modifier;
    };

    static_assert(sizeof(FormatEntry) == 16,
                  "feedback format_table entry must be 16 bytes per spec");

    const FormatEntry kFormatTable[] = {
        {DRM_FORMAT_XRGB8888, 0, DRM_FORMAT_MOD_LINEAR},
        {DRM_FORMAT_ARGB8888, 0, DRM_FORMAT_MOD_LINEAR},
        {DRM_FORMAT_NV12, 0, DRM_FORMAT_MOD_LINEAR},
    };

    constexpr uint32_t kFormatTableEntries = sizeof(kFormatTable) / sizeof(FormatEntry);
    constexpr uint32_t kFormatTableSize    = sizeof(kFormatTable);

    // memfd_create with no glibc wrapper on musl <1.2 just in case.
    int marathon_memfd_create(const char *name, unsigned int flags) {
#ifdef __NR_memfd_create
        return static_cast<int>(syscall(__NR_memfd_create, name, flags));
#else
        Q_UNUSED(name);
        Q_UNUSED(flags);
        errno = ENOSYS;
        return -1;
#endif
    }

    int makeFormatTableFd() {
        int fd = marathon_memfd_create("marathon-dmabuf-table", MFD_CLOEXEC | MFD_ALLOW_SEALING);
        if (fd < 0) {
            qWarning() << "[LinuxDmabufV1] memfd_create failed:" << strerror(errno);
            return -1;
        }
        ssize_t written = write(fd, kFormatTable, kFormatTableSize);
        if (written != static_cast<ssize_t>(kFormatTableSize)) {
            qWarning() << "[LinuxDmabufV1] format table write short:" << written;
            close(fd);
            return -1;
        }
        // Seal the table so clients can mmap it as PROT_READ safely.
        fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE | F_SEAL_SEAL);
        return fd;
    }

    // Build the array of u16 indices for tranche_formats. We expose all
    // table entries as one tranche.
    QByteArray buildTrancheFormatsIndices() {
        QByteArray indices;
        indices.resize(static_cast<int>(kFormatTableEntries) * sizeof(uint16_t));
        auto *out = reinterpret_cast<uint16_t *>(indices.data());
        for (uint32_t i = 0; i < kFormatTableEntries; ++i)
            out[i] = static_cast<uint16_t>(i);
        return indices;
    }

    // Interface dispatch table for zwp_linux_dmabuf_v1.
    const struct zwp_linux_dmabuf_v1_interface kDmabufV1Impl = {
        LinuxDmabufManagerV1::handleDestroy,
        LinuxDmabufManagerV1::handleCreateParams,
        LinuxDmabufManagerV1::handleGetDefaultFeedback,
        LinuxDmabufManagerV1::handleGetSurfaceFeedback,
    };

    // Interface dispatch table for zwp_linux_dmabuf_feedback_v1.
    const struct zwp_linux_dmabuf_feedback_v1_interface kFeedbackV1Impl = {
        LinuxDmabufFeedbackV1::handleDestroy,
    };

    // Interface dispatch table for zwp_linux_buffer_params_v1.
    const struct zwp_linux_buffer_params_v1_interface kBufferParamsV1Impl = {
        LinuxDmabufBufferParamsV1::handleDestroy,
        LinuxDmabufBufferParamsV1::handleAdd,
        LinuxDmabufBufferParamsV1::handleCreate,
        LinuxDmabufBufferParamsV1::handleCreateImmed,
    };

    // Inert wl_buffer dispatch table — used for the stub buffer that
    // create_immed has to produce. Only `destroy` is meaningful; the
    // client should never attach this buffer to a surface (we emit a
    // .release immediately so the client discards it), but if it does,
    // wayland-server handles the destroy cleanly.
    // constexpr: a capture-less lambda converts to a function pointer at
    // compile time, so this needs no throwing pre-main initialiser.
    constexpr struct wl_buffer_interface kStubBufferImpl = {
        [](struct wl_client *, struct wl_resource *resource) { wl_resource_destroy(resource); },
    };

} // namespace

// ---------------------------------------------------------------------------
// LinuxDmabufManagerV1
// ---------------------------------------------------------------------------

LinuxDmabufManagerV1::LinuxDmabufManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    // dev_t of the render node (L5 default /dev/dri/renderD128, overlay-set
    // via DeviceProfile) — sent as main_device in feedback.
    const QByteArray renderNode = DeviceProfile::instance().renderNode().toLocal8Bit();
    struct stat      st{};
    if (stat(renderNode.constData(), &st) == 0) {
        m_mainDevice = static_cast<quint64>(st.st_rdev);
    } else {
        qWarning() << "[LinuxDmabufV1] stat" << renderNode << "failed:" << strerror(errno)
                   << "— feedback main_device will be 0, clients may refuse to allocate";
    }

    m_formatTableFd      = makeFormatTableFd();
    m_formatTableSize    = kFormatTableSize;
    m_formatTableEntries = kFormatTableEntries;

    // ── v4 global advertisement gated by env opt-in ──────────────
    //
    // The v4 spike originally registered unconditionally to fix
    // QRhi/null-texture failures via feedback events. Live regression
    // on 2026-06-30: Mesa's wayland-egl client binds the HIGHEST
    // advertised dmabuf-v1 version (ours, v4), then pipelines
    // create_params → add → create_immed → params.destroy → surface.attach
    // in one batch. Our v4 implementation can't synthesise a Qt-tracked
    // wl_buffer for create_immed without re-implementing Qt's v3 plugin
    // internals, so attach either fails (buffer destroyed too early) or
    // crashes Qt's WaylandEglClientBufferIntegration (orphan buffer with
    // no integration user_data). Qt's own v3 plugin handles allocation
    // correctly; clients that bind v3 work end-to-end.
    //
    // Until the v4 buffer path is wired through Qt's HW integration,
    // gate the v4 advertisement on MARATHON_DMABUF_V4=1 so:
    //   - default: Qt's v3 plugin is the only dmabuf-v1 advertised;
    //     all Qt-EGL clients allocate successfully via v3.
    //   - opt-in:  set the env to advertise v4 too — only when the
    //     consumer (Chromium/WPE) genuinely needs feedback events.
    //
    // The feedback-events fix that justified the original spike was
    // load-bearing for clients that need main_device discovery to
    // pick a renderD path. Currently no production client requires
    // that — WebEngine is disabled on etnaviv pending Mesa 26.2 and
    // WPE is in Phase 2 validation. Re-enable v4 alongside the WPE
    // production cutover (and with a real create_params impl).
    const bool enableV4 = qEnvironmentVariableIntValue("MARATHON_DMABUF_V4") == 1;
    if (!enableV4) {
        qInfo()
            << "[LinuxDmabufV1] v4 advertisement DISABLED (set MARATHON_DMABUF_V4=1 to enable). "
               "Qt's v3 plugin remains active and handles all dmabuf imports.";
        return;
    }

    auto *display = static_cast<struct wl_display *>(m_compositor->display());
    m_global      = wl_global_create(display, &zwp_linux_dmabuf_v1_interface, 4, this,
                                     &LinuxDmabufManagerV1::bindManager);
    if (!m_global) {
        qWarning() << "[LinuxDmabufV1] wl_global_create failed";
    } else {
        qInfo() << "[LinuxDmabufV1] manager registered (version 4, main_device=0x"
                << QString::number(m_mainDevice, 16).toLatin1()
                << ", formats=" << kFormatTableEntries << ")";
    }
}

LinuxDmabufManagerV1::~LinuxDmabufManagerV1() {
    if (m_global)
        wl_global_destroy(m_global);
    if (m_formatTableFd >= 0)
        close(m_formatTableFd);
}

void LinuxDmabufManagerV1::bindManager(struct wl_client *client, void *data, uint32_t version,
                                       uint32_t id) {
    auto               *self    = static_cast<LinuxDmabufManagerV1 *>(data);
    const uint32_t      bindVer = qMin(version, 4u);
    struct wl_resource *resource =
        wl_resource_create(client, &zwp_linux_dmabuf_v1_interface, bindVer, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &kDmabufV1Impl, self, nullptr);
    qInfo() << "[LinuxDmabufV1] client bound (version" << bindVer << ")";
    // No format/modifier events advertised on bind — clients that want
    // capability discovery must use get_default_feedback (v4+).
}

void LinuxDmabufManagerV1::handleDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

void LinuxDmabufManagerV1::handleCreateParams(struct wl_client   *client,
                                              struct wl_resource *resource, uint32_t params_id) {
    // Create a real zwp_linux_buffer_params_v1 resource at params_id so
    // the wire protocol stays valid (`new_id` arg MUST allocate). The
    // implementation refuses buffer creation via .failed events; Qt's
    // wayland-egl client retries on its v3 binding which does have the
    // import path wired up. Previously this posted a protocol error and
    // killed the connection. See header for full rationale.
    const uint32_t      version       = wl_resource_get_version(resource);
    struct wl_resource *paramResource = wl_resource_create(
        client, &zwp_linux_buffer_params_v1_interface, static_cast<int>(version), params_id);
    if (!paramResource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(paramResource, &kBufferParamsV1Impl, nullptr, nullptr);
}

void LinuxDmabufManagerV1::handleGetDefaultFeedback(struct wl_client   *client,
                                                    struct wl_resource *resource, uint32_t id) {
    auto          *self = static_cast<LinuxDmabufManagerV1 *>(wl_resource_get_user_data(resource));
    const uint32_t version  = wl_resource_get_version(resource);
    auto          *feedback = new LinuxDmabufFeedbackV1(self, client, version, id);
    self->m_feedbacks.append(feedback);
    feedback->sendInitial();
}

void LinuxDmabufManagerV1::handleGetSurfaceFeedback(struct wl_client   *client,
                                                    struct wl_resource *resource, uint32_t id,
                                                    struct wl_resource * /*surface_resource*/) {
    // Per-surface feedback is identical to default feedback in the
    // spike — we don't differentiate between surfaces yet (no
    // per-surface preference tranches). Chromium reads main_device
    // from whichever it gets.
    auto          *self = static_cast<LinuxDmabufManagerV1 *>(wl_resource_get_user_data(resource));
    const uint32_t version  = wl_resource_get_version(resource);
    auto          *feedback = new LinuxDmabufFeedbackV1(self, client, version, id);
    self->m_feedbacks.append(feedback);
    feedback->sendInitial();
}

void LinuxDmabufManagerV1::unregisterFeedback(LinuxDmabufFeedbackV1 *feedback) {
    m_feedbacks.removeAll(feedback);
}

// ---------------------------------------------------------------------------
// LinuxDmabufFeedbackV1
// ---------------------------------------------------------------------------

LinuxDmabufFeedbackV1::LinuxDmabufFeedbackV1(LinuxDmabufManagerV1 *manager,
                                             struct wl_client *client, uint32_t version,
                                             uint32_t id)
    : m_manager(manager) {
    m_resource = wl_resource_create(client, &zwp_linux_dmabuf_feedback_v1_interface,
                                    static_cast<int>(version), id);
    if (!m_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(m_resource, &kFeedbackV1Impl, this, [](struct wl_resource *res) {
        auto *self = static_cast<LinuxDmabufFeedbackV1 *>(wl_resource_get_user_data(res));
        if (self) {
            self->m_manager->unregisterFeedback(self);
            self->deleteLater();
        }
    });
}

LinuxDmabufFeedbackV1::~LinuxDmabufFeedbackV1() = default;

void LinuxDmabufFeedbackV1::sendInitial() {
    if (!m_resource)
        return;

    // format_table — dup the manager's memfd so each client gets its own
    // FD. Wire encoding sends the size as u32.
    if (m_manager->formatTableFd() >= 0) {
        int dupFd = fcntl(m_manager->formatTableFd(), F_DUPFD_CLOEXEC, 0);
        if (dupFd >= 0) {
            zwp_linux_dmabuf_feedback_v1_send_format_table(m_resource, dupFd,
                                                           m_manager->formatTableSize());
            close(dupFd);
        }
    }

    // main_device — preferred allocation device (renderD128 dev_t).
    struct wl_array mainDeviceArray;
    wl_array_init(&mainDeviceArray);
    void *mainPtr = wl_array_add(&mainDeviceArray, sizeof(quint64));
    memcpy(mainPtr, &m_manager->m_mainDevice, sizeof(quint64));
    zwp_linux_dmabuf_feedback_v1_send_main_device(m_resource, &mainDeviceArray);

    // One tranche: target the same render node, expose all formats.
    zwp_linux_dmabuf_feedback_v1_send_tranche_target_device(m_resource, &mainDeviceArray);
    zwp_linux_dmabuf_feedback_v1_send_tranche_flags(m_resource, 0);

    QByteArray      trancheIndices = buildTrancheFormatsIndices();
    struct wl_array trancheArray;
    wl_array_init(&trancheArray);
    void *tranchePtr = wl_array_add(&trancheArray, trancheIndices.size());
    memcpy(tranchePtr, trancheIndices.constData(), trancheIndices.size());
    zwp_linux_dmabuf_feedback_v1_send_tranche_formats(m_resource, &trancheArray);
    wl_array_release(&trancheArray);

    zwp_linux_dmabuf_feedback_v1_send_tranche_done(m_resource);
    zwp_linux_dmabuf_feedback_v1_send_done(m_resource);

    wl_array_release(&mainDeviceArray);
}

void LinuxDmabufFeedbackV1::handleDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

// ---------------------------------------------------------------------------
// LinuxDmabufBufferParamsV1 — graceful-fallback stub.
//
// The v4 binding's create_params has to return a real resource (the
// protocol's new_id arg is mandatory) but this implementation refuses
// to actually back any of the buffers it pretends to receive. Qt's
// wayland-egl client treats the .failed event as "this version can't
// allocate; try another binding" and retries on its v3 binding, which
// has full create_params support via Qt's own dmabuf plugin.
// ---------------------------------------------------------------------------

void LinuxDmabufBufferParamsV1::handleDestroy(struct wl_client *, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

void LinuxDmabufBufferParamsV1::handleAdd(struct wl_client * /*client*/,
                                          struct wl_resource * /*resource*/, int32_t fd,
                                          uint32_t /*plane_idx*/, uint32_t /*offset*/,
                                          uint32_t /*stride*/, uint32_t /*modifier_hi*/,
                                          uint32_t /*modifier_lo*/) {
    // We will not import this dmabuf — close the fd immediately to
    // avoid leaking it on the server side. Wayland's wire decoder
    // already dup()'d it into our process when the request landed.
    if (fd >= 0)
        close(fd);
}

void LinuxDmabufBufferParamsV1::handleCreate(struct wl_client * /*client*/,
                                             struct wl_resource *resource, int32_t /*width*/,
                                             int32_t /*height*/, uint32_t /*format*/,
                                             uint32_t /*flags*/) {
    // Deferred-creation path: the protocol's .failed event is the
    // documented way to signal "the requested import did not succeed"
    // without tearing down the connection. The client cleans up the
    // params object after handling this event.
    zwp_linux_buffer_params_v1_send_failed(resource);
}

void LinuxDmabufBufferParamsV1::handleCreateImmed(struct wl_client *client,
                                                  struct wl_resource * /*resource*/,
                                                  uint32_t buffer_id, int32_t /*width*/,
                                                  int32_t /*height*/, uint32_t /*format*/,
                                                  uint32_t /*flags*/) {
    // Immediate-creation path: the buffer_id new_id MUST be allocated
    // or the wire protocol is broken. We allocate the resource and
    // IMMEDIATELY destroy it. wl_resource_destroy emits a
    // wl_display.delete_id event so the client processes the events in
    // order — create_immed succeeds, then the buffer is gone before
    // anything can attach it.
    //
    // The earlier approach of leaving the buffer alive (with a
    // .release event) caused Qt's WaylandEglClientBufferIntegration
    // to call createBufferFor() on the orphan resource and crash
    // dereferencing missing user-data (verified in the L5 coredump
    // stack: marathon-shell SEGV in createBufferFor, Jun 30).
    //
    // Qt's wayland-egl client treats the disappeared buffer as a
    // failed allocation and falls back to its v3 binding (which has
    // a working create_immed via Qt's own dmabuf plugin).
    struct wl_resource *bufferResource =
        wl_resource_create(client, &wl_buffer_interface, 1, buffer_id);
    if (!bufferResource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(bufferResource, &kStubBufferImpl, nullptr, nullptr);
    wl_resource_destroy(bufferResource);
}
