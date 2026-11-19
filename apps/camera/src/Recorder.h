// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QImage>
#include <QSize>
#include <QString>
#include <memory>

typedef struct _GstElement GstElement;

// A video with the microphone's sound: H.264 and AAC in an MP4, encoded by
// GStreamer as frames are pushed.
class Recorder {
  public:
    // rotation: clockwise degrees that stand the video upright.
    static std::unique_ptr<Recorder> start(const QString &path, const QSize &size, int rotation,
                                           QString *error);
    ~Recorder();

    // Loads GStreamer's encoders ahead of the first start(), which would
    // otherwise spend half a second in it.
    static void prepare();

    // Any thread. timestamp: CLOCK_MONOTONIC nanoseconds of the exposure.
    void push(const QImage &frame, qint64 timestamp);
    // Ends the file; false with the reason if it could not be written.
    bool finish(QString *error);

  private:
    Recorder() = default;

    GstElement *m_pipeline = nullptr;
    GstElement *m_video    = nullptr;
    GstElement *m_audio    = nullptr;
    qint64      m_base     = 0;
};
