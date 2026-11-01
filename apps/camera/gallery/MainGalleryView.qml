// SPDX-FileCopyrightText: 2018 - 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.1
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

GalleryView {
    id: root

    captureModel: CaptureModel {
        id: model
    }

    // An InfoLabel, not a ViewPlaceholder, which needs a SilicaFlickable to
    // sit in (the roll is a PagedView).
    InfoLabel {
        anchors.verticalCenter: parent.verticalCenter
        //: Placeholder text for an empty camera reel view
        text: qsTr("Captured photos and videos will appear here when you take some")
        visible: model.count === 0 && model.populated
    }
}
