// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QRect>

// The libcamerasrc element Qt's GStreamer backend makes for the camera. Qt
// gives no access to it, so it is caught as it joins its bin; its properties
// are libcamera's controls.
namespace LibcameraSource {

// Starts watching for the element; once per process.
void watch();

// Focuses once on a window in the AF coordinate space and holds it there.
bool focusOn(const QRect &window);

// Back to focusing continuously over the whole frame.
bool focusContinuously();

} // namespace LibcameraSource
