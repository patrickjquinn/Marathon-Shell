pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// One app in a list: icon, name, one line of summary, rating, and its
// install state. Tapping opens the detail page, where the install action
// lives; a running install can be cancelled from the press-and-hold menu.
ListItem {
    id: root

    required property var store
    required property var app
    property int rank: 0

    readonly property string appId: app.app_id || app.id || ""
    readonly property var rating: store.ratingFor(appId)
    readonly property var job: store.jobFor(appId)
    readonly property bool busy: job !== null && store.jobRunning(job)
    readonly property string stateText: {
        if (job !== null && job.state === "failed")
            return qsTr("Failed");
        if (store.hasUpdate(appId))
            return qsTr("Update");
        if (store.isInstalled(appId))
            return qsTr("Installed");
        return "";
    }
    readonly property color primary: highlighted ? Theme.highlightColor : Theme.primaryColor
    readonly property color secondary: highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor

    contentHeight: Theme.itemSizeExtraLarge
    Accessible.name: (app.name || appId) + (rating ? ", " + qsTr("rated %1 stars").arg(rating.average.toFixed(1)) : "")
    Component.onCompleted: {
        store.ensureRating(appId);
        store.ensureIcon(app);
    }
    onClicked: store.openDetail(app)
    menu: root.store.canCancel(root.job) ? cancelMenu : null

    Component {
        id: cancelMenu
        ContextMenu {
            MenuItem {
                objectName: "cancelItem"
                text: qsTr("Cancel")
                onClicked: root.store.cancelJob(root.appId)
            }
        }
    }

    Label {
        id: rankLabel
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        visible: root.rank > 0
        width: visible ? Theme.iconSizeSmall : 0
        horizontalAlignment: Text.AlignHCenter
        text: root.rank
        color: root.secondary
        font.pixelSize: Theme.fontSizeLarge
    }

    AppIcon {
        id: icon
        anchors.left: rankLabel.visible ? rankLabel.right : parent.left
        anchors.leftMargin: rankLabel.visible ? Theme.paddingMedium : Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSizeLarge
        height: width
        source: root.store.iconFor(root.app)
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: Theme.paddingLarge
        anchors.right: status.left
        anchors.rightMargin: Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter

        Label {
            width: parent.width
            text: root.app.name || root.appId
            color: root.primary
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            text: root.app.summary || root.app.developer_name || (root.app.version ? qsTr("Version %1").arg(root.app.version) : "")
            color: root.secondary
            font.pixelSize: Theme.fontSizeExtraSmall
            truncationMode: TruncationMode.Fade
        }
        Row {
            spacing: Theme.paddingSmall
            visible: root.rating !== null

            StarRating {
                anchors.verticalCenter: parent.verticalCenter
                value: root.rating ? root.rating.average : 0
                starSize: Theme.fontSizeExtraSmall * 0.8
                color: root.secondary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: root.rating ? root.store.formatCount(root.rating.total) : ""
                color: root.secondary
                font.pixelSize: Theme.fontSizeTiny
            }
        }
    }

    Item {
        id: status

        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: root.busy ? Theme.iconSizeMedium : stateLabel.implicitWidth
        height: Theme.iconSizeMedium

        Label {
            id: stateLabel
            objectName: "stateLabel"
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.busy
            text: root.stateText
            color: root.job !== null && root.job.state === "failed" ? Theme.errorColor : root.secondary
            font.pixelSize: Theme.fontSizeExtraSmall
        }
        ProgressCircle {
            anchors.fill: parent
            visible: root.busy && root.job.percent >= 0
            value: root.job && root.job.percent > 0 ? root.job.percent / 100 : 0
            Accessible.role: Accessible.ProgressBar
            Accessible.name: qsTr("Installing %1%").arg(root.job ? root.job.percent : 0)
        }
        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Small
            running: root.busy && !(root.job.percent >= 0)
            visible: running
        }
    }
}
