// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Reference scene: common controls on a Page. Written for Keel.
import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    width: 540
    height: 960
    cover: null
    initialPage: Component {
        Page {
            Column {
                width: parent.width
                PageHeader { title: "Controls" }
                Slider {
                    width: parent.width
                    label: "Volume"
                    minimumValue: 0; maximumValue: 100; value: 40
                    valueText: Math.round(value)
                }
                ComboBox {
                    label: "Mode"
                    menu: ContextMenu {
                        MenuItem { text: "Automatic" }
                        MenuItem { text: "Manual" }
                    }
                }
                ValueButton { label: "Date"; value: "1 October 2026" }
                ProgressBar {
                    width: parent.width
                    label: "Downloading"
                    value: 0.6
                }
                Row {
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingLarge
                    BusyIndicator { running: true; size: BusyIndicatorSize.Medium }
                    Switch { checked: true }
                    Switch { checked: false }
                }
            }
        }
    }
}
