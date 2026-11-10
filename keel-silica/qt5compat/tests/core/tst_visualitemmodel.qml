// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// VisualItemModel under `import QtQuick 2.1` (communi's dialogs), and Qt
// Quick types still resolving through the QtQuick.2.<minor> re-export.
import QtQuick 2.1
import QtTest 1.0

Item {
    width: 200; height: 200

    ListView {
        id: view
        anchors.fill: parent
        model: VisualItemModel {
            id: model
            Rectangle { width: 10; height: 20; color: "red" }
            Text { text: "two" }
            Item { height: 5 }
        }
    }
    Timer { id: timer; interval: 1 }
    QtObject { id: plainObject; property int x: 4 }
    Connections { id: conn; target: null }

    TestCase {
        name: "VisualItemModel"
        when: windowShown

        function test_model() {
            compare(model.count, 3)
            compare(view.count, 3)
            compare(model.get(1).text, "two")
        }
        function test_qtquick_and_qtqml_types_still_resolve() {
            verify(timer)
            compare(plainObject.x, 4)
            verify(conn)
        }
    }
}
