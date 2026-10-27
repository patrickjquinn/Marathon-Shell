pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// Hello: Marathon greets in each shipped language. Swipe up, a tap on the
// bar or Enter begins; the coordinator reads the bar and counts the swipes
// released short.
Item {
    id: root

    readonly property var greetingFor: ({
            "en": "Hello",
            "de": "Hallo",
            "fr": "Bonjour",
            "es": "Hola",
            "ga": "Dia dhuit"
        })
    readonly property var greetings: SettingsManagerCpp.availableLanguages.map(l => greetingFor[l.code]).filter(g => g !== undefined)
    property int shown: 0
    property int failedTries: 0
    // The setting if it names a shipped language, else the system's, else English.
    readonly property var language: {
        const all = SettingsManagerCpp.availableLanguages;
        const find = code => all.find(l => l.code === code);
        return find(SettingsManagerCpp.language) || find(Qt.locale().name.split("_")[0]) || find("en");
    }

    signal done

    function enter() {
        if (!accessibility.open && !languages.open)
            done();
    }

    function handleBack(): bool {
        if (!accessibility.open && !languages.open)
            return false;
        accessibility.open = false;
        languages.open = false;
        return true;
    }

    Keys.onReturnPressed: root.enter()
    Keys.onEnterPressed: root.enter()
    onVisibleChanged: {
        accessibility.open = false;
        languages.open = false;
        shown = 0;
        failedTries = 0;
        if (visible)
            forceActiveFocus();
    }
    Component.onCompleted: {
        if (visible)
            forceActiveFocus();
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.visible && root.greetings.length > 1
        onTriggered: root.shown = (root.shown + 1) % root.greetings.length
    }

    // On a short screen at a large size the greeting shrinks to clear the buttons.
    Column {
        id: greeting

        readonly property real fit: Math.min(1, (buttons.y - Silica.Theme.paddingMedium) / Math.max(1, height))

        objectName: "helloGreeting"
        width: parent.width
        y: Math.max(0, (buttons.y - height * fit) / 2)
        scale: fit
        transformOrigin: Item.Top
        spacing: Silica.Theme.paddingMedium

        MMarathonMark {
            anchors.horizontalCenter: parent.horizontalCenter
            size: Silica.Theme.itemSizeHuge * 1.5
            showLabel: false
            glow: false
        }

        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "MARATHON" // i18n: literal
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
            font.letterSpacing: Silica.Theme.paddingSmall
        }

        Item {
            width: parent.width
            height: Silica.Theme.fontSizeHuge * 2.5

            Repeater {
                model: root.greetings

                Silica.Label {
                    required property string modelData
                    required property int index
                    // The outgoing greeting is gone by the halfway point, before the next appears.
                    property real shownness: index === root.shown ? 1 : 0

                    anchors.centerIn: parent
                    text: modelData
                    color: Silica.Theme.primaryColor
                    font.pixelSize: Silica.Theme.fontSizeHuge * 1.75
                    font.family: Silica.Theme.fontFamilyHeading
                    font.weight: Font.Light
                    opacity: Math.max(0, 2 * shownness - 1)

                    Behavior on shownness {
                        NumberAnimation {
                            duration: 800
                        }
                    }
                }
            }
        }
    }

    Silica.InteractionHintLabel {
        id: hint

        visible: !beginButton.visible
        anchors.bottom: parent.bottom
        topMargin: Silica.Theme.paddingLarge
        bottomMargin: Silica.Theme.paddingLarge
        //: First setup screen: how to start
        text: qsTr("Swipe up on the bar to begin")
    }

    Row {
        id: buttons

        objectName: "helloButtons"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: hint.top
        anchors.bottomMargin: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium

        Silica.Button {
            objectName: "helloAccessibility"
            //: Button that opens reduce motion and text size
            text: qsTr("Accessibility")
            onClicked: accessibility.open = true
        }

        Silica.Button {
            objectName: "helloLanguage"
            text: root.language.nativeName
            //: Button that opens the language list; %1 is the current language
            Accessible.name: qsTr("Language: %1").arg(text)
            onClicked: languages.open = true
        }
    }

    // Beginning is not optional: after the demo, a button in place of Not now.
    PracticeCoach {
        id: coach

        anchors.fill: parent
        running: root.visible && !accessibility.open && !languages.open
        failedTries: root.failedTries
        offersNotNow: false
        interactionMode: Silica.TouchInteraction.Swipe
        direction: Silica.TouchInteraction.Up
        hint.startY: coach.height - coach.hint.height / 2
    }

    Silica.Button {
        id: beginButton

        objectName: "helloBegin"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingLarge
        visible: coach.showNotNow
        //: Starts setup; shown after the swipe-up demo on the first setup screen
        text: qsTr("Begin")
        onClicked: root.done()
    }

    OobeAccessibilitySheet {
        id: accessibility

        objectName: "accessibilitySheet"
        anchors.fill: parent
    }

    OobeLanguageSheet {
        id: languages

        objectName: "languageSheet"
        anchors.fill: parent
        current: root.language.code
    }
}
