// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Direct composition (on unless PACIFIC_DIRECT=0): web frames are drawn
// into a wl_subsurface of the window that Lipstick presents itself, instead
// of being sampled by Qt's scene graph and recomposited with the whole window.
// A frame is presented when the compositor has used the last one (its
// frame callback) and acknowledged then, so WebKit composites the next while
// the compositor shows this one, at no more than the panel's rate
// (ViewBackend::DirectAck). Flinging Wikipedia and The Verge on the Jolla
// Phone, 68-78 frames a second reached the compositor, against 45-59 when
// every frame was presented as it arrived (up to 131 a second, which only
// made Lipstick composite less often) and ~40 when WebKit waited for the
// callback before compositing the next.
//
// Lipstick always stacks a subsurface above its parent's own content, so the
// browser's chrome cannot be drawn over it: the subsurface is only used while
// nothing should cover the page (PacificWebView.directComposite, set by the
// UI), and is moved off screen otherwise, when Qt's path shows the same frame.
// Its input region is empty, so touches still reach the window.
//
// Zero copy (unless PACIFIC_DIRECT_ATTACH=0): on libhybris, WebKit's own
// gralloc buffer is handed to Lipstick (android_wlegl, as any hybris client
// does) and attached to the subsurface, instead of being drawn into a buffer
// of the subsurface's with GL: one full-screen pass and copy less per frame,
// on the GPU and on the GUI thread. A frame Lipstick still reads goes back to
// WebKit only when Lipstick releases its buffer. The buffer is found through
// WPEBackend-fdo's exported image and libhybris's server buffer, both
// private: they are checked against what is public on the first frame, and
// the GL copy is used when they do not match.
//
// The idea is Atlantic's (atlantic-engine qt5-plugin/WPEWaylandSubsurface,
// parked there because the chrome could not be stacked above it).

#pragma once

#include <QMetaObject>
#include <QRect>
#include <QSize>
#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

struct wpe_fdo_egl_exported_image;
struct wl_callback;
struct wl_buffer;
struct wl_compositor;
struct wl_proxy;
struct wl_resource;
struct wl_display;
struct wl_egl_window;
struct wl_subcompositor;
struct wl_subsurface;
struct wl_surface;
class QWindow;

class DirectSurface {
  public:
    // Unless PACIFIC_DIRECT=0, read once.
    static bool enabled();

    // frameDone runs on the GUI thread when the compositor has used the last
    // presented frame (the subsurface's frame callback).
    // releaseImage gives an image back to WebKit (GUI thread), for frames
    // whose release was deferred (deferRelease).
    DirectSurface(std::function<void()>                                    frameDone,
                  std::function<void(struct wpe_fdo_egl_exported_image *)> releaseImage);
    ~DirectSurface();

    // Creates the subsurface under the window's wl_surface on first use;
    // false (and inert) when the platform or the compositor cannot.
    bool ensureCreated(QWindow *window);
    bool isValid() const {
        return m_valid;
    }

    // Where the web content goes, in the parent surface's pixels.
    void setGeometry(const QRect &rect);
    // Shown: frames go to the subsurface. Hidden: it is moved off screen.
    void setShown(bool shown);
    bool isShown() const {
        return m_valid && m_shown;
    }
    // A presented frame the compositor has not called back for yet.
    bool framePending() const {
        return m_frameCallback != nullptr;
    }

    // Shows the frame on the subsurface: WebKit's buffer itself, or a GL copy
    // (GUI thread).
    void present(struct wpe_fdo_egl_exported_image *image);

    // An image the owner is done with: true when Lipstick still reads its
    // buffer, and the image goes back (releaseImage) when Lipstick lets go.
    bool deferRelease(struct wpe_fdo_egl_exported_image *image);

    void onRegistryGlobal(void *registry, uint32_t name, const char *interface);
    void onFrameDone();

    // WebKit's buffer forwarded to Lipstick, for the buffer's life.
    struct Forwarded;
    void onBufferReleased(Forwarded *forwarded);
    void onResourceDestroyed(Forwarded *forwarded);

  private:
    bool       bindGlobals();
    bool       setupGl();
    void       applyPosition();
    void       commitParent();
    void       destroy();
    unsigned   textureFor(struct wpe_fdo_egl_exported_image *image);
    void       presentGl(struct wpe_fdo_egl_exported_image *image);
    bool       presentAttached(struct wpe_fdo_egl_exported_image *image);
    Forwarded *forward(struct wpe_fdo_egl_exported_image *image);
    void       dropForwarded();

    enum class Mode {
        Unknown,
        Attach,
        Gl
    };

    std::function<void()>                                    m_frameDone;
    std::function<void(struct wpe_fdo_egl_exported_image *)> m_releaseImage;
    Mode                                                     m_mode  = Mode::Unknown;
    wl_proxy                                                *m_wlegl = nullptr;
    std::vector<std::unique_ptr<Forwarded>>                  m_forwarded;
    bool                                                     m_valid     = false;
    bool                                                     m_attempted = false;
    bool                                                     m_shown     = false;

    wl_display                                              *m_display       = nullptr;
    wl_surface                                              *m_parent        = nullptr;
    wl_compositor                                           *m_compositor    = nullptr;
    wl_subcompositor                                        *m_subcompositor = nullptr;
    wl_surface                                              *m_surface       = nullptr;
    wl_subsurface                                           *m_subsurface    = nullptr;
    wl_egl_window                                           *m_eglWindow     = nullptr;
    wl_callback                                             *m_frameCallback = nullptr;
    QMetaObject::Connection                                  m_parentDestroyed;

    void                                                    *m_eglDisplay = nullptr;
    void                                                    *m_eglContext = nullptr;
    void                                                    *m_eglSurface = nullptr;
    unsigned                                                 m_program    = 0;
    struct ImageTexture {
        void    *image   = nullptr;
        unsigned texture = 0;
    };
    std::array<ImageTexture, 4> m_textures{};
    unsigned                    m_nextTexture = 0;
    QSize                       m_textureSize;
    bool                        m_dropTextures = false;
    int                         m_sampler      = -1;

    QRect                       m_geometry;
    QRect                       m_applied;
};
