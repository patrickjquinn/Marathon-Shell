// SPDX-FileCopyrightText: 2016 - 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

SettingsMenuItemBase {
    id: menuItem

    property string icon
    property alias iconVisible: image.visible

    visible: icon.length > 0

    Image {
        id: image

        anchors.centerIn: parent
        source: {
            if (menuItem.icon.length > 0) {
                if (menuItem.pressed) {
                    return menuItem.icon + "?" + (Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark));
                } else {
                    return menuItem.icon + "?" + Theme.lightPrimaryColor;
                }
            }
            return "";
        }
    }
}
