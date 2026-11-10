// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ClockItem (private): the time shown in the middle of TimePickerDialog.
// Silica's own file is not open (no BSD header in sailfishsilica-qt5
// 1.2.156); Keel's clean-room stand-in with the properties Silica's BSD
// TimePickerDialog.qml uses: `time` and `hourMode` (DateTime values).
import QtQuick
import Sailfish.Silica 1.0

Label {
    property date time
    property int hourMode: DateTime.DefaultHours

    color: Theme.highlightColor
    font.pixelSize: Theme.fontSizeHuge
    text: Format.formatDate(time, hourMode === DateTime.TwentyFourHours ? Formatter.TimeValueTwentyFourHours
                                  : hourMode === DateTime.TwelveHours ? Formatter.TimeValueTwelveHours
                                  : Formatter.TimeValue)
}
