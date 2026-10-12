pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: dateTimePage

    property string pageName: "datetime"
    readonly property string currentZone: SettingsManagerCpp.timeZone || "UTC"

    pageTitle: "Date & Time"

    // Takes the zone so the binding re-runs when it changes.
    function previewTime(zone, format) {
        return Qt.formatTime(new Date(), format === "24h" ? "HH:mm" : "h:mm AP");
    }

    TimeZoneList {
        id: zoneList
    }

    content: Item {
        Column {
            id: pageHeader

            width: parent.width
            spacing: MSpacing.md
            topPadding: MSpacing.lg
            bottomPadding: MSpacing.md

            MSection {
                x: MSpacing.lg
                width: parent.width - MSpacing.lg * 2
                title: "Clock"
                eyebrow: true

                MSettingsListItem {
                    title: "24-Hour Time"
                    subtitle: dateTimePage.previewTime(dateTimePage.currentZone, SettingsManagerCpp.timeFormat)
                    showToggle: true
                    toggleValue: SettingsManagerCpp.timeFormat === "24h"
                    onToggleChanged: value => SettingsManagerCpp.timeFormat = value ? "24h" : "12h"
                }

                MSettingsListItem {
                    title: "Time Zone"
                    value: zoneList.displayName(dateTimePage.currentZone)
                }
            }

            // Outside the list: a ListView header is rebuilt when the model changes, which dropped focus mid-word.
            MSearchField {
                id: zoneSearch

                x: MSpacing.lg
                width: parent.width - MSpacing.lg * 2
                placeholder: "Search cities or regions"
            }
        }

        ListView {
            id: zoneView

            anchors.top: pageHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: zoneList.search(zoneSearch.text)
            bottomMargin: Constants.navBarHeight

            delegate: Item {
                id: zoneRow

                required property var modelData
                readonly property bool selected: modelData.id === dateTimePage.currentZone

                width: zoneView.width
                height: Math.round(56 * Constants.scaleFactor)

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.city + ", " + modelData.region + ", " + modelData.offset
                Accessible.checked: selected
                Accessible.onPressAction: SettingsManagerCpp.timeZone = modelData.id

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.lg
                    anchors.rightMargin: MSpacing.lg
                    radius: MRadius.md
                    color: zoneMouse.pressed ? MColors.ripple : (zoneRow.selected ? MColors.marathonTealGlowMid : "transparent")
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: MSpacing.lg + MSpacing.md
                    anchors.right: offsetText.left
                    anchors.rightMargin: MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: zoneRow.modelData.city
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        font.weight: zoneRow.selected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: zoneRow.modelData.region
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeFootnote
                        font.family: MTypography.fontFamily
                    }
                }

                Text {
                    id: offsetText

                    anchors.right: checkIcon.left
                    anchors.rightMargin: MSpacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    text: zoneRow.modelData.offset
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                }

                Icon {
                    id: checkIcon

                    anchors.right: parent.right
                    anchors.rightMargin: MSpacing.lg + MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"
                    size: Math.round(20 * Constants.scaleFactor)
                    color: MColors.accentBright
                    opacity: zoneRow.selected ? 1 : 0
                }

                MouseArea {
                    id: zoneMouse

                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        SettingsManagerCpp.timeZone = zoneRow.modelData.id;
                    }
                }
            }

            MEmptyState {
                anchors.centerIn: parent
                width: parent.width - MSpacing.xxl
                visible: zoneView.count === 0
                iconName: "magnifying-glass"
                title: "No matching time zones"
                message: "Try a nearby city or a region such as Europe or America."
            }
        }
    }
}
