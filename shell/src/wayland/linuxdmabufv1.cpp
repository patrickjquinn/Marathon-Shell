#include "linuxdmabufv1.h"

#include "linux-dmabuf-v1-server.h"

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

} // namespace

// ---------------------------------------------------------------------------
// LinuxDmabufManagerV1
// ---------------------------------------------------------------------------

LinuxDmabufManagerV1::LinuxDmabufManagerV1(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    // dev_t of /dev/dri/renderD128 — sent as main_device in feedback.
    struct stat st{};
    if (stat("/dev/dri/renderD128", &st) == 0) {
        m_mainDevice = static_cast<quint64>(st.st_rdev);
    } else {
        qWarning() << "[LinuxDmabufV1] stat /dev/dri/renderD128 failed:" << strerror(errno)
                   << "— feedback main_device will be 0, clients may refuse to allocate";
    }

    m_formatTableFd      = makeFormatTableFd();
    m_formatTableSize    = kFormatTableSize;
    m_formatTableEntries = kFormatTableEntries;

    auto *display = static_cast<struct wl_display *>(m_compositor->display());
    // Register at version 4. Qt's existing v3 plugin (loaded via
    // QT_WAYLAND_HARDWARE_INTEGRATION="...;linux-dmabuf-unstable-v1")
    // registers a SEPARATE wl_global at v3. Wayland-server allows the
    // same interface name at multiple versions; clients (Chromium)
    // bind to the highest they support.
    m_global = wl_global_create(display, &zwp_linux_dmabuf_v1_interface, 4, this,
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

void LinuxDmabufManagerV1::handleCreateParams(struct wl_client *client,
                                              struct wl_resource * /*resource*/,
                                              uint32_t /*params_id*/) {
    // Spike: not implemented. Clients that bind v4 and call create_params
    // get a protocol error. The hypothesis is that Chromium binds v4 for
    // feedback events but falls back to a separate v3 bind for actual
    // buffer allocation. If that's wrong, we'll see this error in the
    // stderr trace and extend the scope. Send NO_MEMORY-style fatal so
    // the client cleanly drops the v4 binding without crashing.
    qWarning() << "[LinuxDmabufV1] create_params called on v4 binding — spike does not "
                  "implement buffer allocation here, returning error to force client to "
                  "fall back to Qt's v3 plugin";
    wl_client_post_implementation_error(
        client, "marathon-dmabuf-v1 spike: create_params not implemented on v4 binding");
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
