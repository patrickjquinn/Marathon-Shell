// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 ContentPickerPage, Keel's clean-room version: picks
// one document, image, video or music file. The page offers the four
// categories; each opens that category's picker, whose pick lands here
// (selectedContent, selectedContentProperties) and returns to the page
// below this one. API from the Sailfish.Pickers documentation.
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

PickerPageBase {
    id: page

    title: qsTr("Select file")

    property alias _list: list

    SilicaListView {
        id: list
        anchors.fill: parent
        header: PageHeader { title: page.title }
        model: ListModel {
            ListElement { name: "documents"; icon: "image://theme/icon-m-file-document"; target: "DocumentPickerPage.qml" }
            ListElement { name: "images"; icon: "image://theme/icon-m-file-image"; target: "ImagePickerPage.qml" }
            ListElement { name: "videos"; icon: "image://theme/icon-m-file-video"; target: "VideoPickerPage.qml" }
            ListElement { name: "music"; icon: "image://theme/icon-m-file-audio"; target: "MusicPickerPage.qml" }
        }
        delegate: BackgroundItem {
            id: category
            required property string icon
            required property string name
            required property string target
            width: ListView.view.width
            height: Theme.itemSizeMedium
            Icon {
                id: categoryIcon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: category.icon
            }
            Label {
                anchors {
                    left: categoryIcon.right
                    leftMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                text: category.name === "documents" ? qsTr("Documents")
                    : category.name === "images" ? qsTr("Images")
                    : category.name === "videos" ? qsTr("Videos") : qsTr("Music")
                color: category.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            onClicked: pageStack.push(Qt.resolvedUrl(target), { "_target": page })
        }
    }
}
