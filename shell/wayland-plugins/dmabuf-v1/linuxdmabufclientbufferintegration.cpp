// Copyright (C) 2018 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
// Qt-Security score:significant reason:default

#include "linuxdmabufclientbufferintegration.h"
#include "linuxdmabuf.h"

#include <QtWaylandCompositor/QWaylandCompositor>
#include <QtWaylandCompositor/private/qwayland-server-wayland.h>
#include <QtWaylandCompositor/private/qwltextureorphanage_p.h>
#include <qpa/qplatformnativeinterface.h>
#include <QtOpenGL/QOpenGLTexture>
#include <QtCore/QVarLengthArray>
#include <QtGui/QGuiApplication>
#include <QtGui/QOpenGLContext>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <unistd.h>
#include <drm_fourcc.h>
#include <cstdio>

QT_BEGIN_NAMESPACE

static QWaylandBufferRef::BufferFormatEgl formatFromDrmFormat(EGLint format) {
    switch (format) {
    case DRM_FORMAT_RGB332:
    case DRM_FORMAT_BGR233:
    case DRM_FORMAT_XRGB4444:
    case DRM_FORMAT_XBGR4444:
    case DRM_FORMAT_RGBX4444:
    case DRM_FORMAT_BGRX4444:
    case DRM_FORMAT_XRGB1555:
    case DRM_FORMAT_XBGR1555:
    case DRM_FORMAT_RGBX5551:
    case DRM_FORMAT_BGRX5551:
    case DRM_FORMAT_RGB565:
    case DRM_FORMAT_BGR565:
    case DRM_FORMAT_RGB888:
    case DRM_FORMAT_BGR888:
    case DRM_FORMAT_XRGB8888:
    case DRM_FORMAT_XBGR8888:
    case DRM_FORMAT_RGBX8888:
    case DRM_FORMAT_BGRX8888:
    case DRM_FORMAT_XRGB2101010:
    case DRM_FORMAT_XBGR2101010:
    case DRM_FORMAT_RGBX1010102:
    case DRM_FORMAT_BGRX1010102:
        return QWaylandBufferRef::BufferFormatEgl_RGB;
    case DRM_FORMAT_ARGB4444:
    case DRM_FORMAT_ABGR4444:
    case DRM_FORMAT_RGBA4444:
    case DRM_FORMAT_BGRA4444:
    case DRM_FORMAT_ARGB1555:
    case DRM_FORMAT_ABGR1555:
    case DRM_FORMAT_RGBA5551:
    case DRM_FORMAT_BGRA5551:
    case DRM_FORMAT_ARGB8888:
    case DRM_FORMAT_ABGR8888:
    case DRM_FORMAT_RGBA8888:
    case DRM_FORMAT_BGRA8888:
    case DRM_FORMAT_ARGB2101010:
    case DRM_FORMAT_ABGR2101010:
    case DRM_FORMAT_RGBA1010102:
    case DRM_FORMAT_BGRA1010102:
        return QWaylandBufferRef::BufferFormatEgl_RGBA;
    case DRM_FORMAT_YUYV:
        return QWaylandBufferRef::BufferFormatEgl_Y_XUXV;
    default:
        qCDebug(qLcWaylandCompositorHardwareIntegration) << "Buffer format" << Qt::hex << format << "not supported";
        return QWaylandBufferRef::BufferFormatEgl_Null;
    }
}

static QOpenGLTexture::TextureFormat openGLFormatFromBufferFormat(QWaylandBufferRef::BufferFormatEgl format) {
    switch (format) {
    case QWaylandBufferRef::BufferFormatEgl_RGB:
        return QOpenGLTexture::RGBFormat;
    case QWaylandBufferRef::BufferFormatEgl_RGBA:
        return QOpenGLTexture::RGBAFormat;
    default:
        return QOpenGLTexture::NoFormat;
    }
}

// Initialize the EGLImage for a dmabuf buffer which conceptually consists of a
// single plane. Note that depending on the modifiers, the buffer may be actually
// transported as multiple dmabuf planes which must be combined into a single
// EGLImage. For formats where the buffer needs to be represented as multiple
// EGLImages (e.g., various YUV formats) a different approach is required.
bool LinuxDmabufClientBufferIntegration::initSimpleTexture(LinuxDmabufWlBuffer *dmabufBuffer)
{
    bool success = true;

    // Resolving GL functions may need a context current, so do it only here.
    if (!gl_egl_image_target_texture_2d)
        gl_egl_image_target_texture_2d = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(eglGetProcAddress("glEGLImageTargetTexture2DOES"));

    if (dmabufBuffer->plane(0).modifiers != DRM_FORMAT_MOD_INVALID && !m_supportsDmabufModifiers) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Buffer uses dmabuf modifiers, which are not supported.";
        success = false;
    }

    // 6 entries for the common attribs plus 10 per possible plane, plus 1 for
    // the final EGL_NONE sentinel.
    QVarLengthArray<EGLint, 6 + 10 * 4 + 1> attribs;

    attribs.append(EGL_WIDTH);
    attribs.append(dmabufBuffer->size().width());
    attribs.append(EGL_HEIGHT);
    attribs.append(dmabufBuffer->size().height());
    attribs.append(EGL_LINUX_DRM_FOURCC_EXT);
    attribs.append(EGLint(dmabufBuffer->drmFormat()));

#define ADD_PLANE_ATTRIBS(plane_idx) { \
    attribs.append(EGL_DMA_BUF_PLANE ## plane_idx ## _FD_EXT); \
    attribs.append(dmabufBuffer->plane(plane_idx).fd); \
    attribs.append(EGL_DMA_BUF_PLANE ## plane_idx ## _OFFSET_EXT); \
    attribs.append(EGLint(dmabufBuffer->plane(plane_idx).offset)); \
    attribs.append(EGL_DMA_BUF_PLANE ## plane_idx ## _PITCH_EXT); \
    attribs.append(EGLint(dmabufBuffer->plane(plane_idx).stride)); \
    if (dmabufBuffer->plane(plane_idx).modifiers != DRM_FORMAT_MOD_INVALID) { \
        attribs.append(EGL_DMA_BUF_PLANE ## plane_idx ## _MODIFIER_LO_EXT); \
        attribs.append(EGLint(dmabufBuffer->plane(plane_idx).modifiers & 0xffffffff)); \
        attribs.append(EGL_DMA_BUF_PLANE ## plane_idx ## _MODIFIER_HI_EXT); \
        attribs.append(EGLint(dmabufBuffer->plane(plane_idx).modifiers >> 32)); \
    } \
}

    switch (dmabufBuffer->planesNumber()) {
    case 4:
        ADD_PLANE_ATTRIBS(3);
        Q_FALLTHROUGH();
    case 3:
        ADD_PLANE_ATTRIBS(2);
        Q_FALLTHROUGH();
    case 2:
        ADD_PLANE_ATTRIBS(1);
        Q_FALLTHROUGH();
    case 1:
        ADD_PLANE_ATTRIBS(0);
        break;
    default:
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Buffer uses invalid number of planes:" << dmabufBuffer->planesNumber();
        return false;
    }

    attribs.append(EGL_NONE);

    // note: EGLImageKHR does NOT take ownership of the file descriptors
    EGLImageKHR image = egl_create_image(m_eglDisplay,
                                         EGL_NO_CONTEXT,
                                         EGL_LINUX_DMA_BUF_EXT,
                                         (EGLClientBuffer) nullptr,
                                         attribs.constData());

    if (image == EGL_NO_IMAGE_KHR) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "failed to create EGL image from" <<
            dmabufBuffer->planesNumber() << "plane(s)";
        success = false;
    }

    dmabufBuffer->initImage(0, image);

    return success;
}

bool LinuxDmabufClientBufferIntegration::initYuvTexture(LinuxDmabufWlBuffer *dmabufBuffer)
{
    bool success = true;

    const YuvFormatConversion conversion = m_yuvFormats.value(dmabufBuffer->drmFormat());
    if (conversion.inputPlanes != dmabufBuffer->planesNumber()) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Buffer for this format must provide" << conversion.inputPlanes
                                                           << "planes but only" << dmabufBuffer->planesNumber() << "received";
        return false;
    }

    // Resolving GL functions may need a context current, so do it only here.
    if (!gl_egl_image_target_texture_2d)
        gl_egl_image_target_texture_2d = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(eglGetProcAddress("glEGLImageTargetTexture2DOES"));


    if (dmabufBuffer->plane(0).modifiers != DRM_FORMAT_MOD_INVALID && !m_supportsDmabufModifiers) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Buffer uses dmabuf modifiers, which are not supported.";
        success = false;
    }

    for (uint32_t i = 0; i < conversion.outputPlanes; ++i) {
        const YuvPlaneConversion plane = conversion.plane[i];

        QVarLengthArray<EGLint, 17> attribs = {
            EGL_WIDTH,                          dmabufBuffer->size().width() / plane.widthDivisor,
            EGL_HEIGHT,                         dmabufBuffer->size().height() / plane.heightDivisor,
            EGL_LINUX_DRM_FOURCC_EXT,           plane.format,
            EGL_DMA_BUF_PLANE0_FD_EXT,          dmabufBuffer->plane(plane.planeIndex).fd,
            EGL_DMA_BUF_PLANE0_OFFSET_EXT,      EGLint(dmabufBuffer->plane(plane.planeIndex).offset),
            EGL_DMA_BUF_PLANE0_PITCH_EXT,       EGLint(dmabufBuffer->plane(plane.planeIndex).stride),
            EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGLint(dmabufBuffer->plane(plane.planeIndex).modifiers & 0xffffffff),
            EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGLint(dmabufBuffer->plane(plane.planeIndex).modifiers >> 32),
            EGL_NONE
        };

        // note: EGLImageKHR does NOT take ownership of the file descriptors
        EGLImageKHR image = egl_create_image(m_eglDisplay,
                                             EGL_NO_CONTEXT,
                                             EGL_LINUX_DMA_BUF_EXT,
                                             (EGLClientBuffer) nullptr,
                                             attribs.constData());

        if (image == EGL_NO_IMAGE_KHR) {
            qCWarning(qLcWaylandCompositorHardwareIntegration) << "failed to create EGL image for plane" << i;
            success = false;
        }

        dmabufBuffer->initImage(i, image);
    }
    return success;
}

LinuxDmabufClientBufferIntegration::LinuxDmabufClientBufferIntegration(bool useLegacyVersion)
    : m_useLegacyVersion(useLegacyVersion)
{
    YuvPlaneConversion firstPlane;
    firstPlane.format = DRM_FORMAT_GR88;
    firstPlane.widthDivisor = 1;
    firstPlane.heightDivisor = 1;
    firstPlane.planeIndex = 0;

    YuvPlaneConversion secondPlane;
    secondPlane.format = DRM_FORMAT_ARGB8888;
    secondPlane.widthDivisor = 2;
    secondPlane.heightDivisor = 1;
    secondPlane.planeIndex = 0;

    YuvFormatConversion formatConversion;
    formatConversion.inputPlanes = 1;
    formatConversion.outputPlanes = 2;
    formatConversion.plane[0] = firstPlane;
    formatConversion.plane[1] = secondPlane;

    m_yuvFormats.insert(DRM_FORMAT_YUYV, formatConversion);
}

LinuxDmabufClientBufferIntegration::~LinuxDmabufClientBufferIntegration()
{
    m_importedBuffers.clear();

    if (m_useLegacyVersion) {
        if (egl_unbind_wayland_display != nullptr && m_displayBound) {
            Q_ASSERT(m_wlDisplay != nullptr);
            if (!egl_unbind_wayland_display(m_eglDisplay, m_wlDisplay))
                qCWarning(qLcWaylandCompositorHardwareIntegration)
                    << "eglUnbindWaylandDisplayWL failed";
        }
    }
}

void LinuxDmabufClientBufferIntegration::initializeHardware(struct ::wl_display *display)
{
    const int version = m_useLegacyVersion ? 3 : 4;
    m_linuxDmabuf.reset(new LinuxDmabuf(version, display, this));

    // Deliver main_device to clients up front, independent of the EGL probes
    // below. etnaviv's EGL lacks EGL_EXT_device_query and the dma_buf modifier
    // extension, so the original code early-returned here and never set the
    // device -> feedback carried no main_device -> Mesa clients (no wl_drm on
    // Mesa 26) could not find the render node and fell back to llvmpipe. Mirror
    // the proven vendored-stub behaviour: stat the render node and advertise it
    // regardless. drmDevice() falls back to MARATHON_DMABUF_MAIN_DEVICE /
    // renderD128 when the EGL query is unavailable.
    m_linuxDmabuf->setDrmDevice(drmDevice());
    fprintf(stderr, "[MDMABUF] init: early main_device=%s\n", drmDevice() ? drmDevice() : "(null)");

    // initialize hardware extensions
    egl_query_dmabuf_modifiers_ext = reinterpret_cast<PFNEGLQUERYDMABUFMODIFIERSEXTPROC>(eglGetProcAddress("eglQueryDmaBufModifiersEXT"));
    egl_query_dmabuf_formats_ext = reinterpret_cast<PFNEGLQUERYDMABUFFORMATSEXTPROC>(eglGetProcAddress("eglQueryDmaBufFormatsEXT"));
    if (!egl_query_dmabuf_modifiers_ext || !egl_query_dmabuf_formats_ext) {
        fprintf(stderr, "[MDMABUF] init RETURN: no eglQueryDmaBufModifiers/FormatsEXT (import disabled, feedback still active)\n");
        return;
    }

    if (m_useLegacyVersion) {
        const bool ignoreBindDisplay = !qgetenv("QT_WAYLAND_IGNORE_BIND_DISPLAY").isEmpty() && qgetenv("QT_WAYLAND_IGNORE_BIND_DISPLAY").toInt() != 0;

        egl_bind_wayland_display = reinterpret_cast<PFNEGLBINDWAYLANDDISPLAYWL>(eglGetProcAddress("eglBindWaylandDisplayWL"));
        egl_unbind_wayland_display = reinterpret_cast<PFNEGLUNBINDWAYLANDDISPLAYWL>(eglGetProcAddress("eglUnbindWaylandDisplayWL"));
        if ((!egl_bind_wayland_display || !egl_unbind_wayland_display) && !ignoreBindDisplay) {
            qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to initialize EGL display. Could not find eglBindWaylandDisplayWL and eglUnbindWaylandDisplayWL.";
            return;
        }
    } else {
        egl_query_display_attrib = reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(eglGetProcAddress("eglQueryDisplayAttribEXT"));
        egl_query_device_string = reinterpret_cast<PFNEGLQUERYDEVICESTRINGEXTPROC>(eglGetProcAddress("eglQueryDeviceStringEXT"));
        // Non-fatal on etnaviv: Vivante's EGL lacks EGL_EXT_device_query, so
        // these procs come back null. Buffer import (eglCreateImageKHR) does
        // NOT need them; only main_device discovery does, and drmDevice()
        // falls back to MARATHON_DMABUF_MAIN_DEVICE / renderD128 in that case.
        // Returning here would leave the whole integration dead (no import).
        if (!egl_query_display_attrib || !egl_query_device_string)
            qCWarning(qLcWaylandCompositorHardwareIntegration) << "eglQueryDisplayAttribEXT/eglQueryDeviceStringEXT unavailable; using fallback main_device.";
    }

    egl_create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
    egl_destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
    if (!egl_create_image || !egl_destroy_image) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to initialize EGL display. Could not find eglCreateImageKHR and eglDestroyImageKHR.";
        return;
    }

    // initialize EGL display
    QPlatformNativeInterface *nativeInterface = QGuiApplication::platformNativeInterface();
    if (!nativeInterface) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to initialize EGL display. No native platform interface available.";
        return;
    }

    m_eglDisplay = nativeInterface->nativeResourceForIntegration("EglDisplay");
    if (!m_eglDisplay) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to initialize EGL display. Could not get EglDisplay for window.";
        return;
    }

    const char *extensionString = eglQueryString(m_eglDisplay, EGL_EXTENSIONS);
    if (!extensionString || !strstr(extensionString, "EGL_EXT_image_dma_buf_import")) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to initialize EGL display. There is no EGL_EXT_image_dma_buf_import extension.";
        return;
    }
    if (strstr(extensionString, "EGL_EXT_image_dma_buf_import_modifiers"))
        m_supportsDmabufModifiers = true;

    if (m_useLegacyVersion && egl_bind_wayland_display && egl_unbind_wayland_display) {
        m_displayBound = egl_bind_wayland_display(m_eglDisplay, display);
        if (!m_displayBound)
            qCDebug(qLcWaylandCompositorHardwareIntegration) << "Wayland display already bound by other client buffer integration.";
        m_wlDisplay = display;
    }

    // request and sent formats/modifiers only after egl_display is bound
    QHash<uint32_t, QList<uint64_t>> modifiers;
    for (const auto &format : supportedDrmFormats()) {
        modifiers[format] = supportedDrmModifiers(format);
    }
    m_linuxDmabuf->setSupportedModifiers(modifiers);
    m_linuxDmabuf->setDrmDevice(drmDevice());
    fprintf(stderr, "[MDMABUF] init OK: import ready, main_device=%s, %d formats\n",
            drmDevice() ? drmDevice() : "(null)", int(modifiers.size()));
}

const char *LinuxDmabufClientBufferIntegration::drmDevice() const
{
    // Single-GPU fallback: when EGL can't report the render node (etnaviv EGL
    // has no EGL_EXT_device_query), still advertise a main_device so Mesa
    // clients can find the render node without the removed wl_drm global.
    // Otherwise the client's eglInitialize fails ("Failed to create context")
    // and every app drops to llvmpipe / aborts.
    static const char *fallback = []() -> const char * {
        const QByteArray env = qgetenv("MARATHON_DMABUF_MAIN_DEVICE");
        static QByteArray dev = env.isEmpty() ? QByteArray("/dev/dri/renderD128") : env;
        return dev.constData();
    }();

    if (!egl_query_device_string || !egl_query_display_attrib)
        return fallback;

    EGLAttrib attrib;
    if (!egl_query_display_attrib(m_eglDisplay, EGL_DEVICE_EXT, &attrib)) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to query EGL device; using fallback main_device" << fallback;
        return fallback;
    }

    EGLDeviceEXT eglDevice = reinterpret_cast<EGLDeviceEXT>(attrib);
    const char *ret = egl_query_device_string(eglDevice, EGL_DRM_RENDER_NODE_FILE_EXT);
    if (!ret)
        ret = egl_query_device_string(eglDevice, EGL_DRM_DEVICE_FILE_EXT);
    if (!ret) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "Failed to query DRM device; using fallback main_device" << fallback;
        ret = fallback;
    }

    return ret;
}

QList<uint32_t> LinuxDmabufClientBufferIntegration::supportedDrmFormats()
{
    if (!egl_query_dmabuf_formats_ext)
        return QList<uint32_t>();

    // request total number of formats
    EGLint count = 0;
    EGLBoolean success = egl_query_dmabuf_formats_ext(m_eglDisplay, 0, nullptr, &count);

    if (success && count > 0) {
        QList<uint32_t> drmFormats(count);
        if (egl_query_dmabuf_formats_ext(m_eglDisplay, count, (EGLint *) drmFormats.data(), &count))
            return drmFormats;
    }

    return QList<uint32_t>();
}

QList<uint64_t> LinuxDmabufClientBufferIntegration::supportedDrmModifiers(uint32_t format)
{
    if (!egl_query_dmabuf_modifiers_ext)
        return QList<uint64_t>();

    // request total number of formats
    EGLint count = 0;
    EGLBoolean success = egl_query_dmabuf_modifiers_ext(m_eglDisplay, format, 0, nullptr, nullptr, &count);

    if (success && count > 0) {
        QList<uint64_t> modifiers(count);
        if (egl_query_dmabuf_modifiers_ext(m_eglDisplay, format, count, modifiers.data(), nullptr, &count)) {
            return modifiers;
        }
    }

    return QList<uint64_t>();
}

void LinuxDmabufClientBufferIntegration::deleteImage(EGLImageKHR image)
{
    egl_destroy_image(m_eglDisplay, image);
}

QtWayland::ClientBuffer *LinuxDmabufClientBufferIntegration::createBufferFor(wl_resource *resource)
{
    auto it = m_importedBuffers.find(resource);
    if (it != m_importedBuffers.end())
        return new LinuxDmabufClientBuffer(this, resource, it.value());

    return nullptr;
}

bool LinuxDmabufClientBufferIntegration::importBuffer(wl_resource *resource, LinuxDmabufWlBuffer *linuxDmabufBuffer)
{
    if (m_importedBuffers.contains(resource)) {
        qCWarning(qLcWaylandCompositorHardwareIntegration) << "buffer has already been added";
        return false;
    }
    m_importedBuffers[resource] = linuxDmabufBuffer;
    if (m_yuvFormats.contains(linuxDmabufBuffer->drmFormat()))
        return initYuvTexture(linuxDmabufBuffer);
    else
        return initSimpleTexture(linuxDmabufBuffer);
}

void LinuxDmabufClientBufferIntegration::removeBuffer(wl_resource *resource)
{
    m_importedBuffers.remove(resource);
}

LinuxDmabufClientBuffer::LinuxDmabufClientBuffer(LinuxDmabufClientBufferIntegration *integration,
                                                 wl_resource *bufferResource,
                                                 LinuxDmabufWlBuffer *dmabufBuffer)
    : ClientBuffer(bufferResource)
    , m_integration(integration)
{
    d = dmabufBuffer;
}

QOpenGLTexture *LinuxDmabufClientBuffer::toOpenGlTexture(int plane)
{
    // At this point we should have a valid OpenGL context, so it's safe to destroy textures
    QtWayland::QWaylandTextureOrphanage::instance()->deleteTextures();

    if (!m_buffer)
        return nullptr;

    QOpenGLTexture *texture = d->texture(plane);

    const auto target = static_cast<QOpenGLTexture::Target>(GL_TEXTURE_2D);

    if (!texture) {
        texture = new QOpenGLTexture(target);
        texture->setFormat(openGLFormatFromBufferFormat(formatFromDrmFormat(d->drmFormat())));
        texture->setSize(d->size().width(), d->size().height());
        texture->create();
        d->initTexture(plane, texture);
    }

    if (m_textureDirty) {
        m_textureDirty = false;
        texture->bind();
        glTexParameterf(target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        m_integration->gl_egl_image_target_texture_2d(target, d->image(plane));
    }
    return texture;
}

void LinuxDmabufClientBuffer::setDestroyed()
{
    m_integration->removeBuffer(m_buffer);
    ClientBuffer::setDestroyed();
}

LinuxDmabufClientBuffer::~LinuxDmabufClientBuffer()
{
    m_buffer = nullptr;
    delete d;
}

QWaylandBufferRef::BufferFormatEgl LinuxDmabufClientBuffer::bufferFormatEgl() const
{
    return formatFromDrmFormat(d->drmFormat());
}

QSize LinuxDmabufClientBuffer::size() const
{
    return d->size();
}

QWaylandSurface::Origin LinuxDmabufClientBuffer::origin() const
{
    return (d->flags() & QtWaylandServer::zwp_linux_buffer_params_v1::flags_y_invert) ? QWaylandSurface::OriginBottomLeft : QWaylandSurface::OriginTopLeft;
}

QT_END_NAMESPACE
