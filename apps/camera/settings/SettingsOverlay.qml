// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica's Screen is qualified (S.Screen): which import an unqualified
// `Screen` names depends on the Qt version (the first up to Qt 6.8, the
// last from 6.10).
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as S
import QtQuick 2.6
import MarathonApp.Camera 1.0

PinchArea {
    id: overlay

    property bool isPortrait
    property real topButtonRowHeight
    property bool showCommonControls: true // any controls from here
    property bool deviceToggleEnabled
    property bool inButtonLayout

    property alias shutter: shutterContainer.children
    property alias anchorContainer: anchorContainer
    property alias container: container
    readonly property alias settingsOpacity: grid.opacity
    property bool orientationTransitionRunning

    property bool _pinchActive
    property bool topMenuOpen
    property bool _closing
    // top menu open or transitioning
    readonly property bool _exposed: topMenuOpen || _closing || verticalAnimation.running || dragArea.drag.active

    default property alias _data: container.data

    readonly property int _captureButtonLocation: overlay.isPortrait ? Settings.global.portraitCaptureButtonLocation : Settings.global.landscapeCaptureButtonLocation

    property real _progress: (panel.y + panel.height) / panel.height

    property real _menuItemHorizontalSpacing: S.Screen.sizeCategory >= S.Screen.Large ? Theme.paddingLarge * 2 : Theme.paddingLarge
    property real _headerHeight: S.Screen.sizeCategory >= S.Screen.Large ? Theme.itemSizeMedium : Theme.itemSizeSmall + Theme.paddingMedium
    property real _headerTopMargin: S.Screen.sizeCategory >= S.Screen.Large ? Theme.paddingLarge + Theme.paddingSmall : // first button reactive area overlapping slightly
    -((Theme.paddingMedium + Theme.paddingSmall) / 2)
    readonly property real _menuWidth: S.Screen.sizeCategory >= S.Screen.Large ? Theme.iconSizeLarge + Theme.paddingMedium * 2 // increase icon hitbox
    : Theme.iconSizeMedium + Theme.paddingMedium + Theme.paddingSmall

    property color _highlightColor: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

    property real _commonControlOpacity: showCommonControls ? 1.0 : 0.0
    Behavior on _commonControlOpacity {
        FadeAnimation {}
    }

    onShowCommonControlsChanged: {
        if (!showCommonControls) {
            closeMenus();
        }
    }

    on_CaptureButtonLocationChanged: inButtonLayout = false

    onIsPortraitChanged: {
        upperHeader.pressedMenu = null;
    }

    signal clicked(var mouse)

    function closeMenus() {
        _closing = true;
        whiteBalanceMenu.open = false;
        topMenuOpen = false;
        inButtonLayout = false;
        _closing = false;
    }

    onPinchStarted: _pinchActive = true
    onPinchFinished: _pinchActive = false

    property list<Item> _buttonAnchors
    _buttonAnchors: [
        ButtonAnchor {
            id: buttonAnchorTL
            index: 0
            anchors {
                left: parent.left
                top: parent.top
            }
            visible: !overlay.isPortrait
        },
        ButtonAnchor {
            id: buttonAnchorCL
            index: 1
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            visible: !overlay.isPortrait
        },
        ButtonAnchor {
            id: buttonAnchorBL
            index: 2
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
        },
        ButtonAnchor {
            id: buttonAnchorBC
            index: 3
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
            }
            visible: overlay.isPortrait
        },
        ButtonAnchor {
            id: buttonAnchorBR
            index: 4
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
        },
        ButtonAnchor {
            id: buttonAnchorCR
            index: 5
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            visible: !overlay.isPortrait
        },
        ButtonAnchor {
            id: buttonAnchorTR
            index: 6
            anchors {
                right: parent.right
                top: parent.top
            }
            visible: !overlay.isPortrait
        }
    ]

    // Position of other elements given the capture button position
    property var _portraitPositions: [

        // Unused
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorBR,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignBottom
        } // buttonAnchorTL
        ,
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorBR,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignBottom
        } // buttonAnchorCL

        ,

        // Used
        {
            "captureMode": overlayAnchorBR,
            "cameraPosition": overlayAnchorBC,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignBottom
        } // buttonAnchorBL
        ,
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorBR,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignBottom
        } // buttonAnchorBC
        ,
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorBC,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignBottom
        } // buttonAnchorBR

        ,

        // Unused
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorBR,
            "exposure": Qt.AlignLeft,
            "backCameraToggle": Qt.AlignBottom
        } // buttonAnchorCR
        ,
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorBR,
            "exposure": Qt.AlignLeft,
            "backCameraToggle": Qt.AlignBottom
        }, // buttonAnchorTR
    ]
    property var _landscapePositions: [
        // Used
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorCL,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignLeft
        } // buttonAnchorTL
        ,
        {
            "captureMode": overlayAnchorBL,
            "cameraPosition": overlayAnchorTL,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignLeft
        } // buttonAnchorCL
        ,
        {
            "captureMode": overlayAnchorCL,
            "cameraPosition": overlayAnchorTL,
            "exposure": Qt.AlignRight,
            "backCameraToggle": Qt.AlignLeft
        } // buttonAnchorBL

        ,

        // Unused
        {
            "captureMode": overlayAnchorBR,
            "cameraPosition": overlayAnchorTR,
            "exposure": Qt.AlignLeft,
            "backCameraToggle": Qt.AlignRight
        } // buttonAnchorBC

        ,

        // Used
        {
            "captureMode": overlayAnchorCR,
            "cameraPosition": overlayAnchorTR,
            "exposure": Qt.AlignLeft,
            "backCameraToggle": Qt.AlignRight
        } // buttonAnchorBR
        ,
        {
            "captureMode": overlayAnchorBR,
            "cameraPosition": overlayAnchorTR,
            "exposure": Qt.AlignLeft,
            "backCameraToggle": Qt.AlignRight
        } // buttonAnchorCR
        ,
        {
            "captureMode": overlayAnchorBR,
            "cameraPosition": overlayAnchorCR,
            "exposure": Qt.AlignLeft,
            "backCameraToggle": Qt.AlignRight
        }, // buttonAnchorTR
    ]

    property var _overlayPosition: overlay.isPortrait ? _portraitPositions[overlay._captureButtonLocation] : _landscapePositions[overlay._captureButtonLocation]

    Item {
        id: shutterContainer

        parent: overlay._buttonAnchors[overlay._captureButtonLocation]
        anchors.fill: parent
    }

    CameraDeviceToggle {
        onSelected: function (deviceId) {
            Settings.deviceId = deviceId;
            camera.digitalZoom = 1.0;
        }
        onZoomReset: zoomResetAnimation.restart()

        NumberAnimation {
            id: zoomResetAnimation
            target: camera
            property: "digitalZoom"
            to: 1.0
            duration: 200
            easing.type: Easing.OutCubic
        }

        parent: {
            switch (_overlayPosition.backCameraToggle) {
            case Qt.AlignBottom:
                return overlayAnchorBC;
            case Qt.AlignLeft:
                return overlayAnchorCL;
            default:
            case Qt.AlignRight:
                return overlayAnchorCR;
            }
        }

        opacity: _commonControlOpacity
        labels: Settings.backCameraLabels(camera.backFacingCameras)
        visible: opacity > 0.0 && !!model && model.length > 1 && labels.length > 0 && Settings.deviceId !== Settings.global.frontFacingDeviceId && !inButtonLayout
        orientation: overlay.isPortrait ? Qt.Horizontal : Qt.Vertical
        enabled: camera.cameraStatus === Camera.ActiveStatus
        model: camera.backFacingCameras
        currentDeviceId: camera.deviceId
        zoom: camera.digitalZoom

        x: {
            if (_overlayPosition.backCameraToggle === Qt.AlignLeft) {
                return parent.width + Theme.paddingLarge;
            } else if (_overlayPosition.backCameraToggle === Qt.AlignRight) {
                return -width - (isPortrait ? 1 : 2) * Theme.paddingLarge;
            }

            return parent.width / 2 - width / 2;
        }

        y: {
            if (_overlayPosition.backCameraToggle & Qt.AlignBottom) {
                return -height - (overlay.isPortrait ? 2 : 1) * Theme.paddingLarge;
            }

            return parent.height / 2 - height / 2;
        }
    }

    ToggleButton {
        objectName: "cameraSwitch"
        parent: _overlayPosition.cameraPosition
        anchors.centerIn: parent
        icon: "image://theme/icon-camera-switch"
        opacity: _commonControlOpacity
        visible: opacity > 0.0 && camera.hasCameraOnBothSides
        enabled: overlay.deviceToggleEnabled

        onClicked: {
            if (Settings.global.position === Camera.BackFace) {
                Settings.deviceId = Settings.global.frontFacingDeviceId;
            } else {
                Settings.deviceId = Settings.global.previousBackFacingDeviceId;
            }

            camera.digitalZoom = 1.0;
        }
    }

    // Soft shade behind the top row where the viewfinder reaches under it
    // (the 16:9 video frame), so it reads over a bright scene. Over the black
    // bar above the 4:3 photo frame it is not seen.
    Rectangle {
        width: overlay.width
        height: topRow._topRowMargin + overlay._menuWidth + 2 * Theme.paddingLarge
        visible: overlay.isPortrait && topRow.visible
        opacity: _commonControlOpacity
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.rgba(Theme.darkPrimaryColor, 0.45)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    CaptureModeMenu {
        id: captureModeMenu

        property real itemStep: Theme.itemSizeExtraSmall + spacing

        parent: _overlayPosition.captureMode
        anchors.verticalCenterOffset: height / 2
        alignment: (parent.anchors.left === container.left ? Qt.AlignRight : Qt.AlignLeft) | Qt.AlignBottom
        open: true
        opacity: _commonControlOpacity
        visible: opacity > 0.0 && CameraConfigs.supportedVideoResolutions.length > 0

        Rectangle {
            id: captureModeHighlight

            z: -1
            width: Theme.itemSizeExtraSmall
            height: Theme.itemSizeExtraSmall
            anchors.horizontalCenter: parent.horizontalCenter
            radius: width / 2
            color: Theme.rgba(_highlightColor, Theme.opacityLow)
            opacity: y < -captureModeMenu.itemStep ? 1.0 - (captureModeMenu.itemStep + y) / (-captureModeMenu.itemStep / 2) : (y > 0 ? 1.0 - y / (captureModeMenu.itemStep / 2) : 1.0)
            // Behind the selected mode, counted from the bottom item: with a
            // single item, `currentIndex == 0 ? -itemStep : 0` drew the circle
            // one step above it, an empty disc.
            y: -(captureModeMenu.count - 1 - captureModeMenu.currentIndex) * captureModeMenu.itemStep
            Behavior on y {
                id: captureModeBehavior

                YAnimator {
                    duration: 400
                    easing.type: Easing.OutQuad
                }
            }
        }
    }

    MouseArea {
        id: dragArea

        property real _lastPos
        property real _direction
        property int _extraDragMargin: overlay.isPortrait && grid.columns >= grid.count ? S.Screen.height / 4 - panel.height / 2 : 0

        anchors.fill: parent
        enabled: !overlay.inButtonLayout && showCommonControls
        drag {
            target: panel
            minimumY: -panel.height
            maximumY: _extraDragMargin
            axis: Drag.YAxis
            filterChildren: true
            onActiveChanged: {
                if (!drag.active) {
                    if (panel.y - _extraDragMargin < -(panel.height / 3) && _direction <= 0) {
                        overlay.topMenuOpen = false;
                    } else if (panel.y > (-panel.height * 2 / 3) && _direction >= 0) {
                        overlay.topMenuOpen = true;
                    }
                    expandBehavior.enabled = true;
                    panel.updateY();
                    expandBehavior.enabled = false;
                }
            }
        }

        onPressed: {
            _direction = 0;
            _lastPos = panel.y;
        }
        onPositionChanged: {
            var pos = panel.y;
            _direction = (_direction + pos - _lastPos) / 2;
            _lastPos = panel.y;
        }

        MouseArea {
            id: container

            property real pressX
            property real pressY

            function outOfBounds(mouseX, mouseY) {
                return mouseX < Theme.paddingLarge || mouseX > width - Theme.paddingLarge || mouseY < Theme.paddingLarge || mouseY > height - Theme.paddingLarge;
            }

            anchors.fill: parent
            opacity: Math.min(1 - overlay._progress, 1 - anchorContainer.opacity)
            enabled: !overlay._pinchActive && showCommonControls

            onPressed: {
                pressX = mouseX;
                pressY = mouseY;
            }

            onClicked: function (mouse) {
                if (overlay.topMenuOpen) {
                    overlay.topMenuOpen = false;
                }
                // don't react near display edges
                if (outOfBounds(mouseX, mouseY))
                    return;
                if (whiteBalanceMenu.expanded) {
                    whiteBalanceMenu.open = false;
                } else if (overlay.inButtonLayout) {
                    overlay.inButtonLayout = false;
                } else {
                    overlay.clicked(mouse);
                }
            }

            onPressAndHold: {
                // don't react near display edges
                if (outOfBounds(mouseX, mouseY))
                    return;
                if (!overlay.topMenuOpen) {
                    var dragDistance = Math.max(Math.abs(mouseX - pressX), Math.abs(mouseY - pressY));
                    if (dragDistance < Theme.startDragDistance) {
                        overlay.inButtonLayout = true;
                    }
                }
            }

            MouseArea {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: grid.anchors.horizontalCenterOffset
                width: grid.width
                height: Math.max(Theme.itemSizeLarge, topRow._topRowMargin + Theme.iconSizeMedium)
                enabled: !overlay._exposed && !overlay.inButtonLayout && showCommonControls

                onClicked: overlay.topMenuOpen = true

                onPressAndHold: function (mouse) {
                    container.pressAndHold(mouse);
                }
            }

            OverlayAnchor {
                id: overlayAnchorBL
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
            }
            OverlayAnchor {
                id: overlayAnchorBC
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                }
            }
            OverlayAnchor {
                id: overlayAnchorBR
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }
            }
            OverlayAnchor {
                id: overlayAnchorCL
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
            }
            OverlayAnchor {
                id: overlayAnchorCR
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
            }
            OverlayAnchor {
                id: overlayAnchorTL
                anchors {
                    left: parent.left
                    top: parent.top
                }
            }
            OverlayAnchor {
                id: overlayAnchorTR
                anchors {
                    right: parent.right
                    top: parent.top
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: overlay._exposed
            onClicked: overlay.topMenuOpen = false
        }

        Item {
            id: panel

            y: -panel.height

            function updateY() {
                if (!dragArea.drag.active) {
                    if (overlay.topMenuOpen) {
                        panel.y = dragArea._extraDragMargin;
                    } else {
                        panel.y = -panel.height;
                    }
                }
            }

            Connections {
                target: overlay
                function onIsPortraitChanged() {
                    panel.updateY();
                }
                function onTopMenuOpenChanged() {
                    expandBehavior.enabled = true;
                    panel.updateY();
                    expandBehavior.enabled = false;
                }
            }

            Behavior on y {
                id: expandBehavior

                enabled: false
                NumberAnimation {
                    id: verticalAnimation
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }

            width: overlay.width
            height: S.Screen.width / 2
        }

        Rectangle {
            anchors.fill: parent
            visible: overlay._exposed
            color: "black"
            opacity: Theme.opacityHigh * (1 - container.opacity)
        }

        Grid {
            id: grid

            property int count: {
                var c = 2; // timer, grid menu
                c = c + (colorFilterMenu.active ? 1 : 0);
                c = c + (flashMenu.active ? 1 : 0);
                c = c + (exposureModeMenu.active ? 1 : 0);
                c = c + (isoMenu.active ? 1 : 0);
                return c;
            }

            y: Math.round(height * panel.y / panel.height) + overlay._headerHeight + overlay._headerTopMargin
            height: Math.max(implicitHeight, S.Screen.height / 2)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: overlay.isPortrait ? 0 : ((-width / 2) - Theme.paddingLarge)

            opacity: 1 - container.opacity
            enabled: overlay._exposed
            visible: overlay._exposed

            columns: Math.min(count, Math.floor((parent.width + spacing - 2 * Theme.horizontalPageMargin) / (overlay._menuWidth + spacing)))
            // The spacing narrows so that all the menus fit on one row, under
            // the top row's icons (a second row would put the grid menu where
            // nothing points).
            spacing: Math.max(Theme.paddingSmall, Math.min(overlay._menuItemHorizontalSpacing, (parent.width - 2 * Theme.horizontalPageMargin - count * overlay._menuWidth) / Math.max(1, count - 1)))

            Item {
                id: colorFilterParentBegin

                width: colorFilterMenu.width
                height: colorFilterMenu.height
                visible: colorFilterMenu.parent === colorFilterParentBegin && colorFilterMenu.active
            }

            SettingsMenu {
                id: colorFilterMenu

                active: Settings.global.colorFiltersAllowed && colorFilter.supportedFilters.length > 1
                parent: grid.count > grid.columns ? colorFilterParentEnd : colorFilterParentBegin
                width: overlay._menuWidth
                title: Settings.colorFiltersEnabledText
                header: upperHeader
                model: [false, true]
                delegate: SettingsMenuItem {
                    settings: Settings.global
                    property: "colorFiltersEnabled"
                    value: modelData
                    icon: Settings.colorFiltersIcon(modelData)
                }
            }

            SettingsMenu {
                width: overlay._menuWidth
                title: Settings.timerText
                header: upperHeader
                model: [0, 3, 10, 15]
                // The delay as a number: the theme has no icon for each.
                delegate: SettingsMenuItemBase {
                    id: timerItem

                    readonly property color _color: pressed ? overlay._highlightColor : Theme.lightPrimaryColor

                    settings: Settings.mode
                    property: "timer"
                    value: modelData

                    Icon {
                        anchors.centerIn: parent
                        visible: timerItem.value === 0
                        color: timerItem._color
                        source: Settings.timerIcon(0)
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: timerItem.value > 0
                        color: timerItem._color
                        //: A timer delay in seconds, short
                        text: qsTr("%1 s").arg(timerItem.value)
                    }
                }
            }

            SettingsMenu {
                id: flashMenu

                active: model.length > 0
                width: overlay._menuWidth
                title: Settings.flashText
                header: upperHeader
                model: CameraConfigs.supportedFlashModes
                delegate: SettingsMenuItem {
                    settings: Settings.mode
                    property: "flash"
                    value: modelData
                    icon: Settings.flashIcon(modelData)
                }
            }

            SettingsMenu {
                id: exposureModeMenu

                active: model.length > 1
                width: overlay._menuWidth
                title: Settings.exposureModeText
                header: upperHeader
                model: CameraConfigs.supportedExposureModes
                delegate: SettingsMenuItem {
                    settings: Settings.mode
                    property: "exposureMode"
                    value: modelData
                    icon: Settings.exposureModeIcon(modelData)
                }
            }

            SettingsMenu {
                id: isoMenu

                active: model.length > 0
                width: overlay._menuWidth
                title: Settings.isoText
                header: upperHeader
                model: CameraConfigs.supportedIsoSensitivities
                delegate: SettingsMenuItemBase {
                    settings: Settings.mode
                    property: "iso"
                    value: modelData

                    IsoItem {
                        anchors.centerIn: parent
                        value: modelData
                    }
                }
            }

            SettingsMenu {
                // Grid menu
                width: overlay._menuWidth
                title: Settings.viewfinderGridText
                header: upperHeader
                model: Settings.viewfinderGridValues
                delegate: SettingsMenuItem {
                    settings: Settings.global
                    property: "viewfinderGrid"
                    value: modelData
                    icon: Settings.viewfinderGridIcon(modelData)
                }
            }

            Item {
                id: colorFilterParentEnd

                width: colorFilterMenu.width
                height: colorFilterMenu.height
                visible: colorFilterMenu.parent === colorFilterParentEnd
            }
        }

        HeaderLabel {
            id: upperHeader

            anchors {
                left: parent.left
                bottom: grid.top
                right: parent.right
            }
            height: overlay._headerHeight
            opacity: grid.opacity
        }
    }

    Row {
        id: topRow

        property real _topRowMargin: Math.max(overlay.topButtonRowHeight / 2 - overlay._menuWidth / 2, (S.Screen.hasCutouts && overlay.isPortrait) ? (S.Screen.topCutout.height + Theme.paddingSmall) : 0)

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: grid.anchors.horizontalCenterOffset
        spacing: grid.spacing
        opacity: _commonControlOpacity
        visible: opacity > 0.0

        function dragY(yValue) {
            return yValue != undefined ? Math.max(topRow._topRowMargin, grid.y + yValue) : topRow._topRowMargin;
        }

        Item {
            height: 1
            width: overlay._menuWidth
            visible: colorFilterMenu.parent === colorFilterParentBegin && colorFilterMenu.active
        }

        Item {
            width: overlay._menuWidth
            height: width
            visible: CameraConfigs.supportedFlashModes.length > 0
            y: flashMenu.currentItem != null ? topRow.dragY(flashMenu.currentItem.y) : 0

            Icon {
                anchors.centerIn: parent
                color: Theme.lightPrimaryColor
                source: Settings.flashIcon(Settings.mode.flash)
            }
        }

        Item {
            width: overlay._menuWidth
            height: width
            visible: CameraConfigs.supportedExposureModes.length > 1
            y: topRow.dragY(exposureModeMenu.currentItem ? exposureModeMenu.currentItem.y : 0)

            Icon {
                anchors.centerIn: parent
                color: Theme.lightPrimaryColor
                source: Settings.exposureModeIcon(Settings.mode.exposureMode)
            }
        }

        Item {
            width: overlay._menuWidth
            height: width
            y: topRow.dragY(isoMenu.currentItem ? isoMenu.currentItem.y : 0)
            visible: CameraConfigs.supportedIsoSensitivities.length > 1

            IsoItem {
                anchors.centerIn: parent
                value: isoMenu.currentItem ? isoMenu.currentItem.value : 0
            }
        }
    }

    Item {
        // have this appear somewhat late when dragging
        opacity: Math.max(0, (overlay._progress - 0.75)) * 4
        visible: overlay._exposed
        anchors.fill: parent
        anchors.leftMargin: page.orientation == Orientation.Landscape ? S.Screen.topCutout.height : 0
        anchors.rightMargin: page.orientation == Orientation.LandscapeInverted ? S.Screen.topCutout.height : 0

        CameraButton {
            background.visible: false
            enabled: !Settings.defaultSettings && parent.opacity > 0.0
            opacity: !Settings.defaultSettings ? 1.0 : 0.0
            Behavior on opacity {
                FadeAnimator {}
            }

            width: Theme.itemSizeMedium
            height: Theme.itemSizeMedium
            // At the bottom right, unless a switch is shown below it.
            anchors.bottom: overlay.isPortrait && highresSwitch.visible ? extraConfig.top : parent.bottom
            anchors.bottomMargin: overlay.isPortrait && highresSwitch.visible ? Theme.paddingLarge : 0
            x: overlay.isPortrait ? parent.width - width : Theme.horizontalPageMargin

            icon {
                opacity: pressed ? Theme.opacityLow : 1.0
                source: "image://theme/icon-camera-reset?" + (pressed ? _highlightColor : Theme.lightPrimaryColor)
            }

            onClicked: {
                upperHeader.pressedMenu = null;
                Settings.reset();
            }
        }

        Column {
            id: extraConfig

            width: overlay.isPortrait ? S.Screen.width : S.Screen.height / 2
            anchors.bottom: parent.bottom
            anchors.right: parent.right

            // to consider: the switch graphics shouldn't necessarily be here "light behind a transparent pattern"
            // since there is no app background. using the common components with the lack of alternatives
            IconTextSwitch {
                id: highresSwitch

                visible: CameraConfigs.supportedHighresImageResolutions.length > 0 && Settings.global.captureMode === "image"
                palette.colorScheme: Theme.LightOnDark
                icon.source: "image://theme/icon-m-imaging"
                text: qsTr("High resolution mode")
                automaticCheck: false
                checked: Settings.mode.enableHighres
                onClicked: Settings.mode.enableHighres = !Settings.mode.enableHighres
            }

            IconTextSwitch {
                // No QR recognition yet.
                visible: false
                palette.colorScheme: Theme.LightOnDark
                icon.source: "image://theme/icon-m-qr"
                text: qsTr("Enable QR-code recognition")
                automaticCheck: false
                checked: Settings.global.qrFilterEnabled
                onClicked: Settings.global.qrFilterEnabled = !Settings.global.qrFilterEnabled
            }

            // explicit padding item seems to work better than Column:bottomPadding.
            // if all the content is otherwise visible: false, the column height has some problems updating
            Item {
                width: 1
                height: Theme.itemSizeSmall
            }
        }
    }

    Column {
        x: exposureSlider.alignment == Qt.AlignLeft ? (isPortrait ? 0 : Theme.paddingLarge) : parent.width - width - (isPortrait ? 0 : Theme.paddingLarge)
        anchors {
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: isPortrait ? (reallyWideScreen ? -Theme.itemSizeSmall : Theme.paddingMedium) : 0
        }
        spacing: Theme.paddingSmall
        opacity: _commonControlOpacity
        visible: opacity > 0.0

        WhiteBalanceMenu {
            id: whiteBalanceMenu

            anchors {
                horizontalCenter: exposureSlider.horizontalCenter
                centerIn: null
            }
            enabled: !Settings.global.colorFiltersEnabled || camera.imageProcessing.colorFilter === CameraImageProcessing.ColorFilterNone

            alignment: exposureSlider.alignment
            opacity: enabled ? 1.0 - settingsOpacity : 0.0
            spacing: Theme.paddingMedium
        }

        ExposureSlider {
            id: exposureSlider

            visible: CameraConfigs.supportsExposureCompensation
            alignment: _overlayPosition.exposure
            enabled: !overlay.topMenuOpen && !overlay.inButtonLayout && !whiteBalanceMenu.open
            opacity: (1.0 - settingsOpacity) * (1.0 - whiteBalanceMenu.openProgress)
            // In landscape the column (white balance above the slider) stays
            // clear of the top button row, which shares its side.
            height: overlay.isPortrait ? Theme.itemSizeSmall * 5 : Math.max(Theme.itemSizeSmall * 2, Math.min(Theme.itemSizeSmall * 5, overlay.height - 2 * (overlay.topButtonRowHeight + Theme.paddingLarge) - whiteBalanceMenu.height - Theme.paddingSmall))
        }
    }

    Item {
        property int paddingVector: overlay.isPortrait ? -2 : _overlayPosition.exposure === Qt.AlignRight ? 2 : -2

        parent: _overlayPosition.exposure === Qt.AlignRight ? overlayAnchorBL : overlayAnchorBR
        anchors {
            centerIn: parent
            verticalCenterOffset: overlay.isPortrait ? overlayAnchorBL.width * paddingVector : 0
            horizontalCenterOffset: overlay.isPortrait ? 0 : overlayAnchorBL.height * paddingVector
        }

        // No QR recognition yet.
        opacity: 0.0
        visible: opacity != 0.0
        Behavior on opacity {
            FadeAnimation {}
        }

        CameraButton {
            icon.source: "image://theme/icon-camera-qr"
            background.visible: false
            anchors.centerIn: parent
            onClicked: {
                pageStack.push("QrPage.qml", {
                    text: ""
                });
            }
        }
    }

    ColorFilterView {
        id: colorFilter

        property bool ready: CameraConfigs.supportedColorFilters.length > 0 && Settings.global.colorFiltersEnabled && Settings.global.colorFiltersAllowed
        property var allowedFilters: [CameraImageProcessing.ColorFilterNone, CameraImageProcessing.ColorFilterGrayscale, CameraImageProcessing.ColorFilterSepia, CameraImageProcessing.ColorFilterPosterize, CameraImageProcessing.ColorFilterWhiteboard, CameraImageProcessing.ColorFilterBlackboard]
        property var supportedFilters: {
            var filters = [];
            var supportedFilters = CameraConfigs.supportedColorFilters;
            for (var i = 0; i < supportedFilters.length; i++) {
                var filter = supportedFilters[i];
                if (allowedFilters.indexOf(filter) >= 0) {
                    filters.push(filter);
                }
            }
            return filters;
        }

        model: ready ? supportedFilters : undefined
        anchors.bottom: parent.bottom
        orientationTransitionRunning: overlay.orientationTransitionRunning
        x: overlay.isPortrait ? 0 : exposureSlider.width + Theme.paddingMedium

        width: {
            if (overlay.isPortrait) {
                return S.Screen.width;
            } else {
                var leftControlWidth = x;
                var rightControlWidth = buttonAnchorCR.width + buttonAnchorCR.largeMargin;
                var resolution = camera.viewfinder.resolution.width;
                var viewfinderWidth = S.Screen.width * (resolution.width > 0 ? resolution.width / resolution.height : 1.2);
                return Math.min(S.Screen.height - rightControlWidth, viewfinderWidth) - leftControlWidth;
            }
        }

        height: overlay.isPortrait ? S.Screen.height / 11 : Theme.itemSizeMedium
        enabled: !overlay._exposed && Settings.global.colorFiltersEnabled

        onCurrentIndexChanged: update()
        onMovingChanged: update()

        function update() {
            if (!moving && !orientationTransitionRunning) {
                camera.imageProcessing.colorFilter = colorFilter.model[colorFilter.currentIndex];
            }
        }
    }

    OpacityRampEffect {
        offset: 1 - 1 / slope
        sourceItem: colorFilter
        slope: 1 + 20 * colorFilter.width / S.Screen.width
        visible: Settings.global.colorFiltersEnabled

        direction: OpacityRamp.BothSides
        opacity: (1.0 - settingsOpacity) * _commonControlOpacity
    }

    Item {
        id: anchorContainer

        anchors.fill: parent
        visible: overlay.inButtonLayout || layoutAnimation.running
        opacity: overlay.inButtonLayout ? 1.0 : 0.0
        Behavior on opacity {
            FadeAnimation {
                id: layoutAnimation
            }
        }

        Rectangle {
            anchors.fill: parent
            opacity: Theme.opacityOverlay
            color: "black"
        }

        Label {
            anchors {
                centerIn: parent
                verticalCenterOffset: -Theme.paddingLarge
            }
            width: overlay.isPortrait ? S.Screen.width - (2 * Theme.itemSizeExtraLarge) : S.Screen.width - Theme.itemSizeExtraLarge
            font.pixelSize: Theme.fontSizeExtraLarge
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.AutoText
            color: _highlightColor

            text: overlay.isPortrait ? qsTr("Select location for the portrait capture key") : qsTr("Select location for the landscape capture key")
        }
    }
}
