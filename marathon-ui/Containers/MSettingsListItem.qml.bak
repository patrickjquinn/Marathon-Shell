import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import MarathonOS.Shell
import QtQuick

Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property string value: ""
    property bool showChevron: false
    property bool showToggle: false
    property bool toggleValue: false
    property bool showDivider: true

    signal settingClicked
    signal toggleChanged(bool value)

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    width: parent ? parent.width : 0
    // Publish the natural size as implicitHeight so callers can override
    // height (collapse to 0, animate) and still ask what it wants to be.
    // Same defect class as MEmptyState: a caller binding height to
    // implicitHeight got 0 and the unclipped content painted over whatever
    // sat above the row.
    implicitHeight: Math.round((subtitle !== "" ? 72 : 56) * scaleFactor)
    height: implicitHeight
    color: "transparent"
    // Default a11y wiring -- every settings row is announced as an interactive
    // list item with title + value/subtitle. Toggles get CheckBox role with
    // checked state so screen readers announce on/off.
    Accessible.role: showToggle ? Accessible.CheckBox : Accessible.ListItem
    Accessible.name: title
    Accessible.description: subtitle.length > 0 ? subtitle : value
    Accessible.checked: showToggle && toggleValue
    Accessible.onPressAction: settingClicked()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.02)
        opacity: mouseArea.pressed ? 1 : 0
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.04)
        radius: MRadius.sm

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.marathonTeal
        opacity: mouseArea.pressed ? 0.05 : 0
        radius: MRadius.sm

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.micro
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md

        // DS Row spec — icon container is a 32 × 32 elev-3 fill
        // (ds-components.jsx Cards & list rows · 'Icon container').
        // The previous treatment was a bare icon flat against the
        // text which lost the carded-row visual rhythm.
        Rectangle {
            id: iconBay

            visible: iconName !== ""
            width: Math.round(32 * root.scaleFactor)
            height: Math.round(32 * root.scaleFactor)
            radius: MRadius.md
            color: MColors.elev3
            anchors.left: parent.left
// One rule for the whole row: leading icon and trailing
            // value/chevron both sit on the title's line. Centring the icon on
            // the row while the value tracks the title would reintroduce the
            // same split this fix removes, just on the other side.
            anchors.verticalCenter: titleColumn.verticalCenter
            anchors.verticalCenterOffset: -Math.round((titleColumn.height - titleText.height) / 2)

            Icon {
                id: iconImage
                anchors.centerIn: parent
                name: iconName
                size: Math.round(18 * root.scaleFactor)
                color: MColors.textPrimary
            }
        }

        Column {
            id: titleColumn

            anchors.left: iconBay.visible ? iconBay.right : parent.left
            anchors.leftMargin: iconBay.visible ? Math.round(14 * root.scaleFactor) : 0
            anchors.right: rightContent.left
            anchors.rightMargin: MSpacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // Title — Subhead 15 / 500 per DS Row spec.
            Text {
                id: titleText

                text: title
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: MTypography.weightMedium
                font.letterSpacing: MTypography.trackingSubhead
                elide: Text.ElideRight
                width: parent.width
            }

            // Subtitle — Footnote 13 / 400 / secondary per DS.
            Text {
                visible: subtitle !== ""
                text: subtitle
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.weight: MTypography.weightRegular
                elide: Text.ElideRight
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
        }

        Item {
            id: rightContent

            // Align to the TITLE, not the row. Both this and titleColumn used
            // parent.verticalCenter — which coincide only when there is no
            // subtitle. With one, the column centres and pushes the title above
            // centre while the value stays on it: "Clock Position" sat 34 px
            // above its own "Center" value, while single-line rows lined up
            // exactly. Anchoring here keeps value, chevron and toggle on the
            // title's optical line in both cases.
            anchors.right: parent.right
            anchors.verticalCenter: titleColumn.verticalCenter
            anchors.verticalCenterOffset: -Math.round((titleColumn.height - titleText.height) / 2)
            width: showToggle ? Math.round(76 * root.scaleFactor) : showChevron ? (valueText.visible ? valueText.width + Math.round(36 * root.scaleFactor) : Math.round(20 * root.scaleFactor)) : (valueText.visible ? valueText.width : 0)
            height: parent.height

            MToggle {
                id: toggle

                visible: showToggle
                checked: toggleValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onToggled: {
                    root.toggleChanged(checked);
                }
            }

            // Value — Body 14 / 400 / secondary / tabular per DS.
            Text {
                id: valueText

                visible: value !== "" && !showToggle
                text: value
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.weight: MTypography.weightRegular
                font.features: ({
                        "tnum": 1
                    })
                anchors.right: chevronIcon.visible ? chevronIcon.left : parent.right
                anchors.rightMargin: chevronIcon.visible ? MSpacing.md : 0
                anchors.verticalCenter: parent.verticalCenter
            }

            Icon {
                id: chevronIcon

                visible: showChevron && !showToggle
                name: "chevron-right"
                size: Math.round(18 * root.scaleFactor)
                color: MColors.textTertiary
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Divider — w-04 hairline indented past the icon column,
    // per DS Cards & list rows · 'Divider: 1px var(--w-04)
    // between siblings only'.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: iconName !== "" ? Math.round((16 + 32 + 14) * root.scaleFactor) : MSpacing.md
        height: 1
        color: MColors.whiteOverlay04
        visible: root.showDivider
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: !showToggle
        onClicked: {
            root.settingClicked();
        }
    }

    transform: Translate {
        y: mouseArea.pressed && !showToggle ? -2 : 0

        Behavior on y {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }
    }
}
