import "../UI"
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Item {
    id: layout

    property bool shifted: false
    property bool capsLock: false
    property string searchText: ""
    readonly property var recentEmojis: ["", "", "", "", "", "", "", "", "", ""]
    readonly property var smileys: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    readonly property var animals: ["", "", "", "", "", "", "", "", "‍", "", "", "", "cow", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "duck", "", ""]
    readonly property var categoryMap: {
        "recent": recentEmojis,
        "smileys": smileys,
        "animals": animals,
        "food": food,
        "activities": activities,
        "travel": travel,
        "objects": objects,
        "symbols": symbols,
        "flags": flags
    }
    readonly property var food: ["", "", "", "", "", "", "", "", "", "🫐", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🫑", "", "", "🫒", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🫓", "", "", "", "", "", "🫔", "", "", "🫕", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🫖", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    readonly property var activities: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "‍", "‍", "‍", "‍", "", "‍", "‍", "", "‍", "‍", "‍", "‍", "‍", "‍", "‍", "‍", "", "", "", "", "", "", "ros", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    readonly property var travel: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "camping", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    readonly property var objects: ["⌚", "", "", "", "⌨", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "⏱", "⏲", "⏰", "", "⌛", "⏳", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🪤", "", "", "", "", "", "", "", "", "", "", "", "", "", "🪦", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🪠", "", "", "", "", "", "", "", "", "🪥", "", "", "🪣", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🪧", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    readonly property var symbols: ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🆔", "", "🉑", "", "", "", "", "🈶", "🈚", "🈸", "🈺", "🈷", "", "🆚", "", "🉐", "㊙", "㊗", "🈴", "🈵", "🈹", "🈲", "🅰", "🅱", "🆎", "🆑", "🅾", "🆘", "", "⭕", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "‼", "⁉", "", "", "〽", "", "", "", "", "", "", "", "🈯", "", "", "", "", "", "", "Ⓜ", "", "", "", "", "", "🅿", "", "🈳", "🈂", "", "", "", "", "", "", "", "", "", "", "", "", "🈁", "", "ℹ", "", "", "", "🆖", "🆗", "🆙", "🆒", "🆕", "🆓", "0⃣", "1⃣", "2⃣", "3⃣", "4⃣", "5⃣", "6⃣", "7⃣", "8⃣", "9⃣", "", "", "#⃣", "*⃣", "⏏", "▶", "⏸", "⏯", "⏹", "⏺", "⏭", "⏮", "⏩", "⏪", "⏫", "⏬", "◀", "", "", "", "⬅", "⬆", "⬇", "↗", "↘", "↙", "↖", "↕", "↔", "↪", "↩", "⤴", "⤵", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "™", "©", "®", "‍", "", "", "", "", "", "〰", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "▪", "▫", "◾", "◽", "◼", "◻", "", "", "", "", "", "", "⬛", "⬜", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "🃏", "", "🀄", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    readonly property var flags: ["", "", "", "", "‍", "‍", "‍", "🇦🇫", "🇦🇽", "🇦🇱", "🇩🇿", "🇦🇸", "🇦🇩", "🇦🇴", "🇦🇮", "🇦🇶", "🇦🇬", "🇦🇷", "🇦🇲", "🇦🇼", "🇦🇺", "🇦🇹", "🇦🇿", "🇧🇸", "🇧🇭", "🇧🇩", "🇧🇧", "🇧🇾", "🇧🇪", "🇧🇿", "🇧🇯", "🇧🇲", "🇧🇹", "🇧🇴", "🇧🇦", "🇧🇼", "🇧🇷", "🇮🇴", "🇻🇬", "🇧🇳", "🇧🇬", "🇧🇫", "🇧🇮", "🇰🇭", "🇨🇲", "🇨🇦", "🇮🇨", "🇨🇻", "🇧🇶", "🇰🇾", "🇨🇫", "🇹🇩", "🇨🇱", "🇨🇳", "🇨🇽", "🇨🇨", "🇨🇴", "🇰🇲", "🇨🇬", "🇨🇩", "🇨🇰", "🇨🇷", "🇨🇮", "🇭🇷", "🇨🇺", "🇨🇼", "🇨🇾", "🇨🇿", "🇩🇰", "🇩🇯", "🇩🇲", "🇩🇴", "🇪🇨", "🇪🇬", "🇸🇻", "🇬🇶", "🇪🇷", "🇪🇪", "🇪🇹", "🇪🇺", "🇫🇰", "🇫🇴", "🇫🇯", "🇫🇮", "🇫🇷", "🇬🇫", "🇵🇫", "🇹🇫", "🇬🇦", "🇬🇲", "🇬🇪", "🇩🇪", "🇬🇭", "🇬🇮", "🇬🇷", "🇬🇱", "🇬🇩", "🇬🇵", "🇬🇺", "🇬🇹", "🇬🇬", "🇬🇳", "🇬🇼", "🇬🇾", "🇭🇹", "🇭🇳", "🇭🇰", "🇭🇺", "🇮🇸", "🇮🇳", "🇮🇩", "🇮🇷", "🇮🇶", "🇮🇪", "🇮🇲", "🇮🇱", "🇮🇹", "🇯🇲", "🇯🇵", "", "🇯🇪", "🇯🇴", "🇰🇿", "🇰🇪", "🇰🇮", "🇽🇰", "🇰🇼", "🇰🇬", "🇱🇦", "🇱🇻", "🇱🇧", "🇱🇸", "🇱🇷", "🇱🇾", "🇱🇮", "🇱🇹", "🇱🇺", "🇲🇴", "🇲🇰", "🇲🇬", "🇲🇼", "🇲🇾", "🇲🇻", "🇲🇱", "🇲🇹", "🇲🇭", "🇲🇶", "🇲🇷", "🇲🇺", "🇾🇹", "🇲🇽", "🇫🇲", "🇲🇩", "🇲🇨", "🇲🇳", "🇲🇪", "🇲🇸", "🇲🇦", "🇲🇿", "🇲🇲", "🇳🇦", "🇳🇷", "🇳🇵", "🇳🇱", "🇳🇨", "🇳🇿", "🇳🇮", "🇳🇪", "🇳🇬", "🇳🇺", "🇳🇫", "🇰🇵", "🇲🇵", "🇳🇴", "🇴🇲", "🇵🇰", "🇵🇼", "🇵🇸", "🇵🇦", "🇵🇬", "🇵🇾", "🇵🇪", "🇵🇭", "🇵🇳", "🇵🇱", "🇵🇹", "🇵🇷", "🇶🇦", "🇷🇪", "🇷🇴", "🇷🇺", "🇷🇼", "🇼🇸", "🇸🇲", "🇸🇦", "🇸🇳", "🇷🇸", "🇸🇨", "🇸🇱", "🇸🇬", "🇸🇽", "🇸🇰", "🇸🇮", "🇬🇸", "🇸🇧", "🇸🇴", "🇿🇦", "🇰🇷", "🇸🇸", "🇪🇸", "🇱🇰", "🇧🇱", "🇸🇭", "🇰🇳", "🇱🇨", "🇵🇲", "🇻🇨", "🇸🇩", "🇸🇷", "🇸🇿", "🇸🇪", "🇨🇭", "🇸🇾", "🇹🇼", "🇹🇯", "🇹🇿", "🇹🇭", "🇹🇱", "🇹🇬", "🇹🇰", "🇹🇴", "🇹🇹", "🇹🇳", "🇹🇷", "🇹🇲", "🇹🇨", "🇹🇻", "🇺🇬", "🇺🇦", "🇦🇪", "🇬🇧", "🇺🇸", "🇺🇾", "🇺🇿", "🇻🇺", "🇻🇦", "🇻🇪", "🇻🇳", "🇼🇫", "🇪🇭", "🇾🇪", "🇿🇲", "🇿🇼"]
    property string currentCategoryId: "smileys"
    property var displayedEmojis: {
        if (searchText.length > 0) {
            var all = [];
            for (var key in categoryMap) {
                all = all.concat(categoryMap[key]);
            }
            var unique = all.filter((item, pos) => {
                return all.indexOf(item) === pos;
            });
            return unique;
        }
        if (currentCategoryId === "recent") {
            var parentRecents = findParentKeyboard(layout);
            if (parentRecents)
                return parentRecents.recentEmojis;

            return recentEmojis;
        }
        return categoryMap[currentCategoryId] || smileys;
    }
    readonly property var categoryList: [
        {
            "icon": "clock",
            "id": "recent"
        },
        {
            "icon": "star",
            "id": "smileys"
        },
        {
            "icon": "tree-pine",
            "id": "animals"
        },
        {
            "icon": "coffee",
            "id": "food"
        },
        {
            "icon": "zap",
            "id": "activities"
        },
        {
            "icon": "plane",
            "id": "travel"
        },
        {
            "icon": "sun",
            "id": "objects"
        },
        {
            "icon": "hash",
            "id": "symbols"
        },
        {
            "icon": "globe",
            "id": "flags"
        }
    ]

    signal keyClicked(string text)
    signal backspaceClicked
    signal enterClicked
    signal spaceClicked
    signal layoutSwitchClicked(string layout)
    signal dismissClicked

    function getCategoryIndex(id) {
        for (var i = 0; i < categoryList.length; i++) {
            if (categoryList[i].id === id)
                return i;
        }
        return 0;
    }

    function findParentKeyboard(item) {
        var p = item.parent;
        while (p) {
            if (p.hasOwnProperty("recentEmojis"))
                return p;

            p = p.parent;
        }
        return null;
    }

    implicitHeight: layoutColumn.implicitHeight

    Column {
        id: layoutColumn

        width: parent.width
        spacing: 0

        Rectangle {
            width: parent.width
            height: Math.round(50 * Constants.scaleFactor)
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 24
                height: parent.height - 16
                color: "#333333"
                radius: 8

                Icon {
                    id: searchIcon

                    name: "search"
                    size: 16
                    color: "white"
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: 0.5
                }

                TextInput {
                    id: searchInput

                    anchors.left: searchIcon.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: "white"
                    font.pixelSize: 16
                    text: layout.searchText
                    onTextChanged: layout.searchText = text
                    onActiveFocusChanged: {
                        if (activeFocus && layout.searchText === "") {}
                    }

                    Text {
                        text: "Search emojis..."
                        color: "#888888"
                        visible: parent.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Icon {
                    name: "x"
                    size: 16
                    color: "white"
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: layout.searchText.length > 0

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            layout.searchText = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }
            }
        }

        GridView {
            id: emojiGrid

            width: parent.width
            height: Math.round(200 * Constants.scaleFactor)
            clip: true
            cellWidth: width / 8
            cellHeight: cellWidth
            model: layout.displayedEmojis

            delegate: Item {
                width: emojiGrid.cellWidth
                height: emojiGrid.cellHeight

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.family: "Noto Color Emoji"
                    font.pixelSize: 28
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        layout.keyClicked(modelData);
                        HapticManager.light();
                        if (layout.searchText.length > 0) {}
                    }
                }
            }
        }

        Item {
            id: bottomContainer

            width: parent.width
            height: layout.searchText.length > 0 ? searchKeyboard.height : categoryRow.height

            Row {
                id: categoryRow

                width: parent.width
                height: Math.round(45 * Constants.scaleFactor)
                visible: layout.searchText.length === 0
                spacing: 0

                Key {
                    width: Math.round(60 * Constants.scaleFactor)
                    height: parent.height
                    text: "ABC"
                    isSpecial: true
                    onClicked: layout.layoutSwitchClicked("qwerty")
                }

                Flickable {
                    id: categoryFlickable

                    width: parent.width - (2 * Math.round(60 * Constants.scaleFactor))
                    height: parent.height
                    contentWidth: tabBar.width
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    MTabBar {
                        id: tabBar

                        height: parent.height
                        width: Math.max(categoryFlickable.width, categoryList.length * 60 * Constants.scaleFactor)
                        color: "transparent"
                        border.width: 0
                        tabs: {
                            var t = [];
                            for (var i = 0; i < categoryList.length; i++) {
                                t.push({
                                    "icon": categoryList[i].icon,
                                    "label": ""
                                });
                            }
                            return t;
                        }
                        activeTab: getCategoryIndex(layout.currentCategoryId)
                        onTabSelected: index => {
                            layout.currentCategoryId = categoryList[index].id;
                        }
                    }
                }

                Key {
                    width: Math.round(60 * Constants.scaleFactor)
                    height: parent.height
                    iconName: "delete"
                    isSpecial: true
                    onClicked: layout.backspaceClicked()
                }
            }

            QwertyLayout {
                id: searchKeyboard

                width: parent.width
                visible: layout.searchText.length > 0
                onKeyClicked: text => {
                    layout.searchText += text;
                }
                onBackspaceClicked: {
                    if (layout.searchText.length > 0)
                        layout.searchText = layout.searchText.slice(0, -1);
                }
                onSpaceClicked: {
                    layout.searchText += " ";
                }
                onEnterClicked: {
                    Qt.inputMethod.visible = false;
                }
                onDismissClicked: {
                    layout.searchText = "";
                    Qt.inputMethod.visible = false;
                }
            }
        }
    }
}
