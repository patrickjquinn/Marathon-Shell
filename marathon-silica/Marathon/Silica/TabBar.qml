import QtQuick
import Sailfish.Silica as S
import Sailfish.Silica.private as P

P.TabBar {
    id: root

    // Silica stops at Medium and scrolls; shrink further first if that makes the titles fit.
    function _titleFontSize(row) {
        if (!row || row.buttonFontSize !== S.Theme.fontSizeMedium)
            return row ? row.buttonFontSize : S.Theme.fontSizeLarge;
        let text = 0, padding = 0;
        for (let i = 0; i < row.children.length; ++i) {
            const button = row.children[i];
            if (button.title !== undefined) {
                text += mediumMetrics.advanceWidth(button.title);
                padding += 2 * S.Theme.paddingLarge;
            }
        }
        for (const size of [S.Theme.fontSizeMedium, S.Theme.fontSizeSmall, S.Theme.fontSizeExtraSmall]) {
            if (text * size / S.Theme.fontSizeMedium + padding <= root.width)
                return size;
        }
        return S.Theme.fontSizeMedium;
    }

    // Arrow keys move the selection; focus follows it.
    on_CurrentTabButtonChanged: {
        for (let p = root.Window.activeFocusItem; p; p = p.parent) {
            if (p === root) {
                if (root._currentTabButton)
                    root._currentTabButton.forceActiveFocus();
                return;
            }
        }
    }

    Accessible.role: Accessible.PageTabList
    Accessible.name: _currentTabButton ? _currentTabButton.title : ""

    // A tab's content scrolls up under the pinned bar, which is see-through
    // over a transparent app window.
    Rectangle {
        objectName: "tabBarBackdrop"
        anchors.fill: parent
        z: -1
        color: Qt.rgba(S.Theme.overlayBackgroundColor.r, S.Theme.overlayBackgroundColor.g, S.Theme.overlayBackgroundColor.b, 1)
        visible: root._tabView !== null && root._tabView.yOffset > 0
    }

    FontMetrics {
        id: mediumMetrics

        font.pixelSize: S.Theme.fontSizeMedium
    }

    delegate: TabButton {
        required property var model

        _tabView: root._tabView
        titleFontSize: root._titleFontSize(parent)
        title: model[root.titleRole] || ""
        icon.source: model[root.iconRole] || ""
        count: model[root.countRole] || 0
    }
}
