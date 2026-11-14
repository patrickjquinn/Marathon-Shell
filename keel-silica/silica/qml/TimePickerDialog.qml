// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) TimePickerDialog.qml
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"

Dialog {
    id: timePickerDialog

    // Items from the Harmattan component interface
    property int hour
    property int minute
    //property int second                   // not supported
    property alias hourMode: clockItem.hourMode
    //property string acceptButtonText      // not supported
    //property string rejectButtonText      // not supported
    //property string titleText             // not supported
    //property int fields                   // not supported

    property date time: new Date(0,0,0, hour, minute)
    property string timeText: timePicker._formatTime(hour, minute, 0)

    allowedOrientations: Orientation.All

    Column {
        spacing: Theme.paddingLarge
        width: parent.width

        DialogHeader {}

        TimePicker {
            id: timePicker

            anchors.horizontalCenter: parent.horizontalCenter
            hourMode: clockItem.hourMode

            ClockItem {
                id: clockItem

                time: timePicker.time
                anchors.centerIn: parent
            }
        }
    }

    onOpened: {
        timePicker.hour = hour
        timePicker.minute = minute
    }

    onDone: {
        if (result == DialogResult.Accepted) {
            hour = timePicker.hour
            minute = timePicker.minute
        }
    }
}
