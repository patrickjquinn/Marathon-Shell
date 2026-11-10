// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Gaps found by the 2026-10-01 corpus load measurement
// (docs/compatibility/keel-gaps.md), one test per fix.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Share 1.0

Item {
    id: root
    width: 540
    height: 960

    readonly property string absoluteIcon: Qt.resolvedUrl("data/icon.xpm").toString().replace("file://", "")
    property bool useIcon: true

    // App-relative and bare absolute paths reach aliased Images in Keel's
    // controls resolved against this file, not against qrc:/Sailfish/Silica.
    CoverPlaceholder { id: placeholderRel; icon.source: "data/icon.xpm"; text: "rel" }
    CoverPlaceholder { id: placeholderAbs; icon.source: root.absoluteIcon; text: "abs" }
    CoverPlaceholder { id: placeholderBound; icon.source: root.useIcon ? "data/icon.xpm" : ""; text: "bound" }
    Button { id: iconButtonRel; icon.source: "data/icon.xpm"; text: "b" }
    IconButton { id: iconOnly; icon.source: "data/icon.xpm" }

    ListItem {
        id: noMenuOnHold
        showMenuOnPressAndHold: false
        menu: Component { ContextMenu { MenuItem { text: "x" } } }
    }
    ListItem {
        id: menuOnHold
        menu: Component { ContextMenu { MenuItem { text: "x" } } }
    }

    ShareAction {
        id: share
        title: "Share link"
        mimeType: "text/x-url"
        resources: [{ "type": "text/x-url", "linkTitle": "Keel", "status": "https://example.org/keel" }]
        property string sharedText
        on_Shared: function(text) { sharedText = text }
    }

    ShareAction {
        id: shareFile
        mimeType: "image/png"
        resources: [{ "type": "image/png", "filePath": "/home/user/Pictures/a.png" }, "file:///tmp/b.png"]
        property string sharedText: "unset"
        on_Shared: function(text) { sharedText = text }
    }

    InfoLabel { id: info; text: "Nothing here" }

    SlideshowView {
        id: slideshow
        width: 300; height: 200
        itemWidth: 300
        model: 4
        delegate: Rectangle { width: 300; height: 200; color: "red" }
    }

    TextField { id: field; textTopMargin: 40; focusOutBehavior: FocusBehavior.KeepFocus }
    TextField { id: assigned; acceptableInput: text.length > 2 }
    TextArea { id: area; textTopMargin: 30 }
    OpacityRampEffect { id: ramp; direction: OpacityRamp.TopToBottom }
    ContextMenu { id: emptyMenu; hasContent: false; MenuItem { text: "x" } }
    Page { id: page; propagateComposedEvents: true }
    ProgressCircle { id: circle; value: 0.5 }
    DockedPanel { id: panel; width: root.width; height: 100; dock: Dock.Bottom }
    DockedPanel {
        id: modalPanel; width: root.width; height: 100; dock: Dock.Top; modal: true
        animationDuration: 250; background: null
    }
    Drawer {
        id: drawer; width: 300; height: 300; dock: Dock.Left
        background: Item { }
        Item { }
    }
    TimePicker { id: picker; hour: 13; minute: 5; hourMode: DateTime.TwentyFourHours }

    TestCase {
        name: "CorpusGaps"
        when: windowShown

        function test_coverPlaceholderIconPaths() {
            tryCompare(placeholderRel.icon, "status", Image.Ready)
            compare(placeholderRel.icon.source.toString(), Qt.resolvedUrl("data/icon.xpm").toString())
            tryCompare(placeholderAbs.icon, "status", Image.Ready)
            compare(placeholderAbs.icon.source.toString(), "file://" + root.absoluteIcon)
            tryCompare(placeholderBound.icon, "status", Image.Ready)
            // The app's binding survives the rewrite.
            root.useIcon = false
            compare(placeholderBound.icon.source.toString(), "")
            root.useIcon = true
            tryCompare(placeholderBound.icon, "status", Image.Ready)
        }

        function test_controlIconPaths() {
            tryCompare(iconButtonRel.icon, "status", Image.Ready)
            tryCompare(iconOnly.icon, "status", Image.Ready)
        }

        function test_listItemShowMenuOnPressAndHold() {
            verify(menuOnHold.showMenuOnPressAndHold)
            compare(noMenuOnHold.showMenuOnPressAndHold, false)
            noMenuOnHold.pressAndHold(null)
            verify(!noMenuOnHold.menuOpen)
            compare(noMenuOnHold._menuItem, null)
            // Keel 0.1's name still works.
            compare(noMenuOnHold.openMenuOnPressAndHold, false)
        }

        function test_shareAction() {
            share.trigger()
            compare(share.sharedText, "https://example.org/keel")
            compare(Clipboard.text, "https://example.org/keel")
        }

        function test_shareActionNeverCopiesFilePaths() {
            Clipboard.text = "before"
            shareFile.trigger()
            compare(shareFile.sharedText, "")
            compare(Clipboard.text, "before")
        }

        function test_infoLabel() {
            compare(info.horizontalAlignment, Text.AlignHCenter)
            compare(info.wrapMode, Text.Wrap)
            compare(info.font.pixelSize, Theme.fontSizeExtraLarge)
            compare(info.x, Theme.horizontalPageMargin)
        }

        function test_slideshowView() {
            compare(slideshow.count, 4)
            compare(slideshow.snapMode, PathView.SnapOneItem)
            verify(slideshow.pathItemCount >= 2)
            verify(slideshow.interactive)
            slideshow.incrementCurrentIndex()
            tryCompare(slideshow, "currentIndex", 1)
        }

        function test_textMarginsAndWritableProperties() {
            // The text starts textTopMargin (+ padding) below the field's top.
            compare(field._editor.mapToItem(field, 0, 0).y, 40 + field.textTopPadding)
            compare(field.focusOutBehavior, FocusBehavior.KeepFocus)
            compare(area.textTopMargin, 30)
            verify(!assigned.acceptableInput)
            assigned.text = "abcd"
            verify(assigned.acceptableInput)
            compare(ramp.direction, OpacityRamp.TopToBottom)
            verify(!emptyMenu.hasContent)
            verify(page.propagateComposedEvents)
        }

        function test_progressCircleDockedPanelDrawerTimePicker() {
            compare(circle.progressValue, 0.5)
            verify(!circle.inAlternateCycle)
            circle.value = 0.1
            verify(circle.inAlternateCycle)
            verify(!panel.open)
            panel.show(true)
            verify(panel.open)
            verify(panel.expanded)
            panel.hide(true)
            verify(!panel.open)
            compare(modalPanel.animationDuration, 250)
            compare(modalPanel.background, null)
            verify(panel.background !== null)
            modalPanel.show(true)
            verify(modalPanel.open)
            // A modal panel closes on a tap outside it.
            mouseClick(root, root.width / 2, root.height - 10)
            verify(!modalPanel.open)
            drawer.show(true)
            verify(drawer.opened)
            tryCompare(drawer.foregroundItem.anchors, "leftMargin", drawer.backgroundSize)
            compare(picker.timeText, "13:05")
        }

        function test_format() {
            compare(Format.formatFileSize(512), "512 B")
            compare(Format.formatFileSize(1536), "1.5 kB")
            compare(Format.formatFileSize(5 * 1024 * 1024), "5.0 MB")
            compare(Format.formatFileSize(300 * 1024 * 1024), "300 MB")
            compare(Format.formatDuration(75, Formatter.DurationShort), "1:15")
            compare(Format.formatDuration(3725, Formatter.DurationShort), "1:02:05")
            compare(Format.formatDuration(3725, Formatter.DurationLong), "1 hour 2 minutes 5 seconds")
            var now = new Date(2026, 9, 1, 12, 0, 0)
            Format._setReferenceTime(now)
            compare(Format.formatDate(new Date(2026, 9, 1, 11, 59, 40), Formatter.DurationElapsed), "Just now")
            compare(Format.formatDate(new Date(2026, 9, 1, 11, 55, 0), Formatter.DurationElapsed), "5 minutes ago")
            compare(Format.formatDate(new Date(2026, 9, 1, 9, 0, 0), Formatter.DurationElapsed), "3 hours ago")
            compare(Format.formatDate(new Date(2026, 8, 29, 12, 0, 0), Formatter.DurationElapsed), "2 days ago")
            compare(Format.formatDate(new Date(2026, 8, 30, 8, 0, 0), Formatter.TimepointSectionRelative), "Yesterday")
            compare(Format.formatDate(new Date(2026, 9, 1, 8, 5, 0), Formatter.TimeValueTwentyFourHours), "08:05")
            compare(Format.formatDate("2026-10-01T11:00:00", Formatter.DurationElapsed), "1 hour ago")
            compare(Format.formatDate("not a date", Formatter.Timepoint), "")
            // The names Silica's date pickers use (through the Format singleton).
            var jan = new Date(2026, 0, 15, 12, 0, 0)
            compare(Format.formatDate(jan, Format.DateLong), jan.toLocaleDateString(Qt.locale(), Locale.LongFormat))
            compare(Format.formatDate(jan, Format.MonthNameStandalone), Qt.locale().standaloneMonthName(0, Locale.LongFormat))
            compare(Format.formatDate(jan, Format.MonthNameStandaloneShort), Qt.locale().standaloneMonthName(0, Locale.ShortFormat))
            Format._setReferenceTime(new Date(NaN))
            compare(Format.formatText("Ääkkönen ja ß?", Formatter.PortableFilename), "Aakkonen_ja__")
            compare(Format.formatText("Crème", Formatter.Ascii7Bit), "Creme")
            verify(Format.formatArticle(Formatter.PostMeridiemIndicator).length > 0)
            compare(Formatter.DurationElapsed, 5)
        }
    

        // harbour-mashka: positionViewAtBeginning() from the header's own
        // onHeightChanged while Qt creates the header. Without Keel's deferral
        // Qt 6 completes the header component re-entrantly and the process
        // crashes when the view is destroyed.
        function test_positionViewFromHeader_data() {
            return [ { tag: "SilicaListView" }, { tag: "SilicaGridView" } ]
        }
        function test_positionViewFromHeader(data) {
            var cells = data.tag === "SilicaGridView" ? " cellWidth: 200; cellHeight: 50;" : ""
            var view = Qt.createQmlObject("import QtQuick 2.0; import Sailfish.Silica 1.0; "
                + data.tag + " { id: v; width: 200; height: 300; model: 30;" + cells
                + " property int calls: 0;"
                + " header: Item { width: 200; height: 50 + r.height;"
                + "   onHeightChanged: { v.calls++; v.positionViewAtBeginning() }"
                + "   Rectangle { id: r; width: 10; height: 20; Component.onCompleted: height = 40 } }"
                + " delegate: Item { width: 200; height: 50 } }", root)
            verify(view)
            tryVerify(function() { return view.headerItem !== null && view.calls > 0 })
            compare(view.headerItem.height, 90)
            view.positionViewAtIndex(20, ListView.Beginning)
            verify(view.contentY > 0)   // no header pending: immediate
            view.positionViewAtBeginning()
            compare(view.contentY, view.originY)
            view.destroy()
            wait(50)
        }
    }
}
