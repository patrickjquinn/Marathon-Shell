// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Tier A/B: the module imports and every implemented type instantiates.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

TestCase {
    id: testCase
    name: "Components"
    when: windowShown
    width: 540
    height: 960

    Item { id: holder; width: 540; height: 960 }

    function test_import() {
        verify(Theme !== undefined && Theme !== null)
        verify(Screen.width > 0)
        verify(Theme.horizontalPageMargin > 0)
        verify(Clipboard !== null)
        compare(PageStatus.Active, 2)
        compare(DialogResult.Accepted, 1)
        compare(DialogStatus.Opened, PageStatus.Active)
        compare(Orientation.All, Orientation.PortraitMask | Orientation.LandscapeMask)
        compare(PageStackAction.Immediate, 1)
        compare(PageNavigation.Forward, 2)
        compare(BusyIndicatorSize.Large, 3)
        compare(TruncationMode.Fade, 2)
        compare(CutoutMode.FullScreen, 0)
        compare(Cover.Active, 2)
    }

    function test_instantiate_data() {
        return ["ApplicationWindow", "Page", "PageStack", "Dialog", "DialogHeader", "PageHeader", "Label", "SilicaFlickable", "SilicaListView", "SilicaGridView", "PullDownMenu", "PushUpMenu", "MenuItem", "MenuLabel", "ContextMenu", "Cover", "CoverBackground", "CoverAction", "CoverActionList", "CoverPlaceholder", "TextField", "PasswordField", "SearchField", "TextArea", "TextSwitch", "Switch", "Slider", "ComboBox", "ValueButton", "Button", "IconButton", "SectionHeader", "DetailItem", "Separator", "RemorsePopup", "RemorseItem", "BusyIndicator", "PageBusyIndicator", "BusyLabel", "ProgressBar", "ViewPlaceholder", "ListItem", "BackgroundItem", "VerticalScrollDecorator", "HorizontalScrollDecorator", "FadeAnimation", "FadeAnimator", "AddAnimation", "RemoveAnimation", "TouchBlocker", "ScrollDecorator", "IconTextSwitch", "InteractionHintLabel", "TouchInteractionHint", "LinkedLabel", "ButtonLayout", "SilicaItem", "SilicaControl", "HighlightImage", "Icon", "OpacityRampEffect"].map(function(t) { return { tag: t, type: t } })
    }

    // Each type is created where an app uses it: pages, windows and covers
    // on their own, a DialogHeader in a Dialog, everything else in a
    // SilicaFlickable on a Page (menus, decorators and placeholders find
    // their flickable), the pages in an ApplicationWindow.
    function snippet(type) {
        var alone = ["ApplicationWindow", "Page", "PageStack", "Dialog", "Cover", "CoverBackground",
                     "CoverAction", "CoverActionList", "CoverPlaceholder", "FadeAnimation", "FadeAnimator",
                     "AddAnimation", "RemoveAnimation", "OpacityRampEffect"]
        if (alone.indexOf(type) >= 0)
            return type + " { }"
        var page
        if (type === "DialogHeader")
            page = "Dialog { DialogHeader { } }"
        else if (type === "MenuItem" || type === "MenuLabel")
            page = "Page { SilicaFlickable { anchors.fill: parent; PullDownMenu { " + type + " { } } } }"
        else
            page = "Page { SilicaFlickable { anchors.fill: parent; contentHeight: 2000; " + type + " { } } }"
        return "ApplicationWindow { width: 540; height: 960; initialPage: Component { " + page + " } }"
    }

    function test_instantiate(data) {
        var obj = Qt.createQmlObject("import QtQuick 2.6; import Sailfish.Silica 1.0; " + snippet(data.type),
                                     holder, "instantiate_" + data.type)
        verify(obj !== null, data.type)
        obj.destroy()
    }
}
