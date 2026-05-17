#pragma once

#include <QImage>
#include <QObject>
#include <QString>
#include <wayland-client-core.h>

#include <QtWaylandClient/qwaylandclientextension.h>

#include "qwayland-wlr-screencopy-unstable-v1.h"

class ScreencopyFrame;

// Shell-side client of zwlr_screencopy_manager_v1 (wl_shm path only,
// matching what marathon-compositor advertises). Each capture() call
// asynchronously yields a QImage via captured(tag, image) once the
// server signals ready, or captureFailed(tag) on protocol error.
class ScreencopyClient : public QWaylandClientExtensionTemplate<ScreencopyClient>,
                         public QtWayland::zwlr_screencopy_manager_v1 {
    Q_OBJECT

  public:
    explicit ScreencopyClient(QObject *parent = nullptr);
    ~ScreencopyClient() override;

    // Request a full-output capture. tag is opaque to the protocol —
    // we use it to route the resulting image back to the right Task
    // when captured() fires (typically the appId).
    void capture(const QString &tag);

  Q_SIGNALS:
    void captured(const QString &tag, const QImage &image);
    void captureFailed(const QString &tag);

  private:
    void              onFrameReady(ScreencopyFrame *frame, const QImage &image);
    void              onFrameFailed(ScreencopyFrame *frame);

    struct wl_output *outputProxy() const;
    struct wl_shm    *shmProxy() const;
};

// One per outstanding capture. Handles the protocol's buffer/copy/
// ready dance, owns the wl_shm buffer it allocates, and delivers
// either a QImage or a failure back to the parent client.
class ScreencopyFrame : public QObject, public QtWayland::zwlr_screencopy_frame_v1 {
    Q_OBJECT

  public:
    ScreencopyFrame(ScreencopyClient *client, struct ::zwlr_screencopy_frame_v1 *frame,
                    struct wl_shm *shm, const QString &tag);
    ~ScreencopyFrame() override;

    QString tag() const {
        return m_tag;
    }

  Q_SIGNALS:
    void ready(const QImage &image);
    void failed();

  protected:
    void zwlr_screencopy_frame_v1_buffer(uint32_t format, uint32_t width, uint32_t height,
                                         uint32_t stride) override;
    void zwlr_screencopy_frame_v1_flags(uint32_t flags) override;
    void zwlr_screencopy_frame_v1_ready(uint32_t tv_sec_hi, uint32_t tv_sec_lo,
                                        uint32_t tv_nsec) override;
    void zwlr_screencopy_frame_v1_failed() override;
    void zwlr_screencopy_frame_v1_buffer_done() override;

  private:
    bool              allocateShmBuffer();
    void              teardown();

    ScreencopyClient *m_client = nullptr;
    struct wl_shm    *m_shm    = nullptr;
    QString           m_tag;
    uint32_t          m_format    = 0;
    uint32_t          m_width     = 0;
    uint32_t          m_height    = 0;
    uint32_t          m_stride    = 0;
    uint32_t          m_flags     = 0;
    int               m_shmFd     = -1;
    void             *m_mappedPtr = nullptr;
    size_t            m_mappedLen = 0;
    struct wl_buffer *m_buffer    = nullptr;
};
