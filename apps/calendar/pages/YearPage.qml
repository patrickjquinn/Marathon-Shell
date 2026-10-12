pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property int year: new Date().getFullYear()
    readonly property date today: new Date()
    readonly property int weekStart: Qt.locale().firstDayOfWeek

    signal monthChosen(int year, int month)

    SilicaFlickable {
        objectName: "yearView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "previousYearItem"
                text: qsTr("Previous year")
                onClicked: page.year--
            }
            MenuItem {
                objectName: "thisYearItem"
                text: qsTr("This year")
                visible: page.year !== page.today.getFullYear()
                onClicked: page.year = page.today.getFullYear()
            }
            MenuItem {
                objectName: "nextYearItem"
                text: qsTr("Next year")
                onClicked: page.year++
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                objectName: "yearHeader"
                title: page.year
            }

            Grid {
                id: grid

                x: Theme.horizontalPageMargin - Theme.paddingSmall
                width: parent.width - 2 * x
                columns: 3
                rowSpacing: Theme.paddingLarge

                Repeater {
                    objectName: "months"
                    model: 12

                    BackgroundItem {
                        id: monthCell

                        required property int index
                        readonly property int offset: (new Date(page.year, index, 1).getDay() - page.weekStart + 7) % 7
                        readonly property int days: new Date(page.year, index + 1, 0).getDate()
                        readonly property bool current: page.today.getFullYear() === page.year && page.today.getMonth() === index

                        width: grid.width / 3
                        height: monthTitle.height + miniDays.height + 2 * Theme.paddingSmall
                        Accessible.name: Qt.locale().standaloneMonthName(index) + " " + page.year
                        onClicked: page.monthChosen(page.year, index)

                        Label {
                            id: monthTitle

                            x: Theme.paddingSmall
                            y: Theme.paddingSmall
                            text: Qt.locale().standaloneMonthName(monthCell.index, Locale.ShortFormat)
                            color: monthCell.current || monthCell.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        Grid {
                            id: miniDays

                            anchors {
                                top: monthTitle.bottom
                                left: parent.left
                                right: parent.right
                                margins: Theme.paddingSmall
                            }
                            columns: 7

                            Repeater {
                                model: 42

                                Label {
                                    required property int index
                                    readonly property int day: index - monthCell.offset + 1
                                    readonly property bool isToday: monthCell.current && day === page.today.getDate()

                                    width: miniDays.width / 7
                                    horizontalAlignment: Text.AlignHCenter
                                    text: day >= 1 && day <= monthCell.days ? day : ""
                                    font.pixelSize: Theme.fontSizeTiny
                                    color: isToday ? Theme.highlightColor : Theme.secondaryColor
                                }
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
