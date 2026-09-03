import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

Item {
    id: section

    property string title: ""
    property string subtitle: ""
    // DS section labels (.m-row groups in Settings, Display, etc.) use a
    // small-caps tracked eyebrow above the card — 11/700 uppercase with
    // 1.4 tracking, secondary colour, NO subtitle. The Title-3 + subtitle
    // variant reads as content, not as a navigational section heading —
    // settings sub-pages were rendering headers visually heavier than
    // their own row labels because the default was Title-3. Default is
    // now eyebrow; the Title-3 + subtitle variant is opt-out via
    // `eyebrow: false` (used by Calendar's EventListPage).
    property bool eyebrow: true
    default property alias content: contentColumn.children

    function updateDividers() {
        var dividerItems = [];
        for (var i = 0; i < contentColumn.children.length; i++) {
            var child = contentColumn.children[i];
            if (!child || child.visible === false)
                continue;
            if (child.hasOwnProperty("showDivider"))
                dividerItems.push(child);
        }

        for (var j = 0; j < dividerItems.length; j++) {
            dividerItems[j].showDivider = true;
        }
        if (dividerItems.length > 0)
            dividerItems[dividerItems.length - 1].showDivider = false;
    }

    width: parent ? parent.width : 400
    height: headerColumn.height + contentCard.height + (title !== "" ? MSpacing.md : 0)

    Column {
        id: headerColumn
        width: parent.width
        spacing: MSpacing.xs
        visible: section.title !== ""

        Text {
            // Two modes:
            //   eyebrow = true  → DS settings label: 11/700 + 1.4 tracking,
            //                     uppercase, --text-secondary. No subtitle.
            //   eyebrow = false → Legacy Title 3: 22/500 with -0.3 tracking.
            text: section.eyebrow ? section.title.toUpperCase() : section.title
            color: section.eyebrow ? MColors.textSecondary : MColors.textPrimary
            font.pixelSize: section.eyebrow ? MTypography.sizeEyebrow : MTypography.sizeTitle3
            font.weight: section.eyebrow ? MTypography.weightBold : MTypography.weightMedium
            font.letterSpacing: section.eyebrow ? MTypography.trackingEyebrow : MTypography.trackingTitle3
            font.family: MTypography.fontFamily
            width: parent.width
        }

        Text {
            // Subtitle suppressed in eyebrow mode — DS doesn't pair the
            // small-caps label with descriptive copy. Only Title-3 mode
            // surfaces this slot.
            visible: !section.eyebrow && section.subtitle !== ""
            text: section.subtitle
            color: MColors.textSecondary
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            wrapMode: Text.WordWrap
            width: parent.width
            opacity: 0.7
        }
    }

    Rectangle {
        id: contentCard
        anchors.top: headerColumn.bottom
        anchors.topMargin: section.title !== "" ? MSpacing.md : 0
        width: parent.width
        height: contentColumn.height
        color: MColors.bb10Card
        radius: MRadius.lg
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        MTopHairline {
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.03)
            lineWidth: 1
        }

        Column {
            id: contentColumn
            width: parent.width

            Component.onCompleted: section.updateDividers()
            onChildrenChanged: section.updateDividers()
        }
    }
}
