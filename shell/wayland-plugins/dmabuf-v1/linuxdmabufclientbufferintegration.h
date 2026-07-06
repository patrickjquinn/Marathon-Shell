// Copyright (C) 2018 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
// Qt-Security score:significant reason:default

#ifndef LINUXDMABUFCLIENTBUFFERINTEGRATION_H
#define LINUXDMABUFCLIENTBUFFERINTEGRATION_H

#include "linuxdmabuf.h"

#include <QtWaylandCompositor/private/qwlclientbufferintegration_p.h>
#include <QtWaylandCompositor/private/qwlclientbuffer_p.h>
#include <QtWaylandCompositor/private/qwayland-server-wayland.h>
#include <QtCore/QMutex>

#include <drm_fourcc.h>

QT_BEGIN_NAMESPACE

typedef EGLBoolean (EGLAPIENTRYP PFNEGLQUERYWAYLANDBUFFERWL_compat) (EGLDisplay dpy, struct wl_resource *buffer, EGLint attribute, EGLint *value);
typedef EGLBoolean (EGLAPIENTRYP PFNEGLQUERYDMABUFFORMATSEXTPROC) (EGLDisplay dpy, EGLint max_formats, EGLint *formats, EGLint *num_formats);
typedef EGLBoolean (EGLAPIENTRYP PFNEGLQUERYDMABUFMODIFIERSEXTPROC) (EGLDisplay dpy, EGLint format, EGLint max_modifiers, EGLuint64KHR *modifiers, EGLBoolean *external_only, EGLint *num_modifiers);

class LinuxDmabufClientBufferIntegrationPrivate;
class LinuxDmabufParams;
class LinuxDmabufClientBuffer;

// buffer conversion definitions to import YUV buffers
struct YuvPlaneConversion {
    EGLint format = DRM_FORMAT_YUYV;
    EGLint widthDivisor = 1;
    EGLint heightDivisor = 1;
    EGLint planeIndex = 0;
};
struct YuvFormatConversion {
    uint32_t inputPlanes = 1;
    uint32_t outputPlanes = 1;
    struct YuvPlaneConversion plane[LinuxDmabufWlBuffer::MaxDmabufPlanes];
};

class LinuxDmabufClientBufferIntegration : public QtWayland::ClientBufferIntegration
{
public:
    LinuxDmabufClientBufferIntegration(bool useLegacyVersion = false);
    ~LinuxDmabufClientBufferIntegration() override;

    void initializeHardware(struct ::wl_display *display) override;
    QtWayland::ClientBuffer *createBufferFor(wl_resource *resource) override;
    bool importBuffer(wl_resource *resource, LinuxDmabufWlBuffer *linuxDmabufBuffer);
    void removeBuffer(wl_resource *resource);
    void deleteImage(EGLImageKHR image);
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC gl_egl_image_target_texture_2d = nullptr;

private:
    Q_DISABLE_COPY(LinuxDmabufClientBufferIntegration)

    bool m_useLegacyVersion;

    PFNEGLBINDWAYLANDDISPLAYWL egl_bind_wayland_display = nullptr;
    PFNEGLUNBINDWAYLANDDISPLAYWL egl_unbind_wayland_display = nullptr;
    ::wl_display *m_wlDisplay = nullptr;
    bool m_displayBound = false;

    PFNEGLQUERYDISPLAYATTRIBEXTPROC egl_query_display_attrib = nullptr;
    PFNEGLQUERYDEVICESTRINGEXTPROC egl_query_device_string = nullptr;

    PFNEGLCREATEIMAGEKHRPROC egl_create_image = nullptr;
    PFNEGLDESTROYIMAGEKHRPROC egl_destroy_image = nullptr;
    PFNEGLQUERYDMABUFMODIFIERSEXTPROC egl_query_dmabuf_modifiers_ext = nullptr;
    PFNEGLQUERYDMABUFFORMATSEXTPROC egl_query_dmabuf_formats_ext = nullptr;

    bool initSimpleTexture(LinuxDmabufWlBuffer *dmabufBuffer);
    bool initYuvTexture(LinuxDmabufWlBuffer *dmabufBuffer);
    QList<uint32_t> supportedDrmFormats();
    QList<uint64_t> supportedDrmModifiers(uint32_t format);
    const char *drmDevice() const;

    EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;

    QHash<EGLint, YuvFormatConversion> m_yuvFormats;
    bool m_supportsDmabufModifiers = false;
    QHash<struct ::wl_resource *, LinuxDmabufWlBuffer *> m_importedBuffers;
    QScopedPointer<LinuxDmabuf> m_linuxDmabuf;
};

class LinuxDmabufClientBuffer : public QtWayland::ClientBuffer
{
public:
    ~LinuxDmabufClientBuffer() override;

    QWaylandBufferRef::BufferFormatEgl bufferFormatEgl() const override;
    QSize size() const override;
    QWaylandSurface::Origin origin() const override;
    QOpenGLTexture *toOpenGlTexture(int plane) override;

protected:
    void setDestroyed() override;

private:
    friend class LinuxDmabufClientBufferIntegration;
    friend class LinuxDmabufClientBufferIntegrationPrivate;

    LinuxDmabufClientBuffer(LinuxDmabufClientBufferIntegration* integration, wl_resource *bufferResource, LinuxDmabufWlBuffer *dmabufBuffer);

    LinuxDmabufWlBuffer *d = nullptr;
    LinuxDmabufClientBufferIntegration *m_integration = nullptr;
};

QT_END_NAMESPACE

#endif // LINUXDMABUFCLIENTBUFFERINTEGRATION_H
