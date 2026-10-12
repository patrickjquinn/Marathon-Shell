pragma ComponentBehavior: Bound
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: root

    property int year: new Date().getFullYear()
    readonly property date today: new Date()

    signal monthChosen(int year, int month)

    color: MColors.background

    Item {
        id: header

        width: parent.width
        height: Math.round(96 * Constants.scaleFactor)

        Text {
            anchors.left: parent.left
            anchors.leftMargin: MSpacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: root.year
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeHuge
            font.weight: MTypography.weightExtraLight
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: MSpacing.sm
            anchors.verticalCenter: parent.verticalCenter

            MIconButton {
                iconName: "chevron-left"
                a11yName: "Previous year"
                onClicked: root.year--
            }

            MIconButton {
                iconName: "chevron-right"
                a11yName: "Next year"
                onClicked: root.year++
            }
        }
    }

    Flickable {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: monthGrid.height + MSpacing.xl * 4
        clip: true

        Grid {
            id: monthGrid

            x: MSpacing.md
            width: parent.width - MSpacing.md * 2
            columns: 3
            rowSpacing: MSpacing.lg
            columnSpacing: MSpacing.md

            Repeater {
                model: 12

                Item {
                    id: monthCell

                    required property int index
                    readonly property int firstDay: (new Date(root.year, index, 1).getDay() + 6) % 7
                    readonly property int daysInMonth: new Date(root.year, index + 1, 0).getDate()
                    readonly property bool isCurrentMonth: root.today.getFullYear() === root.year && root.today.getMonth() === index

                    width: (monthGrid.width - monthGrid.columnSpacing * 2) / 3
                    height: monthTitle.height + MSpacing.xs + miniDays.height

                    Accessible.role: Accessible.Button
                    Accessible.name: Qt.locale().standaloneMonthName(index) + " " + root.year
                    Accessible.onPressAction: root.monthChosen(root.year, index)

                    Text {
                        id: monthTitle

                        text: Qt.locale().standaloneMonthName(monthCell.index, Locale.ShortFormat)
                        color: monthCell.isCurrentMonth ? MColors.marathonTealBright : MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeSubhead
                        font.weight: MTypography.weightDemiBold
                    }

                    Grid {
                        id: miniDays

                        anchors.top: monthTitle.bottom
                        anchors.topMargin: MSpacing.xs
                        width: parent.width
                        columns: 7

                        Repeater {
                            model: 42

                            Item {
                                required property int index
                                readonly property int day: index - monthCell.firstDay + 1
                                readonly property bool isToday: monthCell.isCurrentMonth && day === root.today.getDate()

                                width: miniDays.width / 7
                                height: width

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: width
                                    radius: width / 2
                                    color: MColors.marathonTealBright
                                    visible: parent.isToday
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.day >= 1 && parent.day <= monthCell.daysInMonth
                                    text: parent.day
                                    color: parent.isToday ? MColors.textOnAccent : MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            root.monthChosen(root.year, monthCell.index);
                        }
                    }
                }
            }
        }
    }
}
