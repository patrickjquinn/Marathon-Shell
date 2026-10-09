// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Reference scene: a Dialog with a DialogHeader, text fields, a switch and a
// button. Written for Keel.
import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    width: 540
    height: 960
    cover: null
    initialPage: Component {
        Dialog {
            canAccept: true
            Column {
                width: parent.width
                DialogHeader { acceptText: "Save" }
                TextField {
                    width: parent.width
                    label: "Name"
                    placeholderText: "Name"
                    text: "Ada Lovelace"
                }
                TextField {
                    width: parent.width
                    label: "Email"
                    placeholderText: "Email address"
                }
                TextSwitch {
                    text: "Notify me"
                    description: "Show a notification when it changes"
                    checked: true
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Remove"
                }
            }
        }
    }
}
