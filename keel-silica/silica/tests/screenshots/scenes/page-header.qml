// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Reference scene: a Page with a PageHeader, section headers, details and a
// button. Written for Keel; public Silica API only.
import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    width: 540
    height: 960
    cover: null
    initialPage: Component {
        Page {
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: column.height
                Column {
                    id: column
                    width: parent.width
                    spacing: Theme.paddingMedium
                    PageHeader {
                        title: "Reference page"
                        description: "Keel visual check"
                    }
                    SectionHeader { text: "Details" }
                    DetailItem { label: "Version"; value: "1.2.156" }
                    DetailItem { label: "Status"; value: "Running" }
                    SectionHeader { text: "About" }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        wrapMode: Text.Wrap
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        text: "Pages, headers, labels and buttons as an app on Keel draws them."
                    }
                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Continue"
                    }
                }
                VerticalScrollDecorator {}
            }
        }
    }
}
