// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// What booster-keel compiles before an app is launched (ADR-0016). The
// first group is instantiated once (images, fonts, scene graph and shader
// setup), the second only compiled. The choice of types follows what
// mapplauncherd-booster-silica preloads for Qt 5 Silica apps.
import QtQuick 2.6
import Sailfish.Silica 1.0

ApplicationWindow {
    // No cover window in the booster: Lipstick would show it.
    cover: null
    initialPage: Component {
        Page {
            SilicaFlickable {
                anchors.fill: parent
                PullDownMenu { MenuItem { text: "x" } }
                Column {
                    width: parent.width
                    PageHeader { title: "x" }
                    BackgroundItem { Label { text: "x" } }
                    Button { text: "x" }
                    Slider { }
                    Switch { }
                    TextSwitch { text: "x" }
                    SectionHeader { text: "x" }
                }
            }
        }
    }
    Component {
        Item {
            BusyIndicator { }
            ColumnView { }
            ComboBox { }
            ContextMenu { }
            CoverBackground { CoverActionList { CoverAction { } } }
            CoverPlaceholder { }
            DatePicker { }
            Dialog { DialogHeader { } }
            DockedPanel { }
            IconButton { }
            SilicaListView {
                VerticalScrollDecorator { }
                PushUpMenu { }
                ViewPlaceholder { }
                delegate: ListItem { }
            }
            SilicaGridView { }
            RemorseItem { }
            RemorsePopup { }
            SearchField { }
            TextArea { }
            TextField { }
            ValueButton { }
            DetailItem { }
            OpacityRampEffect { }
        }
    }
}
