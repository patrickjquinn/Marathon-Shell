import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Theme

Item {
    id: addCityDialog
    visible: false
    anchors.fill: parent
    z: Constants.zIndexModalOverlay

    signal cityAdded(string name, int offset)

    function open() {
        visible = true;
        searchQuery = "";
        filterCities();
        if (searchInput && searchInput.forceActiveFocus) {
            searchInput.forceActiveFocus();
        }
    }

    function close() {
        visible = false;
    }

    function filterCities() {
        filteredCities.clear();
        var query = searchQuery.toLowerCase();
        for (var i = 0; i < availableCities.length; i++) {
            var city = availableCities[i];
            if (query === "" || city.name.toLowerCase().indexOf(query) !== -1) {
                filteredCities.append({
                    cityName: city.name,
                    cityOffset: city.offset
                });
            }
        }
    }

    property var availableCities: [
        {
            name: "New York",
            offset: -5
        },
        {
            name: "Los Angeles",
            offset: -8
        },
        {
            name: "Chicago",
            offset: -6
        },
        {
            name: "Toronto",
            offset: -5
        },
        {
            name: "Mexico City",
            offset: -6
        },
        {
            name: "São Paulo",
            offset: -3
        },
        {
            name: "London",
            offset: 0
        },
        {
            name: "Paris",
            offset: 1
        },
        {
            name: "Berlin",
            offset: 1
        },
        {
            name: "Rome",
            offset: 1
        },
        {
            name: "Madrid",
            offset: 1
        },
        {
            name: "Amsterdam",
            offset: 1
        },
        {
            name: "Stockholm",
            offset: 1
        },
        {
            name: "Moscow",
            offset: 3
        },
        {
            name: "Dubai",
            offset: 4
        },
        {
            name: "Mumbai",
            offset: 5.5
        },
        {
            name: "Bangkok",
            offset: 7
        },
        {
            name: "Singapore",
            offset: 8
        },
        {
            name: "Hong Kong",
            offset: 8
        },
        {
            name: "Shanghai",
            offset: 8
        },
        {
            name: "Beijing",
            offset: 8
        },
        {
            name: "Tokyo",
            offset: 9
        },
        {
            name: "Seoul",
            offset: 9
        },
        {
            name: "Sydney",
            offset: 10
        },
        {
            name: "Melbourne",
            offset: 10
        },
        {
            name: "Auckland",
            offset: 12
        }
    ]

    property string searchQuery: ""

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
                    onClicked: {
                        HapticService.light();
                        addCityDialog.close();
                    }
                }
            }

            MTextInput {
                id: searchInput
                width: parent.width
                placeholderText: "Search cities..."
                onTextChanged: {
                    searchQuery = text;
                }
            }

            ListView {
                width: parent.width
                height: parent.height - parent.spacing * 2 - Constants.touchTargetMedium - Math.round(48 * Constants.scaleFactor)
                clip: true
                model: ListModel {
                    id: filteredCities
                }
                spacing: 0

                delegate: Item {
                    width: ListView.view.width
                    height: Constants.touchTargetMedium

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            addCityDialog.cityAdded(model.cityName, model.cityOffset);
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
                                        text: model.cityName
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: Font.Medium
                                    }
                                }

                                Text {
                                    id: offsetText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (model.cityOffset >= 0 ? "+" : "") + model.cityOffset + "h"
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeBody
                                }
                            }
                        }
                    }
                }

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
            }
        }
    }
}
