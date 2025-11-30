import QtQuick
import QtQml.Models
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Theme

Item {
    id: worldClockPage

    property var cities: []

    Component.onCompleted: {
        loadCities();
    }

    function loadCities() {
        var saved = SettingsManagerCpp.get("clock/worldCities", "");
        if (saved) {
            try {
                cities = JSON.parse(saved);
            } catch (e) {
                Logger.error("WorldClock", "Failed to load cities: " + e);
                cities = getDefaultCities();
            }
        } else {
            cities = getDefaultCities();
        }
        citiesChanged();
        updateTimeModel();
    }

    function saveCities() {
        var data = JSON.stringify(cities);
        SettingsManagerCpp.set("clock/worldCities", data);
    }

    function getDefaultCities() {
        return [
            {
                name: "New York",
                offset: -5,
                dst: true
            },
            {
                name: "London",
                offset: 0,
                dst: false
            },
            {
                name: "Tokyo",
                offset: 9,
                dst: false
            },
            {
                name: "Sydney",
                offset: 10,
                dst: false
            }
        ];
    }

    function addCity(name, offset, dst) {
        cities.push({
            name: name,
            offset: offset,
            dst: dst
        });
        citiesChanged();
        saveCities();
        updateTimeModel();
    }

    function removeCity(index) {
        cities.splice(index, 1);
        citiesChanged();
        saveCities();
        updateTimeModel();
    }

    function moveCity(from, to) {
        if (from === to || from < 0 || to < 0 || from >= cities.length || to >= cities.length)
            return;
        var item = cities.splice(from, 1)[0];
        cities.splice(to, 0, item);
        citiesChanged();
        saveCities();
    }

    function updateTimeModel() {
        visualModel.model.clear();
        var now = new Date();
        for (var i = 0; i < cities.length; i++) {
            var city = cities[i];
            var cityTime = new Date(now.getTime() + (city.offset * 3600000));
            var hours = cityTime.getUTCHours();
            var minutes = cityTime.getUTCMinutes();
            var ampm = hours >= 12 ? "PM" : "AM";
            hours = hours % 12;
            if (hours === 0)
                hours = 12;
            var timeStr = hours + ":" + (minutes < 10 ? "0" : "") + minutes + " " + ampm;

            visualModel.model.append({
                cityName: city.name,
                cityTime: timeStr,
                timeDiff: (city.offset >= 0 ? "+" : "") + city.offset + "h",
                cityIndex: i
            });
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            updateTimeModel();
        }
    }

    DelegateModel {
        id: visualModel
        model: ListModel {
            id: timeModel
        }

        delegate: Item {
            id: delegateRoot
            width: cityList.width
            height: Constants.touchTargetLarge

            property int heldIndex: -1
            property int dropIndex: -1

            Rectangle {
                id: content
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
                width: delegateRoot.width
                height: delegateRoot.height
                color: dragArea.drag.active ? MColors.elevated : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Drag.active: dragArea.drag.active
                Drag.source: delegateRoot
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                states: State {
                    when: dragArea.drag.active

                    ParentChange {
                        target: content
                        parent: cityList
                    }
                    AnchorChanges {
                        target: content
                        anchors {
                            horizontalCenter: undefined
                            verticalCenter: undefined
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.lg
                    anchors.rightMargin: MSpacing.lg
                    spacing: MSpacing.md

                    Column {
                        width: parent.width - timeText.width - deleteButton.width - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: MSpacing.xs

                        Text {
                            text: model.cityName
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeBody
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: model.timeDiff
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeSmall
                        }
                    }

                    Text {
                        id: timeText
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.cityTime
                        color: MColors.marathonTeal
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Bold
                    }

                    MIconButton {
                        id: deleteButton
                        width: Constants.touchTargetMedium
                        height: Constants.touchTargetMedium
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "trash-2"
                        iconSize: Constants.iconSizeSmall
                        variant: "ghost"
                        onClicked: {
                            HapticService.light();
                            worldClockPage.removeCity(model.cityIndex);
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: MSpacing.lg
                    anchors.rightMargin: MSpacing.lg
                    height: Constants.borderWidthThin
                    color: MColors.border
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    drag.target: content
                    drag.axis: Drag.YAxis

                    onPressed: {
                        delegateRoot.heldIndex = delegateRoot.DelegateModel.itemsIndex;
                    }

                    onReleased: {
                        if (delegateRoot.dropIndex !== -1 && delegateRoot.heldIndex !== -1) {
                            var from = delegateRoot.heldIndex;
                            var to = delegateRoot.dropIndex;
                            if (from !== to) {
                                visualModel.items.move(from, to);
                                worldClockPage.moveCity(from, to);
                            }
                        }
                        delegateRoot.heldIndex = -1;
                        delegateRoot.dropIndex = -1;
                    }
                }
            }

            DropArea {
                anchors.fill: parent

                onEntered: function (drag) {
                    if (drag && drag.source && drag.source !== delegateRoot && drag.source.heldIndex !== -1) {
                        drag.source.dropIndex = delegateRoot.DelegateModel.itemsIndex;
                    }
                }

                onExited: function (drag) {
                    if (drag && drag.source && drag.source !== delegateRoot) {
                        drag.source.dropIndex = -1;
                    }
                }
            }
        }
    }

    ListView {
        id: cityList
        anchors.fill: parent
        anchors.topMargin: MSpacing.md
        clip: true
        model: visualModel
        spacing: 0

        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: 200
                easing.type: Easing.OutQuad
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, Constants.screenWidth * 0.6)
        height: emptyColumn.height
        color: "transparent"
        visible: cityList.count === 0

        Column {
            id: emptyColumn
            anchors.centerIn: parent
            spacing: MSpacing.lg

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🌍"
                font.pixelSize: Constants.iconSizeXLarge * 2
                opacity: 0.5
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No cities added"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Medium
            }

            Text {
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Tap the + button to add a city"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    MIconButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        iconName: "plus"
        iconSize: 28
        variant: "primary"
        shape: "circular"
        onClicked: {
            HapticService.light();
            addCityDialogLoader.item.open();
        }
    }

    Loader {
        id: addCityDialogLoader
        anchors.fill: parent
        active: true
        asynchronous: true
        source: "../components/AddCityDialog.qml"

        Connections {
            target: addCityDialogLoader.item
            function onCityAdded(name, offset) {
                worldClockPage.addCity(name, offset, false);
            }
        }
    }
}
