pragma ComponentBehavior: Bound

import MarathonApp.Store
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Categories grid, then the top-charts list.
Flickable {
    id: page

    required property var store

    contentWidth: width
    contentHeight: column.height + MSpacing.xl
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: column
        width: page.width
        topPadding: page.store.dp(14)
        spacing: MSpacing.xl

        Column {
            width: parent.width
            spacing: page.store.dp(10)

            SectionHeader {
                width: parent.width
                title: "Categories"
            }

            Grid {
                id: grid
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                columns: 2
                spacing: MSpacing.sm

                Repeater {
                    model: page.store.categories
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        width: (grid.width - grid.spacing) / 2
                        height: page.store.dp(56)
                        radius: MRadius.lg
                        color: tap.pressed ? MColors.elev3 : MColors.elev2
                        border.width: 1
                        border.color: MColors.whiteOverlay06

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: page.store.dp(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: page.store.dp(10)
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: chip.modelData.icon
                                size: page.store.dp(22)
                                color: MColors.marathonTealBright
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: chip.width - page.store.dp(14 + 22 + 10 + 10)
                                text: chip.modelData.label
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Medium
                                lineHeight: 0.95
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: tap
                            anchors.fill: parent
                            onClicked: {
                                HapticService.light();
                                page.store.openCategory(chip.modelData.id, chip.modelData.label);
                            }
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.topApps.length > 0

            SectionHeader {
                width: parent.width
                title: "Top charts"
                subtitle: "Most installed this month"
            }

            Column {
                width: parent.width
                Repeater {
                    model: page.store.topApps
                    delegate: AppRow {
                        required property var modelData
                        required property int index
                        width: parent.width
                        store: page.store
                        app: modelData
                        rank: index + 1
                        showDivider: index < page.store.topApps.length - 1
                    }
                }
            }
        }
    }
}
