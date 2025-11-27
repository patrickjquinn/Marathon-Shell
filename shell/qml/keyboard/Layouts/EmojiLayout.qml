// Marathon Virtual Keyboard - Emoji Layout
import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Navigation
import MarathonUI.Core
import "../UI"

Item {
    id: layout
    
    // Properties
    property bool shifted: false
    property bool capsLock: false
    property string searchText: ""
    
    // Expose Column's implicit height
    implicitHeight: layoutColumn.implicitHeight
    
    // Signals
    signal keyClicked(string text)
    signal backspaceClicked()
    signal enterClicked()
    signal spaceClicked()
    signal layoutSwitchClicked(string layout)
    signal dismissClicked()
    
    // Emoji Data
    readonly property var recentEmojis: ["😂", "❤️", "👍", "🔥", "😊", "🤔", "😭", "🥰", "😎", "✨"]
    
    readonly property var smileys: [
        "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "☺️",
        "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗",
        "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓",
        "😎", "🥸", "🤩", "🥳", "😏", "😒", "😞", "😔", "😟", "😕"
    ]
    
    readonly property var animals: [
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨",
        "🐯", "🦁", "cow", "🐷", "🐽", "🐸", "🐵", "🙈", "🙉", "🙊",
        "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "duck", "🦅", "🦉"
    ]

    // Category Data
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
    
    // Additional Categories
    readonly property var food: ["🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶", "🫑", "🌽", "🥕", "🫒", "🧄", "🧅", "🥔", "🍠", "🥐", "🥯", "🍞", "🥖", "🥨", "🧀", "🥚", "🍳", "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖", "🦴", "🌭", "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮", "🌯", "🫔", "🥗", "🥘", "🫕", "🥫", "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤", "🍙", "🍚", "🍘", "🍥", "🥠", "🥮", "🍢", "🍡", "🍧", "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍿", "🍩", "🍪", "🌰", "🥜", "🍯", "🥛", "🍼", "☕️", "🫖", "🍵", "🧃", "🥤", "🧋", "🍶", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸", "🍹", "🧉", "🍾", "🧊", "🥄", "🍴", "🍽", "🥣", "🥡", "🥢", "🧂"]
    readonly property var activities: ["⚽️", "🏀", "🏈", "⚾️", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑", "🥍", "🏏", "🪃", "🥅", "⛳️", "🪁", "🏹", "🎣", "🤿", "🥊", "🥋", "🎽", "🛹", "🛼", "🛷", "⛸", "🥌", "🎿", "⛷", "🏂", "🪂", "🏋️‍♀️", "🤼‍♀️", "🤸‍♀️", "⛹️‍♀️", "🤺", "🤾‍♀️", "🏌️‍♀️", "🏇", "🧘‍♀️", "🏄‍♀️", "🏊‍♀️", "🤽‍♀️", "🚣‍♀️", "🧗‍♀️", "🚵‍♀️", "🚴‍♀️", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖", "ros", "🎗", "🎫", "🎟", "🎪", "🤹", "🎭", "🩰", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🪘", "🎷", "🎺", "🪗", "🎸", "🪕", "🎻", "🎲", "♟", "🎯", "🎳", "🎮", "🎰", "🧩"]
    readonly property var travel: ["🚗", "🚕", "🚙", "🚌", "🚎", "🏎", "🚓", "🚑", "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🦯", "🦽", "🦼", "🛴", "🚲", "🛵", "🏍", "🛺", "🚨", "🚔", "🚍", "🚘", "🚖", "🚡", "🚠", "🚟", "🚃", "🚋", "🚞", "🚝", "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "🚊", "🚉", "✈️", "🛫", "🛬", "🛩", "💺", "🛰", "🚀", "🛸", "🚁", "🛶", "⛵️", "🚤", "🛥", "🛳", "⛴", "🚢", "⚓️", "🪝", "⛽️", "🚧", "🚦", "🚥", "🚏", "🗺", "🗿", "🗽", "🗼", "🏰", "🏯", "🏟", "🎡", "🎢", "🎠", "⛲️", "⛱", "🏖", "🏝", "🏜", "🌋", "⛰", "🏔", "🗻", "camping", "⛺️", "🏠", "🏡", "🏘", "🏚", "🏗", "🏭", "🏢", "🏬", "🏣", "🏤", "🏥", "🏦", "🏨", "🏪", "🏫", "🏩", "💒", "🏛", "⛪️", "🕌", "🕍", "🛕", "🕋", "⛩", "🛤", "🛣", "🗾", "🎑", "🏞", "🌅", "🌄", "🌠", "🎇", "🎆", "🌇", "🌆", "🏙", "🌃", "🌌", "🌉", "🌁"]
    readonly property var objects: ["⌚️", "📱", "📲", "💻", "⌨️", "🖥", "🖨", "🖱", "🖲", "🕹", "🗜", "💽", "💾", "💿", "📀", "📼", "📷", "📸", "📹", "🎥", "📽", "🎞", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙", "🎚", "🎛", "🧭", "⏱", "⏲", "⏰", "🕰", "⌛️", "⏳", "📡", "🔋", "🔌", "💡", "🔦", "🕯", "🪔", "🧯", "🛢", "💸", "💵", "💴", "💶", "💷", "🪙", "💰", "💳", "💎", "⚖️", "🪜", "🧰", "🪛", "🔧", "🔨", "⚒", "🛠", "⛏", "🪚", "🔩", "⚙️", "🪤", "🧱", "⛓", "🧲", "🔫", "💣", "🧨", "🪓", "🔪", "🗡", "⚔️", "🛡", "🚬", "⚰️", "🪦", "⚱️", "🏺", "🔮", "📿", "🧿", "💈", "⚗️", "🔭", "🔬", "🕳", "🩹", "🩺", "💊", "💉", "🩸", "🧬", "🦠", "🧫", "🧪", "🌡", "🧹", "🪠", "🧺", "🧻", "🚽", "🚰", "🚿", "🛁", "🛀", "🧼", "🪥", "🪒", "🧽", "🪣", "🧴", "🛎", "🔑", "🗝", "🚪", "🪑", "🛋", "🛏", "🛌", "🧸", "🪆", "🖼", "🪞", "🪟", "🛍", "🛒", "🎁", "🎈", "🎏", "🎀", "🪄", "🪅", "🎊", "🎉", "🎎", "🏮", "🎐", "🧧", "✉️", "📩", "📨", "📧", "💌", "📥", "📤", "📦", "🏷", "🪧", "📪", "📫", "📬", "📭", "📮", "📯", "📜", "📃", "📄", "📑", "🧾", "📊", "📈", "📉", "🗒", "🗓", "📆", "📅", "🗑", "📇", "🗃", "🗳", "🗄", "📋", "📁", "📂", "🗂", "🗞", "📰", "📓", "📔", "📒", "📕", "📗", "📘", "📙", "📚", "📖", "🔖", "🧷", "🔗", "📎", "🖇", "📐", "📏", "🧮", "📌", "📍", "✂️", "🖊", "🖋", "✒️", "🖌", "🖍", "📝", "✏️", "🔍", "🔎", "🔏", "🔐", "🔒", "🔓"]
    readonly property var symbols: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "✝️", "☪️", "🕉", "☸️", "✡️", "🔯", "🕎", "☯️", "☦️", "🛐", "⛎", "♈️", "♉️", "♊️", "♋️", "♌️", "♍️", "♎️", "♏️", "♐️", "♑️", "♒️", "♓️", "🆔", "⚛️", "🉑", "☢️", "☣️", "📴", "📳", "🈶", "🈚️", "🈸", "🈺", "🈷️", "✴️", "🆚", "💮", "🉐", "㊙️", "㊗️", "🈴", "🈵", "🈹", "🈲", "🅰️", "🅱️", "🆎", "🆑", "🅾️", "🆘", "❌", "⭕️", "🛑", "⛔️", "📛", "🚫", "💯", "💢", "♨️", "🚷", "🚯", "🚳", "🚱", "🔞", "📵", "🚭", "❗️", "❕", "❓", "❔", "‼️", "⁉️", "🔅", "🔆", "〽️", "⚠️", "🚸", "🔱", "⚜️", "🔰", "♻️", "✅", "🈯️", "💹", "❇️", "✳️", "❎", "🌐", "💠", "Ⓜ️", "🌀", "💤", "🏧", "🚾", "♿️", "🅿️", "🛗", "🈳", "🈂️", "🛂", "🛃", "🛄", "🛅", "🚹", "🚺", "🚼", "⚧", "🚻", "🚮", "🎦", "📶", "🈁", "🔣", "ℹ️", "🔤", "🔡", "🔠", "🆖", "🆗", "🆙", "🆒", "🆕", "🆓", "0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟", "🔢", "#️⃣", "*️⃣", "⏏️", "▶️", "⏸", "⏯", "⏹", "⏺", "⏭", "⏮", "⏩", "⏪", "⏫", "⏬", "◀️", "🔼", "🔽", "➡️", "⬅️", "⬆️", "⬇️", "↗️", "↘️", "↙️", "↖️", "↕️", "↔️", "↪️", "↩️", "⤴️", "⤵️", "🔀", "🔁", "🔂", "🔄", "🔃", "🎵", "🎶", "➕", "➖", "➗", "✖️", "♾", "💲", "💱", "™️", "©️", "®️", "👁‍🗨", "🔚", "🔙", "🔛", "🔝", "🔜", "〰️", "➰", "➿", "✔️", "☑️", "🔘", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫️", "⚪️", "🟤", "🔺", "🔻", "🔸", "🔹", "🔶", "🔷", "🔳", "🔲", "▪️", "▫️", "◾️", "◽️", "◼️", "◻️", "🟥", "🟧", "🟨", "🟩", "🟦", "🟪", "⬛️", "⬜️", "🟫", "🔈", "🔇", "🔉", "🔊", "🔔", "🔕", "📣", "📢", "💬", "💭", "🗯", "♠️", "♣️", "♥️", "♦️", "🃏", "🎴", "🀄️", "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛", "🕜", "🕝", "🕞", "🕟", "🕠", "🕡", "🕢", "🕣", "🕤", "🕥", "🕦", "🕧"]
    readonly property var flags: ["🏳️", "🏴", "🏁", "🚩", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️", "🇦🇫", "🇦🇽", "🇦🇱", "🇩🇿", "🇦🇸", "🇦🇩", "🇦🇴", "🇦🇮", "🇦🇶", "🇦🇬", "🇦🇷", "🇦🇲", "🇦🇼", "🇦🇺", "🇦🇹", "🇦🇿", "🇧🇸", "🇧🇭", "🇧🇩", "🇧🇧", "🇧🇾", "🇧🇪", "🇧🇿", "🇧🇯", "🇧🇲", "🇧🇹", "🇧🇴", "🇧🇦", "🇧🇼", "🇧🇷", "🇮🇴", "🇻🇬", "🇧🇳", "🇧🇬", "🇧🇫", "🇧🇮", "🇰🇭", "🇨🇲", "🇨🇦", "🇮🇨", "🇨🇻", "🇧🇶", "🇰🇾", "🇨🇫", "🇹🇩", "🇨🇱", "🇨🇳", "🇨🇽", "🇨🇨", "🇨🇴", "🇰🇲", "🇨🇬", "🇨🇩", "🇨🇰", "🇨🇷", "🇨🇮", "🇭🇷", "🇨🇺", "🇨🇼", "🇨🇾", "🇨🇿", "🇩🇰", "🇩🇯", "🇩🇲", "🇩🇴", "🇪🇨", "🇪🇬", "🇸🇻", "🇬🇶", "🇪🇷", "🇪🇪", "🇪🇹", "🇪🇺", "🇫🇰", "🇫🇴", "🇫🇯", "🇫🇮", "🇫🇷", "🇬🇫", "🇵🇫", "🇹🇫", "🇬🇦", "🇬🇲", "🇬🇪", "🇩🇪", "🇬🇭", "🇬🇮", "🇬🇷", "🇬🇱", "🇬🇩", "🇬🇵", "🇬🇺", "🇬🇹", "🇬🇬", "🇬🇳", "🇬🇼", "🇬🇾", "🇭🇹", "🇭🇳", "🇭🇰", "🇭🇺", "🇮🇸", "🇮🇳", "🇮🇩", "🇮🇷", "🇮🇶", "🇮🇪", "🇮🇲", "🇮🇱", "🇮🇹", "🇯🇲", "🇯🇵", "🎌", "🇯🇪", "🇯🇴", "🇰🇿", "🇰🇪", "🇰🇮", "🇽🇰", "🇰🇼", "🇰🇬", "🇱🇦", "🇱🇻", "🇱🇧", "🇱🇸", "🇱🇷", "🇱🇾", "🇱🇮", "🇱🇹", "🇱🇺", "🇲🇴", "🇲🇰", "🇲🇬", "🇲🇼", "🇲🇾", "🇲🇻", "🇲🇱", "🇲🇹", "🇲🇭", "🇲🇶", "🇲🇷", "🇲🇺", "🇾🇹", "🇲🇽", "🇫🇲", "🇲🇩", "🇲🇨", "🇲🇳", "🇲🇪", "🇲🇸", "🇲🇦", "🇲🇿", "🇲🇲", "🇳🇦", "🇳🇷", "🇳🇵", "🇳🇱", "🇳🇨", "🇳🇿", "🇳🇮", "🇳🇪", "🇳🇬", "🇳🇺", "🇳🇫", "🇰🇵", "🇲🇵", "🇳🇴", "🇴🇲", "🇵🇰", "🇵🇼", "🇵🇸", "🇵🇦", "🇵🇬", "🇵🇾", "🇵🇪", "🇵🇭", "🇵🇳", "🇵🇱", "🇵🇹", "🇵🇷", "🇶🇦", "🇷🇪", "🇷🇴", "🇷🇺", "🇷🇼", "🇼🇸", "🇸🇲", "🇸🇦", "🇸🇳", "🇷🇸", "🇸🇨", "🇸🇱", "🇸🇬", "🇸🇽", "🇸🇰", "🇸🇮", "🇬🇸", "🇸🇧", "🇸🇴", "🇿🇦", "🇰🇷", "🇸🇸", "🇪🇸", "🇱🇰", "🇧🇱", "🇸🇭", "🇰🇳", "🇱🇨", "🇵🇲", "🇻🇨", "🇸🇩", "🇸🇷", "🇸🇿", "🇸🇪", "🇨🇭", "🇸🇾", "🇹🇼", "🇹🇯", "🇹🇿", "🇹🇭", "🇹🇱", "🇹🇬", "🇹🇰", "🇹🇴", "🇹🇹", "🇹🇳", "🇹🇷", "🇹🇲", "🇹🇨", "🇹🇻", "🇺🇬", "🇺🇦", "🇦🇪", "🇬🇧", "🇺🇸", "🇺🇾", "🇺🇿", "🇻🇺", "🇻🇦", "🇻🇪", "🇻🇳", "🇼🇫", "🇪🇭", "🇾🇪", "🇿🇲", "🇿🇼"]
    
    // Category State
    property string currentCategoryId: "smileys"
    
    // Dynamic Model
    property var displayedEmojis: {
        if (searchText.length > 0) {
            // Filter all categories
            var all = []
            for (var key in categoryMap) {
                all = all.concat(categoryMap[key])
            }
            // Simple deduplication
            var unique = all.filter((item, pos) => all.indexOf(item) === pos)
            // TODO: Map emojis to keywords for proper search
            return unique
        }
        
        if (currentCategoryId === "recent") {
            // Bind to parent keyboard's recents if available
            var parentRecents = findParentKeyboard(layout)
            if (parentRecents) {
                return parentRecents.recentEmojis
            }
            return recentEmojis // Fallback
        }
        
        return categoryMap[currentCategoryId] || smileys
    }
    
    // Category List
    readonly property var categoryList: [
        { icon: "clock", id: "recent" },
        { icon: "star", id: "smileys" },
        { icon: "tree-pine", id: "animals" },
        { icon: "coffee", id: "food" },
        { icon: "zap", id: "activities" },
        { icon: "plane", id: "travel" },
        { icon: "sun", id: "objects" },
        { icon: "hash", id: "symbols" },
        { icon: "globe", id: "flags" }
    ]

    function getCategoryIndex(id) {
        for(var i=0; i<categoryList.length; i++) {
            if(categoryList[i].id === id) return i
        }
        return 0
    }
    
    function findParentKeyboard(item) {
        var p = item.parent
        while (p) {
            if (p.hasOwnProperty("recentEmojis")) return p
            p = p.parent
        }
        return null
    }

    Column {
        id: layoutColumn
        width: parent.width
        spacing: 0
        
        // Search Bar
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
                    
                    // Prevent physical keyboard from interfering if possible, 
                    // but we want onTextChanged to update layout.searchText
                    onTextChanged: layout.searchText = text
                    
                    // When focused, ensure we are in search mode
                    onActiveFocusChanged: {
                        if (activeFocus && layout.searchText === "") {
                            // Just focused
                        }
                    }
                    
                    Text {
                        text: "Search emojis..."
                        color: "#888888"
                        visible: parent.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                
                // Clear button
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
                            layout.searchText = ""
                            searchInput.forceActiveFocus()
                        }
                    }
                }
            }
        }
        
        // Emoji Grid
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
                        layout.keyClicked(modelData)
                        HapticService.light()
                        
                        // If in search mode, maybe clear search? 
                        // iOS keeps search open. We'll keep it open.
                        if (layout.searchText.length > 0) {
                            // Optional: Add to recents logic here if we had access to it
                        }
                    }
                }
            }
        }
        
        // Bottom Container (Categories OR Keyboard)
        Item {
            id: bottomContainer
            width: parent.width
            height: layout.searchText.length > 0 ? searchKeyboard.height : categoryRow.height
            
            // Categories & Navigation (Visible when NOT searching)
            Row {
                id: categoryRow
                width: parent.width
                height: Math.round(45 * Constants.scaleFactor)
                visible: layout.searchText.length === 0
                spacing: 0
                
                // ABC Button
                Key {
                    width: Math.round(60 * Constants.scaleFactor)
                    height: parent.height
                    text: "ABC"
                    isSpecial: true
                    onClicked: layout.layoutSwitchClicked("qwerty")
                }

                // Categories
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
                        // Fix binding loop by using flickable's width
                        width: Math.max(categoryFlickable.width, categoryList.length * 60 * Constants.scaleFactor)
                        
                        color: "transparent"
                        border.width: 0
                        
                        tabs: {
                            var t = []
                            for(var i=0; i<categoryList.length; i++) {
                                t.push({ icon: categoryList[i].icon, label: "" })
                            }
                            return t
                        }
                        
                        activeTab: getCategoryIndex(layout.currentCategoryId)
                        
                        onTabSelected: (index) => {
                            layout.currentCategoryId = categoryList[index].id
                        }
                    }
                }
                
                // Backspace Button
                Key {
                    width: Math.round(60 * Constants.scaleFactor)
                    height: parent.height
                    iconName: "delete"
                    isSpecial: true
                    onClicked: layout.backspaceClicked()
                }
            }
            
            // Search Keyboard (Visible when searching)
            QwertyLayout {
                id: searchKeyboard
                width: parent.width
                visible: layout.searchText.length > 0
                
                // We need to capture input and direct it to the search field
                onKeyClicked: (text) => {
                    layout.searchText += text
                }
                
                onBackspaceClicked: {
                    if (layout.searchText.length > 0) {
                        layout.searchText = layout.searchText.slice(0, -1)
                    }
                }
                
                onSpaceClicked: {
                    layout.searchText += " "
                }
                
                // Hide search on Enter or Dismiss
                onEnterClicked: {
                    Qt.inputMethod.hide() // Or just clear search?
                }
                
                onDismissClicked: {
                    layout.searchText = ""
                    Qt.inputMethod.hide()
                }
            }
        }
    }
}
