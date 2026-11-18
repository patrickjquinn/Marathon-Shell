// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#include "LibcameraSource.h"

#include <QMutex>
#include <QMutexLocker>
#include <QRect>
#include <algorithm>
#include <gst/gst.h>
#include <mutex>

namespace {

// libcamera's control values (control_ids_core.yaml).
constexpr int kAfModeAuto         = 1;
constexpr int kAfModeContinuous   = 2;
constexpr int kAfMeteringAuto     = 0;
constexpr int kAfMeteringWindows  = 1;
constexpr int kAfTriggerStart     = 0;

QMutex      lock;
GstElement *source = nullptr;

// GstBin::element-added on any bin: keep the newest libcamerasrc.
gboolean onElementAdded(GSignalInvocationHint *, guint count, const GValue *params, gpointer) {
    if (count < 2)
        return TRUE;
    auto *element = static_cast<GstElement *>(g_value_get_object(&params[1]));
    if (!element || g_strcmp0(G_OBJECT_TYPE_NAME(element), "GstLibcameraSrc") != 0)
        return TRUE;
    QMutexLocker locked(&lock);
    if (source)
        gst_object_unref(source);
    source = static_cast<GstElement *>(gst_object_ref(element));
    return TRUE;
}

// The current source with a reference, or null.
GstElement *current() {
    QMutexLocker locked(&lock);
    return source ? static_cast<GstElement *>(gst_object_ref(source)) : nullptr;
}

bool hasProperty(GstElement *element, const char *name) {
    return g_object_class_find_property(G_OBJECT_GET_CLASS(element), name) != nullptr;
}

} // namespace

void LibcameraSource::watch() {
    static std::once_flag once;
    std::call_once(once, [] {
        gst_init_check(nullptr, nullptr, nullptr);
        const guint signal = g_signal_lookup("element-added", GST_TYPE_BIN);
        if (signal)
            g_signal_add_emission_hook(signal, 0, onElementAdded, nullptr, nullptr);
    });
}

namespace {

// The sensor area the frame shows, in the sensor's pixel array: the
// coordinates of the AF windows. Empty until the first frame completes.
QRect scalerCrop(GstElement *element) {
    GParamSpec *spec = g_object_class_find_property(G_OBJECT_GET_CLASS(element), "scaler-crop");
    if (!spec)
        return {};
    GValue crop = G_VALUE_INIT;
    g_value_init(&crop, G_PARAM_SPEC_VALUE_TYPE(spec));
    g_object_get_property(G_OBJECT(element), "scaler-crop", &crop);
    int v[4] = {};
    if (GST_VALUE_HOLDS_ARRAY(&crop) && gst_value_array_get_size(&crop) == 4)
        for (guint i = 0; i < 4; ++i)
            v[i] = g_value_get_int(gst_value_array_get_value(&crop, i));
    g_value_unset(&crop);
    return QRect(v[0], v[1], v[2], v[3]);
}

} // namespace

bool LibcameraSource::focusOn(const QPointF &point) {
    GstElement *element = current();
    if (!element)
        return false;
    const QRect crop = scalerCrop(element);
    const bool  ok   = crop.width() > 0 && crop.height() > 0 && hasProperty(element, "af-windows") &&
        hasProperty(element, "af-trigger") && hasProperty(element, "af-metering") &&
        hasProperty(element, "af-mode");
    if (ok) {
        // A fifth of the frame each way around the point, kept inside it.
        const int   w      = crop.width() / 5, h = crop.height() / 5;
        const QRect window(
            std::clamp(crop.x() + int(point.x() * crop.width()) - w / 2, crop.x(), crop.right() + 1 - w),
            std::clamp(crop.y() + int(point.y() * crop.height()) - h / 2, crop.y(), crop.bottom() + 1 - h),
            w, h);
        // af-windows: an array of rectangles, each an array of x, y, width, height.
        GValue windows = G_VALUE_INIT;
        GValue rect    = G_VALUE_INIT;
        GValue cell    = G_VALUE_INIT;
        gst_value_array_init(&windows, 1);
        gst_value_array_init(&rect, 4);
        g_value_init(&cell, G_TYPE_INT);
        for (const int v : {window.x(), window.y(), window.width(), window.height()}) {
            g_value_set_int(&cell, v);
            gst_value_array_append_value(&rect, &cell);
        }
        gst_value_array_append_and_take_value(&windows, &rect);
        g_object_set_property(G_OBJECT(element), "af-windows", &windows);
        g_value_unset(&windows);
        g_value_unset(&cell);
        g_object_set(element, "af-metering", kAfMeteringWindows, "af-mode", kAfModeAuto,
                     "af-trigger", kAfTriggerStart, nullptr);
    }
    gst_object_unref(element);
    return ok;
}

bool LibcameraSource::focusContinuously() {
    GstElement *element = current();
    if (!element)
        return false;
    const bool ok = hasProperty(element, "af-mode") && hasProperty(element, "af-metering");
    if (ok)
        g_object_set(element, "af-metering", kAfMeteringAuto, "af-mode", kAfModeContinuous, nullptr);
    gst_object_unref(element);
    return ok;
}

int LibcameraSource::focusState() {
    GstElement *element = current();
    if (!element)
        return -1;
    int state = -1;
    if (hasProperty(element, "af-state"))
        g_object_get(element, "af-state", &state, nullptr);
    gst_object_unref(element);
    return state;
}
