import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "AppGridLabels"
    when: windowShown

    Window {
        width: 360
        height: 1140
        visible: true

        MarathonAppGrid {
            id: grid

            anchors.fill: parent
            appModel: QtObject {
                readonly property var apps: [
                    {
                        "id": "mail",
                        "name": "Mail",
                        "icon": ""
                    },
                    {
                        "id": "clock",
                        "name": "Clock",
                        "icon": ""
                    }
                ]
                readonly property int count: apps.length
                function getAppAtIndex(i) {
                    return apps[i] || null;
                }
            }
        }
    }

    function cell(i) {
        return findChild(grid, "appIcon-" + i);
    }

    // Before any reading, and where the frame can't be read, the label
    // follows the ambience's scheme. Runs first: a reading replaces the
    // stub's binding.
    function test_aBackdropNotYetReadFollowsTheScheme() {
        const tone = findChild(cell(0), "labelTone");
        const schemeLight = Silica.Theme.colorScheme === Silica.Theme.DarkOnLight;
        compare(tone.fallbackLight, schemeLight);
        compare(findChild(cell(0), "appLabel").color, schemeLight ? Silica.Theme.darkPrimaryColor : Silica.Theme.lightPrimaryColor);
    }

    function test_aLightBackdropDarkensTheLabel() {
        const tone = findChild(cell(0), "labelTone");
        const label = findChild(cell(0), "appLabel");
        tone.light = true;
        tryCompare(label, "color", Silica.Theme.darkPrimaryColor);
        verify(label.styleColor.r > 0.9 && label.styleColor.a < 0.5, "a faint light halo");
        tone.light = false;
        tryCompare(label, "color", Silica.Theme.lightPrimaryColor);
        verify(label.styleColor.r < 0.1 && label.styleColor.a < 0.5, "a soft dark halo");
        compare(label.style, Text.Outline);
    }

    function test_eachLabelReadsItsOwnBackdrop() {
        findChild(cell(0), "labelTone").light = true;
        findChild(cell(1), "labelTone").light = false;
        tryCompare(findChild(cell(0), "appLabel"), "color", Silica.Theme.darkPrimaryColor);
        tryCompare(findChild(cell(1), "appLabel"), "color", Silica.Theme.lightPrimaryColor);
    }

    // The probe reads rows clear of the glyphs: in the gap under the icon,
    // and below the label.
    function test_theProbeFramesTheLabel() {
        const tone = findChild(cell(0), "labelTone");
        const label = findChild(cell(0), "appLabel");
        const top = label.mapToItem(cell(0), 0, 0).y;
        verify(tone.y < top && tone.y + tone.height > top + label.height);
        verify(tone.width > 0 && tone.width <= label.width);
    }
}
