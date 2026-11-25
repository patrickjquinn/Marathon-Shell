import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

// Adding a fingerprint: each touch on the sensor, the ridges the touches
// have covered so far, and what to do next. Leaving stops the enrolment.
Page {
    id: page

    property string finger: ""
    property string pin: ""
    // "scanning", "done" or "failed".
    property string phase: "scanning"
    property string result: ""
    property int passed: 0
    property int stages: Security.fingerprintStages
    property string failure: ""
    property bool started: false
    readonly property var guidance: Logic.enrollGuidance(result, passed, stages, Security.fingerprintScanType)

    function retry() {
        pageStack.replace(Qt.resolvedUrl("AddFingerprintDialog.qml"), {
            finger: page.finger,
            error: page.failure
        });
    }

    onStatusChanged: {
        if (status === PageStatus.Active && !started) {
            started = true;
            Security.enrollFingerprint(finger, pin);
        } else if (status === PageStatus.Deactivating && phase === "scanning") {
            Security.cancelFingerprintEnroll();
        }
    }

    Connections {
        target: Security

        function onFingerprintEnrollStatus(result, passed, stages) {
            page.result = result;
            page.passed = passed;
            if (stages > 0)
                page.stages = stages;
            if (result === "enroll-stage-passed")
                Haptics.light();
            else if (page.guidance.retry)
                Haptics.medium();
        }
        function onFingerprintEnrolled(finger) {
            if (finger !== page.finger)
                return;
            page.phase = "done";
            Haptics.medium();
        }
        function onFingerprintFailed(reason) {
            if (page.phase !== "scanning")
                return;
            page.phase = "failed";
            page.failure = reason;
            Haptics.heavy();
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + button.height + 2 * Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: Logic.fingerName(page.finger)
                description: qsTr("Add fingerprint")
            }
            FingerprintCoverage {
                objectName: "coverage"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(page.width * 0.56, page.height * 0.3)
                height: width * 1.2
                coverage: page.phase === "done" ? 1 : page.passed / Math.max(1, page.stages)
                litColor: page.phase === "failed" ? Theme.errorColor : Theme.highlightColor
                animated: !Settings.reduceMotion
            }
            Label {
                objectName: "enrollTitle"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: page.phase === "failed" ? Theme.errorColor : Theme.highlightColor
                text: page.phase === "done" ? qsTr("Fingerprint added") : page.phase === "failed" ? qsTr("Couldn't add it") : page.guidance.title
            }
            Label {
                objectName: "enrollDetail"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: page.phase === "done" ? qsTr("Touch the sensor to unlock your phone. Your PIN is still asked for after a restart.") : page.phase === "failed" ? page.failure : page.guidance.detail
            }
            Label {
                objectName: "enrollStep"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.phase === "scanning" && page.stages > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                //: Touches taken so far, of those an enrolment needs
                text: qsTr("%1 of %2").arg(page.passed).arg(page.stages)
            }
        }

        Button {
            id: button

            objectName: "enrollButton"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(column.height + Theme.paddingLarge, page.height - height - 2 * Theme.paddingLarge)
            text: page.phase === "done" ? qsTr("Done") : page.phase === "failed" ? qsTr("Try again") : qsTr("Cancel")
            onClicked: {
                if (page.phase === "failed")
                    page.retry();
                else
                    pageStack.pop();
            }
        }
    }
}
