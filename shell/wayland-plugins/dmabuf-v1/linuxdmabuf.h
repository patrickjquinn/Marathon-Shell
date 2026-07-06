// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
// Qt-Security score:critical reason:network-protocol

#ifndef LINUXDMABUF_H
#define LINUXDMABUF_H

#include "qwayland-server-linux-dmabuf-v1.h"

#include <QtWaylandCompositor/private/qwayland-server-wayland.h>
#include <QtWaylandCompositor/private/qwlclientbufferintegration_p.h>

#include <QtOpenGL/QOpenGLTexture>
#include <QtCore/QObject>
#include <QtCore/QHash>
#include <QtCore/QSize>
#include <QtCore/QTextStream>
#include <QtCore/QTemporaryFile>

#include <array>
#include <QtGui/QOpenGLContext>
#include <QtCore/QMutex>

#include <EGL/egl.h>
#include <EGL/eglext.h>

// compatibility with libdrm <= 2.4.74
#ifndef DRM_FORMAT_RESERVED
#define DRM_FORMAT_RESERVED           ((1ULL << 56) - 1)
#endif
#ifndef DRM_FORMAT_MOD_VENDOR_NONE
#define DRM_FORMAT_MOD_VENDOR_NONE    0
#endif
#ifndef DRM_FORMAT_MOD_LINEAR
#define DRM_FORMAT_MOD_LINEAR   fourcc_mod_code(NONE, 0)
#endif
#ifndef DRM_FORMAT_MOD_INVALID
#define DRM_FORMAT_MOD_INVALID  fourcc_mod_code(NONE, DRM_FORMAT_RESERVED)
#endif

#ifndef EGL_DRM_RENDER_NODE_FILE_EXT
#  define EGL_DRM_RENDER_NODE_FILE_EXT 0x3377
#endif

// Copied from eglmesaext.h
#ifndef EGL_WL_bind_wayland_display
typedef EGLBoolean (EGLAPIENTRYP PFNEGLBINDWAYLANDDISPLAYWL) (EGLDisplay dpy, struct wl_display *display);
typedef EGLBoolean (EGLAPIENTRYP PFNEGLUNBINDWAYLANDDISPLAYWL) (EGLDisplay dpy, struct wl_display *display);
#endif

QT_BEGIN_NAMESPACE

class QWaylandCompositor;
class QWaylandResource;
class LinuxDmabufParams;
class LinuxDmabufFeedback;
class LinuxDmabufClientBufferIntegration;

struct Plane {
    int fd = -1;
    uint32_t offset = 0;
    uint32_t stride = 0;
    uint64_t modifiers = 0;
};

class LinuxDmabuf : public QtWaylandServer::zwp_linux_dmabuf_v1
{
public:
    explicit LinuxDmabuf(int version,
                         wl_display *display,
                         LinuxDmabufClientBufferIntegration *clientBufferIntegration);

    void setSupportedModifiers(const QHash<uint32_t, QList<uint64_t>> &modifiers);
    void setDrmDevice(const char *drmDevice);

protected:
    void zwp_linux_dmabuf_v1_bind_resource(Resource *resource) override;
    void zwp_linux_dmabuf_v1_create_params(Resource *resource, uint32_t params_id) override;
    void zwp_linux_dmabuf_v1_get_default_feedback(Resource *resource, uint32_t id) override;
    void zwp_linux_dmabuf_v1_get_surface_feedback(Resource *resource, uint32_t id, struct ::wl_resource *surface) override;

private:
    QHash<uint32_t, QList<uint64_t>> m_modifiers; // key=DRM format, value=supported DRM modifiers for format
    LinuxDmabufClientBufferIntegration *m_clientBufferIntegration = nullptr;
    const char *m_drmDevice = nullptr;
};

class LinuxDmabufFeedback : public QtWaylandServer::zwp_linux_dmabuf_feedback_v1
{
public:
    explicit LinuxDmabufFeedback(QHash<uint32_t, QList<uint64_t>> modifiers, const char *drmDevice,
                                 wl_resource *resource);
    ~LinuxDmabufFeedback() override;

protected:
    void zwp_linux_dmabuf_feedback_v1_bind_resource(Resource *resource) override;
    void zwp_linux_dmabuf_feedback_v1_destroy_resource(Resource *resource) override;
    void zwp_linux_dmabuf_feedback_v1_destroy(Resource *resource) override;

private:
    QByteArray sendFormatTable(Resource *resource);
    void sendFeedback(Resource *resource);
    QHash<uint32_t, QList<uint64_t>> m_modifiers;
    const char *m_drmDevice;
    uchar *m_data = nullptr;
    qsizetype m_size = 0;
};

class LinuxDmabufParams : public QtWaylandServer::zwp_linux_buffer_params_v1
{
public:
    explicit LinuxDmabufParams(LinuxDmabufClientBufferIntegration *clientBufferIntegration, wl_resource *resource);
    ~LinuxDmabufParams() override;

private:
    bool handleCreateParams(Resource *resource, int width, int height, uint format, uint flags);
    uint m_drmFormat = 0;
    uint m_flags = 0;
    QSize m_size;
    bool m_used = false;
    QMap<uint, Plane> m_planes;
    LinuxDmabufClientBufferIntegration *m_clientBufferIntegration;

protected:
    void zwp_linux_buffer_params_v1_destroy(Resource *resource) override;
    void zwp_linux_buffer_params_v1_add(Resource *resource, int32_t fd, uint32_t plane_idx, uint32_t offset, uint32_t stride, uint32_t modifier_hi, uint32_t modifier_lo) override;
    void zwp_linux_buffer_params_v1_create(Resource *resource, int32_t width, int32_t height, uint32_t format, uint32_t flags) override;
    void zwp_linux_buffer_params_v1_create_immed(Resource *resource, uint32_t buffer_id, int32_t width, int32_t height, uint32_t format, uint32_t flags) override;
    void zwp_linux_buffer_params_v1_destroy_resource(Resource *resource) override;

    friend class LinuxDmabufClientBufferIntegrationPrivate;
};

class LinuxDmabufWlBuffer : public QtWaylandServer::wl_buffer
{
public:
    explicit LinuxDmabufWlBuffer(::wl_client *client, LinuxDmabufClientBufferIntegration *clientBufferIntegration, uint id = 0);
    ~LinuxDmabufWlBuffer() override;

    void initImage(uint32_t plane, EGLImageKHR image);
    void initTexture(uint32_t plane, QOpenGLTexture *texture);
    inline QSize size() const { return m_size; }
    inline uint32_t flags() const { return m_flags; }
    inline uint32_t drmFormat() const { return m_drmFormat; }
    inline Plane& plane(uint index) { return m_planes.at(index); }
    inline uint32_t planesNumber() const { return m_planesNumber; }
    inline EGLImageKHR image(uint32_t plane) { return m_eglImages.at(plane); }
    inline QOpenGLTexture *texture(uint32_t plane) const { return m_textures.at(plane); }
    void buffer_destroy_resource(Resource *resource) override;

    static const uint32_t MaxDmabufPlanes = 4;

private:
    QSize m_size;
    uint32_t m_flags = 0;
    uint32_t m_drmFormat = EGL_TEXTURE_RGBA;
    std::array<Plane, MaxDmabufPlanes> m_planes;
    uint32_t m_planesNumber = 1;
    LinuxDmabufClientBufferIntegration *m_clientBufferIntegration = nullptr;
    std::array<EGLImageKHR, MaxDmabufPlanes> m_eglImages = { {EGL_NO_IMAGE_KHR, EGL_NO_IMAGE_KHR, EGL_NO_IMAGE_KHR, EGL_NO_IMAGE_KHR} };
    std::array<QOpenGLTexture *, MaxDmabufPlanes> m_textures = { {nullptr, nullptr, nullptr, nullptr} };
    std::array<QOpenGLContext *, MaxDmabufPlanes> m_texturesContext = { {nullptr, nullptr, nullptr, nullptr} };
    std::array<QMetaObject::Connection, MaxDmabufPlanes> m_texturesAboutToBeDestroyedConnection = { {QMetaObject::Connection(), QMetaObject::Connection(), QMetaObject::Connection(), QMetaObject::Connection()} };
    QMutex m_texturesLock;

    void buffer_destroy(Resource *resource) override;
    void deleteTextures();

    friend class LinuxDmabufParams;
};

QT_END_NAMESPACE

#endif // LINUXDMABUF_H
