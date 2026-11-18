// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QPointF>

// The libcamerasrc element Qt's GStreamer backend makes for the camera. Qt
// gives no access to it, so it is caught as it joins its bin; its properties
// are libcamera's controls.
namespace LibcameraSource {

// Starts watching for the element; once per process.
void watch();

// Focuses once around a point of the frame (0..1 each way) and holds it there.
bool focusOn(const QPointF &point);

// libcamera's AfState (0 idle, 1 scanning, 2 focused, 3 failed), or -1.
int focusState();

// Back to focusing continuously over the whole frame.
bool focusContinuously();

} // namespace LibcameraSource
