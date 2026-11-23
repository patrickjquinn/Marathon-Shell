// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// See directsurface.h.

#include "directsurface.h"

#include <QByteArray>
#include <QGuiApplication>
#include <QWindow>
#include <qpa/qplatformnativeinterface.h>
#include <qpa/qplatformwindow_p.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include <wayland-server-core.h>
#include <wpe/fdo-egl.h>

#include <dlfcn.h>
#include <climits>
#include <cstddef>
#include <cstring>
#include <utility>

struct DirectSurface::Forwarded {
    DirectSurface                     *owner    = nullptr;
    wl_resource                       *resource = nullptr; // WebKit's buffer, in our server
    wl_buffer                         *buffer   = nullptr; // the same gralloc buffer, at Lipstick
    struct wpe_fdo_egl_exported_image *image    = nullptr;
    bool                               busy    = false; // attached and not released by Lipstick yet
    bool                               dropped = false; // the owner is done with image
    wl_listener                        destroyListener{};
};

namespace {

    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC s_imageTarget = nullptr;

    // Off screen, but still a valid position: Lipstick cannot put the subsurface
    // below the window's own content, so hiding it means moving it away.
    constexpr int kOffscreen = 100000;

    void registryGlobal(void *data, wl_registry *registry, uint32_t name, const char *interface,
                        uint32_t) {
        static_cast<DirectSurface *>(data)->onRegistryGlobal(registry, name, interface);
    }
    void                       registryGlobalRemove(void *, wl_registry *, uint32_t) {}
    const wl_registry_listener s_registryListener = {registryGlobal, registryGlobalRemove};

    void                       frameDone(void *data, wl_callback *, uint32_t) {
        static_cast<DirectSurface *>(data)->onFrameDone();
    }
    const wl_callback_listener s_frameListener = {frameDone};

    // libhybris's android_wlegl protocol (wayland-android.xml), the requests a
    // client needs to share a gralloc buffer, as wayland-scanner would write them.
    // android_wlegl_handle's requests carry no objects; android_wlegl's refer to
    // it, so it comes first.
    const wl_interface *s_wleglNoTypes[]        = {nullptr};
    const wl_message    s_wleglHandleRequests[] = {
        {"add_fd", "h", s_wleglNoTypes},
        {"destroy", "", s_wleglNoTypes},
    };
    const wl_interface  s_wleglHandleInterface = {"android_wlegl_handle", 1, 2,
                                                  s_wleglHandleRequests,  0, nullptr};
    const wl_interface *s_wleglTypes[]         = {
        &s_wleglHandleInterface,
        nullptr,
        nullptr,
        &wl_buffer_interface,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        &s_wleglHandleInterface,
    };
    const wl_message s_wleglRequests[] = {
        {"create_handle", "nia", s_wleglTypes},
        {"create_buffer", "niiiiio", s_wleglTypes + 3},
    };
    const wl_interface s_wleglInterface = {"android_wlegl", 1, 2, s_wleglRequests, 0, nullptr};

    // WPEBackend-fdo 1.16/1.17's wpe_fdo_egl_exported_image
    // (view-backend-exportable-fdo-egl-private.h), as far as the buffer.
    struct ExportedImageLayout {
        void        *eglImage;
        uint32_t     width;
        uint32_t     height;
        bool         exported;
        wl_resource *bufferResource;
    };
    // libhybris's server_wlegl_buffer: the resource, then its RemoteWindowBuffer,
    // whose ANativeWindowBuffer follows a vtable pointer.
    struct ServerBufferLayout {
        wl_resource *resource;
        void        *wlegl;
        void        *buffer;
    };
    struct NativeHandle {
        int version;
        int numFds;
        int numInts;
        int data[1];
    };
    // Android's ANativeWindowBuffer (64-bit; the handle is at the same place in
    // the layouts before and after usage became 64 bits).
    struct NativeBufferLayout {
        int                 magic;
        int                 version;
        void               *reserved[4];
        void               *incRef;
        void               *decRef;
        int                 width;
        int                 height;
        int                 stride;
        int                 format;
        int                 usage;
        uintptr_t           layerCount;
        void               *reserved2;
        const NativeHandle *handle;
        uint64_t            usage64;
    };
    static_assert(sizeof(void *) != 8 || offsetof(NativeBufferLayout, handle) == 96,
                  "ANativeWindowBuffer layout");
    constexpr int kNativeBufferMagic = ('_' << 24) | ('b' << 16) | ('f' << 8) | 'r';

    // The exported image's buffer, when the private layout matches the public
    // getters.
    wl_resource *bufferResourceOf(struct wpe_fdo_egl_exported_image *image) {
        auto *layout = reinterpret_cast<const ExportedImageLayout *>(image);
        if (layout->eglImage != wpe_fdo_egl_exported_image_get_egl_image(image) ||
            layout->width != wpe_fdo_egl_exported_image_get_width(image) ||
            layout->height != wpe_fdo_egl_exported_image_get_height(image) ||
            !layout->bufferResource)
            return nullptr;
        const char *cls = wl_resource_get_class(layout->bufferResource);
        return cls && !strcmp(cls, "wl_buffer") ? layout->bufferResource : nullptr;
    }

    // The gralloc buffer behind a libhybris wl_buffer of the given size.
    const NativeBufferLayout *nativeBufferOf(wl_resource *resource, uint32_t width,
                                             uint32_t height) {
        auto *server = static_cast<const ServerBufferLayout *>(wl_resource_get_user_data(resource));
        if (!server || server->resource != resource || !server->buffer)
            return nullptr;
        for (size_t offset : {sizeof(void *), static_cast<size_t>(0)}) {
            auto *buffer = reinterpret_cast<const NativeBufferLayout *>(
                static_cast<const char *>(server->buffer) + offset);
            if (buffer->magic == kNativeBufferMagic &&
                static_cast<uint32_t>(buffer->width) == width &&
                static_cast<uint32_t>(buffer->height) == height && buffer->handle &&
                buffer->handle->numFds > 0 && buffer->handle->numFds <= 16 &&
                buffer->handle->numInts >= 0 && buffer->handle->numInts <= 1024)
                return buffer;
        }
        return nullptr;
    }

    void bufferReleased(void *data, wl_buffer *) {
        auto *forwarded = static_cast<DirectSurface::Forwarded *>(data);
        forwarded->owner->onBufferReleased(forwarded);
    }

    const wl_buffer_listener s_bufferListener = {bufferReleased};

    void                     resourceDestroyed(wl_listener *listener, void *) {
        auto *forwarded = reinterpret_cast<DirectSurface::Forwarded *>(
            reinterpret_cast<char *>(listener) -
            offsetof(DirectSurface::Forwarded, destroyListener));
        forwarded->owner->onResourceDestroyed(forwarded);
    }

    bool attachWanted() {
        static const bool on = qgetenv("PACIFIC_DIRECT_ATTACH") != "0";
        return on;
    }

    bool hybrisLoaded() {
        void *lib = dlopen("libhybris-common.so.1", RTLD_NOW | RTLD_NOLOAD);
        if (lib)
            dlclose(lib);
        return lib;
    }

    GLuint compile(GLenum type, const char *source) {
        GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &source, nullptr);
        glCompileShader(shader);
        return shader;
    }

} // namespace

bool DirectSurface::enabled() {
    static const bool on = qgetenv("PACIFIC_DIRECT") != "0";
    return on;
}

DirectSurface::DirectSurface(std::function<void()>                                    frameDone,
                             std::function<void(struct wpe_fdo_egl_exported_image *)> releaseImage)
    : m_frameDone(std::move(frameDone))
    , m_releaseImage(std::move(releaseImage)) {}

DirectSurface::~DirectSurface() {
    QObject::disconnect(m_parentDestroyed);
    destroy();
}

void DirectSurface::onRegistryGlobal(void *registry, uint32_t name, const char *interface) {
    auto *r = static_cast<wl_registry *>(registry);
    if (!strcmp(interface, "wl_compositor"))
        m_compositor =
            static_cast<wl_compositor *>(wl_registry_bind(r, name, &wl_compositor_interface, 1));
    else if (!strcmp(interface, "wl_subcompositor"))
        m_subcompositor = static_cast<wl_subcompositor *>(
            wl_registry_bind(r, name, &wl_subcompositor_interface, 1));
    else if (!strcmp(interface, "android_wlegl") && attachWanted())
        m_wlegl = static_cast<wl_proxy *>(wl_registry_bind(r, name, &s_wleglInterface, 1));
}

bool DirectSurface::bindGlobals() {
    // A private queue for the round trip, so Qt's own dispatching is untouched.
    wl_event_queue *queue = wl_display_create_queue(m_display);
    if (!queue)
        return false;
    wl_registry *registry = wl_display_get_registry(m_display);
    wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(registry), queue);
    wl_registry_add_listener(registry, &s_registryListener, this);
    wl_display_roundtrip_queue(m_display, queue);
    if (m_compositor)
        wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(m_compositor), nullptr);
    if (m_subcompositor)
        wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(m_subcompositor), nullptr);
    if (m_wlegl)
        wl_proxy_set_queue(m_wlegl, nullptr);
    wl_registry_destroy(registry);
    wl_event_queue_destroy(queue);
    return m_compositor && m_subcompositor;
}

bool DirectSurface::setupGl() {
    EGLDisplay display = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(m_display));
    if (display == EGL_NO_DISPLAY)
        return false;
    eglInitialize(display, nullptr, nullptr); // reference counted; Qt initialised it
    eglBindAPI(EGL_OPENGL_ES_API);
    m_eglDisplay = display;

    const EGLint configAttribs[] = {EGL_SURFACE_TYPE,
                                    EGL_WINDOW_BIT,
                                    EGL_RENDERABLE_TYPE,
                                    EGL_OPENGL_ES2_BIT,
                                    EGL_RED_SIZE,
                                    8,
                                    EGL_GREEN_SIZE,
                                    8,
                                    EGL_BLUE_SIZE,
                                    8,
                                    EGL_ALPHA_SIZE,
                                    0,
                                    EGL_NONE};
    EGLConfig    config          = nullptr;
    EGLint       count           = 0;
    if (!eglChooseConfig(display, configAttribs, &config, 1, &count) || count < 1)
        return false;
    const EGLint contextAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext   context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
    if (context == EGL_NO_CONTEXT)
        return false;
    m_eglContext = context;

    m_eglWindow =
        wl_egl_window_create(m_surface, qMax(1, m_geometry.width()), qMax(1, m_geometry.height()));
    if (!m_eglWindow)
        return false;
    EGLSurface surface = eglCreateWindowSurface(
        display, config, reinterpret_cast<EGLNativeWindowType>(m_eglWindow), nullptr);
    if (surface == EGL_NO_SURFACE)
        return false;
    m_eglSurface = surface;

    EGLDisplay previousDisplay = eglGetCurrentDisplay();
    EGLContext previousContext = eglGetCurrentContext();
    EGLSurface previousDraw    = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface previousRead    = eglGetCurrentSurface(EGL_READ);
    if (!eglMakeCurrent(display, surface, surface, context))
        return false;
    // Pacing comes from the frame callback, not from swapping.
    eglSwapInterval(display, 0);
    if (!s_imageTarget)
        s_imageTarget = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
            eglGetProcAddress("glEGLImageTargetTexture2DOES"));

    static const char *vertex = "attribute vec2 pos;\n"
                                "attribute vec2 tex;\n"
                                "varying vec2 v;\n"
                                "void main() { v = tex; gl_Position = vec4(pos, 0.0, 1.0); }\n";
    static const char *fragment =
        "precision mediump float;\n"
        "uniform sampler2D s;\n"
        "varying vec2 v;\n"
        "void main() { gl_FragColor = vec4(texture2D(s, v).rgb, 1.0); }\n";
    m_program = glCreateProgram();
    glAttachShader(m_program, compile(GL_VERTEX_SHADER, vertex));
    glAttachShader(m_program, compile(GL_FRAGMENT_SHADER, fragment));
    glBindAttribLocation(m_program, 0, "pos");
    glBindAttribLocation(m_program, 1, "tex");
    glLinkProgram(m_program);
    m_sampler = glGetUniformLocation(m_program, "s");

    if (previousContext != EGL_NO_CONTEXT)
        eglMakeCurrent(previousDisplay, previousDraw, previousRead, previousContext);
    else
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    return s_imageTarget && m_program;
}

bool DirectSurface::ensureCreated(QWindow *window) {
    if (m_valid || m_attempted || !window)
        return m_valid;
    m_attempted                      = true;
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (!native)
        return false;
    auto *waylandWindow = window->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
    m_display           = static_cast<wl_display *>(
        native->nativeResourceForIntegration(QByteArrayLiteral("wl_display")));
    m_parent = waylandWindow ? waylandWindow->surface() : nullptr;
    if (!m_display || !m_parent || !bindGlobals()) {
        qWarning("Pacific direct: no Wayland subsurfaces here; frames go through Qt");
        destroy();
        return false;
    }
    m_surface    = wl_compositor_create_surface(m_compositor);
    m_subsurface = wl_subcompositor_get_subsurface(m_subcompositor, m_surface, m_parent);
    if (wl_region *none = wl_compositor_create_region(m_compositor)) {
        wl_surface_set_input_region(m_surface, none);
        wl_region_destroy(none);
    }
    wl_subsurface_set_desync(m_subsurface);
    // Zero copy is tried on the first frame; GL is set up now only when it
    // cannot be.
    if (!m_wlegl || !hybrisLoaded())
        m_mode = Mode::Gl;
    if (m_mode == Mode::Gl && !setupGl()) {
        qWarning("Pacific direct: EGL setup failed; frames go through Qt");
        destroy();
        return false;
    }
    // Qt destroys the window's wl_surface with the window (an accepted close
    // does, before the items go): the subsurface goes too, and frames stay on
    // Qt's path.
    m_parentDestroyed = QObject::connect(
        waylandWindow, &QNativeInterface::Private::QWaylandWindow::surfaceDestroyed, waylandWindow,
        [this] {
            destroy();
            m_parent = nullptr;
        });
    m_valid   = true;
    m_applied = m_geometry;
    applyPosition();
    commitParent();
    qInfo("Pacific direct: web frames on a subsurface (%dx%d)", m_geometry.width(),
          m_geometry.height());
    return true;
}

void DirectSurface::setGeometry(const QRect &rect) {
    m_geometry = rect;
    if (!m_valid || rect == m_applied)
        return;
    if (m_eglWindow && rect.width() > 0 && rect.height() > 0)
        wl_egl_window_resize(m_eglWindow, rect.width(), rect.height(), 0, 0);
    m_applied = rect;
    applyPosition();
    commitParent();
}

void DirectSurface::setShown(bool shown) {
    if (!m_valid || shown == m_shown)
        return;
    m_shown = shown;
    if (!shown)
        m_dropTextures = true;
    // Hidden, the subsurface would keep one of WebKit's buffers from it while
    // Qt draws the page: Lipstick gives it back once nothing is attached.
    // Shown again, the owner presents its newest frame.
    if (!shown && m_mode == Mode::Attach) {
        wl_surface_attach(m_surface, nullptr, 0, 0);
        wl_surface_commit(m_surface);
    }
    applyPosition();
    commitParent();
}

void DirectSurface::applyPosition() {
    if (m_subsurface)
        wl_subsurface_set_position(m_subsurface, m_applied.x(),
                                   m_applied.y() + (m_shown ? 0 : kOffscreen));
}

void DirectSurface::commitParent() {
    // Subsurface position is parent state: it applies on the parent's commit.
    if (!m_parent)
        return;
    wl_surface_commit(m_parent);
    wl_display_flush(m_display);
}

void DirectSurface::present(struct wpe_fdo_egl_exported_image *image) {
    if (!m_valid || !image)
        return;
    if (m_mode != Mode::Gl && presentAttached(image)) {
        if (m_mode == Mode::Unknown)
            qInfo("Pacific direct: WebKit's buffers go to the compositor as they are");
        m_mode = Mode::Attach;
        return;
    }
    if (m_mode == Mode::Attach) {
        // A buffer that cannot be forwarded after others were: drop this frame
        // rather than mix GL's buffers into the surface.
        qWarning("Pacific direct: a frame could not be forwarded");
        return;
    }
    if (m_mode == Mode::Unknown) {
        m_mode = Mode::Gl;
        qInfo("Pacific direct: WebKit's buffers cannot be forwarded; frames are copied with GL");
        if (!setupGl()) {
            qWarning("Pacific direct: EGL setup failed");
            return;
        }
    }
    presentGl(image);
}

bool DirectSurface::presentAttached(struct wpe_fdo_egl_exported_image *image) {
    Forwarded *forwarded = forward(image);
    if (!forwarded)
        return false;
    forwarded->image   = image;
    forwarded->busy    = true;
    forwarded->dropped = false;
    wl_surface_attach(m_surface, forwarded->buffer, 0, 0);
    wl_surface_damage(m_surface, 0, 0, INT32_MAX, INT32_MAX);
    // The next frame waits for the compositor to have used this one.
    if (!m_frameCallback) {
        m_frameCallback = wl_surface_frame(m_surface);
        wl_callback_add_listener(m_frameCallback, &s_frameListener, this);
    }
    wl_surface_commit(m_surface);
    wl_display_flush(m_display);
    return true;
}

// WebKit draws into a few buffers in turn: each is made known to Lipstick
// once, with the same gralloc handle (android_wlegl, as libhybris's own
// Wayland EGL platform does), and forgotten when WebKit destroys it.
DirectSurface::Forwarded *DirectSurface::forward(struct wpe_fdo_egl_exported_image *image) {
    if (!m_wlegl)
        return nullptr;
    wl_resource *resource = bufferResourceOf(image);
    if (!resource)
        return nullptr;
    for (auto &forwarded : m_forwarded) {
        if (forwarded->resource == resource)
            return forwarded.get();
    }
    const NativeBufferLayout *native =
        nativeBufferOf(resource, wpe_fdo_egl_exported_image_get_width(image),
                       wpe_fdo_egl_exported_image_get_height(image));
    if (!native)
        return nullptr;
    const NativeHandle *handle = native->handle;
    wl_array            ints{};
    wl_array_init(&ints);
    if (handle->numInts) {
        void *data = wl_array_add(&ints, handle->numInts * sizeof(int));
        memcpy(data, handle->data + handle->numFds, handle->numInts * sizeof(int));
    }
    wl_proxy *wleglHandle = wl_proxy_marshal_constructor(m_wlegl, 0, &s_wleglHandleInterface,
                                                         nullptr, handle->numFds, &ints);
    wl_array_release(&ints);
    if (!wleglHandle)
        return nullptr;
    for (int i = 0; i < handle->numFds; i++)
        wl_proxy_marshal(wleglHandle, 0, handle->data[i]);
    const int usage  = native->usage64 && native->usage64 <= UINT32_MAX ?
        static_cast<int>(native->usage64) :
        native->usage;
    auto     *buffer = reinterpret_cast<wl_buffer *>(wl_proxy_marshal_constructor(
        m_wlegl, 1, &wl_buffer_interface, nullptr, native->width, native->height, native->stride,
        native->format, usage, wleglHandle));
    wl_proxy_marshal(wleglHandle, 1);
    wl_proxy_destroy(wleglHandle);
    if (!buffer)
        return nullptr;

    auto forwarded      = std::make_unique<Forwarded>();
    forwarded->owner    = this;
    forwarded->resource = resource;
    forwarded->buffer   = buffer;
    wl_buffer_add_listener(buffer, &s_bufferListener, forwarded.get());
    forwarded->destroyListener.notify = resourceDestroyed;
    wl_resource_add_destroy_listener(resource, &forwarded->destroyListener);
    m_forwarded.push_back(std::move(forwarded));
    return m_forwarded.back().get();
}

bool DirectSurface::deferRelease(struct wpe_fdo_egl_exported_image *image) {
    for (auto &forwarded : m_forwarded) {
        if (forwarded->image != image)
            continue;
        if (forwarded->busy) {
            forwarded->dropped = true;
            return true;
        }
        forwarded->image = nullptr;
        return false;
    }
    return false;
}

void DirectSurface::onBufferReleased(Forwarded *forwarded) {
    forwarded->busy = false;
    if (forwarded->dropped) {
        forwarded->dropped = false;
        if (auto *image = std::exchange(forwarded->image, nullptr))
            m_releaseImage(image);
    }
}

// WebKit destroyed the buffer (a new size): Lipstick keeps its own reference
// to the gralloc buffer for as long as it shows it.
void DirectSurface::onResourceDestroyed(Forwarded *forwarded) {
    wl_list_remove(&forwarded->destroyListener.link);
    wl_buffer_destroy(forwarded->buffer);
    if (forwarded->dropped && forwarded->image)
        m_releaseImage(forwarded->image);
    for (auto it = m_forwarded.begin(); it != m_forwarded.end(); ++it) {
        if (it->get() == forwarded) {
            m_forwarded.erase(it);
            break;
        }
    }
}

void DirectSurface::dropForwarded() {
    for (auto &forwarded : m_forwarded) {
        wl_list_remove(&forwarded->destroyListener.link);
        wl_buffer_destroy(forwarded->buffer);
        if (forwarded->dropped && forwarded->image)
            m_releaseImage(forwarded->image);
    }
    m_forwarded.clear();
}

void DirectSurface::presentGl(struct wpe_fdo_egl_exported_image *image) {
    auto       display         = static_cast<EGLDisplay>(m_eglDisplay);
    auto       surface         = static_cast<EGLSurface>(m_eglSurface);
    EGLDisplay previousDisplay = eglGetCurrentDisplay();
    EGLContext previousContext = eglGetCurrentContext();
    EGLSurface previousDraw    = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface previousRead    = eglGetCurrentSurface(EGL_READ);
    if (!eglMakeCurrent(display, surface, surface, static_cast<EGLContext>(m_eglContext)))
        return;

    glViewport(0, 0, qMax(1, m_applied.width()), qMax(1, m_applied.height()));
    glUseProgram(m_program);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureFor(image));
    glUniform1i(m_sampler, 0);
    // The exported image's first row is the top of the page.
    static const GLfloat quad[] = {
        -1.f, -1.f, 0.f, 1.f, 1.f, -1.f, 1.f, 1.f, -1.f, 1.f, 0.f, 0.f, 1.f, 1.f, 1.f, 0.f,
    };
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), quad);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), quad + 2);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    // The next frame waits for the compositor to have used this one.
    if (!m_frameCallback) {
        m_frameCallback = wl_surface_frame(m_surface);
        wl_callback_add_listener(m_frameCallback, &s_frameListener, this);
    }
    eglSwapBuffers(display, surface);

    if (previousContext != EGL_NO_CONTEXT)
        eglMakeCurrent(previousDisplay, previousDraw, previousRead, previousContext);
    else
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
}

// WebKit draws into a few buffers in turn, and WPEBackend-fdo keeps one
// EGLImage per buffer for the buffer's life: a texture per image is bound
// as it is, where targeting one texture at each frame's image made the
// driver import it again (a sixth of the main thread while scrolling). The
// buffers are made again at a new size and may be after the page is hidden;
// the textures go then, so an image address cannot be taken for another's.
unsigned DirectSurface::textureFor(struct wpe_fdo_egl_exported_image *image) {
    void       *eglImage = wpe_fdo_egl_exported_image_get_egl_image(image);
    const QSize size(static_cast<int>(wpe_fdo_egl_exported_image_get_width(image)),
                     static_cast<int>(wpe_fdo_egl_exported_image_get_height(image)));
    if (m_dropTextures || size != m_textureSize) {
        for (ImageTexture &t : m_textures) {
            if (t.texture)
                glDeleteTextures(1, &t.texture);
            t = {};
        }
        m_textureSize  = size;
        m_dropTextures = false;
    }
    for (const ImageTexture &t : m_textures) {
        if (t.texture && t.image == eglImage)
            return t.texture;
    }
    ImageTexture &slot = m_textures[m_nextTexture++ % m_textures.size()];
    if (slot.texture)
        glDeleteTextures(1, &slot.texture);
    glGenTextures(1, &slot.texture);
    glBindTexture(GL_TEXTURE_2D, slot.texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    s_imageTarget(GL_TEXTURE_2D, static_cast<GLeglImageOES>(eglImage));
    slot.image = eglImage;
    return slot.texture;
}

void DirectSurface::onFrameDone() {
    if (m_frameCallback) {
        wl_callback_destroy(m_frameCallback);
        m_frameCallback = nullptr;
    }
    if (m_frameDone)
        m_frameDone();
}

void DirectSurface::destroy() {
    m_valid = false;
    dropForwarded();
    if (m_wlegl)
        wl_proxy_destroy(m_wlegl);
    m_wlegl = nullptr;
    if (m_frameCallback) {
        wl_callback_destroy(m_frameCallback);
        m_frameCallback = nullptr;
    }
    if (m_eglDisplay) {
        auto display = static_cast<EGLDisplay>(m_eglDisplay);
        if (m_eglSurface)
            eglDestroySurface(display, static_cast<EGLSurface>(m_eglSurface));
        if (m_eglContext)
            eglDestroyContext(display, static_cast<EGLContext>(m_eglContext));
    }
    m_eglSurface = m_eglContext = m_eglDisplay = nullptr;
    if (m_eglWindow)
        wl_egl_window_destroy(m_eglWindow);
    m_eglWindow = nullptr;
    if (m_subsurface)
        wl_subsurface_destroy(m_subsurface);
    m_subsurface = nullptr;
    if (m_surface)
        wl_surface_destroy(m_surface);
    m_surface = nullptr;
    if (m_display)
        wl_display_flush(m_display);
}
