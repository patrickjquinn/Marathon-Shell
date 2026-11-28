// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QElapsedTimer>
#include <QImage>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QPointF>
#include <QSize>
#include <QString>
#include <atomic>
#include <map>
#include <memory>
#include <vector>

// libcamera's Signal has members named after Qt's emit and slots macros.
#pragma push_macro("emit")
#pragma push_macro("slots")
#undef emit
#undef slots
#include <libcamera/camera.h>
#include <libcamera/camera_manager.h>
#include <libcamera/control_ids.h>
#include <libcamera/controls.h>
#include <libcamera/formats.h>
#include <libcamera/framebuffer_allocator.h>
#include <libcamera/geometry.h>
#include <libcamera/property_ids.h>
#include <libcamera/request.h>
#include <libcamera/stream.h>
#pragma pop_macro("slots")
#pragma pop_macro("emit")

// A camera as libcamera names it, with the frame sizes it makes.
class Recorder;

struct CameraInfo {
    QString id;
    // Largest first.
    QList<QSize> sizes;
    // libcamera's Location and Rotation properties; -1 without a Location.
    int location = -1;
    int rotation = 0;
    // The sensor's pixel array, in pixels.
    qint64 pixels = 0;
};

// libcamera, driven from the thread this object lives on: everything that
// waits for the camera (start, stop, configure) runs there. Frames arrive on
// libcamera's own thread.
class CameraSession : public QObject {
    Q_OBJECT

  public:
    struct Wanted {
        QString cameraId;
        // Invalid: libcamera's choice.
        QSize size;
        bool  streaming = false;
    };

    CameraSession();
    ~CameraSession() override;

    // These four from any thread.
    void want(const Wanted &wanted);
    // A point of the frame, 0..1 each way: focus there once and hold.
    bool focusOn(const QPointF &point);
    void focusContinuously();
    // The newest viewfinder frame, once; null if it was taken already.
    QImage takeFrame();

    // On the session's thread.
    void discover();
    void takeStill(const QSize &size);
    // rotation: clockwise degrees that stand the video upright.
    void startRecording(const QString &path, int rotation);
    void stopRecording();
    // Closes the camera and libcamera; want() opens them again.
    void release();

  signals:
    void discovered(const QList<CameraInfo> &cameras);
    void streamingChanged(bool streaming);
    void frameReady();
    // The photo's frame, mapped; the image holds its buffer.
    void stillCaptured(const QImage &image);
    // The viewfinder runs again, or will not.
    void stillFinished();
    // The scan a focusOn() started has ended.
    void focusFinished(bool focused);
    void recordingChanged(bool recording);
    void recordingFinished(const QString &path, bool saved);
    void error(const QString &message);

  private:
    struct Mapping {
        const uchar *data;
        size_t       length;
        int          fd;
    };

    bool                                            startManager();
    void                                            reconcile();
    bool                                            open(const QString &id);
    void                                            close();
    bool                                            configureViewfinder(const QSize &size);
    bool                                            startViewfinder();
    void                                            stopCamera();
    void                                            finishStill();
    void                                            finishRecording();
    void                                            requestCompleted(libcamera::Request *request);
    QImage                                          copyFrame(const libcamera::FrameBuffer *buffer);
    void                                            addControls(libcamera::Request *request);

    std::unique_ptr<libcamera::CameraManager>       m_manager;
    std::shared_ptr<libcamera::Camera>              m_camera;
    QString                                         m_cameraId;
    std::unique_ptr<libcamera::CameraConfiguration> m_config;
    QSize                                           m_size;
    // The camera runs m_config, not a photo's.
    bool                                              m_configured = false;
    std::unique_ptr<libcamera::FrameBufferAllocator>  m_allocator;
    std::vector<std::unique_ptr<libcamera::Request>>  m_requests;
    std::map<const libcamera::FrameBuffer *, Mapping> m_mappings;
    QSize                                             m_frameSize;
    unsigned int                                      m_stride = 0;
    std::atomic<bool>                                 m_streaming{false};
    QElapsedTimer                                     m_startClock;
    bool                                              m_firstFrame = false;

    // Frames handed out are only reused once nobody holds them.
    std::vector<QImage> m_pool;
    QMutex              m_frameLock;
    QImage              m_frame;
    std::atomic<bool>   m_framePosted{false};

    QMutex              m_wantLock;
    Wanted              m_wanted;
    std::atomic<bool>   m_reconcilePosted{false};

    // A photo: its buffers, and the frames left until its own.
    std::shared_ptr<libcamera::FrameBufferAllocator> m_stillAllocator;
    std::vector<std::unique_ptr<libcamera::Request>> m_stillRequests;
    std::atomic<int>                                 m_stillFrames{0};
    bool                                             m_stillActive = false;

    // Controls for the next request; the sticky ones also follow a reconfigure.
    QMutex                 m_controlLock;
    libcamera::ControlList m_controls;
    libcamera::ControlList m_sticky;
    libcamera::Rectangle   m_scalerCrop;
    float                  m_lensPosition = -1;
    std::atomic<bool>      m_hasAutofocus{false};
    // The request carrying a focus trigger, until it completes; then the scan's end is awaited.
    libcamera::Request       *m_triggerRequest = nullptr;
    bool                      m_scanning       = false;

    QMutex                    m_recorderLock;
    std::unique_ptr<Recorder> m_recorder;
    QString                   m_recordingPath;
    bool                      m_recorderPrepared = false;
};
