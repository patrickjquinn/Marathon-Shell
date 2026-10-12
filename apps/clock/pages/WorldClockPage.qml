pragma ComponentBehavior: Bound
import MarathonApp.Clock
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQml.Models
import QtQuick

Item {
    id: worldClockPage

    property var cities: []
    property AddCityDialog addCityDialog: null
    property var lastRemoved: null
    readonly property int backLayers: addCityDialog && addCityDialog.visible ? 1 : 0

    function handleBack() {
        addCityDialog.close();
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
                "name": "New York",
                "tz": "America/New_York",
                "offset": -5
            },
            {
                "name": "London",
                "tz": "Europe/London",
                "offset": 0
            },
            {
                "name": "Tokyo",
                "tz": "Asia/Tokyo",
                "offset": 9
            },
            {
                "name": "Sydney",
                "tz": "Australia/Sydney",
                "offset": 10
            }
        ];
    }

    // Cities saved before zones were stored only have a fixed offset.
    function zoneFor(city) {
        if (city.tz)
            return city.tz;
        var known = getDefaultCities();
        for (var i = 0; i < known.length; i++) {
            if (known[i].name === city.name)
                return known[i].tz;
        }
        return "";
    }

    function cityTimeInfo(city) {
        var tz = zoneFor(city);
        if (tz && typeof WorldClockHelper !== "undefined") {
            var r = WorldClockHelper.timeIn(tz);
            return {
                "time": r.time,
                "diff": r.offsetLabel
            };
        }
        return {
            "time": formatCityTime(city.offset),
            "diff": (city.offset >= 0 ? "+" : "") + city.offset + "h"
        };
    }

    function addCity(name, offset, tz) {
        cities.push({
            "name": name,
            "tz": tz,
            "offset": offset
        });
        citiesChanged();
        saveCities();
        updateTimeModel();
    }

    function removeCity(index) {
        lastRemoved = {
            "index": index,
            "city": cities.splice(index, 1)[0]
        };
        citiesChanged();
        saveCities();
        updateTimeModel();
        snackbar.show(lastRemoved.city.name + " removed", "Undo");
    }

    function restoreCity() {
        cities.splice(Math.min(lastRemoved.index, cities.length), 0, lastRemoved.city);
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

    function formatCityTime(offset) {
        var cityTime = new Date(Date.now() + offset * 3.6e+06);
        var hours = cityTime.getUTCHours();
        var minutes = cityTime.getUTCMinutes();
        var ampm = hours >= 12 ? "PM" : "AM";
        hours = hours % 12;
        if (hours === 0)
            hours = 12;
        return hours + ":" + (minutes < 10 ? "0" : "") + minutes + " " + ampm;
    }

    function refreshTimes() {
        // Rows are matched by name: drag-reordering moves cities but not timeModel.
        for (var i = 0; i < timeModel.count; i++) {
            var row = timeModel.get(i);
            var city = cities.find(c => c.name === row.cityName) || {
                "name": row.cityName,
                "offset": row.offset
            };
            var info = cityTimeInfo(city);
            timeModel.setProperty(i, "cityTime", info.time);
            timeModel.setProperty(i, "timeDiff", info.diff);
        }
    }

    function updateTimeModel() {
        timeModel.clear();
        for (var i = 0; i < cities.length; i++) {
            var city = cities[i];
            var info = cityTimeInfo(city);
            timeModel.append({
                "cityName": city.name,
                "cityTime": info.time,
                "timeDiff": info.diff,
                "offset": city.offset
            });
        }
    }

    Component.onCompleted: {
        loadCities();
    }

    Timer {
        interval: 1000
        running: worldClockPage.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: worldClockPage.refreshTimes()
    }

    DelegateModel {
        id: visualModel

        model: ListModel {
            id: timeModel
        }

        delegate: Item {
            id: delegateRoot

            required property string cityName
            required property string cityTime
            required property string timeDiff
            property int heldIndex: -1
            property int dropIndex: -1

            width: cityList.width
            height: Constants.touchTargetLarge

            Rectangle {
                id: content

                width: delegateRoot.width
                height: delegateRoot.height
                color: dragArea.drag.active ? MColors.elevated : "transparent"
                Drag.active: dragArea.drag.active
                Drag.source: delegateRoot
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
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
                            text: delegateRoot.cityName
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeBody
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: delegateRoot.timeDiff
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeSmall
                        }
                    }

                    Text {
                        id: timeText

                        anchors.verticalCenter: parent.verticalCenter
                        text: delegateRoot.cityTime
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
                        a11yName: "Remove " + delegateRoot.cityName
                        onClicked: {
                            HapticService.light();
                            worldClockPage.removeCity(delegateRoot.DelegateModel.itemsIndex);
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

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

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
            }

            DropArea {
                anchors.fill: parent
                onEntered: function (drag) {
                    var sourceItem = drag ? drag.source : null;
                    if (sourceItem && sourceItem !== delegateRoot)
                        sourceItem.dropIndex = delegateRoot.DelegateModel.itemsIndex;
                }
                onExited: {
                    var sourceItem = drag ? drag.source : null;
                    if (sourceItem && sourceItem !== delegateRoot)
                        sourceItem.dropIndex = -1;
                }
            }
        }
    }

    MTopBar {
        id: topBar
        width: parent.width
        title: "World Clock"
    }

    ListView {
        id: cityList

        anchors.fill: parent
        anchors.topMargin: topBar.height + MSpacing.md
        clip: true
        model: visualModel
        spacing: 0
        bottomMargin: fab.height + MSpacing.lg * 2

        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: 200
                easing.type: Easing.OutQuad
            }
        }
    }

    MEmptyState {
        anchors.centerIn: parent
        width: parent.width - MSpacing.xl * 2
        visible: cityList.count === 0
        iconName: "globe"
        iconSize: 64
        title: "No cities added"
        message: "Tap Add city to compare time zones."
    }

    MFloatingActionButton {
        id: fab

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        label: "Add city"
        onClicked: worldClockPage.addCityDialog.open()
    }

    MSnackbar {
        id: snackbar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: fab.top
        anchors.margins: MSpacing.md
        onActionTriggered: worldClockPage.restoreCity()
    }

    Loader {
        id: addCityDialogLoader

        anchors.fill: parent
        active: true
        asynchronous: true
        source: "../components/AddCityDialog.qml"
        onLoaded: worldClockPage.addCityDialog = item

        Connections {
            function onCityAdded(name, offset, tz) {
                worldClockPage.addCity(name, offset, tz);
            }

            target: addCityDialogLoader.item
        }
    }
}
