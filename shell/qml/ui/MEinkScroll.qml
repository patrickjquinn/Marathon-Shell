import QtQuick
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell

// E-paper's scrolling: a list never follows the finger, since every frame
// of a scroll is a panel update. A swipe moves it a page, the view less a
// row, in one jump. Declared in the Flickable; set its interactive to
// !MMotion.instant.
MEinkSwipe {
    id: root

    required property Flickable flickable
    // Stays in view across the jump.
    property real overlap: Silica.Theme.itemSizeSmall
    readonly property bool scrollable: flickable.contentHeight + flickable.topMargin + flickable.bottomMargin > flickable.height

    // A swipe on toward an end the list is already at.
    signal beyond(int step)

    extent: flickable.height
    horizontal: false
    enabled: MMotion.instant && scrollable
    onTurn: step => {
        const f = flickable;
        const top = f.originY - f.topMargin;
        const bottom = Math.max(top, f.originY + f.contentHeight + f.bottomMargin - f.height);
        const y = Math.max(top, Math.min(bottom, f.contentY + step * (f.height - overlap)));
        if (y === f.contentY)
            beyond(step);
        else
            f.contentY = y;
    }
}
