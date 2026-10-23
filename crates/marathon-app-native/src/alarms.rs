//! `Alarms`: the shell's Alarm1, the alarm clock.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::OwnedValue;

use crate::shell::{answers, relay, Service};
use crate::variant;
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        type QList_i32 = cxx_qt_lib::QList<i32>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, alarms, READ, NOTIFY)]
        #[qproperty(QList_QVariant, active_alarms, cxx_name = "activeAlarms", READ, NOTIFY)]
        type Alarms = super::AlarmsRust;

        #[qsignal]
        #[cxx_name = "alarmTriggered"]
        fn alarm_triggered(self: Pin<&mut Self>, id: &QString, label: &QString);
        #[qsignal]
        #[cxx_name = "alarmDismissed"]
        fn alarm_dismissed(self: Pin<&mut Self>, id: &QString);
        #[qsignal]
        #[cxx_name = "alarmSnoozed"]
        fn alarm_snoozed(self: Pin<&mut Self>, id: &QString, minutes: i32);

        #[qinvokable]
        #[cxx_name = "createAlarm"]
        fn create_alarm(
            self: &Alarms,
            time: &QString,
            label: &QString,
            repeat: &QList_i32,
            options: &QMap_QString_QVariant,
        ) -> QString;
        #[qinvokable]
        #[cxx_name = "updateAlarm"]
        fn update_alarm(self: &Alarms, id: &QString, updates: &QMap_QString_QVariant) -> bool;
        #[qinvokable]
        #[cxx_name = "deleteAlarm"]
        fn delete_alarm(self: &Alarms, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "enableAlarm"]
        fn enable_alarm(self: &Alarms, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "disableAlarm"]
        fn disable_alarm(self: &Alarms, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "snoozeAlarm"]
        fn snooze_alarm(self: &Alarms, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "dismissAlarm"]
        fn dismiss_alarm(self: &Alarms, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "stopAll"]
        fn stop_all(self: &Alarms);
        #[qinvokable]
        #[cxx_name = "triggerAlarmNow"]
        fn trigger_alarm_now(self: &Alarms, label: &QString);
    }

    impl cxx_qt::Threading for Alarms {}
    impl cxx_qt::Initialize for Alarms {}
}

use qobject::Alarms;

const ALARM: Service = Service::shell("Alarm");

#[derive(Default)]
pub struct AlarmsRust {
    alarms: QList<QVariant>,
    active_alarms: QList<QVariant>,
}

type Qt = cxx_qt::CxxQtThread<Alarms>;

enum Event {
    Alarms,
    Active,
    Granted,
}

impl cxx_qt::Initialize for Alarms {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(
            qt.clone(),
            ALARM,
            "AlarmTriggered",
            |obj, (id, label): (String, String)| {
                obj.alarm_triggered(&QString::from(&id), &QString::from(&label));
            },
        );
        relay(
            qt.clone(),
            ALARM,
            "AlarmDismissed",
            |obj, (id,): (String,)| obj.alarm_dismissed(&QString::from(&id)),
        );
        relay(
            qt.clone(),
            ALARM,
            "AlarmSnoozed",
            |obj, (id, minutes): (String, i32)| {
                obj.alarm_snoozed(&QString::from(&id), minutes);
            },
        );
        io::spawn(async move {
            read(&qt, true).await;
            read(&qt, false).await;
            let (Ok(alarms), Ok(active), Ok(grants)) = (
                ALARM.signals::<()>("AlarmsChanged").await,
                ALARM.signals::<()>("ActiveAlarmsChanged").await,
                answers("PermissionGranted", "alarms").await,
            ) else {
                return;
            };
            let events = alarms
                .map(|()| Event::Alarms)
                .or(active.map(|()| Event::Active))
                .or(grants.map(|()| Event::Granted));
            let mut events = std::pin::pin!(events);
            while let Some(event) = events.next().await {
                match event {
                    Event::Alarms => read(&qt, true).await,
                    Event::Active => read(&qt, false).await,
                    Event::Granted => {
                        read(&qt, true).await;
                        read(&qt, false).await;
                    }
                }
            }
        });
    }
}

/// `GetAlarms`, or with `all` false `GetActiveAlarms`.
async fn read(qt: &Qt, all: bool) {
    let method = if all { "GetAlarms" } else { "GetActiveAlarms" };
    if let Ok(list) = ALARM.ask::<_, Vec<OwnedValue>>(method, &()).await {
        qt.queue(move |mut obj| {
            let list = variant::qlist(&list);
            if all {
                obj.as_mut().rust_mut().alarms = list;
                obj.alarms_changed();
            } else {
                obj.as_mut().rust_mut().active_alarms = list;
                obj.active_alarms_changed();
            }
        })
        .ok();
    }
}

impl Alarms {
    crate::shell::calls! { ALARM;
        stop_all() => "StopAll";
        trigger_alarm_now(label: &QString) => "TriggerAlarmNow";
    }
    crate::shell::asks! { ALARM;
        update_alarm(id: &QString, updates: &QMap<QMapPair_QString_QVariant>) -> bool => "UpdateAlarm";
        delete_alarm(id: &QString) -> bool => "DeleteAlarm";
        enable_alarm(id: &QString) -> bool => "EnableAlarm";
        disable_alarm(id: &QString) -> bool => "DisableAlarm";
        snooze_alarm(id: &QString) -> bool => "SnoozeAlarm";
        dismiss_alarm(id: &QString) -> bool => "DismissAlarm";
    }
    fn create_alarm(
        &self,
        time: &QString,
        label: &QString,
        repeat: &QList<i32>,
        options: &QMap<QMapPair_QString_QVariant>,
    ) -> QString {
        let repeat: Vec<i32> = repeat.iter().copied().collect();
        let body = (
            time.to_string(),
            label.to_string(),
            repeat,
            variant::map(options),
        );
        ALARM
            .ask_now::<_, String>("CreateAlarm", &body)
            .map(|id| QString::from(&id))
            .unwrap_or_default()
    }
}
