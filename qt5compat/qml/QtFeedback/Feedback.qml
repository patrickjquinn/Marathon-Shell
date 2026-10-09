// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QtFeedback's `Feedback` namespace (enums of QFeedbackEffect). Qt 5
// registered it as uncreatable; here it is an empty object holding the enums.
import QtQml 2.15

QtObject {
    enum State { Stopped, Paused, Running, Loading }
    // Qt 5 has Infinite = -1; Qt 6.4 rejects negative QML enum values, so
    // Infinite is INT_MAX here. FeedbackEffect treats it and any negative
    // duration (a literal -1) as infinite.
    enum Duration { Infinite = 2147483647 }
    enum ErrorType { UnknownError, DeviceBusy }
}
