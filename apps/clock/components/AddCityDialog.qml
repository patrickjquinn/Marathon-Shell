pragma ComponentBehavior: Bound
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: addCityDialog

    property var availableCities: [
        {
            "name": "New York",
            "tz": "America/New_York",
            "offset": -5
        },
        {
            "name": "Los Angeles",
            "tz": "America/Los_Angeles",
            "offset": -8
        },
        {
            "name": "Chicago",
            "tz": "America/Chicago",
            "offset": -6
        },
        {
            "name": "Toronto",
            "tz": "America/Toronto",
            "offset": -5
        },
        {
            "name": "Mexico City",
            "tz": "America/Mexico_City",
            "offset": -6
        },
        {
            "name": "São Paulo",
            "tz": "America/Sao_Paulo",
            "offset": -3
        },
        {
            "name": "London",
            "tz": "Europe/London",
            "offset": 0
        },
        {
            "name": "Paris",
            "tz": "Europe/Paris",
            "offset": 1
        },
        {
            "name": "Berlin",
            "tz": "Europe/Berlin",
            "offset": 1
        },
        {
            "name": "Rome",
            "tz": "Europe/Rome",
            "offset": 1
        },
        {
            "name": "Madrid",
            "tz": "Europe/Madrid",
            "offset": 1
        },
        {
            "name": "Amsterdam",
            "tz": "Europe/Amsterdam",
            "offset": 1
        },
        {
            "name": "Stockholm",
            "tz": "Europe/Stockholm",
            "offset": 1
        },
        {
            "name": "Moscow",
            "tz": "Europe/Moscow",
            "offset": 3
        },
        {
            "name": "Dubai",
            "tz": "Asia/Dubai",
            "offset": 4
        },
        {
            "name": "Mumbai",
            "tz": "Asia/Kolkata",
            "offset": 5.5
        },
        {
            "name": "Bangkok",
            "tz": "Asia/Bangkok",
            "offset": 7
        },
        {
            "name": "Singapore",
            "tz": "Asia/Singapore",
            "offset": 8
        },
        {
            "name": "Hong Kong",
            "tz": "Asia/Hong_Kong",
            "offset": 8
        },
        {
            "name": "Shanghai",
            "tz": "Asia/Shanghai",
            "offset": 8
        },
        {
            "name": "Beijing",
            "tz": "Asia/Shanghai",
            "offset": 8
        },
        {
            "name": "Tokyo",
            "tz": "Asia/Tokyo",
            "offset": 9
        },
        {
            "name": "Seoul",
            "tz": "Asia/Seoul",
            "offset": 9
        },
        {
            "name": "Sydney",
            "tz": "Australia/Sydney",
            "offset": 10
        },
        {
            "name": "Melbourne",
            "tz": "Australia/Melbourne",
            "offset": 10
        },
        {
            "name": "Auckland",
            "tz": "Pacific/Auckland",
            "offset": 12
        }
    ]
    property string searchQuery: ""

    signal cityAdded(string name, real offset, string tz)

    function open() {
        visible = true;
        searchInput.clear();
        filterCities();
        searchInput.focusInput();
    }

    function close() {
        visible = false;
    }

    function filterCities() {
        filteredCities.clear();
        var query = searchQuery.toLowerCase();
        for (var i = 0; i < availableCities.length; i++) {
            var city = availableCities[i];
            if (query === "" || city.name.toLowerCase().indexOf(query) !== -1)
                filteredCities.append({
                    "cityName": city.name,
                    "cityTz": city.tz,
                    "cityOffset": city.offset
                });
        }
    }

    visible: false
    anchors.fill: parent
    z: Constants.zIndexModalOverlay
    onSearchQueryChanged: filterCities()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)

        MouseArea {
            anchors.fill: parent
            onClicked: addCityDialog.close()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 400)
        height: Math.min(parent.height * 0.8, 600)
        color: MColors.background
        radius: MRadius.lg

        Column {
            anchors.fill: parent
            anchors.margins: MSpacing.lg
            spacing: MSpacing.md

            Row {
                width: parent.width
                height: Constants.touchTargetMedium
                spacing: MSpacing.md

                Text {
                    width: parent.width - Constants.touchTargetMedium - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add City"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.Bold
                }

                MIconButton {
                    id: closeButton

                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "x"
                    iconSize: 20
                    variant: "ghost"
                    a11yName: "Close"
                    onClicked: {
                        HapticService.light();
                        addCityDialog.close();
                    }
                }
            }

            MSearchField {
                id: searchInput

                width: parent.width
                placeholder: "Search cities"
                onTextChanged: addCityDialog.searchQuery = text
            }

            ListView {
                width: parent.width
                height: parent.height - parent.spacing * 2 - Constants.touchTargetMedium - searchInput.height
                clip: true
                spacing: 0

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.8
                    height: noResultsText.height
                    color: "transparent"
                    visible: parent.count === 0

                    Text {
                        id: noResultsText

                        anchors.centerIn: parent
                        text: "No cities found"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeBody
                    }
                }

                model: ListModel {
                    id: filteredCities
                }

                delegate: Item {
                    id: cityDelegate

                    required property string cityName
                    required property string cityTz
                    required property real cityOffset

                    width: ListView.view.width
                    height: Constants.touchTargetMedium

                    MouseArea {
                        anchors.fill: parent
                        Accessible.role: Accessible.Button
                        Accessible.name: "Add " + cityDelegate.cityName
                        Accessible.onPressAction: clicked(null)
                        onClicked: {
                            HapticService.light();
                            addCityDialog.cityAdded(cityDelegate.cityName, cityDelegate.cityOffset, cityDelegate.cityTz);
                            addCityDialog.close();
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: parent.pressed ? MColors.elevated : "transparent"
                            radius: MRadius.md

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: MSpacing.md
                                anchors.rightMargin: MSpacing.md
                                spacing: MSpacing.md

                                Column {
                                    width: parent.width - offsetText.width - parent.spacing
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        text: cityDelegate.cityName
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: Font.Medium
                                    }
                                }

                                Text {
                                    id: offsetText

                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (cityDelegate.cityOffset >= 0 ? "+" : "") + cityDelegate.cityOffset + "h"
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeBody
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
