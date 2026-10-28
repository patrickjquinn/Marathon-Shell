// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// One featured app as the home page's banner: the icon, name, summary and
// price on the left over the theme's highlight colour, and on the right
// the app itself, its first screenshot at full brightness as a tall card
// rising from the bottom edge, like a phone held up. An app without a
// screenshot gets its icon there, large. Same roles as PackageDelegate
// (featuredModel).

import QtQuick
import Sailfish.Silica 1.0
import "Texts.js" as Texts

BackgroundItem {
    id: card

    required property string name
    required property string title
    required property string summary
    required property string iconPath
    required property string heroPath
    required property string licenceModel
    required property bool licensed
    required property string installState

    clip: true

    // The ambience's highlight, strongest on the left, fading out.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightBackgroundColor, 0.55) }
            GradientStop { position: 0.6; color: Theme.rgba(Theme.highlightBackgroundColor, 0.2) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightDimmerColor, 0.35) }
        }
    }

    // The app: its screenshot as a card, its whole width shown and only its
    // foot cut off by the banner's bottom (a screenshot cropped at the
    // sides read as broken).
    Rectangle {
        id: phone
        readonly property real cardWidth: Math.round(card.width * 0.36)
        x: card.width - width - Theme.horizontalPageMargin
        y: Theme.paddingLarge * 2
        // The picture's height over its width, read once it has loaded:
        // bound to the image's own size instead, the card's height and the
        // fitted image fed each other (a binding loop on every layout).
        property real aspect: 2.2
        width: cardWidth
        height: Math.round(cardWidth * aspect)
        radius: Theme.paddingMedium
        color: Theme.rgba(Theme.overlayBackgroundColor, 0.6)
        border.color: Theme.rgba(Theme.highlightColor, 0.4)
        border.width: Math.max(1, Math.round(Theme.pixelRatio))
        visible: shot.status === Image.Ready

        Image {
            id: shot
            anchors.fill: parent
            anchors.margins: parent.border.width
            source: card.heroPath.length > 0 ? "file://" + card.heroPath : ""
            // Decoded at the card's width; its height follows the picture.
            sourceSize.width: phone.cardWidth
            fillMode: Image.PreserveAspectFit
            verticalAlignment: Image.AlignTop
            asynchronous: true
            smooth: true
            onStatusChanged: {
                if (status === Image.Ready && implicitWidth > 0)
                    phone.aspect = implicitHeight / implicitWidth
            }
        }
    }
    AppIcon {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: phone.horizontalCenter
        visible: !phone.visible
        iconPath: card.iconPath
        title: card.title
        size: Math.round(card.width * 0.3)
        opacity: 0.9
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.right: phone.left
        anchors.rightMargin: Theme.paddingLarge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.paddingSmall

        AppIcon {
            iconPath: card.iconPath
            title: card.title
            size: Theme.iconSizeLauncher
        }
        Label {
            width: parent.width
            topPadding: Theme.paddingSmall
            text: card.title
            color: card.highlighted ? Theme.highlightColor : Theme.primaryColor
            font.pixelSize: Theme.fontSizeExtraLarge
            font.family: Theme.fontFamilyHeading
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            text: card.summary
            color: card.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            topPadding: Theme.paddingSmall
            text: card.installState === "update_available" ? qsTr("Update ready")
                : card.installState === "installed" ? qsTr("Installed")
                : Texts.price(card.licenceModel, card.licensed)
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }
    }
}
