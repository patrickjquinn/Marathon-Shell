// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Underline (Sailfish.Silica.private): a horizontal line fading from
// `primaryColor` to `secondaryColor`; the base of Silica's BSD
// Separator.qml (names inferred from it). Keel's stand-in: a gradient whose
// `primaryColor` end follows `horizontalAlignment` (left, centre or right).
import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as S // Silica's Screen (an unqualified Screen is Qt Quick's)

Item {
    id: line

    property color primaryColor
    property color secondaryColor
    property int horizontalAlignment: Qt.AlignLeft

    width: parent ? parent.width : S.Screen.width
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: line.horizontalAlignment === Qt.AlignRight || line.horizontalAlignment === Qt.AlignHCenter
                       ? line.secondaryColor : line.primaryColor
            }
            GradientStop {
                position: 0.5
                color: line.horizontalAlignment === Qt.AlignHCenter
                       ? line.primaryColor : Qt.tint(line.secondaryColor, Theme.rgba(line.primaryColor, line.primaryColor.a / 2))
            }
            GradientStop {
                position: 1.0
                color: line.horizontalAlignment === Qt.AlignRight ? line.primaryColor : line.secondaryColor
            }
        }
    }
}
