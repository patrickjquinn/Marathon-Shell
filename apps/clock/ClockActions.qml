import QtQuick
import Keel.Actions 1.0
import "ClockLogic.js" as Logic

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml ClockActions.qml --app-id org.marathonos.clock \
//       --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: alarms, saveAlarm(), toggleAlarm(), setTimer() and countdown.
    property var app

    KeelAction {
        name: "alarms.list"
        title: qsTr("List alarms")
        description: "The alarms in Marathon Clock, each with its id, time (local, 24-hour HH:MM), label, the weekdays it repeats on (0 is Sunday, 6 Saturday; none means it rings once) and whether it is on."
        readOnly: true
        idempotent: true
        returns: KeelResult {
            type: "array"
            itemType: "object"
            KeelParam {
                name: "id"
                type: "string"
                maxLength: 64
                required: true
            }
            KeelParam {
                name: "time"
                type: "string"
                maxLength: 5
                required: true
            }
            KeelParam {
                name: "label"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "repeat"
                type: "array"
                itemType: "integer"
                minimum: 0
                maximum: 6
                maxItems: 7
                required: true
            }
            KeelParam {
                name: "enabled"
                type: "boolean"
                required: true
            }
        }
        onInvoked: (args, call) => call.reply(root.app.alarms.slice(0, 100).map(a => ({
                        id: String(a.id),
                        time: String(a.time),
                        label: String(a.label || "").substring(0, 200),
                        repeat: a.repeat || [],
                        enabled: !!a.enabled
                    })))
    }

    KeelAction {
        name: "alarms.create"
        title: qsTr("Create alarm")
        description: "Set an alarm in Marathon Clock at a local time, 24-hour HH:MM. It repeats on the given weekdays (0 is Sunday, 6 Saturday) or, without any, rings once at the next such time. Returns the new alarm's id."
        idempotent: false
        parameters: [
            KeelParam {
                name: "time"
                type: "string"
                required: true
                pattern: "^([01]\\d|2[0-3]):[0-5]\\d$"
                maxLength: 5
                description: "Time, HH:MM"
            },
            KeelParam {
                name: "label"
                type: "string"
                maxLength: 200
            },
            KeelParam {
                name: "repeat"
                type: "array"
                itemType: "integer"
                minimum: 0
                maximum: 6
                maxItems: 7
                description: "Weekdays it repeats on"
            }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam {
                name: "id"
                type: "string"
                maxLength: 64
                required: true
            }
        }
        onInvoked: (args, call) => {
            const t = Logic.parseTime(args.time);
            const days = [...new Set(args.repeat || [])].sort();
            const id = root.app.saveAlarm("", t.hour, t.minute, String(args.label || "").trim(), days);
            if (id === "")
                call.fail("Failed", "The alarm could not be saved");
            else
                call.reply({
                    id: id
                });
        }
    }

    KeelAction {
        name: "alarms.switch"
        title: qsTr("Turn alarm on or off")
        description: "Turn one of Marathon Clock's alarms on or off, by the id alarms.list gives. An alarm that is off keeps its time and does not ring."
        idempotent: true
        parameters: [
            KeelParam {
                name: "id"
                type: "string"
                required: true
                maxLength: 64
            },
            KeelParam {
                name: "enabled"
                type: "boolean"
                required: true
            }
        ]
        onInvoked: (args, call) => {
            const alarm = root.app.alarms.find(a => a.id === args.id);
            if (!alarm)
                call.fail("InvalidArguments", "There is no alarm with that id");
            else if (!!alarm.enabled !== args.enabled && !root.app.toggleAlarm(args.id))
                call.fail("Failed", "The alarm could not be changed");
        }
    }

    KeelAction {
        name: "timer.start"
        title: qsTr("Start timer")
        description: "Start Marathon Clock's countdown timer for a number of seconds (up to 23:59:59); it rings when it ends, even if Clock is closed. There is one timer: this fails while it is running. Returns when it ends."
        idempotent: false
        parameters: [
            KeelParam {
                name: "seconds"
                type: "integer"
                required: true
                minimum: 1
                maximum: 86399
            }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam {
                name: "endsAt"
                type: "string"
                format: "date-time"
                maxLength: 32
                required: true
            }
        }
        onInvoked: (args, call) => {
            if (root.app.countdown.running) {
                call.fail("Failed", "A timer is already running");
                return;
            }
            root.app.setTimer(args.seconds);
            root.app.countdown.start();
            call.reply({
                endsAt: new Date(root.app.countdown.endsAt).toISOString()
            });
        }
    }
}
