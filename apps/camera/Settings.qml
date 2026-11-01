// SPDX-FileCopyrightText: 2014 - 2022 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

pragma Singleton
import QtQuick 2.0
import Nemo.Configuration 1.0
import MarathonApp.Camera 1.0

SettingsBase {
    // DeclarativeSettings::StoragePathStatus of the Jolla Camera, for
    // Settings.storagePathStatus (always NotSet: no memory card support).
    enum StoragePathStatus {
        NotSet,
        Unavailable,
        Mounting,
        Available
    }

    property alias mode: modeSettings
    property alias global: globalSettings
    // Camera change goes here, CaptureView updates to global.deviceId
    property string deviceId: global.deviceId

    // A mode with no stored ratio: 4:3 for photos, 16:9 for video. The
    // group's Component.onCompleted below stores one only for the mode open
    // at start, so video used to get the photo's 4:3 viewfinder and record
    // a 16:9 frame that was not the one shown.
    readonly property int aspectRatio: mode.aspectRatio !== -1 ? mode.aspectRatio : (global.captureMode === "image" ? CameraConfigs.AspectRatio_4_3 : CameraConfigs.AspectRatio_16_9)
    property var viewfinderGridValues: ["none", "thirds"]

    readonly property var settingsDefaults: ({
            "iso": 0,
            "timer": 0,
            "viewfinderGrid": "none",
            "exposureMode": Camera.ExposureManual,
            "flash": ((globalSettings.captureMode == "image") && (globalSettings.position === Camera.BackFace) ? Camera.FlashAuto : Camera.FlashOff)
        })

    readonly property bool defaultSettings: modeSettings.iso === settingsDefaults["iso"] && modeSettings.timer === settingsDefaults["timer"] && modeSettings.viewfinderGrid === settingsDefaults["viewfinderGrid"] && modeSettings.exposureMode === settingsDefaults["exposureMode"] && modeSettings.flash == settingsDefaults["flash"]

    function reset() {
        var basePath = globalSettings.path + "/" + modeSettings.path;
        var i;
        for (i in settingsDefaults) {
            _singleValue.key = basePath + "/" + i;
            _singleValue.value = settingsDefaults[i];
        }
    }

    property ConfigurationValue _singleValue: ConfigurationValue {}

    // The labels of the back camera switcher, one per back camera in
    // `cameras` (the backend's devices, in order): /apps/camera/
    // backCameraLabels if set, else each camera's magnification from its
    // field of view (zoomLabel). Empty if none fits.
    function backCameraLabels(cameras) {
        var count = cameras ? cameras.length : 0;
        var own = globalSettings.backCameraLabels;
        if (own && own.length >= count && count > 0)
            return own;
        var derived = [];
        for (var i = 0; i < count; i++) {
            if (!cameras[i].zoomLabel)
                return [];
            derived.push(cameras[i].zoomLabel);
        }
        return derived;
    }

    property ConfigurationGroup _global: ConfigurationGroup {
        id: globalSettings

        path: "/apps/camera"

        // Note! don't touch this for changing between cameras, see cameraDevice on root
        property string deviceId
        property string previousBackFacingDeviceId
        property string frontFacingDeviceId
        property int position: Camera.BackFace
        property string captureMode: "image"

        // Labels for several back cameras, e.g. normal, macro and wide angle
        // ["1.0", "2.0", "0.6"] (backCameraLabels() above).
        property var backCameraLabels: []

        property int portraitCaptureButtonLocation: 3
        property int landscapeCaptureButtonLocation: 5

        property string audioCodec: "audio/mpeg, mpegversion=(int)4"
        property int audioSampleRate: 48000
        property string videoCodec: "video/x-h264"
        property string mediaContainer: "video/quicktime, variant=(string)iso"

        property int videoEncodingMode: CameraRecorder.AverageBitRateEncoding
        property int videoBitRate: 12000000

        property bool saveLocationInfo

        property bool qrFilterEnabled: true
        property bool colorFiltersEnabled: false
        property bool colorFiltersAllowed: true

        property int exposureCompensation: 0
        property int whiteBalance: CameraImageProcessing.WhiteBalanceAuto

        property var exposureCompensationValues: [4, 3, 2, 1, 0, -1, -2, -3, -4]
        property string viewfinderGrid: "none"

        ConfigurationGroup {
            id: modeSettings

            path: {
                var position = globalSettings.position === Camera.FrontFace ? "front" : "back";
                return position + "/" + globalSettings.captureMode;
            }

            property int iso: 0
            property int flash: Camera.FlashOff
            property int exposureMode: Camera.ExposureManual
            property int meteringMode: Camera.MeteringMatrix
            property int timer: 0
            property int aspectRatio: -1
            property bool enableHighres

            // A switch of camera or capture mode reads the new mode's
            // stored values, and a key it has not stored kept the last
            // mode's value. Each key the mode has not stored takes its
            // default.
            function _useDefaults() {
                var defaults = {
                    "iso": 0,
                    // Off, as declared (and as it has always started), not
                    // the reset's auto.
                    "flash": Camera.FlashOff,
                    "exposureMode": Camera.ExposureManual,
                    "meteringMode": Camera.MeteringMatrix,
                    "timer": 0,
                    "aspectRatio": globalSettings.captureMode === "image" ? CameraConfigs.AspectRatio_4_3 : CameraConfigs.AspectRatio_16_9,
                    "enableHighres": false
                };
                for (var key in defaults) {
                    var stored = modeSettings.value(key, defaults[key]);
                    if (modeSettings[key] != stored)
                        modeSettings[key] = stored;
                }
            }

            Component.onCompleted: _useDefaults()
        }

        // The mode's path follows these: once the group has read the new
        // path's values.
        Connections {
            target: globalSettings
            function onCaptureModeChanged() {
                Qt.callLater(modeSettings._useDefaults);
            }
            function onPositionChanged() {
                Qt.callLater(modeSettings._useDefaults);
            }
        }
    }

    function captureModeIcon(mode) {
        switch (mode) {
        case "image":
            return "image://theme/icon-camera-camera-mode";
        case "video":
            return "image://theme/icon-camera-video";
        default:
            return "";
        }
    }

    function exposureText(exposure) {
        switch (exposure) {
        case -4:
            return "-2";
        case -3:
            return "-1.5";
        case -2:
            return "-1";
        case -1:
            return "-0.5";
        case 0:
            return "";
        case 1:
            return "+0.5";
        case 2:
            return "+1";
        case 3:
            return "+1.5";
        case 4:
            return "+2";
        }
    }

    function timerIcon(timer) {
        return timer > 0 ? "image://theme/icon-camera-timer-" + timer + "s" : "image://theme/icon-camera-timer";
    }

    function timerText(timer) {
        return timer > 0 ? qsTr("%1 second delay").arg(timer) : qsTr("No delay");
    }

    function colorFiltersIcon(enabled) {
        return "image://theme/icon-camera-filter-" + (enabled ? "on" : "off");
    }

    function colorFiltersEnabledText(enabled) {
        return enabled ? qsTr("Color filters on") : qsTr("Color filters off");
    }

    function isoText(iso) {
        if (iso == 0) {
            return qsTr("Light sensitivity • Automatic");
        } else {
            //: %1 replaced with iso value
            return qsTr("Light sensitivity • ISO %1").arg(iso);
        }
    }

    function meteringModeIcon(mode) {
        switch (mode) {
        case Camera.MeteringMatrix:
            return "image://theme/icon-camera-metering-matrix";
        case Camera.MeteringAverage:
            return "image://theme/icon-camera-metering-weighted";
        case Camera.MeteringSpot:
            return "image://theme/icon-camera-metering-spot";
        }
    }

    function exposureModeIcon(exposureMode) {
        switch (exposureMode) {
        case Camera.ExposureManual:
            return "image://theme/icon-camera-mode-automatic";
        case Camera.ExposurePortrait:
            return "image://theme/icon-camera-mode-portrait";
        case Camera.ExposureNight:
            return "image://theme/icon-camera-mode-night";
        case Camera.ExposureSports:
            return "image://theme/icon-camera-mode-sports";
        case Camera.ExposureHDR:
            return "image://theme/icon-camera-mode-hdr";
        default:
            return ""; // not supported
        }
    }

    function exposureModeText(exposureMode) {
        switch (exposureMode) {
        //: "Automatic exposure mode"
        case Camera.ExposureManual:
            return qsTr("Automatic exposure");
        //: "Portrait exposure mode"
        case Camera.ExposurePortrait:
            return qsTr("Portrait exposure");
        //: "Night exposure mode"
        case Camera.ExposureNight:
            return qsTr("Night exposure");
        //: "Sports exposure mode"
        case Camera.ExposureSports:
            return qsTr("Sports exposure");
        //: "HDR exposure mode"
        case Camera.ExposureHDR:
            return qsTr("HDR exposure");
        default:
            return ""; // not supported
        }
    }

    function flashIcon(flash) {
        switch (flash) {
        case Camera.FlashAuto:
            return "image://theme/icon-camera-flash-automatic";
        case Camera.FlashOff:
            return "image://theme/icon-camera-flash-off";
        case Camera.FlashTorch:
        case Camera.FlashOn:
            return "image://theme/icon-camera-flash-on";
        // JB#54201: Red-eye mode does not work
        // case Camera.FlashRedEyeReduction:   return "image://theme/icon-camera-flash-redeye"
        default:
            return ""; // not supported
        }
    }

    function flashText(flash) {
        switch (flash) {
        //: "Automatic camera flash mode"
        case Camera.FlashAuto:
            return qsTr("Flash automatic");
        //: "Camera flash disabled"
        case Camera.FlashOff:
            return qsTr("Flash disabled");
        //: "Camera flash enabled"
        case Camera.FlashOn:
            return qsTr("Flash enabled");
        //: "Camera flash in torch mode"
        case Camera.FlashTorch:
            return qsTr("Flash on");
        //: "Camera flash with red eye reduction"
        case Camera.FlashRedEyeReduction:
            return qsTr("Flash red eye");
        default:
            return ""; // not supported
        }
    }

    function whiteBalanceIcon(balance) {
        switch (balance) {
        case CameraImageProcessing.WhiteBalanceAuto:
            return "image://theme/icon-camera-wb-automatic";
        case CameraImageProcessing.WhiteBalanceSunlight:
            return "image://theme/icon-camera-wb-sunny";
        case CameraImageProcessing.WhiteBalanceCloudy:
            return "image://theme/icon-camera-wb-cloudy";
        // case CameraImageProcessing.WhiteBalanceShade:       return "image://theme/icon-camera-wb-shade"
        // case CameraImageProcessing.WhiteBalanceSunset:      return "image://theme/icon-camera-wb-sunset"
        case CameraImageProcessing.WhiteBalanceFluorescent:
            return "image://theme/icon-camera-wb-fluorecent";
        case CameraImageProcessing.WhiteBalanceTungsten:
            return "image://theme/icon-camera-wb-tungsten";
        default:
            return ""; // not supported
        }
    }

    function whiteBalanceText(balance) {
        switch (balance) {
        //: "Automatic white balance"
        case CameraImageProcessing.WhiteBalanceAuto:
            return qsTr("Automatic");
        //: "Sunny white balance"
        case CameraImageProcessing.WhiteBalanceSunlight:
            return qsTr("Sunny");
        //: "Cloudy white balance"
        case CameraImageProcessing.WhiteBalanceCloudy:
            return qsTr("Cloudy");
        //: "Shade white balance"
        case CameraImageProcessing.WhiteBalanceShade:
            return qsTr("Shade");
        //: "Sunset white balance"
        case CameraImageProcessing.WhiteBalanceSunset:
            return qsTr("Sunset");
        //: "Fluorecent white balance"
        case CameraImageProcessing.WhiteBalanceFluorescent:
            return qsTr("Fluorecent");
        //: "Tungsten white balance"
        case CameraImageProcessing.WhiteBalanceTungsten:
            return qsTr("Tungsten");
        default:
            return ""; // not supported
        }
    }

    function colorFilterText(filter) {
        switch (filter) {
        case CameraImageProcessing.ColorFilterNone:
            return qsTr("Normal");
        case CameraImageProcessing.ColorFilterGrayscale:
            return qsTr("Grayscale");
        case CameraImageProcessing.ColorFilterNegative:
            return qsTr("Negative");
        case CameraImageProcessing.ColorFilterSolarize:
            return qsTr("Solarize");
        case CameraImageProcessing.ColorFilterSepia:
            return qsTr("Sepia");
        case CameraImageProcessing.ColorFilterPosterize:
            return qsTr("Posterize");
        case CameraImageProcessing.ColorFilterWhiteboard:
            return qsTr("Whiteboard");
        case CameraImageProcessing.ColorFilterBlackboard:
            return qsTr("Blackboard");
        case CameraImageProcessing.ColorFilterAqua:
            return qsTr("Aqua");
        default:
            return ""; // not supported
        }
    }

    function viewfinderGridIcon(grid) {
        switch (grid) {
        case "none":
            return "image://theme/icon-camera-grid-none";
        case "thirds":
            return "image://theme/icon-camera-grid-thirds";
        default:
            return "";
        }
    }

    function viewfinderGridText(grid) {
        switch (grid) {
        case "none":
            return qsTr("No grid");
        case "thirds":
            return qsTr("Thirds grid");
        default:
            return "";
        }
    }
}
