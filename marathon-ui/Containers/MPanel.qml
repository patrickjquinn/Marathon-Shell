import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects

Rectangle {
    id: root

    property string header: ""
    property alias content: panelContent.data
    property alias actions: headerActions.data
    property bool collapsible: false
    property bool collapsed: false

    signal headerClicked

    implicitWidth: parent ? parent.width : 400
    height: collapsed ? headerRect.height : (headerRect.height + panelContent.implicitHeight)

    color: MColors.bb10Elevated
    radius: MRadius.lg
    border.width: 1
    border.color: MColors.borderGlass

    Accessible.role: Accessible.Grouping
    Accessible.name: header

    Behavior on height {
        NumberAnimation {
            duration: MMotion.quick
            easing.bezierCurve: MMotion.easingStandardCurve
        }
    }

    // Performant shadow using simple rectangle (60fps on PinePhone!)
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.leftMargin: -1
        anchors.rightMargin: -1
        anchors.bottomMargin: -3
        z: -1
        radius: parent.radius
        color: Qt.rgba(0, 0, 0, 0.2)
        opacity: 0.3
    }

    layer.enabled: false

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: MColors.highlightSubtle
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: headerRect
            width: parent.width
            height: root.header !== "" ? 56 : 0
            color: headerMouseArea.pressed ? MColors.highlightSubtle : "transparent"
            radius: root.radius
            visible: root.header !== ""

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.lg
                anchors.rightMargin: MSpacing.lg
                spacing: MSpacing.md

                Text {
                    text: root.header
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.weight: MTypography.weightDemiBold
                    font.family: MTypography.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - headerActions.width - chevronIcon.width - (parent.spacing * 2)
                }

                Row {
                    id: headerActions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: MSpacing.sm
                }

                Icon {
                    id: chevronIcon
                    name: "chevron-down"
                    size: 18
                    color: MColors.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: root.collapsed ? -90 : 0
                    visible: root.collapsible

                    Behavior on rotation {
                        NumberAnimation {
                            duration: MMotion.quick
                        }
                    }
                }
            }

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                enabled: root.collapsible
                cursorShape: root.collapsible ? Qt.PointingHandCursor : Qt.ArrowCursor

                onClicked: {
                    if (root.collapsible) {
                        root.collapsed = !root.collapsed;
                        MHaptics.lightImpact();
                    }
                    root.headerClicked();
                }
            }
        }

        Item {
            id: panelContent
            width: parent.width
            height: root.collapsed ? 0 : implicitHeight
            implicitHeight: childrenRect.height
            clip: true
            visible: !root.collapsed

            Behavior on height {
                NumberAnimation {
                    duration: MMotion.quick
                }
            }
        }
    }
}
