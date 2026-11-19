// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#include "Recorder.h"

#include <gst/app/gstappsrc.h>
#include <gst/gst.h>

namespace {

// The encoders Qt's recorder picked: openh264enc keeps up on the phone's CPU.
constexpr char kPipeline[] =
    "appsrc name=video is-live=true format=time max-buffers=4 leaky-type=downstream ! queue ! "
    "videoconvert ! openh264enc rate-control=bitrate bitrate=5000000 complexity=low multi-thread=2 ! h264parse ! "
    "taginject name=orientation scope=stream ! queue ! mp4mux name=mux ! filesink name=file async=false "
    "pulsesrc name=audio ! queue ! audioconvert ! audioresample ! audio/x-raw,channels=2 ! fdkaacenc bitrate=128000 ! queue ! mux.";

} // namespace

void Recorder::prepare() {
    if (!gst_is_initialized())
        gst_init(nullptr, nullptr);
    if (GstElement *pipeline = gst_parse_launch(kPipeline, nullptr))
        gst_object_unref(pipeline);
}

std::unique_ptr<Recorder> Recorder::start(const QString &path, const QSize &size, int rotation,
                                          QString *error) {
    if (!gst_is_initialized())
        gst_init(nullptr, nullptr);
    GError     *parseError = nullptr;
    GstElement *pipeline   = gst_parse_launch(kPipeline, &parseError);
    if (parseError) {
        *error = QString::fromUtf8(parseError->message);
        g_error_free(parseError);
        if (pipeline)
            gst_object_unref(pipeline);
        return nullptr;
    }
    std::unique_ptr<Recorder> recorder(new Recorder);
    recorder->m_pipeline = pipeline;
    recorder->m_video    = gst_bin_get_by_name(GST_BIN(pipeline), "video");
    recorder->m_audio    = gst_bin_get_by_name(GST_BIN(pipeline), "audio");

    GstCaps *caps = gst_caps_new_simple("video/x-raw", "format", G_TYPE_STRING, "RGBx", "width",
                                        G_TYPE_INT, size.width(), "height", G_TYPE_INT,
                                        size.height(), "framerate", GST_TYPE_FRACTION, 30, 1,
                                        nullptr);
    g_object_set(recorder->m_video, "caps", caps, nullptr);
    gst_caps_unref(caps);

    GstElement *file = gst_bin_get_by_name(GST_BIN(pipeline), "file");
    g_object_set(file, "location", path.toUtf8().constData(), nullptr);
    gst_object_unref(file);

    rotation = ((rotation % 360) + 360) % 360;
    if (rotation != 0) {
        GstElement      *orientation = gst_bin_get_by_name(GST_BIN(pipeline), "orientation");
        const QByteArray tags = "image-orientation=rotate-" + QByteArray::number(rotation);
        g_object_set(orientation, "tags", tags.constData(), nullptr);
        gst_object_unref(orientation);
    }

    // The frames carry libcamera's CLOCK_MONOTONIC timestamps, the system clock's.
    GstClock *clock = gst_system_clock_obtain();
    gst_pipeline_use_clock(GST_PIPELINE(pipeline), clock);
    gst_object_unref(clock);

    if (gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE ||
        gst_element_get_state(pipeline, nullptr, nullptr, 3 * GST_SECOND) ==
            GST_STATE_CHANGE_FAILURE) {
        *error = QStringLiteral("Could not start recording");
        return nullptr;
    }
    recorder->m_base = qint64(gst_element_get_base_time(pipeline));
    return recorder;
}

Recorder::~Recorder() {
    gst_element_set_state(m_pipeline, GST_STATE_NULL);
    gst_object_unref(m_video);
    gst_object_unref(m_audio);
    gst_object_unref(m_pipeline);
}

void Recorder::push(const QImage &frame, qint64 timestamp) {
    if (timestamp < m_base)
        return;
    // The frame's pixels, held until the encoder is done with them.
    auto      *held   = new QImage(frame);
    GstBuffer *buffer = gst_buffer_new_wrapped_full(
        GST_MEMORY_FLAG_READONLY, const_cast<uchar *>(held->constBits()), held->sizeInBytes(), 0,
        held->sizeInBytes(), held, [](gpointer image) { delete static_cast<QImage *>(image); });
    GST_BUFFER_PTS(buffer) = GstClockTime(timestamp - m_base);
    gst_app_src_push_buffer(GST_APP_SRC(m_video), buffer);
}

bool Recorder::finish(QString *error) {
    gst_app_src_end_of_stream(GST_APP_SRC(m_video));
    gst_element_send_event(m_audio, gst_event_new_eos());
    GstBus     *bus     = gst_element_get_bus(m_pipeline);
    GstMessage *message = gst_bus_timed_pop_filtered(
        bus, 10 * GST_SECOND, GstMessageType(GST_MESSAGE_EOS | GST_MESSAGE_ERROR));
    gst_object_unref(bus);
    const bool saved = message && GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS;
    if (!message) {
        *error = QStringLiteral("The recording did not finish");
    } else if (!saved) {
        GError *gerror = nullptr;
        gst_message_parse_error(message, &gerror, nullptr);
        *error = QString::fromUtf8(gerror->message);
        g_error_free(gerror);
    }
    if (message)
        gst_message_unref(message);
    gst_element_set_state(m_pipeline, GST_STATE_NULL);
    return saved;
}
