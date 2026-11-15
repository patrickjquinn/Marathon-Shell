// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The model on the phone until it is ready (pilotd's ModelState): an offer
// to download it, with its size and why a download did not start; the
// download's progress; loading; or a failure with Try again. Hidden when
// the model is ready or Pilot uses a cloud model ("none").

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Pilot 1.0

Glass {
    id: card

    readonly property var status: {
        try {
            return JSON.parse(Pilot.modelState || "{}");
        } catch (e) {
            return {};
        }
    }
    readonly property string phase: status.state || ""
    readonly property string why: status.error || ""
    readonly property real total: status.total || 0
    readonly property real bytes: status.bytes || 0

    function headline() {
        switch (phase) {
        case "downloading":
            return qsTr("Downloading Pilot's model");
        case "loading":
            return qsTr("Getting Pilot ready");
        case "failed":
            return qsTr("Pilot's model didn't start");
        default:
            return qsTr("Download Pilot's on-device model");
        }
    }

    function detail() {
        if (phase === "downloading")
            return total > 0 ? qsTr("%1 of %2").arg(Format.formatFileSize(bytes)).arg(Format.formatFileSize(total)) : "";
        if (phase === "loading")
            return qsTr("The model is loading on this phone.");
        if (phase === "failed")
            return qsTr("Try again, or restart the phone if it keeps failing.");
        var offer = total > 0 ? qsTr("Pilot answers on this phone with a model it downloads once (%1).").arg(Format.formatFileSize(total)) : qsTr("Pilot answers on this phone with a model it downloads once.");
        switch (why) {
        case "offline":
            return offer + " " + qsTr("Connect to the internet to download it.");
        case "metered":
            return offer + " " + qsTr("You're on mobile data: download it on Wi-Fi, or use mobile data.");
        case "no-space":
            return offer + " " + qsTr("There isn't room for it on this phone yet.");
        case "download":
            return offer + " " + qsTr("The download stopped before it finished.");
        default:
            return offer;
        }
    }

    objectName: "modelCard"
    visible: ["absent", "downloading", "loading", "failed"].indexOf(phase) >= 0
    accent: true

    Label {
        objectName: "modelHeadline"
        width: parent.width
        wrapMode: Text.Wrap
        font.family: Theme.fontFamilyHeading
        color: Theme.primaryColor
        text: card.headline()
    }
    Label {
        width: parent.width
        visible: text.length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondaryColor
        text: card.detail()
    }
    ProgressBar {
        objectName: "modelProgress"
        visible: card.phase === "downloading"
        width: parent.width
        leftMargin: 0
        rightMargin: 0
        indeterminate: card.total <= 0
        maximumValue: Math.max(1, card.total)
        value: card.bytes
    }
    BusyIndicator {
        visible: card.phase === "loading"
        running: visible
        size: BusyIndicatorSize.Small
    }
    Flow {
        width: parent.width
        spacing: Theme.paddingMedium
        Button {
            objectName: "downloadModel"
            visible: card.phase === "absent" || card.phase === "failed"
            text: card.phase === "failed" || card.why === "download" ? qsTr("Try again") : qsTr("Download")
            onClicked: Pilot.downloadModels(false)
        }
        Button {
            objectName: "downloadOnMobileData"
            visible: card.phase === "absent" && card.why === "metered"
            text: qsTr("Use mobile data")
            onClicked: Pilot.downloadModels(true)
        }
    }
}
