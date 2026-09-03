// Copyright (C) 2018 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
// Qt-Security score:critical reason:network-protocol

#include "linuxdmabuf.h"
#include "linuxdmabufclientbufferintegration.h"

#include <QtCore/QStandardPaths>

#include <QtWaylandCompositor/QWaylandCompositor>
#include <QtWaylandCompositor/private/qwltextureorphanage_p.h>

#include <drm_fourcc.h>
#include <drm_mode.h>
#include <unistd.h>
#include <sys/stat.h>

#include <fcntl.h>
#include <sys/mman.h>

#ifdef Q_OS_LINUX
#  include <sys/syscall.h>
// from linux/memfd.h:
#  ifndef MFD_CLOEXEC
#    define MFD_CLOEXEC     0x0001U
#  endif
#  ifndef MFD_ALLOW_SEALING
#    define MFD_ALLOW_SEALING 0x0002U
#  endif
// from bits/fcntl-linux.h
#  ifndef F_ADD_SEALS
#    define F_ADD_SEALS 1033
#  endif
#  ifndef F_SEAL_SEAL
#    define F_SEAL_SEAL 0x0001
#  endif
#  ifndef F_SEAL_SHRINK
#    define F_SEAL_SHRINK 0x0002
#  endif
#endif

QT_BEGIN_NAMESPACE

LinuxDmabuf::LinuxDmabuf(int version,
                         wl_display *display,
                         LinuxDmabufClientBufferIntegration *clientBufferIntegration)
    : zwp_linux_dmabuf_v1(display, version)
    , m_clientBufferIntegration(clientBufferIntegration)
{
}

void LinuxDmabuf::setDrmDevice(const char *drmDevice)
{
    m_drmDevice = drmDevice;
}

void LinuxDmabuf::setSupportedModifiers(const QHash<uint32_t, QList<uint64_t>> &modifiers)
{
    Q_ASSERT(resourceMap().isEmpty());
    m_modifiers = modifiers;
}

void LinuxDmabuf::zwp_linux_dmabuf_v1_bind_resource(Resource *resource)
{
    if (resource->version() >= ZWP_LINUX_DMABUF_V1_GET_SURFACE_FEEDBACK_SINCE_VERSION)
        return;

    for (auto it = m_modifiers.constBegin(); it != m_modifiers.constEnd(); ++it) {
        auto format = it.key();
        auto modifiers = it.value();
        // send DRM_FORMAT_MOD_INVALID when no modifiers are supported for a format
        if (modifiers.isEmpty())
            modifiers << DRM_FORMAT_MOD_INVALID;
        for (const auto &modifier : std::as_const(modifiers)) {
            if (resource->version() >= ZWP_LINUX_DMABUF_V1_MODIFIER_SINCE_VERSION) {
                const uint32_t modifier_lo = modifier & 0xFFFFFFFF;
                const uint32_t modifier_hi = modifier >> 32;
                send_modifier(resource->handle, format, modifier_hi, modifier_lo);
            } else if (modifier == DRM_FORMAT_MOD_LINEAR || modifier == DRM_FORMAT_MOD_INVALID) {
                send_format(resource->handle, format);
            }
        }
    }
}

void LinuxDmabuf::zwp_linux_dmabuf_v1_create_params(Resource *resource, uint32_t params_id)
{
    wl_resource *r = wl_resource_create(resource->client(), &zwp_linux_buffer_params_v1_interface,
                                        wl_resource_get_version(resource->handle), params_id);
    new LinuxDmabufParams(m_clientBufferIntegration, r); // deleted by the client, or when it disconnects
}

void LinuxDmabuf::zwp_linux_dmabuf_v1_get_default_feedback(Resource *resource, uint32_t id)
{
    if (resource->version() < ZWP_LINUX_DMABUF_V1_GET_DEFAULT_FEEDBACK_SINCE_VERSION)
        return;

    wl_resource *r = wl_resource_create(resource->client(),
                                        &zwp_linux_dmabuf_feedback_v1_interface,
                                        wl_resource_get_version(resource->handle),
                                        id);
    // Deleted by client
    new LinuxDmabufFeedback(m_modifiers, m_drmDevice, r);
}

void LinuxDmabuf::zwp_linux_dmabuf_v1_get_surface_feedback(Resource *resource, uint32_t id, struct ::wl_resource *surface)
{
    if (resource->version() < ZWP_LINUX_DMABUF_V1_GET_SURFACE_FEEDBACK_SINCE_VERSION)
        return;

    Q_UNUSED(surface);
    wl_resource *r = wl_resource_create(resource->client(),
                                        &zwp_linux_dmabuf_feedback_v1_interface,
                                        wl_resource_get_version(resource->handle),
                                        id);
    // Deleted by client
    new LinuxDmabufFeedback(m_modifiers, m_drmDevice, r);
}

LinuxDmabufFeedback::LinuxDmabufFeedback(QHash<uint32_t, QList<uint64_t>> modifiers,
                                         const char *drmDevice, wl_resource *res)
    : zwp_linux_dmabuf_feedback_v1(res)
    , m_modifiers(modifiers)
    , m_drmDevice(drmDevice)
{
    sendFeedback(resource());
}

LinuxDmabufFeedback::~LinuxDmabufFeedback()
{
    if (m_data)
        munmap(m_data, m_size);
}

void LinuxDmabufFeedback::zwp_linux_dmabuf_feedback_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void LinuxDmabufFeedback::zwp_linux_dmabuf_feedback_v1_destroy_resource(Resource *resource)
{
    Q_UNUSED(resource);
    delete this;
}

void LinuxDmabufFeedback::zwp_linux_dmabuf_feedback_v1_bind_resource(Resource *resource)
{
    sendFeedback(resource);
}

QByteArray LinuxDmabufFeedback::sendFormatTable(Resource *)
{
    QList<std::pair<uint32_t, uint64_t> > formatModifierPairs;
    for (auto it = m_modifiers.constBegin(); it != m_modifiers.constEnd(); ++it) {
        uint32_t format = it.key();
        QList<uint64_t> modifiers = it.value();

        if (!modifiers.isEmpty()) {
            for (uint64_t modifier : modifiers)
                formatModifierPairs.append(std::make_pair(format, modifier));
        } else {
            formatModifierPairs.append(std::make_pair(format, DRM_FORMAT_MOD_INVALID));
        }
    }

    if (formatModifierPairs.isEmpty()) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "LinuxDmabufFeedback: No formats";
        return QByteArray{};
    }

    int fd = -1;
#ifdef SYS_memfd_create
    fd = syscall(SYS_memfd_create, "wayland-dmabuf", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd >= 0)
        fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_SEAL);
#endif

    std::unique_ptr<QFile> filePointer;
    if (fd == -1) {
        auto tmpFile =
            std::make_unique<QTemporaryFile>(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) +
                                             QLatin1String("/wayland-dmabuf-XXXXXX"));
        if (tmpFile->open())
            filePointer = std::move(tmpFile);
    } else {
        auto file = std::make_unique<QFile>();
        if (file->open(fd, QIODevice::ReadWrite | QIODevice::Unbuffered, QFile::AutoCloseHandle))
            filePointer = std::move(file);
    }

    m_size = formatModifierPairs.size() * 16;
    if (!filePointer || !filePointer->resize(m_size)) {
        qCWarning(qLcWaylandCompositorHardwareIntegration)
            << "LinuxDmabufFeedback: failed: " << filePointer->errorString();
        return QByteArray{};
    }

    fd = filePointer->handle();

    if (m_data)
        munmap(m_data, m_size);
    m_data = (uchar *) mmap(nullptr, m_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

    QByteArray indicesArray;
    indicesArray.resize(formatModifierPairs.size() * 2); // Each index is 2 bytes
    char *iptr = indicesArray.data();

    // Copy data into array with native endianness
    for (quint16 i = 0; i < quint16(formatModifierPairs.size()); ++i) {
        memcpy(iptr, &i, 2);
        iptr += 2;

        const auto &formatModifierPair = formatModifierPairs.at(i);
        uint32_t format = formatModifierPair.first;
        uint64_t modifiers = formatModifierPair.second;
        memcpy(m_data, &format, 4);
        m_data += 4;

        m_data += 4; // Padding

        memcpy(m_data, &modifiers, 8);
        m_data += 8;
    }

    send_format_table(fd, m_size);

    // Returns indices for convenience
    return indicesArray;
}

void LinuxDmabufFeedback::sendFeedback(Resource *resource)
{
    if (!m_drmDevice)
        return;

    QByteArray indices = sendFormatTable(resource);

    // Query main device by getting the device number of the drm device,
    // granted its still there.
    struct stat drmDeviceStat;
    if (stat(m_drmDevice, &drmDeviceStat)) {
        qCWarning(qLcWaylandCompositorHardwareIntegration)
            << "Failed to access DRM device in linux-dmabuf-feedback";
        return;
    }

    dev_t mainDevice = drmDeviceStat.st_rdev;
    QByteArray mainDeviceArray;
    mainDeviceArray.setRawData(reinterpret_cast<const char *>(&mainDevice), sizeof(dev_t));
    send_main_device(mainDeviceArray);

    // At least one tranche required, we just send one with all formats
    send_tranche_target_device(mainDeviceArray);
    send_tranche_flags(0);
    send_tranche_formats(indices);
    send_tranche_done();

    send_done();
}

LinuxDmabufParams::LinuxDmabufParams(LinuxDmabufClientBufferIntegration *clientBufferIntegration, wl_resource *resource)
    : zwp_linux_buffer_params_v1(resource)
    , m_clientBufferIntegration(clientBufferIntegration)
{
}

LinuxDmabufParams::~LinuxDmabufParams()
{
    for (auto it = m_planes.begin(); it != m_planes.end(); ++it) {
        if (it.value().fd != -1)
            close(it.value().fd);
        it.value().fd = -1;
    }
}

bool LinuxDmabufParams::handleCreateParams(Resource *resource, int width, int height, uint format, uint flags)
{
    if (m_used) {
        wl_resource_post_error(resource->handle,
                               ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
                               "Params already used");
        return false;
    }

    if (width <= 0 || height <= 0) {
        wl_resource_post_error(resource->handle,
                               ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_DIMENSIONS,
                               "Invalid dimensions in create request");
        return false;
    }

    if (m_planes.isEmpty()) {
        wl_resource_post_error(resource->handle,
                               ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE,
                               "Cannot create a buffer with no planes");
        return false;
    }

    // check for holes in plane sequence
    auto planeIds = m_planes.keys();
    std::sort(planeIds.begin(), planeIds.end());
    for (int i = 0; i < planeIds.size(); ++i) {
        if (uint(i) != planeIds[i]) {
            wl_resource_post_error(resource->handle,
                                   ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE,
                                   "No dmabuf parameters provided for plane %i", i);
            return false;
        }
    }

    // check for overflows
    for (auto it = m_planes.constBegin(); it != m_planes.constEnd(); ++it) {
        const auto planeId = it.key();
        const auto plane = it.value();
        if (static_cast<int64_t>(plane.offset) + plane.stride > UINT32_MAX) {
            wl_resource_post_error(resource->handle,
                                   ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS,
                                   "Size overflow for plane %i",
                                   planeId);
            return false;
        }
        if (planeId == 0 && static_cast<int64_t>(plane.offset) + plane.stride * static_cast<int64_t>(height) > UINT32_MAX) {
            wl_resource_post_error(resource->handle,
                                   ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS,
                                   "Size overflow for plane %i",
                                   planeId);
            return false;
        }

        // do not report an error as it might be caused by the kernel not supporting seeking on dmabuf
        off_t size = lseek(plane.fd, 0, SEEK_END);
        if (size == -1) {
            qCDebug(qLcWaylandCompositorHardwareIntegration) << "Seeking is not supported";
            continue;
        }

        if (static_cast<int64_t>(plane.offset) >= size) {
            wl_resource_post_error(resource->handle,
                                   ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS,
                                   "Invalid offset %i for plane %i",
                                   plane.offset, planeId);
            return false;
        }

        if (static_cast<int64_t>(plane.offset) + static_cast<int64_t>(plane.stride) > size) {
            wl_resource_post_error(resource->handle,
                                   ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS,
                                   "Invalid stride %i for plane %i",
                                   plane.stride, planeId);
            return false;
        }

        // only valid for first plane as other planes might be sub-sampled
        if (planeId == 0 && plane.offset + static_cast<int64_t>(plane.stride) * height > size) {
            wl_resource_post_error(resource->handle,
                                   ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS,
                                   "Invalid buffer stride or height for plane %i", planeId);
            return false;
        }
    }

    m_size = QSize(width, height);
    m_drmFormat = format;
    m_flags = flags;
    m_used = true;

    return true;
}

void LinuxDmabufParams::zwp_linux_buffer_params_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void LinuxDmabufParams::zwp_linux_buffer_params_v1_destroy_resource(Resource *resource)
{
    Q_UNUSED(resource);
    delete this;
}

void LinuxDmabufParams::zwp_linux_buffer_params_v1_add(Resource *resource, int32_t fd, uint32_t plane_idx, uint32_t offset, uint32_t stride, uint32_t modifier_hi, uint32_t modifier_lo)
{
    const uint64_t modifiers = (static_cast<uint64_t>(modifier_hi) << 32) | modifier_lo;
    if (plane_idx >= LinuxDmabufWlBuffer::MaxDmabufPlanes) {
        wl_resource_post_error(resource->handle,
                               ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX,
                               "Plane index %i is out of bounds", plane_idx);
    }

    if (m_planes.contains(plane_idx)) {
        wl_resource_post_error(resource->handle,
                               ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_SET,
                               "Plane already set");
    }

    Plane plane;
    plane.fd = fd;
    plane.modifiers = modifiers;
    plane.offset = offset;
    plane.stride = stride;
    m_planes.insert(plane_idx, plane);
}

void LinuxDmabufParams::zwp_linux_buffer_params_v1_create(Resource *resource, int32_t width, int32_t height, uint32_t format, uint32_t flags)
{
    if (!handleCreateParams(resource, width, height, format, flags))
        return;

    auto *buffer = new LinuxDmabufWlBuffer(resource->client(), m_clientBufferIntegration);
    buffer->m_size = m_size;
    buffer->m_flags = m_flags;
    buffer->m_drmFormat = m_drmFormat;
    buffer->m_planesNumber = m_planes.size(); // it is checked before that planes are in consecutive sequence
    for (auto it = m_planes.begin(); it != m_planes.end(); ++it) {
        buffer->m_planes[it.key()] = it.value();
        it.value().fd = -1; // ownership is moved
    }

    if (!m_clientBufferIntegration->importBuffer(buffer->resource()->handle, buffer)) {
        send_failed(resource->handle);
    } else {
        send_created(resource->handle, buffer->resource()->handle);
    }
}

void LinuxDmabufParams::zwp_linux_buffer_params_v1_create_immed(Resource *resource, uint32_t buffer_id, int32_t width, int32_t height, uint32_t format, uint32_t flags)
{
    if (!handleCreateParams(resource, width, height, format, flags))
        return;

    auto *buffer = new LinuxDmabufWlBuffer(resource->client(), m_clientBufferIntegration, buffer_id);
    buffer->m_size = m_size;
    buffer->m_flags = m_flags;
    buffer->m_drmFormat = m_drmFormat;
    buffer->m_planesNumber = m_planes.size(); // it is checked before that planes are in consecutive sequence
    for (auto it = m_planes.begin(); it != m_planes.end(); ++it) {
        buffer->m_planes[it.key()] = it.value();
        it.value().fd = -1; // ownership is moved
    }

    if (!m_clientBufferIntegration->importBuffer(buffer->resource()->handle, buffer)) {
        // for the 'create_immed' request, the implementation can decide
        // how to handle the failure by an unknown cause; we decide
        // to raise a fatal error at the client
        wl_resource_post_error(resource->handle,
                               ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER,
                               "Import of the provided DMA buffer failed");
    }
    // note: create signal shall not be sent for the 'create_immed' request
}

LinuxDmabufWlBuffer::LinuxDmabufWlBuffer(::wl_client *client, LinuxDmabufClientBufferIntegration *clientBufferIntegration, uint id)
    : wl_buffer(client, id, 1 /*version*/)
    , m_clientBufferIntegration(clientBufferIntegration)
{
}

LinuxDmabufWlBuffer::~LinuxDmabufWlBuffer()
{
    if (resource())
        m_clientBufferIntegration->removeBuffer(resource()->handle);
    deleteTextures();
}

void LinuxDmabufWlBuffer::buffer_destroy(Resource *resource)
{
    m_clientBufferIntegration->removeBuffer(resource->handle);
    wl_resource_destroy(resource->handle);
}

void LinuxDmabufWlBuffer::deleteTextures()
{
    QMutexLocker locker(&m_texturesLock);

    for (uint32_t i = 0; i < m_planesNumber; ++i) {
        if (m_textures[i] != nullptr) {
            QtWayland::QWaylandTextureOrphanage::instance()->admitTexture(m_textures[i],
                                                                          m_texturesContext[i]);
            m_textures[i] = nullptr;
            m_texturesContext[i] = nullptr;
            QObject::disconnect(m_texturesAboutToBeDestroyedConnection[i]);
            m_texturesAboutToBeDestroyedConnection[i] = QMetaObject::Connection();
        }
        if (m_eglImages[i] != EGL_NO_IMAGE_KHR) {
            m_clientBufferIntegration->deleteImage(m_eglImages[i]);
            m_eglImages[i] = EGL_NO_IMAGE_KHR;
        }
        if (m_planes[i].fd != -1)
            close(m_planes[i].fd);
        m_planes[i].fd = -1;
    }
    m_planesNumber = 0;
}

void LinuxDmabufWlBuffer::initImage(uint32_t plane, EGLImageKHR image)
{
    Q_ASSERT(plane < m_planesNumber);
    Q_ASSERT(m_eglImages.at(plane) == EGL_NO_IMAGE_KHR);
    m_eglImages[plane] = image;
}

void LinuxDmabufWlBuffer::initTexture(uint32_t plane, QOpenGLTexture *texture)
{
    QMutexLocker locker(&m_texturesLock);

    Q_ASSERT(plane < m_planesNumber);
    Q_ASSERT(m_textures.at(plane) == nullptr);
    Q_ASSERT(QOpenGLContext::currentContext());
    m_textures[plane] = texture;
    m_texturesContext[plane] = QOpenGLContext::currentContext();

    m_texturesAboutToBeDestroyedConnection[plane] =
            QObject::connect(m_texturesContext[plane], &QOpenGLContext::aboutToBeDestroyed,
                             m_texturesContext[plane], [this, plane]() {

        QMutexLocker locker(&this->m_texturesLock);

        // See above lock - there is a chance that this has already been removed from m_textures[plane]!
        // Furthermore, we can trust that all the rest (e.g. disconnect) has also been properly executed!
        if (this->m_textures[plane] == nullptr)
            return;

        delete this->m_textures[plane];

        qCDebug(qLcWaylandCompositorHardwareIntegration)
                << Q_FUNC_INFO
                << "texture deleted due to QOpenGLContext::aboutToBeDestroyed!"
                << "Pointer (now dead) was:" << (void*)(this->m_textures[plane])
                << "  Associated context (about to die too) is: " << (void*)(this->m_texturesContext[plane]);

        this->m_textures[plane] = nullptr;
        this->m_texturesContext[plane] = nullptr;

        QObject::disconnect(this->m_texturesAboutToBeDestroyedConnection[plane]);
        this->m_texturesAboutToBeDestroyedConnection[plane] = QMetaObject::Connection();

    }, Qt::DirectConnection);
}

void LinuxDmabufWlBuffer::buffer_destroy_resource(Resource *resource)
{
    // In most cases this is redundant, but for instance if a buffer has been created,
    // but not committed and the client disconnects, it is vital
    m_clientBufferIntegration->removeBuffer(resource->handle);
}

QT_END_NAMESPACE
